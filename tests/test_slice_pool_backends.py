#!/usr/bin/env python3
"""The slice pool's span tree externs lower to both native C and direct Wasm.

stdlib/slice_pool_internal.goose declares runtime externs (gs_slice_pool_*)
that take node[>..]& and tree& references. Native C calls native/slice_pool.h,
and the direct Wasm backend lowers them to internal checked 512-byte B+ span
tree helpers with zero extra host imports.
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
COMPILER = Path(os.environ.get('GOOSE_COMPILER', ROOT / 'build/bin/goosew')).resolve()
STDLIB = ROOT / "stdlib"
SOURCE = ROOT / "tests/fixtures/contracts/slice-pool/direct_externs.goose"
SPANS = ROOT / "tests/fixtures/contracts/slice-pool/spans.goose"
TRIM = ROOT / "tests/fixtures/contracts/slice-pool/trim.goose"
CORRUPT = ROOT / "tests/fixtures/contracts/slice-pool/corrupt_tree.goose"


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class SlicePoolBackends(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)

    def compile(self, target, *arguments, source=SOURCE):
        command = [COMPILER, source, "--target", target, "-O2", "--stdlib", STDLIB, *arguments]
        return subprocess.run(list(map(str, command)), cwd=self.work, capture_output=True, text=True)

    def engines(self, wasm):
        if shutil.which("node"):
            yield "V8", ["node", ROOT / "scripts/run_wasm.mjs", wasm]
        if importlib.util.find_spec("wasmtime") is not None:
            yield "Wasmtime", [sys.executable, ROOT / "scripts/run_wasmtime.py", wasm]

    def test_wasm_direct_emits_and_runs_slice_pool_externs(self):
        checked = self.compile("wasm-direct", "--check")
        self.assertEqual(checked.returncode, 0, checked.stderr)
        cases = (
            ("direct_externs", SOURCE, 0, "2 1 0 1\n0 1 0\n4\n", None),
            ("spans", SPANS, 0, "0 [0, 0] 9\n2 10 8\n2 12\n13 0 0 0 1\n18 [103, 104, 105]\n2 4 [0, 0, 0]\n0 21 21\ntrue true\n99 799\n0 799 1\n", None),
            ("trim", TRIM, 0, "true\ntrue true\ntrue true true 0\n5000 true\n", None),
            ("corrupt", CORRUPT, "nonzero", "1 3\n", "slice pool span tree is corrupt (line 7)"),
        )
        for name, src, exp_rc, exp_out, exp_err in cases:
            for tag, flags in (("O0", ("-O0",)), ("O2", ("-O2",)), ("mem64", ("--wasm-memory64", "-O2"))):
                wasm = self.work / f"{name}-{tag}.wasm"
                command = [COMPILER, src, "--target", "wasm-direct", "--stdlib", STDLIB, *flags, "-o", wasm]
                emitted = subprocess.run(list(map(str, command)), cwd=self.work, capture_output=True, text=True)
                self.assertEqual(emitted.returncode, 0, f"{name} {tag}: {emitted.stderr}")
                self.assertTrue(wasm.is_file())
                for engine, run_cmd in self.engines(wasm):
                    with self.subTest(case=name, mode=tag, engine=engine):
                        ran = subprocess.run(list(map(str, run_cmd)), cwd=self.work, capture_output=True, text=True)
                        if exp_rc == "nonzero":
                            self.assertNotEqual(ran.returncode, 0)
                            self.assertIn(exp_err, ran.stderr)
                        else:
                            self.assertEqual(ran.returncode, exp_rc, ran.stderr)
                        self.assertEqual(ran.stdout, exp_out)

    def test_wasm_direct_mixed_non_region_slice_pool_and_trim_memory(self):
        src = self.work / "mixed_pool.goose"
        src.write_text(
            "import slice_pool;\n"
            "import os;\n"
            "export fn probe() -> i64 {\n"
            "    reusable[] var rpool: i64[>..] = [];\n"
            "    let ra = rpool.alloc_slice(4);\n"
            "    rpool.free_slice(ra);\n"
            "    let rb = rpool.alloc_slice(4);\n"
            "    var spool = slice_pool<i64> {};\n"
            "    var runs: i64[:][>..] = [];\n"
            "    for i in 100 { runs.push(spool.alloc_slice(2)); }\n"
            "    for i in 50 { spool.free_slice(runs[2 * i]); }\n"
            "    let reused = spool.alloc_slice(2);\n"
            "    reused[0] = 77;\n"
            "    assert(spool.tree.height > 0 && trim_memory());\n"
            "    var bpool = slice_pool<u8> {};\n"
            "    let x = bpool.alloc_slice(5000);\n"
            "    let y = bpool.alloc_slice(30000);\n"
            "    for i in y.len { y[i] = 9; }\n"
            "    bpool.free_slice(y);\n"
            "    assert(bpool.trim() && y[15000] == 0);\n"
            "    return rb.len + reused[0] + x.len;\n"
            "}\n"
            "fn main() { print(probe()); }\n"
        )
        for tag, flags in (("O0", ("-O0",)), ("O2", ("-O2",)), ("mem64", ("--wasm-memory64", "-O2"))):
            wasm = self.work / f"mixed-{tag}.wasm"
            emitted = subprocess.run(
                list(map(str, [COMPILER, src, "--target", "wasm-direct", "--stdlib", STDLIB, *flags, "-o", wasm])),
                cwd=self.work, capture_output=True, text=True,
            )
            self.assertEqual(emitted.returncode, 0, f"mixed {tag}: {emitted.stderr}")
            for engine, run_cmd in self.engines(wasm):
                with self.subTest(mode=tag, engine=engine):
                    ran = subprocess.run(list(map(str, run_cmd)), cwd=self.work, capture_output=True, text=True)
                    self.assertEqual(ran.returncode, 0, ran.stderr)
                    self.assertEqual(ran.stdout.strip(), "5081")

    def test_native_emits_the_span_tree(self):
        emitted = self.compile("native", "-o", "pool.c")
        self.assertEqual(emitted.returncode, 0, emitted.stderr)
        text = (self.work / "pool.c").read_text()
        self.assertIn("static int64_t g_slice_pool_place(", text)
        self.assertIn("const GLoc *g_at", text)


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class DirectWasmReusableSlicePools(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.work = Path(directory.name)

    def run_wasm(self, source_text, *flags):
        src = self.work / "prog.goose"
        wasm = self.work / "prog.wasm"
        src.write_text(source_text)
        compiled = subprocess.run(
            [str(COMPILER), str(src), "--target", "wasm-direct", "--stdlib", str(STDLIB), *flags, "-o", str(wasm)],
            cwd=self.work, stdin=subprocess.DEVNULL, capture_output=True, text=True,
        )
        self.assertEqual(compiled.returncode, 0, f"compile {flags} failed:\n{compiled.stderr}")
        return subprocess.run(
            [os.environ.get("PYTHON", str(ROOT / ".venv/bin/python")), str(ROOT / "scripts/run_wasmtime.py"), str(wasm)],
            cwd=self.work, stdin=subprocess.DEVNULL, capture_output=True, text=True,
        )

    def test_slice_pool_alloc_free_coalesce_realloc_and_rebind(self):
        source = """
struct Item { a: i64 = 11, b: i64 = 22 }
fn retarget(var p: i64[>..]&, q: i64[>..]&) {
    p .= q;
    let x = p.alloc_slice(2);
    x[0] = 7; x[1] = 8;
}
fn main() {
    // 1. Alloc, free, coalesce, shrink, regrow, and move
    reusable[] var pool: i64[>..] = [];
    let a = pool.alloc_slice(4);
    for i in 0..4 { a[i] = i + 1; }
    let b = pool.alloc_slice(4);
    for i in 0..4 { b[i] = 100 + i; }
    let c = pool.alloc_slice(4);
    for i in 0..4 { c[i] = 200 + i; }
    pool.free_slice(a);
    pool.free_slice(c);
    // Grow b into adjacent freed c without moving
    let b2 = pool.realloc_slice(b, 6);
    assert(b2[0] == 100 && b2[3] == 103 && b2[4] == 0 && b2[5] == 0);
    // Shrink b2 and reuse freed tail + coalesced front
    let b3 = pool.realloc_slice(b2, 2);
    assert(b3[0] == 100 && b3[1] == 101);
    let d = pool.alloc_slice(3);
    d[0] = 77; d[2] = 79;
    assert(pool[0] == 77 && pool[2] == 79);

    // 2. Non-zero struct defaults on alloc and growth
    reusable[] var items: Item[>..] = [];
    let s1 = items.alloc_slice(2);
    assert(s1[0].a == 11 && s1[0].b == 22 && s1[1].a == 11 && s1[1].b == 22);
    s1[0].a = 99;
    let s2 = items.realloc_slice(s1, 4);
    assert(s2[0].a == 99 && s2[1].b == 22 && s2[2].a == 11 && s2[3].b == 22);

    // 3. Many free spans exercising B+ tree splits and merges
    reusable[] var many: i64[>..] = [];
    var starts: i64[>..] = [];
    for k in 0..120 {
        let s = many.alloc_slice(2);
        s[0] = k; s[1] = k + 1000;
        starts.push(many.index_of(s[0]));
    }
    var idx = 0;
    while idx < 120 {
        let pos = starts[idx];
        many.free_slice(many[pos..pos + 2]);
        idx += 2;
    }
    // Now 60 non-adjacent free spans exist; freeing odds coalesces everything
    idx = 1;
    while idx < 120 {
        let pos = starts[idx];
        many.free_slice(many[pos..pos + 2]);
        idx += 2;
    }
    let big = many.alloc_slice(200);
    assert(many.index_of(big[0]) == 0 && big.len == 200);

    // 4. Loop re-declaration resets pool state
    for round in 0..3 {
        reusable[] var lp: i64[>..] = [];
        let x = lp.alloc_slice(3);
        x[0] = round + 1;
        let y = lp.alloc_slice(2);
        y[0] = 55;
        lp.free_slice(x);
        let z = lp.alloc_slice(2);
        z[0] = 88;
        assert(lp.len == 5 && lp[0] == 88 && y[0] == 55);
    }

    // 5. Pool rebinding
    reusable[] var ra: i64[>..] = [];
    reusable[] var rb: i64[>..] = [];
    let old = rb.alloc_slice(3);
    rb.free_slice(old);
    retarget(ra, rb);
    assert(ra.len == 0 && rb.len == 3 && rb[0] == 7 && rb[1] == 8);

    print("slice pools ok");
}
"""
        for flags in (("-O0",), ("-O2",), ("--wasm-memory64", "-O2")):
            ran = self.run_wasm(source, *flags)
            self.assertEqual(ran.returncode, 0, f"run {flags} failed:\n{ran.stdout}\n{ran.stderr}")
            self.assertEqual(ran.stdout.strip(), "slice pools ok")

    def test_slice_pool_aborts_on_foreign_and_negative(self):
        foreign_src = """
fn pick(cond: bool, a: i64[:], b: i64[:]) -> i64[:] {
    if cond { return a; }
    return b;
}
fn main() {
    reusable[] var a: i64[>..] = [];
    reusable[] var b: i64[>..] = [];
    let sa = a.alloc_slice(2);
    let sb = b.alloc_slice(2);
    let chosen = pick(true, sa, sb);
    b.free_slice(chosen);
}
"""
        negative_src = """
fn main() {
    reusable[] var a: i64[>..] = [];
    let n = -3;
    let s = a.alloc_slice(n);
    print(s.len);
}
"""
        for flags in (("-O2",), ("--wasm-memory64", "-O2")):
            ran = self.run_wasm(foreign_src, *flags)
            self.assertNotEqual(ran.returncode, 0)
            self.assertIn("slice not from this pool", ran.stderr)
            ran = self.run_wasm(negative_src, *flags)
            self.assertNotEqual(ran.returncode, 0)
            self.assertIn("invalid slice length", ran.stderr)

    def test_flat_from_bytes_and_diverging_ref(self):
        source = """
enum Color { Red, Green, Blue }
enum Shape { Circle { r: i32, ok: bool }, Empty }
struct Entry { id: u32, flag: bool, color: Color, shape: Shape }

fn find_first(xs: i64[>..]&, want: i64) -> i64&? {
    for &x in xs {
        if x == want { return x; }
    }
    while true { return null; }
}

fn main() {
    var nums: i64[>..] = [10, 20, 30];
    let hit = find_first(nums, 20);
    let miss = find_first(nums, 99);
    guard hit else { assert(false); return; }
    assert(hit == 20 && !miss);

    var entries: Entry[>..] = [
        Entry { id: 7, flag: true, color: Color.Green, shape: Shape.Circle { r: 5, ok: true } },
        Entry { id: 9, flag: false, color: Color.Blue, shape: Shape.Empty }
    ];
    let img = to_bytes(entries);
    let back, ok = from_bytes<Entry[>..]>(img);
    assert(ok && back.len == 2 && back[0].id == 7 && back[0].flag && back[1].id == 9 && !back[1].flag);

    let bad_prefix: u8[2] = [128, 0];
    let bp, bp_ok = from_bytes<u8[>..]>(bad_prefix);
    assert(!bp_ok && bp.len == 0);

    let bad_bool: u8[2] = [1, 2];
    let bb, bb_ok = from_bytes<bool[>..]>(bad_bool);
    assert(!bb_ok && bb.len == 0);

    let bad_color: u8[2] = [1, 3];
    let bc, bc_ok = from_bytes<Color[>..]>(bad_color);
    assert(!bc_ok && bc.len == 0);

    var bad_shape: u8[>..] = to_bytes(entries);
    bad_shape[12] = 2;
    let bs, bs_ok = from_bytes<Entry[>..]>(bad_shape);
    assert(!bs_ok && bs.len == 0);

    print("from_bytes and diverging ref ok");
}
"""
        for flags in (("-O0",), ("-O2",), ("--wasm-memory64", "-O2")):
            ran = self.run_wasm(source, *flags)
            self.assertEqual(ran.returncode, 0, f"run {flags} failed:\n{ran.stdout}\n{ran.stderr}")
            self.assertEqual(ran.stdout.strip(), "from_bytes and diverging ref ok")


if __name__ == "__main__":
    unittest.main()
