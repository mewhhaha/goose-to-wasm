#!/usr/bin/env python3
"""Interleave self-check, Wasm emission, and C emission on frozen compiler sources."""
import argparse
import json
import os
from pathlib import Path
import random
import resource
import statistics
import sys

ROOT = Path.cwd()
sys.path.insert(0, str(ROOT / "bench"))
import langbench

MODES = {
    "check": ["--check"],
    "wasm": ["--target", "wasm-direct", "-O2", "--wasm-max-pages", "65535"],
    "c": ["--target", "native", "-O2"],
}


def cpu():
    usage = resource.getrusage(resource.RUSAGE_CHILDREN)
    return usage.ru_utime + usage.ru_stime


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="frozen selfhost, stdlib and native directories")
    parser.add_argument("--parent", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cpu", type=int, default=7)
    parser.add_argument("--samples", type=int, default=5)
    parser.add_argument("--seed", type=int, default=111755)
    parser.add_argument("--modes", nargs="+", choices=list(MODES), default=list(MODES))
    args = parser.parse_args()
    if args.samples < 1 or args.cpu not in os.sched_getaffinity(0):
        parser.error("samples must be positive and CPU available")
    args.output.mkdir(parents=True)
    source = args.source.resolve()
    output = args.output.resolve()
    compilers = {"parent": args.parent.resolve(), "candidate": args.candidate.resolve()}
    paths = [*compilers.values(), *[source / directory for directory in ("selfhost", "stdlib", "native")]]
    fingerprints = langbench.fingerprint(paths)
    report = {"source": str(source), "fingerprints": fingerprints, "cpu": args.cpu,
              "samples": args.samples, "order_seed": args.seed, "machine_before": langbench.machine_state(),
              "rows": [], "summary": {}}
    rng = random.Random(args.seed)
    for mode in args.modes:
        for sample in range(-1, args.samples):
            order = list(compilers)
            rng.shuffle(order)
            for name in order:
                artifact = output / f"{name}.{mode}"
                stats = output / f"{name}.{mode}.stats.json"
                artifact.unlink(missing_ok=True)
                stats.unlink(missing_ok=True)
                argv = [compilers[name], source / "selfhost/main.goose", "--stdlib", source / "stdlib",
                        *MODES[mode], "--wasm-stats", stats]
                if mode != "check":
                    argv += ["-o", artifact]
                before = cpu()
                result = langbench.invoke(argv, timeout=60, cpu=args.cpu)
                seconds = cpu() - before
                if result["status"] != "passed" or result["stdout"] or result["stderr"]:
                    raise RuntimeError(result)
                phases = json.loads(stats.read_text())
                phases.pop("function_names")
                phases.pop("function_info")
                result.update(mode=mode, name=name, sample=sample, cpu_seconds=seconds, phases=phases,
                              artifact_sha256=langbench.sha256(artifact) if artifact.exists() else None)
                report["rows"].append(result)
        measured = [row for row in report["rows"] if row["mode"] == mode and row["sample"] >= 0]
        result = {}
        for name in compilers:
            samples = [row for row in measured if row["name"] == name]
            result[name] = {key: statistics.median(row[key] for row in samples)
                            for key in ("wall_seconds", "cpu_seconds")}
            result[name].update({key: statistics.median(row["phases"][key] for row in samples)
                                 for key in ("parse_ns", "typecheck_ns", "lifetime_ns", "optimize_ns", "backend_ns")})
        hashes = {row["artifact_sha256"] for row in measured}
        result.update(same_artifact=len(hashes) == 1, paired_cpu_ratios=[
            next(row["cpu_seconds"] for row in measured if row["sample"] == sample and row["name"] == "candidate") /
            next(row["cpu_seconds"] for row in measured if row["sample"] == sample and row["name"] == "parent")
            for sample in range(args.samples)])
        report["summary"][mode] = result
        print(mode, result, flush=True)
        (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    report["machine_after"] = langbench.machine_state()
    if fingerprints != langbench.fingerprint(paths):
        raise RuntimeError("benchmark inputs changed")
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
