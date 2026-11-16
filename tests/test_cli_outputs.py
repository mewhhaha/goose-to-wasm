#!/usr/bin/env python3
"""The compiler refuses outputs that would replace a source or another output, and reads its size options."""
from pathlib import Path
import re
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


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class StackReserve(unittest.TestCase):
    """--stack-reserve writes GS_STACK_RESERVE into the generated C, as upstream's does."""
    REFUSAL = "--stack-reserve takes a size from 64 KB to 256 TB"

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)
        (self.work / "main.goose").write_text("fn main() { print(1); }\n")

    def emit(self, *arguments):
        command = [COMPILER, "main.goose", "--target", "native", "--stdlib", STDLIB, "-o", "out.c", *arguments]
        return subprocess.run(list(map(str, command)), cwd=self.work, capture_output=True, text=True)

    # The option's own line: the runtime's default, under #ifndef, is spelled (2048ull << 20).
    OPTION = re.compile(r"#define GS_STACK_RESERVE \d+ull")

    def defines(self):
        return [line for line in (self.work / "out.c").read_text().splitlines() if self.OPTION.fullmatch(line)]

    def test_default_writes_no_define(self):
        self.assertEqual(self.emit().returncode, 0)
        self.assertEqual(self.defines(), [])

    def test_sizes_and_suffixes(self):
        plain = None
        for size, value in (("64K", 65536), ("65536", 65536), ("16g", 16 << 30), ("2GB", 2 << 30),
                            ("3m", 3 << 20), ("256T", 1 << 48)):
            with self.subTest(size=size):
                result = self.emit("--stack-reserve", size)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.defines(), [f"#define GS_STACK_RESERVE {value}ull"])
                rest = [line for line in (self.work / "out.c").read_text().splitlines()
                        if not self.OPTION.fullmatch(line)]
                if plain is None:
                    self.assertEqual(self.emit().returncode, 0)
                    plain = (self.work / "out.c").read_text().splitlines()
                self.assertEqual(rest, plain)

    def test_refused_sizes(self):
        for size in ("1K", "65535", "257T", "300T", "12x", "G", "", "-1", "9999999999999999999", "1.5G"):
            with self.subTest(size=size):
                result = self.emit("--stack-reserve", size)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(self.REFUSAL, result.stderr)

    def test_missing_value(self):
        result = self.emit("--stack-reserve")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing option value", result.stderr)


if __name__ == "__main__":
    unittest.main()
