"""Paired compiler & runtime benchmarks for Batch 4 (lifetime pass fusion, dynamic summary table & zero-copy)."""
from __future__ import annotations

import gzip
import hashlib
import json
import os
from pathlib import Path
import random
import resource
import shutil
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
WORK_DIR = ROOT / "build/bench-batch4"
HOST = ROOT / "host/rust/target/release/goose-wasmtime"
FROZEN = ROOT / "build/bench-batch2/frozen-9a6040a"
BASELINE_NATIVE = ROOT / "build/qualify-batch3/bootstrap/bin/goose"
BASELINE_BALANCED = ROOT / "build/bench-batch3/balanced.wasm"
CANDIDATE_NATIVE = ROOT / "build/qualify-batch4/bootstrap/bin/goose"
CANDIDATE_STDLIB = ROOT / "build/qualify-batch4/bootstrap/bin/stdlib"

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
    med = statistics.median(ratios)
    return {
        "median": med,
        "interval95": [ratios[0], ratios[-1]],
        "rounds_below_one": sum(1 for r in ratios if r < 1.0),
    }


def build_releases() -> tuple[Path, Path, Path, Path]:
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    stats_wasm = WORK_DIR / "stats.wasm"
    subprocess.run([
        CANDIDATE_NATIVE, "selfhost/main.goose", "--stdlib", CANDIDATE_STDLIB,
        "--target", "wasm-direct", "-O2", "--wasm-memory64", "--wasm-max-pages", "262144",
        "--wasm-region-stats", "-o", stats_wasm,
    ], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)

    profiles = []
    for name, cwd, args in [
        ("self", FROZEN, SELFBUILD_ARGS),
        ("squares", ROOT, ["examples/squares.goose", "--stdlib", str(CANDIDATE_STDLIB), "--target", "wasm-direct", "-O2"]),
        ("sorting", ROOT, ["examples/sorting.goose", "--stdlib", str(CANDIDATE_STDLIB), "--target", "wasm-direct", "-O2"]),
        ("tour", ROOT, ["examples/tour.goose", "--stdlib", str(CANDIDATE_STDLIB), "--target", "wasm-direct", "-O2"]),
    ]:
        prof = WORK_DIR / f"train_{name}.prof"
        out = WORK_DIR / f"train_{name}.wasm"
        env = dict(os.environ, GOOSE_REGION_PROFILE=str(prof))
        subprocess.run([
            str(ROOT / ".venv/bin/python"), str(ROOT / "scripts/run_wasmtime.py"),
            str(stats_wasm), "--", *args, "-o", str(out),
        ], cwd=cwd, env=env, stdin=subprocess.DEVNULL, check=True)
        profiles.append(prof)

    merged: dict[int, int] = {}
    for p in profiles:
        for line in p.read_text().splitlines():
            if not line.strip():
                continue
            k, v = map(int, line.split())
            if v > merged.get(k, 0):
                merged[k] = v
    train_prof = WORK_DIR / "training.profile"
    train_prof.write_text("".join(f"{k} {v}\n" for k, v in sorted(merged.items())))
    shutil.copyfile(train_prof, OUT_DIR / "training.profile")

    direct = WORK_DIR / "direct.wasm"
    direct_args = [
        "selfhost/main.goose", "--stdlib", str(CANDIDATE_STDLIB),
        "--target", "wasm-direct", "-O2", "--wasm-bundled-host",
        "--wasm-initial-pages", "65535", "--wasm-max-pages", "65535",
        "--wasm-region-profile", str(train_prof),
    ]
    subprocess.run([CANDIDATE_NATIVE, *direct_args, "-o", direct], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)

    balanced = WORK_DIR / "balanced.wasm"
    size = WORK_DIR / "size.wasm"
    for prof_name, dest in [("balanced", balanced), ("size", size)]:
        subprocess.run([
            str(ROOT / ".venv/bin/python"), str(ROOT / "scripts/goose_wasm.py"),
            "compact", "--profile", prof_name, str(direct), "-o", str(dest),
        ], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)

    # Verify native and balanced Wasm compilers emit byte-identical bundled 32-bit direct.wasm.
    bal_cache = WORK_DIR / "balanced.cwasm"
    subprocess.run([HOST, balanced, "--cache", bal_cache, "--", "--version"], cwd=ROOT, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, check=True)
    direct_from_wasm = WORK_DIR / "direct-from-wasm.wasm"
    subprocess.run([HOST, balanced, "--cache", bal_cache, "--", *direct_args, "-o", direct_from_wasm], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)
    h_nat = hashlib.sha256(direct.read_bytes()).hexdigest()
    h_wasm = hashlib.sha256(direct_from_wasm.read_bytes()).hexdigest()
    if h_nat != h_wasm:
        raise RuntimeError(f"direct.wasm mismatch native={h_nat} vs wasm={h_wasm}")
    print(f"Verified byte-identical direct.wasm ({direct.stat().st_size:,} bytes, sha256={h_nat[:12]})", flush=True)
    print(f"  balanced.wasm: {balanced.stat().st_size:,} bytes", flush=True)
    print(f"  size.wasm:     {size.stat().st_size:,} bytes", flush=True)
    return direct, balanced, size, train_prof


def run_paired_cached(workdir: Path, source_dir: Path, cases: dict[str, Path], rounds: int) -> dict:
    workdir.mkdir(parents=True, exist_ok=True)
    out_wasm = workdir / "output.wasm"
    timer = workdir / "engine.json"
    stats_file = workdir / "stats.json"
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
            cmd = [HOST, path, "--cache", cache, "--timing-json", timer, "--", *SELFBUILD_ARGS, "--wasm-stats", stats_file, "-o", out_wasm]
        else:
            cmd = [path, *SELFBUILD_ARGS, "--wasm-stats", stats_file, "-o", out_wasm]
        commands[name] = cmd
        meta[name] = info

    expected_out = {}
    for name, cmd in commands.items():
        out_wasm.unlink(missing_ok=True)
        stats_file.unlink(missing_ok=True)
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
            stats_file.unlink(missing_ok=True)
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
            st = json.loads(stats_file.read_bytes()) if stats_file.is_file() else {}
            phases = {k: st.get(k, 0) for k in ("parse_ns", "typecheck_ns", "lifetime_ns", "optimize_ns", "backend_ns")}
            row = {
                "round": r + 1,
                "case": name,
                "wall_ns": wall_ns,
                "cpu_s": (after.ru_utime + after.ru_stime) - (before.ru_utime + before.ru_stime),
                "counters": counters,
                "phases": phases,
                "output": actual,
            }
            if timer.is_file():
                row["engine"] = json.loads(timer.read_bytes())
            samples.append(row)
            print(
                f"  round {r+1}/{rounds} {name:16s} wall={wall_ns/1e6:7.1f}ms "
                f"life={phases['lifetime_ns']/1e6:5.1f}ms opt={phases['optimize_ns']/1e6:5.1f}ms "
                f"instr={counters['instructions']['value']/1e9:6.3f}B cyc={counters['cycles']['value']/1e9:6.3f}B",
                flush=True,
            )

    medians = {}
    for name in cases:
        rows = [s for s in samples if s["case"] == name]
        medians[name] = {
            "wall_seconds": statistics.median(s["wall_ns"] for s in rows) / 1e9,
            "cpu_seconds": statistics.median(s["cpu_s"] for s in rows),
            "parse_seconds": statistics.median(s["phases"]["parse_ns"] for s in rows) / 1e9,
            "typecheck_seconds": statistics.median(s["phases"]["typecheck_ns"] for s in rows) / 1e9,
            "lifetime_seconds": statistics.median(s["phases"]["lifetime_ns"] for s in rows) / 1e9,
            "optimize_seconds": statistics.median(s["phases"]["optimize_ns"] for s in rows) / 1e9,
            "backend_seconds": statistics.median(s["phases"]["backend_ns"] for s in rows) / 1e9,
            "instructions": int(statistics.median(s["counters"]["instructions"]["value"] for s in rows)),
            "cycles": int(statistics.median(s["counters"]["cycles"]["value"] for s in rows)),
            "output": expected_out[name],
        }
    return {"cases": meta, "rounds": rounds, "medians": medians, "samples": samples}


def run_cold_cached(workdir: Path, balanced: Path, size: Path, rounds: int = 5) -> dict:
    workdir.mkdir(parents=True, exist_ok=True)
    modules = {
        "previous": BASELINE_BALANCED,
        "balanced": balanced,
        "size": size,
    }
    rng = random.Random(124706)
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
                "preparation_seconds": statistics.median(r["engine"]["compile_instantiate_ns"] for r in sub) / 1e9,
                "paired_time_change": statistics.median((a["wall_ns"] / b["wall_ns"]) - 1.0 for a, b in zip(sub, prev)),
            }
        profiles[k] = entry
    return {"rounds": rounds, "modules": mod_meta, "profiles": profiles, "rows": rows}


def main():
    resource.setrlimit(resource.RLIMIT_STACK, (256 << 20, resource.getrlimit(resource.RLIMIT_STACK)[1]))
    os.sched_setaffinity(0, {7})
    direct, balanced, size, _ = build_releases()
    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        print("1) Frozen 9a6040a paired cached rebuilds (7 rounds, CPU 7)...", flush=True)
        frozen = run_paired_cached(
            work / "frozen", FROZEN,
            {
                "native-before": BASELINE_NATIVE,
                "native-after": CANDIDATE_NATIVE,
                "wasm-before": BASELINE_BALANCED,
                "wasm-after": balanced,
            },
            rounds=7,
        )
        print("2) Own-source paired cached rebuilds (7 rounds, CPU 7)...", flush=True)
        own = run_paired_cached(
            work / "own", ROOT,
            {
                "native-after": CANDIDATE_NATIVE,
                "wasm-after": balanced,
            },
            rounds=7,
        )
        print("3) Frozen 9a6040a cold & cached release profiles (5 rounds, CPU 7)...", flush=True)
        release = run_cold_cached(work / "release", balanced, size, rounds=5)

    def pair_summary(data, num_key, den_key):
        num = [s for s in data["samples"] if s["case"] == num_key]
        den = [s for s in data["samples"] if s["case"] == den_key]
        return {
            "wall_seconds": paired_ratio_stats([s["wall_ns"] for s in num], [s["wall_ns"] for s in den]),
            "cpu_seconds": paired_ratio_stats([s["cpu_s"] for s in num], [s["cpu_s"] for s in den]),
            "lifetime_seconds": paired_ratio_stats([s["phases"]["lifetime_ns"] for s in num], [s["phases"]["lifetime_ns"] for s in den]),
            "optimize_seconds": paired_ratio_stats([s["phases"]["optimize_ns"] for s in num], [s["phases"]["optimize_ns"] for s in den]),
            "backend_seconds": paired_ratio_stats([s["phases"]["backend_ns"] for s in num], [s["phases"]["backend_ns"] for s in den]),
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
        "direct_wasm": file_info(direct),
        "frozen": {"rounds": frozen["rounds"], "medians": frozen["medians"], "paired": frozen_pairs},
        "own": {"rounds": own["rounds"], "medians": own["medians"], "paired": own_pairs},
    }, indent=2) + "\n")
    with gzip.open(OUT_DIR / "samples.json.gz", "wt", encoding="utf-8") as gz:
        json.dump({"frozen": frozen, "own": own, "release": release}, gz, indent=1)
    print("Wrote profiles.json, rebuilds.json, samples.json.gz", flush=True)


if __name__ == "__main__":
    main()
