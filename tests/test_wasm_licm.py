#!/usr/bin/env python3
"""Qualify Wasm loop-invariant array header hoisting (LICM) soundness and codegen."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMPILER = Path(os.environ.get("GOOSE_COMPILER", ROOT / "build/bin/goose")).resolve()
STDLIB = Path(os.environ.get("GOOSE_STDLIB", COMPILER.parent / "stdlib")).resolve()
WASMTIME_HOST = ROOT / "host/rust/target/release/goose-wasmtime"


def run_wasm(wasm: Path) -> subprocess.CompletedProcess[bytes]:
    if WASMTIME_HOST.is_file():
        return subprocess.run([WASMTIME_HOST, wasm], stdin=subprocess.DEVNULL, capture_output=True, timeout=30)
    return subprocess.run(["node", ROOT / "scripts/run_wasm.mjs", wasm], stdin=subprocess.DEVNULL, capture_output=True, timeout=30)


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class WasmLoopHeaderHoisting(unittest.TestCase):
    def setUp(self):
        work = tempfile.TemporaryDirectory()
        self.addCleanup(work.cleanup)
        self.work = Path(work.name)

    def build_native(self, source: str) -> Path:
        src = self.work / "prog.goose"
        src.write_text(source)
        out_bin = self.work / "prog"
        res = subprocess.run(
            [str(ROOT / ".venv/bin/python"), str(ROOT / "scripts/goose_wasm.py"), "build",
             "--backend", "native", "--cc", "clang", "--jobs", "1",
             "--goose", str(COMPILER), "--stdlib", str(STDLIB), "-O2",
             "--build-dir", str(self.work / "nat"), "-o", str(out_bin), str(src)],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        return out_bin

    def emit_wasm(self, source: str, *extra: str, opt: str = "-O2", name: str = "prog.wasm") -> Path:
        src = self.work / "prog.goose"
        src.write_text(source)
        out = self.work / name
        res = subprocess.run(
            [str(COMPILER), str(src), "--stdlib", str(STDLIB), "--target", "wasm-direct", opt, *extra, "-o", str(out)],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        return out

    def check_matches_native(self, source: str, expected: str):
        nat_bin = self.build_native(source)
        nat = subprocess.run([str(nat_bin)], stdin=subprocess.DEVNULL, capture_output=True, text=True, check=True)
        self.assertEqual(nat.stdout, expected)
        for extra, name in [
            (("--wasm-bundled-host",), "prog32.wasm"),
            (("--wasm-memory64", "--wasm-bundled-host"), "prog64.wasm"),
        ]:
            wasm = self.emit_wasm(source, *extra, name=name)
            res = run_wasm(wasm)
            self.assertEqual(res.returncode, 0, f"{name}: {res.stderr.decode(errors='replace')}")
            self.assertEqual(res.stdout.decode(), expected, name)

    def test_hoisted_patterns_and_load_reduction(self):
        source = """struct Item { val: i64, next: i64 }
root struct State {
    items: Item[>..],
    out: i64[>..],
    text: const u8[:],
}
fn sum_owner(xs: const i64[>..]&) -> i64 {
    var acc: i64 = 0;
    var i: i64 = 0;
    while i < xs.len {
        acc += xs[i];
        i++;
    }
    return acc;
}
fn insertion_owner(xs: i64[>..]&) {
    for i in 1..xs.len {
        let v = xs[i];
        var j = i;
        while j > 0 && xs[j - 1] > v {
            xs[j] = xs[j - 1];
            j--;
        }
        xs[j] = v;
    }
}
fn walk_state(s: State&) -> i64 {
    // Disjoint direct fields: mutating s.out while reading s.items and s.text.
    for it in s.items {
        s.out.push(it.val * 2);
    }
    // Unproven linked-index walk over s.items.
    var cur: i64 = 0;
    var acc: i64 = 0;
    while cur >= 0 {
        acc += s.items[cur].val;
        cur = s.items[cur].next;
    }
    // Slice field loop.
    var k: i64 = 0;
    while k < s.text.len {
        acc += s.text[k] as i64;
        k++;
    }
    return acc;
}
fn filter_disjoint(xs: const i64[>..]&) -> i64 {
    var local_out: i64[>..] = [];
    for i in 0..xs.len {
        if xs[i] > 2 { local_out.push(xs[i]); }
    }
    var sum: i64 = 0;
    for v in local_out { sum += v; }
    return sum;
}
fn nested_ptr_then_len(xs: const i64[>..]&, idxs: const i64[>..]&) -> i64 {
    var acc: i64 = 0;
    for i in 0..xs.len {
        // Outer loop only needs proven xs[i]; inner loop needs unproven xs[idxs[j]] and xs.len.
        acc += xs[i];
        for j in 0..idxs.len {
            let k = idxs[j];
            if k >= 0 && k < xs.len {
                acc += xs[k];
            }
        }
    }
    return acc;
}
fn pure_step(xs: const i64[:], idx: i64&) -> i64 {
    let v = xs[idx];
    idx++;
    return v;
}
fn walk_with_pure_call(xs: const i64[>..]&, ys: const i64[:]) -> i64 {
    var acc: i64 = 0;
    var at: i64 = 0;
    for i in 0..xs.len {
        acc += xs[i];
        if at < ys.len { acc += pure_step(ys, at); }
    }
    return acc;
}
fn main() {
    var xs: i64[>..] = [5, 2, 4, 1, 3];
    insertion_owner(xs);
    var idxs: i64[>..] = [0, 4, 2];
    var st = State {
        items: [Item { val: 10, next: 2 }, Item { val: 20, next: -1 }, Item { val: 30, next: 1 }],
        out: [],
        text: "abc",
    };
    let w = walk_state(st);
    var out_sum: i64 = 0;
    for v in st.out { out_sum += v; }
    // 0-trip and 1-trip loops must be exact.
    var z: i64 = 0;
    for i in 0..0 { z += xs[i]; }
    for i in 5..5 { z += xs[i]; }
    for i in 5..3 { z += xs[i]; }
    for i in 2..3 { z += xs[i]; }
    print(sum_owner(xs), " ", w, " ", out_sum, " ", filter_disjoint(xs), " ", nested_ptr_then_len(xs, idxs), " ", z, " ", walk_with_pure_call(xs, idxs));
}
"""
        self.check_matches_native(source, "15 354 120 12 60 3 21\n")

        # Verify LICM actually hoists header loads out of insertion_owner / sum_owner loops at -O2.
        wasm_dis = shutil.which("wasm-dis")
        if wasm_dis:
            w32 = self.emit_wasm(source, "--wasm-bundled-host", opt="-O2", name="check_hoist32.wasm")
            wat = subprocess.run([wasm_dis, str(w32)], stdin=subprocess.DEVNULL, capture_output=True, text=True, check=True).stdout
            # Check sum_owner: inside its loop there should be only 1 i64.load (xs[i]) and 0 i32.load (no header reloads).
            # Check insertion_owner inner loop: no i32.load header reloads inside the inner while loop.
            self.assertIn("loop", wat)
            # Extract function bodies containing i64.load (element loads) and verify at least one has a loop with 0 i32.load.
            funcs = wat.split("(func ")
            hoisted_loops = 0
            for fn in funcs[1:]:
                if "(loop " in fn and "i64.load" in fn:
                    # Take the innermost loop text up to its closing end.
                    after_loop = fn.split("(loop ", 1)[1]
                    if "i32.load" not in after_loop.split("(br ", 1)[0]:
                        hoisted_loops += 1
            self.assertGreaterEqual(hoisted_loops, 2, "expected loop header i32.loads to be hoisted out of inner loops")

    def test_soundness_aliasing_and_mutations(self):
        source = """struct Holder { xs: i64[>..] }
struct SliceBox { view: i64[:] }

fn mutate_self_while(xs: i64[>..]&) -> i64 {
    var i: i64 = 0;
    var acc: i64 = 0;
    while i < xs.len {
        acc += xs[i];
        if i == 1 && xs.len < 6 { xs.push(100); xs.push(200); }
        i++;
    }
    return acc;
}
fn mutate_self_for_seq(xs: i64[>..]&) -> i64 {
    var acc: i64 = 0;
    for v, i in xs {
        acc += v;
        if i == 0 && xs.len < 5 { xs.push(50); }
    }
    return acc;
}
fn alias_params(a: i64[>..]&, b: i64[>..]&) -> i64 {
    var acc: i64 = 0;
    for i in 0..3 {
        b.push(a[i] + 10);
        acc += a[a.len - 1];
    }
    return acc;
}
fn rebind_ref_in_loop(a: Holder&, b: Holder&) -> i64 {
    var cur: Holder& = a;
    var acc: i64 = 0;
    for i in 0..2 {
        acc += cur.xs[0];
        cur .= b;
    }
    return acc;
}
fn reassign_slice_field(box: SliceBox&, other: i64[:]) -> i64 {
    var acc: i64 = 0;
    for i in 0..2 {
        acc += box.view[0] + box.view.len;
        box.view = other;
    }
    return acc;
}
fn helper_push(xs: i64[>..]&, v: i64) { xs.push(v); }
fn call_mutates(xs: i64[>..]&) -> i64 {
    var acc: i64 = 0;
    var i: i64 = 0;
    while i < xs.len {
        acc += xs[i];
        if i == 0 { helper_push(xs, 77); }
        i++;
    }
    return acc;
}
fn for_element_binding(rows: SliceBox[>..]&) -> i64 {
    var acc: i64 = 0;
    for row in rows {
        acc += row.view[0];
    }
    return acc;
}
fn optional_ref_null(xs: const i64[>..]?&) -> i64 {
    var i: i64 = 0;
    var acc: i64 = 0;
    while xs != null && i < xs.len {
        acc += xs[i];
        i++;
    }
    return acc;
}
fn defer_mutates(xs: i64[>..]&) -> i64 {
    var acc: i64 = 0;
    for i in 0..3 {
        defer { if xs.len < 5 { xs.push(9); } }
        acc += xs.len;
        if i == 0 { continue; }
    }
    return acc;
}
fn reslice_string_cursor() -> i64 {
    var t = "hello";
    var acc: i64 = 0;
    while t.len > 0 {
        acc += t[0] as i64;
        t = t[1..];
    }
    return acc;
}
fn main() {
    var a: i64[>..] = [1, 2, 3];
    let r1 = mutate_self_while(a);
    var b: i64[>..] = [1, 2, 3];
    let r2 = mutate_self_for_seq(b);
    var c: i64[>..] = [1, 2, 3];
    let r3 = alias_params(c, c);
    var h1 = Holder { xs: [10, 20] };
    var h2 = Holder { xs: [30, 40] };
    let r4 = rebind_ref_in_loop(h1, h2);
    var v1: i64[>..] = [5, 6];
    var v2: i64[>..] = [8, 9, 10];
    var sb = SliceBox { view: v1 };
    let r5 = reassign_slice_field(sb, v2);
    var d: i64[>..] = [4, 5];
    let r6 = call_mutates(d);
    var row_a: i64[>..] = [11];
    var row_b: i64[>..] = [22];
    var row_c: i64[>..] = [33];
    var rows: SliceBox[>..] = [SliceBox { view: row_a }, SliceBox { view: row_b }, SliceBox { view: row_c }];
    let r7 = for_element_binding(rows);
    let r8 = optional_ref_null(null);
    let r9 = optional_ref_null(d);
    var e: i64[>..] = [1, 2];
    let r10 = defer_mutates(e);
    let r11 = reslice_string_cursor();
    print(r1, " ", r2, " ", r3, " ", r4, " ", r5, " ", r6, " ", r7, " ", r8, " ", r9, " ", r10, " ", r11);
}
"""
        self.check_matches_native(source, "306 56 36 40 18 86 66 0 86 9 532\n")

    def test_hoisted_unproven_still_traps(self):
        source = """fn lookup(xs: const i64[>..]&, idxs: const i64[>..]&) -> i64 {
    var acc: i64 = 0;
    for i in 0..idxs.len {
        acc += xs[idxs[i]];
    }
    return acc;
}
fn main() {
    var xs: i64[>..] = [1, 2, 3];
    var idxs: i64[>..] = [0, 2, 3];
    print(lookup(xs, idxs));
}
"""
        for extra, name in [
            (("--wasm-bundled-host",), "trap32.wasm"),
            (("--wasm-memory64", "--wasm-bundled-host"), "trap64.wasm"),
        ]:
            wasm = self.emit_wasm(source, *extra, name=name)
            res = run_wasm(wasm)
            self.assertNotEqual(res.returncode, 0, f"{name} unexpectedly succeeded")


if __name__ == "__main__":
    unittest.main()
