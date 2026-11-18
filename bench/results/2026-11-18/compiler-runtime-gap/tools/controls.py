"""Vary the runtime and the compiler module's memory width on the same frozen workload."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack
from importlib.metadata import version
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading

root = Path(__file__).resolve().parents[5]
sys.path[:0] = [str(root / "scripts"), str(root / "bench"),
                str(root / "bench/results/2026-11-18/selfhost-wasm-runtime/tools")]
from measure import measured
from selfhost_comparison import SOURCE, WASM_FLAGS, identity, verify_frozen_source, receive
from run_wasmtime import HOSTED_STACK_BYTES, create_hosted_config, create_engine, PreparedModule, run_module
import wasmtime
from wasmtime import _ffi

p = argparse.ArgumentParser(description=__doc__)
for name in ("compiler_stage", "workload_stage", "stage"):
    p.add_argument(name, type=lambda x: Path(x).resolve())
p.add_argument("--cpu", type=int, default=7)
p.add_argument("--rounds", type=int, default=4)
p.add_argument("--reference-only", action="store_true", help="compare the two memory64 modules for the adjacent-field experiment")
a = p.parse_args()
s = a.stage
compiler = json.loads((a.compiler_stage / "builds.json").read_text())
workload = json.loads((a.workload_stage / "builds.json").read_text())
for receipt, stage in ((compiler, a.compiler_stage), (workload, a.workload_stage)):
    verify_frozen_source(stage / "source", receipt["source_commit"], receipt["source_archive_sha256"])
binary = a.compiler_stage / "build-1/compiler-native"
wasm = a.compiler_stage / "build-1/compiler.wasm"
assert all(identity(f) == compiler["samples"][0]["artifacts"][f.name] for f in (binary, wasm))
os.chdir(a.workload_stage / "source")
expected = workload["samples"][0]["artifacts"]["compiler.wasm"]
assert identity(s / "stats-output.wasm") == expected
config = create_hosted_config()
config.cache = True
engine = create_engine(config)
modules = {}
report = dict(compiler=compiler["source_commit"], workload=workload["source_commit"], workload_archive_sha256=workload["source_archive_sha256"],
              emitter=compiler["emitter"], native=identity(binary), clang=compiler["clang"], expected_emission=expected,
              regions=identity(s/"regions.txt"), stats_wasm=identity(s/"stats.wasm"), wasmtime=version("wasmtime"),
              wasmtime_library=identity(Path(_ffi.dll._name)), cpu=a.cpu, modules={}, runs=[])
paths = [("default64", wasm), ("profile64", s/"profiled64.wasm"), ("profile32", s/"profiled32.wasm")]
order = ["native", "default64", "profile64", "profile32", "v8"]
receipt = s / "controls.json"
if a.reference_only:
    paths = [("default64", wasm), ("adjacent", s/"reference64.wasm")]
    order = ["default64", "adjacent"]
    receipt = s / "adjacent.json"
    report["modified_lifetime_source"] = identity(s/"reference-src/selfhost/checker_lifetimes.goose")
for label, path in paths:
    data = path.read_bytes()
    ident = identity(path)
    mod = wasmtime.Module(engine, data)
    modules[label] = (data, PreparedModule(engine, mod, ident["sha256"], None, {}))
    report["modules"][label] = ident
    print("ready", label, flush=True)

def trial(label, mode, n):
    output = s / "control-output.wasm"
    output.unlink(missing_ok=True)
    argv = [*SOURCE, "--check"]
    if mode == "emit":
        argv = [*SOURCE, *WASM_FLAGS, "-o", str(output)]
    row = dict(label=label, mode=mode, round=n)
    if label == "native":
        res, elapsed, counters = measured(lambda: subprocess.run([binary, *argv], capture_output=True, check=True), child=True)
        assert not (res.stdout or res.stderr)
        row.update(wall_ns=elapsed, counters=counters)
    elif label == "v8":
        node.stdin.write(json.dumps(argv)+"\n")
        node.stdin.flush()
        res = receive(node)
        assert (res["exitCode"], res["stdout"], res["stderr"]) == (0, "", ""), res
        row.update(wall_ns=res["timing"]["start_function_ns"], instantiate_ns=res["timing"]["compile_instantiate_ns"])
    else:
        data, prepared = modules[label]
        res, _, counters = measured(lambda: run_module(data, b"", prepared=prepared, arguments=["compiler", *argv]))
        assert (res["exit_code"], res["stdout"], res["stderr"]) == (0, b"", ""), res
        row.update(wall_ns=res["timing"]["start_function_ns"], instantiate_ns=res["timing"]["compile_instantiate_ns"], counters=counters)
    if mode == "emit":
        row["emitted"] = identity(output)
        assert row["emitted"] == expected
    report["runs"].append(row)
    receipt.write_text(json.dumps(report, indent=2)+"\n")
    print(n, label, mode, round(row["wall_ns"]/1e9, 3), flush=True)

with ExitStack() as stack:
    if not a.reference_only:
        exe = Path(shutil.which("node")).resolve()
        node = stack.enter_context(subprocess.Popen([exe, "--no-liftoff", "--no-wasm-lazy-compilation", root/"bench/selfhost_v8.mjs", wasm],
                                                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True))
        stack.callback(node.stdin.close)
        ready = receive(node)
        assert ready["source_sha256"] == identity(wasm)["sha256"]
        report["v8"] = dict(ready, executable=identity(exe))
        for task in Path(f"/proc/{node.pid}/task").iterdir():
            os.sched_setaffinity(int(task.name), {a.cpu})
    os.sched_setaffinity(0, {a.cpu})
    threading.stack_size(HOSTED_STACK_BYTES + (64 << 20))
    with ThreadPoolExecutor(1) as worker:
        for n in range(a.rounds):
            sequence = list(order)
            if n % 2:
                sequence.reverse()
            for label in sequence:
                worker.submit(trial, label, "check", n+1).result()
        # Recorded separately; these single emissions validate the result from every configuration.
        for label in sequence:
            worker.submit(trial, label, "emit", 0).result()
