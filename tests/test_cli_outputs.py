#!/usr/bin/env python3
"""The compiler refuses outputs that would replace a source or another output, reads its size options, and runs as a Wasm module."""
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def declared_locals(module):
    """The number of locals each function body of a Wasm module declares."""
    data = Path(module).read_bytes()

    def unsigned(at):
        value = shift = 0
        while True:
            byte = data[at]
            at += 1
            value |= (byte & 0x7F) << shift
            shift += 7
            if byte < 0x80:
                return value, at

    at, counts = 8, []
    while at < len(data):
        section = data[at]
        size, at = unsigned(at + 1)
        if section == 10:
            bodies, cursor = unsigned(at)
            for _ in range(bodies):
                length, cursor = unsigned(cursor)
                groups, inner = unsigned(cursor)
                total = 0
                for _ in range(groups):
                    count, inner = unsigned(inner)
                    inner += 1
                    total += count
                counts.append(total)
                cursor += length
        at += size
    return counts
COMPILER = Path(__import__('os').environ.get('GOOSE_COMPILER', ROOT / 'build/bin/goosew'))
STDLIB = ROOT / "build/bin/stdlib"
# The stdlib in the tree: what the compiler's own sources and the examples import.
SOURCE_STDLIB = ROOT / "stdlib"
# The Rust Wasmtime host, once built (cargo build --release in host/rust).
RUST_HOST = ROOT / "host/rust/target/release/goose-wasmtime"


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

    def test_run_native_without_output_flag(self):
        result = self.build("--run", target="native")
        self.assertEqual((result.returncode, result.stdout), (0, "41\n"), result.stderr)


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class InliningBudget(unittest.TestCase):
    def test_exact_budget_with_zero_cost_nested_function(self):
        # The block costs one node, the bindings two each and the assignments
        # three each. The last declaration costs zero, leaving the total at 200.
        body = "    total += seed;\n" * 65
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            source = work / "main.goose"
            stats = work / "stats.json"
            output = work / "program.wasm"
            for extra in ("", "    seed;\n"):
                with self.subTest(extra_node=bool(extra)):
                    source.write_text(
                        "inline fn score(seed: i64, total: i64&) {\n"
                        "    let first = seed;\n"
                        "    let second = seed;\n"
                        + body
                        + "    fn unused(other: i64) -> i64 { return other - 100; }\n"
                        + extra
                        + "}\n"
                        # The defer keeps main out of tail-loop analysis so the
                        # node count changes only when the callee is cloned.
                        "fn main() { defer {} var total = 0; score(2, total); print(total); }\n"
                    )
                    counts = []
                    for level in (0, 1, 2):
                        command = [COMPILER, source, "--target", "wasm-direct", f"-O{level}",
                                   "--stdlib", SOURCE_STDLIB, "--wasm-stats", stats, "-o", output]
                        result = subprocess.run(command, capture_output=True, text=True, timeout=30)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        counts.append(json.loads(stats.read_text())["nodes"])
                    if extra:
                        self.assertEqual(counts, [counts[0]] * 3)
                    else:
                        self.assertGreater(counts[1], counts[0])
                        self.assertEqual(counts[1], counts[2])


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class ClassLifetimeChecks(unittest.TestCase):
    def test_replayed_slice_slot_store(self):
        # Distinct roots make the checker reach its 4,096-frame threshold
        # before analyzing the slice store, without changing compiler options.
        roots = "\n".join(f"    var root_{i}: i64 = 0; occupy(root_{i});" for i in range(4200))
        program = """\
fn occupy(slot: i64&) { slot += 1; }
fn put(slot: u8[:]&, value: u8[:]) { slot = value; }
fn relay(slot: u8[:]&, value: u8[:]) { put(slot, value); }
fn main() {
""" + roots + """
    var a: u8[>..] = [65];
    var s = a[..];
    relay(s, b[..]);
    print(s);
}
"""
        storage = "var b: u8[>..] = [66];\n"
        local = program.replace("    var a:", "    " + storage + "    var a:")
        cases = [
            ("different depth", storage + program, "binding changes its committed root lifetime depth"),
            ("same depth", local, ""),
            ("shrink after rebinding", local.replace("    print(s);", "    b.clear();\n    print(s);"),
             "array shrink invalidates a reference or holder"),
        ]
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "main.goose"
            for name, text, error in cases:
                with self.subTest(name=name):
                    source.write_text(text)
                    result = subprocess.run([COMPILER, source, "--target", "native", "--check", "--stdlib", SOURCE_STDLIB],
                                            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
                    if error:
                        self.assertEqual(result.returncode, 1, result.stderr)
                        self.assertIn(error, result.stderr)
                    else:
                        self.assertEqual(result.returncode, 0, result.stderr)

    def test_class_lifetime_precision_and_controls(self):
        # Cross the 4,096-frame class threshold so every positive and negative
        # case runs through class-keyed lifetime summaries.
        roots = "\n".join(f"    var root_{i}: i64 = 0; occupy(root_{i});" for i in range(4200))
        preamble = "fn occupy(slot: i64&) { slot += 1; }\n"

        def wrap(decls: str, body: str) -> str:
            return preamble + decls + "fn main() {\n" + roots + "\n" + body + "}\n"

        cases = [
            ("grow-only slice and member slotread beside grow-shrink tail",
             wrap(
                 "struct Holder { s: const u8[:] }\n"
                 "struct Keys { keys: u8[>..]&, gs: u8[>..<] }\n"
                 "fn key(keys: u8[>..]&) -> const u8[:] { return keys[..]; }\n"
                 "fn fill(keys: u8[>..]&, h: Holder&) { h.s = key(keys); }\n"
                 "fn prep(k: Keys&, h: Holder&) { fill(k.keys, h); }\n",
                 "    var ks: u8[>..] = [65, 66];\n"
                 "    var k = Keys { keys: ks, gs: [9] };\n"
                 "    var h = Holder { s: default<const u8[:]>() };\n"
                 "    prep(k, h);\n"
                 "    print(h.s.len);\n",
             ), ""),
            ("holder parameter field slotread",
             wrap(
                 "struct Buf { items: i64[:], junk: i64[>..<] }\n"
                 "struct Store { a: Buf&, b: Buf& }\n"
                 "struct View { x: i64[:], y: i64[:] }\n"
                 "fn make_view(self_: Store) -> View { return View { x: self_.a.items, y: self_.b.items }; }\n",
                 "    var data: i64[>..] = [10, 20];\n"
                 "    var b1 = Buf { items: data[..], junk: [1] };\n"
                 "    var b2 = Buf { items: data[..], junk: [2] };\n"
                 "    let s = Store { a: b1, b: b2 };\n"
                 "    let v = make_view(s);\n"
                 "    print(v.x.len + v.y.len);\n",
             ), ""),
            ("temporary aggregate argument in recursive cycle",
             wrap(
                 "struct Roles { words: const u8[:] }\n"
                 "recursive fn walk(n: i64, roles: Roles) -> i64 {\n"
                 "    if n == 0 { return roles.words.len; }\n"
                 "    var buf: u8[4] = [1, 2, 3, 4];\n"
                 "    return walk(n - 1, Roles { words: buf[..2] });\n"
                 "}\n",
                 '    print(walk(2, Roles { words: "ab" }));\n',
             ), ""),
            ("static empty slice does not accumulate stored roots",
             wrap(
                 "struct Value { n: i64 = 0, elements: const Value[:] = default<const Value[:]>(), }\n"
                 "reusable[] var element_pool: Value[>..] = [];\n"
                 "struct Reader { dummy: i64 = 0 }\n"
                 "fn make_elems(self_: Reader&, count: i64) -> Value[:] {\n"
                 "    let r = element_pool.alloc_slice(count);\n"
                 "    for &v in r { v = Value { .. }; }\n"
                 "    return r;\n"
                 "}\n"
                 "fn pollute(other: Value[:]) {\n"
                 "    var s: Value[:] = default<Value[:]>();\n"
                 "    if other.len > 0 { s = other; }\n"
                 "    if s.len > 0 { s[0] = Value { elements: other, .. }; }\n"
                 "}\n"
                 "recursive fn unaryValue(self_: Reader&, value: Value, depth: i64) -> Value {\n"
                 "    if depth > 4 || value.elements.len == 0 { return Value { n: value.n, .. }; }\n"
                 "    let elems = self_.make_elems(value.elements.len);\n"
                 "    for element, index in value.elements { elems[index] = self_.unaryValue(element, depth + 1); }\n"
                 "    return Value { elements: elems, .. };\n"
                 "}\n"
                 "recursive fn prefix(self_: Reader&, depth: i64) -> Value {\n"
                 "    if depth > 4 { return Value { .. }; }\n"
                 "    if depth < 2 {\n"
                 "        let operand = self_.prefix(depth + 1);\n"
                 "        return self_.unaryValue(operand, depth + 1);\n"
                 "    }\n"
                 "    return Value { elements: self_.make_elems(2), .. };\n"
                 "}\n",
                 "    var r = Reader { .. };\n"
                 "    pollute(r.make_elems(1));\n"
                 "    let out = r.prefix(0);\n"
                 "    print(out.n);\n",
             ), ""),
            ("negative: shrink slice ref loaded through T[:]&",
             wrap(
                 "fn peek(p: i64[:]&, gs: i64[>..<]&) {\n"
                 "    let v = p;\n"
                 "    gs.clear();\n"
                 "    print(v[0]);\n"
                 "}\n",
                 "    var gs: i64[>..<] = [42];\n"
                 "    var s = gs[..];\n"
                 "    peek(s, gs);\n",
             ), "array shrink invalidates a reference or holder"),
            ("negative: shrink while T[:]& alias is used",
             wrap(
                 "struct Item { x: i64 }\n"
                 "fn shrink_it(a: Item[>..<]&, r: Item[:]&) -> i64 { a.clear(); return r.len; }\n",
                 "    var a: Item[>..<] = [Item { x: 1 }];\n"
                 "    var s: Item[:] = a;\n"
                 "    print(shrink_it(a, s));\n",
             ), "array shrink invalidates a reference or holder"),
            ("negative: element assignment through ref keeps sibling escape",
             wrap(
                 "struct Box { r: i64& }\n"
                 "fn bad(boxes: Box[>..<]&, x: i64&) -> i64 {\n"
                 "    var local: i64 = 7;\n"
                 "    boxes[0] = Box { r: local };\n"
                 "    boxes[1] = Box { r: x };\n"
                 "    return 0;\n"
                 "}\n",
                 "    var a: i64 = 1;\n"
                 "    var b: Box[>..<] = [Box { r: a }, Box { r: a }];\n"
                 "    print(bad(b, a));\n",
             ), "stored reference does not outlive the storage that receives it"),
            ("negative: store grow-shrink field slice",
             wrap(
                 "struct Pool { items: i64[>..<] }\n"
                 "struct Holder { s: i64[:] }\n"
                 "fn bad(p: Pool&, h: Holder&) { h.s = p.items; }\n",
                 "    var p = Pool { items: [1, 2] };\n"
                 "    var k: i64[>..] = [3];\n"
                 "    var h = Holder { s: k };\n"
                 "    bad(p, h);\n"
                 "    p.items.clear();\n"
                 "    print(h.s.len);\n",
             ), "reference into grow-shrink elements cannot be stored"),
            ("negative: let holder of grow-shrink in recursive cycle",
             wrap(
                 "struct View { s: i64[:] }\n"
                 "recursive fn rec(n: i64, v: View) -> i64 {\n"
                 "    if n == 0 { return v.s.len; }\n"
                 "    var arr: i64[>..<] = [1, 2];\n"
                 "    let next = View { s: arr };\n"
                 "    let r = rec(n - 1, next);\n"
                 "    arr.clear();\n"
                 "    return r;\n"
                 "}\n",
                 "    var a: i64[>..] = [1];\n"
                 "    print(rec(2, View { s: a }));\n",
             ), "error:"),
            ("negative: back-edge unkeyed static holder taint",
             wrap(
                 "struct Box { s: const u8[:] }\n"
                 "recursive fn rec(n: i64, b: Box) -> Box {\n"
                 "    if n == 0 { return b; }\n"
                 "    var local: u8[2] = [65, 66];\n"
                 "    return rec(n - 1, Box { s: local[..] });\n"
                 "}\n",
                 '    let b = rec(2, Box { s: "hi" });\n'
                 "    print(b.s.len);\n",
             ), "error:"),
            ("negative: sound rejection of implicit T[>..<]& to T[:] stored in struct",
             wrap(
                 "struct Reflection { x: i64 }\n"
                 "struct Engine { reflections: Reflection[>..<]& }\n"
                 "struct ReflectionOrder { items: Reflection[:] }\n"
                 "fn makeReflectionOrder(items: Reflection[:]) -> ReflectionOrder { return ReflectionOrder { items }; }\n"
                 "fn finish(self_: Engine&) -> i64 {\n"
                 "    var ctx = makeReflectionOrder(self_.reflections);\n"
                 "    self_.reflections.clear();\n"
                 "    return ctx.items[0].x;\n"
                 "}\n",
                 "    var arr: Reflection[>..<] = [Reflection { x: 42 }];\n"
                 "    var e = Engine { reflections: arr };\n"
                 "    print(finish(e));\n",
             ), "reference into grow-shrink elements cannot be stored"),
            ("folded globals shrink does not false-positive against disjoint class parameter target",
             wrap(
                 "\n".join(f"var gbuf_{i}: u8[>..<] = [{i}];" for i in range(20)) + "\n"
                 "struct Job { code: i64 = 0 }\n"
                 "fn pick_buf(i: i64) -> u8[>..<]& {\n"
                 + "".join(f"    if i == {i} {{ return gbuf_{i}; }}\n" for i in range(19))
                 + "    return gbuf_19;\n"
                 "}\n"
                 "fn run_work(i: i64) -> i64 {\n"
                 "    pick_buf(i).clear();\n"
                 "    return 7;\n"
                 "}\n"
                 "fn execute_job(job: Job&, i: i64) {\n"
                 "    job.code = run_work(i);\n"
                 "}\n",
                 "    var j = Job { .. };\n"
                 "    execute_job(j, 3);\n"
                 "    print(j.code);\n",
             ), ""),
            ("negative: folded globals shrink still rejects overlapping class parameter target",
             wrap(
                 "struct Job { code: i64 = 0 }\n"
                 + "\n".join(f"var gjobs_{i}: Job[>..<] = [Job {{ code: {i} }}];" for i in range(20)) + "\n"
                 "fn pick_jobs(i: i64) -> Job[>..<]& {\n"
                 + "".join(f"    if i == {i} {{ return gjobs_{i}; }}\n" for i in range(19))
                 + "    return gjobs_19;\n"
                 "}\n"
                 "fn run_work(i: i64) -> i64 {\n"
                 "    pick_jobs(i).clear();\n"
                 "    return 7;\n"
                 "}\n"
                 "fn execute_job(job: Job&, i: i64) {\n"
                 "    job.code = run_work(i);\n"
                 "}\n",
                 "    execute_job(gjobs_3[0], 3);\n"
                 "    print(gjobs_3.len);\n",
             ), "array shrink invalidates a value still needed by the enclosing expression"),
        ]
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "main.goose"
            for name, text, error in cases:
                with self.subTest(name=name):
                    source.write_text(text)
                    result = subprocess.run([COMPILER, source, "--target", "native", "--check", "--stdlib", SOURCE_STDLIB],
                                            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
                    if error:
                        self.assertEqual(result.returncode, 1, result.stderr)
                        self.assertIn(error, result.stderr)
                    else:
                        self.assertEqual(result.returncode, 0, result.stderr)

    def test_multi_discard_bindings(self):
        # Multiple `_` bindings in local declarations and `for` loops match
        # upstream Goose semantics across both backends; duplicate `_`
        # parameters, globals, and undeclared `_` assignment stay rejected.
        source_text = """\
fn triple() -> i64, i64, i64 { return 10, 20, 30; }
fn pair() -> i64, i64 { return 40, 50; }
fn main() {
    let a, _, _ = triple();
    var _, _ = pair();
    let _ = 1;
    let _ = 2;
    let xs: i64[3] = [1, 2, 3];
    var count = 0;
    for _, _ in xs { count += 1; }
    print(a + count);
}
"""
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            src = work / "discard.goose"
            src.write_text(source_text)
            for opt in ("-O0", "-O2"):
                with self.subTest(backend="native", opt=opt):
                    ran = subprocess.run(
                        [COMPILER, src, "--target", "native", opt, "--run", "--stdlib", SOURCE_STDLIB],
                        cwd=work, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
                    )
                    self.assertEqual((ran.returncode, ran.stdout), (0, "13\n"), ran.stderr)
                with self.subTest(backend="wasm-direct", opt=opt):
                    wasm = work / f"discard{opt}.wasm"
                    built = subprocess.run(
                        [COMPILER, src, "--target", "wasm-direct", opt, "--stdlib", SOURCE_STDLIB, "-o", wasm],
                        stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
                    )
                    self.assertEqual(built.returncode, 0, built.stderr)
                    host_cmd = [RUST_HOST, wasm] if RUST_HOST.is_file() else [sys.executable, ROOT / "scripts/run_wasmtime.py", wasm]
                    ran = subprocess.run(host_cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
                    self.assertEqual((ran.returncode, ran.stdout), (0, "13\n"), ran.stderr)

            for name, bad in (
                ("duplicate param", "fn f(_: i64, _: i64) {}\nfn main() { f(1, 2); }\n"),
                ("duplicate global", "let _ = 1;\nlet _ = 2;\nfn main() {}\n"),
                ("undeclared assign", "fn pair() -> i64, i64 { return 1, 2; }\nfn main() { var a = 0; a, _ = pair(); }\n"),
            ):
                with self.subTest(negative=name):
                    bad_src = work / f"{name.replace(' ', '_')}.goose"
                    bad_src.write_text(bad)
                    res = subprocess.run(
                        [COMPILER, bad_src, "--target", "native", "--check", "--stdlib", SOURCE_STDLIB],
                        stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
                    )
                    self.assertEqual(res.returncode, 1, res.stderr)


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class PostPinUpstreamParity(unittest.TestCase):
    """Regression coverage for post-pin upstream Goose language, checker, and stdlib parity fixes."""

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)

    def _run_both_backends(self, name: str, source_text: str, expected: str):
        src = self.work / f"{name}.goose"
        src.write_text(source_text)
        compiler = COMPILER.resolve()
        for opt in ("-O0", "-O2"):
            with self.subTest(case=name, backend="native", opt=opt):
                ran = subprocess.run(
                    [compiler, src, "--target", "native", opt, "--run", "--stdlib", SOURCE_STDLIB],
                    cwd=self.work, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
                )
                self.assertEqual((ran.returncode, ran.stdout), (0, expected), ran.stderr)
            with self.subTest(case=name, backend="wasm-direct", opt=opt):
                wasm = self.work / f"{name}{opt}.wasm"
                built = subprocess.run(
                    [compiler, src, "--target", "wasm-direct", opt, "--stdlib", SOURCE_STDLIB, "-o", wasm],
                    stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
                )
                self.assertEqual(built.returncode, 0, built.stderr)
                host_cmd = [RUST_HOST, wasm] if RUST_HOST.is_file() else [sys.executable, ROOT / "scripts/run_wasmtime.py", wasm]
                ran = subprocess.run(host_cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
                self.assertEqual((ran.returncode, ran.stdout), (0, expected), ran.stderr)

    def _expect_rejected(self, name: str, source_text: str, needle: str):
        src = self.work / f"neg_{name}.goose"
        src.write_text(source_text)
        res = subprocess.run(
            [COMPILER.resolve(), src, "--target", "native", "--check", "--stdlib", SOURCE_STDLIB],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(res.returncode, 1, f"{name} unexpectedly accepted")
        self.assertIn(needle, res.stderr)

    def test_deprecated_modifier_and_contextual_name(self):
        source = """\
deprecated "use next_val" fn old_val(x: i64) -> i64 { return x + 1; }
deprecated fn bare_val() -> i64 { return 2; }
fn main() {
    deprecated "use kept" fn inner() -> i64 { return 3; }
    let deprecated = 4;
    print(old_val(1), " ", bare_val(), " ", inner(), " ", deprecated);
}
"""
        self._run_both_backends("deprecated", source, "2 2 3 4\n")
        self._expect_rejected("defer_deprecated", "fn main() { defer deprecated fn f() {} }\n", "defer takes a statement or a block")

    def test_const_polymorphic_trailing_block_preservation(self):
        source = """\
fn each_byte<F>(s: u8[:]) {
    for b in s { F(b); }
}
fn emit(s: u8[:]) {
    var total = 0;
    each_byte(s) { total += it as i64; };
    print(total);
}
fn main() {
    var mut_buf: u8[>..] = [1, 2, 3];
    emit(mut_buf[..]);
    emit("AB");
}
"""
        self._run_both_backends("const_poly_trailing", source, "6\n131\n")

    def test_generic_format_hooks_and_non_hooks(self):
        source = """\
struct Tag<T> { _: bool = false }
struct Box<T> { v: T }
struct Big<T> { v: T, s: u8[>..] }
enum Opt<T> { Some { v: T }, None }
struct Pt { x: i32 }

fn tag_size(t: Tag<u32>) -> i64 { return 4; }
fn format<T>(out: u8[>..]&, t: Tag<T>) { format(out, "tag=", tag_size(t)); }
fn format<T>(out: u8[>..]&, b: Box<T>) { format(out, "Box(", b.v, ")"); }
fn format(out: u8[>..]&, b: Box<bool>) { out.append("BoolBox"); }
fn format<T>(out: u8[>..]&, b: Big<T>&) { format(out, "Big(", b.v, ",", b.s.len, ")"); }
fn format<T>(out: u8[>..]&, o: const Opt<T>&) {
    match o { Some s => format(out, "Some(", s.v, ")"), None => out.append("None") }
}
fn format<T>(out: u8[>..]&, v: T) { out.push('!'); }
fn format<T>(out: u8[>..]&, a: T[]) { out.push('#'); }
fn format<T>(out: u8[>..]&, p: Pt) { out.push('?'); }
fn format<T>(out: u8[>..]&, b: Box<T>?) { out.push('o'); }

fn main() {
    var big = Big<i64> { 5, [] };
    big.s.push(9);
    let some: Opt<i32> = Opt<i32>.Some { 4 };
    let none: Opt<i32> = Opt<i32>.None {};
    let opt_box: Box<i32>? = null;
    var xs: i32[] = [1, 2];
    print(Tag<u32> {}, " ", Box<i32> { 3 }, " ", Box<bool> { true }, " ", Box<Box<i32>> { Box<i32> { 7 } });
    print(big, " ", some, " ", none, " ", Pt { 1 }, " ", xs, " ", opt_box);
}
"""
        self._run_both_backends(
            "generic_format_hooks",
            source,
            "tag=4 Box(3) BoolBox Box(Box(7))\nBig(5,1) Some(4) None Pt { 1 } [1, 2] null\n",
        )

    def test_root_component_pool_index_of(self):
        source = """\
struct Item { n: i64 }
root struct Pool {
    items: Item[>..],
}
var P: Pool;
struct Link { target: Item&<u32 in P.items> }
fn main() {
    P.items.push(Item { 10 });
    P.items.push(Item { 20 });
    var links: (Item&<u32 in P.items>)[>..] = [];
    links.push(P.items[1]);
    let holder = Link { P.items[1] };
    let i1 = P.items.index_of(links[0]);
    let i2 = P.items.index_of(holder.target);
    let r .= holder.target;
    let i3 = P.items.index_of(r);
    print(i1, " ", i2, " ", i3, " ", P.items[i1].n);
}
"""
        self._run_both_backends("root_component_index_of", source, "1 1 1 20\n")

    def test_emptied_static_fields_and_holder_param_stores_later(self):
        emptied_source = """\
struct Msg { tag: const u8[:] = "", payload: const u8[:] = "", first: (u8&)? = null }
fn reset_fields(buf: u8[>..]&, out: Msg&, data: const u8[:]) {
    out.tag = "";
    out.payload = "";
    out.first .= null;
    buf.clear();
    buf.append(data);
    out.tag = buf[..1];
    out.payload = buf[1..];
    out.first .= buf[0];
}
fn reset_whole(buf: u8[>..]&, out: Msg&, data: const u8[:]) {
    out = Msg {};
    buf.clear();
    buf.append(data);
    out.payload = buf[..];
}
fn main() {
    var buf: u8[>..] = [];
    var m = Msg {};
    for i in 2 {
        reset_fields(buf, m, "abc");
        reset_whole(buf, m, "xy");
    }
    print(m.payload);
    m = Msg {};
    buf.clear();
    print(m.tag, "ok");
}
"""
        self._run_both_backends("emptied_static", emptied_source, "xy\nok\n")

        holder_source = """\
struct Row { v: const u8[:] }
fn put(out: Row[>..]&, x: Row) { out.push(x); }
fn main() {
    var k: u8[>..] = [];
    k.push('k');
    var out: Row[>..] = [];
    var n = 0;
    if n == 0 {
        var a: u8[>..] = [];
        a.push('a');
        var rows: Row[>..] = [];
        rows.push(Row { k[..] });
        put(out, rows[0]);
        rows.push(Row { a[..] });
        a.clear();
        print(out[0].v);
    }
}
"""
        self._run_both_backends("holder_stores_later", holder_source, "k\n")

        # Soundness negatives must remain rejected.
        self._expect_rejected(
            "holder_push_before_put",
            """\
struct Row { v: const u8[:] }
fn put(out: Row[>..]&, x: Row) { out.push(x); }
fn main() {
    var out: Row[>..] = [];
    var n = 0;
    if n == 0 {
        var a: u8[>..] = [];
        a.push('a');
        var rows: Row[>..] = [];
        rows.push(Row { a[..] });
        put(out, rows[0]);
    }
    print(out[0].v);
}
""",
            "stored reference does not outlive",
        )
        self._expect_rejected(
            "holder_push_in_loop",
            """\
struct Row { v: const u8[:] }
fn put(out: Row[>..]&, x: Row) { out.push(x); }
fn main() {
    var out: Row[>..] = [];
    var rows: Row[>..] = [];
    for i in 0..2 {
        var a: u8[>..] = [];
        a.push('a');
        put(out, rows[0]);
        rows.push(Row { a[..] });
    }
    print(out[0].v);
}
""",
            "stored reference does not outlive",
        )
        self._expect_rejected(
            "emptied_missed_field",
            """\
struct Msg { tag: const u8[:] = "", body: const u8[:] = "" }
fn clear_partial(buf: u8[>..]&, out: Msg&) {
    out.tag = "";
    buf.clear();
}
fn main() {
    var buf: u8[>..] = [];
    buf.append("hi");
    var m = Msg { buf[..], buf[..] };
    clear_partial(buf, m);
    print(m.body);
}
""",
            "array shrink invalidates",
        )

    def test_run_based_checkfree_and_upgraded_stdlib(self):
        # Run-based checkfree: checkfree callers can call plain helpers and
        # upgraded stdlib modules (mat, quat, binary, math, std, os) without
        # callee checkfree annotations, as long as nothing reached keeps a check.
        ok_source = """\
import math;
import vec;
import mat;
import quat;
import binary;
import os;
import std;

fn sum_plain(xs: i64[:]) -> i64 {
    var t = 0;
    for i in xs.len { t += xs[i]; }
    return t;
}
fn each_plain<F>(xs: i64[:]) {
    for x in xs { F(x); }
}
checkfree fn run_checkfree(xs: i64[:]) -> i64 {
    var total = sum_plain(xs);
    each_plain(xs) { x => total += x; };
    let a: double2x2 = [double2 { 1.0, 3.0 }, double2 { 2.0, 4.0 }];
    let r = row(a, 1);
    let q = angle_axis(PI / 2.0, double3 { 0.0, 0.0, 1.0 });
    let rot = rotate(q, double3 { 1.0, 0.0, 0.0 });
    let sw = byte_swap(0x12345678 as u32);
    let cs = copysign(3.0, -1.0);
    let csf = copysign(3.0 as f32, -1.0 as f32);
    let h: f32 = hypot(3.0 as f32, 4.0 as f32);
    let b = ascii::is_digit('7');
    var rnd: u8[8] = [0; 8];
    let ok = random_bytes(rnd);
    print(total, " ", r.x, " ", round(rot.y), " ", sw, " ", cs, " ", csf, " ", h, " ", b, " ", ok);
    return total;
}
fn main() {
    let xs: i64[3] = [2, 3, 5];
    let _ = run_checkfree(xs[..]);
    let buf: u8[4] = [1, 2, 3, 4];
    let rd, ok2 = binary::read_u32be(buf, 0);
    print(rd, " ", ok2);
}
"""
        self._run_both_backends(
            "checkfree_and_stdlib",
            ok_source,
            "20 3.0 1.0 2018915346 -3.0 -3.0 5.0 true true\n16909060 true\n",
        )

        # Negative 1: transitive non-checkfree callee keeping a bounds check reports the call chain.
        self._expect_rejected(
            "checkfree_callee_chain",
            """\
var a: i64[>..] = [1, 2, 3];
fn get(i: i64) -> i64 { return a[i]; }
fn twice(i: i64) -> i64 { return get(i) + get(i); }
checkfree fn sum_all(n: i64) -> i64 { return twice(n); }
fn main() { print(sum_all(1)); }
""",
            "checkfree fn sum_all calls twice, which calls get, which keeps a bounds check",
        )

        # Negative 2: block passed into checkfree keeping a bounds check attributes the caller.
        self._expect_rejected(
            "checkfree_block_check",
            """\
checkfree fn each<F>(n: i64) { for i in 0..n { F(i); } }
fn main() {
    var a: i64[>..] = [1, 2, 3];
    var t = 0;
    each(3) { x => t += a[x]; };
    print(t);
}
""",
            "checkfree fn each keeps a bounds check in code written in fn main",
        )


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


@unittest.skipUnless(COMPILER.is_file() and (__import__('shutil').which('cc') or __import__('shutil').which('clang') or __import__('shutil').which('gcc')),
                     "bootstrap the compiler first; needs a C compiler")
class CHostLibraryBuild(unittest.TestCase):
    """--emit-runtime, --header, --shared, goose_init/goose_exit, direct host externs, and export-only reachability."""

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)
        self.cc = (__import__('shutil').which('clang') or __import__('shutil').which('gcc') or 'cc')

    def test_separate_runtime_header_reinit_and_unreachable_skip(self):
        rt_c = self.work / "goose_runtime.c"
        rt_o = self.work / "goose_runtime.o"
        emit_rt = subprocess.run([str(COMPILER), "--emit-runtime", str(rt_c)],
                                 stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
        self.assertEqual(emit_rt.returncode, 0, emit_rt.stderr)
        subprocess.run([self.cc, "-std=gnu11", "-D_GNU_SOURCE", "-O2", "-pthread", "-c", str(rt_c), "-o", str(rt_o)],
                       stdin=subprocess.DEVNULL, check=True, capture_output=True, text=True, timeout=60)

        lib = self.work / "lib.goose"
        lib.write_text(
            'extern fn host_add(a: i32, b: i32) -> i32 = "c_host_add";\n'
            'var counter: i64 = 10;\n'
            'struct Deferred { label: const u8[:] = default<const u8[:]>(), value: i32 }\n'
            'fn unreachable_broken() -> i64 { let bad: i64 = "not an int"; return bad; }\n'
            'fn helper(x: i32) -> i32 {\n'
            '    var d: Deferred;\n'
            '    if x > 0 { d = Deferred { label: "pos", value: x }; } else { d = Deferred { label: "neg", value: 0 }; }\n'
            '    counter += d.value as i64;\n'
            '    return host_add(d.value, counter as i32);\n'
            '}\n'
            'export "demo_entry" fn entry(x: i32) -> i32 { return helper(x); }\n'
            'export "demo_greeting" fn greeting() -> const u8[:] { return "hello-c-host"; }\n'
            'export "demo_bump" fn bump(p: i64&) { p += 5; }\n'
        )
        prog_c = self.work / "prog.c"
        prog_h = self.work / "prog.h"
        emit = subprocess.run([str(COMPILER), "-o", str(prog_c), "--header", str(prog_h), "-O2",
                               "--stdlib", str(SOURCE_STDLIB), str(lib)],
                              stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
        self.assertEqual(emit.returncode, 0, emit.stderr)
        header = prog_h.read_text()
        self.assertIn("void goose_init(int argc, char **argv);", header)
        self.assertIn("void goose_exit(void);", header)
        self.assertIn("int32_t demo_entry(int32_t arg0);", header)
        self.assertIn("const uint8_t *demo_greeting(int64_t *gs_export_len);", header)
        self.assertIn("#define GS_SEPARATE_RUNTIME 1", prog_c.read_text())

        host_c = self.work / "host.c"
        host_c.write_text(
            '#include <stdio.h>\n'
            '#include "prog.h"\n'
            'int32_t c_host_add(int32_t a, int32_t b) { return a + b + 100; }\n'
            'int main(int argc, char **argv) {\n'
            '    goose_init(argc, argv);\n'
            '    int32_t v = demo_entry(7);\n'
            '    int64_t len = 0;\n'
            '    const uint8_t *msg = demo_greeting(&len);\n'
            '    int64_t n = 37;\n'
            '    demo_bump(&n);\n'
            '    printf("v=%d msg=%.*s len=%lld n=%lld\\n", v, (int)len, (const char*)msg, (long long)len, (long long)n);\n'
            '    goose_exit();\n'
            '    goose_init(argc, argv);\n'
            '    int32_t v2 = demo_entry(1);\n'
            '    goose_exit();\n'
            '    printf("v2=%d\\n", v2);\n'
            '    return 0;\n'
            '}\n'
        )
        host_o = self.work / "host.o"
        app = self.work / "host_app"
        subprocess.run([self.cc, "-std=gnu11", "-D_GNU_SOURCE", "-O2", "-pthread", "-c", str(host_c), "-o", str(host_o)],
                       stdin=subprocess.DEVNULL, check=True, capture_output=True, text=True, timeout=60)
        # Link without -rdynamic and without -ldl (Blot2 build.py link shape).
        subprocess.run([self.cc, "-std=gnu11", "-D_GNU_SOURCE", "-O2", "-pthread",
                        str(prog_c), str(host_o), str(rt_o), "-lm", "-o", str(app)],
                       stdin=subprocess.DEVNULL, check=True, capture_output=True, text=True, timeout=60)
        run = subprocess.run([str(app)], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout, "v=124 msg=hello-c-host len=12 n=42\nv2=112\n")

        # --header --standalone embeds the runtime so no runtime object is linked.
        sa_c = self.work / "sa.c"
        sa_h = self.work / "sa.h"
        sa_app = self.work / "sa_app"
        subprocess.run([str(COMPILER), "-o", str(sa_c), "--header", str(sa_h), "--standalone", "-O2",
                        "--stdlib", str(SOURCE_STDLIB), str(lib)],
                       stdin=subprocess.DEVNULL, check=True, capture_output=True, text=True, timeout=60)
        subprocess.run([self.cc, "-std=gnu11", "-D_GNU_SOURCE", "-O2", "-pthread",
                        str(sa_c), str(host_o), "-lm", "-o", str(sa_app)],
                       stdin=subprocess.DEVNULL, check=True, capture_output=True, text=True, timeout=60)
        sa_run = subprocess.run([str(sa_app)], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
        self.assertEqual((sa_run.returncode, sa_run.stdout), (0, run.stdout), sa_run.stderr)

        # Calling an export before goose_init aborts cleanly.
        bad_c = self.work / "bad.c"
        bad_c.write_text('#include "prog.h"\nint32_t c_host_add(int32_t a, int32_t b) { return a + b; }\nint main(void) { return demo_entry(1); }\n')
        bad_app = self.work / "bad_app"
        subprocess.run([self.cc, "-std=gnu11", "-D_GNU_SOURCE", "-O2", "-pthread",
                        str(prog_c), str(bad_c), str(rt_o), "-lm", "-o", str(bad_app)],
                       stdin=subprocess.DEVNULL, check=True, capture_output=True, text=True, timeout=60)
        bad_run = subprocess.run([str(bad_app)], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
        self.assertNotEqual(bad_run.returncode, 0)
        self.assertIn("goose_init must be called before exported functions", bad_run.stderr)

    def test_shared_library_and_option_errors(self):
        src = self.work / "mul.goose"
        src.write_text('export "so_mul" fn mul(a: i64, b: i64) -> i64 { return a * b; }\n')
        so_path = self.work / "libmul.so"
        so_h = self.work / "mul.h"
        built = subprocess.run([str(COMPILER), "--shared", "--header", str(so_h), "--cc", self.cc, "-O2",
                                "--stdlib", str(SOURCE_STDLIB), "-o", str(so_path), str(src)],
                               stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
        self.assertEqual(built.returncode, 0, built.stderr)
        loader_c = self.work / "loader.c"
        loader_c.write_text(
            '#include <stdio.h>\n#include <dlfcn.h>\n#include <stdint.h>\n'
            f'int main(int argc, char **argv) {{\n'
            f'    void *h = dlopen("{so_path}", RTLD_NOW);\n'
            f'    if (!h) return 2;\n'
            f'    void (*init)(int, char**) = dlsym(h, "goose_init");\n'
            f'    void (*fini)(void) = dlsym(h, "goose_exit");\n'
            f'    int64_t (*mul)(int64_t, int64_t) = dlsym(h, "so_mul");\n'
            f'    init(argc, argv);\n'
            f'    printf("%lld\\n", (long long)mul(6, 7));\n'
            f'    fini();\n'
            f'    dlclose(h);\n'
            f'    return 0;\n'
            f'}}\n'
        )
        loader = self.work / "loader"
        subprocess.run([self.cc, "-std=gnu11", "-O2", str(loader_c), "-ldl", "-o", str(loader)],
                       stdin=subprocess.DEVNULL, check=True, capture_output=True, text=True, timeout=60)
        run = subprocess.run([str(loader)], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
        self.assertEqual((run.returncode, run.stdout), (0, "42\n"), run.stderr)

        # Header overwriting source or output is refused, and --header on wasm-direct is refused.
        for extra, expected in (
            (["--header", str(src), "-o", str(self.work / "o.c")], "header would overwrite"),
            (["--header", str(self.work / "same.c"), "-o", str(self.work / "same.c")], "header would overwrite"),
            (["--target", "wasm-direct", "--header", str(self.work / "w.h"), "-o", str(self.work / "w.wasm")], "require the native target"),
        ):
            with self.subTest(extra=extra):
                res = subprocess.run([str(COMPILER), *extra, "--stdlib", str(SOURCE_STDLIB), str(src)],
                                     stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
                self.assertNotEqual(res.returncode, 0)
                self.assertIn(expected, res.stderr)

    def test_native_codegen_regressions(self):
        # Empty slice literals / default<T[:]> fields in recursive functions must
        # not allocate transient regions; generic struct templates with wrapped
        # type params (const T&, U[:]) must not emit non-concrete helpers; and
        # field-only concrete types must be marked used by cc_used_types.
        src = self.work / "regressions.goose"
        src.write_text("""\
struct Scratch {
    storage: i64[:] = default<i64[:]>(),
    items: const u8[:] = default<const u8[:]>(),
}
recursive fn sum_down(n: i64, extra: const i64[:]) -> i64 {
    var empty: i64[:] = default<i64[:]>();
    var scratch = Scratch {..};
    if n <= 0 { return empty.len + scratch.storage.len + extra.len; }
    return n + sum_down(n - 1, default<const i64[:]>());
}
struct GenericBox<T, U> {
    owner: const T&,
    items: const U[:],
    only_field_slice: i16[:] = default<i16[:]>(),
}
fn box_sum<T, U>(owner: const T&, items: const U[:]) -> i64 {
    var box = GenericBox<T, U> { owner, items, .. };
    var total: i64 = (box.owner as i64) + box.items.len + box.only_field_slice.len;
    return total;
}
struct PoolItem { tag: i32 = 0, value: i64 = 0 }
fn unused_const_slice_ref(items: const PoolItem[:]) -> i64 { return items.len; }
reusable[] var pool_items: PoolItem[>..] = [];
let epoch: const u8[:] = "ok";
struct SameNameDefault { epoch: const u8[:] = epoch, count: i64 = 7 }
fn make_same_name() -> SameNameDefault { return SameNameDefault {..}; }
let always_true: bool = true;
let always_false: bool = false;
fn early_check(n: i64) -> bool {
    if n < 0 { return false; }
    if n == 0 { return false; }
    return n > 3;
}
fn folded_inline_exits(n: i64) -> i64 {
    var score: i64 = 0;
    if always_true && early_check(n) { score += 1; }
    if always_false || early_check(n - 5) { score += 2; }
    if always_true { if early_check(n + 1) { score += 4; } }
    return score;
}
fn main() {
    let x: i32 = 17;
    let ys: u16[2] = [3, 4];
    let a = sum_down(5, []);
    let b = box_sum<i32, u16>(x, ys[..]);
    var ps = pool_items.alloc_slice(2);
    ps[0].value = 11;
    ps = pool_items.realloc_slice(ps, 4);
    let c = ps.len + ps[0].value;
    pool_items.free_slice(ps);
    let reply = make_same_name();
    let d = folded_inline_exits(10) * 10 + folded_inline_exits(2);
    print(a, " ", b, " ", c, " ", reply.epoch, " ", d);
}
""")
        c_out = self.work / "regressions.c"
        exe = self.work / "regressions"
        emit = subprocess.run([str(COMPILER), str(src), "--stdlib", str(SOURCE_STDLIB), "--target", "c", "-O2", "-o", str(c_out)],
                              stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
        self.assertEqual(emit.returncode, 0, emit.stderr)
        subprocess.run([self.cc, "-std=gnu11", "-D_GNU_SOURCE", "-O2", "-pthread", str(c_out), "-lm", "-o", str(exe)],
                       stdin=subprocess.DEVNULL, check=True, capture_output=True, text=True, timeout=60)
        run = subprocess.run([str(exe)], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
        self.assertEqual((run.returncode, run.stdout), (0, "15 19 15 ok 70\n"), run.stderr)

        # Field defaults must not resolve to sibling struct fields.
        bad_field_ref = self.work / "bad_field_default.goose"
        bad_field_ref.write_text("struct S { a: i64 = 1, b: i64 = a }\nfn main() { let s = S {..}; print(s.b); }\n")
        bad_check = subprocess.run([str(COMPILER), str(bad_field_ref), "--stdlib", str(SOURCE_STDLIB), "--check"],
                                   stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
        self.assertNotEqual(bad_check.returncode, 0)
        self.assertIn("unknown", bad_check.stderr)


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
        for argv in (("guide", "--list"), ("guide", "rules"), ("guide", "idioms"), ("guide", "--cheatsheet")):
            with self.subTest(argv=argv):
                a, b = self.hosted(*argv), self.native(*argv)
                self.assertEqual((a.returncode, a.stdout, a.stderr), (0, b.stdout, b.stderr))

    def test_locals_are_reused(self):
        # A local for every temporary gave the largest function 23,905 of them
        # and the module 1.37 million; sharing indexes leaves about 1,200 and 96,000.
        counts = declared_locals(self.module)
        self.assertLess(max(counts), 4000)
        self.assertLess(sum(counts), 300000)


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
        command = {"v8": ["node", ROOT / "scripts/run_wasm.mjs"], "wasmtime": [sys.executable, ROOT / "scripts/run_wasmtime.py"], "rust": [RUST_HOST]}[engine]
        return subprocess.run(list(map(str, [*command, module, *arguments])), cwd=ROOT, capture_output=True, stdin=subprocess.DEVNULL)

    def test_examples_print_the_same(self):
        engines = ["v8", "wasmtime"] + (["rust"] if RUST_HOST.is_file() else [])
        for example in ("squares", "sorting", "tour"):
            narrow, wide = self.work / f"{example}.32.wasm", self.work / f"{example}.64.wasm"
            self.emit(f"examples/{example}.goose", narrow)
            self.emit(f"examples/{example}.goose", wide, "--wasm-memory64")
            expected = self.run_module("v8", narrow)
            self.assertEqual(expected.returncode, 0, expected.stderr)
            for engine in engines:
                for module in (narrow, wide) if engine == "rust" else (wide,):
                    with self.subTest(example=example, engine=engine, module=module.name):
                        observed = self.run_module(engine, module)
                        self.assertEqual((observed.returncode, observed.stdout), (0, expected.stdout), observed.stderr)

    def test_local_reuse_across_reference_parameter_edits(self):
        source = self.work / "typed-parameter-locals.goose"
        # The immutable reference can use its incoming parameter directly.
        # The rebound reference needs a cell while the loop keeps differently
        # typed values live across branches, including a v128 slice in memory64.
        source.write_text("""\
fn score(base: const i64&, var cell: i64&, other: i64&, values: i64[:], rebind: bool) -> i64, f64 {
    var total = base + cell;
    var weight = 0.5;
    if rebind { cell .= other; }
    for value in values {
        if (value & 1) == 0 {
            total += value + base;
            weight += (value as f64) / 2.0;
        } else {
            total += cell - value;
            weight -= base as f64;
        }
        cell += value;
    }
    return total, weight;
}
fn main() {
    let base: i64 = 7;
    var first: i64 = 10;
    var second: i64 = 20;
    let values: i64[3] = [2, 3, 4];
    let a, x = score(base, first, second, values[..], true);
    let b, y = score(base, first, second, values[..], false);
    print(a, " ", x, " ", b, " ", y, " ", first, " ", second);
}
""")
        for width, flags in ((32, []), (64, ["--wasm-memory64"])):
            with self.subTest(width=width):
                module = self.work / f"typed-parameter-locals.{width}.wasm"
                self.emit(source, module, *flags)
                observed = self.run_module("wasmtime", module)
                self.assertEqual((observed.returncode, observed.stdout), (0, b"56 -3.5 46 -3.5 19 29\n"), observed.stderr)

    @unittest.skipUnless(RUST_HOST.is_file(), "build the Rust host first: cargo build --release in host/rust")
    def test_rust_host_reports_errors_as_the_python_runner(self):
        source = self.work / "fails.goose"
        source.write_text("fn main() { var a: i64[>..] = []; a.push(1); print(a[0]); print(a[3]); }\n")
        for memory in ([], ["--wasm-memory64"]):
            with self.subTest(memory=memory):
                module = self.work / "fails.wasm"
                self.emit(source, module, *memory)
                first, second = self.run_module("rust", module), self.run_module("wasmtime", module)
                self.assertEqual((first.returncode, first.stdout, first.stderr), (second.returncode, second.stdout, second.stderr))
                self.assertEqual(first.returncode, 1)

    def test_page_limits(self):
        # 65,536 pages is all a 32-bit memory can declare; a 64-bit one takes more.
        refused = subprocess.run(list(map(str, [COMPILER, "examples/squares.goose", "--stdlib", SOURCE_STDLIB, "--target", "wasm-direct",
                                                "--wasm-max-pages", "262144", "-o", self.work / "refused.wasm"])), cwd=ROOT, capture_output=True, text=True)
        self.assertNotEqual(refused.returncode, 0)
        self.emit("examples/squares.goose", self.work / "large.wasm", "--wasm-memory64", "--wasm-max-pages", "262144")
        observed = self.run_module("v8", self.work / "large.wasm")
        self.assertEqual((observed.returncode, observed.stdout), (0, b"sum=140\n"), observed.stderr)

    def test_more_than_32_bits_of_elements(self):
        try:
            available = int(re.search(r"MemAvailable:\s+(\d+)", Path("/proc/meminfo").read_text()).group(1))
        except (OSError, AttributeError):
            available = 0
        if available < 8 * 1024 * 1024:
            self.skipTest("needs 8 GiB of free memory")
        source = self.work / "large.goose"
        source.write_text("""fn main() {
    var a: u8[>..] = [];
    a.resize(4294967296 + 16, 7);
    print(len(a)); print(a[4294967300] as i64);
    a.push(9); a.append("xyz");
    print(len(a)); print(a[4294967313] as i64);
    let tail = a[4294967296..];
    print(len(tail));
}
""")
        # 32 bits of memory cannot hold it and say so; 64 bits do.
        self.emit(source, self.work / "large32.wasm", "--wasm-max-pages", "65535")
        refused = self.run_module("wasmtime", self.work / "large32.wasm")
        self.assertEqual(refused.returncode, 1)
        self.assertIn(b"array length overflow", refused.stderr)
        self.emit(source, self.work / "large64.wasm", "--wasm-memory64", "--wasm-max-pages", "262144")
        observed = self.run_module("wasmtime", self.work / "large64.wasm", "--")
        self.assertEqual((observed.returncode, observed.stdout), (0, b"4294967312\n7\n4294967316\n120\n20\n"), observed.stderr)

    def test_region_profile(self):
        # Eight arrays live at once in 96 pages: an equal share is 699 KB, and
        # one array needs 2 MB. A profile of what each region held, taken where
        # there is room, gives that one the share it needs.
        source = self.work / "uneven.goose"
        source.write_text("""fn main() {
    var a: i64[>..] = []; var b: i64[>..] = []; var c: i64[>..] = []; var d: i64[>..] = [];
    var e: i64[>..] = []; var g: i64[>..] = []; var h: i64[>..] = []; var big: i64[>..] = [];
    for i in 250000 { big.push(i); }
    a.push(1); b.push(2); c.push(3); d.push(4); e.push(5); g.push(6); h.push(7);
    print(len(big) + a[0] + b[0] + c[0] + d[0] + e[0] + g[0] + h[0]);
}
""")
        profile = self.work / "uneven.profile"
        for memory in ([], ["--wasm-memory64"]):
            with self.subTest(memory=memory):
                small = ["--wasm-initial-pages", "1", "--wasm-max-pages", "96", *memory]
                self.emit(source, self.work / "equal.wasm", *small)
                refused = self.run_module("v8", self.work / "equal.wasm")
                self.assertEqual(refused.returncode, 1)
                self.assertIn("data region exhausted", refused.stderr.decode())
                self.emit(source, self.work / "roomy.wasm", "--wasm-max-pages", "1024", "--wasm-region-stats", *memory)
                for engine in ("v8", "wasmtime"):
                    profile.unlink(missing_ok=True)
                    command = ["node", ROOT / "scripts/run_wasm.mjs"] if engine == "v8" else [sys.executable, ROOT / "scripts/run_wasmtime.py"]
                    measured = subprocess.run(list(map(str, [*command, self.work / "roomy.wasm"])), cwd=ROOT, capture_output=True, stdin=subprocess.DEVNULL,
                                              env=dict(__import__("os").environ, GOOSE_REGION_PROFILE=str(profile)))
                    self.assertEqual((measured.returncode, measured.stdout), (0, b"250028\n"), measured.stderr)
                    rows = [tuple(map(int, line.split())) for line in profile.read_text().splitlines()]
                    self.assertEqual(len(rows), 8)
                    self.assertEqual(max(held for _, held in rows), 2000000)
                self.emit(source, self.work / "profiled.wasm", "--wasm-region-profile", profile, *small)
                observed = self.run_module("v8", self.work / "profiled.wasm")
                self.assertEqual((observed.returncode, observed.stdout), (0, b"250028\n"), observed.stderr)

    def test_compiler_compiles_itself(self):
        module, cache = self.work / "goose64.wasm", self.work / "goose64.cwasm"
        options = ["--debug", "--wasm-memory64", "--wasm-region-stats", "--wasm-max-pages", self.PAGES]
        self.emit("selfhost/main.goose", module, *options)
        profile = self.work / "goose64.profile"

        # Under Wasmtime: through the Rust host when it is built, else the Python runner.
        wasmtime_host = [RUST_HOST] if RUST_HOST.is_file() else [sys.executable, ROOT / "scripts/run_wasmtime.py"]

        def hosted(*arguments, **environment):
            command = [*wasmtime_host, module, "--cache", cache, "--", *arguments]
            return subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, stdin=subprocess.DEVNULL,
                                  env=dict(__import__("os").environ, **environment))

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
        result = hosted("selfhost/main.goose", "--stdlib", SOURCE_STDLIB, "--target", "wasm-direct", "-O2", *options, "-o", again,
                        GOOSE_REGION_PROFILE=str(profile))
        self.assertEqual((result.returncode, result.stderr), (0, b""))
        self.assertEqual(again.read_bytes(), module.read_bytes())
        # V8 holds 16 GiB of 64-bit memory: an equal share for each of the
        # compiler's regions is too small for its largest table, the shares of
        # the profile just taken are not. The 32-bit module fits the same way.
        for name, memory in (("v8-64.wasm", ["--wasm-memory64", "--wasm-max-pages", "262144"]), ("v8-32.wasm", ["--wasm-max-pages", "65535"])):
            with self.subTest(module=name):
                self.emit("selfhost/main.goose", self.work / name, *memory, "--wasm-region-profile", profile)
                checked = self.run_module("v8", self.work / name, "--", "selfhost/main.goose", "--stdlib", SOURCE_STDLIB, "--check")
                self.assertEqual((checked.returncode, checked.stdout, checked.stderr), (0, b"", b""))


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class AuditRegressionTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)

    def _compile(self, source: Path, target: str, opt: str, out: Path, *extra: str):
        return subprocess.run(
            list(map(str, [COMPILER, source, "--stdlib", SOURCE_STDLIB, "--target", target, opt, *extra, "-o", out])),
            cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )

    def _run_wasm(self, host: str, module: Path, *extra: str, stdin: bytes = b""):
        if host == "wasmtime":
            command = [sys.executable, ROOT / "scripts/run_wasmtime.py", module, *extra]
        elif host == "v8":
            command = ["node", ROOT / "scripts/run_wasm.mjs", module, *extra]
        elif host == "rust":
            command = [RUST_HOST, module, *extra]
        else:
            raise AssertionError(host)
        return subprocess.run(list(map(str, command)), cwd=ROOT, input=stdin, capture_output=True, timeout=60)

    def test_u64_for_range_and_count_loops(self):
        source = self.work / "u64_loops.goose"
        source.write_text("""\
fn rt_range(lo: u64, hi: u64) -> i64 {
    var c: i64 = 0;
    for i in lo..hi {
        c += 1;
        if c == 3 { break; }
    }
    return c;
}
fn rt_count(n: u64) -> i64 {
    var c: i64 = 0;
    for i in n {
        c += 1;
        if c == 4 { break; }
    }
    return c;
}
fn main() {
    var c1: i64 = 0;
    for i in (0 as u64)..(18446744073709551615 as u64) {
        c1 += 1;
        if c1 == 3 { break; }
    }
    var c2: i64 = 0;
    for i in (18446744073709551613 as u64)..(18446744073709551615 as u64) {
        c2 += 1;
    }
    print(c1, " ", c2, " ", rt_range(0, 18446744073709551615), " ", rt_count(18446744073709551615));
}
""")
        for opt in ("-O0", "-O2"):
            with self.subTest(target="native", opt=opt):
                ran = subprocess.run(
                    list(map(str, [COMPILER, source, "--stdlib", SOURCE_STDLIB, "--target", "native", opt, "--run"])),
                    cwd=self.work, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
                )
                self.assertEqual((ran.returncode, ran.stdout), (0, "3 2 3 4\n"), ran.stderr)
            for tag, flags in (("wasm32", ()), ("wasm64", ("--wasm-memory64",))):
                with self.subTest(target=tag, opt=opt):
                    module = self.work / f"u64_{tag}_{opt}.wasm"
                    built = self._compile(source, "wasm-direct", opt, module, *flags)
                    self.assertEqual(built.returncode, 0, built.stderr)
                    ran = self._run_wasm("wasmtime", module)
                    self.assertEqual((ran.returncode, ran.stdout), (0, b"3 2 3 4\n"), ran.stderr)

    def test_narrow_signed_min_div_neg_one(self):
        source = self.work / "narrow_div.goose"
        source.write_text("""\
fn rt_i8(a: i8, b: i8) -> i8 { return a / b; }
fn rt_i16(a: i16, b: i16) -> i16 { return a / b; }
fn rt_i32(a: i32, b: i32) -> i32 { return a / b; }
fn main() {
    let a: i8 = (-128 as i8) / (-1 as i8);
    let b: i16 = (-32768 as i16) / (-1 as i16);
    let c: i32 = (-2147483648 as i32) / (-1 as i32);
    print(a == (-128 as i8), " ", a, " ", b == (-32768 as i16), " ", b, " ",
          c == (-2147483648 as i32), " ", c, " ",
          rt_i8(-128 as i8, -1 as i8), " ", rt_i16(-32768 as i16, -1 as i16), " ",
          rt_i32(-2147483648 as i32, -1 as i32));
}
""")
        expected = "true -128 true -32768 true -2147483648 -128 -32768 -2147483648\n"
        for opt in ("-O0", "-O2"):
            with self.subTest(target="native", opt=opt):
                ran = subprocess.run(
                    list(map(str, [COMPILER, source, "--stdlib", SOURCE_STDLIB, "--target", "native", opt, "--run"])),
                    cwd=self.work, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
                )
                self.assertEqual((ran.returncode, ran.stdout), (0, expected), ran.stderr)
            with self.subTest(target="wasm-direct", opt=opt):
                module = self.work / f"ndiv_{opt}.wasm"
                built = self._compile(source, "wasm-direct", opt, module)
                self.assertEqual(built.returncode, 0, built.stderr)
                ran = self._run_wasm("wasmtime", module)
                self.assertEqual((ran.returncode, ran.stdout.decode()), (0, expected), ran.stderr)

        debug_src = self.work / "narrow_div_dbg.goose"
        debug_src.write_text("fn main() { let a: i8 = (-128 as i8) / (-1 as i8); print(a); }\n")
        ran_native = subprocess.run(
            list(map(str, [COMPILER, debug_src, "--stdlib", SOURCE_STDLIB, "--target", "native", "--debug", "-O2", "--run"])),
            cwd=self.work, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )
        self.assertNotEqual(ran_native.returncode, 0)
        dbg_wasm = self.work / "narrow_div_dbg.wasm"
        built_dbg = self._compile(debug_src, "wasm-direct", "-O2", dbg_wasm, "--debug")
        self.assertEqual(built_dbg.returncode, 0, built_dbg.stderr)
        ran_wasm = self._run_wasm("wasmtime", dbg_wasm)
        self.assertNotEqual(ran_wasm.returncode, 0)

    def test_invalid_trailing_block_rejected_without_ice(self):
        cases = [
            ("untyped", "fn helper(F) { F(1); }\nfn main() { helper() { x => print(x); } }\n"),
            ("fn_type", "fn helper(f: fn(i64)) { f(1); }\nfn main() { helper() { x => print(x); } }\n"),
        ]
        for name, code in cases:
            source = self.work / f"tb_{name}.goose"
            source.write_text(code)
            for mode in (["--check"], ["--target", "native", "-O2", "-o", str(self.work / f"{name}.c")],
                         ["--target", "wasm-direct", "-O2", "-o", str(self.work / f"{name}.wasm")]):
                with self.subTest(name=name, mode=mode[0]):
                    res = subprocess.run(
                        list(map(str, [COMPILER, source, "--stdlib", SOURCE_STDLIB, *mode])),
                        cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
                    )
                    self.assertEqual(res.returncode, 1, res.stderr)
                    self.assertIn("no overload matches", res.stderr)
                    self.assertNotIn("out of bounds", res.stderr)

    def test_driver_default_run_shared_and_option_diagnostic(self):
        ran = subprocess.run(
            list(map(str, [COMPILER, "examples/squares.goose", "--stdlib", SOURCE_STDLIB, "-o", self.work / "squares.wasm", "--run"])),
            cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual((ran.returncode, ran.stdout), (0, "sum=140\n"), ran.stderr)
        external_cwd = subprocess.run(
            list(map(str, [COMPILER, ROOT / "examples/squares.goose", "--stdlib", SOURCE_STDLIB, "--run"])),
            cwd=self.work, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual((external_cwd.returncode, external_cwd.stdout), (0, "sum=140\n"), external_cwd.stderr)
        isolated = self.work / "isolated_goosew"
        isolated.write_bytes(COMPILER.read_bytes())
        isolated.chmod(0o755)
        missing_host = subprocess.run(
            list(map(str, [isolated, ROOT / "examples/squares.goose", "--stdlib", SOURCE_STDLIB, "--run"])),
            cwd=self.work, env={"PATH": ""}, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(missing_host.returncode, 1)
        self.assertIn("GOOSE_WASM_HOST", missing_host.stderr)
        lib = self.work / "libsq.so"
        shared = subprocess.run(
            list(map(str, [COMPILER, "examples/squares.goose", "--stdlib", SOURCE_STDLIB, "--target", "native", "--shared", "-o", lib])),
            cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(shared.returncode, 0, shared.stderr)
        self.assertTrue(lib.is_file())
        self.assertFalse(Path(str(lib) + ".goose.c").exists())
        bad = subprocess.run(
            list(map(str, [COMPILER, "examples/squares.goose", "--expansion-node-limit", "abc"])),
            cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(bad.returncode, 2)
        self.assertIn("invalid expansion node limit", bad.stderr)

    def test_wasm_hosts_os_externs_resource_dir_and_find_pair(self):
        source = self.work / "os_host_parity.goose"
        source.write_text("""\
import os;
import std;
extern fn raw_find_pair(s: const u8[:], a: const ByteSet&, d: i64, b: const ByteSet&) -> i64 = "gs_find_pair";
fn main() {
    let a = args();
    var line: u8[>..] = [];
    let got_line = read_line(line);
    var rest: u8[>..] = [];
    read_stdin(rest);
    var rdir: u8[>..] = [];
    let has_rdir = resource_dir(rdir);
    let base = a[1];
    var sub: u8[>..] = [];
    sub.append(base); sub.append("/d");
    let mk1 = make_dir(sub[..]);
    let mk2 = make_dir(sub[..]);
    let isd = is_dir(sub[..]);
    var fa: u8[>..] = []; fa.append(sub[..]); fa.append("/b.txt");
    var fb: u8[>..] = []; fb.append(sub[..]); fb.append("/a.txt");
    let wa = write_file_atomic(fa[..], "hello");
    let rn = rename_file(fa[..], fb[..]);
    var listing: u8[>..] = [];
    let ld = list_dir(sub[..], listing);
    var content: u8[>..] = [];
    let rf = read_file(fb[..], content);
    let df = delete_file(fb[..]);
    let dd = delete_dir(sub[..]);
    sleep_ms(1);
    let r1 = random_seed();
    let r2 = random_seed();
    let set_a = byte_set("a");
    let fp_neg = raw_find_pair("abca", set_a, -1, set_a);
    let fp_big = raw_find_pair("abca", set_a, 99, set_a);
    let fp_ok = find_pair("abca", set_a, 3, set_a);
    print(a.len, "|", got_line, "|", line, "|", rest, "|", has_rdir && rdir.len > 0, "|",
          mk1, mk2, isd, wa, rn, ld, rf, df, dd, "|", listing, "|", content, "|", r1 != r2, "|",
          fp_neg, ",", fp_big, ",", fp_ok);
}
""")
        hosts = ["wasmtime", "v8"] + (["rust"] if RUST_HOST.is_file() else [])
        expected = b"2|true|first line|rest!|true|truetruetruetruetruetruetruetruetrue|a.txt\n|hello|true|-1,-1,0\n"
        for tag, flags in (("wasm32", ()), ("wasm64", ("--wasm-memory64",))):
            module = self.work / f"os_{tag}.wasm"
            built = self._compile(source, "wasm-direct", "-O2", module, *flags)
            self.assertEqual(built.returncode, 0, built.stderr)
            for host in hosts:
                with self.subTest(tag=tag, host=host):
                    sub = self.work / f"dir_{tag}_{host}"
                    sub.mkdir()
                    ran = self._run_wasm(host, module, "--", str(sub), stdin=b"first line\r\nrest!")
                    self.assertEqual((ran.returncode, ran.stdout), (0, expected), ran.stderr)

    def test_stdlib_math_json_format_flt_nul_and_read_line(self):
        source = self.work / "stdlib_host_parity.goose"
        source.write_text("""\
import std;
import math;
import json;
import os;
fn main() {
    let a64 = sin(0.5) + cos(0.5) + tan(0.25) + asin(0.5) + acos(0.5) + atan(0.5) + atan2(1.0, 2.0);
    let b64 = exp(1.0) + log(2.0) + log2(8.0) + log10(100.0) + pow(2.0, 3.0) + mul_add(2.0, 3.0, 4.0);
    let r64 = round(0.5) + round(-0.5) + round(-0.4) + round(0.49999999999999994);
    let m64 = 5.5 % 2.0;
    let a32: f32 = sin(0.5 as f32) + cos(0.5 as f32) + tan(0.25 as f32) + asin(0.5 as f32) + acos(0.5 as f32) + atan(0.5 as f32) + atan2(1.0 as f32, 2.0 as f32);
    let b32: f32 = exp(1.0 as f32) + log(2.0 as f32) + log2(8.0 as f32) + log10(100.0 as f32) + pow(2.0 as f32, 3.0 as f32) + mul_add(2.0 as f32, 3.0 as f32, 4.0 as f32);
    let r32: f32 = round(0.5 as f32) + round(-0.5 as f32) + round(-0.4 as f32);
    var rdr = json::reader("12.5");
    let jn = rdr.read_number();
    var jout: u8[>..] = [];
    json::format_number(jout, jn);
    var jsub: u8[>..] = [];
    json::format_number(jsub, 1e-309);
    let _ = trim_memory();
    var f1: u8[>..] = [];
    format_flt(f1, 10000000000000.0, 6);
    var f2: u8[>..] = [];
    format_flt(f2, -0.0, 2);
    var nul_path: u8[>..] = ['a', 0, 'b'];
    var tmp: u8[>..] = [];
    let nr = read_file(nul_path[..], tmp);
    let nw = write_file(nul_path[..], "x");
    let na = write_file_atomic(nul_path[..], "x");
    var pre: u8[>..] = ['A', 13];
    let l1 = read_line(pre);
    let l2 = read_line(pre);
    sleep_ms(-1);
    print(a64 > 4.0 && b64 > 26.0, " ", r64, " ", m64, " ", a32 > (4.0 as f32) && b32 > (26.0 as f32), " ", r32, " ",
          jout, " ", jsub, " ", f1, " ", f2, " ", nr, nw, na, " ", l1, l2, " ", pre.len, " ", pre[1] as i64);
}
""")
        expected = b"true 0.0 1.5 true 0.0 12.5 1e-309 10000000000000.000000 -0.00 falsefalsefalse truefalse 2 13\n"
        c_out = self.work / "stdlib_parity.c"
        ran_nat = subprocess.run(
            list(map(str, [COMPILER, source, "--stdlib", SOURCE_STDLIB, "--target", "native", "-O2", "-o", c_out, "--run"])),
            cwd=self.work, input=b"\n", capture_output=True, timeout=60,
        )
        self.assertEqual((ran_nat.returncode, ran_nat.stdout), (0, expected), ran_nat.stderr)
        self.assertNotIn("static char *g_path", c_out.read_text(encoding="utf-8"))
        hosts = ["wasmtime", "v8"] + (["rust"] if RUST_HOST.is_file() else [])
        for tag, flags in (("wasm32", ()), ("wasm64", ("--wasm-memory64",))):
            module = self.work / f"stdlib_{tag}.wasm"
            built = self._compile(source, "wasm-direct", "-O2", module, *flags)
            self.assertEqual(built.returncode, 0, built.stderr)
            for host in hosts:
                with self.subTest(tag=tag, host=host):
                    ran = self._run_wasm(host, module, stdin=b"\n")
                    self.assertEqual((ran.returncode, ran.stdout), (0, expected), ran.stderr)

    def test_driver_clobber_guards_non_c_run_and_utf8_json(self):
        src = self.work / "dmain.goose"
        src.write_text('export "f" fn f() -> i64 { return 42; }\nfn main() { print(42); }\n')
        rt_clash = subprocess.run(
            list(map(str, [COMPILER, src, "--stdlib", SOURCE_STDLIB, "--target", "native", "--emit-runtime", src, "-o", self.work / "o.c"])),
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(rt_clash.returncode, 1)
        self.assertIn("runtime output would overwrite", rt_clash.stderr)
        self.assertIn("export", src.read_text())

        shared_src = self.work / "libclash.so.goose.c"
        shared_src.write_text('export "f" fn f() -> i64 { return 1; }\n')
        sh_clash = subprocess.run(
            list(map(str, [COMPILER, shared_src, "--stdlib", SOURCE_STDLIB, "--target", "native", "--shared", "-o", self.work / "libclash.so"])),
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(sh_clash.returncode, 1)
        self.assertIn("temporary C output would overwrite", sh_clash.stderr)
        self.assertTrue(shared_src.is_file())

        non_c = subprocess.run(
            list(map(str, [COMPILER, src, "--stdlib", SOURCE_STDLIB, "--target", "native", "-o", self.work / "native.out", "--run"])),
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual((non_c.returncode, non_c.stdout), (0, "42\n"), non_c.stderr)

        bslash = subprocess.run(
            list(map(str, [COMPILER, src, "--stdlib", SOURCE_STDLIB, "--target", "native", "-o", "x\\y.c", "--run"])),
            cwd=self.work, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual((bslash.returncode, bslash.stdout), (0, "42\n"), bslash.stderr)

        bin_src = self.work / "embed_bin.goose"
        bin_src.write_text('let data = embed_file("bin.dat");\nfn main() { print(data.len); }\n')
        (self.work / "bin.dat").write_bytes(b"\xff\xfe\x80\x00hello\xc3\xa9")
        deps = self.work / "deps.json"
        dep_res = subprocess.run(
            list(map(str, [COMPILER, bin_src, "--stdlib", SOURCE_STDLIB, "-o", self.work / "eb.wasm", "--wasm-deps", deps])),
            stdin=subprocess.DEVNULL, capture_output=True, timeout=30,
        )
        self.assertEqual(dep_res.returncode, 0, dep_res.stderr)
        parsed = json.loads(deps.read_bytes().decode("utf-8"))
        self.assertTrue(any(row["path"].endswith("bin.dat") and row["text"] == "\u00ff\u00fe\u0080\u0000hello\u00e9" for row in parsed))

    def test_direct_wasm_batch2_regressions(self):
        source = self.work / "wasm_batch2_regressions.goose"
        source.write_text("""\
import exception;

enum Part { Wheels { sizes: f64[], count: i64 }, Nothing }
struct Cell { v: i64 }
var cells: Cell[>..] = [];
var default_ticks = 0;
fn next_tick() -> i64 { default_ticks += 1; return default_ticks; }
struct Ticket { id: i64 = next_tick() }
struct SNode { key: i64, link: SNode&<u32> }
reusable var gpool: SNode[>..] = [];

fn adapt_limited(a: i64[..]) -> i64 { return a.len * 10 + a[0]; }
fn apply_limited<F>(a: i64[>..]&) -> i64 { return F(copy(a)); }

fn junk_grow() -> i64 {
    var j: i64[>..] = [];
    for i in 8 { j.push(0x7fff00007fff0000); }
    return j[7] & 1;
}

fn local_snode_pool() -> i64 {
    reusable var lp: SNode[>..] = [];
    lp.alloc_index(SNode { key: 1, link: self });
    lp.alloc_index(SNode { key: lp[lp.len - 1].link.key + 1, link: self });
    return lp[1].link.key;
}

fn slice_pool_rebind_one() {
    reusable[] var p: i64[>..] = [];
    let s = p.alloc_slice(4);
    p.free_slice(s);
}

fn slice_pool_rebind_two() -> i64 {
    reusable[] var a: i64[>..] = [];
    reusable[] var b: i64[>..] = [];
    a.push(1);
    let t = b.alloc_slice(3);
    b.free_slice(t);
    var r: i64[>..]& = a;
    r .= b;
    let u = r.alloc_slice(2);
    u[0] = 7; u[1] = 8;
    return a[0] * 100 + b[0] * 10 + b[1];
}

fn stop_now() -> i64 { exception::throw("boom"); }
fn ref_take(a: i64&, b: i64) { assert(false); }

fn main() {
    let p: Part.. = Part.Wheels { count: 4, .. };
    let wcount = match p { Wheels w => w.sizes.len * 10 + w.count, Nothing => -2 };
    var limsrc: i64[>..] = [3, 4];
    let lim = adapt_limited(copy(limsrc)) + apply_limited(limsrc) { x: i64[..] => x.len * 10 + x[1] };
    reusable[] var tickets: Ticket[>..] = [];
    let ts = tickets.alloc_slice(3);
    let tsum = ts[0].id * 100 + ts[1].id * 10 + ts[2].id;
    gpool.alloc_index(SNode { key: 5, link: self });
    gpool.alloc_index(SNode { key: 6, link: self });
    let z = junk_grow();
    let lres = local_snode_pool();
    slice_pool_rebind_one();
    let sres = slice_pool_rebind_two();
    for i in 12 { cells.push(Cell { v: 100 + i }); }
    var relv: (Cell&<varint in cells>)[>..] = [cells[9], cells[10]];
    relv.push(cells[11]);
    var rsum = 0;
    for c in relv { rsum = rsum * 100 + (c.v - 100); }
    var marks = 0;
    var x = 42;
    fn mark() { marks += 1; }
    fn run_ref() { ref_take(if true { mark(); x } else { x }, stop_now()); }
    fn catch_ref(e: const u8[:]) { assert(e == "boom"); marks += 10; }
    exception::try<const u8[:]>(run_ref, catch_ref);
    print(wcount, " ", lim, " ", tsum, " ", z, " ", lres, " ", sres, " ", rsum, " ", marks);
}
""")
        expected = b"4 47 123 0 2 178 91011 11\n"
        for opt in ("-O0", "-O2"):
            for tag, flags in (("w32", ()), ("w64", ("--wasm-memory64",))):
                with self.subTest(opt=opt, tag=tag):
                    module = self.work / f"b2_{tag}_{opt}.wasm"
                    built = self._compile(source, "wasm-direct", opt, module, *flags)
                    self.assertEqual(built.returncode, 0, built.stderr)
                    ran = self._run_wasm("wasmtime", module)
                    self.assertEqual((ran.returncode, ran.stdout), (0, expected), ran.stderr)

    def test_batch3_defer_and_checker_regressions(self):
        reject_cases = [
            (
                "defer_reads_popped_ref",
                """\
fn main() {
    var xs: i64[>..] = [1, 2];
    let r = &xs[1];
    defer { print(r); }
    xs.pop(); xs.push(999);
}
""",
                "array shrink invalidates",
            ),
            (
                "defer_lifo_shrink_before_earlier_read",
                """\
fn main() {
    var xs: i64[>..] = [1, 2];
    let r = &xs[1];
    defer { print(r); }
    defer { xs.pop(); xs.push(888); }
}
""",
                "array shrink invalidates",
            ),
            (
                "defer_nested_block_shrink_before_outer_defer",
                """\
fn main() {
    var xs: i64[>..] = [1, 2];
    let r = &xs[0];
    defer { print(r); }
    { defer { xs.pop(); } }
}
""",
                "array shrink invalidates",
            ),
            (
                "defer_early_return_lifo_shrink",
                """\
fn f(cond: bool) {
    var xs: i64[>..] = [1, 2];
    let r = &xs[0];
    defer { print(r); }
    if cond {
        defer { xs.pop(); }
        return;
    }
}
fn main() { f(true); }
""",
                "array shrink invalidates",
            ),
            (
                "defer_block_tail_ref_invalidated",
                """\
fn main() {
    var xs: i64[>..] = [1, 2];
    let r: i64& .= { defer { xs.clear(); } xs[0] };
    print(r);
}
""",
                "array shrink invalidates",
            ),
            (
                "defer_break_ref_invalidated",
                """\
fn main() {
    var xs: i64[>..] = [1, 2];
    let r: i64& .= block {
        defer { xs.clear(); }
        if xs.len > 0 { break xs[0]; }
        xs[1]
    };
    print(r);
}
""",
                "array shrink invalidates",
            ),
            (
                "defer_return_ref_invalidated",
                """\
fn bad(xs: i64[>..]&) -> i64& {
    defer { xs.clear(); }
    return xs[0];
}
fn main() { var xs: i64[>..] = [1, 2]; print(bad(xs)); }
""",
                "array shrink invalidates",
            ),
            (
                "defer_continue_shrinks_outer_ref",
                """\
fn main() {
    var xs: i64[>..] = [1, 2];
    let r = &xs[0];
    for i in 3 {
        defer { xs.clear(); }
        if i == 0 { continue; }
        print(r);
    }
}
""",
                "array shrink invalidates",
            ),
            (
                "serialize_grow_shrink_refs",
                """\
struct N { v: i64, next: N&<u32>? }
fn load(bytes: u8[:]) -> i64 {
    var a, ok = from_bytes<N[>..<]>(bytes);
    return if ok { a.len } else { -1 };
}
fn main() { print(load("")); }
""",
                "cannot hold relative references",
            ),
            (
                "global_before_init_from_bytes_index",
                """\
type Id = u32 in nodes;
struct Box<T> { value: T }
fn load<T>() -> bool {
    let image: u8[5] = [4, 0, 0, 0, 0];
    let values, ok = from_bytes<T[>..]>(image);
    ok
}
var first = load<Box<Box<Id>>>();
var nodes: i64[>..] = [10];
fn main() { print(first); }
""",
                "before its initialization",
            ),
            (
                "holder_param_inexact_views",
                """\
struct Pair { a: const i32[:], b: const i32[:] }
fn refill(dst: i32[>..]&, p: Pair) {
    dst.clear();
    for x in p.a { dst.push(x); }
    for x in p.b { dst.push(x); }
}
fn main() {
    let xs: i32[] = [1, 2];
    let ys: i32[] = [3];
    var out: i32[>..] = [9];
    refill(out, Pair { a: xs, b: ys });
    print(out.len);
}
""",
                "array shrink invalidates",
            ),
            (
                "holder_param_inexact_views_copy",
                """\
struct Pair { a: const i32[:], b: const i32[:] }
fn refill(dst: i32[>..]&, p: Pair) {
    let q = p;
    dst.clear();
    for x in q.a { dst.push(x); }
}
fn main() {
    let xs: i32[] = [1, 2];
    let ys: i32[] = [3];
    var out: i32[>..] = [9];
    refill(out, Pair { a: xs, b: ys });
    print(out.len);
}
""",
                "array shrink invalidates",
            ),
            (
                "holder_param_inexact_views_slice_read",
                """\
struct Pair { a: const i32[:], b: const i32[:] }
fn refill(dst: i32[>..]&, p: Pair) {
    let s = p.a;
    dst.clear();
    print(s.len);
}
fn main() {
    let xs: i32[] = [1, 2];
    let ys: i32[] = [3];
    var out: i32[>..] = [9];
    refill(out, Pair { a: xs, b: ys });
}
""",
                "array shrink invalidates",
            ),
        ]
        for name, code, snippet in reject_cases:
            with self.subTest(reject=name):
                src = self.work / f"b3_{name}.goose"
                src.write_text(code)
                res = subprocess.run(
                    list(map(str, [COMPILER, src, "--stdlib", SOURCE_STDLIB, "--check"])),
                    stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
                )
                self.assertNotEqual(res.returncode, 0, f"{name} was unexpectedly accepted")
                self.assertIn(snippet, res.stderr)

        accept_cases = [
            (
                "defer_clears_after_read",
                """\
fn main() {
    var xs: i64[>..] = [1, 2];
    let r = &xs[0];
    defer { xs.clear(); }
    print(r);
}
""",
            ),
            (
                "defer_lifo_clear_after_later_read",
                """\
fn main() {
    var xs: i64[>..] = [1, 2];
    let r = &xs[0];
    defer { xs.clear(); }
    defer { print(r); }
}
""",
            ),
            (
                "defer_early_return_dead_after",
                """\
fn f(cond: bool) {
    var xs: i64[>..] = [1, 2];
    let r = &xs[0];
    defer { xs.clear(); }
    if cond { return; }
    print(r);
}
fn main() { f(true); }
""",
            ),
            (
                "defer_continue_loop_local_ref",
                """\
fn main() {
    var xs: i64[>..] = [1, 2];
    for i in 3 {
        if xs.len == 0 { break; }
        let r = &xs[0];
        defer { xs.clear(); }
        if i == 0 { continue; }
        print(r);
    }
}
""",
            ),
            (
                "holder_param_caller_exact_after_put",
                """\
struct Pair { a: const i32[:], b: const i32[:] }
fn put(out: Pair[>..]&, p: Pair) { out.push(p); }
fn main() {
    let xs: i32[] = [1, 2];
    let ys: i32[] = [3];
    var other: i32[>..] = [9];
    var out: Pair[>..] = [];
    put(out, Pair { a: xs, b: ys });
    other.clear();
    print(out[0].a.len);
}
""",
            ),
            (
                "holder_param_out_deeper",
                """\
struct Pair { a: const i32[:], b: const i32[:] }
fn refill(dst: i32[>..]&, p: Pair) {
    dst.clear();
    for x in p.a { dst.push(x); }
}
fn main() {
    let xs: i32[] = [1, 2];
    let ys: i32[] = [3];
    let c = true;
    if c {
        var out: i32[>..] = [9];
        refill(out, Pair { a: xs, b: ys });
        print(out.len);
    }
}
""",
            ),
        ]
        for name, code in accept_cases:
            with self.subTest(accept=name):
                src = self.work / f"b3_ok_{name}.goose"
                src.write_text(code)
                res = subprocess.run(
                    list(map(str, [COMPILER, src, "--stdlib", SOURCE_STDLIB, "--check"])),
                    stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
                )
                self.assertEqual(res.returncode, 0, f"{name} rejected:\n{res.stderr}")


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class ParallelJobsAndPool(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)

    def test_jobs_cli_options(self):
        src = self.work / "main.goose"
        src.write_text("fn main() { print(42); }\n")
        outputs = []
        for args in (["--jobs", "1"], ["--jobs=4"], ["--jobs", "auto"], ["-j", "2"], ["-j=auto"]):
            out = self.work / f"out_{len(outputs)}.wasm"
            res = subprocess.run(
                list(map(str, [COMPILER, src, "--stdlib", STDLIB, *args, "-o", out])),
                stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(res.returncode, 0, f"{args}: {res.stderr}")
            outputs.append(out.read_bytes())
        for blob in outputs[1:]:
            self.assertEqual(blob, outputs[0])
        for bad in (["--jobs", "0"], ["--jobs=0"], ["--jobs", "65"], ["--jobs=abc"], ["-j", "0"]):
            res = subprocess.run(
                list(map(str, [COMPILER, src, "--stdlib", STDLIB, *bad, "--check"])),
                stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(res.returncode, 2, f"expected exit 2 for {bad}, got {res.returncode}: {res.stderr}")
            self.assertIn("--jobs", res.stderr)

    def test_compiler_pool_monolithic_split_and_wasm(self):
        prog = """\
let GP_COMPILER_PARALLEL_MARKER: i64 = 1;
fn gp_native_available() -> bool { return false; }
fn gp_default_jobs() -> i64 { return 1; }
struct Ctx { items: const i64[:] }
struct Out { sum: i64 = 0, scratch_sum: i64 = 0 }
fn gp_parse_range(ctx: const Ctx&, out: Out[:], begin: i64, end: i64) {
    var local: i64[>..] = [];
    for i in begin..end {
        local.clear();
        let x = ctx.items[i];
        var s: i64 = 0;
        for k in 0..8 {
            let v = (x * 13 + k * 7) ^ (i * 3);
            local.push(v);
            s += v;
        }
        var check: i64 = 0;
        for v in local { check += v; }
        out[i].sum = s;
        out[i].scratch_sum = check;
    }
}
fn gp_parse_dispatch(jobs: i64, ctx: const Ctx&, out: Out[:]) -> bool {
    gp_parse_range(ctx, out, 0, out.len);
    return true;
}
fn main() {
    if GP_COMPILER_PARALLEL_MARKER == 0 { return; }
    var items: i64[>..] = [];
    var outs: Out[>..] = [];
    for i in 0..256 { items.push(i * 17 + 5); outs.push(Out {}); }
    let ctx = Ctx { items: items };
    let jobs = if gp_native_available() { 8 } else { 1 };
    let ok = gp_parse_dispatch(jobs, ctx, outs);
    var total: i64 = 0;
    var ok_all = ok && gp_default_jobs() >= 1;
    for o in outs {
        if o.sum != o.scratch_sum { ok_all = false; }
        total += o.sum;
    }
    print(if ok_all { total } else { -1 });
}
"""
        src = self.work / "pool_test.goose"
        src.write_text(prog)
        c_file = self.work / "pool_test.c"
        wasm_file = self.work / "pool_test.wasm"
        res_c = subprocess.run(
            list(map(str, [COMPILER, src, "--stdlib", STDLIB, "--target", "native", "-O2", "-o", c_file])),
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(res_c.returncode, 0, res_c.stderr)
        c_text = c_file.read_text()
        self.assertIn("g_cpool_init(", c_text)
        self.assertIn("g_cpool_run(", c_text)
        self.assertIn("g_cpool_thunk_", c_text)

        # Monolithic native build & run
        cc = __import__("os").environ.get("CC", "clang")
        mono_bin = self.work / "pool_mono"
        flags = ["-std=gnu11", "-O2", "-lm", "-ldl", "-pthread"]
        if sys.platform == "darwin":
            flags = ["-std=gnu11", "-O2", "-lm", "-lpthread"]
        elif sys.platform == "win32":
            flags = ["-std=gnu11", "-O2", "-lm"]
        comp = subprocess.run([cc, flags[0], flags[1], str(c_file), *flags[2:], "-o", str(mono_bin)],
                              stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
        self.assertEqual(comp.returncode, 0, comp.stderr)
        run_mono = subprocess.run([str(mono_bin)], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
        self.assertEqual(run_mono.returncode, 0, run_mono.stderr)
        expected = run_mono.stdout.strip()
        self.assertNotEqual(expected, "-1")
        self.assertTrue(expected.lstrip("-").isdigit(), repr(expected))

        # Split-unit native build (3 units + runtime unit) & run
        marker = "\n#else /* program units */\n"
        cut = c_text.find(marker)
        self.assertGreater(cut, 0)
        rt_c = self.work / "rt.c"
        rt_c.write_text(c_text[:cut + 1] + "#endif\n")
        objs = [self.work / "rt.o"]
        r = subprocess.run([cc, flags[0], flags[1], "-DG_RUNTIME_UNIT", "-c", str(rt_c), "-o", str(objs[0])],
                           stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stderr)
        for u in range(3):
            obj = self.work / f"u{u}.o"
            objs.append(obj)
            r = subprocess.run([cc, flags[0], flags[1], "-DG_UNITS=3", f"-DG_UNIT={u}", "-c", str(c_file), "-o", str(obj)],
                               stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
            self.assertEqual(r.returncode, 0, r.stderr)
        split_bin = self.work / "pool_split"
        r = subprocess.run([cc, flags[0], flags[1], *map(str, objs), *flags[2:], "-o", str(split_bin)],
                           stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stderr)
        run_split = subprocess.run([str(split_bin)], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
        self.assertEqual((run_split.returncode, run_split.stdout.strip()), (0, expected), run_split.stderr)

        # Direct Wasm build & run (single-threaded fallback, zero extra imports)
        res_w = subprocess.run(
            list(map(str, [COMPILER, src, "--stdlib", STDLIB, "--target", "wasm-direct", "-O2", "-o", wasm_file])),
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(res_w.returncode, 0, res_w.stderr)
        if RUST_HOST.is_file():
            run_w = subprocess.run([str(RUST_HOST), str(wasm_file)], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
            self.assertEqual((run_w.returncode, run_w.stdout.strip()), (0, expected), run_w.stderr)

    def test_compiler_spmd_barrier_grow_and_multifile_determinism(self):
        prog = """\
let GP_COMPILER_PARALLEL_MARKER: i64 = 1;
fn gp_native_available() -> bool { return false; }
fn gp_barrier() {}
fn gp_grow_i64(arr: i64[>..]&, new_len: i64) {
    while arr.len < new_len { arr.push(0); }
}
struct SpmdCtx {
    counts: i64[>..]&,
    offsets: i64[>..]&,
    dest: i64[>..]&,
    total: i64&,
}
fn gp_parse_spmd_range(ctx: const SpmdCtx&, out: i64[:], worker_id: i64, worker_count: i64) {
    let n = out.len;
    let items: i64 = 16;
    ctx.counts[worker_id] = items;
    gp_barrier();
    if worker_id == 0 {
        var acc: i64 = 0;
        for w in 0..worker_count {
            ctx.offsets[w] = acc;
            acc += ctx.counts[w];
        }
        gp_grow_i64(ctx.dest, acc);
        ctx.total = acc;
    }
    gp_barrier();
    let base = ctx.offsets[worker_id];
    var local_sum: i64 = 0;
    for k in 0..items {
        let v = (worker_id + 1) * 100 + k * 7;
        ctx.dest[base + k] = v;
        local_sum += v;
    }
    if worker_id < n { out[worker_id] = local_sum; }
}
fn gp_parse_spmd_dispatch(jobs: i64, ctx: const SpmdCtx&, out: i64[:]) -> bool {
    gp_parse_spmd_range(ctx, out, 0, 1);
    return true;
}
fn main() {
    if GP_COMPILER_PARALLEL_MARKER == 0 { return; }
    let participants: i64 = if gp_native_available() { 4 } else { 1 };
    var counts: i64[>..] = []; counts.resize(participants, 0);
    var offsets: i64[>..] = []; offsets.resize(participants, 0);
    var dest: i64[>..] = [];
    var slots: i64[>..] = []; slots.resize(participants, 0);
    var total: i64 = 0;
    let ctx = SpmdCtx { counts: counts, offsets: offsets, dest: dest, total: total };
    let ok = gp_parse_spmd_dispatch(participants, ctx, slots[..]);
    var sum_dest: i64 = 0;
    for v in dest { sum_dest += v; }
    var sum_slots: i64 = 0;
    for s in slots { sum_slots += s; }
    print(if ok && dest.len == total && sum_dest == sum_slots && total == participants * 16 { 1 } else { 0 });
}
"""
        src = self.work / "spmd_test.goose"
        src.write_text(prog)
        c_file = self.work / "spmd_test.c"
        wasm_file = self.work / "spmd_test.wasm"
        res_c = subprocess.run(
            list(map(str, [COMPILER, src, "--stdlib", STDLIB, "--target", "native", "-O2", "-o", c_file])),
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(res_c.returncode, 0, res_c.stderr)
        c_text = c_file.read_text()
        self.assertIn("g_cpool_run_spmd(", c_text)
        self.assertIn("g_cpool_barrier(", c_text)
        self.assertIn("g_cpool_grow_array(", c_text)

        cc = __import__("os").environ.get("CC", "clang")
        flags = ["-std=gnu11", "-O2", "-lm", "-ldl", "-pthread"]
        if sys.platform == "darwin":
            flags = ["-std=gnu11", "-O2", "-lm", "-lpthread"]
        elif sys.platform == "win32":
            flags = ["-std=gnu11", "-O2", "-lm"]

        mono_bin = self.work / "spmd_mono"
        r = subprocess.run([cc, flags[0], flags[1], str(c_file), *flags[2:], "-o", str(mono_bin)],
                           stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stderr)
        run_mono = subprocess.run([str(mono_bin)], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
        self.assertEqual((run_mono.returncode, run_mono.stdout.strip()), (0, "1"), run_mono.stderr)

        # Direct Wasm fallback (single-threaded, zero extra imports)
        res_w = subprocess.run(
            list(map(str, [COMPILER, src, "--stdlib", STDLIB, "--target", "wasm-direct", "-O2", "-o", wasm_file])),
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(res_w.returncode, 0, res_w.stderr)
        if RUST_HOST.is_file():
            run_w = subprocess.run([str(RUST_HOST), str(wasm_file)], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
            self.assertEqual((run_w.returncode, run_w.stdout.strip()), (0, "1"), run_w.stderr)

        # Multi-file bit-identity across --jobs 1, 4, 8, auto (Wasm + Native C)
        mf = self.work / "multifile"
        mf.mkdir()
        (mf / "shared.goose").write_text("struct Pair { a: i64, b: i64 }\n")
        imports = ["import shared;"]
        calls = []
        for idx in range(6):
            mod = f"m{idx}"
            imports.append(f"import {mod};")
            fns = ["import shared;"]
            for f in range(12):
                fns.append(
                    f"fn f_{idx}_{f}(x: i64) -> i64 {{\n"
                    f"    let p = Pair {{ a: x + {f}, b: x ^ {idx + 1} }};\n"
                    f"    var acc: i64 = p.a * 3 + p.b;\n"
                    f"    for i in 0..4 {{ acc += (i + x) & 15; }}\n"
                    f"    return acc;\n"
                    f"}}\n"
                )
            (mf / f"{mod}.goose").write_text("\n".join(fns))
            calls.append(f"    acc += f_{idx}_0(acc); acc += f_{idx}_11(acc);")
        (mf / "main.goose").write_text(
            "\n".join(imports) + "\nfn main() {\n    var acc: i64 = 7;\n" + "\n".join(calls) + "\n    print(acc);\n}\n"
        )
        for target, ext in (("wasm-direct", "wasm"), ("native", "c")):
            outputs = []
            for j in ("1", "4", "8", "auto"):
                out = self.work / f"mf_{target}_{j}.{ext}"
                r = subprocess.run(
                    list(map(str, [COMPILER, mf / "main.goose", "--stdlib", STDLIB, "--target", target, "-O2", "--jobs", j, "-o", out])),
                    stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
                )
                self.assertEqual(r.returncode, 0, f"{target} j={j}: {r.stderr}")
                outputs.append(out.read_bytes())
            for blob in outputs[1:]:
                self.assertEqual(blob, outputs[0], f"{target} output differed across --jobs")


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class GuideCommand(unittest.TestCase):
    """`goosew guide` prints a built-in version-matched cheatsheet and focused topic sections."""

    TOPICS = {
        "rules": "## 1. Top Rules",
        "types": "## 2. Scalars, Casts, Arrays, Slices & Strings",
        "structs": "## 3. Structs, `root struct`, Enums & `match`",
        "refs": "## 4. References, Optionals, Lifetimes & Memory Model",
        "control": "## 5. Functions, Control Flow, Generics & Modules",
        "stdlib": "## 6. Standard Library (`--stdlib`)",
        "cli": "## 7. `goosew` CLI Workflows",
        "idioms": "## Idiomatic Goose Patterns",
    }

    DEFAULT_TOPICS = ("rules", "types", "structs", "refs", "control", "stdlib", "cli")

    def run_goosew(self, *args, cwd=ROOT):
        return subprocess.run(
            list(map(str, [COMPILER, *args])),
            cwd=cwd,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=30,
        )

    def test_default_and_cheatsheet_match_and_include_version(self):
        version_line = self.run_goosew("--version").stdout.strip()
        version_token = version_line.split()[1]
        default = self.run_goosew("guide")
        cheatsheet = self.run_goosew("guide", "--cheatsheet")
        all_topic = self.run_goosew("guide", "all")
        self.assertEqual((default.returncode, default.stderr), (0, ""))
        self.assertEqual(default.stdout, cheatsheet.stdout)
        self.assertEqual(default.stdout, all_topic.stdout)
        self.assertIn(version_token, default.stdout)
        self.assertIn("Unqualified modules", default.stdout)
        self.assertIn("os::read_file", default.stdout)
        self.assertIn("import` never opens a namespace", default.stdout)
        self.assertIn("No `if let` in Goose", default.stdout)
        self.assertIn("json::Node[>..]", default.stdout)
        self.assertIn("cur .= cur.next", default.stdout)
        self.assertIn("starts_with", default.stdout)
        self.assertIn("variable-size structs cannot be indexed", default.stdout)
        self.assertIn("goosew guide idioms", default.stdout)
        for topic in self.DEFAULT_TOPICS:
            self.assertIn(self.TOPICS[topic], default.stdout)
        idioms = self.run_goosew("guide", "idioms")
        self.assertEqual((idioms.returncode, idioms.stderr), (0, ""))
        self.assertIn("## Idiomatic Goose Patterns", idioms.stdout)
        self.assertIn("guard ok else", idioms.stdout)
        self.assertIn("each_step<F>", idioms.stdout)
        self.assertIn("slot_pool<T>", idioms.stdout)
        self.assertIn("from_bytes", idioms.stdout)

    def test_topics_list_help_and_errors(self):
        listed = self.run_goosew("guide", "--list")
        self.assertEqual((listed.returncode, listed.stderr), (0, ""))
        for topic, heading in self.TOPICS.items():
            self.assertIn(topic, listed.stdout)
            one = self.run_goosew("guide", topic)
            self.assertEqual((one.returncode, one.stderr), (0, ""))
            self.assertIn(heading, one.stdout)
            for other_topic, other_heading in self.TOPICS.items():
                if other_topic != topic:
                    self.assertNotIn(other_heading, one.stdout)

        helped = self.run_goosew("guide", "--help")
        self.assertEqual((helped.returncode, helped.stderr), (0, ""))
        self.assertIn("goosew guide --cheatsheet", helped.stdout)
        self.assertIn("goosew guide --list", helped.stdout)

        main_help = self.run_goosew("--help")
        self.assertEqual(main_help.returncode, 0)
        self.assertIn("goosew guide", main_help.stdout)

        unknown = self.run_goosew("guide", "nonexistent")
        self.assertEqual(unknown.returncode, 2)
        self.assertIn("unknown topic", unknown.stderr)
        self.assertIn("goosew guide --list", unknown.stderr)

        too_many = self.run_goosew("guide", "rules", "types")
        self.assertEqual(too_many.returncode, 2)
        self.assertIn("at most one topic", too_many.stderr)

    def test_guide_source_filename_still_compiles(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            (work / "guide.goose").write_text("fn main() { print(42); }\n")
            res = self.run_goosew("guide.goose", "--stdlib", SOURCE_STDLIB, "--check", cwd=work)
            self.assertEqual((res.returncode, res.stderr), (0, ""))


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class AotAndRunnerCliTests(unittest.TestCase):
    """CLI --target aot-x64|aot-aarch64 and --runner selection."""

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)
        self.src = self.work / "prog.goose"
        self.src.write_text(
            "fn main() {\n"
            "    var s: i64 = 0;\n"
            "    for i in 1..11 { s += i * i; }\n"
            "    print(s);\n"
            "}\n"
        )

    def test_invalid_target_and_runner_rejected(self):
        bad_t = subprocess.run(
            [str(COMPILER), str(self.src), "--stdlib", str(SOURCE_STDLIB), "--target", "bogus"],
            stdin=subprocess.DEVNULL, capture_output=True, text=True,
        )
        self.assertEqual(bad_t.returncode, 2)
        self.assertIn("aot-x64", bad_t.stderr)

        bad_r = subprocess.run(
            [str(COMPILER), str(self.src), "--stdlib", str(SOURCE_STDLIB), "--runner=bogus"],
            stdin=subprocess.DEVNULL, capture_output=True, text=True,
        )
        self.assertEqual(bad_r.returncode, 2)
        self.assertIn("wtime-aot", bad_r.stderr)

    def test_runner_modes_with_wasm_direct(self):
        available = [
            ("winch", ROOT / "host/rust/target/release/goose-wasmtime"),
            ("wasmtime", ROOT / "host/rust/target/release/goose-wasmtime"),
            ("wtime-aot", ROOT / "host/wtime-aot/target/release/goose-wtime-aot"),
            ("wtime-aot-fast", ROOT / "host/wtime-aot/target/release/goose-wtime-aot"),
            ("wtime", ROOT / "host/wtime/target/release/goose-wtime"),
        ]
        for mode, binary in available:
            if not binary.is_file():
                continue
            with self.subTest(runner=mode):
                out = self.work / f"prog_{mode}.wasm"
                res = subprocess.run(
                    [
                        str(COMPILER), str(self.src), "--stdlib", str(SOURCE_STDLIB),
                        "-O2", "-o", str(out), "--run", "--runner", mode,
                    ],
                    cwd=self.work,
                    stdin=subprocess.DEVNULL,
                    capture_output=True,
                    text=True,
                    timeout=30,
                )
                self.assertEqual((res.returncode, res.stdout.strip()), (0, "385"), res.stderr)

        # Node runner from a temp cwd (verifies scripts/run_wasm.mjs lookup via resource_dir)
        out_node = self.work / "prog_node.wasm"
        res_node = subprocess.run(
            [
                str(COMPILER), str(self.src), "--stdlib", str(SOURCE_STDLIB),
                "-O2", "-o", str(out_node), "--run", "--runner=node",
            ],
            cwd=self.work,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual((res_node.returncode, res_node.stdout.strip()), (0, "385"), res_node.stderr)

    def test_aot_x64_and_aarch64_targets(self):
        aot_bin = ROOT.parent / "wtime/tools/wtime-aot/target/release/wtime-aot"
        if not aot_bin.is_file():
            self.skipTest("wtime-aot binary not built")
        # Build + run x64 static ELF for both wasm32 and wasm64
        for mem64, name in ((False, "prog_x64_32"), (True, "prog_x64_64")):
            out = self.work / name
            cmd = [
                str(COMPILER), str(self.src), "--stdlib", str(SOURCE_STDLIB),
                "--target", "aot-x64", "-O2", "-o", str(out), "--run",
            ]
            if mem64:
                cmd.append("--wasm-memory64")
            res = subprocess.run(
                cmd, cwd=self.work, stdin=subprocess.DEVNULL,
                capture_output=True, text=True, timeout=30,
            )
            self.assertEqual((res.returncode, res.stdout.strip()), (0, "385"), res.stderr)
            hdr = out.read_bytes()[:20]
            self.assertEqual(hdr[:4], b"\x7fELF")
            self.assertEqual(int.from_bytes(hdr[18:20], "little"), 62)  # EM_X86_64
            self.assertFalse((self.work / f"{name}.goose.wasm").exists())

        # Cross-compile AArch64 static ELF directly from Goose (zero Clang)
        arm_out = self.work / "prog_arm64"
        res_arm = subprocess.run(
            [
                str(COMPILER), str(self.src), "--stdlib", str(SOURCE_STDLIB),
                "--target=aot-aarch64", "--wasm-memory64", "-O2", "-o", str(arm_out),
            ],
            cwd=self.work, stdin=subprocess.DEVNULL,
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(res_arm.returncode, 0, res_arm.stderr)
        hdr = arm_out.read_bytes()[:20]
        self.assertEqual(hdr[:4], b"\x7fELF")
        self.assertEqual(int.from_bytes(hdr[18:20], "little"), 183)  # EM_AARCH64
        self.assertFalse((self.work / "prog_arm64.goose.wasm").exists())


@unittest.skipUnless(COMPILER.is_file() and RUST_HOST.is_file(), "bootstrap compiler and Rust host required")
class WasmCodegenAndBceTests(unittest.TestCase):
    """Correctness and soundness regressions for direct-Wasm codegen, peephole, and BCE passes."""

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)

    def build_and_run(self, name, source, opt="-O2", extra_args=()):
        src = self.work / f"{name}.goose"
        out = self.work / f"{name}_{opt.lstrip('-')}.wasm"
        src.write_text(source)
        res = subprocess.run(
            [str(COMPILER), str(src), "--stdlib", str(SOURCE_STDLIB), opt, *extra_args, "-o", str(out)],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(res.returncode, 0, res.stderr)
        run = subprocess.run(
            [str(RUST_HOST), str(out)],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
        )
        return out, run

    def test_const_divmod_and_shifts_edge_cases(self):
        src = """
fn run_signed(a: i64) -> i64 {
    var x = a;
    let q1 = a / 1;
    let r1 = a % 1;
    let q2 = a / 2;
    let r2 = a % 2;
    let q8 = a / 8;
    let r8 = a % 8;
    let q9 = a / 9;
    let r9 = a % 9;
    x /= 3;
    var y = a;
    y %= 7;
    print(q1, " ", r1, " ", q2, " ", r2, " ", q8, " ", r8, " ", q9, " ", r9, " ", x, " ", y);
    return (q1 / 16) + r1 * 3 + (q2 / 8) + r2 * 5 + (q8 / 4) + r8 * 11 + (q9 / 4) + r9 * 13 + (x / 8) + y * 17;
}
fn run_small(a: i8, b: u8, c: i16, d: u16, e: i32, f: u32, g: u64) -> i64 {
    let s1 = (a / 3) as i64 + (a % 3) as i64 + (a % 4) as i64;
    let s2 = (b / 3) as i64 + (b % 3) as i64 + (b / 4) as i64 + (b % 4) as i64;
    let s3 = (c / 5) as i64 + (c % 5) as i64 + (c % 8) as i64;
    let s4 = (d / 7) as i64 + (d % 7) as i64 + (d / 8) as i64;
    let s5 = (e / 9) as i64 + (e % 9) as i64 + (e % 16) as i64;
    let s6 = (f / 9) as i64 + (f % 9) as i64 + (f / 16) as i64;
    let s7 = ((g / 9) + (g % 9) + (g / 8) + (g % 8)) as i64;
    let sh = ((a << 11) as i64) + ((b >> 11) as i64) + ((e << 35) as i64) + ((g >> 67) as i64);
    return s1 + s2 + s3 + s4 + s5 + s6 + s7 + sh;
}
fn main() {
    let min64: i64 = -9223372036854775807 - 1;
    let vals: i64[9] = [0, 1, -1, 7, -7, -8, -9, -10, min64];
    for v in vals { print(run_signed(v)); }
    print(run_small((-128) as i8, 250 as u8, (-32768) as i16, 65000 as u16, (-2147483647 - 1) as i32, 4000000000 as u32, 1000000000000 as u64));
    // Non-negative proven constant div/mod in a loop
    var acc: i64 = 0;
    for i in 0..81 { acc += (i / 9) * 100 + (i % 9) + (i / 8) + (i % 8); }
    print(acc);
}
"""
        _, r0 = self.build_and_run("divmod", src, "-O0")
        out2, r2 = self.build_and_run("divmod", src, "-O2")
        _, rdbg = self.build_and_run("divmod_dbg", src, "-O2", ("--debug",))
        self.assertEqual(r0.returncode, 0, r0.stderr)
        self.assertEqual((r2.returncode, r2.stdout), (0, r0.stdout), r2.stderr)
        self.assertEqual((rdbg.returncode, rdbg.stdout), (0, r0.stdout), rdbg.stderr)
        if __import__("shutil").which("wasm2wat"):
            wat = subprocess.check_output(["wasm2wat", str(out2)], text=True)
            self.assertIn("i64.div_u", wat)
            self.assertIn("i64.rem_u", wat)

    def test_direct_br_if_and_defer_safety(self):
        src = """
fn with_defer() -> i64 {
    var acc: i64 = 0;
    var i: i64 = 0;
    while i < 10 {
        defer { acc += 100; }
        i += 1;
        if i == 3 { continue; }
        if i == 6 { break; }
        acc += i;
    }
    return acc;
}
fn clean_branches() -> i64 {
    var acc: i64 = 0;
    for i in 0..20 {
        guard i % 2 == 0 else { continue; }
        if i > 12 { break; }
        if i == 4 { continue; } else { acc += i; }
    }
    return acc;
}
fn main() {
    print(with_defer(), " ", clean_branches());
}
"""
        _, r0 = self.build_and_run("brif", src, "-O0")
        _, r2 = self.build_and_run("brif", src, "-O2")
        self.assertEqual(r0.returncode, 0, r0.stderr)
        self.assertEqual((r2.returncode, r2.stdout), (0, r0.stdout), r2.stderr)
        # defer runs on all 6 iterations (600) + i in {1,2,4,5} (12) = 612;
        # clean_branches sums even i <= 12 except 4: 0+2+6+8+10+12 = 38.
        self.assertEqual(r2.stdout.strip(), "612 38")

    def test_const_fixed_scalar_arrays_data_copy(self):
        src = """
let G_I64: i64[6] = [-10, -1, 0, 1, 42, 999999999999];
let G_U8: u8[6] = [0, 1, 127, 128, 254, 255];
let G_F64: f64[4] = [-1.5, 0.0, 2.25, 100.5];
let G_F32: f32[4] = [-0.5, 0.0, 1.5, 3.25];
let G_BOOL: bool[4] = [true, false, true, true];
fn main() {
    let loc: i16[5] = [-300, -1, 0, 1, 300];
    var sum: i64 = 0;
    for x in G_I64 { sum += x; }
    for x in G_U8 { sum += x as i64; }
    for x in loc { sum += x as i64; }
    for x in G_BOOL { if x { sum += 1; } }
    let fsum = G_F64[0] + G_F64[1] + G_F64[2] + G_F64[3] + (G_F32[0] + G_F32[2] + G_F32[3]) as f64;
    print(sum, " ", (fsum * 4.0) as i64);
}
"""
        out0, r0 = self.build_and_run("constarr", src, "-O0")
        out2, r2 = self.build_and_run("constarr", src, "-O2")
        _, rdbg = self.build_and_run("constarr_dbg", src, "-O2", ("--debug",))
        self.assertEqual((r0.returncode, r0.stdout.strip()), (0, "1000000000799 422"), r0.stderr)
        self.assertEqual((r2.returncode, r2.stdout), (0, r0.stdout), r2.stderr)
        self.assertEqual((rdbg.returncode, rdbg.stdout), (0, r0.stdout), rdbg.stderr)
        if __import__("shutil").which("wasm2wat"):
            wat = subprocess.check_output(["wasm2wat", str(out2)], text=True)
            self.assertIn("memory.copy", wat)

    def test_bce_soundness_overflow_and_le_only(self):
        # 1. `i * i <= 1000` starting from `i = 4000000000` overflows i64 to negative;
        #    bounds check on `flags[i]` MUST NOT be eliminated and must trap.
        overflow_src = """
fn main() {
    var flags: u8[>..] = [];
    flags.resize(1001, 1);
    var i: i64 = 4000000000;
    while i * i <= 1000 {
        flags[i] = 0;
        i += 1;
    }
    print(flags[0]);
}
"""
        _, r_ovf = self.build_and_run("bce_sq_ovf", overflow_src, "-O2")
        self.assertNotEqual(r_ovf.returncode, 0)
        self.assertIn("out of bounds", r_ovf.stderr)

        # 2. `let mid = xs.len / 2;` has `le_only = true`: `xs[mid - 1]` when `xs.len == 1`
        #    evaluates `xs[-1]` and MUST trap (must not be misproved as `xs[xs.len - 1]`).
        le_only_src = """
fn bad(xs: i32[:]) -> i32 {
    if xs.len >= 1 {
        let mid = xs.len / 2;
        return xs[mid - 1];
    }
    return 0;
}
fn main() {
    var a: i32[1] = [7];
    print(bad(a[..]));
}
"""
        _, r_le = self.build_and_run("bce_le_only", le_only_src, "-O2")
        self.assertNotEqual(r_le.returncode, 0)
        self.assertIn("out of bounds", r_le.stderr)


if __name__ == "__main__":
    unittest.main()
