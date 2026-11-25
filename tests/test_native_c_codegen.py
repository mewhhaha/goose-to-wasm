#!/usr/bin/env python3
"""Verify native C codegen quality and runtime contracts under Clang and GCC."""
from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT / "scripts/goose_wasm.py"
COMPILER = Path(os.environ.get("GOOSE_COMPILER", ROOT / "build/bin/goosew")).resolve()
STDLIB = Path(os.environ.get("GOOSE_STDLIB", COMPILER.parent / "stdlib")).resolve()


def available_compilers() -> list[str]:
    compilers = []
    for name in ("clang", "gcc"):
        if shutil.which(name):
            compilers.append(name)
    return compilers


@unittest.skipUnless(COMPILER.is_file(), "bootstrap the compiler first")
class NativeCCodegen(unittest.TestCase):
    def setUp(self):
        work = tempfile.TemporaryDirectory()
        self.addCleanup(work.cleanup)
        self.work = Path(work.name)

    def emit_c(self, source: str, *extra: str, name: str = "prog.c") -> str:
        src = self.work / "prog.goose"
        src.write_text(source)
        out = self.work / name
        res = subprocess.run(
            [str(COMPILER), str(src), "--stdlib", str(STDLIB), "--target", "native", "-O2", *extra, "-o", str(out)],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        return out.read_text()

    def build_and_run(self, source: str, cc: str, jobs: int = 1, extra_flags: tuple[str, ...] = (), name: str = "prog") -> subprocess.CompletedProcess[str]:
        src = self.work / (name + ".goose")
        src.write_text(source)
        out_bin = self.work / f"{name}-{cc}-j{jobs}"
        build_dir = self.work / f"build-{name}-{cc}-j{jobs}"
        cmd = [
            str(ROOT / ".venv/bin/python"), str(DRIVER), "build",
            "--backend", "native", "--cc", cc, "--jobs", str(jobs),
            "--goose", str(COMPILER), "--stdlib", str(STDLIB), "-O2",
            "--no-cache", "--build-dir", str(build_dir),
            "-o", str(out_bin), *extra_flags, str(src),
        ]
        res = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=120)
        self.assertEqual(res.returncode, 0, f"{cc} -j{jobs}:\n{res.stdout}\n{res.stderr}")
        return subprocess.run([str(out_bin)], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)

    def test_emitted_c_structural_properties(self):
        source = """
struct Padded { tag: u8, pad 3, value: i64, flag: bool, small: u16 }
struct Inner { a: i32, b: i64 }
struct Outer { head: u8, inner: Inner, tail: i64 }

fn bump(p: Padded&, delta: i64) -> i64 {
    p.value += delta;
    p.tag = (p.tag as i64 + 1) as u8;
    return p.value + (p.tag as i64);
}

fn fill_and_sum(n: i64) -> i64 {
    var xs: Padded[>..] = [];
    for i in n {
        xs.push(Padded { tag: (i & 7) as u8, value: i * 3, flag: (i & 1) == 0, small: (i & 15) as u16 });
    }
    var sum: i64 = 0;
    for i in xs.len {
        sum += bump(xs[i], 2);
    }
    var o = Outer { head: 5, inner: Inner { a: 7, b: 11 }, tail: 13 };
    return sum + (o.head as i64) + (o.inner.a as i64) + o.inner.b + o.tail;
}

recursive fn fib(n: i64) -> i64 {
    if n <= 1 { return n; }
    return fib(n - 1) + fib(n - 2);
}

fn main() {
    print(fill_and_sum(10), " ", fib(10));
}
"""
        c_text = self.emit_c(source)
        prog_c = c_text.split("G_FN void g_initialize(void);", 1)[1]
        # No dead scope publication wrappers or empty watermark calls.
        self.assertNotIn("g_scope_publications", prog_c)
        self.assertNotIn("g_mark_regions(g_base,0,NULL)", prog_c)
        # Packed struct typedefs with explicit padding and direct field access.
        self.assertIn("#pragma pack(push,1)\ntypedef struct {", prog_c)
        self.assertIn("g_p0[3];", prog_c)
        self.assertIn(")->f", prog_c)
        self.assertIn(".f0=", prog_c)
        # Simple .push uses g_push_slot_nn without passing &g_v... to g_push_nn.
        self.assertIn("g_push_slot_nn(", prog_c)
        self.assertNotIn("g_push_nn(", prog_c)
        # Ordinary functions omit GClosure *g_env.
        self.assertNotRegex(prog_c, r"g_fn\d+\(GClosure \*g_env,")
        # Recursive function keeps g_stack_check(), ordinary non-recursive functions omit it.
        fn_bodies = re.findall(r"G_L\d+ [^\n]+ g_fn\d+\([^\n]*\) \{.*?\n\}\n", prog_c, re.S)
        checked = [b for b in fn_bodies if "g_stack_check();" in b]
        unchecked = [b for b in fn_bodies if "g_stack_check();" not in b]
        self.assertEqual(len(checked), 1, "only recursive fib should emit g_stack_check()")
        self.assertGreaterEqual(len(unchecked), 1, "non-recursive functions should omit g_stack_check()")

        for cc in available_compilers():
            for jobs in (1, 3):
                run = self.build_and_run(source, cc, jobs=jobs, name="struct")
                self.assertEqual(run.returncode, 0, run.stderr)
                self.assertEqual(run.stdout, "230 55\n")

    def test_closures_callbacks_nonlocal_and_defer(self):
        source = """
fn apply(x: i64, f: fn(i64) -> i64) -> i64 {
    return f(x);
}

fn double_it(x: i64) -> i64 {
    return x * 2;
}

fn call_each(xs: const i64[:], f: fn(i64)) {
    for v in xs { f(v); }
}

recursive fn find_first_gt(xs: const i64[:], limit: i64, log: u8[>..]&) -> i64 {
    defer { log.append("D"); }
    fn check(v: i64) {
        if v > limit {
            log.append("H");
            return v from find_first_gt;
        }
    }
    call_each(xs, check);
    log.append("M");
    return -1;
}

fn build_pair(n: i64) -> i64[>..], u8[>..] {
    var nums: i64[>..] = [];
    var text: u8[>..] = [];
    for i in n {
        nums.push(i * i);
        text.append("a");
    }
    nums.resize(n + 2, 99);
    let last = nums.pop();
    nums.append([last, 7]);
    return nums, text;
}

fn main() {
    var offset: i64 = 10;
    fn add_off(v: i64) -> i64 { return v + offset; }
    let r1 = apply(5, add_off);
    let r2 = apply(5, double_it);
    var log: u8[>..] = [];
    let found = find_first_gt([1, 4, 9, 2], 5, log);
    let miss = find_first_gt([1, 2], 5, log);
    let nums, text = build_pair(4);
    print(r1, " ", r2, " ", found, " ", miss, " ", log, " ", nums.len, " ", nums[nums.len - 2], " ", text);
}
"""
        c_text = self.emit_c(source, name="closures.c")
        prog_c = c_text.split("G_FN void g_initialize(void);", 1)[1]
        # Functions used as closures/function values MUST carry GClosure *g_env.
        self.assertRegex(prog_c, r"g_fn\d+\(GClosure \*g_env,")
        # Plain direct-only functions (main, apply, build_pair) omit GClosure *g_env.
        self.assertRegex(prog_c, r"g_fn\d+\(int64_t g_base")

        for cc in available_compilers():
            for jobs in (1, 3):
                run = self.build_and_run(source, cc, jobs=jobs, name="closures")
                self.assertEqual(run.returncode, 0, run.stderr)
                self.assertEqual(run.stdout, "15 10 9 -1 HDMD 7 99 aaaa\n")

    def test_recursive_stack_overflow_and_data_stack_overflow(self):
        rec_source = """
recursive fn dive(n: i64, acc: i64) -> i64 {
    var buf: i64[64] = [n; 64];
    buf[acc & 63] = n ^ acc;
    if n <= 0 { return buf[0]; }
    let r = dive(n - 1, acc + buf[n & 63]);
    return r + buf[(r ^ n) & 63];
}
fn main() {
    print(dive(1000000, 1));
}
"""
        data_source = """
struct Item { a: i64, b: i64 }
fn main() {
    var xs: Item[>..] = [];
    for i in 100000 {
        xs.push(Item { a: i, b: i + 1 });
    }
    print(xs.len);
}
"""
        data_c = self.work / "data-ovf.c"
        data_c.write_text(self.emit_c(data_source, "--stack-reserve", "128K", name="data-ovf-emit.c"))
        for cc in available_compilers():
            rec = self.build_and_run(rec_source, cc, jobs=1, name="rec-ovf")
            self.assertNotEqual(rec.returncode, 0, f"{cc}: expected stack overflow failure")
            self.assertIn("native call stack overflow", rec.stderr)

            data_bin = self.work / f"data-ovf-{cc}"
            subprocess.run(
                [cc, "-std=gnu11", "-O2", str(data_c), "-lm", "-ldl", "-pthread", "-o", str(data_bin)],
                stdin=subprocess.DEVNULL, capture_output=True, text=True, check=True, timeout=60,
            )
            data = subprocess.run([str(data_bin)], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
            self.assertNotEqual(data.returncode, 0, f"{cc}: expected data stack overflow failure")
            self.assertIn("data stack overflow", data.stderr)


if __name__ == "__main__":
    unittest.main()
