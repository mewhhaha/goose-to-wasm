"""Time each whole request, including every failed and repeated guest invocation."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import threading
import time

import wasmtime
from recovery import Partition, compile_with_recovery


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def output_digest(path):
    if path.is_file():
        return digest(path)
    return None


parser = argparse.ArgumentParser(description=__doc__)
for key in ("repo", "compiler_stage", "project_stage", "memory_stage", "stage"):
    parser.add_argument(key, type=Path)
parser.add_argument("--cpu", type=int, default=7)
parser.add_argument("--rounds", type=int, default=4)
parser.add_argument(
    "--datasets", nargs="+", default=["blot-parse", "self-check", "self-emit"]
)
parser.add_argument(
    "--cases",
    nargs="+",
    choices=("initial", "recover", "warm", "fit", "plain", "double"),
    default=["initial", "recover", "warm", "fit"],
)
parser.add_argument("--name", default="samples")
a = parser.parse_args()
resource.setrlimit(
    resource.RLIMIT_STACK, (256 << 20, resource.getrlimit(resource.RLIMIT_STACK)[1])
)
repo, compiler, project, memory, stage = [
    getattr(a, k).resolve()
    for k in ("repo", "compiler_stage", "project_stage", "memory_stage", "stage")
]
sys.path.insert(0, str(repo / "bench"))
from selfhost_comparison import verify_frozen_source

sys.path.insert(0, str(repo / "scripts"))
from run_wasmtime import (
    create_engine,
    create_hosted_config,
    HOSTED_STACK_BYTES,
    PreparedModule,
    run_module,
)

for path in (compiler, project):
    manifest = json.loads((path / "builds.json").read_text())
    verify_frozen_source(
        path / "source", manifest["source_commit"], manifest["source_archive_sha256"]
    )
engine_config = create_hosted_config()
engine_config.cache = True
engine = create_engine(engine_config)
modules = {}
paths = {
    "adapter": stage / "adapter.wasm",
    "initial": memory / "root32.wasm",
    "fit": memory / "two-project-fit.wasm",
}
for label, path in paths.items():
    data = path.read_bytes()
    modules[label] = (
        data,
        PreparedModule(engine, wasmtime.Module(engine, data), digest(path), None, {}),
    )
output = stage / (a.name + "-output.wasm")
flags = [
    "--target",
    "wasm-direct",
    "-O2",
    "--wasm-memory64",
    "--wasm-max-pages",
    "262144",
    "-o",
    str(output),
]
source = ["selfhost/main.goose", "--stdlib", "stdlib"]
datasets = {
    "self-check": (project / "source", source + ["--check"]),
    "self-emit": (project / "source", source + flags),
    "blot-parse": (
        memory / "heldout/blot/compiler-goose",
        ["src/main.goose", "--stdlib", "../stdlib", "--target", "native", "--parse"],
    ),
    "tree-emit": (
        memory / "heldout",
        ["tree.goose", "--stdlib", str(compiler / "source/stdlib"), *flags],
    ),
    "borrow-emit": (
        memory / "heldout",
        ["borrow-tree.goose", "--stdlib", str(compiler / "source/stdlib"), *flags],
    ),
    "escape": (
        repo,
        [
            "tests/fixtures/contracts/temporary-values-and-copies/caller_escape.goose",
            "--stdlib",
            "stdlib",
            "--check",
        ],
    ),
}
for path in sorted((memory / "heldout/examples").glob("*.goose")):
    datasets[path.stem] = (
        memory / "heldout",
        ["examples/" + path.name, "--stdlib", str(compiler / "source/stdlib"), *flags],
    )
if "wide-parse" in a.datasets:
    stress = stage / "wide.goose"
    with stress.open("w") as f:
        for i in range(40000):
            print(
                f"fn trial_{i}(n: i64) -> i64 {{ var a = n + 1; var b = a * 3; return b + a; }}",
                file=f,
            )
        print("fn main() { print(trial_0(4)); }", file=f)
    datasets["wide-parse"] = (
        stage,
        [stress.name, "--stdlib", str(compiler / "source/stdlib"), "--parse"],
    )
for shape in ("compact", "padded"):
    if shape in a.datasets:
        datasets[shape] = (
            stage,
            [shape + ".goose", "--stdlib", str(compiler / "source/stdlib"), "--parse"],
        )
layout = {}
native = compiler / "build-1/compiler-native"
ref = {}
expected_bytes = {}
os.sched_setaffinity(0, {a.cpu})
for name in a.datasets:
    cwd, args = datasets[name]
    output.unlink(missing_ok=True)
    r = subprocess.run([native, *args], cwd=cwd, capture_output=True)
    ref[name] = (r.returncode, r.stdout, r.stderr.decode())
    expected_bytes[name] = output_digest(output)
    if name != "escape":
        assert ref[name] == (0, b"", ""), (name, ref[name])
    else:
        assert r.returncode == 1 and r.stderr
report = dict(
    cpu=a.cpu,
    rounds=a.rounds,
    cases=a.cases,
    datasets=a.datasets,
    modules={k: digest(v) for k, v in paths.items()},
    native=digest(native),
    projects={
        k: json.loads((v / "builds.json").read_text())["source_archive_sha256"]
        for k, v in [("compiler", compiler), ("frozen", project)]
    },
    native_emissions=expected_bytes,
    host_sha256=digest(repo / "scripts/run_wasmtime.py"),
    samples=[],
)
if "wide-parse" in a.datasets:
    report["wide_source_sha256"] = digest(stress)
out_json = stage / (a.name + ".json")


def one(name, case):
    cwd, args = datasets[name]
    os.chdir(cwd)
    label = "adapter"
    if case in ("initial", "fit"):
        label = case
    data, prepared = modules[label]
    part = None
    if case == "warm" and name in layout:
        part = layout[name]
    elif case in ("recover", "warm"):
        part = Partition(4)
    elif case == "double":
        part = Partition(2)
    attempts = []
    previous_failures = 0
    if part is not None:
        previous_failures = len(part.failures)
    start_cpu, start_wall = time.thread_time_ns(), time.perf_counter_ns()
    if part is not None:
        result, attempts = compile_with_recovery(
            data, prepared, ["compiler", *args], part, output
        )
    else:
        output.unlink(missing_ok=True)
        result = run_module(data, b"", arguments=["compiler", *args], prepared=prepared)
        attempts = [result["timing"]["start_function_ns"]]
    wall = time.perf_counter_ns() - start_wall
    cpu = time.thread_time_ns() - start_cpu
    observed = (result["exit_code"], result["stdout"], result["stderr"])
    emitted = output_digest(output)
    match = observed == ref[name] and emitted == expected_bytes[name]
    if match and observed[0] == 0 and case in ("recover", "warm"):
        layout[name] = part
    failures = []
    if part is not None:
        failures = part.failures[previous_failures:]
    if not match and case not in ("initial", "plain"):
        raise AssertionError((name, case, observed, emitted, failures, attempts))
    return dict(
        cpu_ns=cpu,
        wall_ns=wall,
        guest_attempt_ns=attempts,
        matches=match,
        status=observed[0],
        error=observed[2],
        output_sha256=emitted,
        failures=failures,
    )


threading.stack_size(HOSTED_STACK_BYTES + (64 << 20))
with ThreadPoolExecutor(1) as worker:
    for i in range(a.rounds):
        order = a.cases
        if i % 2:
            order = list(reversed(order))
        for name in a.datasets:
            for case in order:
                if case == "warm" and name not in layout:
                    worker.submit(one, name, "recover").result()
                sample = worker.submit(one, name, case).result()
                sample.update(round=i + 1, dataset=name, case=case)
                report["samples"].append(sample)
                out_json.write_text(json.dumps(report, indent=2) + "\n")
                print(
                    i + 1,
                    name,
                    case,
                    sample["matches"],
                    len(sample["guest_attempt_ns"]),
                    round(sample["cpu_ns"] / 1e9, 3),
                    sample["failures"],
                    flush=True,
                )
