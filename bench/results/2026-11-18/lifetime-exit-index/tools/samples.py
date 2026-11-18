"""Focused memory-width control for the current self-hosted release."""
from concurrent.futures import ThreadPoolExecutor
from importlib.metadata import version
import json
import os
from pathlib import Path
import subprocess
import sys
import threading

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "wasm-execution-gap-2026-11-18"))
from measure import (
    HOSTED_STACK_BYTES, PreparedModule, create_engine, create_hosted_config,
    measured, run_module, sha256, wasmtime,
)
STAGE = HERE.parent / "wasm-copy-2026-11-18/selfhost-chart"
BASE = STAGE / "build-1"
SOURCE = ["selfhost/main.goose", "--stdlib", "stdlib"]
TARGET = ["--target", "wasm-direct", "-O2", "--wasm-memory64", "--wasm-max-pages", "262144"]


def main():
    chart = json.loads((STAGE / "measurements.json").read_text())
    artifacts = chart["build"]["samples"][0]["artifacts"]
    reference = artifacts["compiler.wasm"]["sha256"]
    native = BASE / "compiler-native"
    assert sha256(native.read_bytes()) == artifacts["compiler-native"]["sha256"]
    assert sha256((BASE / "compiler.wasm").read_bytes()) == reference
    assert sha256((HERE.parent / "wasmtime-ceiling-2026-11-18/profile-output.wasm").read_bytes()) == reference
    os.chdir(STAGE / "source")
    os.sched_setaffinity(0, {2, 3, 4, 5})
    engine = create_engine(create_hosted_config())
    modules = {}
    report = {"source_commit": chart["build"]["source_commit"],
              "source_archive_sha256": chart["build"]["source_archive_sha256"],
              "artifact": reference, "native_sha256": artifacts["compiler-native"]["sha256"],
              "wasmtime": version("wasmtime"), "width_artifacts": {}, "cpu": 6, "samples": []}
    for label, path in (
        ("memory64", BASE / "compiler.wasm"),
        ("candidate64", HERE / "candidate64.wasm"),
        ("memory32", HERE.parent / "wasmtime-ceiling-2026-11-18/profiled32.wasm"),
        ("candidate32", HERE / "candidate32.wasm"),
    ):
        data = path.read_bytes()
        digest = sha256(data)
        modules[label] = (path, data, PreparedModule(engine, wasmtime.Module(engine, data), digest, None, {}))
        report["width_artifacts"][label] = {"sha256": digest, "bytes": len(data)}
        print("compiled module", label, flush=True)

    def run():
        os.sched_setaffinity(0, {6})
        for workload in ("check", "emit"):
            orders = (("native", "memory32", "candidate32", "memory64", "candidate64"),
                      ("candidate64", "memory64", "candidate32", "memory32", "native"))
            for number, order in enumerate(orders, 1):
                for label in order:
                    output = HERE / "emitted.wasm"
                    output.unlink(missing_ok=True)
                    args = [*SOURCE, "--check"]
                    if workload == "emit":
                        args = [*SOURCE, *TARGET, "-o", str(output)]
                    if label == "native":
                        result, elapsed, counters = measured(lambda: subprocess.run(
                            [native, *args], capture_output=True, timeout=90), child=True)
                        assert (result.returncode, result.stdout, result.stderr) == (0, b"", b"")
                    else:
                        path, data, module = modules[label]
                        result, _, counters = measured(lambda: run_module(
                            data, b"", prepared=module, arguments=[str(path), *args]))
                        if (result["exit_code"], result["stdout"], result["stderr"]) != (0, b"", ""):
                            raise RuntimeError((label, workload, result))
                        elapsed = result["timing"]["start_function_ns"]
                    if workload == "emit":
                        assert sha256(output.read_bytes()) == reference
                    report["samples"].append({"workload": workload, "round": number, "label": label,
                                              "wall_ns": elapsed, "counters": counters})
                    (HERE / "samples.json").write_text(json.dumps(report, indent=2) + "\n")
                    print(workload, number, label, round(elapsed / 1e9, 3),
                          counters["instructions"]["value"], flush=True)

    threading.stack_size(HOSTED_STACK_BYTES + (64 << 20))
    with ThreadPoolExecutor(1) as pool:
        pool.submit(run).result()


if __name__ == "__main__":
    main()
