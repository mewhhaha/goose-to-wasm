#!/usr/bin/env python3
"""Paired alternating benchmark for Item 1 + Item 2 + Item 3:
  - Baseline: e0d95bd (build/qualify-wtime-cli-v2/bootstrap/bin/goosew)
  - Candidate: Wasm codegen + peephole + BCE batch (build/qualify-wasm-opt-v2/bootstrap/bin/goosew)

Measures (pinned CPU 7, alternating rounds):
  Suite A: 6 runtime benchmarks (sorting, life, sudoku, sieve, maze, mandelbrot 2048x2048)
           - .wasm size, wtime-aot x64 cold build time & binary size
           - Wasmtime (.cwasm), wtime-aot --backend x64, and native Clang -O2 runtimes
  Suite B: Large real-world Wasm64 workloads
           - selfhost/ (57.5k LOC): .wasm size, wtime-aot x64 & aarch64 cold build, standalone ELF self-compile
           - blot2 (79.0k LOC, 84 host imports): .wasm size (-O0/-O2), goose-wtime-aot (--fast, O2, --cache)
             vs goose-wasmtime --fast-jit (Winch) on fibonacci.blot & matrix_multiply.blot (SHA-256 verified)
"""
from __future__ import annotations

import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "scripts"))
import run_wasmtime  # noqa: E402

OUT_DIR = Path(__file__).resolve().parent
WORK = ROOT / "build" / "bench-2026-11-28-work"
PIN_CPU = 7

BASELINE = ROOT / "build" / "qualify-wtime-cli-v2" / "bootstrap" / "bin" / "goosew"
CANDIDATE = ROOT / "build" / "qualify-wasm-opt-v2" / "bootstrap" / "bin" / "goosew"
UPSTREAM = ROOT / "build" / "native" / "goose"
STDLIB = ROOT / "stdlib"
WTIME_AOT = ROOT.parent / "wtime" / "tools" / "wtime-aot" / "target" / "release" / "wtime-aot"
GOOSE_WTIME_AOT = ROOT / "host" / "wtime-aot" / "target" / "release" / "goose-wtime-aot"
GOOSE_WASMTIME = ROOT / "host" / "rust" / "target" / "release" / "goose-wasmtime"
BLOT2_DIR = ROOT / "build" / "blot2-head-probe"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def run_cmd(cmd, *, cwd=ROOT, env=None, stdin_bytes=b"", timeout_s=180, pin_single=True):
    def _pin():
        if pin_single:
            os.sched_setaffinity(0, {PIN_CPU})

    t0 = time.perf_counter()
    p = subprocess.run(
        cmd,
        cwd=str(cwd),
        env=env,
        input=stdin_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout_s,
        preexec_fn=_pin if pin_single else None,
    )
    wall = time.perf_counter() - t0
    return {
        "rc": p.returncode,
        "wall_s": wall,
        "stdout": p.stdout.decode("utf-8", "replace"),
        "stderr": p.stderr.decode("utf-8", "replace"),
    }


def alternating(items, rounds=5):
    results = {name: [] for name, _ in items}
    for r in range(rounds):
        order = items if r % 2 == 0 else list(reversed(items))
        for name, fn in order:
            results[name].append(fn())
    summary = {}
    for name, runs in results.items():
        walls = [x["wall_s"] for x in runs]
        summary[name] = {
            "median_wall_s": statistics.median(walls),
            "min_wall_s": min(walls),
            "max_wall_s": max(walls),
            "walls_s": [round(w, 6) for w in walls],
        }
    return summary


def main() -> None:
    for p in (BASELINE, CANDIDATE, WTIME_AOT, GOOSE_WTIME_AOT, GOOSE_WASMTIME):
        assert p.is_file(), f"missing binary: {p}"

    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True)

    base_env = dict(os.environ)

    # ---- Suite A: 6 runtime benchmarks (CPU 7, 5 alternating rounds) ----
    suite_a = {}
    sizes_and_aot = {}
    rt_examples = ["sorting", "life", "sudoku", "sieve", "maze"]

    print("=== Suite A: 6 Runtime Benchmarks (CPU 7, 5 alternating rounds) ===", flush=True)
    for ex in rt_examples:
        src = ROOT / "examples" / f"{ex}.goose"
        exp = (ROOT / "examples/expected" / f"{ex}.out").read_text()

        base_wasm = WORK / f"{ex}-base.wasm"
        cand_wasm = WORK / f"{ex}-cand.wasm"
        cand_nat = WORK / f"{ex}-cand-nat"

        r = run_cmd([str(BASELINE), "--target", "wasm-direct", "-O2", "--stdlib", str(STDLIB), "-o", str(base_wasm), str(src)])
        assert r["rc"] == 0, r["stderr"]
        r = run_cmd([str(CANDIDATE), "--target", "wasm-direct", "-O2", "--stdlib", str(STDLIB), "-o", str(cand_wasm), str(src)])
        assert r["rc"] == 0, r["stderr"]
        r = run_cmd([sys.executable, str(ROOT / "scripts/goose_wasm.py"), "build", str(src), "--goose", str(CANDIDATE), "--stdlib", str(STDLIB), "--backend", "native", "--cc", "clang", "-O2", "-o", str(cand_nat)])
        assert r["rc"] == 0, r["stderr"]

        base_bytes = base_wasm.read_bytes()
        cand_bytes = cand_wasm.read_bytes()
        base_prep = run_wasmtime.prepare_module(base_bytes, WORK / f"{ex}-base.cwasm")
        cand_prep = run_wasmtime.prepare_module(cand_bytes, WORK / f"{ex}-cand.cwasm")

        base_x64 = WORK / f"{ex}-base.x64"
        cand_x64 = WORK / f"{ex}-cand.x64"

        def build_aot(wpath, outp):
            if outp.exists():
                outp.unlink()
            res = run_cmd([str(WTIME_AOT), str(wpath), "--backend", "x64", "-o", str(outp)])
            assert res["rc"] == 0, res["stderr"]
            return res

        aot_timing = alternating([
            ("base_aot_x64_build", lambda wp=base_wasm, op=base_x64: build_aot(wp, op)),
            ("cand_aot_x64_build", lambda wp=cand_wasm, op=cand_x64: build_aot(wp, op)),
        ], rounds=3)

        sizes_and_aot[ex] = {
            "base_wasm_bytes": len(base_bytes),
            "cand_wasm_bytes": len(cand_bytes),
            "wasm_delta_pct": round((len(cand_bytes) - len(base_bytes)) / len(base_bytes) * 100.0, 2),
            "base_x64_bin_bytes": base_x64.stat().st_size,
            "cand_x64_bin_bytes": cand_x64.stat().st_size,
            "base_aot_cold_ms": round(aot_timing["base_aot_x64_build"]["median_wall_s"] * 1000.0, 2),
            "cand_aot_cold_ms": round(aot_timing["cand_aot_x64_build"]["median_wall_s"] * 1000.0, 2),
        }

        def run_wt(wb, pr, expected=exp):
            os.sched_setaffinity(0, {PIN_CPU})
            t0 = time.perf_counter()
            res = run_wasmtime.run_module(wb, b"", prepared=pr)
            wall = time.perf_counter() - t0
            assert res["exit_code"] == 0 and res["stdout"].decode("utf-8") == expected
            return {"rc": 0, "wall_s": wall}

        def run_bin(b, expected=exp):
            res = run_cmd([str(b)])
            assert res["rc"] == 0 and res["stdout"] == expected
            return res

        res = alternating([
            ("base_wasmtime", lambda wb=base_bytes, pr=base_prep: run_wt(wb, pr)),
            ("cand_wasmtime", lambda wb=cand_bytes, pr=cand_prep: run_wt(wb, pr)),
            ("base_wtime_aot_x64", lambda b=base_x64: run_bin(b)),
            ("cand_wtime_aot_x64", lambda b=cand_x64: run_bin(b)),
            ("cand_native_o2", lambda b=cand_nat: run_bin(b)),
        ], rounds=5)
        suite_a[ex] = res
        s = sizes_and_aot[ex]
        print(
            f"  {ex:10s} wasm={s['base_wasm_bytes']//1024}K->{s['cand_wasm_bytes']//1024}K ({s['wasm_delta_pct']:+.1f}%) | "
            f"wt={res['base_wasmtime']['median_wall_s']*1000:5.2f}->{res['cand_wasmtime']['median_wall_s']*1000:5.2f}ms | "
            f"x64={res['base_wtime_aot_x64']['median_wall_s']*1000:5.2f}->{res['cand_wtime_aot_x64']['median_wall_s']*1000:5.2f}ms "
            f"(aot {s['base_aot_cold_ms']:.1f}->{s['cand_aot_cold_ms']:.1f}ms) | "
            f"nat={res['cand_native_o2']['median_wall_s']*1000:5.2f}ms",
            flush=True,
        )

    # Mandelbrot 2048x2048 (kernel clock)
    mb_src = ROOT / "bench/langbench/mandelbrot.goose"
    mb_host = ROOT / "bench/host_input.c"
    mb_in = b"2048 1000 1\n"
    mb_base_wasm = WORK / "mb-base.wasm"
    mb_cand_wasm = WORK / "mb-cand.wasm"
    mb_cand_c = WORK / "mb-cand.c"
    mb_cand_nat = WORK / "mb-cand-nat"

    assert run_cmd([str(BASELINE), "--target", "wasm-direct", "-O2", "--stdlib", str(STDLIB), "-o", str(mb_base_wasm), str(mb_src)])["rc"] == 0
    assert run_cmd([str(CANDIDATE), "--target", "wasm-direct", "-O2", "--stdlib", str(STDLIB), "-o", str(mb_cand_wasm), str(mb_src)])["rc"] == 0
    assert run_cmd([str(CANDIDATE), "--target", "c", "-O2", "--stdlib", str(STDLIB), "-o", str(mb_cand_c), str(mb_src)])["rc"] == 0
    assert run_cmd(["clang", "-O2", str(mb_cand_c), str(mb_host), "-lm", "-lpthread", "-o", str(mb_cand_nat)])["rc"] == 0

    mb_base_bytes = mb_base_wasm.read_bytes()
    mb_cand_bytes = mb_cand_wasm.read_bytes()
    mb_base_prep = run_wasmtime.prepare_module(mb_base_bytes, WORK / "mb-base.cwasm")
    mb_cand_prep = run_wasmtime.prepare_module(mb_cand_bytes, WORK / "mb-cand.cwasm")

    mb_base_x64 = WORK / "mb-base.x64"
    mb_cand_x64 = WORK / "mb-cand.x64"

    def build_mb_aot(wpath, outp):
        if outp.exists():
            outp.unlink()
        res = run_cmd([str(WTIME_AOT), str(wpath), "--backend", "x64", "-o", str(outp)])
        assert res["rc"] == 0, res["stderr"]
        return res

    mb_aot = alternating([
        ("base_aot_x64_build", lambda: build_mb_aot(mb_base_wasm, mb_base_x64)),
        ("cand_aot_x64_build", lambda: build_mb_aot(mb_cand_wasm, mb_cand_x64)),
    ], rounds=3)

    sizes_and_aot["mandelbrot"] = {
        "base_wasm_bytes": len(mb_base_bytes),
        "cand_wasm_bytes": len(mb_cand_bytes),
        "wasm_delta_pct": round((len(mb_cand_bytes) - len(mb_base_bytes)) / len(mb_base_bytes) * 100.0, 2),
        "base_x64_bin_bytes": mb_base_x64.stat().st_size,
        "cand_x64_bin_bytes": mb_cand_x64.stat().st_size,
        "base_aot_cold_ms": round(mb_aot["base_aot_x64_build"]["median_wall_s"] * 1000.0, 2),
        "cand_aot_cold_ms": round(mb_aot["cand_aot_x64_build"]["median_wall_s"] * 1000.0, 2),
    }

    def mb_parse(stdout: str) -> float:
        lines = stdout.strip().splitlines()
        assert lines[0].strip() == "1038538536", f"bad mandelbrot checksum: {lines}"
        return int(lines[1].strip()) / 1e9

    def mb_wt(wb, pr):
        os.sched_setaffinity(0, {PIN_CPU})
        res = run_wasmtime.run_module(wb, mb_in, prepared=pr)
        assert res["exit_code"] == 0
        return {"rc": 0, "wall_s": mb_parse(res["stdout"].decode("utf-8"))}

    def mb_bin(b):
        res = run_cmd([str(b)], stdin_bytes=mb_in)
        assert res["rc"] == 0
        res["wall_s"] = mb_parse(res["stdout"])
        return res

    suite_a["mandelbrot"] = alternating([
        ("base_wasmtime", lambda: mb_wt(mb_base_bytes, mb_base_prep)),
        ("cand_wasmtime", lambda: mb_wt(mb_cand_bytes, mb_cand_prep)),
        ("base_wtime_aot_x64", lambda: mb_bin(mb_base_x64)),
        ("cand_wtime_aot_x64", lambda: mb_bin(mb_cand_x64)),
        ("cand_native_o2", lambda: mb_bin(mb_cand_nat)),
    ], rounds=5)
    m = suite_a["mandelbrot"]
    s = sizes_and_aot["mandelbrot"]
    print(
        f"  {'mandelbrot':10s} wasm={s['base_wasm_bytes']//1024}K->{s['cand_wasm_bytes']//1024}K ({s['wasm_delta_pct']:+.1f}%) | "
        f"wt={m['base_wasmtime']['median_wall_s']:.3f}->{m['cand_wasmtime']['median_wall_s']:.3f}s | "
        f"x64={m['base_wtime_aot_x64']['median_wall_s']:.3f}->{m['cand_wtime_aot_x64']['median_wall_s']:.3f}s "
        f"(aot {s['base_aot_cold_ms']:.1f}->{s['cand_aot_cold_ms']:.1f}ms) | "
        f"nat={m['cand_native_o2']['median_wall_s']:.3f}s",
        flush=True,
    )

    # ---- Suite B: Large real-world Wasm64 workloads (selfhost + blot2) ----
    suite_b = {}
    print("\n=== Suite B: Large Wasm64 Workloads (selfhost + blot2) ===", flush=True)

    # B1: selfhost/ Wasm64
    sh_base = WORK / "selfhost64-base.wasm"
    sh_cand = WORK / "selfhost64-cand.wasm"

    sh_emit = alternating([
        ("base_selfhost_o2", lambda: run_cmd([str(BASELINE), "selfhost/main.goose", "--stdlib", str(STDLIB), "--wasm-memory64", "--wasm-max-pages", "262144", "--jobs", "8", "-O2", "-o", str(sh_base)], pin_single=False)),
        ("cand_selfhost_o2", lambda: run_cmd([str(CANDIDATE), "selfhost/main.goose", "--stdlib", str(STDLIB), "--wasm-memory64", "--wasm-max-pages", "262144", "--jobs", "8", "-O2", "-o", str(sh_cand)], pin_single=False)),
    ], rounds=3)
    assert sh_base.is_file() and sh_cand.is_file()

    sh_base_x64 = WORK / "selfhost64-base.x64"
    sh_cand_x64 = WORK / "selfhost64-cand.x64"
    sh_cand_arm = WORK / "selfhost64-cand.aarch64"

    sh_aot = alternating([
        ("base_x64_aot", lambda: run_cmd([str(WTIME_AOT), str(sh_base), "--backend", "x64", "-o", str(sh_base_x64)], pin_single=True)),
        ("cand_x64_aot", lambda: run_cmd([str(WTIME_AOT), str(sh_cand), "--backend", "x64", "-o", str(sh_cand_x64)], pin_single=True)),
    ], rounds=3)
    arm_res = run_cmd([str(WTIME_AOT), str(sh_cand), "--backend", "aarch64", "-o", str(sh_cand_arm)], pin_single=True)
    assert arm_res["rc"] == 0, arm_res["stderr"]

    # Standalone selfhost64.x64 self-compiling selfhost/main.goose (single-threaded inside wasm64, pinned CPU 7)
    sh_self_base_out = WORK / "sh-self-base.wasm"
    sh_self_cand_out = WORK / "sh-self-cand.wasm"
    sh_self_nat_out = WORK / "sh-self-nat.wasm"
    assert run_cmd([str(CANDIDATE), "selfhost/main.goose", "--stdlib", str(STDLIB), "--wasm-memory64", "--wasm-max-pages", "262144", "-O2", "-o", str(sh_self_nat_out)], pin_single=False)["rc"] == 0
    sh_nat_sha = sha256_file(sh_self_nat_out)

    def run_sh_bin(binp, outp, check_sha=None):
        res = run_cmd([str(binp), "--allow-files", str(ROOT), "--", "selfhost/main.goose", "--stdlib", str(STDLIB), "--wasm-memory64", "--wasm-max-pages", "262144", "-O2", "-o", str(outp)], pin_single=True)
        assert res["rc"] == 0, res["stderr"]
        if check_sha is not None:
            assert sha256_file(outp) == check_sha, "selfhost64.x64 output mismatch vs native goosew!"
        return res

    sh_run = alternating([
        ("base_selfhost_x64_run", lambda: run_sh_bin(sh_base_x64, sh_self_base_out)),
        ("cand_selfhost_x64_run", lambda: run_sh_bin(sh_cand_x64, sh_self_cand_out, sh_nat_sha)),
    ], rounds=3)

    suite_b["selfhost64"] = {
        "base_wasm_bytes": sh_base.stat().st_size,
        "cand_wasm_bytes": sh_cand.stat().st_size,
        "wasm_delta_pct": round((sh_cand.stat().st_size - sh_base.stat().st_size) / sh_base.stat().st_size * 100.0, 2),
        "base_x64_bin_bytes": sh_base_x64.stat().st_size,
        "cand_x64_bin_bytes": sh_cand_x64.stat().st_size,
        "cand_aarch64_bin_bytes": sh_cand_arm.stat().st_size,
        "cand_aarch64_aot_ms": round(arm_res["wall_s"] * 1000.0, 2),
        "emit_o2_8j": sh_emit,
        "wtime_aot_x64_build": sh_aot,
        "self_compile_x64_run": sh_run,
        "self_compile_bit_exact_sha256": sh_nat_sha,
    }
    print(
        f"  selfhost64 wasm={sh_base.stat().st_size/1048576:.2f}->{sh_cand.stat().st_size/1048576:.2f} MiB ({suite_b['selfhost64']['wasm_delta_pct']:+.1f}%) | "
        f"aot-x64={sh_aot['base_x64_aot']['median_wall_s']*1000:.0f}->{sh_aot['cand_x64_aot']['median_wall_s']*1000:.0f}ms | "
        f"self-compile={sh_run['base_selfhost_x64_run']['median_wall_s']:.3f}->{sh_run['cand_selfhost_x64_run']['median_wall_s']:.3f}s (bit-exact) | "
        f"aarch64={arm_res['wall_s']*1000:.0f}ms ({sh_cand_arm.stat().st_size/1048576:.2f} MiB)",
        flush=True,
    )

    # B2: Blot2 (79.0k LOC, 84 host imports) if present
    blot_main = BLOT2_DIR / "compiler-goose" / "src" / "main.goose"
    if blot_main.is_file():
        blot_std = BLOT2_DIR / "compiler-goose" / "stdlib"
        if not blot_std.is_dir():
            blot_std = STDLIB
        blot_base_o0 = WORK / "blot2-base-O0.wasm"
        blot_cand_o0 = WORK / "blot2-cand-O0.wasm"
        blot_base_o2 = WORK / "blot2-base-O2.wasm"
        blot_cand_o2 = WORK / "blot2-cand-O2.wasm"

        def blot_build(compiler, opt, outp):
            res = run_cmd([
                str(compiler), str(blot_main), "--stdlib", str(blot_std),
                "--target", "wasm-direct", "--wasm-memory64", "--wasm-max-pages", "65536",
                "--library", "--reachable-program", "--expansion-node-limit", "1000000",
                "--jobs", "8", opt, "-o", str(outp),
            ], pin_single=False)
            assert res["rc"] == 0, res["stderr"]
            return res

        blot_emit_o0 = alternating([
            ("base_blot2_o0", lambda: blot_build(BASELINE, "-O0", blot_base_o0)),
            ("cand_blot2_o0", lambda: blot_build(CANDIDATE, "-O0", blot_cand_o0)),
        ], rounds=3)
        blot_emit_o2 = alternating([
            ("base_blot2_o2", lambda: blot_build(BASELINE, "-O2", blot_base_o2)),
            ("cand_blot2_o2", lambda: blot_build(CANDIDATE, "-O2", blot_cand_o2)),
        ], rounds=3)

        # Run fibonacci.blot and matrix_multiply.blot via goose-wasmtime (--fast-jit) and goose-wtime-aot (--fast, O2, --cache)
        blot_cases = {}
        blot_cache = WORK / "blot2-cand-O2.wtaot"
        # Prime cache once and capture O2 cold time separately in alternating loop
        for bname, blot_file in [
            ("fibonacci", BLOT2_DIR / "benchmarks/idiomatic/fibonacci.blot"),
            ("matrix_multiply", BLOT2_DIR / "benchmarks/idiomatic/matrix_multiply.blot"),
        ]:
            out_winch = WORK / f"{bname}-winch.wasm"
            out_wta_fast = WORK / f"{bname}-wta-fast.wasm"
            out_wta_o2 = WORK / f"{bname}-wta-o2.wasm"
            out_wta_warm = WORK / f"{bname}-wta-warm.wasm"
            common_tail = [
                "--entry", "blot_goose_main", "--",
                "build-project", str(blot_file), "{OUT}",
                "--std-root", str(BLOT2_DIR / "std"), "--prelude", str(BLOT2_DIR / "std/prelude.blot"),
            ]

            def run_blot(cmd_prefix, outp, ref_sha=None):
                cmd = [*cmd_prefix, *[c.replace("{OUT}", str(outp)) for c in common_tail]]
                res = run_cmd(cmd, pin_single=True)
                assert res["rc"] == 0, res["stderr"]
                sha = sha256_file(outp)
                if ref_sha is not None:
                    assert sha == ref_sha, f"blot2 output mismatch for {cmd_prefix}: {sha} != {ref_sha}"
                return res

            # Establish reference sha with Winch on candidate O0
            r_ref = run_blot([str(GOOSE_WASMTIME), "--fast-jit", str(blot_cand_o0)], out_winch)
            ref_sha = sha256_file(out_winch)
            # Prime warm cache for cand O2
            if not blot_cache.is_file():
                run_blot([str(GOOSE_WTIME_AOT), "--cache", str(blot_cache), str(blot_cand_o2)], out_wta_warm, ref_sha)

            runs = alternating([
                ("winch_cand_o0_cold", lambda: run_blot([str(GOOSE_WASMTIME), "--fast-jit", str(blot_cand_o0)], out_winch, ref_sha)),
                ("wtime_aot_fast_cand_o0_cold", lambda: run_blot([str(GOOSE_WTIME_AOT), "--fast", str(blot_cand_o0)], out_wta_fast, ref_sha)),
                ("wtime_aot_o2_cand_o2_cold", lambda: run_blot([str(GOOSE_WTIME_AOT), str(blot_cand_o2)], out_wta_o2, ref_sha)),
                ("wtime_aot_o2_cand_o2_warm", lambda: run_blot([str(GOOSE_WTIME_AOT), "--cache", str(blot_cache), str(blot_cand_o2)], out_wta_warm, ref_sha)),
            ], rounds=3)
            blot_cases[bname] = {"sha256": ref_sha, "runs": runs}
            print(
                f"  blot2/{bname:15s} winch-O0={runs['winch_cand_o0_cold']['median_wall_s']*1000:6.1f}ms | "
                f"wta-fast-O0={runs['wtime_aot_fast_cand_o0_cold']['median_wall_s']*1000:6.1f}ms | "
                f"wta-O2-cold={runs['wtime_aot_o2_cand_o2_cold']['median_wall_s']*1000:6.1f}ms | "
                f"wta-O2-warm={runs['wtime_aot_o2_cand_o2_warm']['median_wall_s']*1000:5.1f}ms (sha={ref_sha[:12]})",
                flush=True,
            )

        suite_b["blot2"] = {
            "base_o0_bytes": blot_base_o0.stat().st_size,
            "cand_o0_bytes": blot_cand_o0.stat().st_size,
            "o0_delta_pct": round((blot_cand_o0.stat().st_size - blot_base_o0.stat().st_size) / blot_base_o0.stat().st_size * 100.0, 2),
            "base_o2_bytes": blot_base_o2.stat().st_size,
            "cand_o2_bytes": blot_cand_o2.stat().st_size,
            "o2_delta_pct": round((blot_cand_o2.stat().st_size - blot_base_o2.stat().st_size) / blot_base_o2.stat().st_size * 100.0, 2),
            "emit_o0_8j": blot_emit_o0,
            "emit_o2_8j": blot_emit_o2,
            "cases": blot_cases,
        }
        print(
            f"  blot2 sizes: O0 {blot_base_o0.stat().st_size/1048576:.2f}->{blot_cand_o0.stat().st_size/1048576:.2f} MiB ({suite_b['blot2']['o0_delta_pct']:+.1f}%) | "
            f"O2 {blot_base_o2.stat().st_size/1048576:.2f}->{blot_cand_o2.stat().st_size/1048576:.2f} MiB ({suite_b['blot2']['o2_delta_pct']:+.1f}%)",
            flush=True,
        )

    out_data = {
        "schema": "goose-to-wasm-wtime-aot-codegen-v1",
        "date": "2026-11-28",
        "cpu": PIN_CPU,
        "host": platform.platform(),
        "clang": subprocess.check_output(["clang", "--version"], text=True).splitlines()[0],
        "wasmtime_py": importlib.metadata.version("wasmtime"),
        "baseline_goosew": str(BASELINE),
        "baseline_sha256": sha256_file(BASELINE),
        "candidate_goosew": str(CANDIDATE),
        "candidate_sha256": sha256_file(CANDIDATE),
        "wtime_git_rev": subprocess.check_output(["git", "-C", str(ROOT.parent / "wtime"), "rev-parse", "HEAD"], text=True).strip(),
        "wtime_aot_sha256": sha256_file(WTIME_AOT),
        "goose_wtime_aot_sha256": sha256_file(GOOSE_WTIME_AOT),
        "goose_wasmtime_sha256": sha256_file(GOOSE_WASMTIME),
        "suite_a_sizes_and_aot": sizes_and_aot,
        "suite_a_runtime": suite_a,
        "suite_b_large_wasm64": suite_b,
    }
    (OUT_DIR / "results.json").write_text(json.dumps(out_data, indent=2) + "\n")
    print(f"\nWrote {OUT_DIR / 'results.json'}")


if __name__ == "__main__":
    main()
