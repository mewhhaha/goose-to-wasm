#!/usr/bin/env python3
"""Interleave direct-Wasm compiler variants on unchanged example sources."""
import argparse
from datetime import datetime, timezone
import itertools
import json
from pathlib import Path
import random
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "bench"))
import benchmark as common
from examples import validate_timing

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--baseline", type=Path, required=True)
parser.add_argument("--candidate", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--samples", type=int, default=7)
parser.add_argument("--compile-samples", type=int, default=5)
parser.add_argument("--names", nargs="+", default=["sorting", "sudoku", "squares", "maze", "life"])
args = parser.parse_args()
args.goose, args.node, args.cc, args.emcc = args.candidate, "node", "gcc", "emcc"
args.machine_label = "AMD Ryzen 7 3800X, shared desktop host"
args.output.mkdir(parents=True, exist_ok=True)
catalog = json.loads((ROOT / "examples/manifest.json").read_text())
examples = [e for e in catalog["examples"] if e["name"] in args.names]
assert {e["name"] for e in examples} == set(args.names)
compilers = {"baseline": args.baseline.resolve(), "candidate": args.candidate.resolve()}
paths = [Path(__file__), ROOT / "examples/manifest.json", ROOT / "bench/benchmark.py",
         ROOT / "bench/examples.py", ROOT / "scripts/goose_wasm.py", ROOT / "oracle/goose_wasm.py",
         ROOT / "scripts/run_wasm.mjs", ROOT / "scripts/run_wasmtime.py", *compilers.values()]
for example in examples:
    paths += [ROOT / "examples" / example["file"], ROOT / "examples" / example["expected"]]
for compiler in compilers.values():
    paths += sorted((compiler.parent / "stdlib").glob("*.goose"))
identities = {str(p): common.digest(p) for p in paths}
report = {"schema": "goose-example-pairs-v1", "status": "running", "started_utc": datetime.now(timezone.utc).isoformat(),
          "environment": common.metadata(args), "configuration": vars(args), "input_sha256": identities,
          "compiler_sources": {name: json.loads((path.parent.parent / "source.json").read_text()) for name, path in compilers.items()},
          "seed": 16119, "builds": [], "runs": [], "summary": [],
          "method": "Paired O2 direct builds and fresh-process Wasm probes, shuffled cells and within-pair variant order. "
                    "One untimed fresh-process warmup per cell/variant. Entrypoint includes initialization, host output callbacks and lazy JIT. "
                    "Both variants write timing files after engine intervals; instrumented process wall is diagnostic, not the headline example metric."}

def checkpoint():
    (args.output / "report.json").write_text(json.dumps(report, indent=2, default=str) + "\n")

checkpoint()
rng = random.Random(report["seed"])
artifacts = {}
jobs = list(itertools.product(range(args.compile_samples), examples))
rng.shuffle(jobs)
for sample, example in jobs:
    variants = list(compilers)
    rng.shuffle(variants)
    for variant in variants:
        directory = args.output / "compile" / example["name"] / variant / str(sample)
        artifact, stats = directory / "program.wasm", directory / "stats.json"
        command = [sys.executable, ROOT / "scripts/goose_wasm.py", "build", ROOT / "examples" / example["file"],
                   "--backend", "direct", "--goose", compilers[variant], "--offline", "--no-cache", "-O2", "-o", artifact, "--stats", stats]
        _, wall = common.run(command, directory=directory, name="build")
        row = {"name": example["name"], "variant": variant, "sample": sample, "command": [str(v) for v in command],
               "wall_seconds": wall, "artifact": str(artifact), "sha256": common.digest(artifact), "stats": json.loads(stats.read_text())}
        report["builds"].append(row)
        artifacts[example["name"], variant] = row
for example, variant in itertools.product(examples, compilers):
    assert len({row["sha256"] for row in report["builds"] if row["name"] == example["name"] and row["variant"] == variant}) == 1

for phase, count in [("warmup", 1), ("measure", args.samples)]:
    jobs = list(itertools.product(range(count), examples, ["v8", "wasmtime"]))
    rng.shuffle(jobs)
    for sample, example, engine in jobs:
        variants = list(compilers)
        rng.shuffle(variants)
        for variant in variants:
            build = artifacts[example["name"], variant]
            directory = args.output / "runtime" / phase / example["name"] / engine / str(sample) / variant
            directory.mkdir(parents=True, exist_ok=True)
            timing = directory / "timing.json"
            command = ["node", ROOT / "scripts/run_wasm.mjs", build["artifact"]]
            if engine == "wasmtime":
                command = [sys.executable, ROOT / "scripts/run_wasmtime.py", build["artifact"]]
            command += ["--timing-json", timing]
            result, wall = common.run(command, directory=directory, name="run")
            assert result.stdout == (ROOT / "examples" / example["expected"]).read_text()
            measured = json.loads(timing.read_text())
            validate_timing(measured, wall)
            report["runs"].append({"phase": phase, "name": example["name"], "engine": engine, "variant": variant,
                "sample": sample, "command": [str(v) for v in command], "artifact_sha256": build["sha256"],
                "process_wall_seconds": wall, "entry_seconds": measured["start_function_ns"] / 1e9, "timing": measured})
        checkpoint()
        print(phase, example["name"], engine, sample, flush=True)
for example, engine in itertools.product(examples, ["v8", "wasmtime"]):
    rows = [row for row in report["runs"] if row["phase"] == "measure" and row["name"] == example["name"] and row["engine"] == engine]
    indexed = {(row["sample"], row["variant"]): row for row in rows}
    result = {"name": example["name"], "engine": engine}
    for metric in ["entry_seconds", "process_wall_seconds"]:
        result[metric] = {variant: common.summary([indexed[sample, variant][metric] for sample in range(args.samples)]) for variant in compilers}
        result[metric]["paired_speedup"] = common.summary([indexed[sample, "baseline"][metric] / indexed[sample, "candidate"][metric] for sample in range(args.samples)])
    report["summary"].append(result)
assert all(common.digest(Path(path)) == sha for path, sha in identities.items())
assert all(common.digest(Path(row["artifact"])) == row["sha256"] for row in report["builds"])
report["status"] = "passed"
report["finished_utc"] = datetime.now(timezone.utc).isoformat()
checkpoint()
print("PASS", args.output / "report.json")
