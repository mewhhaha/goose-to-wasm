#!/usr/bin/env python3
"""Comprehensive pinned benchmark suite for the 2026-11-27 Four-Levers Campaign.

Measures (all using frozen inputs, read-only sibling repos, and pinned binaries):
  1. Matched unprofiled Clang-23 -O2 5-way paired alternating progression (--jobs 8, 5 rounds):
     v2026.4-4 (8cf23ee) -> Lifetime B2 (9ca5ad7) -> Lever 1 (0e5e241) -> Lever 3 (0496493) -> Lever 4 (7c75334)
     across Blot2 (-O0 Wasm64, -O2 Wasm64, -O0 C, --check patched),
     selfhost_f746c6e (-O0 Wasm64, -O2 Wasm64, --check),
     flat_multi_100k (-O0 Wasm64), and flat_multi_250k (-O0 Wasm64).
  2. Separate Fresh Clang-23 PGO reference run (--jobs 8, 5 alternating rounds):
     v2026.4-4 PGO -> Lifetime B2 PGO -> Final Lever 4 PGO across the same workloads.
  3. Unmodified Blot2 §5.2 negative check (rc=1 at check/check.goose:5049:86),
     --jobs 1 == --jobs 8 determinism, and exact 24 selfhost Wasm64 imports.
  4. Lever 3 edited-file incremental --cache-dir turnaround (unprofiled & separate PGO, 5 rounds + warmup)
     on an isolated scratch copy of Blot2 98f277f2:
     - Cold miss (-O0 & --check) + .life certificate size
     - Unchanged cache hits (--check, -O0 same out, -O0 new out)
     - Edited-file rebuilds with verified life_cache_hit=true:
       * check/check.goose (911 KiB) --check scalar+if+let edit
       * check/check.goose (911 KiB) -O0 EOF comment edit
       * check/check.goose (911 KiB) -O0 scalar+if+let edit
       * compile.goose -O0 scalar+if+let edit (+ Winch execution verification on fibonacci.blot)
       * check/diagnostic_code.goose -O0 string-literal edit
  5. Lever 4 cold JIT + run, warm .cwasm, safe-Rust goose-wtime, and 18/18 .blot bit-exact parity:
     - v2026.4-4 (9.45 MiB) vs Final Lever 4 (8.34 MiB) -O0 Wasm64 under Winch --fast-jit & Cranelift speed
     - Final Lever 4 -O2 Wasm64 (12.79 MiB) under Winch --fast-jit & Cranelift speed
     - fibonacci.blot & matrix_multiply.blot (cold & warm .cwasm)
     - Safe-Rust goose-wtime --execution register (-O2 & -O0, 3 rounds)
     - Full 18/18 .blot bit-exact parity (16/16 SHA-256 identical .wasm + 2/2 identical rc=1).
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[4]
OUT_DIR = Path(__file__).resolve().parent

BLOT_DIR = ROOT / "build/blot2-head-probe"
BLOT_SRC = BLOT_DIR / "compiler-goose/src/main.goose"
BLOT_RAW = ROOT / "build/probe-life/blot2-raw/compiler-goose/src/main.goose"
BLOT_STD = (ROOT / "../blot2/build/goose-port/upstream-d5ae5bb/source-precision/stdlib").resolve()
BLOT_STD_ROOT = BLOT_DIR / "std"
BLOT_PRELUDE = BLOT_STD_ROOT / "prelude.blot"
BLOT_BENCH_DIR = BLOT_DIR / "benchmarks/idiomatic"
BLOT_FLAGS = [
    "--stdlib", str(BLOT_STD),
    "--library", "--reachable-program",
    "--expansion-node-limit", "1000000",
    "--wasm-memory64", "--wasm-max-pages", "65536",
]

WORKLOADS_ROOT = ROOT / "build/bench-workloads/2026-11-26"
SELFHOST_SRC = WORKLOADS_ROOT / "selfhost_f746c6e/selfhost/main.goose"
SELFHOST_STD = WORKLOADS_ROOT / "selfhost_f746c6e/stdlib"
FLAT100_SRC = WORKLOADS_ROOT / "flat_multi_100k/main.goose"
FLAT250_SRC = WORKLOADS_ROOT / "flat_multi_250k/main.goose"

HOST_WASMTIME = ROOT / "host/rust/target/release/goose-wasmtime"
HOST_WTIME = ROOT / "host/wtime/target/release/goose-wtime"

NOPGO_BINS = {
    "v2026_4_4": ROOT / "build/qualify-release-v2026.4-4/bootstrap/bin/goosew",
    "life_b2": ROOT / "build/qualify-life-b2/bootstrap/bin/goosew",
    "lever1": ROOT / "build/qualify-lever1/bootstrap/bin/goosew",
    "lever3": ROOT / "build/qualify-lever3/bootstrap/bin/goosew",
    "lever4": ROOT / "build/qualify-lever4/bootstrap/bin/goosew",
}

PGO_BINS = {
    "v2026_4_4_pgo": ROOT / "build/pgo-blot2-final/goosew_pgo",
    "life_b2_pgo": ROOT / "build/pgo-life-final/goosew_pgo",
    "lever4_pgo": ROOT / "build/pgo-four-levers/goosew_pgo",
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


def tool_version(cmd: list[str]) -> str:
    p = subprocess.run(cmd, capture_output=True, text=True)
    return (p.stdout or p.stderr).strip().splitlines()[0] if (p.stdout or p.stderr).strip() else ""


def cpu_model() -> str:
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name"):
                return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor()


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
        "stderr": err if expect_rc != 0 else "",
    }


def parse_stats(stats_path: Path) -> dict:
    st = json.loads(stats_path.read_text())
    return {
        "parse_ms": round(st.get("parse_ns", 0) / 1e6, 2),
        "typecheck_ms": round(st.get("typecheck_ns", 0) / 1e6, 2),
        "lifetime_ms": round(st.get("lifetime_ns", 0) / 1e6, 2),
        "typecheck_excl_life_ms": round((st.get("typecheck_ns", 0) - st.get("lifetime_ns", 0)) / 1e6, 2),
        "optimize_ms": round(st.get("optimize_ns", 0) / 1e6, 2),
        "backend_ms": round(st.get("backend_ns", 0) / 1e6, 2),
        "cache_complete": st.get("cache_complete"),
        "cache_hit": st.get("cache_hit"),
        "life_cache_hit": st.get("life_cache_hit"),
    }


def summarize_runs(runs: list[dict], extra: dict | None = None) -> dict:
    walls = [r["wall_ms"] for r in runs]
    rss = [r["max_rss_kb"] for r in runs]
    res: dict = {
        "median_ms": round(statistics.median(walls), 2),
        "min_ms": round(min(walls), 2),
        "runs_ms": walls,
        "median_max_rss_mib": round(statistics.median(rss) / 1024.0, 1),
    }
    if runs and "stages_ms" in runs[0]:
        keys = ["parse_ms", "typecheck_ms", "typecheck_excl_life_ms", "lifetime_ms", "optimize_ms", "backend_ms"]
        res["stages_ms"] = {
            k: round(statistics.median(r["stages_ms"][k] for r in runs), 2)
            for k in keys
        }
    if runs and "jit_ms" in runs[0]:
        res["median_jit_ms"] = round(statistics.median(r["jit_ms"] for r in runs), 2)
        res["median_run_ms"] = round(statistics.median(r["run_ms"] for r in runs), 2)
        res["optimization"] = runs[0]["optimization"]
    if extra:
        res.update(extra)
    return res


def build_workload_cmd(compiler: Path, workload: str, out_path: Path, stats_path: Path | None,
                       jobs: int = 8, extra: list[str] | None = None, src_override: Path | None = None) -> tuple[list[str], int, bool]:
    """Returns (cmd, expect_rc, produces_output)."""
    if workload == "blot2_o0_wasm64":
        cmd = [str(compiler), str(src_override or BLOT_SRC), *BLOT_FLAGS, "-O0", "--jobs", str(jobs), "-o", str(out_path)]
        expect_rc, has_out = 0, True
    elif workload == "blot2_o2_wasm64":
        cmd = [str(compiler), str(src_override or BLOT_SRC), *BLOT_FLAGS, "-O2", "--jobs", str(jobs), "-o", str(out_path)]
        expect_rc, has_out = 0, True
    elif workload == "blot2_o0_c":
        cmd = [str(compiler), str(src_override or BLOT_SRC), *BLOT_FLAGS, "--target", "c", "-O0", "--jobs", str(jobs), "-o", str(out_path)]
        expect_rc, has_out = 0, True
    elif workload == "blot2_check_patched":
        cmd = [str(compiler), str(src_override or BLOT_SRC), *BLOT_FLAGS, "--check", "--jobs", str(jobs)]
        expect_rc, has_out = 0, False
    elif workload == "blot2_check_unmodified":
        cmd = [str(compiler), str(BLOT_RAW), *BLOT_FLAGS, "--check", "--jobs", str(jobs)]
        expect_rc, has_out = 1, False
    elif workload == "selfhost_o0_wasm64":
        cmd = [str(compiler), str(SELFHOST_SRC), "--stdlib", str(SELFHOST_STD),
               "--wasm-memory64", "--wasm-max-pages", "65536", "-O0", "--jobs", str(jobs), "-o", str(out_path)]
        expect_rc, has_out = 0, True
    elif workload == "selfhost_o2_wasm64":
        cmd = [str(compiler), str(SELFHOST_SRC), "--stdlib", str(SELFHOST_STD),
               "--wasm-memory64", "--wasm-max-pages", "65536", "-O2", "--jobs", str(jobs), "-o", str(out_path)]
        expect_rc, has_out = 0, True
    elif workload == "selfhost_check":
        cmd = [str(compiler), str(SELFHOST_SRC), "--stdlib", str(SELFHOST_STD), "--check", "--jobs", str(jobs)]
        expect_rc, has_out = 0, False
    elif workload == "flat_multi_100k_o0":
        cmd = [str(compiler), str(FLAT100_SRC), "-O0", "--jobs", str(jobs), "-o", str(out_path)]
        expect_rc, has_out = 0, True
    elif workload == "flat_multi_250k_o0":
        cmd = [str(compiler), str(FLAT250_SRC), "-O0", "--jobs", str(jobs), "-o", str(out_path)]
        expect_rc, has_out = 0, True
    else:
        raise ValueError(f"Unknown workload: {workload}")

    if stats_path is not None and expect_rc == 0:
        cmd.extend(["--wasm-stats", str(stats_path)])
    if extra:
        cmd.extend(extra)
    return cmd, expect_rc, has_out


def run_workload(compiler: Path, workload: str, out_path: Path, stats_path: Path | None,
                 jobs: int = 8, extra: list[str] | None = None, src_override: Path | None = None) -> dict:
    if out_path.exists():
        out_path.unlink()
    if stats_path is not None and stats_path.exists():
        stats_path.unlink()
    cmd, expect_rc, has_out = build_workload_cmd(compiler, workload, out_path, stats_path, jobs, extra, src_override)
    r = run_timed(cmd, expect_rc=expect_rc)
    if stats_path is not None and stats_path.exists():
        r["stages_ms"] = parse_stats(stats_path)
    if has_out and out_path.exists():
        r["out_bytes"] = out_path.stat().st_size
        r["out_sha256"] = sha256_file(out_path)
    return r


def run_alternating_group(bins: dict[str, Path], workloads: list[str], rounds: int, tmp: Path, label: str) -> dict:
    group_res: dict = {}
    keys = list(bins.keys())
    out_path = tmp / "out.bin"
    st_path = tmp / "st.json"
    for wl in workloads:
        # 1 warmup on first and last binary
        run_workload(bins[keys[0]], wl, out_path, st_path)
        run_workload(bins[keys[-1]], wl, out_path, st_path)
        runs_by_bin: dict[str, list[dict]] = {k: [] for k in keys}
        for rep in range(rounds):
            order = keys if rep % 2 == 0 else list(reversed(keys))
            for k in order:
                runs_by_bin[k].append(run_workload(bins[k], wl, out_path, st_path))
        wl_entry: dict = {}
        for k in keys:
            extra = {}
            if "out_bytes" in runs_by_bin[k][0]:
                shas = {r["out_sha256"] for r in runs_by_bin[k]}
                assert len(shas) == 1, f"Non-deterministic output on {label}/{wl}/{k}"
                extra["out_bytes"] = runs_by_bin[k][0]["out_bytes"]
                extra["out_sha256"] = runs_by_bin[k][0]["out_sha256"]
            wl_entry[k] = summarize_runs(runs_by_bin[k], extra)
        group_res[wl] = wl_entry
        first_m = wl_entry[keys[0]]["median_ms"]
        last_m = wl_entry[keys[-1]]["median_ms"]
        line = f"[{label}] {wl:22s}: " + " -> ".join(f"{k}={wl_entry[k]['median_ms']:.1f}" for k in keys)
        line += f" ms ({first_m / last_m:.2f}x)"
        print(line, flush=True)
    return group_res


def run_wasmtime_timed(wasm_path: Path, blot_in: Path, blot_out: Path, tj_path: Path,
                       fast_jit: bool = False, cache_path: Path | None = None) -> dict:
    if blot_out.exists():
        blot_out.unlink()
    if tj_path.exists():
        tj_path.unlink()
    cmd = [str(HOST_WASMTIME), str(wasm_path), "--entry", "blot_goose_main", "--timing-json", str(tj_path)]
    if fast_jit:
        cmd.append("--fast-jit")
    if cache_path is not None:
        cmd.extend(["--cache", str(cache_path)])
    cmd.extend(["--", "build-project", str(blot_in), str(blot_out),
                "--std-root", str(BLOT_STD_ROOT), "--prelude", str(BLOT_PRELUDE)])
    r = run_timed(cmd, expect_rc=0)
    tj = json.loads(tj_path.read_text())
    r["optimization"] = tj["optimization"]
    r["jit_ms"] = round(tj["compile_instantiate_ns"] / 1e6, 2)
    r["run_ms"] = round(tj["start_function_ns"] / 1e6, 2)
    r["out_sha256"] = sha256_file(blot_out)
    return r


def bench_incremental_and_edits(compiler: Path, ref_fib_sha: str, tmp: Path, tag: str) -> dict:
    """Measures cold miss, unchanged hits, and 5 realistic edited-file .life hits."""
    scratch_blot = tmp / f"blot_copy_{tag}"
    shutil.copytree(BLOT_DIR / "compiler-goose", scratch_blot)
    src_main = scratch_blot / "src/main.goose"
    f_compile = scratch_blot / "src/compile.goose"
    f_diag = scratch_blot / "src/check/diagnostic_code.goose"
    f_check = scratch_blot / "src/check/check.goose"

    orig_compile = f_compile.read_text()
    orig_diag = f_diag.read_text()
    orig_check = f_check.read_text()

    cdir = tmp / f"cache_{tag}"
    out1 = tmp / f"inc_out1_{tag}.wasm"
    out2 = tmp / f"inc_out2_{tag}.wasm"
    st = tmp / f"inc_st_{tag}.json"

    # 1. Cold misses populating cache & .life certificate
    r_miss_o0 = run_workload(compiler, "blot2_o0_wasm64", out1, st, extra=["--cache-dir", str(cdir)], src_override=src_main)
    assert r_miss_o0["stages_ms"]["cache_complete"] is True and r_miss_o0["stages_ms"]["cache_hit"] is False
    assert r_miss_o0["stages_ms"]["life_cache_hit"] is False
    ref_o0_sha = r_miss_o0["out_sha256"]

    life_files = list(cdir.glob("l_*.life"))
    assert len(life_files) == 1, f"Expected 1 .life cert, got {life_files}"
    life_bytes = life_files[0].stat().st_size

    r_miss_chk = run_workload(compiler, "blot2_check_patched", out1, st, extra=["--cache-dir", str(cdir)], src_override=src_main)
    assert r_miss_chk["stages_ms"]["cache_complete"] is True and r_miss_chk["stages_ms"]["cache_hit"] is False
    # Check reuses the .life cert just saved by -O0!
    assert r_miss_chk["stages_ms"]["life_cache_hit"] is True

    # 2. Warm unchanged hits (5 rounds)
    hit_same, hit_new, hit_chk = [], [], []
    for _ in range(5):
        r1 = run_workload(compiler, "blot2_o0_wasm64", out1, st, extra=["--cache-dir", str(cdir)], src_override=src_main)
        assert r1["stages_ms"]["cache_hit"] is True and r1["out_sha256"] == ref_o0_sha
        hit_same.append(r1)
        r2 = run_workload(compiler, "blot2_o0_wasm64", out2, st, extra=["--cache-dir", str(cdir)], src_override=src_main)
        assert r2["stages_ms"]["cache_hit"] is True and r2["out_sha256"] == ref_o0_sha
        hit_new.append(r2)
        r3 = run_workload(compiler, "blot2_check_patched", out1, st, extra=["--cache-dir", str(cdir)], src_override=src_main)
        assert r3["stages_ms"]["cache_hit"] is True
        hit_chk.append(r3)

    # 3. Edited-file rebuilds with .life certificate hits (1 warmup + 5 rounds each)
    def measure_edit(edit_name: str, workload: str, target_file: Path, orig_text: str,
                     anchor: str, make_repl, verify_exec: bool = False) -> dict:
        runs = []
        for idx in range(6):  # idx=0 warmup, 1..5 measured
            assert anchor in orig_text, f"Anchor missing in {target_file}"
            target_file.write_text(orig_text.replace(anchor, make_repl(idx + 1), 1))
            r = run_workload(compiler, workload, out2, st, extra=["--cache-dir", str(cdir)], src_override=src_main)
            assert r["stages_ms"]["cache_hit"] is False, f"{edit_name} unexpectedly hit whole-program cache"
            assert r["stages_ms"]["life_cache_hit"] is True, f"{edit_name} missed .life cert! stats={r['stages_ms']}"
            if verify_exec and idx == 1:
                fib_out = tmp / f"edit_fib_{tag}.wasm"
                tj = tmp / f"edit_tj_{tag}.json"
                er = run_wasmtime_timed(out2, BLOT_BENCH_DIR / "fibonacci.blot", fib_out, tj, fast_jit=True)
                assert er["out_sha256"] == ref_fib_sha, f"Edited {edit_name} broke fibonacci parity"
            if idx > 0:
                runs.append(r)
        target_file.write_text(orig_text)
        res = summarize_runs(runs, {"life_cache_hit": True})
        print(f"[edit {tag}] {edit_name:34s}: {res['median_ms']:6.1f} ms (life={res['stages_ms']['lifetime_ms']:5.1f} ms)", flush=True)
        return res

    anchor_check_fn = "fn checkedAstList(tree:const blot_parse_ast::Tree&,range:blot_parse_ast::List)->blot_parse_ast::List {let count=tree.list(range).len;return range;}"
    anchor_compile = "    if built.failed { return Result { has_diagnostic: true, diagnostic: Diagnostic { unit: built.unit, span: built.span, code: built.code } }; }\n    return Result { emitted_functions: built.emitted_functions"
    anchor_diag = 'cycle => { return "Compile-time constant dependencies contain a cycle"; },'

    edits = {
        "check_goose_911k_check_scalar_if_let": measure_edit(
            "check.goose --check scalar+if+let", "blot2_check_patched", f_check, orig_check, anchor_check_fn,
            lambda k: f"fn checkedAstList(tree:const blot_parse_ast::Tree&,range:blot_parse_ast::List)->blot_parse_ast::List {{let count=tree.list(range).len;var acc=count+{k};if acc>0 {{acc+=1;}}return range;}}",
        ),
        "check_goose_911k_o0_comment": measure_edit(
            "check.goose -O0 EOF comment", "blot2_o0_wasm64", f_check, orig_check, anchor_check_fn,
            lambda k: anchor_check_fn + f"\n// edit round {k}",
        ),
        "check_goose_911k_o0_scalar_if_let": measure_edit(
            "check.goose -O0 scalar+if+let", "blot2_o0_wasm64", f_check, orig_check, anchor_check_fn,
            lambda k: f"fn checkedAstList(tree:const blot_parse_ast::Tree&,range:blot_parse_ast::List)->blot_parse_ast::List {{let count=tree.list(range).len;var acc=count+{k};if acc>0 {{acc+=1;}}return range;}}",
        ),
        "compile_goose_o0_scalar_if_let": measure_edit(
            "compile.goose -O0 scalar+if+let", "blot2_o0_wasm64", f_compile, orig_compile, anchor_compile,
            lambda k: f"    if built.failed {{ return Result {{ has_diagnostic: true, diagnostic: Diagnostic {{ unit: built.unit, span: built.span, code: built.code }} }}; }}\n    var tag_chk = (entry as i64) + {k}; if tag_chk < 0 {{ tag_chk = 0; }}\n    return Result {{ emitted_functions: built.emitted_functions",
            verify_exec=True,
        ),
        "diagnostic_code_o0_string_lit": measure_edit(
            "diagnostic_code -O0 string lit", "blot2_o0_wasm64", f_diag, orig_diag, anchor_diag,
            lambda k: f'cycle => {{ return "Compile-time constant dependencies contain a cycle ({k})"; }},',
        ),
    }

    res = {
        "life_cert_bytes": life_bytes,
        "cold_miss_o0_ms": r_miss_o0["wall_ms"],
        "cold_miss_o0_stages_ms": r_miss_o0["stages_ms"],
        "cold_miss_check_with_life_hit_ms": r_miss_chk["wall_ms"],
        "warm_hit_o0_same_out": summarize_runs(hit_same),
        "warm_hit_o0_new_out": summarize_runs(hit_new),
        "warm_hit_check": summarize_runs(hit_chk),
        "edited_file_life_hits": edits,
    }
    print(f"[cache {tag}] --check hit={res['warm_hit_check']['median_ms']:.1f} ms | "
          f"-O0 same={res['warm_hit_o0_same_out']['median_ms']:.1f} ms | "
          f"-O0 new={res['warm_hit_o0_new_out']['median_ms']:.1f} ms | .life={life_bytes:,} B", flush=True)
    return res


def main() -> None:
    for name, p in {**NOPGO_BINS, **PGO_BINS}.items():
        assert p.is_file(), f"Missing binary {name}: {p}"
    assert HOST_WASMTIME.is_file() and HOST_WTIME.is_file()

    report: dict = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "environment": {
            "cpu": cpu_model(),
            "kernel": platform.release(),
            "arch": platform.machine(),
            "clang": tool_version(["clang", "--version"]),
            "rustc_1_97_1": tool_version(["rustup", "run", "1.97.1", "rustc", "--version"]),
            "git_head": tool_version(["git", "rev-parse", "HEAD"]),
        },
        "binaries": {
            "unprofiled": {k: {"path": str(v), "sha256": sha256_file(v)} for k, v in NOPGO_BINS.items()},
            "pgo_reference": {k: {"path": str(v), "sha256": sha256_file(v)} for k, v in PGO_BINS.items()},
            "hosts": {
                "goose_wasmtime": {"path": str(HOST_WASMTIME), "sha256": sha256_file(HOST_WASMTIME)},
                "goose_wtime": {"path": str(HOST_WTIME), "sha256": sha256_file(HOST_WTIME)},
            },
        },
    }

    workloads = [
        "blot2_o0_wasm64",
        "blot2_o2_wasm64",
        "blot2_o0_c",
        "blot2_check_patched",
        "selfhost_o0_wasm64",
        "selfhost_o2_wasm64",
        "selfhost_check",
        "flat_multi_100k_o0",
        "flat_multi_250k_o0",
    ]

    with tempfile.TemporaryDirectory(prefix="four_levers_suite_") as td:
        tmp = Path(td)

        # 1. Matched unprofiled 5-way progression (--jobs 8, 5 alternating rounds)
        report["paired_unprofiled_j8"] = run_alternating_group(NOPGO_BINS, workloads, 5, tmp, "unprof")

        # 2. Separate Fresh Clang-23 PGO reference run (--jobs 8, 5 alternating rounds)
        report["paired_pgo_reference_j8"] = run_alternating_group(PGO_BINS, workloads, 5, tmp, "pgo*")

        # 3. Unmodified Blot2 §5.2 negative check (3 rounds each), j1==j8, 24 selfhost imports
        out_p = tmp / "chk_out.wasm"
        raw_unprof = [run_workload(NOPGO_BINS["lever4"], "blot2_check_unmodified", out_p, None) for _ in range(3)]
        raw_pgo = [run_workload(PGO_BINS["lever4_pgo"], "blot2_check_unmodified", out_p, None) for _ in range(3)]
        for r in raw_unprof + raw_pgo:
            assert "check/check.goose:5049:86" in r["stderr"], f"Missing §5.2 diagnostic: {r['stderr']}"
        report["blot2_unmodified_check"] = {
            "lever4_unprofiled": summarize_runs(raw_unprof),
            "lever4_pgo_ref": summarize_runs(raw_pgo),
            "diagnostic_site": "check/check.goose:5049:86",
        }
        print(f"[§5.2 raw] unprof={report['blot2_unmodified_check']['lever4_unprofiled']['median_ms']:.1f} ms | "
              f"pgo*={report['blot2_unmodified_check']['lever4_pgo_ref']['median_ms']:.1f} ms", flush=True)

        # Emit reference Wasm64 modules for JIT/parity & verify determinism + 24 imports
        v4_o0 = tmp / "v4_o0.wasm"
        v4_o2 = tmp / "v4_o2.wasm"
        l4_o0 = tmp / "l4_o0.wasm"
        l4_o0_j1 = tmp / "l4_o0_j1.wasm"
        l4_o2 = tmp / "l4_o2.wasm"
        sh_o0 = tmp / "sh_o0.wasm"
        sh_o2 = tmp / "sh_o2.wasm"

        run_workload(NOPGO_BINS["v2026_4_4"], "blot2_o0_wasm64", v4_o0, None)
        run_workload(NOPGO_BINS["v2026_4_4"], "blot2_o2_wasm64", v4_o2, None)
        run_workload(NOPGO_BINS["lever4"], "blot2_o0_wasm64", l4_o0, None, jobs=8)
        run_workload(NOPGO_BINS["lever4"], "blot2_o0_wasm64", l4_o0_j1, None, jobs=1)
        assert sha256_file(l4_o0) == sha256_file(l4_o0_j1), "Blot2 -O0 j1 != j8"
        run_workload(NOPGO_BINS["lever4"], "blot2_o2_wasm64", l4_o2, None, jobs=8)
        run_workload(NOPGO_BINS["lever4"], "selfhost_o0_wasm64", sh_o0, None, jobs=8)
        run_workload(NOPGO_BINS["lever4"], "selfhost_o2_wasm64", sh_o2, None, jobs=8)
        imp0, imp2 = count_wasm_imports(sh_o0), count_wasm_imports(sh_o2)
        assert imp0 == 24 and imp2 == 24, f"selfhost imports != 24: {imp0}, {imp2}"

        report["contracts_and_sizes"] = {
            "blot2_o0_j1_eq_j8": True,
            "selfhost_o0_imports": imp0,
            "selfhost_o2_imports": imp2,
            "v2026_4_4_blot2_o0_bytes": v4_o0.stat().st_size,
            "v2026_4_4_blot2_o2_bytes": v4_o2.stat().st_size,
            "lever4_blot2_o0_bytes": l4_o0.stat().st_size,
            "lever4_blot2_o0_sha256": sha256_file(l4_o0),
            "lever4_blot2_o2_bytes": l4_o2.stat().st_size,
            "lever4_blot2_o2_sha256": sha256_file(l4_o2),
        }
        print(f"[sizes] Blot2 -O0: {v4_o0.stat().st_size:,} -> {l4_o0.stat().st_size:,} B "
              f"({(l4_o0.stat().st_size - v4_o0.stat().st_size)/v4_o0.stat().st_size*100:+.1f}%) | "
              f"-O2: {v4_o2.stat().st_size:,} -> {l4_o2.stat().st_size:,} B | selfhost imports={imp0}", flush=True)

        # 4. Lever 4 Cold JIT + run (5 alternating rounds + warmup), Warm .cwasm, goose-wtime
        fib_src = BLOT_BENCH_DIR / "fibonacci.blot"
        mat_src = BLOT_BENCH_DIR / "matrix_multiply.blot"
        bout = tmp / "blot_out.wasm"
        tj = tmp / "timing.json"

        cold_cases = [
            ("v4_o0_winch_fib", v4_o0, fib_src, True),
            ("l4_o0_winch_fib", l4_o0, fib_src, True),
            ("l4_o2_winch_fib", l4_o2, fib_src, True),
            ("v4_o0_speed_fib", v4_o0, fib_src, False),
            ("l4_o0_speed_fib", l4_o0, fib_src, False),
            ("l4_o2_speed_fib", l4_o2, fib_src, False),
            ("v4_o0_winch_mat", v4_o0, mat_src, True),
            ("l4_o0_winch_mat", l4_o0, mat_src, True),
        ]
        # Warmup
        for _, wp, bsrc, fj in cold_cases:
            run_wasmtime_timed(wp, bsrc, bout, tj, fast_jit=fj)
        cold_runs: dict[str, list[dict]] = {name: [] for name, _, _, _ in cold_cases}
        for rep in range(5):
            order = cold_cases if rep % 2 == 0 else list(reversed(cold_cases))
            for name, wp, bsrc, fj in order:
                cold_runs[name].append(run_wasmtime_timed(wp, bsrc, bout, tj, fast_jit=fj))

        ref_fib_sha = cold_runs["v4_o0_speed_fib"][0]["out_sha256"]
        ref_mat_sha = cold_runs["v4_o0_winch_mat"][0]["out_sha256"]
        jit_report: dict = {}
        for name, _, bsrc, _ in cold_cases:
            expected_sha = ref_fib_sha if bsrc == fib_src else ref_mat_sha
            for r in cold_runs[name]:
                assert r["out_sha256"] == expected_sha, f"SHA mismatch on {name}"
            jit_report[f"cold_{name}"] = summarize_runs(cold_runs[name], {"out_sha256": expected_sha})
            m = jit_report[f"cold_{name}"]
            print(f"[cold JIT] {name:18s}: wall={m['median_ms']:6.1f} ms "
                  f"(jit={m['median_jit_ms']:6.1f}, run={m['median_run_ms']:5.1f}, {m['optimization']}, RSS={m['median_max_rss_mib']:.0f} MiB)", flush=True)

        # Warm .cwasm runs (5 rounds + warmup)
        warm_cases = [
            ("l4_o0_winch_fib", l4_o0, fib_src, True),
            ("l4_o0_winch_mat", l4_o0, mat_src, True),
            ("l4_o0_speed_fib", l4_o0, fib_src, False),
            ("l4_o2_speed_fib", l4_o2, fib_src, False),
            ("l4_o2_speed_mat", l4_o2, mat_src, False),
        ]
        for name, wp, bsrc, fj in warm_cases:
            cw = tmp / f"warm_{name}.cwasm"
            run_wasmtime_timed(wp, bsrc, bout, tj, fast_jit=fj, cache_path=cw)
            runs = [run_wasmtime_timed(wp, bsrc, bout, tj, fast_jit=fj, cache_path=cw) for _ in range(5)]
            expected_sha = ref_fib_sha if bsrc == fib_src else ref_mat_sha
            for r in runs:
                assert r["out_sha256"] == expected_sha
            jit_report[f"warm_{name}"] = summarize_runs(runs, {"cwasm_bytes": cw.stat().st_size, "out_sha256": expected_sha})
            m = jit_report[f"warm_{name}"]
            print(f"[warm .cwasm] {name:16s}: wall={m['median_ms']:5.1f} ms (jit={m['median_jit_ms']:4.1f}, run={m['median_run_ms']:5.1f}, RSS={m['median_max_rss_mib']:.0f} MiB)", flush=True)

        # Safe-Rust goose-wtime --execution register (3 rounds)
        for name, wp in [("l4_o2", l4_o2), ("l4_o0", l4_o0)]:
            cmd = [str(HOST_WTIME), str(wp), "--entry", "blot_goose_main",
                   "--execution", "register", "--max-instructions", "10000000000",
                   "--", "build-project", str(fib_src), str(bout),
                   "--std-root", str(BLOT_STD_ROOT), "--prelude", str(BLOT_PRELUDE)]
            runs = []
            for _ in range(3):
                if bout.exists():
                    bout.unlink()
                runs.append(run_timed(cmd, expect_rc=0))
                assert sha256_file(bout) == ref_fib_sha
            jit_report[f"wtime_register_{name}"] = summarize_runs(runs, {"out_sha256": ref_fib_sha})
            m = jit_report[f"wtime_register_{name}"]
            print(f"[wtime reg] {name:18s}: wall={m['median_ms']:6.1f} ms (RSS={m['median_max_rss_mib']:.0f} MiB)", flush=True)

        report["blot2_jit_and_run"] = jit_report

        # 5. Lever 3 Incremental & Edited-File Benchmarks (unprofiled + PGO)
        report["blot2_incremental_and_edits"] = {
            "lever4_unprofiled": bench_incremental_and_edits(NOPGO_BINS["lever4"], ref_fib_sha, tmp, "unprof"),
            "lever4_pgo_ref": bench_incremental_and_edits(PGO_BINS["lever4_pgo"], ref_fib_sha, tmp, "pgo"),
        }

        # 6. Full 18/18 .blot bit-exact parity check (Lever 4 -O0 Winch --fast-jit vs v2026.4-4 -O0 Cranelift speed)
        parity = {"total": 0, "compiled_match": 0, "expected_rc1": 0}
        cw_ref = tmp / "parity_ref.cwasm"
        cw_new = tmp / "parity_new.cwasm"
        for bf in sorted(BLOT_BENCH_DIR.glob("*.blot")):
            parity["total"] += 1
            o_ref = tmp / f"p_ref_{bf.stem}.wasm"
            o_new = tmp / f"p_new_{bf.stem}.wasm"
            r_ref = run_timed([str(HOST_WASMTIME), str(v4_o0), "--entry", "blot_goose_main", "--cache", str(cw_ref),
                               "--", "build-project", str(bf), str(o_ref),
                               "--std-root", str(BLOT_STD_ROOT), "--prelude", str(BLOT_PRELUDE)], expect_rc=None)
            r_new = run_timed([str(HOST_WASMTIME), str(l4_o0), "--entry", "blot_goose_main", "--fast-jit", "--cache", str(cw_new),
                               "--", "build-project", str(bf), str(o_new),
                               "--std-root", str(BLOT_STD_ROOT), "--prelude", str(BLOT_PRELUDE)], expect_rc=None)
            assert r_ref["rc"] == r_new["rc"], f"rc mismatch on {bf.name}: {r_ref['rc']} vs {r_new['rc']}"
            if r_ref["rc"] == 0:
                assert sha256_file(o_ref) == sha256_file(o_new), f"wasm mismatch on {bf.name}"
                parity["compiled_match"] += 1
            else:
                parity["expected_rc1"] += 1
        report["blot2_parity_18"] = parity
        print("Blot2 18/18 Winch parity:", parity, flush=True)

    out_json = OUT_DIR / "results.json"
    out_json.write_text(json.dumps(report, indent=2) + "\n")
    print("Wrote", out_json, flush=True)


if __name__ == "__main__":
    main()
