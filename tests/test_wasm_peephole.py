#!/usr/bin/env python3
"""Qualify Wasm peephole folding, dead region/scratch mark elimination, and cold abort outlining."""
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


def decode_wasm_functions(wasm_path: Path) -> tuple[list[tuple[str, str]], list[list[tuple[int, int | None]]]]:
    """Decode imports and instruction streams (opcode, operand) for all code bodies."""
    data = wasm_path.read_bytes()
    pos = 8
    sections: dict[int, tuple[int, int]] = {}
    while pos < len(data):
        sid = data[pos]
        pos += 1
        sz = 0
        sh = 0
        while True:
            b = data[pos]
            pos += 1
            sz |= (b & 127) << sh
            if not (b & 128):
                break
            sh += 7
        sections[sid] = (pos, sz)
        pos += sz

    def make_reader(start: int):
        p = [start]

        def rleb() -> int:
            v = 0
            sh = 0
            while True:
                b = data[p[0]]
                p[0] += 1
                v |= (b & 127) << sh
                if not (b & 128):
                    return v
                sh += 7

        return p, rleb

    imports: list[tuple[str, str]] = []
    if 2 in sections:
        p, rleb = make_reader(sections[2][0])
        nimp = rleb()
        for _ in range(nimp):
            ml = rleb()
            mod = data[p[0]:p[0] + ml].decode()
            p[0] += ml
            nl = rleb()
            name = data[p[0]:p[0] + nl].decode()
            p[0] += nl
            _kind = data[p[0]]
            p[0] += 1
            rleb()
            imports.append((mod, name))

    bodies: list[list[tuple[int, int | None]]] = []
    p, rleb = make_reader(sections[10][0])
    nf = rleb()
    for _ in range(nf):
        bsz = rleb()
        end = p[0] + bsz
        ng = rleb()
        for _ in range(ng):
            rleb()
            p[0] += 1
        ops: list[tuple[int, int | None]] = []
        while p[0] < end:
            op = data[p[0]]
            p[0] += 1
            val: int | None = None
            if op in (0x02, 0x03, 0x04):
                b = data[p[0]]
                p[0] += 1
                if b & 0x80:
                    while data[p[0] - 1] & 0x80:
                        p[0] += 1
            elif op in (0x0c, 0x0d, 0x10, 0x20, 0x21, 0x22, 0x23, 0x24, 0x3f, 0x40):
                val = rleb()
            elif op == 0x0e:
                c = rleb()
                for _ in range(c + 1):
                    rleb()
            elif op == 0x11:
                rleb()
                rleb()
            elif op == 0x1c:
                c = rleb()
                p[0] += c
            elif 0x28 <= op <= 0x3e:
                rleb()
                rleb()
            elif op in (0x41, 0x42):
                rleb()
            elif op == 0x43:
                p[0] += 4
            elif op == 0x44:
                p[0] += 8
            elif op == 0xfc:
                sub = rleb()
                if sub in (8, 10):
                    rleb()
                    rleb()
                elif sub in (9, 11):
                    rleb()
            elif op == 0xfd:
                sub = rleb()
                if sub <= 0x0b or sub in (0x5c, 0x5d):
                    rleb()
                    rleb()
                elif sub in (0x0c, 0x0d):
                    p[0] += 16
                elif 0x15 <= sub <= 0x22:
                    p[0] += 1
                elif 0x54 <= sub <= 0x5b:
                    rleb()
                    rleb()
                    p[0] += 1
            ops.append((op, val))
        bodies.append(ops)
    return imports, bodies


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class WasmPeepholeAndCompaction(unittest.TestCase):
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

    def test_peephole_zero_adjacent_set_get_and_no_dead_marks(self):
        source = """inline fn mix(x: i64, y: i64) -> i64 {
    if x < 0 { return -x + y; }
    return (x * 3 + y) ^ (x >> 1);
}

fn hot_work(arr: i64[>..]&, idx: i64[>..]&, limit: i64) -> i64 {
    var acc: i64 = 0;
    var i: i64 = 0;
    while i < limit {
        let k = idx[i];
        if k < 0 { break; }
        if k == 999 { i++; continue; }
        let v = mix(arr[k], i);
        arr[k] = v;
        acc += v;
        i++;
    }
    return acc;
}

fn main() {
    var arr: i64[>..] = [];
    var idx: i64[>..] = [];
    for i in 0..32 {
        arr.push(i * 7 + 1);
        idx.push((i * 5) % 32);
    }
    print(hot_work(arr, idx, 32));
}
"""
        self.check_matches_native(source, "10960\n")
        for extra, name in [
            (("--wasm-bundled-host",), "chk32.wasm"),
            (("--wasm-memory64", "--wasm-bundled-host"), "chk64.wasm"),
        ]:
            wasm = self.emit_wasm(source, *extra, name=name)
            imports, bodies = decode_wasm_functions(wasm)
            abort_idx = next(i for i, (m, n) in enumerate(imports) if m == "goose" and n == "abort")
            # User function 0 is hot_work (mix is inlined into hot_work; user functions start at body 0).
            # Verify no user function has an adjacent non-parameter local.set L; local.get L pair.
            # hot_work takes 3 params (0, 1, 2), so locals >= 3 are non-parameter locals.
            hot = bodies[0]
            adj_pairs = sum(
                1 for (op1, v1), (op2, v2) in zip(hot, hot[1:])
                if op1 == 0x21 and op2 == 0x20 and v1 == v2 and v1 is not None and v1 >= 3
            )
            self.assertEqual(adj_pairs, 0, f"{name}: adjacent set/get pair left in hot_work")
            # hot_work acquires no regions and never calls print: zero g3 and zero g0 accesses!
            g3_ops = sum(1 for op, v in hot if op in (0x23, 0x24) and v == 3)
            g0_ops = sum(1 for op, v in hot if op in (0x23, 0x24) and v == 0)
            self.assertEqual(g3_ops, 0, f"{name}: dead global 3 accesses left in hot_work")
            self.assertEqual(g0_ops, 0, f"{name}: dead global 0 accesses left in hot_work")
            # Direct calls to import goose.abort inside hot_work must be outlined to abort helpers!
            direct_abort_calls = sum(1 for op, v in hot if op == 0x10 and v == abort_idx)
            self.assertEqual(direct_abort_calls, 0, f"{name}: inline goose.abort calls not outlined in hot_work")

    def test_region_reclamation_and_print_scratch_and_zero_init_soundness(self):
        source = """struct Pair { a: i64, b: i64 }

fn make_pair(x: i64) -> Pair {
    return Pair { a: x + 1, b: x * 2 };
}

fn cond_loop_init(flag: bool, n: i64) -> i64 {
    var x: i64 = 0;
    for i in 0..n {
        if flag && i == 3 { x = 42; }
    }
    return x;
}

fn region_loop(n: i64) -> i64 {
    var total: i64 = 0;
    for i in 0..n {
        var tmp: i64[>..] = [];
        tmp.push(i);
        tmp.push(i + 1);
        total += tmp[0] + tmp[1];
        if i == n - 1 { break; }
    }
    return total;
}

fn print_break_loop(xs: i64[:]) -> i64 {
    var s: i64 = 0;
    for i in 0..xs.len {
        let sub = xs[0..i + 1];
        if i == 2 {
            print("hit", sub.len);
            break;
        }
        s += sub[i];
    }
    return s;
}

fn main() {
    let p = make_pair(10);
    let z0 = cond_loop_init(false, 5);
    let z1 = cond_loop_init(true, 5);
    let r = region_loop(500);
    let xs: i64[4] = [3, 5, 7, 11];
    let pb = print_break_loop(xs);
    print(p.a, p.b, z0, z1, r, pb);
}
"""
        self.check_matches_native(source, "hit3\n11200422500008\n")

    def test_outlined_abort_preserves_message_and_line(self):
        source = """fn read_at(a: i64[:], i: i64) -> i64 {
    return a[i];
}

fn main() {
    let a: i64[3] = [1, 2, 3];
    print(read_at(a, 5));
}
"""
        nat_bin = self.build_native(source)
        nat = subprocess.run([str(nat_bin)], stdin=subprocess.DEVNULL, capture_output=True, text=True)
        self.assertNotEqual(nat.returncode, 0)
        self.assertIn("out of bounds", nat.stderr)
        self.assertIn(":2)", nat.stderr)
        for extra, name in [
            (("--wasm-bundled-host",), "oob32.wasm"),
            (("--wasm-memory64", "--wasm-bundled-host"), "oob64.wasm"),
        ]:
            wasm = self.emit_wasm(source, *extra, name=name)
            res = run_wasm(wasm)
            self.assertNotEqual(res.returncode, 0, name)
            err = res.stderr.decode(errors="replace")
            self.assertIn("array index out of bounds", err, name)
            self.assertIn("line 2", err, name)


if __name__ == "__main__":
    unittest.main()
