#!/usr/bin/env python3
"""The slice pool's span tree externs lower to native C; direct Wasm refuses them.

stdlib/slice_pool_internal.goose declares runtime externs (gs_slice_pool_*)
that take node[>..]& and tree& references. The frontend accepts them for
either target; native C calls native/slice_pool.h, and the direct Wasm
backend, which has no span tree, refuses them by name.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMPILER = Path(os.environ.get('GOOSE_COMPILER', ROOT / 'build/bin/goose'))
STDLIB = ROOT / "stdlib"
SOURCE = ROOT / "tests/fixtures/contracts/slice-pool/direct_externs.goose"


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class SlicePoolBackends(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)

    def compile(self, target, *arguments):
        command = [COMPILER, SOURCE, "--target", target, "-O2", "--stdlib", STDLIB, *arguments]
        return subprocess.run(list(map(str, command)), cwd=self.work, capture_output=True, text=True)

    def test_wasm_direct_checks_and_refuses_emission(self):
        checked = self.compile("wasm-direct", "--check")
        self.assertEqual(checked.returncode, 0, checked.stderr)
        emitted = self.compile("wasm-direct", "-o", "pool.wasm")
        self.assertEqual(emitted.returncode, 1, emitted.stderr)
        self.assertIn("slice pool span tree externs are not supported by the direct Wasm backend", emitted.stderr)
        self.assertNotIn("public exports", emitted.stderr)
        self.assertFalse((self.work / "pool.wasm").exists())

    def test_native_emits_the_span_tree(self):
        emitted = self.compile("native", "-o", "pool.c")
        self.assertEqual(emitted.returncode, 0, emitted.stderr)
        text = (self.work / "pool.c").read_text()
        self.assertIn("static int64_t g_slice_pool_place(", text)
        self.assertIn("const GLoc *g_at", text)


if __name__ == "__main__":
    unittest.main()
