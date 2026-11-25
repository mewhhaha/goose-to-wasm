#!/usr/bin/env python3
"""Qualify expanded bounds-check elision (BCE) and direct Wasm/C indexing."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMPILER = Path(os.environ.get("GOOSE_COMPILER", ROOT / "build/bin/goosew")).resolve()
STDLIB = Path(os.environ.get("GOOSE_STDLIB", COMPILER.parent / "stdlib")).resolve()
WASMTIME_HOST = ROOT / "host/rust/target/release/goose-wasmtime"


def run_wasm(wasm: Path) -> subprocess.CompletedProcess[bytes]:
    if WASMTIME_HOST.is_file():
        return subprocess.run([WASMTIME_HOST, wasm], stdin=subprocess.DEVNULL, capture_output=True, timeout=30)
    return subprocess.run(["node", ROOT / "scripts/run_wasm.mjs", wasm], stdin=subprocess.DEVNULL, capture_output=True, timeout=30)


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class BceAndDirectIndex(unittest.TestCase):
    def setUp(self):
        work = tempfile.TemporaryDirectory()
        self.addCleanup(work.cleanup)
        self.work = Path(work.name)

    def emit_c(self, source: str, opt: str = "-O2") -> tuple[str, Path]:
        src = self.work / "prog.goose"
        src.write_text(source)
        out_c = self.work / "prog.c"
        out_bin = self.work / "prog"
        res = subprocess.run(
            [str(ROOT / ".venv/bin/python"), str(ROOT / "scripts/goose_wasm.py"), "build",
             "--backend", "native", "--cc", "clang", "--jobs", "1",
             "--goose", str(COMPILER), "--stdlib", str(STDLIB), opt,
             "--build-dir", str(self.work / "nat"), "--emit-c", str(out_c), "-o", str(out_bin), str(src)],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        return out_c.read_text(), out_bin

    def emit_wasm(self, source: str, *extra: str, name: str = "prog.wasm") -> Path:
        src = self.work / "prog.goose"
        src.write_text(source)
        out = self.work / name
        res = subprocess.run(
            [str(COMPILER), str(src), "--stdlib", str(STDLIB), "--target", "wasm-direct", "-O2", *extra, "-o", str(out)],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        return out

    def test_elision_patterns_in_c_and_wasm(self):
        source = """fn sum_while(xs: const i64[:]) -> i64 {
    var i: i64 = 0;
    var acc: i64 = 0;
    while i < xs.len {
        acc += xs[i];
        i++;
    }
    return acc;
}
fn insertion(xs: i64[:]) {
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
fn same_slice(a: const i64[:], b: const i64[:]) -> bool {
    if a.len != b.len { return false; }
    for v, i in a {
        if b[i] != v { return false; }
    }
    return true;
}
fn guard_and_early_exit(xs: const i64[:], idx: i64) -> i64 {
    if idx < 0 || idx >= xs.len { return -1; }
    let a = xs[idx];
    guard idx >= 0 && idx < xs.len else { return -2; }
    return a + xs[idx];
}
fn push_resize_mask(id: i64, u: u64, byte: u8) -> i64 {
    var arr: i64[>..] = [];
    arr.push(11);
    let last = arr[arr.len - 1];
    arr.resize(id + 1, 7);
    let at_id = arr[id];
    var lut: i64[256] = [0; 256];
    lut[byte] = 5;
    let mask_arr: i64[4] = [1, 2, 3, 4];
    let m = mask_arr.len - 1;
    let masked = mask_arr[id & m];
    let modv = mask_arr[(u % (mask_arr.len as u64)) as i64];
    return last + at_id + lut[byte] + masked + modv;
}
fn main() {
    var xs: i64[>..] = [5, 2, 4, 1, 3];
    insertion(xs);
    var ys: i64[>..] = [1, 2, 3, 4, 5];
    print(sum_while(xs), " ", same_slice(xs, ys), " ", guard_and_early_exit(xs, 2), " ", push_resize_mask(3, 9, 42));
}
"""
        c_text, bin_path = self.emit_c(source, "-O2")
        prog_c = c_text.split("G_FN void g_initialize(void);", 1)[1]
        unchecked_hits = (
            prog_c.count("g_element_unchecked(")
            + prog_c.count("g_element_unchecked_nn(")
            + prog_c.count(".data+(uint64_t)")
            + prog_c.count(".base+(uintptr_t)((uint64_t)")
        )
        self.assertGreaterEqual(unchecked_hits, 12)
        self.assertLessEqual(prog_c.count("g_element_at_nn(") + prog_c.count("g_element_at("), 1)
        nat = subprocess.run([str(bin_path)], stdin=subprocess.DEVNULL, capture_output=True, text=True, check=True)
        expected = "15 true 6 29\n"
        self.assertEqual(nat.stdout, expected)

        for extra, name in [
            (("--wasm-bundled-host",), "prog32.wasm"),
            (("--wasm-memory64", "--wasm-bundled-host"), "prog64.wasm"),
        ]:
            wasm = self.emit_wasm(source, *extra, name=name)
            res = run_wasm(wasm)
            self.assertEqual(res.returncode, 0, res.stderr.decode(errors="replace"))
            self.assertEqual(res.stdout.decode(), expected)

    def test_unsound_cases_still_trap(self):
        cases = [
            ("non_diverging_if", """fn bad(xs: const i64[:], i: i64) -> i64 {
    if i < 0 || i >= xs.len { let _ = 0; }
    return xs[i];
}
fn main() { var a: i64[>..] = [1, 2]; print(bad(a, 5)); }
"""),
            ("push_invalidates_len_eq", """fn bad(a: i64[>..]&, b: i64[>..]&) -> i64 {
    if a.len != b.len { return 0; }
    a.push(9);
    var s: i64 = 0;
    for v, i in a { s += b[i]; }
    return s;
}
fn main() { var a: i64[>..] = [1, 2]; var b: i64[>..] = [3, 4]; print(bad(a, b)); }
"""),
            ("dec_before_minus_one", """fn bad(xs: i64[:]) -> i64 {
    var s: i64 = 0;
    for i in 1..xs.len {
        var j = i;
        while j > 0 {
            j--;
            s += xs[j - 1];
        }
    }
    return s;
}
fn main() { var a: i64[>..] = [1, 2, 3]; print(bad(a)); }
"""),
            ("pop_in_for_loop", """fn bad(xs: i64[>..]&) -> i64 {
    var s: i64 = 0;
    for i in 0..xs.len {
        if xs.len > 0 { let _ = xs.pop(); }
        s += xs[i];
    }
    return s;
}
fn main() { var a: i64[>..] = [1, 2, 3]; print(bad(a)); }
"""),
            ("while_step_two", """fn bad(xs: const i64[:]) -> i64 {
    var i: i64 = 0;
    var s: i64 = 0;
    while i < xs.len {
        i += 2;
        s += xs[i];
    }
    return s;
}
fn main() { var a: i64[>..] = [1, 2, 3]; print(bad(a)); }
"""),
            ("while_break_invalidates_exit", """fn bad(xs: i64[>..]&, id: i64) -> i64 {
    while xs.len <= id { break; }
    return xs[id];
}
fn main() { var a: i64[>..] = [1]; print(bad(a, 5)); }
"""),
        ]
        for label, source in cases:
            with self.subTest(case=label):
                _, bin_path = self.emit_c(source, "-O2")
                nat = subprocess.run([str(bin_path)], stdin=subprocess.DEVNULL, capture_output=True, text=True)
                self.assertNotEqual(nat.returncode, 0, f"{label} native did not trap!")
                self.assertIn("out of bounds", nat.stderr)
                for extra, suffix in [(("--wasm-bundled-host",), "32"), (("--wasm-memory64", "--wasm-bundled-host"), "64")]:
                    wasm = self.emit_wasm(source, *extra, name=f"{label}_{suffix}.wasm")
                    res = run_wasm(wasm)
                    self.assertNotEqual(res.returncode, 0, f"{label} wasm{suffix} did not trap!")
                    self.assertIn("out of bounds", res.stderr.decode(errors="replace"))


if __name__ == "__main__":
    unittest.main()
