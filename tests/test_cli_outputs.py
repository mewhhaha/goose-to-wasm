#!/usr/bin/env python3
"""The compiler refuses outputs that would replace a source or another output, reads its size options, and runs as a Wasm module."""
import importlib.util
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMPILER = Path(__import__('os').environ.get('GOOSE_COMPILER', ROOT / 'build/bin/goose'))
STDLIB = ROOT / "build/bin/stdlib"
# The stdlib in the tree: what the compiler's own sources and the examples import.
SOURCE_STDLIB = ROOT / "stdlib"


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


@unittest.skipUnless(COMPILER.is_file() and __import__('shutil').which('node'), "bootstrap the compiler first; needs node")
class WasmHostedCompiler(unittest.TestCase):
    """The compiler compiled to direct Wasm, run by scripts/run_wasm.mjs, does what the native one does."""

    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.work = Path(cls.directory.name)
        cls.module = cls.work / "goose.wasm"
        built = subprocess.run([str(COMPILER), str(ROOT / "selfhost/main.goose"), "--stdlib", str(SOURCE_STDLIB), "--target", "wasm-direct",
                                "-O2", "--wasm-max-pages", "65535", "-o", str(cls.module)], capture_output=True, text=True)
        assert built.returncode == 0, built.stderr

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def hosted(self, *arguments):
        command = ["node", ROOT / "scripts/run_wasm.mjs", self.module, "--", *arguments]
        return subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, stdin=subprocess.DEVNULL)

    def native(self, *arguments):
        return subprocess.run(list(map(str, [COMPILER, *arguments])), cwd=ROOT, capture_output=True)

    def test_same_outputs(self):
        # tour recurses deeply enough to need the host's larger stack.
        for example, target, suffix in (("squares", "wasm-direct", "wasm"), ("squares", "native", "c"), ("tour", "wasm-direct", "wasm")):
            if True:
                with self.subTest(example=example, target=target):
                    a, b = self.work / f"hosted.{suffix}", self.work / f"native.{suffix}"
                    arguments = [f"examples/{example}.goose", "--stdlib", SOURCE_STDLIB, "--target", target, "-O2", "-o"]
                    first, second = self.hosted(*arguments, a), self.native(*arguments, b)
                    self.assertEqual((first.returncode, first.stdout, first.stderr), (0, second.stdout, second.stderr))
                    self.assertEqual(a.read_bytes(), b.read_bytes())

    def test_same_diagnostics(self):
        source = self.work / "bad.goose"
        source.write_text('fn main() { let x: i64 = "no"; }\n')
        first, second = self.hosted(source, "--stdlib", SOURCE_STDLIB, "--check"), self.native(source, "--stdlib", SOURCE_STDLIB, "--check")
        self.assertEqual((first.returncode, first.stdout, first.stderr), (1, second.stdout, second.stderr))
        self.assertIn(b"error:", first.stderr)

    def test_version_and_arguments(self):
        first, second = self.hosted("--version"), self.native("--version")
        self.assertEqual((first.returncode, first.stdout), (0, second.stdout))


@unittest.skipUnless(COMPILER.is_file() and __import__('shutil').which('node') and importlib.util.find_spec("wasmtime"),
                     "bootstrap the compiler first; needs node and the wasmtime package")
class WasmMemory64(unittest.TestCase):
    """--wasm-memory64: programs print what their 32-bit modules print, and the compiler as a 64-bit module compiles itself."""

    # 256 GiB of address space: every data region of the compiler holds its largest table.
    PAGES = "4194304"

    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.work = Path(cls.directory.name)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def emit(self, source, output, *options):
        command = [COMPILER, source, "--stdlib", SOURCE_STDLIB, "--target", "wasm-direct", "-O2", *options, "-o", output]
        result = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def run_module(self, engine, module, *arguments):
        command = ["node", ROOT / "scripts/run_wasm.mjs", module] if engine == "v8" else [sys.executable, ROOT / "scripts/run_wasmtime.py", module]
        return subprocess.run(list(map(str, [*command, *arguments])), cwd=ROOT, capture_output=True, stdin=subprocess.DEVNULL)

    def test_examples_print_the_same(self):
        for example in ("squares", "sorting", "tour"):
            narrow, wide = self.work / f"{example}.32.wasm", self.work / f"{example}.64.wasm"
            self.emit(f"examples/{example}.goose", narrow)
            self.emit(f"examples/{example}.goose", wide, "--wasm-memory64")
            expected = self.run_module("v8", narrow)
            self.assertEqual(expected.returncode, 0, expected.stderr)
            for engine in ("v8", "wasmtime"):
                with self.subTest(example=example, engine=engine):
                    observed = self.run_module(engine, wide)
                    self.assertEqual((observed.returncode, observed.stdout), (0, expected.stdout), observed.stderr)

    def test_page_limits(self):
        # 65,536 pages is all a 32-bit memory can declare; a 64-bit one takes more.
        refused = subprocess.run(list(map(str, [COMPILER, "examples/squares.goose", "--stdlib", SOURCE_STDLIB, "--target", "wasm-direct",
                                                "--wasm-max-pages", "262144", "-o", self.work / "refused.wasm"])), cwd=ROOT, capture_output=True, text=True)
        self.assertNotEqual(refused.returncode, 0)
        self.emit("examples/squares.goose", self.work / "large.wasm", "--wasm-memory64", "--wasm-max-pages", "262144")
        observed = self.run_module("v8", self.work / "large.wasm")
        self.assertEqual((observed.returncode, observed.stdout), (0, b"sum=140\n"), observed.stderr)

    def test_compiler_compiles_itself(self):
        module, cache = self.work / "goose64.wasm", self.work / "goose64.cwasm"
        options = ["--debug", "--wasm-memory64", "--wasm-max-pages", self.PAGES]
        self.emit("selfhost/main.goose", module, *options)

        def hosted(*arguments):
            return self.run_module("wasmtime", module, "--cache", cache, "--", *arguments)

        # A small program for both targets, then itself: the module it was built as.
        for target, suffix in (("wasm-direct", "wasm"), ("native", "c")):
            with self.subTest(target=target):
                a, b = self.work / f"hosted.{suffix}", self.work / f"native.{suffix}"
                arguments = ["examples/squares.goose", "--stdlib", SOURCE_STDLIB, "--target", target, "-O2", "-o"]
                first = hosted(*arguments, a)
                second = subprocess.run(list(map(str, [COMPILER, *arguments, b])), cwd=ROOT, capture_output=True)
                self.assertEqual((first.returncode, first.stdout, first.stderr), (0, second.stdout, second.stderr))
                self.assertEqual(a.read_bytes(), b.read_bytes())
        again = self.work / "again.wasm"
        result = hosted("selfhost/main.goose", "--stdlib", SOURCE_STDLIB, "--target", "wasm-direct", "-O2", *options, "-o", again)
        self.assertEqual((result.returncode, result.stderr), (0, b""))
        self.assertEqual(again.read_bytes(), module.read_bytes())


if __name__ == "__main__":
    unittest.main()
