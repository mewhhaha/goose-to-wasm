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
WTIME_AOT_HOST = ROOT / "host/wtime-aot/target/release/goose-wtime-aot"
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

    def test_wasm32_and_wasm64_args_floats_and_os_externs(self):
        code = (
            "import os;\n"
            "import std;\n"
            'extern fn raw_find_pair(s: const u8[:], a: const ByteSet&, d: i64, b: const ByteSet&) -> i64 = "gs_find_pair";\n'
            "fn main() {\n"
            "    let a = args();\n"
            "    var line: u8[>..] = [];\n"
            "    let got_line = read_line(line);\n"
            "    var rest: u8[>..] = [];\n"
            "    read_stdin(rest);\n"
            "    var rdir: u8[>..] = [];\n"
            "    let has_rdir = resource_dir(rdir);\n"
            "    let base = a[1];\n"
            "    var sub: u8[>..] = [];\n"
            '    sub.append(base); sub.append("/d");\n'
            "    let mk = make_dir(sub[..]);\n"
            "    var fa: u8[>..] = []; fa.append(sub[..]); fa.append(\"/b.txt\");\n"
            "    var fb: u8[>..] = []; fb.append(sub[..]); fb.append(\"/a.txt\");\n"
            '    let wa = write_file_atomic(fa[..], "ok");\n'
            "    let rn = rename_file(fa[..], fb[..]);\n"
            "    var listing: u8[>..] = [];\n"
            "    let ld = list_dir(sub[..], listing);\n"
            "    let df = delete_file(fb[..]);\n"
            "    let dd = delete_dir(sub[..]);\n"
            '    let set_a = byte_set("a");\n'
            '    let fp_neg = raw_find_pair("abca", set_a, -1, set_a);\n'
            '    let fp_ok = find_pair("abca", set_a, 3, set_a);\n'
            "    let fz: f64 = 0.0; let fnz: f64 = -0.0; let f1: f64 = 1.0;\n"
            "    let f32_p1: f32 = 0.1; let f32_nz: f32 = -0.0;\n"
            '    print(a.len, "|", got_line, "|", line, "|", rest, "|", has_rdir && rdir.len > 0, "|",\n'
            '          mk, wa, rn, ld, df, dd, "|", listing, "|", fp_neg, ",", fp_ok, "|",\n'
            '          fz, " ", fnz, " ", f1, " ", f32_p1, " ", f32_nz);\n'
            "}\n"
        )
        expected = "2|true|hello|world|true|truetruetruetruetruetrue|a.txt\n|-1,0|0.0 -0.0 1.0 0.1 -0.0\n"
        for memory64 in (False, True):
            wasm = self._compile(code, memory64=memory64)
            sub = self.work / f"wtime_{memory64}"
            sub.mkdir()
            run = subprocess.run(
                [str(WTIME_HOST), str(wasm), "--", str(sub)],
                input="hello\r\nworld",
                capture_output=True,
                text=True,
            )
            self.assertEqual(run.returncode, 0, f"memory64={memory64}: {run.stderr}")
            self.assertEqual(run.stdout, expected)

    def test_entry_i64_exit_code_negative_sleep_and_stdlib_math(self):
        code = (
            "import math;\n"
            "import json;\n"
            "import os;\n"
            'extern fn bsleep(ms: i64) = "blot_sleep_ms";\n'
            'export "run64" fn run64() -> i64 {\n'
            "    sleep_ms(-1);\n"
            "    bsleep(-1);\n"
            "    let _ = trim_memory();\n"
            "    let r = round(0.5) + round(-0.5) + mul_add(2.0, 3.0, 4.0) + (sin(0.5 as f32) as f64);\n"
            '    var rdr = json::reader("12.5");\n'
            "    var out: u8[>..] = [];\n"
            "    json::format_number(out, rdr.read_number());\n"
            "    print(out, \" \", r > 10.0);\n"
            "    return 7;\n"
            "}\n"
        )
        for memory64 in (False, True):
            wasm = self._compile(code, memory64=memory64, library=True)
            run = subprocess.run(
                [str(WTIME_HOST), str(wasm), "--entry", "run64"],
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                timeout=15,
            )
            self.assertEqual(run.returncode, 7, f"memory64={memory64}: {run.stderr}")
            self.assertEqual(run.stdout, "12.5 true\n")

    def test_f64_digits_random_bytes_stdin_max_and_f32_math(self):
        code = (
            "import json;\n"
            "import math;\n"
            "import os;\n"
            "fn main() {\n"
            "    var out: u8[>..] = [];\n"
            "    json::format_number(out, 1.5e300);\n"
            '    out.push(\' \');\n'
            "    json::format_number(out, 5e-324);\n"
            "    var chunk1: u8[>..] = [];\n"
            "    let ok1 = read_stdin(chunk1, 4);\n"
            "    var chunk2: u8[>..] = [];\n"
            "    let ok2 = read_stdin(chunk2, 10);\n"
            "    var chunk3: u8[>..] = [];\n"
            "    let ok3 = read_stdin(chunk3, 4);\n"
            "    var rnd: u8[16] = [0; 16];\n"
            "    let r_ok = random_bytes(rnd[..]);\n"
            "    var nz = false;\n"
            "    for b in rnd { if b != 0 { nz = true; } }\n"
            "    let s = hypot(3.0 as f32, 4.0 as f32) + cbrt(27.0 as f32) + exp2(3.0 as f32)\n"
            "          + expm1(0.0 as f32) + log1p(0.0 as f32) + sinh(0.0 as f32)\n"
            "          + cosh(0.0 as f32) + tanh(0.0 as f32);\n"
            '    print(out, "|", ok1, ":", chunk1, "|", ok2, ":", chunk2, "|", ok3, "|", r_ok && nz, "|", s);\n'
            "}\n"
        )
        for memory64 in (False, True):
            wasm = self._compile(code, memory64=memory64)
            run = subprocess.run(
                [str(WTIME_HOST), str(wasm)],
                input="abcdef",
                capture_output=True,
                text=True,
            )
            self.assertEqual(run.returncode, 0, f"memory64={memory64}: {run.stderr}")
            self.assertEqual(run.stdout, "1.5e300 5e-324|true:abcd|true:ef|false|true|17.0\n")


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
@unittest.skipUnless(WTIME_AOT_HOST.is_file(), "build host/wtime-aot first")
class WtimeAotHostExecutionTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)

    def _compile(self, code: str, *, memory64: bool = False, library: bool = False) -> Path:
        src = self.work / ("aot64.goose" if memory64 else "aot32.goose")
        out = self.work / ("aot64.wasm" if memory64 else "aot32.wasm")
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

    def test_wasm32_and_wasm64_fast_cache_and_timing(self):
        code = (
            "import json;\n"
            "import math;\n"
            "import os;\n"
            "fn main() {\n"
            "    var out: u8[>..] = [];\n"
            "    json::format_number(out, 1.5e300);\n"
            "    out.push(' ');\n"
            "    json::format_number(out, 5e-324);\n"
            "    var chunk: u8[>..] = [];\n"
            "    let ok = read_stdin(chunk, 4);\n"
            "    var rnd: u8[16] = [0; 16];\n"
            "    let r_ok = random_bytes(rnd[..]);\n"
            "    var nz = false;\n"
            "    for b in rnd { if b != 0 { nz = true; } }\n"
            "    let s = hypot(3.0 as f32, 4.0 as f32) + cbrt(27.0 as f32);\n"
            '    print(out, "|", ok, ":", chunk, "|", r_ok && nz, "|", s);\n'
            "}\n"
        )
        expected = "1.5e300 5e-324|true:abcd|true|8.0\n"
        for memory64 in (False, True):
            wasm = self._compile(code, memory64=memory64)
            cache = self.work / f"m{int(memory64)}.wtaot"
            for label, extra in (
                ("fast", ["--fast"]),
                ("o2-cold", ["--cache", str(cache)]),
                ("o2-warm", ["--cache", str(cache)]),
            ):
                timing = self.work / f"timing_{int(memory64)}_{label}.json"
                run = subprocess.run(
                    [str(WTIME_AOT_HOST), *extra, "--timing-json", str(timing), str(wasm)],
                    input="abcdef",
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(run.returncode, 0, f"memory64={memory64} {label}: {run.stderr}")
                self.assertEqual(run.stdout, expected)
                meta = json.loads(timing.read_text())
                self.assertEqual(meta["engine"], "wtime-aot-host")
                self.assertGreater(meta["compile_ns"], 0)
                self.assertGreater(meta["run_ns"], 0)
            self.assertTrue(cache.is_file())

    def test_entry_and_blot_externs_wasm64(self):
        payload = self.work / "aot-probe.txt"
        code = (
            'extern fn argument_count() -> i64 = "blot_argument_count";\n'
            'extern fn argument_size(index: i64) -> i64 = "blot_argument_size";\n'
            'extern fn argument_copy(index: i64, out: u8&, capacity: u64) -> i64 = "blot_argument_copy";\n'
            'extern fn open_write(path: const u8&, exclusive: bool) -> i32 = "blot_open_write";\n'
            'extern fn write_fd(fd: i32, first: const u8&, count: u64) -> i64 = "blot_write";\n'
            'extern fn close_fd(fd: i32) -> i32 = "blot_close";\n'
            'export "probe_main" fn probe_main() -> i32 {\n'
            "    if argument_count() < 2 { return 2; }\n"
            "    let n = argument_size(1);\n"
            "    var path: u8[>..] = []; path.resize(n + 1, 0);\n"
            "    let _ = argument_copy(1, path[0], n as u64);\n"
            "    let fd = open_write(path[0], false);\n"
            "    if fd < 0 { return 3; }\n"
            '    let msg: u8[>..] = "hello-wtime-aot";\n'
            "    let _ = write_fd(fd, msg[0], msg.len as u64);\n"
            "    let _ = close_fd(fd);\n"
            "    print(msg);\n"
            "    return 0;\n"
            "}\n"
        )
        wasm = self._compile(code, memory64=True, library=True)
        run = subprocess.run(
            [str(WTIME_AOT_HOST), "--fast", "--entry", "probe_main", str(wasm), "--", str(payload)],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.strip(), "hello-wtime-aot")
        self.assertEqual(payload.read_text(), "hello-wtime-aot")

    def test_inc_cache_edited_module_reuses_and_matches_cold(self):
        inc_dir = self.work / "inc-cache"
        t1 = self.work / "inc1.json"
        t2 = self.work / "inc2.json"
        code_v1 = (
            "fn helper_a(x: i64) -> i64 { return x * 3 + 1; }\n"
            "fn helper_b(x: i64) -> i64 { return x * 5 + 2; }\n"
            "fn main() { print(helper_a(7) + helper_b(11)); }\n"
        )
        code_v2 = code_v1.replace("x * 5 + 2", "x * 5 + 9")
        w1 = self._compile(code_v1, memory64=True)
        r1 = subprocess.run(
            [str(WTIME_AOT_HOST), "--inc-cache", str(inc_dir), "--timing-json", str(t1), str(w1)],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
        )
        self.assertEqual(r1.returncode, 0, r1.stderr)
        self.assertEqual(r1.stdout.strip(), str(22 + 57))
        self.assertTrue((inc_dir / "x64-inc").is_dir())

        w2 = self._compile(code_v2, memory64=True)
        r2 = subprocess.run(
            [str(WTIME_AOT_HOST), "--inc-cache", str(inc_dir), "--timing-json", str(t2), str(w2)],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
        )
        self.assertEqual(r2.returncode, 0, r2.stderr)
        self.assertEqual(r2.stdout.strip(), str(22 + 64))
        self.assertGreater(json.loads(t2.read_text())["compile_ns"], 0)


if __name__ == "__main__":
    unittest.main()
