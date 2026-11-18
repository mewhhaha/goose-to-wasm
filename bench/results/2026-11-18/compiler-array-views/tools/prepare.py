"""Time compilation of two unprepared modules on one CPU with the hosted config."""
import argparse
import hashlib
from importlib.metadata import version
import json
import os
from pathlib import Path
import sys
import time

import wasmtime
from wasmtime import _ffi

root = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(root / "scripts"))
from run_wasmtime import create_engine, create_hosted_config

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("before", type=Path)
parser.add_argument("after", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--cpu", type=int, default=5)
args = parser.parse_args()
os.sched_setaffinity(0, {args.cpu})
modules = {"before": args.before.read_bytes(), "after": args.after.read_bytes()}
report = {
    "cpu": args.cpu, "wasmtime": version("wasmtime"),
    "engine_sha256": hashlib.sha256(Path(_ffi.dll._name).read_bytes()).hexdigest(),
    "cache": False, "parallel_compilation": False, "rounds": 4,
    "modules": {k: {"sha256": hashlib.sha256(v).hexdigest(), "bytes": len(v)} for k, v in modules.items()},
    "samples": [],
}
for index in range(4):
    order = list(modules)
    if index % 2:
        order.reverse()
    for label in order:
        config = create_hosted_config()
        config.parallel_compilation = False
        with create_engine(config) as engine:
            cpu = time.thread_time_ns()
            wall = time.perf_counter_ns()
            with wasmtime.Module(engine, modules[label]) as module:
                wall = time.perf_counter_ns() - wall
                cpu = time.thread_time_ns() - cpu
                size = len(module.serialize())
            report["samples"].append({"round": index + 1, "label": label, "cpu_ns": cpu,
                                      "wall_ns": wall, "serialized_bytes": size})
args.output.write_text(json.dumps(report, indent=2) + "\n")
