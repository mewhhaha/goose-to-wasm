#!/usr/bin/env python3
"""Benchmark suite for the 2026-11-27 lifetime optimization campaign.

Measures (using strictly frozen inputs and pinned binaries):
  1. Unprofiled 1-unit progression (--jobs 8, 5 interleaved rounds):
     v2026.4-4 (8cf23ee) -> Batch 1 (b75c334) -> Batch 2 / HEAD (9ca5ad7)
     on Blot2 -O0 Wasm64, Blot2 --check, and selfhost_f746c6e --check.
  2. Complete Blot2 98f277f2 turnaround matrix (unprofiled 9ca5ad7 & separate
     fresh Clang-23 PGO 9ca5ad7 reference run, --jobs 8, 5 rounds + warmup):
     - --check (patched & unmodified §5.2 rc=1), -O0 Wasm64, -O2 Wasm64,
       selfhost_f746c6e --check
     - --jobs 1 == --jobs 8 SHA-256 bit-identity on Blot2 -O0 Wasm64
     - Exact 24 Wasm64 imports on selfhost/main.goose
     - goose-wasmtime cold --fast-jit & speed JIT + run (fibonacci.blot),
       warm .cwasm (fibonacci.blot & matrix_multiply.blot),
       safe-Rust goose-wtime --execution register (-O2 & -O0),
       incremental --cache-dir warm hits (--check & -O0)
  3. 18/18 Blot2 .blot bit-exact parity check under --fast-jit.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import platform
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

SELFHOST_FROZEN_SRC = ROOT / "build/bench-workloads/2026-11-26/selfhost_f746c6e/selfhost/main.goose"
SELFHOST_FROZEN_STD = ROOT / "build/bench-workloads/2026-11-26/selfhost_f746c6e/stdlib"

HOST_WASMTIME = ROOT / "host/rust/target/release/goose-wasmtime"
HOST_WTIME = ROOT / "host/wtime/target/release/goose-wtime"

BINS = {
    "v2026_4_4_nopgo": ROOT / "build/qualify-release-v2026.4-4/bootstrap/bin/goosew",
    "batch1_nopgo": ROOT / "build/qualify-life-b1/bootstrap/bin/goosew",
    "batch2_nopgo": ROOT / "build/qualify-life-b2/bootstrap/bin/goosew",
    "v2026_4_4_pgo": ROOT / "build/pgo-blot2-final/goosew_pgo",
    "batch2_pgo": ROOT / "build/pgo-life-final/goosew_pgo",
    "batch4d_nopgo": ROOT / "build/qualify-batch4d/bootstrap/bin/goosew",
}


def sha256_file(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def count_wasm_imports(wasm_path: Path) -> int:
    data = wasm_path.read_bytes()
    i = 8

    def uleb(b: bytes, pos: int) -> tuple[int, int]:
        val, shift = 0, 0
        while True:
            x = b[pos]
            pos += 1
            val |= (x & 0x7F) << shift
            if (x & 0x80) == 0:
                return val, pos
            shift += 7

    while i < len(data):
        sec = data[i]
        i += 1
        sz, i = uleb(data, i)
        if sec == 2:
            cnt, _ = uleb(data, i)
            return cnt
        i += sz
    return 0


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
                 extra: list[str] | None = None, src: Path = BLOT_SRC, expect_rc: int = 0,
                 jobs: int = 8) -> dict:
    cmd = [str(compiler), str(src), *BLOT_FLAGS, "--jobs", str(jobs)]
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


def compile_selfhost_check(compiler: Path, stats_path: Path, jobs: int = 8) -> dict:
    cmd = [str(compiler), str(SELFHOST_FROZEN_SRC), "--stdlib", str(SELFHOST_FROZEN_STD),
           "--check", "--jobs", str(jobs), "--wasm-stats", str(stats_path)]
    r = run_timed(cmd, expect_rc=0)
    st = json.loads(stats_path.read_text())
    r["stages_ms"] = {
        "parse_ms": round(st.get("parse_ns", 0) / 1e6, 2),
        "typecheck_ms": round(st.get("typecheck_ns", 0) / 1e6, 2),
        "lifetime_ms": round(st.get("lifetime_ns", 0) / 1e6, 2),
        "typecheck_excl_life_ms": round((st.get("typecheck_ns", 0) - st.get("lifetime_ns", 0)) / 1e6, 2),
        "optimize_ms": round(st.get("optimize_ns", 0) / 1e6, 2),
        "backend_ms": round(st.get("backend_ns", 0) / 1e6, 2),
    }
    return r


def med_stages(runs: list[dict]) -> dict:
    keys = ["parse_ms", "typecheck_ms", "typecheck_excl_life_ms", "lifetime_ms", "optimize_ms", "backend_ms"]
    return {k: round(statistics.median(r["stages_ms"][k] for r in runs), 2) for k in keys if "stages_ms" in runs[0]}


def main() -> None:
    clang_ver = subprocess.check_output(["clang", "--version"], text=True).splitlines()[0]
    head_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report: dict = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "head_commit": head_sha,
        "environment": {
            "kernel": platform.release(),
            "machine": platform.machine(),
            "clang": clang_ver,
        },
        "binaries": {k: {"path": str(v), "sha256": sha256_file(v)} for k, v in BINS.items()},
        "hosts": {
            "goose_wasmtime": {"path": str(HOST_WASMTIME), "sha256": sha256_file(HOST_WASMTIME)},
            "goose_wtime": {"path": str(HOST_WTIME), "sha256": sha256_file(HOST_WTIME)},
        },
        "progression_nopgo_j8": {},
        "blot2_emit": {},
        "blot2_jit_and_run": {},
        "blot2_incremental_cache": {},
    }

    with tempfile.TemporaryDirectory(prefix="life_campaign_suite_") as tmpdir:
        tmp = Path(tmpdir)
        st_path = tmp / "st.json"
        out_path = tmp / "out.wasm"

        # 0. Verify Wasm64 sizes, --jobs 1 == --jobs 8 SHA-256, and exact 24 selfhost Wasm64 imports
        b4d_o0 = tmp / "b4d_o0.wasm"
        v4_o0 = tmp / "v4_o0.wasm"
        fin_o0_j8 = tmp / "fin_o0_j8.wasm"
        fin_o0_j1 = tmp / "fin_o0_j1.wasm"
        fin_o2 = tmp / "fin_o2.wasm"
        sh_wasm = tmp / "selfhost_head.wasm"

        compile_blot(BINS["batch4d_nopgo"], "-O0", b4d_o0)
        compile_blot(BINS["v2026_4_4_nopgo"], "-O0", v4_o0)
        compile_blot(BINS["batch2_nopgo"], "-O0", fin_o0_j8, jobs=8)
        compile_blot(BINS["batch2_nopgo"], "-O0", fin_o0_j1, jobs=1)
        compile_blot(BINS["batch2_nopgo"], "-O2", fin_o2, jobs=8)
        run_timed([str(BINS["batch2_nopgo"]), str(ROOT / "selfhost/main.goose"),
                   "--target", "wasm-direct", "--wasm-memory64", "-O0", "--jobs", "8", "-o", str(sh_wasm)])

        sha_v4 = sha256_file(v4_o0)
        sha_j8 = sha256_file(fin_o0_j8)
        sha_j1 = sha256_file(fin_o0_j1)
        assert sha_j8 == sha_j1, f"j8 vs j1 mismatch: {sha_j8} vs {sha_j1}"
        assert sha_j8 == sha_v4, f"HEAD vs v2026.4-4 mismatch: {sha_j8} vs {sha_v4}"
        sh_imports = count_wasm_imports(sh_wasm)
        assert sh_imports == 24, f"Expected 24 imports, got {sh_imports}"

        report["invariants"] = {
            "blot2_o0_bytes": fin_o0_j8.stat().st_size,
            "blot2_o0_sha256": sha_j8,
            "blot2_o0_j1_eq_j8": True,
            "blot2_o0_eq_v2026_4_4": True,
            "blot2_o2_bytes": fin_o2.stat().st_size,
            "blot2_o2_sha256": sha256_file(fin_o2),
            "selfhost_wasm64_imports": sh_imports,
        }
        print(f"Invariants OK: Blot2 -O0={fin_o0_j8.stat().st_size/1048576:.2f} MiB sha={sha_j8[:12]}... (j1==j8==v2026.4-4), selfhost imports={sh_imports}")

        # 1. Interleaved unprofiled 1-unit progression (v2026.4-4 -> Batch 1 -> Batch 2, 5 rounds)
        prog_keys = ["v2026_4_4_nopgo", "batch1_nopgo", "batch2_nopgo"]
        for wname in ("blot2_o0_wasm64", "blot2_check_patched", "selfhost_check"):
            # warmup
            for k in prog_keys:
                if wname == "blot2_o0_wasm64":
                    compile_blot(BINS[k], "-O0", out_path, st_path)
                elif wname == "blot2_check_patched":
                    compile_blot(BINS[k], "--check", out_path, st_path)
                else:
                    compile_selfhost_check(BINS[k], st_path)
            runs_by_k = {k: [] for k in prog_keys}
            for rep in range(5):
                order = prog_keys if rep % 2 == 0 else list(reversed(prog_keys))
                for k in order:
                    if wname == "blot2_o0_wasm64":
                        runs_by_k[k].append(compile_blot(BINS[k], "-O0", out_path, st_path))
                    elif wname == "blot2_check_patched":
                        runs_by_k[k].append(compile_blot(BINS[k], "--check", out_path, st_path))
                    else:
                        runs_by_k[k].append(compile_selfhost_check(BINS[k], st_path))
            report["progression_nopgo_j8"][wname] = {}
            for k in prog_keys:
                s = summarize_runs(runs_by_k[k], {"stages_ms": med_stages(runs_by_k[k])})
                report["progression_nopgo_j8"][wname][k] = s
                print(f"Prog {wname:20s} {k:16s}: {s['median_ms']:7.1f} ms  lf={s['stages_ms']['lifetime_ms']:6.1f} ms  RSS={s['median_max_rss_mib']:6.1f} MiB")

        # 2. Complete Blot2 & selfhost --check emit matrix (unprofiled 9ca5ad7 & separate PGO 9ca5ad7, 5 rounds)
        for tag, bkey in [("final_nopgo", "batch2_nopgo"), ("final_pgo", "batch2_pgo")]:
            for mode_name, opt, src, rc in [
                ("check_patched", "--check", BLOT_SRC, 0),
                ("check_unmodified", "--check", BLOT_RAW, 1),
                ("emit_o0", "-O0", BLOT_SRC, 0),
                ("emit_o2", "-O2", BLOT_SRC, 0),
            ]:
                compile_blot(BINS[bkey], opt, out_path, st_path if rc == 0 else None, src=src, expect_rc=rc)
                runs = [compile_blot(BINS[bkey], opt, out_path, st_path if rc == 0 else None, src=src, expect_rc=rc)
                        for _ in range(5 if mode_name != "check_unmodified" else 3)]
                extra = {"stages_ms": med_stages(runs)} if rc == 0 else {}
                report["blot2_emit"][f"{tag}_{mode_name}"] = summarize_runs(runs, extra)
                m = report["blot2_emit"][f"{tag}_{mode_name}"]
                lf = m["stages_ms"]["lifetime_ms"] if "stages_ms" in m else "-"
                print(f"Emit {tag}_{mode_name:18s}: {m['median_ms']:7.1f} ms  lf={lf}  RSS={m['median_max_rss_mib']:6.1f} MiB")

            # selfhost_f746c6e --check
            compile_selfhost_check(BINS[bkey], st_path)
            sh_runs = [compile_selfhost_check(BINS[bkey], st_path) for _ in range(5)]
            report["blot2_emit"][f"{tag}_selfhost_check"] = summarize_runs(sh_runs, {"stages_ms": med_stages(sh_runs)})
            m = report["blot2_emit"][f"{tag}_selfhost_check"]
            print(f"Emit {tag}_selfhost_check    : {m['median_ms']:7.1f} ms  lf={m['stages_ms']['lifetime_ms']}  RSS={m['median_max_rss_mib']:6.1f} MiB")

        # 3. Host cold JIT + run, warm .cwasm, safe-Rust goose-wtime
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

        ref_fib_sha = None
        for name, wp, fj in [
            ("final_o0_speed", fin_o0_j8, False),
            ("final_o0_fast_jit", fin_o0_j8, True),
            ("final_o2_fast_jit", fin_o2, True),
        ]:
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
                    assert sha == ref_fib_sha
            report["blot2_jit_and_run"][f"cold_{name}"] = summarize_runs(runs, {"fib_wasm_sha256": ref_fib_sha})
            m = report["blot2_jit_and_run"][f"cold_{name}"]
            print(f"Cold JIT+run {name:22s}: {m['median_ms']:7.1f} ms  RSS={m['median_max_rss_mib']:6.1f} MiB")

        for name, wp, fj in [
            ("final_o0_fast_jit_fib", fin_o0_j8, True),
            ("final_o2_speed_fib", fin_o2, False),
        ]:
            cwasm = tmp / f"{name}.cwasm"
            run_wasmtime(wp, fib_src, fib_out, fast_jit=fj, cache_path=cwasm)
            runs = [run_wasmtime(wp, fib_src, fib_out, fast_jit=fj, cache_path=cwasm) for _ in range(5)]
            assert sha256_file(fib_out) == ref_fib_sha
            report["blot2_jit_and_run"][f"warm_{name}"] = summarize_runs(runs, {"cwasm_bytes": cwasm.stat().st_size})
            m = report["blot2_jit_and_run"][f"warm_{name}"]
            print(f"Warm .cwasm  {name:22s}: {m['median_ms']:7.1f} ms  RSS={m['median_max_rss_mib']:6.1f} MiB")

        cwasm_o2 = tmp / "final_o2_speed_fib.cwasm"
        run_wasmtime(fin_o2, mat_src, mat_out, fast_jit=False, cache_path=cwasm_o2)
        mat_runs = [run_wasmtime(fin_o2, mat_src, mat_out, fast_jit=False, cache_path=cwasm_o2) for _ in range(5)]
        report["blot2_jit_and_run"]["warm_final_o2_speed_mat"] = summarize_runs(mat_runs, {"mat_wasm_sha256": sha256_file(mat_out)})

        # Safe-Rust goose-wtime --execution register (-O2, 3 rounds)
        cmd_wt = [str(HOST_WTIME), str(fin_o2), "--entry", "blot_goose_main",
                  "--execution", "register", "--max-instructions", "10000000000",
                  "--", "build-project", str(fib_src), str(fib_out),
                  "--std-root", str(BLOT_STD_ROOT), "--prelude", str(BLOT_PRELUDE)]
        wt_runs = []
        for _ in range(3):
            if fib_out.exists():
                fib_out.unlink()
            wt_runs.append(run_timed(cmd_wt, expect_rc=0))
            assert sha256_file(fib_out) == ref_fib_sha
        report["blot2_jit_and_run"]["wtime_register_final_o2"] = summarize_runs(wt_runs, {"fib_wasm_sha256": ref_fib_sha})
        m = report["blot2_jit_and_run"]["wtime_register_final_o2"]
        print(f"wtime reg    final_o2              : {m['median_ms']:7.1f} ms  RSS={m['median_max_rss_mib']:6.1f} MiB")

        # 4. Incremental --cache-dir warm hits (unprofiled 9ca5ad7)
        cdir = tmp / "cache_nopgo"
        cout = tmp / "cache_out.wasm"
        compile_blot(BINS["batch2_nopgo"], "-O0", cout, st_path, extra=["--cache-dir", str(cdir)])
        compile_blot(BINS["batch2_nopgo"], "--check", cout, st_path, extra=["--cache-dir", str(cdir)])
        hit_o0 = []
        hit_chk = []
        for _ in range(5):
            r1 = compile_blot(BINS["batch2_nopgo"], "-O0", cout, st_path, extra=["--cache-dir", str(cdir)])
            assert r1["stages_ms"]["cache_hit"] is True
            hit_o0.append(r1)
            r2 = compile_blot(BINS["batch2_nopgo"], "--check", cout, st_path, extra=["--cache-dir", str(cdir)])
            assert r2["stages_ms"]["cache_hit"] is True
            hit_chk.append(r2)
        report["blot2_incremental_cache"]["final_nopgo"] = {
            "warm_hit_o0_same_out": summarize_runs(hit_o0),
            "warm_hit_check": summarize_runs(hit_chk),
        }
        print(f"Cache final_nopgo: --check={report['blot2_incremental_cache']['final_nopgo']['warm_hit_check']['median_ms']:.1f} ms | "
              f"-O0={report['blot2_incremental_cache']['final_nopgo']['warm_hit_o0_same_out']['median_ms']:.1f} ms")

        # 5. 18/18 .blot bit-exact parity (final_o0 --fast-jit vs batch4d_o0 speed)
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
            r_new = run_timed([str(HOST_WASMTIME), str(fin_o0_j8), "--entry", "blot_goose_main", "--fast-jit", "--cache", str(cw_new),
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

    out_json = OUT_DIR / "lifetime_turnaround.json"
    out_json.write_text(json.dumps(report, indent=2) + "\n")
    print("Wrote", out_json)


if __name__ == "__main__":
    main()
