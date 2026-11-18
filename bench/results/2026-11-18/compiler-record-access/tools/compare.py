"""Compare prepared compiler modules and native executables on one frozen source archive."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from importlib.metadata import version
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import threading
import time

import wasmtime
from wasmtime import _ffi

root = Path(__file__).resolve().parents[5]
sys.path[:0] = [str(root / "bench"), str(root / "scripts"),
                str(root / "bench/results/2026-11-18/selfhost-wasm-runtime/tools")]
from selfhost_comparison import identity, verify_frozen_source, SOURCE, WASM_FLAGS
from run_wasmtime import HOSTED_STACK_BYTES, PreparedModule, create_engine, create_hosted_config, run_module
from measure import measured

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("project", type=Path, help="frozen selfhost_comparison stage")
parser.add_argument("output", type=Path)
parser.add_argument("cases", nargs="+", help="name=module.wasm or name=native-executable")
parser.add_argument("--expected", action="append", default=[], help="name=output.wasm when code generation changes")
parser.add_argument("--cpu", type=int, default=7)
parser.add_argument("--rounds", type=int, default=4)
parser.add_argument("--modes", nargs="+", choices=["check", "emit"], default=["check", "emit"])
args = parser.parse_args()
if args.rounds < 1:
    parser.error("--rounds must be positive")


def paths(specs):
    result = {}
    for spec in specs:
        name, filename = spec.split("=", 1)
        if name in result:
            parser.error(f"duplicate case {name}")
        result[name] = Path(filename).resolve(strict=True)
    return result


cases = paths(args.cases)
expected_files = paths(args.expected)
assert set(expected_files) <= set(cases)
project = args.project.resolve()
output = args.output.resolve()
manifest = json.loads((project / "builds.json").read_text())
verify_frozen_source(project / "source", manifest["source_commit"], manifest["source_archive_sha256"])
expected = dict.fromkeys(cases, manifest["samples"][0]["artifacts"]["compiler.wasm"])
expected.update({label: identity(path) for label, path in expected_files.items()})
report = dict(workload=manifest["source_commit"], archive_sha256=manifest["source_archive_sha256"],
              wasmtime=version("wasmtime"), engine=identity(Path(_ffi.dll._name)),
              artifacts={k: identity(v) for k, v in cases.items()}, expected=expected, cpu=args.cpu, samples=[])
cfg = create_hosted_config()
cfg.cache = True
engine = create_engine(cfg)
modules = {}
for label, path in cases.items():
    if path.suffix == ".wasm":
        data = path.read_bytes()
        module = wasmtime.Module(engine, data)
        modules[label] = (data, PreparedModule(engine, module, report["artifacts"][label]["sha256"], None, {}))

os.chdir(project / "source")
os.sched_setaffinity(0, {args.cpu})
threading.stack_size(HOSTED_STACK_BYTES + (64 << 20))


def child_cpu():
    usage = resource.getrusage(resource.RUSAGE_CHILDREN)
    return round((usage.ru_utime + usage.ru_stime) * 1e9)


def run(label, mode, number):
    emitted = output.with_suffix(".wasm")
    emitted.unlink(missing_ok=True)
    arguments = [*SOURCE, "--check"]
    if mode == "emit":
        arguments = [*SOURCE, *WASM_FLAGS, "-o", str(emitted)]
    if label in modules:
        data, prepared = modules[label]
        start = time.thread_time_ns()
        result, _, counters = measured(lambda: run_module(data, b"", prepared=prepared, arguments=["compiler", *arguments]))
        cpu = time.thread_time_ns() - start
        assert result["exit_code"] == 0 and not result["stdout"] and not result["stderr"], result
        wall = result["timing"]["start_function_ns"]
    else:
        start = child_cpu()
        result, wall, counters = measured(lambda: subprocess.run([cases[label], *arguments], capture_output=True), child=True)
        cpu = child_cpu() - start
        assert (result.returncode, result.stdout, result.stderr) == (0, b"", b""), result
    row = dict(label=label, mode=mode, round=number, cpu_ns=cpu, wall_ns=wall, counters=counters)
    if mode == "emit":
        row["emitted"] = identity(emitted)
        assert row["emitted"] == expected[label], row
    else:
        assert not emitted.exists()
    report["samples"].append(row)
    output.write_text(json.dumps(report, indent=2) + "\n")
    print(number, label, mode, round(cpu / 1e9, 3), round(wall / 1e9, 3), counters["instructions"]["value"], flush=True)


with ThreadPoolExecutor(1) as worker:
    for index in range(args.rounds):
        order = list(cases)
        if index % 2:
            order.reverse()
        for mode in args.modes:
            for label in order:
                worker.submit(run, label, mode, index + 1).result()
