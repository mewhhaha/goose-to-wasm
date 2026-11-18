"""Evaluate three application-launch layouts against frozen native reference output."""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import resource
import subprocess
import sys
import tarfile
import time

p = argparse.ArgumentParser(description=__doc__)
for name in ["repo", "compiler_stage", "project_stage", "memory_stage", "out"]:
    p.add_argument(name, type=Path)
p.add_argument("--cpu", type=int, default=4)
p.add_argument("--rounds", type=int, default=3)
a = p.parse_args()
REPO, compiler, project, base, HERE = [
    x.resolve()
    for x in (a.repo, a.compiler_stage, a.project_stage, a.memory_stage, a.out)
]
HERE.mkdir(exist_ok=True, parents=True)
os.environ["ESTIMATE_REPO"] = str(REPO)
from runner import SHA

tools_dir = Path(__file__).resolve().parent
sys.path.insert(0, str(REPO / "bench"))
from selfhost_comparison import identity, verify_frozen_source

host_script = HERE / "run_wasmtime_frozen.py"
host_script.write_bytes(
    subprocess.check_output(
        ["git", "-C", REPO, "show", "c131e7c:scripts/run_wasmtime.py"]
    )
)
os.environ["ESTIMATE_FROZEN_HOST"] = str(host_script)
inputs = base / "heldout"
gold = json.loads(
    (
        REPO
        / "bench/results/2026-11-18/compiler-layout-trials/memory/validation-root.json"
    ).read_text()
)
for stage in [compiler, project]:
    m = json.loads((stage / "builds.json").read_text())
    verify_frozen_source(
        stage / "source", m["source_commit"], m["source_archive_sha256"]
    )
mod = base / "root32.wasm"
assert identity(mod) == gold["modules"]["root32"] and identity(mod)["sha256"] == SHA
assert identity(compiler / "build-1/compiler-native") == gold["native"]
manifest = json.loads(
    (REPO / "bench/fixtures/compiler-goose/manifest.json").read_text()
)
archive = REPO / manifest["archive"]["path"]
assert identity(archive)["sha256"] == gold["fixture_sha256"]
with tarfile.open(archive) as t:
    for rec in t:
        if rec.isfile():
            assert (inputs / "blot" / rec.name).read_bytes() == t.extractfile(
                rec
            ).read()
for name, ident in gold["examples"].items():
    assert identity(inputs / "examples" / (name + ".goose")) == ident
for key, path in [("generated", "tree"), ("borrow_tree", "borrow-tree")]:
    assert identity(inputs / (path + ".goose")) == gold[key]
os.sched_setaffinity(0, {a.cpu})
resource.setrlimit(
    resource.RLIMIT_STACK, (256 << 20, resource.getrlimit(resource.RLIMIT_STACK)[1])
)
art = HERE / "emitted.wasm"
opts = [
    "--target",
    "wasm-direct",
    "-O2",
    "--wasm-memory64",
    "--wasm-max-pages",
    "262144",
    "-o",
    str(art),
]
stage = compiler / "source/stdlib"
cases = {
    "blot-parse": (
        inputs / "blot/compiler-goose",
        ["src/main.goose", "--stdlib", "../stdlib", "--target", "native", "--parse"],
    ),
    "self-check": (
        project / "source",
        ["selfhost/main.goose", "--stdlib", "stdlib", "--check"],
    ),
    "self-emit": (
        project / "source",
        ["selfhost/main.goose", "--stdlib", "stdlib", *opts],
    ),
    "tree-emit": (inputs, ["tree.goose", "--stdlib", str(stage), *opts]),
    "borrow-tree-emit": (inputs, ["borrow-tree.goose", "--stdlib", str(stage), *opts]),
}
for name in gold["examples"]:
    cases[name + "-emit"] = (
        inputs,
        ["examples/" + name + ".goose", "--stdlib", str(stage), *opts],
    )


def run(kind, label, case, ratios):
    cwd, args = case
    timing = HERE / "tmp.timing.json"
    sizing = HERE / "tmp.sizing.json"
    for p in [art, timing, sizing]:
        p.unlink(missing_ok=True)
    cmd = [
        REPO / ".venv/bin/python",
        tools_dir / "runner.py",
        mod,
        "--cache",
        HERE / "root32.cwasm",
        "--timing-json",
        timing,
        "--",
        *args,
    ]
    t = time.perf_counter_ns()
    proc = subprocess.run(
        cmd,
        cwd=cwd,
        capture_output=True,
        env={
            **os.environ,
            "PYTHONDONTWRITEBYTECODE": "1",
            "POLICY": kind,
            "RATIOS": json.dumps(ratios),
            "SIZING_JSON": str(sizing),
        },
        timeout=120,
    )
    wall = time.perf_counter_ns() - t
    observed = dict(status=proc.returncode)
    if proc.stderr:
        observed["stderr"] = proc.stderr.decode()
    if proc.stdout:
        observed["stdout_sha256"] = hashlib.sha256(proc.stdout).hexdigest()
    if art.is_file():
        observed["emission"] = identity(art)
    row = dict(
        observed=observed,
        wall_ns=wall,
        metrics=json.loads(sizing.read_text()),
        timing=json.loads(timing.read_text()),
    )
    print(
        label,
        kind,
        row["observed"]["status"],
        round(row["timing"]["start_function_ns"] / 1e9, 3),
        row["metrics"].get("input_bytes"),
        flush=True,
    )
    return row


report = {
    key: gold[key]
    for key in [
        "compiler_commit",
        "workload",
        "compiler_archive_sha256",
        "workload_archive_sha256",
        "fixture_sha256",
        "generated",
        "borrow_tree",
        "examples",
        "native",
    ]
}
report.update(
    cpu=a.cpu,
    module=identity(mod),
    host=identity(host_script),
    wrapper=identity(tools_dir / "runner.py"),
    training={},
    results={},
)
runner = tools_dir / "runner.py"
trained = gold["training"]["training"]
maxima = [0, 0]
for train in trained:
    n = train["name"]
    local = base / "training/examples" / (n + ".goose")
    prof = base / "training" / (n + ".profile")
    assert (
        identity(local)["sha256"] == train["source_sha256"]
        and identity(prof)["sha256"] == train["profile_sha256"]
    )
    case = (
        base / "training",
        ["examples/" + n + ".goose", "--stdlib", str(stage), *opts],
    )
    ran = run("baseline", n, case, [])
    assert ran["observed"]["emission"]["sha256"] == train["emitted_sha256"]
    size = ran["metrics"]["read_bytes"]
    peaks = {
        int(i): int(v)
        for i, v in [line.split() for line in prof.read_text().splitlines()]
    }
    rates = [math.ceil(peaks[i] / size) for i in [6, 7]]
    maxima = list(map(max, maxima, rates))
    report["training"][n] = {
        "source_bytes": size,
        "source_files": ran["metrics"]["read_files"],
        "token_bytes": peaks[6],
        "ast_bytes": peaks[7],
        "rounded_rates": rates,
    }
report["ratios"] = maxima


def save():
    (HERE / "evidence.json").write_text(json.dumps(report, indent=2) + "\n")


for name, case in cases.items():
    modes = ["baseline", "estimate", "sampled"]
    rows = report["results"].setdefault(name, [])
    for mode in modes:
        row = run(mode, name, case, maxima)
        row.update(
            mode=mode,
            matches_native=row["observed"] == gold["correctness"][name]["reference"],
        )
        rows.append(row)
        save()
for num in range(a.rounds - 1):
    for name in ["blot-parse", "self-check", "self-emit"]:
        for mode in (
            ["sampled", "estimate", "baseline"]
            if num % 2 == 0
            else ["estimate", "baseline", "sampled"]
        ):
            row = run(mode, name, cases[name], maxima)
            row.update(
                mode=mode,
                matches_native=row["observed"]
                == gold["correctness"][name]["reference"],
            )
            report["results"][name].append(row)
            save()
