"""Measure complete compiler requests, then collect compiler phase clocks separately."""

import argparse
import json
import os
from pathlib import Path
import resource
import shutil
import subprocess
import sys
import time

parser = argparse.ArgumentParser(description=__doc__)
for key in ("repo", "compiler_stage", "output"):
    parser.add_argument(key, type=Path)
parser.add_argument("--cpu", type=int, default=7)
parser.add_argument("--parallel-cpus", default="0,1,2,3,4,5,6,7")
parser.add_argument("--rounds", type=int, default=3)
parser.add_argument("--layout-profile", type=Path, help="profile trained on the compiler under test")
parser.add_argument("--fixed-bundled32", action="store_true", help="set bundled memory32 minimum and maximum to 65535 pages")
a = parser.parse_args()
repo, stage, out = [p.resolve() for p in (a.repo, a.compiler_stage, a.output)]
sys.path.insert(0, str(repo / "bench"))
from selfhost_comparison import SOURCE, WASM_FLAGS, identity, verify_frozen_source

out.mkdir(parents=True)
manifest = json.loads((stage / "builds.json").read_bytes())
source = stage / "source"
verify_frozen_source(
    source, manifest["source_commit"], manifest["source_archive_sha256"]
)
project = out / "project"
shutil.copytree(source, project)
native = stage / "build-1/compiler-native"
general = stage / "build-1/compiler.wasm"
host = repo / "host/rust/target/release/goose-wasmtime"
profile = (
    repo
    / "bench/results/2026-11-18/compiler-layout-trials/memory/training-root.profile"
)
if a.layout_profile:
    profile = a.layout_profile.resolve()
bundled64, bundled32 = out / "bundled64.wasm", out / "bundled32.wasm"
resource.setrlimit(
    resource.RLIMIT_STACK, (256 << 20, resource.getrlimit(resource.RLIMIT_STACK)[1])
)
os.sched_setaffinity(0, {a.cpu})
emit = [*SOURCE, "--target", "wasm-direct", "-O2", "--wasm-bundled-host"]
subprocess.run(
    [native, *emit, "--wasm-memory64", "--wasm-max-pages", "262144", "-o", bundled64],
    cwd=source,
    check=True,
)
narrow_flags = []
if a.fixed_bundled32:
    narrow_flags = ["--wasm-initial-pages", "65535"]
subprocess.run(
    [
        native,
        *emit,
        *narrow_flags,
        "--wasm-max-pages",
        "65535",
        "--wasm-region-profile",
        profile,
        "-o",
        bundled32,
    ],
    cwd=source,
    check=True,
)
modules = {"general64": general, "bundled64": bundled64, "bundled32": bundled32}
cases = {
    "cold1": ("general64", "uncached", 1),
    "cold8": ("general64", "uncached", 8),
    "cached64": ("general64", "cached", 1),
    "cached_bundled64": ("bundled64", "cached", 1),
    "cached_bundled32": ("bundled32", "cached", 1),
    "cold8_bundled32": ("bundled32", "uncached", 8),
    "native": ("native", "direct", 1),
}
parallel_cpus = {int(c) for c in a.parallel_cpus.split(",")}
assert len(parallel_cpus) == 8 and a.cpu in parallel_cpus
expected = identity(general)
result = dict(
    source_commit=manifest["source_commit"],
    source_archive_sha256=manifest["source_archive_sha256"],
    native=identity(native),
    host=identity(host),
    profile=identity(profile),
    fixed_bundled32=a.fixed_bundled32,
    modules={k: identity(v) for k, v in modules.items()},
    cpu=a.cpu,
    parallel_cpus=sorted(parallel_cpus),
    cases=cases,
    expected=expected,
    preparations=[],
    samples=[],
)
guest_output = out / "emitted.wasm"
timer = out / "timing.json"
phase_file = out / "phase.json"


def invoke(argv, cpus, workers):
    os.sched_setaffinity(0, cpus)
    env = dict(os.environ, RAYON_NUM_THREADS=str(workers))
    start = time.perf_counter_ns()
    done = subprocess.run(argv, cwd=project, env=env, capture_output=True)
    elapsed = time.perf_counter_ns() - start
    os.sched_setaffinity(0, {a.cpu})
    if done.returncode:
        raise RuntimeError(done.stderr.decode())
    return elapsed


for name, module in modules.items():
    cache = out / (name + ".cwasm")
    elapsed = invoke(
        [host, module, "--cache", cache, "--timing-json", timer, "--", "--version"],
        parallel_cpus,
        8,
    )
    assert (
        cache.is_file()
        and cache.with_suffix(".cwasm.sha256").read_text().strip()
        == identity(module)["sha256"]
    )
    result["preparations"].append(
        dict(
            module=name,
            wall_ns=elapsed,
            engine=json.loads(timer.read_bytes()),
            cache=identity(cache),
        )
    )


def run(name, kind, number):
    module, policy, workers = cases[name]
    guest_output.unlink(missing_ok=True)
    phase_file.unlink(missing_ok=True)
    timer.unlink(missing_ok=True)
    command = [native]
    if module != "native":
        command = [host, modules[module], "--timing-json", timer]
        if policy == "cached":
            command.extend(["--cache", out / (module + ".cwasm")])
        else:
            command.append("--no-cache")
        command.append("--")
    command.extend([*SOURCE, *WASM_FLAGS, "-o", guest_output])
    if kind == "profile":
        command.extend(["--wasm-stats", phase_file])
    cpus = {a.cpu}
    if workers == 8:
        cpus = parallel_cpus
    elapsed = invoke(command, cpus, workers)
    sample = dict(
        case=name,
        kind=kind,
        round=number,
        wall_ns=elapsed,
        output=identity(guest_output),
    )
    reference = expected
    if kind == "edit":
        reference = recorded_edit
    assert sample["output"] == reference, sample
    if timer.exists():
        sample["engine"] = json.loads(timer.read_bytes())
    if kind == "profile":
        phase = json.loads(phase_file.read_bytes())
        sample["phase"] = {
            k: phase[k]
            for k in (
                "parse_ns",
                "typecheck_ns",
                "lifetime_ns",
                "optimize_ns",
                "backend_ns",
                "functions",
                "nodes",
                "source_files",
            )
        }
    result["samples"].append(sample)
    (out / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(kind, number, name, round(elapsed / 1e9, 3), flush=True)


for i in range(a.rounds):
    order = list(cases)
    if i % 2:
        order.reverse()
    for name in order:
        run(name, "emit", i + 1)
for i in range(a.rounds):
    order = ["native", "cached_bundled32"]
    if i % 2:
        order.reverse()
    for name in order:
        run(name, "profile", i + 1)
driver = project / "selfhost/driver.goose"
original = driver.read_bytes()
assert original.count(b"Usage: goose-selfhost") == 1
driver.write_bytes(original.replace(b"Usage: goose-selfhost", b"Usage: goose-compiler"))
try:
    reference = out / "edited-reference.wasm"
    invoke([native, *SOURCE, *WASM_FLAGS, "-o", reference], {a.cpu}, 1)
    recorded_edit = identity(reference)
    if recorded_edit == expected:
        raise RuntimeError("The help-text edit produced the unedited compiler module")
    result["edited_reference"] = recorded_edit
    for i in range(a.rounds):
        order = ["native", "cached_bundled32"]
        if i % 2:
            order.reverse()
        for name in order:
            run(name, "edit", i + 1)
finally:
    driver.write_bytes(original)
