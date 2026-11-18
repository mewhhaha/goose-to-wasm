"""Run resident, paired compiler comparisons against the same frozen input."""
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

baseline = root / "build/lifetime-exit-index-2026-11-18"
workload = root / "build/wasm-copy-2026-11-18/selfhost-chart"
sys.path.insert(0, str(root / "scripts"))
sys.path.insert(0, str(root / "bench/results/2026-11-18/selfhost-wasm-runtime/tools"))
sys.path.insert(0, str(root / "bench"))
from selfhost_comparison import benchmark_engine, preparation_options, verify_frozen_source
from selfhost_charts import timings
from measure import HOSTED_STACK_BYTES, PreparedModule, measured, sha256, wasmtime, run_module
from wasmtime import _ffi

reference = json.loads((root / "bench/results/2026-11-18/lifetime-exit-index/matched.json").read_text())
widths = json.loads((root / "bench/results/2026-11-18/lifetime-exit-index/paired-wasm.json").read_text())["width_artifacts"]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--cpu", type=int, default=5)
parser.add_argument("--stage", type=Path, default=root / "build/wasm-lowering-1118")
parser.add_argument("--wide", action="store_true")
parser.add_argument("--preflight", action="store_true", help="check all inputs, report shape, counters and hosted execution")
parser.add_argument("--comparison-report", type=Path, default=Path(__file__).resolve().parents[1] / "measurements.json")
preparation_options(parser)
args = parser.parse_args()
stage = args.stage.resolve()
width = "candidate32"
candidate = "lowering"
labels = ("effects", "regions", "scalars", "records", "combined")
inputs = {"direct": baseline / "candidate32.wasm", **{name: stage / name / "compiler.wasm" for name in labels}}
if args.wide:
    width = "candidate64"
    candidate = "wide"
    labels = ("combined",)
    inputs = {"direct": baseline / "candidate64.wasm", "combined": stage / "release64.wasm"}
native = baseline / "native-candidate"
if sha256(native.read_bytes()) != reference["candidate_native_sha256"]:
    raise ValueError(f"native compiler changed: {native}")
run_cpu = args.cpu
os.sched_setaffinity(0, {run_cpu})
folder = Path(__file__).resolve().parents[1]
expected = json.loads((folder / f"{candidate}-samples.json").read_text())
timings(json.loads(args.comparison_report.read_text()))
verify_frozen_source(workload / "source", reference["source_commit"], reference["source_archive_sha256"])
if set(inputs) != set(expected["modules"]) or expected["modules"]["direct"]["sha256"] != widths[width]["sha256"]:
    raise ValueError(f"invalid module set for {width}")
for label, path in inputs.items():
    if sha256(path.read_bytes()) != expected["modules"][label]["sha256"]:
        raise ValueError(f"module changed: {path}")
if version("wasmtime") != expected["wasmtime"] or sha256(Path(_ffi.dll._name).read_bytes()) != expected["wasmtime_sha256"]:
    raise ValueError("Wasmtime library changed")
engine = benchmark_engine(args)
smoke = wasmtime.wat2wasm('(module (memory (export "memory") 1) (func (export "_start")))')
tiny = PreparedModule(engine, wasmtime.Module(engine, smoke), sha256(smoke), None, {})
result, _, counters = measured(lambda: run_module(smoke, b"", prepared=tiny))
if (result["exit_code"], result["stdout"], result["stderr"]) != (0, b"", "") or counters["instructions"]["value"] <= 0:
    raise RuntimeError("hosted counter smoke failed")
if args.preflight:
    print(f"{width}: verified {len(inputs)} modules, native compiler, frozen project, report rounds and hosted counters")
    sys.exit(0)
modules = {}
report = {
    "compiler_source_commit": "ba9dece0d4e58abb22c815dae1f37e28c99758de",
    "workload_commit": reference["source_commit"], "workload_archive_sha256": reference["source_archive_sha256"],
    "wasmtime": version("wasmtime"), "wasmtime_sha256": sha256(Path(_ffi.dll._name).read_bytes()),
    "preparation_cache_enabled": not args.cold_preparation,
    "cpu": run_cpu, "native_sha256": reference["candidate_native_sha256"],
    "expected_emission_sha256": reference["artifact"], "modules": {}, "samples": [],
}
for label, path in inputs.items():
    data = path.read_bytes()
    digest = sha256(data)
    if label == "direct":
        assert digest == widths[width]["sha256"]
    start = perf_counter_ns()
    module = wasmtime.Module(engine, data)
    report["modules"][label] = {"sha256": digest, "bytes": len(data), "prepare_ns": perf_counter_ns() - start}
    modules[label] = (data, PreparedModule(engine, module, digest, None, {}))
    print("prepared", label, flush=True)


def trials():
    os.sched_setaffinity(0, {run_cpu})
    os.chdir(workload / "source")
    last_round = ("combined", "direct", "native")
    if args.wide:
        last_round = ("direct", "native", "combined")
    order = ("native", "direct", *labels)
    rounds = (order, tuple(reversed(order)), last_round)
    for mode in ("check", "emit"):
        for n, visit in enumerate(rounds, 1):
            for label in visit:
                argv = ["selfhost/main.goose", "--stdlib", "stdlib"]
                out = stage / f"{candidate}-returned.wasm"
                out.unlink(missing_ok=True)
                if mode == "check":
                    argv += ["--check"]
                else:
                    argv += ["--target", "wasm-direct", "-O2", "--wasm-memory64", "--wasm-max-pages", "262144", "-o", str(out)]
                if label == "native":
                    result, ns, counts = measured(lambda: subprocess.run([native, *argv], capture_output=True, timeout=90), child=True)
                    assert (result.returncode, result.stdout, result.stderr) == (0, b"", b""), result
                else:
                    data, module = modules[label]
                    result, _, counts = measured(lambda: run_module(data, b"", prepared=module, arguments=[str(inputs[label]), *argv]))
                    assert (result["exit_code"], result["stdout"], result["stderr"]) == (0, b"", ""), result
                    ns = result["timing"]["start_function_ns"]
                digest = None
                if mode == "emit":
                    digest = sha256(out.read_bytes())
                    assert digest == reference["artifact"], (label, digest)
                report["samples"].append(dict(workload=mode, round=n, label=label, wall_ns=ns, counters=counts, emitted_sha256=digest))
                (stage / f"{candidate}-samples.json").write_text(json.dumps(report, indent=2) + "\n")
                print(mode, n, label, round(ns / 1e9, 3), counts["instructions"]["value"], flush=True)

threading.stack_size(HOSTED_STACK_BYTES + (64 << 20))
with ThreadPoolExecutor(1) as pool:
    pool.submit(trials).result()
