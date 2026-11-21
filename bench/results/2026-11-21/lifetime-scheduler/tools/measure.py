#!/usr/bin/env python3
"""Pair the frozen rebuilds and verify the emitted module in every run."""
import argparse
import hashlib
import itertools
import json
import os
from pathlib import Path
from statistics import median
import subprocess
from time import perf_counter_ns


root = Path.cwd()
work = root / "build/neon-shadow-scheduler"
frozen = Path(os.environ.get("WORKLOAD_SOURCE", root / "build/next-small-release/own/source")).resolve()
runner = Path(os.environ.get("WASMTIME_RUNNER", root / "host/rust/target/release/goose-wasmtime")).resolve()
expected = "86cc98b268138c073ca529febfde21689dcb130658edf6f31f4ef7e3256342a3"
flags = ["selfhost/main.goose", "--stdlib", "stdlib", "--target", "wasm-direct", "-O2",
         "--wasm-memory64", "--wasm-max-pages", "262144"]
modes = ("control", "shadow", "validation")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(mode):
    tool = work / mode / "compiler.wasm"
    cache = tool.with_suffix(".cwasm")
    output = work / mode / "frozen.wasm"
    output.unlink(missing_ok=True)
    start = perf_counter_ns()
    proc = subprocess.run([runner, tool, "--cache", cache, "--", *flags, "-o", output],
                          cwd=frozen, check=True, capture_output=True, timeout=150)
    wall = perf_counter_ns() - start
    assert not proc.stderr, proc.stderr
    assert sha(output) == expected
    rows = [line.split() for line in proc.stdout.decode().splitlines()]
    discovery = {int(parts[1]): int(parts[2]) for parts in rows if parts[0] == "round"}
    assert sorted(discovery) == [1, 2, 3, 4], rows
    [(validation,)] = [parts[1:] for parts in rows if parts[0] == "validate"]
    result = dict(mode=mode, wall_ns=wall, discovery_ns=discovery, validation_ns=int(validation))
    result["later_ns"] = sum(discovery[i] for i in (2, 3, 4))
    if mode == "shadow":
        keys = ("class_frames", "bodies", "leaves", "leaf_ns", "clean",
                "clean_ns", "predicted", "rejected", "projected_ns", "ordered_ns")
        shadow = {int(parts[1]): dict(zip(keys, map(int, parts[2:]), strict=True))
                  for parts in rows if parts[0] == "shadow"}
        assert sorted(shadow) == [1, 2, 3, 4], rows
        result["shadow"] = shadow
        for k in keys[1:]:
            if k in shadow[2]:
                result[k] = sum(shadow[i][k] for i in (2, 3, 4))
    if mode == "validation":
        [detail] = [tuple(map(int, parts[1:])) for parts in rows if parts[0] == "validation_detail"]
        result.update(zip(("capture_count", "capture_ns", "replay_count", "replay_ns"), detail))
    return result


def print_round(number, rows):
    for row in rows:
        fields = [str(number), row["mode"], f'{row["wall_ns"]/1e6:.1f} ms wall']
        for key in ("leaf_ns", "ordered_ns", "clean_ns", "projected_ns", "predicted", "rejected", "capture_ns", "replay_ns"):
            if key in row:
                fields.append(f'{key}={row[key]/1e6:.1f}ms' if key.endswith("_ns") else f'{key}={row[key]}')
        print(" ".join(fields), flush=True)


if __name__ == "__main__":
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("--rounds", type=int, default=6)
    opts = args.parse_args()
    os.sched_setaffinity(0, {7})
    pressure = Path("/proc/pressure/cpu")
    before = pressure.read_text()
    warm = [run(m) for m in modes]
    print_round("warm", warm)
    samples = []
    for number, order in enumerate(itertools.islice(itertools.cycle(itertools.permutations(modes)), opts.rounds), 1):
        rows = [run(mode) for mode in order]
        print_round(number, rows)
        samples.append({r["mode"]: r for r in rows})
    if samples:
        summaries = {}
        for mode in modes:
            objs = [row[mode] for row in samples]
            summaries[mode] = {key: median(r[key] for r in objs)
                               for key, value in objs[0].items() if isinstance(value, int)}
        for name in ("shadow", "validation"):
            for k in ("wall_ns", "later_ns", "validation_ns"):
                summaries[name]["paired_delta_" + k] = median(s[name][k] - s["control"][k] for s in samples)
        result = dict(source="204ae57", workload="9a6040a2999dbdb100755ec07f211605bf3b228f",
                      output_sha256=expected, cpu=7, runner_sha256=sha(runner),
                      modules={mode: sha(work / mode / "compiler.wasm") for mode in modes},
                      pressure_start=before, pressure_end=pressure.read_text(),
                      summary=summaries, warmup=warm, samples=samples)
        (work / "paired.json").write_text(json.dumps(result, indent=2) + "\n")
