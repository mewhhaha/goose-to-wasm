"""Collect the pinned inputs, coverage, and median guest times from the two reports."""
import hashlib
import json
from pathlib import Path
from statistics import median
import sys

out = Path(sys.argv[1])
data = json.loads((out / "validation-root.json").read_text())
diagnosis = json.loads((out / "diagnosis.json").read_text())
summary = {
    "compiler_commit": data["compiler_commit"],
    "workload_commit": data["workload"],
    "cpu": data["cpu"],
    "engine": json.loads((out / "heldout/timing.json").read_text())["wasmtime"],
    "training_sources": [t["name"] for t in data["training"]["training"]],
    "policy": "per-region maximum of 64-bit training peaks; square root in Q8 weights; existing mean floor",
    "policy_selection": "square root chosen after the raw maximum failed the frozen compiler, before testing borrow-tree",
    "automatic_module": data["modules"]["root32"],
    "profile_sha256": hashlib.sha256((out / "training-root.profile").read_bytes()).hexdigest(),
    "median_guest_seconds": {
        mode: {name: round(median(values),6) for name, values in rows.items()}
        for mode,rows in data["self_timing_s"].items()
    },
    "heldout_agreement": {
        name: [task for task,rows in data["correctness"].items() if rows["runs"][name]["matches_native"]]
        for name in data["modules"]
    },
    "first_failure": {
        label: diag["failed"] for label,diag in diagnosis["reserve_failures"].items()
    },
    "blot2": diagnosis["blot_256gib"],
}
summary["self_emission"] = data["correctness"]["self-emit"]["reference"]["emission"]
(out / "summary.json").write_text(json.dumps(summary,indent=2)+"\n")
