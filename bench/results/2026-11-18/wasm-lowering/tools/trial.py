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
from measure import HOSTED_STACK_BYTES, PreparedModule, create_engine, create_hosted_config, measured, sha256, wasmtime, run_module
from wasmtime import _ffi

reference = json.loads((root / "bench/results/2026-11-18/lifetime-exit-index/matched.json").read_text())
widths = json.loads((root / "bench/results/2026-11-18/lifetime-exit-index/paired-wasm.json").read_text())["width_artifacts"]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--cpu", type=int, default=5)
parser.add_argument("--stage", type=Path, default=root / "build/wasm-lowering-1118")
parser.add_argument("--wide", action="store_true")
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
assert sha256(native.read_bytes()) == reference["candidate_native_sha256"]
run_cpu = args.cpu
os.sched_setaffinity(0, {run_cpu})
engine = create_engine(create_hosted_config())
modules = {}
report = {
    "compiler_source_commit": "ba9dece0d4e58abb22c815dae1f37e28c99758de",
    "workload_commit": reference["source_commit"], "workload_archive_sha256": reference["source_archive_sha256"],
    "wasmtime": version("wasmtime"), "wasmtime_sha256": sha256(Path(_ffi.dll._name).read_bytes()),
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
