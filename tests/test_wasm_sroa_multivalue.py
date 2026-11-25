#!/usr/bin/env python3
"""Qualify Wasm small-struct SROA and multi-value returns."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
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
class WasmSroaAndMultiValue(unittest.TestCase):
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

    def test_multivalue_and_frame_free_codegen(self):
        source = """struct Vec3 { x: f64, y: f64, z: f64 }
struct Pair { a: i64, b: i64 }

// Non-trivial bodies so optimizer keeps them as real calls to exercise ABI.
fn step_vec(x: f64, y: f64, z: f64, k: i64) -> Vec3 {
    var v = Vec3 { x: x, y: y, z: z };
    var i: i64 = 0;
    while i < k {
        let nx = v.x * 1.0001 + v.y * 0.25;
        let ny = v.y * 0.9999 - v.z * 0.125;
        let nz = v.z + v.x * 0.0625;
        v = Vec3 { x: nx, y: ny, z: nz };
        i++;
    }
    return v;
}

fn step_pair(a: i64, b: i64, n: i64) -> Pair {
    var p = Pair { a: a, b: b };
    var i: i64 = 0;
    while i < n {
        p = Pair { a: p.b, b: p.a + p.b };
        i++;
    }
    return p;
}

fn sum_pairs(xs: const Pair[:]) -> i64 {
    var total: i64 = 0;
    for item in xs {
        total += item.a * 3 + item.b;
    }
    return total;
}

fn main() {
    let v = step_vec(1.0, 2.0, 3.0, 4);
    let p = step_pair(1, 1, 10);
    let direct_z = step_vec(2.0, 1.0, 0.5, 3).z;
    step_pair(3, 4, 2);
    var arr: Pair[3] = [Pair { a: 1, b: 2 }, Pair { a: 3, b: 4 }, p];
    print(p.a, " ", p.b, " ", sum_pairs(arr), " ", (v.x * 1000.0) as i64, " ", (direct_z * 1000.0) as i64);
}
"""
        self.check_matches_native(source, "89 144 429 2429 920\n")

        # Verify Wasm type & code sections directly (no external disassembler required).
        def parse_wasm_funcs(path: Path):
            data = path.read_bytes()
            def read_leb(pos: int):
                res = 0; shift = 0
                while True:
                    b = data[pos]; pos += 1
                    res |= (b & 0x7f) << shift
                    if not (b & 0x80): return res, pos
                    shift += 7
            tmap = {0x7f: "i32", 0x7e: "i64", 0x7d: "f32", 0x7c: "f64", 0x7b: "v128"}
            pos = 8; types = []; func_types = []; bodies = []
            while pos < len(data):
                sid = data[pos]; pos += 1
                slen, pos = read_leb(pos); end = pos + slen
                if sid == 1:
                    cnt, pos = read_leb(pos)
                    for _ in range(cnt):
                        pos += 1  # 0x60
                        np, pos = read_leb(pos); ps = tuple(tmap.get(data[pos + i], "?") for i in range(np)); pos += np
                        nr, pos = read_leb(pos); rs = tuple(tmap.get(data[pos + i], "?") for i in range(nr)); pos += nr
                        types.append((ps, rs))
                elif sid == 3:
                    cnt, pos = read_leb(pos)
                    for _ in range(cnt):
                        ti, pos = read_leb(pos); func_types.append(ti)
                elif sid == 10:
                    cnt, pos = read_leb(pos)
                    for _ in range(cnt):
                        bsz, pos = read_leb(pos); bodies.append(data[pos:pos + bsz]); pos += bsz
                pos = end
            return [(types[ti], body) for ti, body in zip(func_types, bodies)]

        for extra, name in [
            (("--wasm-bundled-host",), "mv32.wasm"),
            (("--wasm-memory64", "--wasm-bundled-host"), "mv64.wasm"),
        ]:
            wasm = self.emit_wasm(source, *extra, name=name)
            funcs = parse_wasm_funcs(wasm)
            found_vec = False
            found_pair = False
            for (params, results), body in funcs:
                if results == ("f64", "f64", "f64"):
                    found_vec = True
                    # Must not allocate activation stack frame (global.set 0 = 0x24 0x00)
                    # or spill/load f64 fields (f64.load = 0x2b, f64.store = 0x39).
                    self.assertNotIn(b"\x24\x00", body, f"{name}: step_vec allocated stack frame")
                    self.assertNotIn(b"\x2b", body, f"{name}: step_vec loaded f64 from memory")
                    self.assertNotIn(b"\x39", body, f"{name}: step_vec stored f64 to memory")
                elif results == ("i64", "i64"):
                    found_pair = True
                    self.assertNotIn(b"\x24\x00", body, f"{name}: step_pair allocated stack frame")
                    self.assertNotIn(b"\x37", body, f"{name}: step_pair stored i64 to memory")
            self.assertTrue(found_vec, f"{name}: Vec3 multi-value body not found")
            self.assertTrue(found_pair, f"{name}: Pair multi-value body not found")

    def test_swap_compound_narrow_and_padding(self):
        source = """struct Narrow { a: u8, b: i8, c: u16, ok: bool }
struct Padded { tag: u8, val: i64, flag: bool }

fn make_narrow(x: i64) -> Narrow {
    var n = Narrow { a: (x + 250) as u8, b: (x - 130) as i8, c: (x + 65530) as u16, ok: (x & 1) == 0 };
    if x > 100 { n.a += 1; }
    return n;
}

fn make_padded(t: u8, v: i64, f: bool) -> Padded {
    var p = Padded { tag: t, val: v, flag: f };
    if v < 0 { p.val = -p.val; }
    return p;
}

fn accept_padded(p: Padded) -> i64 {
    var r = p.val + (p.tag as i64);
    if p.flag { r += 1000; }
    return r;
}

fn main() {
    var n = make_narrow(10);
    n.a += 250;
    n.a++;
    n.b -= 10;
    n.b--;
    n.c += 20;
    // Self-referential swap in place
    n = Narrow { a: (n.c & 255) as u8, b: n.a as! i8, c: n.a as u16, ok: !n.ok };
    var p: Padded;
    p = make_padded(7, -42, true);
    var arr: Padded[2] = [Padded { tag: 1, val: 2, flag: false }, Padded { tag: 3, val: 4, flag: true }];
    arr[0] = p;
    arr[1] = make_padded(9, 10, false);
    let r1 = accept_padded(p);
    let r2 = accept_padded(arr[0]);
    let r3 = accept_padded(arr[1]);
    print(n.a, " ", n.b, " ", n.c, " ", n.ok, " ", r1, " ", r2, " ", r3);
}
"""
        self.check_matches_native(source, "24 -1 255 false 1049 1049 19\n")

    def test_slice_and_ref_fields_sroa(self):
        source = """struct Cursor { data: const u8[:], pos: i64 }
struct RefBox { r: i64&, tag: i64 }

fn make_cursor(s: const u8[:], start: i64) -> Cursor {
    var c = Cursor { data: s, pos: start };
    if c.pos < 0 { c.pos = 0; }
    return c;
}

fn sum_bytes(s: const u8[:]) -> i64 {
    var acc: i64 = 0;
    for ch in s { acc += ch as i64; }
    return acc;
}

fn main() {
    var cur = make_cursor("abcdef", 1);
    var loop_sum: i64 = 0;
    for ch in cur.data { loop_sum += ch as i64; }
    cur.data = cur.data[2..];
    cur.pos += 1;
    let slice_sum = sum_bytes(cur.data);
    let byte_at = cur.data[cur.pos] as i64;

    var x: i64 = 10;
    var y: i64 = 200;
    var box = RefBox { r: x, tag: 3 };
    box.r = 40;
    box.r += 5;
    box.tag++;
    box.r .= y;
    box.r += 7;
    print(loop_sum, " ", slice_sum, " ", byte_at, " ", x, " ", y, " ", box.tag);
}
"""
        self.check_matches_native(source, "597 402 101 45 207 4\n")

    def test_escapes_closures_enums_and_tuples(self):
        source = """struct Pt { x: i64, y: i64 }
enum Shape {
    Circle { r: i64, tag: i64 },
    Rect { w: i64, h: i64 },
}

fn make_pt(x: i64, y: i64) -> Pt {
    var p = Pt { x: x, y: y };
    if x < 0 { p.x = -p.x; }
    return p;
}

fn make_pt_fnval(x: i64, y: i64) -> Pt {
    var p = Pt { x: x + 1, y: y + 2 };
    if x < 0 { p.x = 0; }
    return p;
}

fn apply_pt(f: fn(i64, i64) -> Pt, x: i64, y: i64) -> Pt {
    return f(x, y);
}

fn make_circle(r: i64) -> Shape.Circle {
    var c = Shape.Circle { r: r, tag: r * 2 };
    if r < 0 { c.r = 0; }
    return c;
}

fn make_pair(a: i64, b: i64) -> Pt, i64 {
    return Pt { x: a, y: b }, a + b;
}

fn inc(v: i64&) { v += 10; }
fn shift(p: Pt&) { p.x += 100; p.y += 200; }

fn area(s: const Shape) -> i64 {
    return match s {
        Circle c => c.r * c.r + c.tag,
        Rect r => r.w * r.h,
    };
}

fn main() {
    // Escapes via &p and &p.x and ref params
    var a = make_pt(3, 4);
    shift(a);
    var b = make_pt(5, 6);
    inc(b.x);
    let r = &b.y;
    r += 1;

    // Captured by nested function
    var cap = make_pt(7, 8);
    fn add_cap(k: i64) -> i64 { return cap.x + cap.y + k; }
    let cap_res = add_cap(5);

    // Function value (F_VALUE_USED) fallback
    let fv = apply_pt(make_pt_fnval, 10, 20);

    // Enum variant from multi-value helper + match binder SROA
    let s1: Shape = make_circle(6);
    let s2: Shape = Shape.Rect { w: 4, h: 9 };

    // Tuple multi-binding into SROA local
    let tp, tsum = make_pair(11, 22);

    print(a.x, " ", a.y, " ", b.x, " ", b.y, " ", cap_res, " ", fv.x, " ", fv.y, " ", area(s1), " ", area(s2), " ", tp.x + tp.y, " ", tsum);
}
"""
        self.check_matches_native(source, "103 204 15 7 20 11 22 48 36 33 33\n")

    def test_push_and_array_element_assign_sroa(self):
        source = """struct Ev { a: i32, b: i32, tag: u8 }

fn make_ev(a: i32, b: i32, tag: u8) -> Ev {
    var e = Ev { a: a, b: b, tag: tag };
    if a < 0 { e.a = -e.a; }
    return e;
}

fn push_side(xs: Ev[>..]&, x: i32) -> i32 {
    xs.push(Ev { a: x, b: x + 1, tag: 9 });
    return xs.len as i32;
}

fn main() {
    var xs: Ev[>..] = [];
    // Direct SROA push of record literal, SROA local, multi-value call, and side-effecting push
    xs.push(Ev { a: 10, b: 20, tag: 1 });
    let local_ev = Ev { a: 30, b: 40, tag: 2 };
    xs.push(local_ev);
    xs.push(make_ev(-50, 60, 3));
    // Field initializer mutates xs before outer push reserves its slot
    xs.push(Ev { a: push_side(xs, 70), b: xs.len as i32, tag: 4 });
    // Self-referential swap in array element
    xs[0] = Ev { a: xs[0].b, b: xs[0].a, tag: xs[0].tag + 10 };
    var sum: i64 = 0;
    for e in xs {
        sum = sum * 7 + (e.a as i64) + (e.b as i64) * 3 + (e.tag as i64);
    }
    print(xs.len, " ", xs[0].a, " ", xs[0].b, " ", xs[0].tag, " ", xs[3].a, " ", xs[4].a, " ", xs[4].b, " ", sum);
}
"""
        self.check_matches_native(source, "5 20 10 11 70 4 4 212078\n")


if __name__ == "__main__":
    unittest.main()
