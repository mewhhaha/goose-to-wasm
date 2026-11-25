#!/usr/bin/env python3
"""Verify rich compiler diagnostics (snippets, carets, candidates, suggestions, lifetime stacks) and Wasm host imports."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMPILER = Path(os.environ.get("GOOSE_COMPILER", ROOT / "build/bin/goose")).resolve()
STDLIB = ROOT / "stdlib"


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class DiagnosticsAndHostImports(unittest.TestCase):
    def check_source(self, source: str, extra_args=()):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            src = work / "main.goose"
            src.write_text(source)
            cmd = [str(COMPILER), str(src), "--stdlib", str(STDLIB), *extra_args]
            return subprocess.run(cmd, cwd=work, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)

    def test_snippet_caret_and_type_mismatch_help(self):
        res = self.check_source(
            "fn main() {\n"
            "    var x: i32 = 1;\n"
            "    var y: u32 = x;\n"
            "    print(y);\n"
            "}\n",
            ("--check",),
        )
        self.assertEqual(res.returncode, 1, res.stderr)
        self.assertIn("got `i32`, expected `u32`", res.stderr)
        self.assertIn(" |     var y: u32 = x;", res.stderr)
        self.assertIn(" |                  ^", res.stderr)
        self.assertIn("help: convert explicitly with `as u32`", res.stderr)

    def test_overload_candidates_and_no_duplicate_cascade(self):
        res = self.check_source(
            "fn add(a: i64, b: i64) -> i64 { return a + b; }\n"
            "fn add(a: f64, b: f64) -> f64 { return a + b; }\n"
            "fn main() { print(add(1, \"oops\")); }\n",
            ("--check",),
        )
        self.assertEqual(res.returncode, 1, res.stderr)
        self.assertEqual(res.stderr.count("no overload matches"), 1, res.stderr)
        self.assertNotIn("empty array element type was never determined", res.stderr)
        self.assertIn("`add(i64, const u8[:])`", res.stderr)
        self.assertIn("candidate `fn add(a: i64, b: i64) -> i64`", res.stderr)
        self.assertIn("argument 2 `b`: got `const u8[:]`, expected `i64`", res.stderr)

    def test_typo_suggestions_and_available_variants(self):
        res_name = self.check_source(
            "fn main() { let counter = 10; print(countr); }\n",
            ("--check",),
        )
        self.assertEqual(res_name.returncode, 1, res_name.stderr)
        self.assertEqual(res_name.stderr.count("unknown name"), 1, res_name.stderr)
        self.assertIn("unknown name `countr`; did you mean `counter`?", res_name.stderr)

        res_type = self.check_source(
            "struct Point { x: i64, y: i64 }\n"
            "fn main() { var p: Pionts = Point { x: 1, y: 2 }; }\n",
            ("--check",),
        )
        self.assertEqual(res_type.returncode, 1, res_type.stderr)
        self.assertIn("unknown type: Pionts; did you mean `Point`?", res_type.stderr)

        res_field = self.check_source(
            "struct Point { x: i64, y: i64, label: const u8[:] }\n"
            "fn main() { let p = Point { x: 1, y: 2, label: \"a\" }; print(p.labl); }\n",
            ("--check",),
        )
        self.assertEqual(res_field.returncode, 1, res_field.stderr)
        self.assertIn("`Point` has no field `labl`; did you mean `label`?", res_field.stderr)

        res_enum = self.check_source(
            "enum Color { Red, Green, Blue }\n"
            "fn main() { let c = Color.Yellow; }\n",
            ("--check",),
        )
        self.assertEqual(res_enum.returncode, 1, res_enum.stderr)
        self.assertIn("`Color` has no variant `Yellow`", res_enum.stderr)
        self.assertIn("available variants: `Red`, `Green`, `Blue`", res_enum.stderr)

    def test_lifetime_shrink_identifies_variable_and_call_stack(self):
        res = self.check_source(
            "fn clear_it(buf: u8[>..<]&) { buf.clear(); }\n"
            "fn main() {\n"
            "    var data: u8[>..<] = [65, 66, 67];\n"
            "    let view = data[..];\n"
            "    clear_it(data);\n"
            "    print(view[0]);\n"
            "}\n",
            ("--check",),
        )
        self.assertEqual(res.returncode, 1, res.stderr)
        self.assertIn("array shrink invalidates a reference or holder that is used afterward: `view`", res.stderr)
        self.assertIn("in fn clear_it (called from", res.stderr)
        self.assertIn("in fn main (", res.stderr)

    def test_wasm_host_import_abi_error_is_actionable(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            src = work / "main.goose"
            wasm = work / "out.wasm"
            src.write_text(
                "struct Pair { a: i64, b: i64 }\n"
                "extern fn host_pair(p: Pair) -> i64;\n"
                "fn main() { print(host_pair(Pair { a: 1, b: 2 })); }\n"
            )
            res = subprocess.run(
                [str(COMPILER), str(src), "--stdlib", str(STDLIB), "--target", "wasm-direct", "-o", str(wasm)],
                cwd=work, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(res.returncode, 1, res.stderr)
            self.assertIn("`host_pair` parameter `p` has type `Pair`", res.stderr)
            self.assertIn("env.host_pair", res.stderr)

    @unittest.skipUnless(shutil.which("node"), "requires Node.js for custom Wasm host import execution")
    def test_custom_extern_fn_runs_as_wasm_host_import(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            src = work / "main.goose"
            wasm = work / "out.wasm"
            src.write_text(
                "extern fn host_add(a: i64, b: i64) -> i64;\n"
                "extern \"libdemo\" { fn host_mul(a: i64, b: i64) -> i64; }\n"
                "export fn run(x: i64) -> i64 { return host_mul(host_add(x, 7), 3); }\n"
                "fn main() {}\n"
            )
            built = subprocess.run(
                [str(COMPILER), str(src), "--stdlib", str(STDLIB), "--target", "wasm-direct", "-O2", "-o", str(wasm)],
                cwd=work, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(built.returncode, 0, built.stderr)
            js = (
                "const fs = require('fs');\n"
                "const bytes = fs.readFileSync(process.argv[1]);\n"
                "const noop = () => {};\n"
                "const goose = new Proxy({}, { get: () => noop });\n"
                "WebAssembly.instantiate(bytes, {\n"
                "  goose,\n"
                "  env: {\n"
                "    host_add: (a, b) => a + b,\n"
                "    host_mul: (a, b) => a * b,\n"
                "  },\n"
                "}).then(({ instance }) => {\n"
                "  console.log(instance.exports.run(5n).toString());\n"
                "});\n"
            )
            run = subprocess.run(["node", "-e", js, str(wasm)], capture_output=True, text=True, timeout=30)
            self.assertEqual((run.returncode, run.stdout.strip()), (0, "36"), run.stderr)


if __name__ == "__main__":
    unittest.main()
