"""Run from the repository root: python measure.py BASELINE CANDIDATE OUT.json CPU."""
import contextlib
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import sys
import tempfile

import wasmtime

root = Path.cwd()
sys.path.insert(0, str(root / "bench"))
sys.path.insert(0, str(root / "scripts"))
from langbench_hot import V8Worker
import run_wasmtime as host


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checksum(n):
    return sum((i % 5 - 2) * 8193 for i in range(n))


def fuel(data, counts):
    config = host.create_config()
    config.consume_fuel = True
    engine = wasmtime.Engine(config)
    module = wasmtime.Module(engine, data)
    costs = []
    for n in counts:
        with wasmtime.Store(engine) as store:
            budget = 10**12
            store.set_fuel(budget)
            numbers = []

            def reject(*args):
                raise RuntimeError(f"unexpected guest failure {args}")

            callbacks = {
                "bench_input": lambda: n,
                "bench_clock": lambda: budget - store.get_fuel(),
                "print_i64": numbers.append,
                "newline": lambda: None,
                "exit": reject,
                "abort": reject,
            }
            imports = [wasmtime.Func(store, item.type, callbacks.get(item.name, reject))
                       for item in module.imports]
            instance = wasmtime.Instance(store, module, imports)
            instance.exports(store)["_start"](store)
            if len(numbers) != 2 or numbers[0] != checksum(n):
                raise ValueError(f"fuel run at {n} returned {numbers}")
            costs.append(numbers[1])
    return costs


def main():
    before, after, out, cpu_text = sys.argv[1:]
    cpu = int(cpu_text)
    os.sched_setaffinity(0, {cpu})
    source = Path(__file__).with_name("sum.goose").resolve()
    node = Path(shutil.which("node"))
    library, = Path(wasmtime.__file__).parent.rglob("_libwasmtime.so")
    counts = [1001, 2002, 4004, 8008]
    fuel_counts = [201, 402, 804, 1608]
    compilers = {"before": Path(before).resolve(), "after": Path(after).resolve()}
    result = {
        "source_sha256": digest(source), "cpu": cpu, "counts": counts, "fuel_counts": fuel_counts,
        "compilers": {label: {"path": str(path), "sha256": digest(path)} for label, path in compilers.items()},
        "tools": {
            "node": subprocess.check_output([node, "-v"], text=True).strip(),
            "v8": subprocess.check_output([node, "-p", "process.versions.v8"], text=True).strip(),
            "node_sha256": digest(node), "python": sys.version, "python_sha256": digest(Path(sys.executable)),
            "wasmtime": importlib.metadata.version("wasmtime"), "wasmtime_sha256": digest(library),
            "run_wasmtime_sha256": digest(root / "scripts/run_wasmtime.py"),
            "run_wasm_sha256": digest(root / "scripts/run_wasm.mjs"),
        },
        "args": ["--stdlib", "stdlib", "--target", "wasm-direct", "-O2", "--wasm-max-pages", "8192"],
        "warmups_per_cell": 2, "rounds": 7, "modules": {}, "timings": [],
    }
    with tempfile.TemporaryDirectory() as directory, contextlib.ExitStack() as stack:
        for width in (32, 64):
            runners = {}
            for label, compiler in compilers.items():
                name = f"{label}-{width}"
                path = Path(directory) / (name + ".wasm")
                args = result["args"].copy()
                if width == 64:
                    args.append("--wasm-memory64")
                subprocess.run([compiler, source, *args, "-o", path], check=True)
                data = path.read_bytes()
                sha = digest(path)
                result["modules"][name] = {"sha256": sha, "bytes": len(data),
                                            "kernel_fuel": fuel(data, fuel_counts)}
                worker = V8Worker(path, sha, cpu)
                stack.callback(worker.close)
                prepared = host.prepare_module(data, path.with_suffix(".cwasm"))
                runners["V8", label] = worker.run
                runners["Wasmtime", label] = lambda stdin, d=data, p=prepared: host.run_module(d, stdin, prepared=p)

            for n in counts:
                expected = checksum(n)
                for engine in ("Wasmtime", "V8"):
                    samples = {"before": [], "after": []}
                    for iteration in range(-2, 7):
                        order = ["before", "after"]
                        if iteration % 2:
                            order.reverse()
                        for label in order:
                            run = runners[engine, label](f"{n}\n")
                            values = run["stdout"].split()
                            if run["exit_code"] or len(values) != 2 or int(values[0]) != expected:
                                raise ValueError(f"{engine} {label} {n}: {run}")
                            if iteration >= 0:
                                samples[label].append(int(values[1]))
                    result["timings"].append({"engine": engine, "width": width, "count": n,
                                              "checksum": expected, "kernel_ns": samples})
                    print(engine, width, n, {k: statistics.median(v) for k, v in samples.items()}, flush=True)
    Path(out).write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
