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
COMPILER = Path(os.environ.get('GOOSE_COMPILER', ROOT / 'build/bin/goose')).resolve()
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
