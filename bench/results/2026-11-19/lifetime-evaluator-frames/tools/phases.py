"""Count host instructions on the thread running each compiler phase (Linux)."""
import argparse
import json
import os
from pathlib import Path
import resource
import struct
import subprocess
import sys

ROOT = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
sys.path.insert(0, str(ROOT / "bench"))
from selfhost_comparison import SOURCE, WASM_FLAGS, sha256, verify_frozen_source

COUNTERS = ("instructions", "cycles", "branch_misses", "cache_misses")
PHASES = ("parse", "typecheck", "lifetime", "optimize", "backend")
# clock.c writes monotonic nanoseconds, Linux thread ID and four counters.
SAMPLE = struct.Struct("=q5Q")


def phase_counts(trace, durations):
    rows = list(SAMPLE.iter_unpack(trace.read_bytes()))
    samples = {row[0]: row[1:] for row in rows}
    if len(samples) != len(rows):
        raise ValueError("Overlapping clock timestamps")
    spans = {}
    for name in PHASES:
        duration = durations[name + "_ns"]
        starts = []
        for start, record in samples.items():
            end = start + duration
            if end in samples and samples[end][0] == record[0]:
                starts.append(start)
        if len(starts) != 1:
            raise ValueError(f"{name} matched {len(starts)} clock intervals")
        start = starts[0]
        spans[name] = (start, start + duration)
    for first, second in (("parse", "typecheck"), ("typecheck", "optimize"), ("optimize", "backend")):
        if spans[first][1] != spans[second][0]:
            raise ValueError(f"{first} and {second} do not share a phase boundary")
    if not (spans["typecheck"][0] <= spans["lifetime"][0] < spans["lifetime"][1] <= spans["typecheck"][1]):
        raise ValueError("Lifetime measurement falls outside type checking")

    counts = {}
    for name, (start, end) in spans.items():
        counts[name] = {"ns": end - start}
        for index, counter in enumerate(COUNTERS, start=1):
            counts[name][counter] = samples[end][index] - samples[start][index]
    counts["checking_except_lifetime"] = {
        key: value - counts["lifetime"][key] for key, value in counts["typecheck"].items()
    }
    return counts, len(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path, help="stage created by bench/selfhost_comparison.py build")
    parser.add_argument("wasm", type=Path, help="compiled Goose compiler module")
    parser.add_argument("work", type=Path, help="fresh directory for the report and binary artifacts")
    parser.add_argument("--host", type=Path, default=ROOT / "host/rust/target/release/goose-wasmtime")
    parser.add_argument("--cpu", type=int, default=5)
    parser.add_argument("--rounds", type=int, default=4)
    args = parser.parse_args()
    if args.rounds <= 0:
        parser.error("--rounds must be positive")

    stage = args.stage.resolve()
    work = args.work.resolve()
    work.mkdir(parents=True)
    source = stage / "source"
    metadata = json.loads((stage / "builds.json").read_bytes())
    verify_frozen_source(source, metadata["source_commit"], metadata["source_archive_sha256"])
    native = stage / "build-1/compiler-native"
    expected = sha256(stage / "build-1/compiler.wasm")
    module = args.wasm.resolve()
    host = args.host.resolve()
    os.sched_setaffinity(0, {args.cpu})
    resource.setrlimit(resource.RLIMIT_STACK, (256 << 20, resource.getrlimit(resource.RLIMIT_STACK)[1]))

    library = work / "clock.so"
    probe = Path(__file__).with_name("clock.c")
    subprocess.run(["cc", "-std=gnu11", "-O2", "-fPIC", "-shared", probe, "-o", library], check=True)
    commands = {"native": [native], "wasm": [host, module, "--cache", work / "compiler.cwasm", "--"]}
    subprocess.run([*commands["wasm"], "--version"], check=True, stdout=subprocess.DEVNULL)
    report = dict(source=metadata["source_commit"], source_archive_sha256=metadata["source_archive_sha256"],
                  cpu=args.cpu, native=sha256(native), wasm=sha256(module), host=sha256(host),
                  probe_sha256=sha256(probe), expected_output=expected, samples=[])
    trace = work / "clock-samples.bin"
    stats = work / "stats.json"
    output = work / "output.wasm"
    env = dict(os.environ, LD_PRELOAD=str(library), GOOSE_PHASE_LOG=str(trace))
    order = ["native", "wasm"]
    for round_id in range(1, args.rounds + 1):
        for name in order:
            for previous in (trace, stats, output):
                previous.unlink(missing_ok=True)
            subprocess.run([*commands[name], *SOURCE, *WASM_FLAGS, "--wasm-stats", stats, "-o", output],
                           env=env, cwd=source, check=True)
            if sha256(output) != expected:
                raise ValueError(f"Wrong compiler output in {name} round {round_id}")
            phases, sample_count = phase_counts(trace, json.loads(stats.read_bytes()))
            report["samples"].append(dict(engine=name, round=round_id, phases=phases, clock_samples=sample_count))
            (work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
            print(round_id, name, flush=True)
        order.reverse()


if __name__ == "__main__":
    main()
