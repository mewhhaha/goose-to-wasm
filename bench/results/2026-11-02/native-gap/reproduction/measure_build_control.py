"""Measure paired Life build times without running generated modules."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import random
import platform
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build/native-gap"
OUT = BUILD / "build-control"
OUT.mkdir(parents=True, exist_ok=True)
BASE_REPORT = BUILD / "dispatch-pairs/report.json"
LIFE = ROOT / "examples/life.goose"
SEED = 52037
PAIRS = 15


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def summary(values):
    median = statistics.median(values)
    return {"n": len(values), "median": median,
            "mad": statistics.median(abs(value - median) for value in values),
            "min": min(values), "max": max(values), "samples": values}


def summarize_metric(rows, field):
    indexed = {(row["pair"], row["variant"]): row[field] for row in rows if row["phase"] == "measure"}
    return {
        variant: summary([indexed[pair, variant] for pair in range(PAIRS)])
        for variant in ("baseline", "candidate")
    }


def save_process(directory, command, result):
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "build.command.json").write_text(json.dumps([str(value) for value in command], indent=2) + "\n")
    (directory / "build.stdout").write_text(result.stdout, encoding="utf-8")
    (directory / "build.stderr").write_text(result.stderr, encoding="utf-8")


def main():
    previous = json.loads(BASE_REPORT.read_text())
    assert previous["status"] == "passed"
    compilers = {name: Path(previous["configuration"][name]).resolve()
                 for name in ("baseline", "candidate")}
    assert compilers["baseline"] == (BUILD / "baseline/bin/goose").resolve()
    assert compilers["candidate"] == (BUILD / "dispatch/bin/goose").resolve()
    source_identities = {}
    input_paths = [Path(__file__).resolve(), Path(sys.executable).resolve(), BASE_REPORT, LIFE, ROOT / "scripts/goose_wasm.py", ROOT / "oracle/goose_wasm.py",
                   ROOT / "toolchain.json",
                   ROOT / "patches/direct-target.patch", ROOT / "oracle/patches/0001-webassembly-target.patch"]
    for variant, compiler in compilers.items():
        source_json = compiler.parent.parent / "source.json"
        toolchain_json = compiler.parent.parent / "toolchain.json"
        source_identities[variant] = json.loads(source_json.read_text())
        assert source_identities[variant] == previous["compiler_sources"][variant]
        input_paths += [compiler, source_json, toolchain_json]
        input_paths += sorted((compiler.parent / "stdlib").glob("*.goose"))

    expected_modules = {}
    for variant in ("baseline", "candidate"):
        hashes = {row["sha256"] for row in previous["builds"]
                  if row["name"] == "life" and row["variant"] == variant}
        assert len(hashes) == 1
        expected_modules[variant] = next(iter(hashes))

    identities = {str(path.resolve()): digest(path) for path in sorted(set(input_paths))}
    report = {
        "schema": "goose-life-build-control-v1", "status": "running",
        "started_utc": datetime.now(timezone.utc).isoformat(), "python":sys.version, "platform":platform.platform(), "seed": SEED, "pairs": PAIRS,
        "source": str(LIFE), "source_sha256": digest(LIFE),
        "compiler_sha256": {name: digest(path) for name, path in compilers.items()},
        "compiler_sources": source_identities,
        "expected_life_module_sha256": expected_modules,
        "input_sha256": identities, "warmups": [], "builds": [], "summary": [], "failures": [],
        "method": "Uncached direct O2 Life compiler builds only; one untimed build per compiler, then 15 shuffled baseline/candidate pairs. Each output is checked against its exact Life artifact hash from dispatch-pairs/report.json. No generated module is run.",
    }
    report_path = OUT / "report.json"

    def checkpoint():
        report_path.write_text(json.dumps(report, indent=2) + "\n")

    checkpoint()
    rng = random.Random(SEED)

    def build(variant, phase, pair):
        label = "warmup" if phase == "warmup" else str(pair)
        directory = OUT / "compile" / variant / phase / label
        artifact = directory / "program.wasm"
        stats_path = directory / "stats.json"
        command = [sys.executable, ROOT / "scripts/goose_wasm.py", "build", LIFE,
                   "--backend", "direct", "--goose", compilers[variant],
                   "--offline", "--no-cache", "-O2", "-o", artifact, "--stats", stats_path]
        started = time.perf_counter()
        result = subprocess.run([str(value) for value in command], cwd=ROOT, text=True,
                                capture_output=True, check=False)
        wall = time.perf_counter() - started
        save_process(directory, command, result)
        if result.returncode:
            raise RuntimeError(f"{variant} {phase} build failed: {(result.stdout + result.stderr)[-2000:]}")
        stats = json.loads(stats_path.read_text())
        module_hash = digest(artifact)
        assert module_hash == expected_modules[variant], (variant, phase, pair, module_hash,
                                                           expected_modules[variant])
        row = {
            "variant": variant, "phase": phase, "pair": pair, "command": [str(value) for value in command],
            "wall_seconds": wall, "frontend_ms": stats["frontend_ms"],
            "backend_ns": stats["backend_stats"]["backend_ns"],
            "backend_ms": stats["backend_stats"]["backend_ns"] / 1e6,
            "backend_stats": stats["backend_stats"], "artifact": str(artifact),
            "artifact_sha256": module_hash, "stats_path": str(stats_path),
        }
        return row

    for variant in ("baseline", "candidate"):
        row = build(variant, "warmup", None)
        report["warmups"].append(row)
        checkpoint()

    for pair in range(PAIRS):
        order = ["baseline", "candidate"]
        rng.shuffle(order)
        for variant in order:
            report["builds"].append(build(variant, "measure", pair))
            checkpoint()
        print("pair", pair + 1, "of", PAIRS, flush=True)

    for field in ("wall_seconds", "frontend_ms", "backend_ms"):
        metrics = summarize_metric(report["builds"], field)
        paired_ratios = []
        for pair in range(PAIRS):
            by_variant = {row["variant"]: row[field] for row in report["builds"]
                          if row["phase"] == "measure" and row["pair"] == pair}
            paired_ratios.append(by_variant["baseline"] / by_variant["candidate"])
        report["summary"].append({"metric": field, "variants": metrics,
                                  "paired_speedup": summary(paired_ratios)})

    assert len(report["builds"]) == PAIRS * 2
    assert len({row["artifact"] for row in report["warmups"] + report["builds"]}) == 2 + PAIRS * 2
    assert identities == {str(path.resolve()): digest(path) for path in sorted(set(input_paths))}
    assert report["compiler_sha256"] == {name: digest(path) for name, path in compilers.items()}
    report["status"] = "passed"
    report["finished_utc"] = datetime.now(timezone.utc).isoformat()
    checkpoint()
    print("PASS", report_path)


if __name__ == "__main__":
    main()
