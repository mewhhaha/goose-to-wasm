"""Compare old and indexed slot allocation on the same project, or measure module preparation."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from importlib.metadata import version
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
from time import perf_counter_ns

root = Path(__file__).resolve().parents[5]
sys.path[:0] = [str(root / "bench"), str(root / "scripts"),
                str(root / "bench/results/2026-11-18/selfhost-wasm-runtime/tools")]
from selfhost_comparison import benchmark_engine, identity, preparation_options, verify_frozen_source, write_report, SOURCE, WASM_FLAGS
from measure import HOSTED_STACK_BYTES, PreparedModule, measured, run_module, wasmtime
from wasmtime import _ffi

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("baseline", type=Path)
parser.add_argument("candidate", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--cpu", type=int, required=True)
parser.add_argument("--rounds", type=int, default=3)
parser.add_argument("--mode", choices=("both", "check", "emit"), default="both")
parser.add_argument("--preparation-only", action="store_true", help="prepare the candidate and run one self-check")
preparation_options(parser)
args = parser.parse_args()
stages = {"baseline": args.baseline.resolve(), "candidate": args.candidate.resolve()}
output = args.output.resolve()
source = stages["baseline"] / "source"
receipts = {label: json.loads((stage / "builds.json").read_text()) for label, stage in stages.items()}
for label, receipt in receipts.items():
    verify_frozen_source(stages[label] / "source", receipt["source_commit"], receipt["source_archive_sha256"])
    for name, expected in receipt["samples"][0]["artifacts"].items():
        if identity(stages[label] / "build-1" / name) != expected:
            raise ValueError(f"{label} build artifact changed: {name}")
os.sched_setaffinity(0, {args.cpu})
os.chdir(source)
report = {"workload_commit": receipts["baseline"]["source_commit"], "cpu": args.cpu,
          "workload_sha256": receipts["baseline"]["source_archive_sha256"],
          "wasmtime": version("wasmtime"), "engine": identity(Path(_ffi.dll._name)),
          "cache_enabled": not args.cold_preparation, "compilers": {}, "samples": []}
expected = receipts["baseline"]["samples"][0]["artifacts"]["compiler.wasm"]
modules = {}
for label, stage in stages.items():
    if args.preparation_only and label == "baseline":
        continue
    wasm = stage / "build-1/compiler.wasm"
    data = wasm.read_bytes()
    started = perf_counter_ns()
    engine = benchmark_engine(args)
    compiled = wasmtime.Module(engine, data)
    elapsed = perf_counter_ns() - started
    artifacts = receipts[label]["samples"][0]["artifacts"]
    report["compilers"][label] = {"source_commit": receipts[label]["source_commit"], "artifacts": artifacts,
                                  "preparation_ns": elapsed}
    modules[label] = (data, PreparedModule(engine, compiled, artifacts["compiler.wasm"]["sha256"], None, {}))
    print(label, "ready", round(elapsed / 1e9, 3), flush=True)


def sample(label, host, mode, n):
    emitted = output.with_suffix(".wasm")
    emitted.unlink(missing_ok=True)
    argv = [*SOURCE, "--check"]
    if mode == "emit":
        argv = [*SOURCE, *WASM_FLAGS, "-o", str(emitted)]
    if host == "native":
        binary = stages[label] / "build-1/compiler-native"
        result, elapsed, counters = measured(lambda: subprocess.run([binary, *argv], capture_output=True, timeout=120), child=True)
        status = (result.returncode, result.stdout, result.stderr.decode())
    else:
        data, module = modules[label]
        result, _, counters = measured(lambda: run_module(data, b"", prepared=module, arguments=["compiler.wasm", *argv]))
        status = (result["exit_code"], result["stdout"], result["stderr"])
        elapsed = result["timing"]["start_function_ns"]
    if status != (0, b"", ""):
        raise RuntimeError(status)
    proof = None
    if mode == "emit":
        proof = identity(emitted)
        if proof != expected:
            raise ValueError(f"different emission: {proof}")
    elif emitted.exists():
        raise ValueError("unexpected check output")
    report["samples"].append(dict(label=label, host=host, mode=mode, round=n, wall_ns=elapsed,
                                  counters=counters, emitted=proof))
    write_report(output, report)
    print(n, label, host, mode, round(elapsed / 1e9, 3), flush=True)


def trials():
    if args.preparation_only:
        sample("candidate", "wasmtime", "check", 1)
        return
    modes = ("check", "emit")
    if args.mode != "both":
        modes = (args.mode,)
    for n in range(1, args.rounds + 1):
        for mode in modes:
            for host in ("wasmtime", "native"):
                for label in sorted(stages, reverse=n % 2 == 0):
                    sample(label, host, mode, n)


threading.stack_size(HOSTED_STACK_BYTES + (64 << 20))
with ThreadPoolExecutor(1) as pool:
    pool.submit(trials).result()
