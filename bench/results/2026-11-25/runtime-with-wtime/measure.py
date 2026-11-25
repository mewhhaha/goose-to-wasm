#!/usr/bin/env python3
"""Pinned CPU-7 runtime benchmark comparing Upstream C++ Goose, Goose to Wasm Native,
Wasmtime, and wtime-aot (x64 & safe-Rust backends) on the 6 README Suite 3 workloads.

Keeps sibling ../wtime strictly read-only and stores all temporary build artifacts
under build/runtime-with-wtime-work.
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
WORK = ROOT / "build" / "runtime-with-wtime-work"
PIN_CPU = 7

GOOSEW = ROOT / "build" / "bin" / "goosew"
UPSTREAM = ROOT / "build" / "native" / "goose"
STDLIB = ROOT / "stdlib"
WTIME_AOT = ROOT.parent / "wtime" / "tools" / "wtime-aot" / "target" / "release" / "wtime-aot"
GOOSE_WTIME = ROOT / "host" / "wtime" / "target" / "release" / "goose-wtime"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def run_cmd(cmd, *, cwd=ROOT, env=None, stdin_bytes=b"", timeout_s=120):
    def _pin():
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
        preexec_fn=_pin,
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
        if "extra" in runs[-1]:
            summary[name]["extra"] = runs[-1]["extra"]
    return summary


def main() -> None:
    os.sched_setaffinity(0, {PIN_CPU})
    for p in (GOOSEW, UPSTREAM, WTIME_AOT):
        assert p.is_file(), f"missing binary: {p}"

    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True)

    base_env = dict(os.environ)
    up_home = WORK / "upstream-home"
    up_home.mkdir()
    up_env = dict(base_env, GOOSE_HOME=str(up_home), GOOSE_CC="clang")

    # Warm upstream runtime cache once
    warm = run_cmd([str(UPSTREAM), "build", str(ROOT / "examples/squares.goose"), "--stdlib", str(STDLIB), "-O2", "-o", str(WORK / "warm")], env=up_env)
    assert warm["rc"] == 0, warm["stderr"]

    cache_x64 = WORK / "wtime-cache-x64"
    cache_rust = WORK / "wtime-cache-rust"
    cache_x64.mkdir()
    cache_rust.mkdir()

    suite3 = {}
    aot_compile_ms = {}
    rt_examples = ["sorting", "life", "sudoku", "sieve", "maze"]

    print("=== Suite 3: Runtime performance with wtime-aot (CPU 7, 5 alternating rounds) ===", flush=True)
    for ex in rt_examples:
        src = ROOT / "examples" / f"{ex}.goose"
        exp = (ROOT / "examples/expected" / f"{ex}.out").read_text()
        bin_up = WORK / f"{ex}-up"
        bin_g2w = WORK / f"{ex}-g2w"
        wasm_g2w = WORK / f"{ex}.wasm"

        r = run_cmd([str(UPSTREAM), "build", str(src), "--stdlib", str(STDLIB), "-O2", "-o", str(bin_up)], env=up_env)
        assert r["rc"] == 0, r["stderr"]

        r = run_cmd([sys.executable, str(ROOT / "scripts/goose_wasm.py"), "build", str(src), "--goose", str(GOOSEW), "--stdlib", str(STDLIB), "--backend", "native", "--cc", "clang", "-O2", "-o", str(bin_g2w)], env=base_env)
        assert r["rc"] == 0, r["stderr"]

        r = run_cmd([str(GOOSEW), "--target", "wasm-direct", "-O2", "--stdlib", str(STDLIB), "-o", str(wasm_g2w), str(src)], env=base_env)
        assert r["rc"] == 0, r["stderr"]

        wbytes = wasm_g2w.read_bytes()
        prep = run_wasmtime.prepare_module(wbytes, WORK / f"{ex}.cwasm")

        rx = run_cmd([str(WTIME_AOT), "build", str(wasm_g2w), "--cache", str(cache_x64), "--backend", "x64"], env=base_env)
        assert rx["rc"] == 0, rx["stderr"]
        bin_x64 = Path(rx["stdout"].strip().splitlines()[-1])

        rr = run_cmd([str(WTIME_AOT), "build", str(wasm_g2w), "--cache", str(cache_rust), "--backend", "rust"], env=base_env)
        assert rr["rc"] == 0, rr["stderr"]
        bin_rust = Path(rr["stdout"].strip().splitlines()[-1])

        aot_compile_ms[ex] = {
            "wasm_bytes": len(wbytes),
            "x64_cold_ms": round(rx["wall_s"] * 1000.0, 2),
            "rust_cold_ms": round(rr["wall_s"] * 1000.0, 2),
            "x64_bin_bytes": bin_x64.stat().st_size,
            "rust_bin_bytes": bin_rust.stat().st_size,
        }

        def run_up(b=bin_up, expected=exp):
            res = run_cmd([str(b)], env=base_env)
            assert res["rc"] == 0 and res["stdout"] == expected
            return res

        def run_g2w_nat(b=bin_g2w, expected=exp):
            res = run_cmd([str(b)], env=base_env)
            assert res["rc"] == 0 and res["stdout"] == expected
            return res

        def run_wt(wb=wbytes, pr=prep, expected=exp):
            os.sched_setaffinity(0, {PIN_CPU})
            t0 = time.perf_counter()
            res = run_wasmtime.run_module(wb, b"", prepared=pr)
            wall = time.perf_counter() - t0
            assert res["exit_code"] == 0 and res["stdout"].decode("utf-8") == expected
            return {"rc": 0, "wall_s": wall}

        def run_x64(b=bin_x64, expected=exp):
            res = run_cmd([str(b)], env=base_env)
            assert res["rc"] == 0 and res["stdout"] == expected
            return res

        def run_rust(b=bin_rust, expected=exp):
            res = run_cmd([str(b)], env=base_env)
            assert res["rc"] == 0 and res["stdout"] == expected
            return res

        res = alternating([
            ("upstream_native_o2", run_up),
            ("g2w_native_o2", run_g2w_nat),
            ("g2w_wasm_wasmtime", run_wt),
            ("g2w_wtime_aot_x64", run_x64),
            ("g2w_wtime_aot_rust", run_rust),
        ], rounds=5)
        suite3[ex] = res
        print(
            f"  {ex:10s} up={res['upstream_native_o2']['median_wall_s']*1000:5.2f}ms | "
            f"g2w-c={res['g2w_native_o2']['median_wall_s']*1000:5.2f}ms | "
            f"wasmtime={res['g2w_wasm_wasmtime']['median_wall_s']*1000:5.2f}ms | "
            f"wtime-x64={res['g2w_wtime_aot_x64']['median_wall_s']*1000:5.2f}ms (aot {aot_compile_ms[ex]['x64_cold_ms']:.1f}ms) | "
            f"wtime-rust={res['g2w_wtime_aot_rust']['median_wall_s']*1000:5.2f}ms",
            flush=True,
        )

    # Mandelbrot 2048x2048 (kernel clock)
    mb_src = ROOT / "bench/langbench/mandelbrot.goose"
    mb_host = ROOT / "bench/host_input.c"
    mb_in = b"2048 1000 1\n"
    mb_up_c = WORK / "mb_up.c"
    mb_up_bin = WORK / "mb_up"
    mb_g2w_c = WORK / "mb_g2w.c"
    mb_g2w_bin = WORK / "mb_g2w"
    mb_wasm = WORK / "mb.wasm"

    assert run_cmd([str(UPSTREAM), str(mb_src), "--stdlib", str(STDLIB), "--standalone", "-O2", "-o", str(mb_up_c)], env=up_env)["rc"] == 0
    assert run_cmd(["clang", "-O2", str(mb_up_c), str(mb_host), "-lm", "-lpthread", "-o", str(mb_up_bin)])["rc"] == 0
    assert run_cmd([str(GOOSEW), "--target", "c", "-O2", "--stdlib", str(STDLIB), "-o", str(mb_g2w_c), str(mb_src)])["rc"] == 0
    assert run_cmd(["clang", "-O2", str(mb_g2w_c), str(mb_host), "-lm", "-lpthread", "-o", str(mb_g2w_bin)])["rc"] == 0
    assert run_cmd([str(GOOSEW), "--target", "wasm-direct", "-O2", "--stdlib", str(STDLIB), "-o", str(mb_wasm), str(mb_src)])["rc"] == 0
    mb_wbytes = mb_wasm.read_bytes()
    mb_prep = run_wasmtime.prepare_module(mb_wbytes, WORK / "mb.cwasm")

    rx = run_cmd([str(WTIME_AOT), "build", str(mb_wasm), "--cache", str(cache_x64), "--backend", "x64"], env=base_env)
    assert rx["rc"] == 0, rx["stderr"]
    mb_x64 = Path(rx["stdout"].strip().splitlines()[-1])

    rr = run_cmd([str(WTIME_AOT), "build", str(mb_wasm), "--cache", str(cache_rust), "--backend", "rust"], env=base_env)
    assert rr["rc"] == 0, rr["stderr"]
    mb_rust = Path(rr["stdout"].strip().splitlines()[-1])

    aot_compile_ms["mandelbrot"] = {
        "wasm_bytes": len(mb_wbytes),
        "x64_cold_ms": round(rx["wall_s"] * 1000.0, 2),
        "rust_cold_ms": round(rr["wall_s"] * 1000.0, 2),
        "x64_bin_bytes": mb_x64.stat().st_size,
        "rust_bin_bytes": mb_rust.stat().st_size,
    }

    def mb_parse(stdout: str) -> float:
        lines = stdout.strip().splitlines()
        assert lines[0].strip() == "1038538536", f"bad mandelbrot checksum: {lines}"
        return int(lines[1].strip()) / 1e9

    def mb_up_run():
        res = run_cmd([str(mb_up_bin)], stdin_bytes=mb_in)
        assert res["rc"] == 0
        res["wall_s"] = mb_parse(res["stdout"])
        return res

    def mb_g2w_nat_run():
        res = run_cmd([str(mb_g2w_bin)], stdin_bytes=mb_in)
        assert res["rc"] == 0
        res["wall_s"] = mb_parse(res["stdout"])
        return res

    def mb_wt_run():
        os.sched_setaffinity(0, {PIN_CPU})
        res = run_wasmtime.run_module(mb_wbytes, mb_in, prepared=mb_prep)
        assert res["exit_code"] == 0
        return {"rc": 0, "wall_s": mb_parse(res["stdout"].decode("utf-8"))}

    def mb_x64_run():
        res = run_cmd([str(mb_x64)], stdin_bytes=mb_in)
        assert res["rc"] == 0
        res["wall_s"] = mb_parse(res["stdout"])
        return res

    def mb_rust_run():
        res = run_cmd([str(mb_rust)], stdin_bytes=mb_in)
        assert res["rc"] == 0
        res["wall_s"] = mb_parse(res["stdout"])
        return res

    suite3["mandelbrot"] = alternating([
        ("upstream_native_o2", mb_up_run),
        ("g2w_native_o2", mb_g2w_nat_run),
        ("g2w_wasm_wasmtime", mb_wt_run),
        ("g2w_wtime_aot_x64", mb_x64_run),
        ("g2w_wtime_aot_rust", mb_rust_run),
    ], rounds=5)
    m = suite3["mandelbrot"]
    print(
        f"  {'mandelbrot':10s} up={m['upstream_native_o2']['median_wall_s']:.3f}s | "
        f"g2w-c={m['g2w_native_o2']['median_wall_s']:.3f}s | "
        f"wasmtime={m['g2w_wasm_wasmtime']['median_wall_s']:.3f}s | "
        f"wtime-x64={m['g2w_wtime_aot_x64']['median_wall_s']:.3f}s (aot {aot_compile_ms['mandelbrot']['x64_cold_ms']:.1f}ms) | "
        f"wtime-rust={m['g2w_wtime_aot_rust']['median_wall_s']:.3f}s",
        flush=True,
    )

    out_data = {
        "schema": "goose-to-wasm-runtime-wtime-v1",
        "date": "2026-11-25",
        "cpu": PIN_CPU,
        "rounds": 5,
        "host": platform.platform(),
        "clang": subprocess.check_output(["clang", "--version"], text=True).splitlines()[0],
        "wasmtime_py": importlib.metadata.version("wasmtime"),
        "goosew_version": subprocess.check_output([str(GOOSEW), "--version"], text=True).strip(),
        "goosew_sha256": sha256_file(GOOSEW),
        "upstream_version": subprocess.check_output([str(UPSTREAM), "--version"], text=True, stderr=subprocess.STDOUT).strip(),
        "upstream_sha256": sha256_file(UPSTREAM),
        "wtime_git_rev": subprocess.check_output(["git", "-C", str(ROOT.parent / "wtime"), "rev-parse", "HEAD"], text=True).strip(),
        "wtime_git_tag": subprocess.check_output(["git", "-C", str(ROOT.parent / "wtime"), "describe", "--tags", "--always"], text=True).strip(),
        "wtime_aot_sha256": sha256_file(WTIME_AOT),
        "aot_compile_ms": aot_compile_ms,
        "suite3_runtime": suite3,
    }
    res_path = OUT_DIR / "results.json"
    res_path.write_text(json.dumps(out_data, indent=2) + "\n")
    print(f"\nSaved pinned results to {res_path}", flush=True)


if __name__ == "__main__":
    main()
