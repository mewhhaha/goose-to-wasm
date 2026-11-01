#!/usr/bin/env python3
"""Interleave direct-Wasm artifacts from two qualified LangArena reports."""

import argparse
import itertools
import json
from pathlib import Path
import random
import sys
from types import SimpleNamespace

import langarena as arena


def load(path):
    report = json.loads(path.read_text())
    if report["status"] not in ("passed", "passed-with-explicit-whole-suite-refusals"):
        raise ValueError(f"report is not qualified: {path}")
    if report["failures"] or not all(report[key] for key in (
        "source_hashes_still_match", "compiler_hash_still_matches", "stdlib_hashes_still_match"
    )):
        raise ValueError(f"report identities or checks failed: {path}")
    artifacts = {}
    checked = set()
    for row in report["observations"]:
        if row["track"] != "adapted" or row["backend"] != "direct" or row["status"] != "passed":
            continue
        if row["kind"] == "build" and row["phase"] == "cold":
            artifact = Path(row["artifact"])
            if arena.sha256(artifact) != row["artifact_sha256"]:
                raise ValueError(f"artifact changed: {artifact}")
            artifacts[row["task"]] = row
        if row["kind"] == "execution" and row["phase"] == "normal" and row["profile"] == "test":
            checked.add((row["task"], row["engine"], row["artifact_sha256"]))
    for task, row in artifacts.items():
        for engine in ("v8", "wasmtime"):
            if (task, engine, row["artifact_sha256"]) not in checked:
                raise ValueError(f"missing small-input qualification: {task}/{engine}")
    return report, artifacts


def measure_builds(args, reports, artifacts, cases, report, output, rng):
    if not args.compile_samples:
        return
    for source in reports.values():
        compiler = Path(source["configuration"]["goose"])
        if arena.sha256(compiler) != source["environment"]["compiler_sha256"]:
            raise ValueError(f"compiler changed since qualification: {compiler}")
    jobs = list(itertools.product(range(args.compile_samples), cases))
    rng.shuffle(jobs)
    for sample, case in jobs:
        order = ["baseline", "candidate"]
        rng.shuffle(order)
        for label in order:
            qualified = artifacts[label][case["name"]]
            directory = output / "logs/compile" / case["name"].replace("::", "_") / str(sample) / label
            stats = directory / "driver-stats.json"
            artifact = directory / "program.wasm"
            tools = SimpleNamespace(current_backend="direct", goose=reports[label]["configuration"]["goose"])
            command = arena.build_command(tools, qualified["driver_stats"]["source"], artifact, stats)
            result = arena.execute(command, directory, cwd=arena.ROOT)
            row = {"task": case["name"], "sample": sample, "variant": label, **result}
            report["compile_observations"].append(row)
            try:
                if result["returncode"] or arena.sha256(artifact) != qualified["artifact_sha256"]:
                    raise ValueError(f"build failed or artifact differs from qualification: {case['name']}/{label}")
                row["driver_stats"] = json.loads(stats.read_text())
            finally:
                arena.checkpoint(report, output)
    for case in cases:
        row = {"task": case["name"]}
        for label in ("baseline", "candidate"):
            matching = [r for r in report["compile_observations"] if r["task"] == case["name"] and r["variant"] == label]
            row[label] = {
                "wall_seconds": arena.summarize([r["wall_seconds"] for r in matching]),
                "emitter_seconds": arena.summarize([r["driver_stats"]["backend_stats"]["backend_ns"] / 1e9 for r in matching]),
                "module_bytes": matching[0]["driver_stats"]["output_bytes"],
                "code_bytes": matching[0]["driver_stats"]["backend_stats"]["code_bytes"],
            }
        report["compile_summary"].append(row)
    print("PASS paired complete builds", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--compile-samples", type=int, default=5, help="paired cold builds; 0 reuses qualified artifacts only")
    parser.add_argument("--filter", default="")
    parser.add_argument("--output-dir", type=Path, default=arena.ROOT / "build/runtime-comparison")
    args = parser.parse_args()
    if args.samples < 5:
        parser.error("at least five paired samples are required")
    if args.compile_samples < 0:
        parser.error("compile sample count cannot be negative")
    reports, artifacts = {}, {}
    for label, path in (("baseline", args.baseline), ("candidate", args.candidate)):
        reports[label], artifacts[label] = load(path.resolve())
    before, after = reports.values()
    for key in ("node", "wasmtime", "input_sha256"):
        if before["environment"][key] != after["environment"][key]:
            raise ValueError(f"reports differ in {key}")
    libraries = []
    for source in reports.values():
        root = Path(source["configuration"]["goose"]).parent / "stdlib"
        libraries.append({str(Path(path).relative_to(root)): digest
                          for path, digest in source["environment"]["installed_stdlib_sha256"].items()})
    if libraries[0] != libraries[1]:
        raise ValueError("compiler standard libraries differ")
    environment = before["environment"]
    node = before["configuration"]["node"]
    if arena.tool_version([node, "-p", "JSON.stringify(process.versions)"]) != environment["node"]:
        raise ValueError("Node identity changed since qualification")
    import importlib.metadata
    if importlib.metadata.version("wasmtime") != environment["wasmtime"]:
        raise ValueError("Wasmtime identity changed since qualification")
    for name, digest in environment["input_sha256"].items():
        if arena.sha256(arena.ROOT / name) != digest:
            raise ValueError(f"input changed since qualification: {name}")
    cases = [case for case in arena.load_manifest()["cases"]
             if case["name"] in artifacts["baseline"] and args.filter in case["name"]]
    if not cases:
        parser.error("no adapted tasks selected")
    for case in cases:
        task = case["name"]
        if artifacts["baseline"][task]["staged_source_sha256"] != artifacts["candidate"][task]["staged_source_sha256"]:
            raise ValueError(f"workload sources differ: {task}")
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    report = {
        "schema": "goose-paired-runtime-v1", "status": "incomplete", "started_utc": arena.utc_now(),
        "environment": environment, "inputs": {}, "observations": [], "summary": [],
        "compile_observations": [], "compile_summary": [],
        "harness_sha256": arena.sha256(Path(__file__)),
        "method": "Shuffled task/engine pairs; baseline/candidate order shuffled within every pair. "
        "Official production inputs and warmups. No concurrent work launched by this harness. Shared desktop host.",
    }
    for label, path in (("baseline", args.baseline), ("candidate", args.candidate)):
        report["inputs"][label] = {"report": str(path.resolve()), "sha256": arena.sha256(path),
                                   "compiler_sha256": reports[label]["environment"]["compiler_sha256"]}
    arena.checkpoint(report, output)
    rng = random.Random(761204)
    measure_builds(args, reports, artifacts, cases, report, output, rng)
    jobs = list(itertools.product(range(args.samples), cases, ("v8", "wasmtime")))
    rng.shuffle(jobs)
    for sample, case, engine in jobs:
        order = ["baseline", "candidate"]
        rng.shuffle(order)
        for label in order:
            artifact = artifacts[label][case["name"]]
            directory = output / "logs" / case["name"].replace("::", "_") / engine / str(sample) / label
            timing = directory / "engine-timing.json"
            command = [sys.executable, arena.ROOT / "scripts/run_wasmtime.py", artifact["artifact"]]
            if engine == "v8":
                command = [node, arena.ROOT / "scripts/run_wasm.mjs", artifact["artifact"]]
            command += ["--timing-json", timing]
            result = arena.execute(command, directory, cwd=arena.ROOT, stdin=arena.port_stdin(case, "run"), timeout=600)
            row = {"sample": sample, "task": case["name"], "engine": engine, "variant": label,
                   "artifact_sha256": artifact["artifact_sha256"], **result}
            report["observations"].append(row)
            try:
                row.update(arena.parse_port_result(result["stdout"], result["returncode"], case["run"]["checksum"]))
                row["engine_timing"] = json.loads(timing.read_text())
            finally:
                arena.checkpoint(report, output)
        print(f"PASS pair {case['name']} {engine} sample {sample}", flush=True)
    for case, engine in itertools.product(cases, ("v8", "wasmtime")):
        row = {"task": case["name"], "engine": engine}
        for label in ("baseline", "candidate"):
            matching = [r for r in report["observations"] if r["task"] == case["name"] and r["engine"] == engine and r["variant"] == label]
            row[label] = arena.summarize([r["timed_region_seconds"] for r in matching])
            row[label + "_startup"] = arena.summarize([r["engine_timing"]["compile_instantiate_ns"] / 1e9 for r in matching])
        row["speedup"] = row["baseline"]["median"] / row["candidate"]["median"]
        paired = {}
        for observation in report["observations"]:
            if observation["task"] == case["name"] and observation["engine"] == engine:
                paired.setdefault(observation["sample"], {})[observation["variant"]] = observation["timed_region_seconds"]
        row["paired_speedups"] = arena.summarize([pair["baseline"] / pair["candidate"] for pair in paired.values()])
        report["summary"].append(row)
        print(f"{case['name']} {engine}: {row['speedup']:.3f}x", flush=True)
    for label in ("baseline", "candidate"):
        for row in artifacts[label].values():
            if arena.sha256(Path(row["artifact"])) != row["artifact_sha256"]:
                raise ValueError("artifact changed during measurement")
    for name, digest in environment["input_sha256"].items():
        if arena.sha256(arena.ROOT / name) != digest:
            raise ValueError(f"input changed during measurement: {name}")
    report.update(status="passed", finished_utc=arena.utc_now())
    arena.checkpoint(report, output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
