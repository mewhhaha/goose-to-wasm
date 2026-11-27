#!/usr/bin/env python3
"""Benchmark suite for the 2026-11-27 Blot2 turnaround campaign.

Measures:
  1. Batch-by-batch progression on Blot2 -O0 Wasm64 (4D -> A -> B -> C -> D)
  2. Complete Blot2 98f277f2 edit -> compile -> JIT/run turnaround matrix:
     - Unprofiled & fresh Clang-23 PGO emit (-O0, -O2, --check, unmodified --check)
     - Wasm64 size reduction (Batch 4D vs Final)
     - goose-wasmtime cold JIT + run (default speed vs --fast-jit, Batch 4D vs Final Wasm)
     - goose-wasmtime warm .cwasm runs (fibonacci.blot, matrix_multiply.blot)
     - goose-wtime --execution register (Batch 4D vs Final -O2 Wasm)
     - goosew --cache-dir warm hits (--check, -O0 same/new out) & cold miss overhead
  3. 18/18 Blot2 .blot bit-exact parity check under --fast-jit
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[4]
OUT_DIR = Path(__file__).resolve().parent

BLOT_SRC = ROOT / "build/blot2-head-probe/compiler-goose/src/main.goose"
BLOT_RAW = ROOT / "build/probe-life/blot2-raw/compiler-goose/src/main.goose"
BLOT_STD = (ROOT / "../blot2/build/goose-port/upstream-d5ae5bb/source-precision/stdlib").resolve()
BLOT_STD_ROOT = ROOT / "build/blot2-head-probe/std"
BLOT_PRELUDE = BLOT_STD_ROOT / "prelude.blot"
BLOT_BENCH_DIR = ROOT / "build/blot2-head-probe/benchmarks/idiomatic"
BLOT_FLAGS = [
    "--stdlib", str(BLOT_STD),
    "--library", "--reachable-program",
    "--expansion-node-limit", "1000000",
    "--wasm-memory64", "--wasm-max-pages", "65536",
]

HOST_WASMTIME = ROOT / "host/rust/target/release/goose-wasmtime"
HOST_WTIME = ROOT / "host/wtime/target/release/goose-wtime"

BINS = {
    "batch4d_nopgo": ROOT / "build/qualify-batch4d/bootstrap/bin/goosew",
    "batch_a_nopgo": ROOT / "build/qualify-blot2-batch-a/bootstrap/bin/goosew",
    "batch_b_nopgo": ROOT / "build/qualify-blot2-batch-b/bootstrap/bin/goosew",
    "batch_c_nopgo": ROOT / "build/qualify-blot2-batch-c2/bootstrap/bin/goosew",
    "batch_d_nopgo": ROOT / "build/qualify-blot2-batch-d/bootstrap/bin/goosew",
    "batch4d_pgo": ROOT / "build/pgo-batch4d/goosew_pgo",
    "batch_d_pgo": ROOT / "build/pgo-blot2-final/goosew_pgo",
}


def sha256_file(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def run_timed(cmd: list[str], expect_rc: int | None = 0) -> dict:
    t0 = time.perf_counter_ns()
    proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    _, status, rusage = os.wait4(proc.pid, 0)
    wall_ns = time.perf_counter_ns() - t0
    rc = os.waitstatus_to_exitcode(status)
    out = proc.stdout.read().decode("utf-8", errors="replace") if proc.stdout else ""
    err = proc.stderr.read().decode("utf-8", errors="replace") if proc.stderr else ""
    if expect_rc is not None and rc != expect_rc:
        raise RuntimeError(f"Command failed (rc={rc}, expected {expect_rc}): {cmd}\nstderr:\n{err}\nstdout:\n{out}")
    return {
        "wall_ms": round(wall_ns / 1e6, 2),
        "max_rss_kb": rusage.ru_maxrss,
        "rc": rc,
    }


def summarize_runs(runs: list[dict], extra: dict | None = None) -> dict:
    walls = [r["wall_ms"] for r in runs]
    rss = [r["max_rss_kb"] for r in runs]
    res = {
        "median_ms": round(statistics.median(walls), 2),
        "min_ms": round(min(walls), 2),
        "runs_ms": walls,
        "median_max_rss_mib": round(statistics.median(rss) / 1024.0, 1),
    }
    if extra:
        res.update(extra)
    return res


def compile_blot(compiler: Path, opt: str, out_path: Path, stats_path: Path | None = None,
                 extra: list[str] | None = None, src: Path = BLOT_SRC, expect_rc: int = 0) -> dict:
    cmd = [str(compiler), str(src), *BLOT_FLAGS, "--jobs", "8"]
    if opt == "--check":
        cmd.append("--check")
    else:
        cmd.extend([opt, "-o", str(out_path)])
    if stats_path is not None:
        cmd.extend(["--wasm-stats", str(stats_path)])
    if extra:
        cmd.extend(extra)
    r = run_timed(cmd, expect_rc=expect_rc)
    if stats_path is not None and stats_path.exists():
        st = json.loads(stats_path.read_text())
        r["stages_ms"] = {
            "parse_ms": round(st.get("parse_ns", 0) / 1e6, 2),
            "typecheck_ms": round(st.get("typecheck_ns", 0) / 1e6, 2),
            "lifetime_ms": round(st.get("lifetime_ns", 0) / 1e6, 2),
            "typecheck_excl_life_ms": round((st.get("typecheck_ns", 0) - st.get("lifetime_ns", 0)) / 1e6, 2),
            "optimize_ms": round(st.get("optimize_ns", 0) / 1e6, 2),
            "backend_ms": round(st.get("backend_ns", 0) / 1e6, 2),
            "cache_complete": st.get("cache_complete"),
            "cache_hit": st.get("cache_hit"),
        }
    return r


def med_stages(runs: list[dict]) -> dict:
    keys = ["parse_ms", "typecheck_ms", "typecheck_excl_life_ms", "lifetime_ms", "optimize_ms", "backend_ms"]
    return {k: round(statistics.median(r["stages_ms"][k] for r in runs), 2) for k in keys if "stages_ms" in runs[0]}


def main() -> None:
    report: dict = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "binaries": {k: {"path": str(v), "sha256": sha256_file(v)} for k, v in BINS.items()},
        "hosts": {
            "goose_wasmtime": {"path": str(HOST_WASMTIME), "sha256": sha256_file(HOST_WASMTIME)},
            "goose_wtime": {"path": str(HOST_WTIME), "sha256": sha256_file(HOST_WTIME)},
        },
        "blot2_progression_o0_nopgo": {},
        "blot2_emit": {},
        "blot2_jit_and_run": {},
        "blot2_incremental_cache": {},
    }

    with tempfile.TemporaryDirectory(prefix="blot2_final_suite_") as tmpdir:
        tmp = Path(tmpdir)

        # 1. Emit reference Wasm64 modules (Batch 4D vs Final, -O0 and -O2)
        b4d_o0 = tmp / "b4d_o0.wasm"
        b4d_o2 = tmp / "b4d_o2.wasm"
        fin_o0 = tmp / "fin_o0.wasm"
        fin_o2 = tmp / "fin_o2.wasm"
        compile_blot(BINS["batch4d_nopgo"], "-O0", b4d_o0)
        compile_blot(BINS["batch4d_nopgo"], "-O2", b4d_o2)
        compile_blot(BINS["batch_d_nopgo"], "-O0", fin_o0)
        compile_blot(BINS["batch_d_nopgo"], "-O2", fin_o2)

        report["wasm_sizes"] = {
            "batch4d_o0_bytes": b4d_o0.stat().st_size,
            "batch4d_o0_sha256": sha256_file(b4d_o0),
            "batch4d_o2_bytes": b4d_o2.stat().st_size,
            "batch4d_o2_sha256": sha256_file(b4d_o2),
            "final_o0_bytes": fin_o0.stat().st_size,
            "final_o0_sha256": sha256_file(fin_o0),
            "final_o2_bytes": fin_o2.stat().st_size,
            "final_o2_sha256": sha256_file(fin_o2),
        }
        print(f"Wasm64 sizes: -O0 {b4d_o0.stat().st_size/1048576:.2f} -> {fin_o0.stat().st_size/1048576:.2f} MiB | "
              f"-O2 {b4d_o2.stat().st_size/1048576:.2f} -> {fin_o2.stat().st_size/1048576:.2f} MiB")

        # 2. Batch-by-batch interleaved progression (unprofiled --jobs 8, 3 rounds)
        prog_keys = ["batch4d_nopgo", "batch_a_nopgo", "batch_b_nopgo", "batch_c_nopgo", "batch_d_nopgo"]
        prog_runs = {k: [] for k in prog_keys}
        st_path = tmp / "st.json"
        out_path = tmp / "out.wasm"
        for rep in range(3):
            order = prog_keys if rep % 2 == 0 else list(reversed(prog_keys))
            for k in order:
                prog_runs[k].append(compile_blot(BINS[k], "-O0", out_path, st_path))
        for k in prog_keys:
            report["blot2_progression_o0_nopgo"][k] = summarize_runs(
                prog_runs[k], {"stages_ms": med_stages(prog_runs[k])}
            )
            m = report["blot2_progression_o0_nopgo"][k]
            print(f"Progression {k:14s}: {m['median_ms']:7.1f} ms  RSS={m['median_max_rss_mib']:6.1f} MiB  "
                  f"tc={m['stages_ms']['typecheck_excl_life_ms']}  lf={m['stages_ms']['lifetime_ms']}  be={m['stages_ms']['backend_ms']}")

        # 3. Blot2 --check (patched & unmodified §5.2) and -O0/-O2 emit (unprofiled & PGO, 5 rounds)
        for tag, bkey in [("final_nopgo", "batch_d_nopgo"), ("final_pgo", "batch_d_pgo")]:
            for mode_name, opt, src, rc in [
                ("check_patched", "--check", BLOT_SRC, 0),
                ("check_unmodified", "--check", BLOT_RAW, 1),
                ("emit_o0", "-O0", BLOT_SRC, 0),
                ("emit_o2", "-O2", BLOT_SRC, 0),
            ]:
                # warmup
                compile_blot(BINS[bkey], opt, out_path, st_path if rc == 0 else None, src=src, expect_rc=rc)
                runs = [compile_blot(BINS[bkey], opt, out_path, st_path if rc == 0 else None, src=src, expect_rc=rc)
                        for _ in range(5 if mode_name != "check_unmodified" else 3)]
                extra = {"stages_ms": med_stages(runs)} if rc == 0 else {}
                report["blot2_emit"][f"{tag}_{mode_name}"] = summarize_runs(runs, extra)
                m = report["blot2_emit"][f"{tag}_{mode_name}"]
                print(f"Emit {tag}_{mode_name:18s}: {m['median_ms']:7.1f} ms  RSS={m['median_max_rss_mib']:6.1f} MiB")

        # 4. Cold JIT + run & warm .cwasm & goose-wtime (fibonacci.blot & matrix_multiply.blot)
        fib_src = BLOT_BENCH_DIR / "fibonacci.blot"
        mat_src = BLOT_BENCH_DIR / "matrix_multiply.blot"
        fib_out = tmp / "fib.wasm"
        mat_out = tmp / "mat.wasm"

        def run_wasmtime(wasm_path: Path, blot_in: Path, blot_out: Path, fast_jit: bool = False, cache_path: Path | None = None) -> dict:
            cmd = [str(HOST_WASMTIME), str(wasm_path), "--entry", "blot_goose_main"]
            if fast_jit:
                cmd.append("--fast-jit")
            if cache_path is not None:
                cmd.extend(["--cache", str(cache_path)])
            cmd.extend(["--", "build-project", str(blot_in), str(blot_out),
                        "--std-root", str(BLOT_STD_ROOT), "--prelude", str(BLOT_PRELUDE)])
            return run_timed(cmd, expect_rc=0)

        jit_cases = [
            ("batch4d_o0_speed", b4d_o0, False),
            ("batch4d_o0_fast_jit", b4d_o0, True),
            ("final_o0_speed", fin_o0, False),
            ("final_o0_fast_jit", fin_o0, True),
            ("batch4d_o2_speed", b4d_o2, False),
            ("final_o2_speed", fin_o2, False),
            ("final_o2_fast_jit", fin_o2, True),
        ]
        ref_fib_sha = None
        for name, wp, fj in jit_cases:
            # 1 warmup + 5 rounds
            run_wasmtime(wp, fib_src, fib_out, fast_jit=fj)
            runs = []
            for _ in range(5):
                if fib_out.exists():
                    fib_out.unlink()
                runs.append(run_wasmtime(wp, fib_src, fib_out, fast_jit=fj))
                sha = sha256_file(fib_out)
                if ref_fib_sha is None:
                    ref_fib_sha = sha
                else:
                    assert sha == ref_fib_sha, f"fib.wasm mismatch on {name}: {sha} vs {ref_fib_sha}"
            report["blot2_jit_and_run"][f"cold_{name}"] = summarize_runs(runs, {"fib_wasm_sha256": ref_fib_sha})
            m = report["blot2_jit_and_run"][f"cold_{name}"]
            print(f"Cold JIT+run {name:22s}: {m['median_ms']:7.1f} ms  RSS={m['median_max_rss_mib']:6.1f} MiB")

        # Warm .cwasm runs (final_o0 speed & fast-jit, final_o2 speed)
        for name, wp, fj in [
            ("final_o0_speed_fib", fin_o0, False),
            ("final_o0_fast_jit_fib", fin_o0, True),
            ("final_o2_speed_fib", fin_o2, False),
        ]:
            cwasm = tmp / f"{name}.cwasm"
            run_wasmtime(wp, fib_src, fib_out, fast_jit=fj, cache_path=cwasm)
            runs = [run_wasmtime(wp, fib_src, fib_out, fast_jit=fj, cache_path=cwasm) for _ in range(5)]
            assert sha256_file(fib_out) == ref_fib_sha
            report["blot2_jit_and_run"][f"warm_{name}"] = summarize_runs(runs, {"cwasm_bytes": cwasm.stat().st_size})
            m = report["blot2_jit_and_run"][f"warm_{name}"]
            print(f"Warm .cwasm  {name:22s}: {m['median_ms']:7.1f} ms  RSS={m['median_max_rss_mib']:6.1f} MiB")

        # matrix_multiply warm .cwasm
        cwasm_o2 = tmp / "final_o2_speed_fib.cwasm"
        run_wasmtime(fin_o2, mat_src, mat_out, fast_jit=False, cache_path=cwasm_o2)
        mat_runs = [run_wasmtime(fin_o2, mat_src, mat_out, fast_jit=False, cache_path=cwasm_o2) for _ in range(5)]
        report["blot2_jit_and_run"]["warm_final_o2_speed_mat"] = summarize_runs(mat_runs, {"mat_wasm_sha256": sha256_file(mat_out)})

        # Safe-Rust goose-wtime --execution register (Batch 4D -O2 vs Final -O2, 3 rounds)
        for name, wp in [("batch4d_o2", b4d_o2), ("final_o2", fin_o2), ("final_o0", fin_o0)]:
            cmd = [str(HOST_WTIME), str(wp), "--entry", "blot_goose_main",
                   "--execution", "register", "--max-instructions", "10000000000",
                   "--", "build-project", str(fib_src), str(fib_out),
                   "--std-root", str(BLOT_STD_ROOT), "--prelude", str(BLOT_PRELUDE)]
            runs = []
            for _ in range(3):
                if fib_out.exists():
                    fib_out.unlink()
                runs.append(run_timed(cmd, expect_rc=0))
                assert sha256_file(fib_out) == ref_fib_sha
            report["blot2_jit_and_run"][f"wtime_register_{name}"] = summarize_runs(runs, {"fib_wasm_sha256": ref_fib_sha})
            m = report["blot2_jit_and_run"][f"wtime_register_{name}"]
            print(f"wtime reg    {name:22s}: {m['median_ms']:7.1f} ms  RSS={m['median_max_rss_mib']:6.1f} MiB")

        # 5. Incremental --cache-dir benchmarks (unprofiled & PGO, 5 rounds each)
        for tag, bkey in [("final_nopgo", "batch_d_nopgo"), ("final_pgo", "batch_d_pgo")]:
            cdir = tmp / f"cache_{tag}"
            cout = tmp / f"cache_out_{tag}.wasm"
            cout2 = tmp / f"cache_out2_{tag}.wasm"
            # Cold miss (-O0 & --check)
            r_miss_o0 = compile_blot(BINS[bkey], "-O0", cout, st_path, extra=["--cache-dir", str(cdir)])
            assert r_miss_o0["stages_ms"]["cache_complete"] is True and r_miss_o0["stages_ms"]["cache_hit"] is False
            r_miss_chk = compile_blot(BINS[bkey], "--check", cout, st_path, extra=["--cache-dir", str(cdir)])
            assert r_miss_chk["stages_ms"]["cache_complete"] is True and r_miss_chk["stages_ms"]["cache_hit"] is False

            # Warm hits (5 rounds each)
            hit_same = []
            hit_new = []
            hit_chk = []
            for _ in range(5):
                r1 = compile_blot(BINS[bkey], "-O0", cout, st_path, extra=["--cache-dir", str(cdir)])
                assert r1["stages_ms"]["cache_hit"] is True
                hit_same.append(r1)
                if cout2.exists():
                    cout2.unlink()
                r2 = compile_blot(BINS[bkey], "-O0", cout2, st_path, extra=["--cache-dir", str(cdir)])
                assert r2["stages_ms"]["cache_hit"] is True
                assert sha256_file(cout2) == report["wasm_sizes"]["final_o0_sha256"]
                hit_new.append(r2)
                r3 = compile_blot(BINS[bkey], "--check", cout, st_path, extra=["--cache-dir", str(cdir)])
                assert r3["stages_ms"]["cache_hit"] is True
                hit_chk.append(r3)

            report["blot2_incremental_cache"][tag] = {
                "cold_miss_o0_ms": r_miss_o0["wall_ms"],
                "cold_miss_check_ms": r_miss_chk["wall_ms"],
                "warm_hit_o0_same_out": summarize_runs(hit_same),
                "warm_hit_o0_new_out": summarize_runs(hit_new),
                "warm_hit_check": summarize_runs(hit_chk),
            }
            ic = report["blot2_incremental_cache"][tag]
            print(f"Cache {tag:12s}: --check hit={ic['warm_hit_check']['median_ms']:.1f} ms | "
                  f"-O0 same={ic['warm_hit_o0_same_out']['median_ms']:.1f} ms | "
                  f"-O0 new={ic['warm_hit_o0_new_out']['median_ms']:.1f} ms")

        # 6. Verify 18/18 .blot bit-exact parity (final_o0 --fast-jit vs batch4d_o0 speed)
        parity = {"total": 0, "compiled_match": 0, "expected_rc1": 0}
        cw_ref = tmp / "parity_ref.cwasm"
        cw_new = tmp / "parity_new.cwasm"
        for bf in sorted(BLOT_BENCH_DIR.glob("*.blot")):
            parity["total"] += 1
            o_ref = tmp / f"p_ref_{bf.stem}.wasm"
            o_new = tmp / f"p_new_{bf.stem}.wasm"
            r_ref = run_timed([str(HOST_WASMTIME), str(b4d_o0), "--entry", "blot_goose_main", "--cache", str(cw_ref),
                               "--", "build-project", str(bf), str(o_ref),
                               "--std-root", str(BLOT_STD_ROOT), "--prelude", str(BLOT_PRELUDE)], expect_rc=None)
            r_new = run_timed([str(HOST_WASMTIME), str(fin_o0), "--entry", "blot_goose_main", "--fast-jit", "--cache", str(cw_new),
                               "--", "build-project", str(bf), str(o_new),
                               "--std-root", str(BLOT_STD_ROOT), "--prelude", str(BLOT_PRELUDE)], expect_rc=None)
            assert r_ref["rc"] == r_new["rc"], f"rc mismatch on {bf.name}: {r_ref['rc']} vs {r_new['rc']}"
            if r_ref["rc"] == 0:
                assert sha256_file(o_ref) == sha256_file(o_new), f"wasm mismatch on {bf.name}"
                parity["compiled_match"] += 1
            else:
                parity["expected_rc1"] += 1
        report["blot2_parity_18"] = parity
        print("Blot2 18-benchmark parity:", parity)

    out_json = OUT_DIR / "blot2_turnaround.json"
    out_json.write_text(json.dumps(report, indent=2) + "\n")
    print("Wrote", out_json)


if __name__ == "__main__":
    main()
