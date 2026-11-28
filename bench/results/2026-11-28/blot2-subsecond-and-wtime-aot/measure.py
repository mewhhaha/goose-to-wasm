#!/usr/bin/env python3
"""Paired alternating benchmark for v2026.4-7 (Track 1 + Track 2 + Track 3):
  1. Blot2 (79.0k LOC, 172 files, 7,961 functions, 84 host imports):
     - Cold vs edited (.life hit) vs unchanged emit across Unprofiled & PGO* v2026.4-7
       (vs pre-Track-1 baseline build/qualify-wasm-opt-v2/bootstrap/bin/goosew)
     - End-to-end edited turnaround (8 cores unpinned, 5 alternating rounds):
       goosew (--cache-dir, .life hit) + goose-wtime-aot --inc-cache (O2 per-fn x64)
       vs goosew + goose-wasmtime --fast-jit (Winch) vs goosew + goose-wtime-aot --fast / O2 cold
     - Single-core CPU 7 hosted Blot2 comparison (for apples-to-apples check vs prior report)
     - Bit-exact SHA-256 verification on fibonacci.blot and matrix_multiply.blot
  2. Suite A — 6 Runtime Benchmarks (CPU 7, 5 alternating rounds):
     - sorting, life, sudoku, sieve, maze, mandelbrot (2048x2048x1000, checksum 1038538536)
     - New v2026.4-7 + optimized wtime-aot x64 vs Wasmtime 50.0.1 (.cwasm) vs Native Clang -O2
     - Plus .wasm size, x64 ELF size, and wtime-aot x64 cold build time
  3. Suite B — selfhost/ (57.5k LOC Wasm64, 3 alternating rounds):
     - Unprofiled & PGO* -O2 emit (--jobs 8), .wasm size, wtime-aot x64 build, standalone ELF self-compile (CPU 7)
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
WORK = ROOT / "build" / "bench-2026-11-28-subsecond"
PIN_CPU = 7

BASELINE = ROOT / "build" / "qualify-wasm-opt-v2" / "bootstrap" / "bin" / "goosew"
CAND_UNPROF = ROOT / "build" / "snapshot76" / "boot-from-75" / "goosew"
CAND_PGO = ROOT / "build" / "snapshot76" / "verify-default" / "bin" / "goosew"
STDLIB = ROOT / "stdlib"
WTIME_AOT = ROOT.parent / "wtime" / "tools" / "wtime-aot" / "target" / "release" / "wtime-aot"
GOOSE_WTIME_AOT = ROOT / "host" / "wtime-aot" / "target" / "release" / "goose-wtime-aot"
GOOSE_WASMTIME = ROOT / "host" / "rust" / "target" / "release" / "goose-wasmtime"
BLOT2_SRC_RO = ROOT / "build" / "blot2-head-probe"
PRIOR_REPORT = ROOT / "bench" / "results" / "2026-11-28" / "wtime-aot-and-codegen" / "results.json"


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
        list(map(str, cmd)),
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
            results[name].append(fn(r))
    summary = {}
    for name, runs in results.items():
        walls = [x["wall_s"] for x in runs]
        row = {
            "median_wall_s": statistics.median(walls),
            "min_wall_s": min(walls),
            "max_wall_s": max(walls),
            "walls_s": [round(w, 6) for w in walls],
        }
        if runs and "extra" in runs[0]:
            row["extras"] = [x["extra"] for x in runs]
        summary[name] = row
    return summary


def main() -> None:
    for p in (BASELINE, CAND_UNPROF, CAND_PGO, WTIME_AOT, GOOSE_WTIME_AOT, GOOSE_WASMTIME, BLOT2_SRC_RO):
        assert p.exists(), f"missing required path: {p}"

    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True)

    # =========================================================================
    # Suite 1: Blot2 (79.0k LOC, 84 imports) — cold, .life edited, and hosted
    # =========================================================================
    print("=== Suite 1: Blot2 Sub-Second Edit -> Native Run (8 cores, 5 alt rounds) ===", flush=True)
    blot_copy = WORK / "blot2"
    shutil.copytree(BLOT2_SRC_RO, blot_copy)
    blot_main = blot_copy / "compiler-goose" / "src" / "main.goose"
    blot_std = blot_copy / "compiler-goose" / "stdlib"
    if not blot_std.is_dir():
        blot_std = STDLIB
    compile_goose = blot_copy / "compiler-goose" / "src" / "compile.goose"
    check_goose = blot_copy / "compiler-goose" / "src" / "check" / "check.goose"
    orig_compile = compile_goose.read_text()
    orig_check = check_goose.read_text()

    def blot_emit_cmd(compiler: Path, opt: str, outp: Path, cache_dir: Path | None, stats_path: Path | None, check_only: bool = False):
        cmd = [
            compiler, blot_main, "--stdlib", blot_std,
            "--target", "wasm-direct", "--wasm-memory64", "--wasm-max-pages", "65536",
            "--library", "--reachable-program", "--expansion-node-limit", "1000000",
            "--jobs", "8", opt,
        ]
        if check_only:
            cmd.append("--check")
        else:
            cmd.extend(["-o", outp])
        if cache_dir is not None:
            cmd.extend(["--cache-dir", cache_dir])
        if stats_path is not None:
            cmd.extend(["--wasm-stats", stats_path])
        return cmd

    # 1a. Cold -O0 emit: Baseline vs Unprofiled v2026.4-7 vs PGO* v2026.4-7 (5 alt rounds)
    def run_blot_cold(compiler: Path, tag: str, r: int):
        outp = WORK / f"blot-cold-{tag}-r{r}.wasm"
        stp = WORK / f"blot-cold-{tag}-r{r}.stats.json"
        res = run_cmd(blot_emit_cmd(compiler, "-O0", outp, None, stp), pin_single=False)
        assert res["rc"] == 0, res["stderr"]
        st = json.loads(stp.read_text())
        res["extra"] = {
            "wasm_bytes": outp.stat().st_size,
            "lifetime_ms": round(st.get("lifetime_ns", 0) / 1e6, 2),
            "life_cache_hit": st.get("life_cache_hit", False),
        }
        return res

    blot_cold_emit = alternating([
        ("baseline_o0_cold", lambda r: run_blot_cold(BASELINE, "base", r)),
        ("unprof_o0_cold", lambda r: run_blot_cold(CAND_UNPROF, "unprof", r)),
        ("pgo_o0_cold", lambda r: run_blot_cold(CAND_PGO, "pgo", r)),
    ], rounds=5)
    print(
        f"  Blot2 cold -O0 emit (--jobs 8): base={blot_cold_emit['baseline_o0_cold']['median_wall_s']*1000:.1f}ms | "
        f"unprof={blot_cold_emit['unprof_o0_cold']['median_wall_s']*1000:.1f}ms | "
        f"pgo*={blot_cold_emit['pgo_o0_cold']['median_wall_s']*1000:.1f}ms",
        flush=True,
    )

    # Prime caches for Unprofiled & PGO* on clean source, and keep reference cold .wasm
    cache_unprof = WORK / "cache-unprof"
    cache_pgo = WORK / "cache-pgo"
    blot_clean_wasm = WORK / "blot-clean-O0.wasm"
    st_prime_u = WORK / "prime-u.stats.json"
    st_prime_p = WORK / "prime-p.stats.json"
    assert run_cmd(blot_emit_cmd(CAND_UNPROF, "-O0", blot_clean_wasm, cache_unprof, st_prime_u), pin_single=False)["rc"] == 0
    assert run_cmd(blot_emit_cmd(CAND_PGO, "-O0", WORK / "blot-clean-pgo.wasm", cache_pgo, st_prime_p), pin_single=False)["rc"] == 0
    assert sha256_file(blot_clean_wasm) == sha256_file(WORK / "blot-clean-pgo.wasm"), "unprof vs PGO blot2 .wasm mismatch!"
    blot_clean_o2_wasm = WORK / "blot-clean-O2.wasm"
    assert run_cmd(blot_emit_cmd(CAND_PGO, "-O2", blot_clean_o2_wasm, None, None), pin_single=False)["rc"] == 0

    # Prime wtime-aot incremental caches (separate for fib & mat, and separate for compile.goose vs check.goose edits)
    fib_file = blot_copy / "benchmarks/idiomatic/fibonacci.blot"
    mat_file = blot_copy / "benchmarks/idiomatic/matrix_multiply.blot"
    std_root = blot_copy / "std"
    prelude = blot_copy / "std/prelude.blot"

    def run_blot_host(cmd_prefix, outp: Path, blot_file: Path, timing_json: Path | None = None, ref_sha: str | None = None, pin_single: bool = False):
        if outp.exists():
            outp.unlink()
        cmd = [*cmd_prefix]
        if timing_json is not None:
            cmd.extend(["--timing-json", timing_json])
        cmd.extend([
            "--entry", "blot_goose_main", "--",
            "build-project", blot_file, outp,
            "--std-root", std_root, "--prelude", prelude,
        ])
        res = run_cmd(cmd, pin_single=pin_single)
        assert res["rc"] == 0, f"host failed ({cmd_prefix}): {res['stderr']}"
        sha = sha256_file(outp)
        if ref_sha is not None:
            assert sha == ref_sha, f"blot2 output mismatch for {cmd_prefix}: {sha} != {ref_sha}"
        extra = {"sha256": sha}
        if timing_json is not None and timing_json.is_file():
            tj = json.loads(timing_json.read_text())
            extra["compile_ms"] = round(tj.get("compile_ns", 0) / 1e6, 2)
            extra["run_ms"] = round(tj.get("run_ns", 0) / 1e6, 2)
        res["extra"] = extra
        return res

    # Establish bit-exact reference SHA-256 via Winch on clean Blot2
    fib_ref_out = WORK / "fib-ref.wasm"
    mat_ref_out = WORK / "mat-ref.wasm"
    fib_sha = run_blot_host([GOOSE_WASMTIME, "--fast-jit", blot_clean_wasm], fib_ref_out, fib_file)["extra"]["sha256"]
    mat_sha = run_blot_host([GOOSE_WASMTIME, "--fast-jit", blot_clean_wasm], mat_ref_out, mat_file)["extra"]["sha256"]
    print(f"  Reference SHAs: fibonacci={fib_sha[:16]}  matrix_multiply={mat_sha[:16]}", flush=True)

    # Prime warm .wtaot cache (unchanged module) and per-function --inc-cache on clean O0 & O2 .wasm
    inc_o0_dir = WORK / "wta-inc-o0"
    inc_o2_dir = WORK / "wta-inc-o2"
    warm_o0_cache = WORK / "blot-clean-O0.wtaot"
    warm_o2_cache = WORK / "blot-clean-O2.wtaot"
    run_blot_host([GOOSE_WTIME_AOT, "--inc-cache", inc_o0_dir, blot_clean_wasm], WORK / "p1.wasm", fib_file, ref_sha=fib_sha)
    run_blot_host([GOOSE_WTIME_AOT, "--inc-cache", inc_o2_dir, blot_clean_o2_wasm], WORK / "p2.wasm", fib_file, ref_sha=fib_sha)
    run_blot_host([GOOSE_WTIME_AOT, "--cache", warm_o0_cache, blot_clean_wasm], WORK / "p3.wasm", fib_file, ref_sha=fib_sha)
    run_blot_host([GOOSE_WTIME_AOT, "--cache", warm_o2_cache, blot_clean_o2_wasm], WORK / "p4.wasm", fib_file, ref_sha=fib_sha)

    # 1b. Edited-file .life emit + --check + unchanged cache hit (5 alternating rounds)
    edit_scenarios = {}
    for edit_name, target_file, orig_text, make_edit in [
        (
            "compile_goose",
            compile_goose,
            orig_compile,
            lambda rev: orig_compile.replace(
                "let built = blot_direct::compileWithStaged(",
                f"var _bench_rev: i64 = {rev}; _bench_rev += 1;\n    let built = blot_direct::compileWithStaged(",
                1,
            ),
        ),
        (
            "check_goose",
            check_goose,
            orig_check,
            lambda rev: orig_check.replace(
                "fn checkedAstList(tree:const blot_parse_ast::Tree&,range:blot_parse_ast::List)->blot_parse_ast::List {let count=tree.list(range).len;return range;}",
                f"fn checkedAstList(tree:const blot_parse_ast::Tree&,range:blot_parse_ast::List)->blot_parse_ast::List {{var _bench_rev:i64={rev};_bench_rev+=1;let count=tree.list(range).len;return range;}}",
                1,
            ),
        ),
    ]:
        # Produce 5 distinct edited .wasm modules (one per round) and time emit + --check
        edited_wasms = []
        edit_emit = {"unprof_o0_edited": [], "pgo_o0_edited": [], "unprof_check_edited": [], "pgo_check_edited": []}
        for r in range(5):
            new_src = make_edit(r + 1)
            assert new_src != orig_text, f"edit did not apply for {edit_name}"
            target_file.write_text(new_src)

            # Alternate unprof / pgo on odd/even rounds
            pair = [("unprof", CAND_UNPROF, cache_unprof), ("pgo", CAND_PGO, cache_pgo)]
            if r % 2 == 1:
                pair.reverse()
            round_wasm = WORK / f"blot-edit-{edit_name}-r{r}.wasm"
            for label, comp, cdir in pair:
                outp = round_wasm if label == "unprof" else WORK / f"blot-edit-{edit_name}-pgo-r{r}.wasm"
                stp = WORK / f"st-{edit_name}-{label}-r{r}.json"
                res = run_cmd(blot_emit_cmd(comp, "-O0", outp, cdir, stp), pin_single=False)
                assert res["rc"] == 0, res["stderr"]
                st = json.loads(stp.read_text())
                assert st.get("life_cache_hit") is True, f"expected .life cache hit for {edit_name}/{label}: {st}"
                res["extra"] = {
                    "lifetime_ms": round(st.get("lifetime_ns", 0) / 1e6, 2),
                    "wasm_bytes": outp.stat().st_size,
                    "life_cache_hit": True,
                }
                edit_emit[f"{label}_o0_edited"].append(res)

                stc = WORK / f"stc-{edit_name}-{label}-r{r}.json"
                resc = run_cmd(blot_emit_cmd(comp, "-O0", outp, cdir, stc, check_only=True), pin_single=False)
                assert resc["rc"] == 0, resc["stderr"]
                stcj = json.loads(stc.read_text())
                assert stcj.get("life_cache_hit") is True, f"expected .life hit in --check: {stcj}"
                resc["extra"] = {"lifetime_ms": round(stcj.get("lifetime_ns", 0) / 1e6, 2), "life_cache_hit": True}
                edit_emit[f"{label}_check_edited"].append(resc)

            assert sha256_file(round_wasm) == sha256_file(WORK / f"blot-edit-{edit_name}-pgo-r{r}.wasm")
            edited_wasms.append(round_wasm)

        # Restore clean source
        target_file.write_text(orig_text)

        # Also time hosted execution on the 5 distinct edited .wasm modules (8-core unpinned!)
        hosted_8c = {}
        for bname, bfile, bsha in [("fibonacci", fib_file, fib_sha), ("matrix_multiply", mat_file, mat_sha)]:
            # Re-prime a fresh per-function inc cache from clean O0 before each benchmark so deltas are real 1-fn edits
            inc_sub = WORK / f"inc-{edit_name}-{bname}"
            shutil.copytree(inc_o0_dir, inc_sub)
            delta_sizes = []

            def run_inc(r, isub=inc_sub, bf=bfile, bs=bsha):
                # Copy clean baseline inc cache per round so every round measures a fresh 1-fn edit against clean!
                rd = WORK / f"inc-run-{edit_name}-{bname}-r{r}"
                if rd.exists():
                    shutil.rmtree(rd)
                shutil.copytree(inc_o0_dir, rd)
                tj = WORK / f"tj-inc-{edit_name}-{bname}-r{r}.json"
                res = run_blot_host([GOOSE_WTIME_AOT, "--inc-cache", rd, edited_wasms[r]], WORK / f"out-inc-{r}.wasm", bf, timing_json=tj, ref_sha=bs, pin_single=False)
                deltas = list((rd / "x64-inc").glob("*.delta"))
                dbytes = sum(d.stat().st_size for d in deltas)
                res["extra"]["delta_bytes"] = dbytes
                delta_sizes.append(dbytes)
                return res

            hosted_8c[bname] = alternating([
                ("winch_o0_cold_8c", lambda r, bf=bfile, bs=bsha: run_blot_host([GOOSE_WASMTIME, "--fast-jit", edited_wasms[r]], WORK / f"out-winch-{r}.wasm", bf, ref_sha=bs, pin_single=False)),
                ("wtime_aot_fast_o0_cold_8c", lambda r, bf=bfile, bs=bsha: run_blot_host([GOOSE_WTIME_AOT, "--fast", edited_wasms[r]], WORK / f"out-wtaf-{r}.wasm", bf, timing_json=WORK / f"tj-wtaf-{edit_name}-{bname}-r{r}.json", ref_sha=bs, pin_single=False)),
                ("wtime_aot_o2_cold_8c", lambda r, bf=bfile, bs=bsha: run_blot_host([GOOSE_WTIME_AOT, edited_wasms[r]], WORK / f"out-wtao2-{r}.wasm", bf, timing_json=WORK / f"tj-wtao2-{edit_name}-{bname}-r{r}.json", ref_sha=bs, pin_single=False)),
                ("wtime_aot_o2_inc_cache_8c", run_inc),
                ("wtime_aot_o2_warm_unchanged_8c", lambda r, bf=bfile, bs=bsha: run_blot_host([GOOSE_WTIME_AOT, "--cache", warm_o0_cache, blot_clean_wasm], WORK / f"out-wtaw-{r}.wasm", bf, timing_json=WORK / f"tj-wtaw-{edit_name}-{bname}-r{r}.json", ref_sha=bs, pin_single=False)),
            ], rounds=5)

        emit_summary = {}
        for k, runs in edit_emit.items():
            walls = [x["wall_s"] for x in runs]
            emit_summary[k] = {
                "median_wall_s": statistics.median(walls),
                "min_wall_s": min(walls),
                "max_wall_s": max(walls),
                "walls_s": [round(w, 6) for w in walls],
                "median_lifetime_ms": statistics.median([x["extra"]["lifetime_ms"] for x in runs]),
            }
        edit_scenarios[edit_name] = {"emit": emit_summary, "hosted_8c": hosted_8c}
        eu = emit_summary["unprof_o0_edited"]["median_wall_s"] * 1000
        ep = emit_summary["pgo_o0_edited"]["median_wall_s"] * 1000
        fib_inc = hosted_8c["fibonacci"]["wtime_aot_o2_inc_cache_8c"]["median_wall_s"] * 1000
        fib_winch = hosted_8c["fibonacci"]["winch_o0_cold_8c"]["median_wall_s"] * 1000
        print(
            f"  Blot2 edit ({edit_name:13s}): emit unprof={eu:.1f}ms (life={emit_summary['unprof_o0_edited']['median_lifetime_ms']:.1f}ms) | "
            f"pgo*={ep:.1f}ms | fib+inc={fib_inc:.1f}ms -> TOTAL unprof={(eu+fib_inc):.1f}ms / pgo*={(ep+fib_inc):.1f}ms | "
            f"fib+winch={fib_winch:.1f}ms -> TOTAL unprof={(eu+fib_winch):.1f}ms",
            flush=True,
        )

    # Also measure single-core CPU 7 hosted Blot2 on clean O0 & edited compile.goose (3 rounds)
    compile_goose.write_text(orig_compile.replace(
        "let built = blot_direct::compileWithStaged(",
        "var _bench_rev: i64 = 99; _bench_rev += 1;\n    let built = blot_direct::compileWithStaged(",
        1,
    ))
    blot_edit_cpu7 = WORK / "blot-edit-cpu7.wasm"
    assert run_cmd(blot_emit_cmd(CAND_PGO, "-O0", blot_edit_cpu7, cache_pgo, None), pin_single=False)["rc"] == 0
    compile_goose.write_text(orig_compile)

    def run_inc_cpu7(r, bf, bs):
        rd = WORK / f"inc-cpu7-{bf.stem}-r{r}"
        if rd.exists():
            shutil.rmtree(rd)
        shutil.copytree(inc_o0_dir, rd)
        return run_blot_host([GOOSE_WTIME_AOT, "--inc-cache", rd, blot_edit_cpu7], WORK / f"out-c7-inc-{r}.wasm", bf, timing_json=WORK / f"tj-c7-inc-{bf.stem}-r{r}.json", ref_sha=bs, pin_single=True)

    hosted_cpu7 = {}
    for bname, bfile, bsha in [("fibonacci", fib_file, fib_sha), ("matrix_multiply", mat_file, mat_sha)]:
        hosted_cpu7[bname] = alternating([
            ("winch_o0_cold_cpu7", lambda r, bf=bfile, bs=bsha: run_blot_host([GOOSE_WASMTIME, "--fast-jit", blot_edit_cpu7], WORK / f"out-c7-winch-{r}.wasm", bf, ref_sha=bs, pin_single=True)),
            ("wtime_aot_fast_o0_cold_cpu7", lambda r, bf=bfile, bs=bsha: run_blot_host([GOOSE_WTIME_AOT, "--fast", blot_edit_cpu7], WORK / f"out-c7-wtaf-{r}.wasm", bf, ref_sha=bs, pin_single=True)),
            ("wtime_aot_o2_inc_cache_cpu7", lambda r, bf=bfile, bs=bsha: run_inc_cpu7(r, bf, bs)),
            ("wtime_aot_o2_warm_cpu7", lambda r, bf=bfile, bs=bsha: run_blot_host([GOOSE_WTIME_AOT, "--cache", warm_o2_cache, blot_clean_o2_wasm], WORK / f"out-c7-wtaw-{r}.wasm", bf, ref_sha=bs, pin_single=True)),
        ], rounds=3)
        print(
            f"  Blot2 CPU 7 ({bname:15s}): winch={hosted_cpu7[bname]['winch_o0_cold_cpu7']['median_wall_s']*1000:.1f}ms | "
            f"wta-fast={hosted_cpu7[bname]['wtime_aot_fast_o0_cold_cpu7']['median_wall_s']*1000:.1f}ms | "
            f"wta-inc={hosted_cpu7[bname]['wtime_aot_o2_inc_cache_cpu7']['median_wall_s']*1000:.1f}ms | "
            f"wta-warm={hosted_cpu7[bname]['wtime_aot_o2_warm_cpu7']['median_wall_s']*1000:.1f}ms",
            flush=True,
        )

    # =========================================================================
    # Suite 2: 6 Runtime Benchmarks (CPU 7, 5 alternating rounds)
    # =========================================================================
    print("\n=== Suite 2: 6 Runtime Benchmarks (CPU 7, 5 alternating rounds) ===", flush=True)
    suite_rt = {}
    suite_sizes = {}
    for ex in ["sorting", "life", "sudoku", "sieve", "maze"]:
        src = ROOT / "examples" / f"{ex}.goose"
        exp = (ROOT / "examples/expected" / f"{ex}.out").read_text()
        w_path = WORK / f"{ex}.wasm"
        x64_path = WORK / f"{ex}.x64"
        nat_path = WORK / f"{ex}-nat"
        assert run_cmd([CAND_PGO, "--target", "wasm-direct", "-O2", "--stdlib", STDLIB, "-o", w_path, src])["rc"] == 0
        assert run_cmd([sys.executable, ROOT / "scripts/goose_wasm.py", "build", src, "--goose", CAND_PGO, "--stdlib", STDLIB, "--backend", "native", "--cc", "clang", "-O2", "-o", nat_path])["rc"] == 0
        w_bytes = w_path.read_bytes()
        prep = run_wasmtime.prepare_module(w_bytes, WORK / f"{ex}.cwasm")

        def build_aot(_r, wp=w_path, op=x64_path):
            if op.exists():
                op.unlink()
            res = run_cmd([WTIME_AOT, wp, "--backend", "x64", "-o", op])
            assert res["rc"] == 0, res["stderr"]
            return res

        aot_t = alternating([("aot_x64_build", build_aot)], rounds=3)
        suite_sizes[ex] = {
            "wasm_bytes": len(w_bytes),
            "x64_bin_bytes": x64_path.stat().st_size,
            "aot_cold_ms": round(aot_t["aot_x64_build"]["median_wall_s"] * 1000.0, 2),
        }

        def run_wt(_r, wb=w_bytes, pr=prep, expected=exp):
            os.sched_setaffinity(0, {PIN_CPU})
            t0 = time.perf_counter()
            res = run_wasmtime.run_module(wb, b"", prepared=pr)
            wall = time.perf_counter() - t0
            assert res["exit_code"] == 0 and res["stdout"].decode("utf-8") == expected
            return {"rc": 0, "wall_s": wall}

        def run_bin(_r, b, expected=exp):
            res = run_cmd([b])
            assert res["rc"] == 0 and res["stdout"] == expected
            return res

        suite_rt[ex] = alternating([
            ("wasmtime", run_wt),
            ("wtime_aot_x64", lambda r, b=x64_path: run_bin(r, b)),
            ("native_o2", lambda r, b=nat_path: run_bin(r, b)),
        ], rounds=5)
        rt = suite_rt[ex]
        print(
            f"  {ex:10s} wasm={len(w_bytes):6d}B | aot={suite_sizes[ex]['aot_cold_ms']:5.2f}ms | "
            f"wt={rt['wasmtime']['median_wall_s']*1000:5.2f}ms | "
            f"wtime-x64={rt['wtime_aot_x64']['median_wall_s']*1000:5.2f}ms | "
            f"nat-O2={rt['native_o2']['median_wall_s']*1000:5.2f}ms",
            flush=True,
        )

    # Mandelbrot 2048x2048x1000 (strict IEEE-754 checksum 1038538536)
    mb_src = ROOT / "bench/langbench/mandelbrot.goose"
    mb_host = ROOT / "bench/host_input.c"
    mb_in = b"2048 1000 1\n"
    mb_wasm = WORK / "mandelbrot.wasm"
    mb_c = WORK / "mandelbrot.c"
    mb_x64 = WORK / "mandelbrot.x64"
    mb_nat = WORK / "mandelbrot-nat"
    assert run_cmd([CAND_PGO, "--target", "wasm-direct", "-O2", "--stdlib", STDLIB, "-o", mb_wasm, mb_src])["rc"] == 0
    assert run_cmd([CAND_PGO, "--target", "c", "-O2", "--stdlib", STDLIB, "-o", mb_c, mb_src])["rc"] == 0
    assert run_cmd(["clang", "-O2", mb_c, mb_host, "-lm", "-lpthread", "-o", mb_nat])["rc"] == 0
    mb_bytes = mb_wasm.read_bytes()
    mb_prep = run_wasmtime.prepare_module(mb_bytes, WORK / "mandelbrot.cwasm")
    mb_aot = alternating([("aot_x64_build", lambda _r: run_cmd([WTIME_AOT, mb_wasm, "--backend", "x64", "-o", mb_x64]))], rounds=3)
    suite_sizes["mandelbrot"] = {
        "wasm_bytes": len(mb_bytes),
        "x64_bin_bytes": mb_x64.stat().st_size,
        "aot_cold_ms": round(mb_aot["aot_x64_build"]["median_wall_s"] * 1000.0, 2),
    }

    def mb_parse(stdout: str) -> float:
        lines = stdout.strip().splitlines()
        assert lines[0].strip() == "1038538536", f"bad mandelbrot checksum: {lines}"
        return int(lines[1].strip()) / 1e9

    def mb_wt(_r):
        os.sched_setaffinity(0, {PIN_CPU})
        res = run_wasmtime.run_module(mb_bytes, mb_in, prepared=mb_prep)
        assert res["exit_code"] == 0
        return {"rc": 0, "wall_s": mb_parse(res["stdout"].decode("utf-8"))}

    def mb_bin(_r, b):
        res = run_cmd([b], stdin_bytes=mb_in)
        assert res["rc"] == 0
        res["wall_s"] = mb_parse(res["stdout"])
        return res

    suite_rt["mandelbrot"] = alternating([
        ("wasmtime", mb_wt),
        ("wtime_aot_x64", lambda r: mb_bin(r, mb_x64)),
        ("native_o2", lambda r: mb_bin(r, mb_nat)),
    ], rounds=5)
    m = suite_rt["mandelbrot"]
    print(
        f"  {'mandelbrot':10s} wasm={len(mb_bytes):6d}B | aot={suite_sizes['mandelbrot']['aot_cold_ms']:5.2f}ms | "
        f"wt={m['wasmtime']['median_wall_s']:.3f}s | wtime-x64={m['wtime_aot_x64']['median_wall_s']:.3f}s | "
        f"nat-O2={m['native_o2']['median_wall_s']:.3f}s",
        flush=True,
    )

    # =========================================================================
    # Suite 3: selfhost/ (57.5k LOC Wasm64, 3 alternating rounds)
    # =========================================================================
    print("\n=== Suite 3: selfhost/ Wasm64 (57.5k LOC, 3 alternating rounds) ===", flush=True)
    sh_wasm = WORK / "selfhost64.wasm"
    sh_emit = alternating([
        ("unprof_o2_8j", lambda r: run_cmd([CAND_UNPROF, "selfhost/main.goose", "--stdlib", STDLIB, "--wasm-memory64", "--wasm-max-pages", "262144", "--jobs", "8", "-O2", "-o", sh_wasm], pin_single=False)),
        ("pgo_o2_8j", lambda r: run_cmd([CAND_PGO, "selfhost/main.goose", "--stdlib", STDLIB, "--wasm-memory64", "--wasm-max-pages", "262144", "--jobs", "8", "-O2", "-o", WORK / "selfhost64-pgo.wasm"], pin_single=False)),
    ], rounds=3)
    assert sha256_file(sh_wasm) == sha256_file(WORK / "selfhost64-pgo.wasm")
    sh_x64 = WORK / "selfhost64.x64"
    sh_aot = alternating([("aot_x64_build_cpu7", lambda _r: run_cmd([WTIME_AOT, sh_wasm, "--backend", "x64", "-o", sh_x64], pin_single=True))], rounds=3)
    sh_ref_sha = sha256_file(sh_wasm)

    def run_sh_self(r):
        outp = WORK / f"sh-self-r{r}.wasm"
        res = run_cmd([sh_x64, "--allow-files", ROOT, "--", "selfhost/main.goose", "--stdlib", STDLIB, "--wasm-memory64", "--wasm-max-pages", "262144", "-O2", "-o", outp], pin_single=True)
        assert res["rc"] == 0, res["stderr"]
        assert sha256_file(outp) == sh_ref_sha, "selfhost64.x64 self-compile output mismatch!"
        return res

    sh_run = alternating([("self_compile_x64_cpu7", run_sh_self)], rounds=3)
    print(
        f"  selfhost64: wasm={sh_wasm.stat().st_size/1048576:.2f}MiB | emit unprof={sh_emit['unprof_o2_8j']['median_wall_s']*1000:.0f}ms / pgo*={sh_emit['pgo_o2_8j']['median_wall_s']*1000:.0f}ms | "
        f"aot={sh_aot['aot_x64_build_cpu7']['median_wall_s']:.3f}s | self-compile={sh_run['self_compile_x64_cpu7']['median_wall_s']:.3f}s (bit-exact)",
        flush=True,
    )

    prior = json.loads(PRIOR_REPORT.read_text()) if PRIOR_REPORT.is_file() else {}
    out_data = {
        "schema": "goose-to-wasm-blot2-subsecond-wtime-aot-v1",
        "date": "2026-11-28",
        "version": "v2026.4-7",
        "cpu": PIN_CPU,
        "host": platform.platform(),
        "clang": subprocess.check_output(["clang", "--version"], text=True).splitlines()[0],
        "wasmtime_py": importlib.metadata.version("wasmtime"),
        "baseline_goosew": str(BASELINE),
        "baseline_sha256": sha256_file(BASELINE),
        "candidate_unprof_goosew": str(CAND_UNPROF),
        "candidate_unprof_sha256": sha256_file(CAND_UNPROF),
        "candidate_pgo_goosew": str(CAND_PGO),
        "candidate_pgo_sha256": sha256_file(CAND_PGO),
        "wtime_git_rev": subprocess.check_output(["git", "-C", str(ROOT.parent / "wtime"), "rev-parse", "HEAD"], text=True).strip(),
        "wtime_aot_sha256": sha256_file(WTIME_AOT),
        "goose_wtime_aot_sha256": sha256_file(GOOSE_WTIME_AOT),
        "goose_wasmtime_sha256": sha256_file(GOOSE_WASMTIME),
        "suite1_blot2": {
            "clean_o0_bytes": blot_clean_wasm.stat().st_size,
            "clean_o2_bytes": blot_clean_o2_wasm.stat().st_size,
            "fibonacci_sha256": fib_sha,
            "matrix_multiply_sha256": mat_sha,
            "cold_emit_8c": blot_cold_emit,
            "edits": edit_scenarios,
            "hosted_cpu7": hosted_cpu7,
        },
        "suite2_runtime_cpu7": {
            "sizes_and_aot": suite_sizes,
            "runtime": suite_rt,
            "prior_wtime_aot_x64_s": {
                k: prior.get("suite_a_runtime", {}).get(k, {}).get("cand_wtime_aot_x64", {}).get("median_wall_s")
                for k in ["sorting", "life", "sudoku", "sieve", "maze", "mandelbrot"]
            },
        },
        "suite3_selfhost64": {
            "wasm_bytes": sh_wasm.stat().st_size,
            "x64_bin_bytes": sh_x64.stat().st_size,
            "emit_o2_8j": sh_emit,
            "wtime_aot_x64_build_cpu7": sh_aot,
            "self_compile_x64_cpu7": sh_run,
            "bit_exact_sha256": sh_ref_sha,
        },
    }
    (OUT_DIR / "results.json").write_text(json.dumps(out_data, indent=2) + "\n")
    print(f"\nWrote {OUT_DIR / 'results.json'}", flush=True)


if __name__ == "__main__":
    main()
