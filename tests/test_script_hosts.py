#!/usr/bin/env python3
"""Both script hosts print f32 as native Goose does and pass stdin bytes through unchanged."""
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

import wasmtime

ROOT = Path(__file__).resolve().parents[1]
NODE_HOST = ROOT / "scripts/run_wasm.mjs"
PYTHON_HOST = ROOT / "scripts/run_wasmtime.py"
spec = importlib.util.spec_from_file_location("python_wasmtime", PYTHON_HOST)
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)

# f32 bit patterns and native gs_fmt_f32's text for them (native/runtime/runtime_impl.h).
F32_TEXT = {
    # Decimal ties: of two shortest spellings as near, the even last digit.
    0x49F42402: "2000000.2",  # 2000000.25
    0xC9F42402: "-2000000.2",
    0x4A000001: "2097152.2",  # 2097152.25
    0x39800000: "0.00024414062",  # 2^-12 = 0.000244140625
    0xB9800000: "-0.00024414062",
    # Powers of two: the gap down is half the gap up, so shorter text lies above.
    0x0F800000: "1.2621775e-29",  # 2^-96
    0x8F800000: "-1.2621775e-29",
    0x6B000000: "1.5474251e+26",  # 2^87
    0xEB000000: "-1.5474251e+26",
    0x6C800000: "1.2379401e+27",  # 2^90
    # Subnormals, extremes, notation thresholds and special values keep their spelling.
    0x00000001: "1e-45",
    0x007FFFFF: "1.1754942e-38",
    0x00800000: "1.1754944e-38",
    0x7F7FFFFF: "3.4028235e+38",
    0x3DCCCCCD: "0.1",
    0x38D1B717: "0.0001",
    0x3F800000: "1.0",
    0x4B800000: "16777216.0",
    0x5A5E0B6B: "1.5625e+16",
    0x00000000: "0.0",
    0x80000000: "-0.0",
    0x7F800000: "inf",
    0xFF800000: "-inf",
    0x7FC00000: "nan",
}


def f32(bits):
    return struct.unpack("<f", struct.pack("<I", bits))[0]


def print_f32_module(patterns):
    """A module printing each f32 through print_f32, then through format_f32 and write."""
    data = b"".join(struct.pack("<I", bits) for bits in patterns)
    escaped = "".join(f"\\{byte:02x}" for byte in data)
    return wasmtime.wat2wasm(f'''(module
      (import "goose" "print_f32" (func $print (param f32)))
      (import "goose" "format_f32" (func $format (param i32 f32) (result i32)))
      (import "goose" "write" (func $write (param i32 i32)))
      (import "goose" "newline" (func $newline))
      (memory (export "memory") 1)
      (data (i32.const 64) "{escaped}")
      (func (export "_start") (local $at i32)
        (local.set $at (i32.const 64))
        (block $done (loop $next
          (br_if $done (i32.ge_u (local.get $at) (i32.const {64 + len(data)})))
          (call $print (f32.load (local.get $at))) (call $newline)
          (call $write (i32.const 0) (call $format (i32.const 0) (f32.load (local.get $at)))) (call $newline)
          (local.set $at (i32.add (local.get $at) (i32.const 4)))
          (br $next)))))''')


# Echo stdin through WASI64 fd_read/fd_write, at most 100 bytes per read.
ECHO = wasmtime.wat2wasm('''(module
  (import "wasi_snapshot_preview1" "fd_read" (func $read (param i32 i64 i64 i64) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $write (param i32 i64 i64 i64) (result i32)))
  (memory (export "memory") i64 1)
  (func (export "_start")
    (loop $more
      (i64.store (i64.const 0) (i64.const 64)) (i64.store (i64.const 8) (i64.const 100))
      (drop (call $read (i32.const 0) (i64.const 0) (i64.const 1) (i64.const 16)))
      (if (i64.ne (i64.load (i64.const 16)) (i64.const 0)) (then
        (i64.store (i64.const 8) (i64.load (i64.const 16)))
        (drop (call $write (i32.const 1) (i64.const 0) (i64.const 1) (i64.const 24)))
        (br $more))))))''')

# Read two scalar tokens, print them, then echo all of stdin.
SCALARS_THEN_ECHO = wasmtime.wat2wasm('''(module
  (import "env" "bench_input" (func $input (result i64)))
  (import "goose" "print_i64" (func $print (param i64)))
  (import "goose" "newline" (func $newline))
  (import "wasi_snapshot_preview1" "fd_read" (func $read (param i32 i64 i64 i64) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $write (param i32 i64 i64 i64) (result i32)))
  (memory (export "memory") i64 1)
  (func (export "_start")
    (call $print (call $input)) (call $newline)
    (call $print (call $input)) (call $newline)
    (i64.store (i64.const 0) (i64.const 64)) (i64.store (i64.const 8) (i64.const 1000))
    (drop (call $read (i32.const 0) (i64.const 0) (i64.const 1) (i64.const 16)))
    (i64.store (i64.const 8) (i64.load (i64.const 16)))
    (drop (call $write (i32.const 1) (i64.const 0) (i64.const 1) (i64.const 24)))))''')

# NUL, CR/LF, invalid UTF-8, valid multibyte UTF-8, then every byte value.
BINARY = bytes.fromhex("fffe00410d0a") + "é€\n".encode() + bytes(range(256))


class HostCase(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)

    def module(self, name, data):
        path = self.work / name
        path.write_bytes(data)
        return path

    def hosts(self, module, stdin=b""):
        """Run a module on the Node and Python script hosts through their command lines."""
        results = {}
        for name, command in (("node", ["node", str(NODE_HOST)]), ("python", [sys.executable, str(PYTHON_HOST)])):
            results[name] = subprocess.run([*command, str(module)], input=stdin, capture_output=True, timeout=60)
        return results

    def node(self, script, *args):
        result = subprocess.run(["node", "--input-type=module", "-e", script, *map(str, args)],
                                cwd=ROOT, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)


class F32Formatting(HostCase):
    def test_python_helper_matches_native(self):
        for bits, text in F32_TEXT.items():
            with self.subTest(bits=f"{bits:08x}"):
                self.assertEqual(host.goose_float(f32(bits), 32), text)

    def test_node_helper_matches_native(self):
        observed = self.node('''
          import {gooseFloat} from "./scripts/run_wasm.mjs";
          const view = new DataView(new ArrayBuffer(4));
          console.log(JSON.stringify(JSON.parse(process.argv[1]).map((bits) => {
            view.setUint32(0, bits);
            return gooseFloat(view.getFloat32(0), 32);
          })));''', json.dumps(list(F32_TEXT)))
        for (bits, text), actual in zip(F32_TEXT.items(), observed):
            with self.subTest(bits=f"{bits:08x}"):
                self.assertEqual(actual, text)

    def test_hosts_print_and_format_f32_as_native(self):
        module = self.module("floats.wasm", print_f32_module(F32_TEXT))
        expected = "".join(f"{text}\n{text}\n" for text in F32_TEXT.values()).encode()
        for name, result in self.hosts(module).items():
            with self.subTest(host=name):
                self.assertEqual((result.returncode, result.stderr), (0, b""))
                self.assertEqual(result.stdout, expected)

    def test_f64_spelling_is_unchanged(self):
        cases = {0.1: "0.1", 2000000.25: "2000000.25", 1e15: "1e+15", 123456789012345.6: "123456789012345.6",
                 5e-324: "5e-324", -0.0001: "-0.0001", 1.7976931348623157e308: "1.7976931348623157e+308"}
        observed = self.node('''
          import {gooseFloat} from "./scripts/run_wasm.mjs";
          console.log(JSON.stringify(JSON.parse(process.argv[1]).map((value) => gooseFloat(value, 64))));''',
                             json.dumps(list(cases)))
        self.assertEqual(observed, list(cases.values()))
        self.assertEqual([host.goose_float(value) for value in cases], list(cases.values()))


class BinaryStdin(HostCase):
    def test_cli_hosts_echo_exact_bytes(self):
        module = self.module("echo.wasm", ECHO)
        for name, result in self.hosts(module, BINARY).items():
            with self.subTest(host=name):
                self.assertEqual((result.returncode, result.stderr), (0, b""))
                self.assertEqual(result.stdout, BINARY)

    def test_scalar_tokens_split_on_ascii_whitespace_beside_binary_bytes(self):
        module = self.module("scalars.wasm", SCALARS_THEN_ECHO)
        stdin = b"41\x0b-7 \xff\xfe\x00\n"
        for name, result in self.hosts(module, stdin).items():
            with self.subTest(host=name):
                self.assertEqual((result.returncode, result.stderr), (0, b""))
                self.assertEqual(result.stdout, b"41\n-7\n" + stdin)

    def test_programmatic_hosts_take_bytes_or_text(self):
        self.assertEqual(host.run_module(ECHO, BINARY, timing=False)["stdout"], BINARY)
        self.assertEqual(host.run_module(ECHO, "é\n", timing=False)["stdout"], "é\n".encode())
        module = self.module("echo.wasm", ECHO)
        observed = self.node('''
          import {readFileSync} from "node:fs";
          import {runModule} from "./scripts/run_wasm.mjs";
          const bytes = readFileSync(process.argv[1]);
          const results = [];
          for (const input of [Buffer.from(process.argv[2], "hex"), "é\\n"]) {
            const result = await runModule(bytes, input);
            results.push([result.exitCode, result.stdout.toString("hex")]);
          }
          console.log(JSON.stringify(results));''', module, BINARY.hex())
        self.assertEqual(observed, [[0, BINARY.hex()], [0, "é\n".encode().hex()]])


if __name__ == "__main__":
    unittest.main()
