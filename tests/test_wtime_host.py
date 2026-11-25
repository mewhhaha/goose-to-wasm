#!/usr/bin/env python3
"""Tests for --library --reachable-program direct Wasm emission and the goose-wtime Rust host."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMPILER = Path(os.environ.get("GOOSE_COMPILER", ROOT / "build/bin/goosew"))
STDLIB = ROOT / "stdlib"
WTIME_HOST = ROOT / "host/wtime/target/release/goose-wtime"
RUST_HOST = ROOT / "host/rust/target/release/goose-wasmtime"


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class LibraryReachableWasmTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)

    def test_library_reachable_program_skips_unreachable_and_exports_entry(self):
        src = self.work / "lib_entry.goose"
        src.write_text(
            "fn unreachable_helper() -> i64 {\n"
            "    return 999;\n"
            "}\n"
            "\n"
            "fn compute(n: i64) -> i64 {\n"
            "    var s: i64 = 0;\n"
            "    for i in 1..(n + 1) { s += i * i; }\n"
            "    return s;\n"
            "}\n"
            "\n"
            'export "entry_main" fn entry_main() -> i32 {\n'
            "    print(compute(5));\n"
            "    return 0;\n"
            "}\n"
        )
        out32 = self.work / "lib32.wasm"
        out64 = self.work / "lib64.wasm"
        for out, extra in [(out32, []), (out64, ["--wasm-memory64"])]:
            res = subprocess.run(
                [
                    str(COMPILER), str(src),
                    "--stdlib", str(STDLIB),
                    "--target", "wasm-direct",
                    "--library", "--reachable-program",
                    "-O2", "-o", str(out), *extra,
                ],
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
            )
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertTrue(out.is_file() and out.stat().st_size > 0)

        if WTIME_HOST.is_file():
            for out in (out32, out64):
                timing = self.work / f"{out.stem}.timing.json"
                run = subprocess.run(
                    [
                        str(WTIME_HOST), str(out),
                        "--entry", "entry_main",
                        "--timing-json", str(timing),
                    ],
                    stdin=subprocess.DEVNULL,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(run.returncode, 0, run.stderr)
                self.assertEqual(run.stdout.strip(), "55")
                meta = json.loads(timing.read_text())
                self.assertEqual(meta["engine"], "wtime")
                self.assertGreater(meta["compile_ns"], 0)
                self.assertGreater(meta["run_ns"], 0)


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
@unittest.skipUnless(WTIME_HOST.is_file(), "build host/wtime first")
class WtimeHostExecutionTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)

    def _compile(self, code: str, *, memory64: bool = False, library: bool = False) -> Path:
        src = self.work / ("mod64.goose" if memory64 else "mod32.goose")
        out = self.work / ("mod64.wasm" if memory64 else "mod32.wasm")
        src.write_text(code)
        cmd = [
            str(COMPILER), str(src),
            "--stdlib", str(STDLIB),
            "--target", "wasm-direct",
            "-O2", "-o", str(out),
        ]
        if memory64:
            cmd.append("--wasm-memory64")
        if library:
            cmd.extend(["--library", "--reachable-program"])
        res = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stderr)
        return out

    def test_wasm32_and_wasm64_all_execution_policies(self):
        code = (
            "fn main() {\n"
            "    var xs: i64[>..] = [];\n"
            "    for i in 1..9 { xs.push(i * i); }\n"
            "    var sum: i64 = 0;\n"
            "    for x in xs { sum += x; }\n"
            "    print(sum);\n"
            "}\n"
        )
        for memory64 in (False, True):
            wasm = self._compile(code, memory64=memory64)
            for policy in ("decoded", "compact", "register"):
                run = subprocess.run(
                    [str(WTIME_HOST), str(wasm), "--execution", policy],
                    stdin=subprocess.DEVNULL,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(run.returncode, 0, f"memory64={memory64} policy={policy}: {run.stderr}")
                self.assertEqual(run.stdout.strip(), "204")

    def test_blot_extern_args_and_fs_roundtrip(self):
        payload_file = self.work / "probe.txt"
        code = (
            'extern fn argument_count() -> i64 = "blot_argument_count";\n'
            'extern fn argument_size(index: i64) -> i64 = "blot_argument_size";\n'
            'extern fn argument_copy(index: i64, out: u8&, capacity: u64) -> i64 = "blot_argument_copy";\n'
            'extern fn copy_u8(dst: u8&, src: const u8&, count: u64) = "blot_copy_u8";\n'
            'extern fn copy_u32(dst: u32&, src: const u8&, count: u64) = "blot_copy_u32";\n'
            'extern fn open_write(path: const u8&, exclusive: bool) -> i32 = "blot_open_write";\n'
            'extern fn write_fd(fd: i32, first: const u8&, count: u64) -> i64 = "blot_write";\n'
            'extern fn close_fd(fd: i32) -> i32 = "blot_close";\n'
            'extern fn open_read(path: const u8&) -> i32 = "blot_open_read";\n'
            'extern fn read_fd(fd: i32, out: u8&, count: u64) -> i64 = "blot_read";\n'
            '\n'
            'export "probe_main" fn probe_main() -> i32 {\n'
            '    let argc = argument_count();\n'
            '    if argc < 2 { return 2; }\n'
            '    let n = argument_size(1);\n'
            '    var path: u8[>..] = [];\n'
            '    path.resize(n + 1, 0);\n'
            '    let copied = argument_copy(1, path[0], n as u64);\n'
            '    if copied != n { return 3; }\n'
            '    let wfd = open_write(path[0], false);\n'
            '    if wfd < 0 { return 4; }\n'
            '    let msg: u8[>..] = "hello-wtime";\n'
            '    var dup: u8[>..] = [];\n'
            '    dup.resize(msg.len, 0);\n'
            '    copy_u8(dup[0], msg[0], msg.len as u64);\n'
            '    var raw_u32: u8[4] = [0x78, 0x56, 0x34, 0x12];\n'
            '    var out_u32: u32[1] = [0];\n'
            '    copy_u32(out_u32[0], raw_u32[0], 1);\n'
            '    if out_u32[0] != 0x12345678 { return 9; }\n'
            '    if write_fd(wfd, dup[0], dup.len as u64) != dup.len { return 5; }\n'
            '    if close_fd(wfd) != 0 { return 6; }\n'
            '    let rfd = open_read(path[0]);\n'
            '    if rfd < 0 { return 7; }\n'
            '    var buf: u8[>..] = [];\n'
            '    buf.resize(msg.len, 0);\n'
            '    let got = read_fd(rfd, buf[0], msg.len as u64);\n'
            '    let _ = close_fd(rfd);\n'
            '    if got != msg.len { return 8; }\n'
            '    print(buf);\n'
            '    return 0;\n'
            '}\n'
        )
        wasm = self._compile(code, memory64=True, library=True)
        run = subprocess.run(
            [str(WTIME_HOST), str(wasm), "--entry", "probe_main", "--", str(payload_file)],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.strip(), "hello-wtime")
        self.assertEqual(payload_file.read_text(), "hello-wtime")

        if RUST_HOST.is_file():
            payload_wt = self.work / "probe-wasmtime.txt"
            cache = self.work / "probe.cwasm"
            for attempt in range(2):
                run_wt = subprocess.run(
                    [str(RUST_HOST), str(wasm), "--entry", "probe_main", "--cache", str(cache), "--", str(payload_wt)],
                    stdin=subprocess.DEVNULL,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(run_wt.returncode, 0, f"attempt={attempt}: {run_wt.stderr}")
                self.assertEqual(run_wt.stdout.strip(), "hello-wtime")
                self.assertEqual(payload_wt.read_text(), "hello-wtime")
            self.assertTrue(cache.is_file())


if __name__ == "__main__":
    unittest.main()
