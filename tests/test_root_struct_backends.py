#!/usr/bin/env python3
"""Root owners lower to native C and to direct Wasm.

Both backends emit a root struct program the frontend accepts, and the direct
Wasm module prints what the native executable does, in V8 and (when its
bindings are installed) Wasmtime. A program whose only direct-Wasm refusal is
slice_pool's span tree externs is refused by those externs, not its root owner.
"""
from pathlib import Path
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMPILER = Path(os.environ.get('GOOSE_COMPILER', ROOT / 'build/bin/goose')).resolve()
STDLIB = COMPILER.parent / "stdlib"
OWNER = ROOT / "tests/fixtures/contracts/root-struct/owner.goose"
SLICE_POOL = ROOT / "tests/fixtures/contracts/slice-pool/spans.goose"
EXPECTED = b"4 [0, 1, 2, 3] abcd 0\n"


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class RootStructBackends(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)

    def compile(self, source, target, level, *arguments):
        command = [COMPILER, source, "--target", target, f"-O{level}", "--stdlib", STDLIB, *arguments]
        return subprocess.run(list(map(str, command)), cwd=self.work, capture_output=True, text=True)

    def engines(self, wasm):
        if shutil.which("node"):
            yield "V8", ["node", ROOT / "scripts/run_wasm.mjs", wasm]
        if importlib.util.find_spec("wasmtime") is not None:
            yield "Wasmtime", [sys.executable, ROOT / "scripts/run_wasmtime.py", wasm]

    def test_wasm_direct_emits_and_runs_owner_storage(self):
        for level in (0, 2):
            wasm = self.work / f"owner-O{level}.wasm"
            emitted = self.compile(OWNER, "wasm-direct", level, "-o", wasm)
            self.assertEqual(emitted.returncode, 0, emitted.stderr)
            self.assertNotIn("root struct storage", emitted.stderr)
            for engine, command in self.engines(wasm):
                with self.subTest(level=level, engine=engine):
                    result = subprocess.run(list(map(str, command)), capture_output=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, EXPECTED)

    def test_wasm_direct_refuses_slice_pool_by_its_externs(self):
        emitted = self.compile(SLICE_POOL, "wasm-direct", 2, "-o", "pool.wasm")
        self.assertEqual(emitted.returncode, 1, emitted.stderr)
        self.assertIn("slice pool span tree externs are not supported by the direct Wasm backend", emitted.stderr)
        self.assertNotIn("root struct", emitted.stderr)
        self.assertFalse((self.work / "pool.wasm").exists())

    def test_native_emits_owner_storage(self):
        emitted = self.compile(OWNER, "native", 2, "-o", "owner.c")
        self.assertEqual(emitted.returncode, 0, emitted.stderr)
        self.assertGreater((self.work / "owner.c").stat().st_size, 0)


if __name__ == "__main__":
    unittest.main()
