#!/usr/bin/env python3
"""Root owners lower to native C; the direct Wasm backend refuses them itself.

The frontend accepts a root struct program for either target, so the refusal
belongs to Wasm emission and names the target, while native emission succeeds.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMPILER = Path(os.environ.get('GOOSE_COMPILER', ROOT / 'build/bin/goose'))
STDLIB = ROOT / "build/bin/stdlib"
OWNER = ROOT / "tests/fixtures/contracts/root-struct/owner.goose"


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class RootStructBackends(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)

    def compile(self, target, *arguments):
        command = [COMPILER, OWNER, "--target", target, "-O2", "--stdlib", STDLIB, *arguments]
        return subprocess.run(list(map(str, command)), cwd=self.work, capture_output=True, text=True)

    def test_wasm_direct_checks_and_refuses_emission(self):
        checked = self.compile("wasm-direct", "--check")
        self.assertEqual(checked.returncode, 0, checked.stderr)
        emitted = self.compile("wasm-direct", "-o", "owner.wasm")
        self.assertEqual(emitted.returncode, 1, emitted.stderr)
        self.assertIn("root struct storage is not supported by the direct Wasm backend", emitted.stderr)
        self.assertNotIn("not yet supported by code generation", emitted.stderr)
        self.assertFalse((self.work / "owner.wasm").exists())

    def test_native_emits_owner_storage(self):
        emitted = self.compile("native", "-o", "owner.c")
        self.assertEqual(emitted.returncode, 0, emitted.stderr)
        self.assertGreater((self.work / "owner.c").stat().st_size, 0)


if __name__ == "__main__":
    unittest.main()
