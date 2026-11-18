"""Time a record passed by value in the original and record-only Wasm modules."""
import argparse
import json
import os
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[5]
stage = root / "build/wasm-lowering-1118"
sys.path.insert(0, str(root / "scripts"))
sys.path.insert(0, str(root / "bench/results/2026-11-18/selfhost-wasm-runtime/tools"))
sys.path.insert(0, str(root / "bench"))
from selfhost_comparison import benchmark_engine, preparation_options
from measure import PreparedModule, measured, sha256, wasmtime, run_module

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--preflight", action="store_true", help="verify pinned inputs and run each hosted fixture once")
preparation_options(parser)
args = parser.parse_args()
reference = json.loads((Path(__file__).resolve().parents[1] / "record-loop.json").read_text())
modules = {}
hashes = {}
source_sha256 = sha256((stage / "record-loop.goose").read_bytes())
if source_sha256 != reference["source_sha256"]:
    raise ValueError("record workload changed")
for label in ("direct", "records"):
    data = (stage / f"record-loop-{label}.wasm").read_bytes()
    hashes[label] = sha256(data)
    if hashes[label] != reference["modules"][label]:
        raise ValueError(f"{label} record module changed")
    modules[label] = data

os.sched_setaffinity(0, {0})
engine = benchmark_engine(args)
for label, data in modules.items():
    prepared = PreparedModule(engine, wasmtime.Module(engine, data), hashes[label], None, {})
    modules[label] = (data, prepared)

report = {
    "source_sha256": source_sha256,
    "modules": hashes, "cpu": 0, "expected": "2000033000000 1\n", "samples": [],
}
rounds = 8
if args.preflight:
    rounds = 1
for round_id in range(rounds):
    for label in sorted(modules, reverse=bool(round_id % 2)):
        data, prepared = modules[label]
        result, _, counts = measured(lambda: run_module(data, b"", prepared=prepared))
        assert (result["exit_code"], result["stdout"], result["stderr"]) == (0, report["expected"].encode(), "")
        if round_id > 0:
            report["samples"].append({
                "label": label, "round": round_id, "wall_ns": result["timing"]["start_function_ns"],
                "instructions": counts["instructions"]["value"],
            })
if args.preflight:
    print("Verified both hosted record modules against the frozen checksum")
    sys.exit(0)
(stage / "record-loop.json").write_text(json.dumps(report, indent=2) + "\n")
