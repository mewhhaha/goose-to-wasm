"""Time a record passed by value in the original and record-only Wasm modules."""
import json
import os
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[5]
stage = root / "build/wasm-lowering-1118"
sys.path.insert(0, str(root / "scripts"))
sys.path.insert(0, str(root / "bench/results/2026-11-18/selfhost-wasm-runtime/tools"))
from measure import PreparedModule, create_engine, create_hosted_config, measured, sha256, wasmtime, run_module

os.sched_setaffinity(0, {0})
engine = create_engine(create_hosted_config())
modules = {}
hashes = {}
for label in ("direct", "records"):
    data = (stage / f"record-loop-{label}.wasm").read_bytes()
    hashes[label] = sha256(data)
    prepared = PreparedModule(engine, wasmtime.Module(engine, data), hashes[label], None, {})
    modules[label] = (data, prepared)

report = {
    "source_sha256": sha256((stage / "record-loop.goose").read_bytes()),
    "modules": hashes, "cpu": 0, "expected": "2000033000000 1\n", "samples": [],
}
for round_id in range(8):
    for label in sorted(modules, reverse=bool(round_id % 2)):
        data, prepared = modules[label]
        result, _, counts = measured(lambda: run_module(data, b"", prepared=prepared))
        assert (result["exit_code"], result["stdout"], result["stderr"]) == (0, report["expected"].encode(), "")
        if round_id > 0:
            report["samples"].append({
                "label": label, "round": round_id, "wall_ns": result["timing"]["start_function_ns"],
                "instructions": counts["instructions"]["value"],
            })
(stage / "record-loop.json").write_text(json.dumps(report, indent=2) + "\n")
