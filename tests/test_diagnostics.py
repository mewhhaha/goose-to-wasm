#!/usr/bin/env python3
"""Verify rich compiler diagnostics (snippets, carets, candidates, suggestions, lifetime stacks) and Wasm host imports."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMPILER = Path(os.environ.get("GOOSE_COMPILER", ROOT / "build/bin/goosew")).resolve()
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

    def test_generic_and_stdlib_instantiation_stack(self):
        res = self.check_source(
            "fn inner<T>(x: T) -> T { return x + 1; }\n"
            "fn outer<U>(v: U) -> U { return inner(v); }\n"
            "fn main() { let s = outer(\"hi\"); print(s); }\n",
            ("--check",),
        )
        self.assertEqual(res.returncode, 1, res.stderr)
        self.assertIn("note: while instantiating `inner` called from", res.stderr)
        self.assertIn("note: while instantiating `outer` called from", res.stderr)

        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            lib = work / "lib"
            lib.mkdir()
            (lib / "std.goose").write_text((STDLIB / "std.goose").read_text())
            (lib / "badlib.goose").write_text(
                "namespace badlib;\n"
                "fn broken() -> i64 { let x: i32 = 1; var y: u32 = x; return y as i64; }\n"
            )
            src = work / "main.goose"
            src.write_text("import badlib;\nfn main() {\n    print(badlib::broken());\n}\n")
            res_lib = subprocess.run(
                [str(COMPILER), str(src), "--stdlib", str(lib), "--check"],
                cwd=work, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(res_lib.returncode, 1, res_lib.stderr)
            self.assertIn("badlib.goose:2:", res_lib.stderr)
            self.assertIn("note: while instantiating `broken` called from", res_lib.stderr)
            self.assertIn("main.goose:3:", res_lib.stderr)

    def test_missing_match_variants_and_unknown_variant_suggestion(self):
        res = self.check_source(
            "enum Color { Red, Green, Blue, Alpha }\n"
            "fn f(c: Color) -> i64 {\n"
            "    return match c { Red => 1 };\n"
            "}\n"
            "fn main() { print(f(Color.Red)); }\n",
            ("--check",),
        )
        self.assertEqual(res.returncode, 1, res.stderr)
        self.assertIn("match does not cover every possible value: missing variant(s): `Green`, `Blue`, `Alpha`", res.stderr)
        self.assertIn("help: add the missing arm(s) or a wildcard `_ => ...`", res.stderr)

        res_typo = self.check_source(
            "enum Color { Red, Green, Blue }\n"
            "fn f(c: Color) -> i64 { return match c { Red => 1, Gren => 2, _ => 3 }; }\n"
            "fn main() { print(f(Color.Red)); }\n",
            ("--check",),
        )
        self.assertEqual(res_typo.returncode, 1, res_typo.stderr)
        self.assertIn("`Color` has no variant `Gren`; did you mean `Green`?", res_typo.stderr)

        res_int = self.check_source(
            "fn f(x: i64) -> i64 { return match x { 0 => 1, 1 => 2 }; }\n"
            "fn main() { print(f(0)); }\n",
            ("--check",),
        )
        self.assertEqual(res_int.returncode, 1, res_int.stderr)
        self.assertIn("help: integer match requires a wildcard arm `_ => ...`", res_int.stderr)

    def test_missing_struct_fields_and_duplicate_field(self):
        res = self.check_source(
            "struct Config { host: const u8[:], port: i64, tls: bool }\n"
            "fn main() { let c = Config { host: \"localhost\" }; print(c.port); }\n",
            ("--check",),
        )
        self.assertEqual(res.returncode, 1, res.stderr)
        self.assertEqual(res.stderr.count("record literal leaves a field without an initializer"), 1, res.stderr)
        self.assertIn("`Config` is missing `port`, `tls`", res.stderr)
        self.assertIn("help: provide initializers for the missing field(s)", res.stderr)

        res_dup = self.check_source(
            "struct Config { host: const u8[:], port: i64 }\n"
            "fn main() { let c = Config { host: \"a\", host: \"b\", port: 80 }; print(c.port); }\n",
            ("--check",),
        )
        self.assertEqual(res_dup.returncode, 1, res_dup.stderr)
        self.assertIn("field initialized more than once: `host`", res_dup.stderr)

    def test_duplicate_declarations_prior_location(self):
        res_global = self.check_source(
            "struct Dup { a: i64 }\n"
            "struct Dup { b: i64 }\n"
            "fn main() {}\n",
            ("--check",),
        )
        self.assertEqual(res_global.returncode, 1, res_global.stderr)
        self.assertIn("duplicate declaration in this scope: `Dup`", res_global.stderr)
        self.assertIn("note: previously declared at", res_global.stderr)
        self.assertIn("main.goose:1:", res_global.stderr)

        res_param = self.check_source(
            "fn f(alpha: i64, alpha: i64) -> i64 { return alpha; }\n"
            "fn main() { print(f(1, 2)); }\n",
            ("--check",),
        )
        self.assertEqual(res_param.returncode, 1, res_param.stderr)
        self.assertIn("duplicate declaration name: `alpha`", res_param.stderr)
        self.assertIn("note: previously declared at", res_param.stderr)
        self.assertIn("main.goose:1:6", res_param.stderr)

    def test_immutable_let_reassignment_and_return_mismatch(self):
        res_let = self.check_source(
            "fn main() {\n"
            "    let count = 1;\n"
            "    count = 2;\n"
            "    print(count);\n"
            "}\n",
            ("--check",),
        )
        self.assertEqual(res_let.returncode, 1, res_let.stderr)
        self.assertIn("let binding cannot be assigned again: `count`", res_let.stderr)
        self.assertIn("note: `count` declared at", res_let.stderr)
        self.assertIn("main.goose:2:", res_let.stderr)
        self.assertIn("help: declare `count` with `var` to allow reassignment", res_let.stderr)

        res_ret = self.check_source(
            "fn f(x: i32) -> u32 {\n"
            "    return x;\n"
            "}\n"
            "fn main() { print(f(1)); }\n",
            ("--check",),
        )
        self.assertEqual(res_ret.returncode, 1, res_ret.stderr)
        self.assertIn("got `i32`, expected `u32`", res_ret.stderr)
        self.assertIn("help: convert explicitly with `as u32`", res_ret.stderr)

    def test_unclosed_delimiters_note_opening_location(self):
        res_brace = self.check_source(
            "fn main() {\n"
            "    let x = 1;\n",
            ("--check",),
        )
        self.assertEqual(res_brace.returncode, 1, res_brace.stderr)
        self.assertIn("expected } before end of file", res_brace.stderr)
        self.assertIn("note: opening `{` at", res_brace.stderr)
        self.assertIn("main.goose:1:11", res_brace.stderr)

        res_paren = self.check_source(
            "fn f(a: i64) {}\n"
            "fn main() {\n"
            "    f(1;\n"
            "}\n",
            ("--check",),
        )
        self.assertEqual(res_paren.returncode, 1, res_paren.stderr)
        self.assertIn("expected ) after call arguments", res_paren.stderr)
        self.assertIn("note: opening delimiter at", res_paren.stderr)
        self.assertIn("main.goose:3:6", res_paren.stderr)

    def test_json_error_format_and_color_options(self):
        src = (
            "fn main() {\n"
            "    let count = 1;\n"
            "    count = 2;\n"
            "}\n"
        )
        for flag in (("--error-format=json",), ("--error-format", "json")):
            res = self.check_source(src, ("--check", *flag))
            self.assertEqual(res.returncode, 1, res.stderr)
            items = json.loads(res.stderr)
            self.assertIsInstance(items, list)
            self.assertGreaterEqual(len(items), 1)
            first = items[0]
            self.assertEqual(first["severity"], "error")
            self.assertTrue(first["file"].endswith("main.goose"))
            self.assertEqual(first["line"], 3)
            self.assertEqual(first["column"], 5)
            self.assertGreater(first["end"], first["start"])
            self.assertIn("let binding cannot be assigned again", first["message"])
            self.assertTrue(any("note:" in n for n in first["notes"]), first["notes"])
            self.assertTrue(any("help:" in n for n in first["notes"]), first["notes"])

        res_color = self.check_source(src, ("--check", "--color=always"))
        self.assertEqual(res_color.returncode, 1, res_color.stderr)
        self.assertIn("\x1b[1;31merror:\x1b[0m", res_color.stderr)
        self.assertIn("\x1b[1;36mnote:\x1b[0m", res_color.stderr)
        self.assertIn("\x1b[1;32mhelp:\x1b[0m", res_color.stderr)

        res_plain = self.check_source(src, ("--check", "--color=never"))
        self.assertEqual(res_plain.returncode, 1, res_plain.stderr)
        self.assertNotIn("\x1b[", res_plain.stderr)

        res_bad = self.check_source(src, ("--check", "--error-format=xml"))
        self.assertEqual(res_bad.returncode, 2, res_bad.stderr)


if __name__ == "__main__":
    unittest.main()
