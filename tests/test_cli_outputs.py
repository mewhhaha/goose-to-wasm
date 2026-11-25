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
COMPILER = Path(__import__('os').environ.get('GOOSE_COMPILER', ROOT / 'build/bin/goose'))
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


if __name__ == "__main__":
    unittest.main()
