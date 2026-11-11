#!/usr/bin/env python3
"""The compiler refuses outputs that would replace a source or another output."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMPILER = Path(__import__('os').environ.get('GOOSE_COMPILER', ROOT / 'build/bin/goose'))
STDLIB = ROOT / "build/bin/stdlib"


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class OutputCollisions(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)
        self.sources = {
            "main.goose": "import helper;\nfn main() { print(helper::value()); }\n",
            "helper.goose": "namespace helper;\nfn value() -> i64 { return 41; }\n",
        }
        for name, text in self.sources.items():
            (self.work / name).write_text(text)

    def build(self, *arguments, target="wasm-direct"):
        command = [COMPILER, "main.goose", "--target", target, "-O2", "--stdlib", STDLIB, *arguments]
        return subprocess.run(list(map(str, command)), cwd=self.work, capture_output=True, text=True)

    def assert_refused(self, *arguments, message, target="wasm-direct"):
        result = self.build(*arguments, target=target)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(message, result.stderr)
        for name, text in self.sources.items():
            self.assertEqual((self.work / name).read_text(), text)

    def test_output_over_imported_source(self):
        self.assert_refused("-o", "helper.goose", message="output would overwrite a source file")
        self.assert_refused("-o", "./helper.goose", message="output would overwrite a source file", target="native")

    def test_statistics_over_output_or_source(self):
        self.assert_refused("-o", "m.wasm", "--wasm-stats", "m.wasm", message="statistics would overwrite")
        self.assertFalse((self.work / "m.wasm").exists())
        self.assert_refused("--check", "--wasm-stats", "helper.goose", message="statistics would overwrite")

    def test_dependencies_over_source_or_output(self):
        self.assert_refused("-o", "m.wasm", "--wasm-deps", "main.goose", message="dependency manifest would overwrite")
        self.assert_refused("-o", "m.wasm", "--wasm-stats", "s.json", "--wasm-deps", "s.json",
                            message="dependency manifest would overwrite")

    def test_distinct_outputs_are_written(self):
        result = self.build("-o", "m.wasm", "--wasm-stats", "s.json", "--wasm-deps", "d.json")
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in ("m.wasm", "s.json", "d.json"):
            self.assertTrue((self.work / name).stat().st_size > 0)


if __name__ == "__main__":
    unittest.main()
