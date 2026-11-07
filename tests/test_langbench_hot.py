#!/usr/bin/env python3
"""Prepared execution must reuse code while resetting guest and host state."""

import hashlib
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
SPEC = importlib.util.spec_from_file_location("langbench_hot_contract", ROOT / "bench/langbench_hot.py")
HOT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HOT)

STATEFUL = '''(module
  (import "env" "bench_input" (func $input (result i64)))
  (import "goose" "print_i64" (func $print (param i64)))
  (import "goose" "newline" (func $newline))
  (memory (export "memory") 1)
  (data (i32.const 0) "\\07")
  (global $counter (mut i64) (i64.const 0))
  (func (export "_start")
    (call $print (call $input)) (call $newline)
    (call $print (global.get $counter)) (call $newline)
    (global.set $counter (i64.add (global.get $counter) (i64.const 1)))
    (call $print (i64.extend_i32_u (i32.load8_u (i32.const 0)))) (call $newline)
    (i32.store8 (i32.const 0) (i32.const 9))))'''


class PreparedExecution(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(dir=ROOT / "build")
        self.addCleanup(self.directory.cleanup)
        self.work = Path(self.directory.name)
        self.data = bytes(wasmtime.wat2wasm(STATEFUL))

    def test_wasmtime_reuses_deserialized_code_without_compiling_or_new_engine(self):
        prepared = HOT.host.prepare_module(self.data, self.work / "trusted.cwasm")
        self.assertEqual(prepared.source_sha256, hashlib.sha256(self.data).hexdigest())
        self.assertEqual(prepared.serialized_sha256,
                         hashlib.sha256((self.work / "trusted.cwasm").read_bytes()).hexdigest())
        self.assertEqual(prepared.preparation["module_compile_count"], 1)
        self.assertEqual(prepared.preparation["module_deserialize_count"], 1)
        with mock.patch.object(wasmtime, "Module", side_effect=AssertionError("recompiled")), \
                mock.patch.object(HOT.host, "create_engine", side_effect=AssertionError("new engine")):
            for value in (11, 22):
                result = HOT.host.run_module(self.data, f"{value}\n", prepared=prepared, timing=False)
                self.assertEqual(result, {"stdout": f"{value}\n0\n7\n".encode(), "stderr": "", "exit_code": 0})

    def test_prepared_source_mismatch_is_rejected(self):
        prepared = HOT.host.prepare_module(self.data, self.work / "trusted.cwasm")
        with self.assertRaisesRegex(ValueError, "does not match"):
            HOT.host.run_module(b"different source", "", prepared=prepared)

    def test_foreign_serialized_file_is_never_deserialized_or_overwritten(self):
        artifact = self.work / "foreign.cwasm"
        artifact.write_bytes(b"untrusted")
        with mock.patch.object(wasmtime.Module, "deserialize", side_effect=AssertionError("foreign deserialize")):
            with self.assertRaises(FileExistsError):
                HOT.host.prepare_module(self.data, artifact)
        self.assertEqual(artifact.read_bytes(), b"untrusted")

    def test_v8_resident_module_keeps_pid_and_resets_every_invocation(self):
        artifact = self.work / "state.wasm"
        artifact.write_bytes(self.data)
        worker = HOT.V8Worker(artifact, hashlib.sha256(self.data).hexdigest(), None, timeout=10)
        try:
            self.assertEqual(worker.ready["module_construction_count"], 1)
            for value in (11, 22):
                result = worker.run(f"{value}\n")
                self.assertEqual(result["stdout"], f"{value}\n0\n7\n")
                self.assertEqual(result["exit_code"], 0)
                self.assertEqual(result["pid"], worker.ready["pid"])
                self.assertEqual(result["module_construction_count"], 1)
        finally:
            self.assertEqual(worker.close(), {"exit_code": 0, "stderr": ""})

    def test_v8_bytes_api_and_prepared_module_api_agree(self):
        artifact = self.work / "state.wasm"
        artifact.write_bytes(self.data)
        script = '''
          import {readFileSync} from "node:fs";
          import {runModule} from "./scripts/run_wasm.mjs";
          const bytes = readFileSync(process.argv[1]);
          const module = await WebAssembly.compile(bytes);
          const results = [];
          for (const input of [bytes, module, module]) {
            const result = await runModule(input, "11\\n");
            results.push({stdout: result.stdout.toString(), stderr: result.stderr, exitCode: result.exitCode});
          }
          console.log(JSON.stringify(results));
        '''
        result = subprocess.run(["node", "--input-type=module", "-e", script, str(artifact)],
                                cwd=ROOT, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout),
                         [{"stdout": "11\n0\n7\n", "stderr": "", "exitCode": 0}] * 3)

    def test_native_goose_is_invoked_once_with_stdin(self):
        with mock.patch.object(HOT.cold, "invoke", return_value={}) as invoke:
            HOT.execute("goose-native", [8, 25, 1], Path("program"), None, b"", None, 7)
        invoke.assert_called_once_with([Path("program")], stdin="8 25 1\n", cpu=7)

    def test_v8_timeout_kills_and_quarantines_worker(self):
        artifact = self.work / "loop.wasm"
        artifact.write_bytes(wasmtime.wat2wasm('(module (func (export "_start") (loop $again (br $again))))'))
        worker = HOT.V8Worker(artifact, hashlib.sha256(artifact.read_bytes()).hexdigest(), None, timeout=1)
        with self.assertRaises(TimeoutError):
            worker.run("")
        self.assertIsNotNone(worker.child.poll())
        with self.assertRaisesRegex(ValueError, "not restarted"):
            worker.run("")
        self.assertNotEqual(worker.close()["exit_code"], 0)

    def test_relocated_artifacts_need_no_old_checkout_or_compiler(self):
        import wasmtime._ffi as ffi
        import shutil

        manifest = HOT.cold.load_manifest()
        artifacts = self.work / "relocated"
        fingerprints = {}
        for relative in ("bench/langbench/mandelbrot.goose", "bench/langbench/mandelbrot.c",
                         "bench/langbench/manifest.json", "bench/langbench/workload.yaml", "bench/host_input.c"):
            fingerprints["/missing/old-checkout/" + relative] = {"sha256": HOT.cold.sha256(ROOT / relative)}
        runtime_paths = {"node": str(Path(shutil.which("node")).resolve()), "python": str(Path(sys.executable).resolve())}
        library = str(Path(ffi.dll._name).resolve())
        for path in [*runtime_paths.values(), library]:
            fingerprints[path] = {"sha256": HOT.cold.sha256(Path(path))}
        report = {"schema": "goose-langbench-local-v1", "status": "passed", "profiles": ["small"],
                  "manifest": manifest, "samples": 1, "compile_samples": 1, "builds": [], "runs": [],
                  "metadata": {"fingerprints": fingerprints, "tools": {**runtime_paths, "goose": "/missing/compiler"},
                               "wasmtime": {"library": library}}}
        for cell in HOT.CELLS:
            name = "program"
            payload = b"native reference"
            if cell.startswith("goose-wasm-"):
                name = "program.wasm"
                payload = self.data
            destination = artifacts / cell / "0" / name
            destination.parent.mkdir(parents=True)
            destination.write_bytes(payload)
            report["builds"].append({"cell": cell, "round": 0, "status": "passed", "wall_seconds": 1,
                "artifacts": {f"/missing/artifacts/{cell}/0/{name}": {"sha256": hashlib.sha256(payload).hexdigest()}}})
            for phase in ("warmup", "measurement"):
                report["runs"].append({"cell": cell, "profile": "small", "phase": phase, "round": 0,
                                      "status": "passed", "wall_seconds": 1, "timed_region_ns": 1})
        path = self.work / "reference.json"
        path.write_text(json.dumps(report))
        _, actual, receipts = HOT.verify_reference(path, artifacts)
        self.assertEqual(len(actual), 6)
        self.assertEqual(receipts["frozen_reference_tools"]["goose"], "/missing/compiler")
        actual["c-gcc"].write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "artifact fingerprint changed"):
            HOT.verify_reference(path, artifacts)


if __name__ == "__main__":
    unittest.main()
