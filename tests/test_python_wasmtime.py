#!/usr/bin/env python3
"""Keep optional CLI timing metadata out of the differential execution path."""
import importlib.metadata
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import wasmtime

ROOT = Path(__file__).resolve().parents[1]
HOST = ROOT / "scripts/run_wasmtime.py"
spec = importlib.util.spec_from_file_location("python_wasmtime", HOST)
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)


class PythonHostTiming(unittest.TestCase):
    def test_import_does_not_load_distribution_metadata(self):
        code = ("import runpy, sys; runpy.run_path(sys.argv[1]); "
                "assert 'importlib.metadata' not in sys.modules")
        result = subprocess.run([sys.executable, "-S", "-c", code, str(HOST)], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_programmatic_default_retains_timing_and_opt_out_skips_lookup(self):
        module = wasmtime.wat2wasm('(module (func (export "_start")))')
        with mock.patch.object(importlib.metadata, "version", return_value="test-version") as version:
            result = host.run_module(module, "")
            version.assert_called_once_with("wasmtime")
        timing = result["timing"]
        self.assertEqual(set(timing), {"engine", "wasmtime", "optimization", "compile_instantiate_ns",
                                       "start_function_ns", "engine_total_ns"})
        self.assertEqual(timing["wasmtime"], "test-version")
        self.assertEqual(timing["compile_instantiate_ns"] + timing["start_function_ns"], timing["engine_total_ns"])
        with mock.patch.object(importlib.metadata, "version", side_effect=AssertionError("metadata lookup")):
            plain = host.run_module(module, "", timing=False)
        self.assertNotIn("timing", plain)
        self.assertEqual({k: v for k, v in result.items() if k != "timing"}, plain)

    def test_cli_timing_preserves_output_and_schema(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as temp:
            work = Path(temp)
            module, timing = work / "program.wasm", work / "timing.json"
            module.write_bytes(wasmtime.wat2wasm('''(module
              (import "goose" "print_i64" (func $print (param i64)))
              (func (export "_start") (call $print (i64.const 42))))'''))
            command = [sys.executable, str(HOST), str(module)]
            plain = subprocess.run(command, capture_output=True)
            measured = subprocess.run([*command, "--timing-json", str(timing)], capture_output=True)
            self.assertEqual((plain.returncode, plain.stdout, plain.stderr), (0, b"42", b""))
            self.assertEqual((measured.returncode, measured.stdout, measured.stderr),
                             (plain.returncode, plain.stdout, plain.stderr))
            metadata = json.loads(timing.read_text())
            self.assertEqual(metadata["engine"], "Wasmtime")
            self.assertEqual(metadata["wasmtime"], importlib.metadata.version("wasmtime"))
            self.assertEqual(metadata["optimization"], "cranelift speed")
            self.assertEqual(metadata["compile_instantiate_ns"] + metadata["start_function_ns"],
                             metadata["engine_total_ns"])


if __name__ == "__main__":
    unittest.main()
