#!/usr/bin/env python3
"""Both script hosts print f32 as native Goose does."""
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


if __name__ == "__main__":
    unittest.main()
