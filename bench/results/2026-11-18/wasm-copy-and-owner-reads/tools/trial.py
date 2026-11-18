"""Compare two Wasm lowering changes on identical self-hosted compiler sources."""
from concurrent.futures import ThreadPoolExecutor
from importlib.metadata import version
import json
import os
from pathlib import Path
import sys
import threading

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "wasm-execution-gap-2026-11-18"))
from measure import (
    ARTIFACT, BASE, HOSTED_STACK_BYTES, SOURCE, PreparedModule, create_engine, create_hosted_config,
    measured, run_module, sha256, wasmtime,
)

PATHS = {"reference": ARTIFACT, "copy": HERE / "copy.wasm", "combined": HERE / "combined.wasm"}


def main():
    os.chdir(BASE / "source")
    os.sched_setaffinity(0, {3, 4, 5})
    engine = create_engine(create_hosted_config())
    modules = {}
    report = {"wasmtime": version("wasmtime"), "run_cpu": 6, "module_artifacts": {}, "samples": []}
    for label, path in PATHS.items():
        data = path.read_bytes()
        digest = sha256(data)
        module = wasmtime.Module(engine, data)
        modules[label] = (data, PreparedModule(engine, module, digest, None, {}))
        report["module_artifacts"][label] = {"sha256": digest, "bytes": len(data)}
        print("ready", label, digest, flush=True)

    def run_trials():
        os.sched_setaffinity(0, {6})
        order = list(PATHS)
        for workload, rounds in (("check", 3), ("emit", 1)):
            for index in range(rounds):
                for label in order[index:] + order[:index]:
                    output = HERE / f"returned-{label}.wasm"
                    output.unlink(missing_ok=True)
                    argv = [*SOURCE, "--check"]
                    if workload == "emit":
                        argv = [*SOURCE, "--target", "wasm-direct", "-O2", "--wasm-memory64",
                                "--wasm-max-pages", "262144", "-o", str(output)]
                    data, prepared = modules[label]
                    result, _, counters = measured(lambda: run_module(
                        data, b"", prepared=prepared, arguments=[str(PATHS[label]), *argv]))
                    if (result["exit_code"], result["stdout"], result["stderr"]) != (0, b"", ""):
                        raise RuntimeError((label, workload, result))
                    emitted = None
                    if workload == "emit":
                        emitted = sha256(output.read_bytes())
                        if emitted != report["module_artifacts"]["reference"]["sha256"]:
                            raise RuntimeError(f"{label} emitted {emitted}, expected the original module")
                    elapsed = result["timing"]["start_function_ns"]
                    report["samples"].append({"round": index + 1, "label": label, "workload": workload,
                        "start_function_ns": elapsed, "counters": counters, "emitted_wasm_sha256": emitted})
                    (HERE / "trial.json").write_text(json.dumps(report, indent=2) + "\n")
                    print(workload, index + 1, label, round(elapsed / 1e9, 3),
                          counters["instructions"]["value"], flush=True)

    threading.stack_size(HOSTED_STACK_BYTES + (64 << 20))
    with ThreadPoolExecutor(1) as pool:
        pool.submit(run_trials).result()


if __name__ == "__main__":
    main()
