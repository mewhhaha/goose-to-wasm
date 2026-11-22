"""Paired compiler and runtime benchmarks for Batch 1 (Wasm local promotion & direct codegen)."""
from __future__ import annotations

import gzip
import hashlib
import json
import os
from pathlib import Path
import random
import resource
import statistics
import subprocess
import sys
import tempfile
from time import perf_counter_ns

ROOT = Path(__file__).resolve().parents[4]
sys.path[:0] = [
    str(ROOT / "bench"),
    str(ROOT / "scripts"),
    str(ROOT / "bench/results/2026-11-18/selfhost-wasm-runtime/tools"),
]
from measure import measured

OUT_DIR = Path(__file__).resolve().parent
HOST = ROOT / "host/rust/target/release/goose-wasmtime"
FROZEN = ROOT / "build/next-small-release/own/source"
BASELINE_NATIVE = ROOT / "build/neon-implementation/own/build-1/compiler-native"
BASELINE_BALANCED = ROOT / "build/neon-implementation/artifacts/balanced.wasm"
CANDIDATE_NATIVE = ROOT / "build/qualify-batch1/bootstrap/bin/goose"
CANDIDATE_DIRECT = ROOT / "build/bench-batch1/direct.wasm"
CANDIDATE_BALANCED = ROOT / "build/bench-batch1/balanced.wasm"
CANDIDATE_SIZE = ROOT / "build/bench-batch1/size.wasm"

SELFBUILD_ARGS = [
    "selfhost/main.goose", "--stdlib", "stdlib", "--target", "wasm-direct", "-O2",
    "--wasm-memory64", "--wasm-max-pages", "262144",
]


def file_info(path: Path) -> dict:
    data = path.read_bytes()
    return {
        "path": str(path),
        "bytes": len(data),
        "gzip_bytes": len(gzip.compress(data, compresslevel=9, mtime=0)),
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def paired_ratio_stats(num: list[float], den: list[float]) -> dict:
    ratios = sorted(a / b for a, b in zip(num, den))
    n = len(ratios)
    med = statistics.median(ratios)
    # Exact binomial 95% interval on order statistics (or min/max for n<=7)
    lo = ratios[0]
    hi = ratios[-1]
    return {
        "median": med,
        "interval95": [lo, hi],
        "rounds_below_one": sum(1 for r in ratios if r < 1.0),
    }


def run_paired_cached(workdir: Path, source_dir: Path, cases: dict[str, Path], rounds: int) -> dict:
    workdir.mkdir(parents=True, exist_ok=True)
    out_wasm = workdir / "output.wasm"
    timer = workdir / "engine.json"
    commands = {}
    meta = {}
    for name, path in cases.items():
        info = file_info(path)
        if path.suffix == ".wasm":
            cache = workdir / f"{name}.cwasm"
            subprocess.run(
                [HOST, path, "--cache", cache, "--", "--version"],
                cwd=source_dir, check=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            )
            info["cache_sha256"] = hashlib.sha256(cache.read_bytes()).hexdigest()
            cmd = [HOST, path, "--cache", cache, "--timing-json", timer, "--", *SELFBUILD_ARGS, "-o", out_wasm]
        else:
            cmd = [path, *SELFBUILD_ARGS, "-o", out_wasm]
        commands[name] = cmd
        meta[name] = info

    # Warmup one run of each
    expected_out = {}
    for name, cmd in commands.items():
        out_wasm.unlink(missing_ok=True)
        proc = subprocess.run(cmd, cwd=source_dir, stdin=subprocess.DEVNULL, capture_output=True)
        if proc.returncode or proc.stderr:
            raise RuntimeError((name, proc.returncode, proc.stderr.decode(errors="replace")))
        expected_out[name] = {"bytes": out_wasm.stat().st_size, "sha256": hashlib.sha256(out_wasm.read_bytes()).hexdigest()}

    samples = []
    for r in range(rounds):
        order = list(commands)
        if r % 2:
            order.reverse()
        for name in order:
            out_wasm.unlink(missing_ok=True)
            timer.unlink(missing_ok=True)
            before = resource.getrusage(resource.RUSAGE_CHILDREN)
            proc, wall_ns, counters = measured(
                lambda: subprocess.run(commands[name], cwd=source_dir, stdin=subprocess.DEVNULL, capture_output=True),
                child=True,
            )
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            if proc.returncode or proc.stderr:
                raise RuntimeError((name, proc.returncode, proc.stderr.decode(errors="replace")))
            actual = {"bytes": out_wasm.stat().st_size, "sha256": hashlib.sha256(out_wasm.read_bytes()).hexdigest()}
            if actual != expected_out[name]:
                raise ValueError((name, actual, expected_out[name]))
            row = {
                "round": r + 1,
                "case": name,
                "wall_ns": wall_ns,
                "cpu_s": (after.ru_utime + after.ru_stime) - (before.ru_utime + before.ru_stime),
                "counters": counters,
                "output": actual,
            }
            if timer.is_file():
                row["engine"] = json.loads(timer.read_bytes())
            samples.append(row)
            print(f"  round {r+1}/{rounds} {name:16s} wall={wall_ns/1e6:7.1f}ms instr={counters['instructions']['value']/1e9:6.3f}B cyc={counters['cycles']['value']/1e9:6.3f}B", flush=True)

    medians = {}
    for name in cases:
        rows = [s for s in samples if s["case"] == name]
        medians[name] = {
            "wall_seconds": statistics.median(s["wall_ns"] for s in rows) / 1e9,
            "cpu_seconds": statistics.median(s["cpu_s"] for s in rows),
            "instructions": int(statistics.median(s["counters"]["instructions"]["value"] for s in rows)),
            "cycles": int(statistics.median(s["counters"]["cycles"]["value"] for s in rows)),
            "output": expected_out[name],
        }
    return {"cases": meta, "rounds": rounds, "medians": medians, "samples": samples}


def run_cold_cached(workdir: Path, rounds: int = 5) -> dict:
    workdir.mkdir(parents=True, exist_ok=True)
    modules = {
        "previous": BASELINE_BALANCED,
        "balanced": CANDIDATE_BALANCED,
        "size": CANDIDATE_SIZE,
    }
    rng = random.Random(124705)
    out_wasm = workdir / "cold_out.wasm"
    stats = workdir / "cold_engine.json"
    rows = []
    mod_meta = {k: file_info(p) for k, p in modules.items()}

    def invoke(key: str, cached: bool) -> dict:
        cache_args = ["--cache", workdir / f"rel_{key}.cwasm"] if cached else ["--no-cache"]
        out_wasm.unlink(missing_ok=True)
        stats.unlink(missing_ok=True)
        cmd = [HOST, modules[key], *cache_args, "--timing-json", stats, "--", *SELFBUILD_ARGS, "-o", out_wasm]
        t0 = perf_counter_ns()
        proc = subprocess.run(cmd, cwd=FROZEN, stdin=subprocess.DEVNULL, capture_output=True, timeout=120, check=True)
        elapsed = perf_counter_ns() - t0
        if proc.stdout or proc.stderr:
            raise RuntimeError((key, proc.stderr.decode(errors="replace")))
        return {
            "profile": key,
            "cached": cached,
            "wall_ns": elapsed,
            "output_bytes": out_wasm.stat().st_size,
            "output_sha256": hashlib.sha256(out_wasm.read_bytes()).hexdigest(),
            "engine": json.loads(stats.read_bytes()),
        }

    for k in modules:
        invoke(k, True)
    for r in range(rounds):
        for cached in (False, True):
            order = list(modules)
            rng.shuffle(order)
            for k in order:
                row = invoke(k, cached)
                row["round"] = r + 1
                rows.append(row)
                print(f"  release r{r+1}/{rounds} {k:10s} {'cached' if cached else 'cold  '} wall={row['wall_ns']/1e9:.3f}s", flush=True)

    profiles = {}
    for k in modules:
        entry = {
            "bytes": mod_meta[k]["bytes"],
            "gzip_bytes": mod_meta[k]["gzip_bytes"],
            "sha256": mod_meta[k]["sha256"],
        }
        for mode, cached in (("cold", False), ("cached", True)):
            sub = [r for r in rows if r["profile"] == k and r["cached"] == cached]
            prev = [r for r in rows if r["profile"] == "previous" and r["cached"] == cached]
            entry[mode] = {
                "wall_seconds": statistics.median(r["wall_ns"] for r in sub) / 1e9,
                "preparation_seconds": statistics.median(
                    r["engine"]["compile_instantiate_ns"] for r in sub
                ) / 1e9,
                "paired_time_change": statistics.median(
                    (a["wall_ns"] / b["wall_ns"]) - 1.0 for a, b in zip(sub, prev)
                ),
            }
        profiles[k] = entry
    return {"rounds": rounds, "modules": mod_meta, "profiles": profiles, "rows": rows}


def run_output_runtime(workdir: Path, rounds: int = 7) -> dict:
    workdir.mkdir(parents=True, exist_ok=True)
    # Measure sorting.goose runtime emitted by baseline vs candidate in cached Wasmtime
    results = {}
    for name, src in [("sorting", ROOT / "examples/sorting.goose")]:
        bins = {}
        for tag, comp in [("baseline", BASELINE_NATIVE), ("candidate", CANDIDATE_NATIVE)]:
            wasm_path = workdir / f"{name}_{tag}.wasm"
            subprocess.run(
                [comp, src, "--stdlib", ROOT / "stdlib", "--target", "wasm-direct", "-O2", "-o", wasm_path],
                cwd=ROOT, check=True, stdin=subprocess.DEVNULL, capture_output=True,
            )
            cache = workdir / f"{name}_{tag}.cwasm"
            proc = subprocess.run(
                [HOST, wasm_path, "--cache", cache],
                cwd=ROOT, check=True, stdin=subprocess.DEVNULL, capture_output=True,
            )
            bins[tag] = (wasm_path, cache, hashlib.sha256(proc.stdout).hexdigest(), wasm_path.stat().st_size)
        assert bins["baseline"][2] == bins["candidate"][2], f"stdout mismatch on {name}"
        samples = []
        for r in range(rounds):
            order = ["baseline", "candidate"]
            if r % 2:
                order.reverse()
            for tag in order:
                wasm_path, cache, expected_stdout, size = bins[tag]
                timer = workdir / "rt_engine.json"
                proc, wall_ns, counters = measured(
                    lambda: subprocess.run(
                        [HOST, wasm_path, "--cache", cache, "--timing-json", timer],
                        cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True, check=True,
                    ),
                    child=True,
                )
                assert hashlib.sha256(proc.stdout).hexdigest() == expected_stdout
                eng = json.loads(timer.read_bytes())
                samples.append({
                    "round": r + 1, "case": tag, "wall_ns": wall_ns,
                    "run_ns": eng["start_function_ns"], "counters": counters,
                })
        med = {}
        for tag in ("baseline", "candidate"):
            sub = [s for s in samples if s["case"] == tag]
            med[tag] = {
                "bytes": bins[tag][3],
                "wall_ms": statistics.median(s["wall_ns"] for s in sub) / 1e6,
                "run_ms": statistics.median(s["run_ns"] for s in sub) / 1e6,
                "instructions": int(statistics.median(s["counters"]["instructions"]["value"] for s in sub)),
                "cycles": int(statistics.median(s["counters"]["cycles"]["value"] for s in sub)),
            }
        results[name] = {"medians": med, "samples": samples}
        print(f"  runtime {name}: baseline={med['baseline']['run_ms']:.1f}ms ({med['baseline']['instructions']/1e6:.1f}M instr) -> candidate={med['candidate']['run_ms']:.1f}ms ({med['candidate']['instructions']/1e6:.1f}M instr)", flush=True)
    return results


def main():
    resource.setrlimit(resource.RLIMIT_STACK, (256 << 20, resource.getrlimit(resource.RLIMIT_STACK)[1]))
    os.sched_setaffinity(0, {7})
    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        print("1) Frozen 9a6040a paired cached rebuilds (7 rounds, CPU 7)...", flush=True)
        frozen = run_paired_cached(
            work / "frozen", FROZEN,
            {
                "native-before": BASELINE_NATIVE,
                "native-after": CANDIDATE_NATIVE,
                "wasm-before": BASELINE_BALANCED,
                "wasm-after": CANDIDATE_BALANCED,
            },
            rounds=7,
        )
        print("2) Own-source paired cached rebuilds (7 rounds, CPU 7)...", flush=True)
        own = run_paired_cached(
            work / "own", ROOT,
            {
                "native-after": CANDIDATE_NATIVE,
                "wasm-after": CANDIDATE_BALANCED,
            },
            rounds=7,
        )
        print("3) Frozen 9a6040a cold & cached release profiles (5 rounds, CPU 7)...", flush=True)
        release = run_cold_cached(work / "release", rounds=5)
        print("4) Emitted Wasm runtime check (sorting, 7 rounds, CPU 7)...", flush=True)
        runtime = run_output_runtime(work / "runtime", rounds=7)

    # Compute paired ratio summaries
    def pair_summary(data, num_key, den_key):
        num = [s for s in data["samples"] if s["case"] == num_key]
        den = [s for s in data["samples"] if s["case"] == den_key]
        return {
            "wall_seconds": paired_ratio_stats([s["wall_ns"] for s in num], [s["wall_ns"] for s in den]),
            "cpu_seconds": paired_ratio_stats([s["cpu_s"] for s in num], [s["cpu_s"] for s in den]),
            "instructions": paired_ratio_stats([s["counters"]["instructions"]["value"] for s in num], [s["counters"]["instructions"]["value"] for s in den]),
            "cycles": paired_ratio_stats([s["counters"]["cycles"]["value"] for s in num], [s["counters"]["cycles"]["value"] for s in den]),
        }

    frozen_pairs = {
        "wasm-after / wasm-before": pair_summary(frozen, "wasm-after", "wasm-before"),
        "native-after / native-before": pair_summary(frozen, "native-after", "native-before"),
        "wasm-after / native-before": pair_summary(frozen, "wasm-after", "native-before"),
        "wasm-after / native-after": pair_summary(frozen, "wasm-after", "native-after"),
    }
    own_pairs = {
        "wasm-after / native-after": pair_summary(own, "wasm-after", "native-after"),
    }

    (OUT_DIR / "profiles.json").write_text(json.dumps(release["profiles"], indent=2) + "\n")
    (OUT_DIR / "rebuilds.json").write_text(json.dumps({
        "cpu": 7,
        "host": file_info(HOST),
        "frozen": {"rounds": frozen["rounds"], "medians": frozen["medians"], "paired": frozen_pairs},
        "own": {"rounds": own["rounds"], "medians": own["medians"], "paired": own_pairs},
        "runtime": {k: v["medians"] for k, v in runtime.items()},
    }, indent=2) + "\n")
    with gzip.open(OUT_DIR / "samples.json.gz", "wt", encoding="utf-8") as gz:
        json.dump({"frozen": frozen, "own": own, "release": release, "runtime": runtime}, gz, indent=1)
    print("Wrote profiles.json, rebuilds.json, samples.json.gz", flush=True)


if __name__ == "__main__":
    main()
