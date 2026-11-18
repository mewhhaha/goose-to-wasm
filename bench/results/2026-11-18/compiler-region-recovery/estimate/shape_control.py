"""Measure a novel compact arithmetic call tree and a byte-matched low-density tree."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import time

p = argparse.ArgumentParser(description=__doc__)
for name in ["repo", "compiler_stage", "memory_stage", "out"]:
    p.add_argument(name, type=Path)
p.add_argument("--cpu", type=int, default=4)
a = p.parse_args()
REPO, stage, base, HERE = [
    v.resolve() for v in (a.repo, a.compiler_stage, a.memory_stage, a.out)
]
tools_dir = Path(__file__).resolve().parent
os.environ.update(
    ESTIMATE_REPO=str(REPO), ESTIMATE_FROZEN_HOST=str(HERE / "run_wasmtime_frozen.py")
)
os.sched_setaffinity(0, {a.cpu})
resource.setrlimit(
    resource.RLIMIT_STACK, (256 << 20, resource.getrlimit(resource.RLIMIT_STACK)[1])
)
python = REPO / ".venv/bin/python"
stdlib = stage / "source/stdlib"


def tree_blob(height):
    lines = []
    for i in reversed(range(1, 1 << height)):
        rhs = f"x+{i}"
        if 2 * i < 1 << height:
            rhs = f"g{2 * i}(x)+g{2 * i + 1}(x)"
        lines.append(f"fn g{i}(x:i64)->i64{{return {rhs};}}\n")
    lines.append("fn main(){print(g1(1));}\n")
    return "".join(lines).encode()


dense = tree_blob(17)
sparse = tree_blob(13)
sparse += b"//" + b" " * (len(dense) - len(sparse) - 3) + b"\n"
assert len(dense) == len(sparse)
train = json.loads((HERE / "evidence.json").read_text())
result = {}
for name, data in [("compact", dense), ("padded", sparse)]:
    f = HERE / (name + ".goose")
    f.write_bytes(data)
    row = {
        "input_bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "outcomes": {},
    }
    args = [f.name, "--stdlib", str(stdlib), "--parse"]
    for mode in ["native", "baseline", "estimate", "sampled"]:
        command = [stage / "build-1/compiler-native"]
        if mode != "native":
            command = [
                python,
                tools_dir / "runner.py",
                base / "root32.wasm",
                "--cache",
                HERE / "root32.cwasm",
                "--timing-json",
                HERE / "shape-timing.json",
                "--",
            ]
        t = time.perf_counter_ns()
        r = subprocess.run(
            [*command, *args],
            cwd=HERE,
            capture_output=True,
            timeout=60,
            env={
                **os.environ,
                "PYTHONDONTWRITEBYTECODE": "1",
                "POLICY": mode,
                "SIZING_JSON": str(HERE / "shape-metric.json"),
                "RATIOS": json.dumps(train["ratios"]),
            },
        )
        wall = time.perf_counter_ns() - t
        m = {
            "status": r.returncode,
            "stderr": r.stderr.decode(),
            "stdout": r.stdout.decode(),
            "wall_ns": wall,
        }
        if mode != "native":
            m["metrics"] = json.loads((HERE / "shape-metric.json").read_text())
            m["timing"] = json.loads((HERE / "shape-timing.json").read_text())
        if mode == "native":
            assert r.returncode == 0 and not r.stderr and not r.stdout
        row["outcomes"][mode] = m
        print(name, mode, m["status"], m["stderr"].strip(), flush=True)
    result[name] = row
    (HERE / "shape.json").write_text(json.dumps(result, indent=2) + "\n")
