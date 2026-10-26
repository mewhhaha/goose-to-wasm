#!/usr/bin/env python3
"""Measure complete cold builds and validated runtime work across three backends.

Cold means the driver content cache is disabled and every compiler/linker is a
fresh process; OS filesystem caches are not purged. Each executable receives
its workload from stdin. Two kernel executions warm the engine in the SAME
process before the timed region. Results include raw samples and dispersion;
no speed claim is produced when compilation or checksum validation fails.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import random
import statistics
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
WORKLOADS = {
    "integer_mod": {"input": 10000000, "smoke_input": 1000, "description": "dependent i64 recurrence and Euclidean remainder"},
    "recursive_fibonacci": {"input": 35, "smoke_input": 12, "description": "runtime-input recursive Fibonacci"},
    "float_recurrence": {"input": 8000000, "smoke_input": 1000, "description": "ordered f64 recurrence without fused multiply-add"},
    "array_updates": {"input": 8000000, "smoke_input": 1000, "description": "1024-element fixed array with dynamic indexed updates"},
}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def checksum(name, count):
    """Independent small reference algorithm, outside every timed sample."""
    if name == "recursive_fibonacci":
        a, b = 0, 1
        for _ in range(count):
            a, b = b, a + b
        return a
    if name == "float_recurrence":
        value = 0.5
        for _ in range(count):
            value = (value * 1.0000001 + 0.000001) / 1.0000002
        return int(value * 1000000.0)
    total = 0
    if name == "integer_mod":
        value = 1
        for _ in range(count):
            value = value * 48271 % 2147483647
            total = (total + value) % 1000000007
    elif name == "array_updates":
        values = [1] * 1024
        for i in range(count):
            index = i % 1024
            value = (values[index] * 48271 + i) % 2147483647
            values[index] = value
            total = (total + value) % 1000000007
    else:
        raise ValueError("unknown benchmark: " + name)
    return total


def summary(values):
    if not values:
        return None
    ordered = sorted(values)
    median = statistics.median(ordered)
    def percentile(fraction):
        position = (len(ordered) - 1) * fraction
        left = int(position)
        right = min(left + 1, len(ordered) - 1)
        return ordered[left] + (ordered[right] - ordered[left]) * (position - left)
    return {"n": len(values), "median": median, "min": ordered[0], "max": ordered[-1],
            "mad": statistics.median(abs(value - median) for value in ordered),
            "p25": percentile(0.25), "p75": percentile(0.75), "samples": values}


def command_version(command):
    try:
        result = subprocess.run(command, text=True, capture_output=True, timeout=30, check=False)
        return {"command": command, "exit_code": result.returncode, "output": (result.stdout + result.stderr).strip()}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"command": command, "error": str(error)}


def metadata(args):
    cpu = "unknown"
    info = Path("/proc/cpuinfo")
    try:
        for line in info.read_text().splitlines():
            if line.startswith("model name"):
                cpu = line.partition(":")[2].strip()
                break
    except OSError:
        pass
    affinity = None
    if hasattr(os, "sched_getaffinity"):
        try:
            affinity = sorted(os.sched_getaffinity(0))
        except OSError:
            pass
    try:
        wasmtime_version = importlib.metadata.version("wasmtime")
    except importlib.metadata.PackageNotFoundError:
        wasmtime_version = "not installed"
    tracked_inputs = [ROOT / "scripts" / "goose_wasm.py", ROOT / "oracle" / "goose_wasm.py", ROOT / "scripts" / "run_wasm.mjs",
                      ROOT / "scripts" / "run_wasmtime.py", ROOT / "bench" / "host_input.c", Path(__file__)]
    return {"platform": platform.platform(), "machine": platform.machine(), "cpu": cpu,
            "supplied_machine_label": args.machine_label,
            "logical_cpu_count": os.cpu_count(), "cpu_affinity": affinity, "python": sys.version,
            "node": command_version([args.node, "-p", "JSON.stringify(process.versions)"]),
            "native_cc": command_version([args.cc, "--version"]), "emcc": command_version([args.emcc, "--version"]),
            "wasmtime": wasmtime_version, "toolchain_pin": json.loads((ROOT / "toolchain.json").read_text()),
            "wasmtime_config": {"cranelift_opt_level": "speed", "wasm_memory64": True, "wasm_tail_call": True,
                                 "wasm_exceptions": True, "wasm_simd": True, "wasm_bulk_memory": True,
                                 "wasm_multi_value": True, "wasm_threads": False, "wasm_relaxed_simd": False},
            "v8_runner_flags": [],
            "compiler_sha256": digest(args.goose),
            "input_sha256": {str(path.relative_to(ROOT)): digest(path) for path in tracked_inputs}}


def run(command, *, directory, stdin="", timeout=300, name="run"):
    started = time.perf_counter_ns()
    result = subprocess.run([str(value) for value in command], cwd=ROOT, input=stdin, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, check=False)
    seconds = (time.perf_counter_ns() - started) / 1e9
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f"{name}.command.json").write_text(json.dumps([str(value) for value in command], indent=2) + "\n")
    (directory / f"{name}.stdout").write_text(result.stdout)
    (directory / f"{name}.stderr").write_text(result.stderr)
    if result.returncode:
        raise RuntimeError(f"{name} exited {result.returncode}: {(result.stdout + result.stderr)[-3000:]}")
    return result, seconds


def render(report):
    meta = report["environment"]
    lines = ["# Goose backend benchmark", "", f"Status: **{report['status']}**.", "",
             "These are measurements from this machine and workload set, not universal speed claims.", "",
             f"CPU: {meta['cpu']}. Platform: {meta['platform']}. Wasmtime: {meta['wasmtime']}.",
             f"Supplied machine description: {meta['supplied_machine_label'] or 'none'}.",
             f"Compiler SHA-256: `{meta['compiler_sha256']}`.", "",
             "## Measurement contract", "",
             "All backends use the same Goose source and `-O2` semantic passes. Direct emits binary Wasm without LLVM; "
             "native C and C-Wasm additionally use their C compiler's `-O2`. Direct uses memory32. The C-Wasm profile "
             "preserves Goose's LP64 C layout in one standalone memory64 binary, run unchanged on V8 and Wasmtime "
             "through the same WASI64 service contract. These memory-layout differences are part of the compared targets.", "",
             "Cold-build wall time includes driver startup, Goose frontend/emission, and any C compilation/linking. "
             "`--no-cache` disables the content cache. OS file caches are retained; this is a complete fresh-process build, "
             "not a disk-cold experiment. Emscripten's installed system-library cache is reused. Sample order is deterministically shuffled.", "",
             f"Each runtime process performs {report['configuration']['kernel_warmups']} untimed kernel executions before "
             "one timed execution. The timed region excludes process startup, Wasm compilation/instantiation, input parsing, "
             "and output formatting. It includes two scalar FFI barriers and the clock-call boundary. Process wall time "
             "includes all warmup kernels and startup. Outer warmup processes prime system caches only.", "",
             "Inputs arrive at runtime through stdin; a volatile C barrier or Wasm host import makes them opaque to "
             "optimizers. A sink consumes every computed result before the end timestamp. Each sample must match the "
             "independent Python reference checksum. There are no Python callbacks inside computational loops.", "",
             "## Complete cold builds", "",
             "Times are median milliseconds; dispersion is median absolute deviation (MAD).", "",
             "| Workload | Backend | Samples | Median ms | MAD ms | Module / executable bytes |",
             "| --- | --- | ---: | ---: | ---: | ---: |"]
    for row in report["compile"]:
        values = row["wall_seconds"]
        lines.append(f"| {row['workload']} | {row['backend']} | {values['n']} | {values['median'] * 1000:.3f} | {values['mad'] * 1000:.3f} | {row['bytes']} |")
    lines += ["", "## Runtime", "", "| Workload | Backend / engine | Samples | Timed region median ms | MAD ms | Process median ms | Checksum |",
              "| --- | --- | ---: | ---: | ---: | ---: | ---: |"]
    for row in report["runtime"]:
        region, process = row["timed_region_seconds"], row["process_wall_seconds"]
        lines.append(f"| {row['workload']} | {row['backend']} / {row['engine']} | {region['n']} | {region['median'] * 1000:.3f} | {region['mad'] * 1000:.3f} | {process['median'] * 1000:.3f} | {row['checksum']} |")
    lines += ["", "## Qualification and limits", ""]
    for warning in report["warnings"]:
        lines.append("- " + warning)
    for failure in report["failures"]:
        lines.append("- Failed: " + failure)
    lines += ["", "Raw samples, min/max, quartiles, tool versions, commands, checksums, fixture hashes, and driver phase "
              "timings are in `report.json` and the adjacent per-sample logs. Unchanged-build and edited-source latency "
              "are measured separately by `bench/incremental.py`.", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=ROOT / "build" / "bin" / "goose")
    parser.add_argument("--emcc", default=os.environ.get("EMCC", "emcc"))
    parser.add_argument("--cc", default=os.environ.get("CC", "cc"))
    parser.add_argument("--node", default="node")
    parser.add_argument("--machine-label", help="optional independently observed hardware description, recorded as supplied")
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--compile-samples", type=int, default=5)
    parser.add_argument("--warmups", type=int, default=2, help="untimed whole-process warmups per runtime cell")
    parser.add_argument("--kernel-warmups", type=int, default=2, help="untimed kernel executions inside every runtime process")
    parser.add_argument("--smoke", action="store_true", help="small correctness-only workloads; not performance evidence")
    parser.add_argument("--workloads", nargs="+", choices=tuple(WORKLOADS), default=list(WORKLOADS))
    parser.add_argument("--backends", nargs="+", choices=("direct", "c-wasm", "native"), default=["direct", "c-wasm", "native"])
    parser.add_argument("--engines", nargs="+", choices=("v8", "wasmtime"), default=["v8", "wasmtime"])
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build" / "benchmark")
    args = parser.parse_args()
    if min(args.samples, args.compile_samples) < 1 or min(args.warmups, args.kernel_warmups) < 0:
        parser.error("sample counts must be positive and warmup counts nonnegative")
    args.goose = args.goose.resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    report = {"schema": "goose-backend-benchmark-v1", "status": "incomplete", "started_utc": datetime.now(timezone.utc).isoformat(),
              "configuration": vars(args).copy(),
              "environment": metadata(args), "compile": [], "runtime": [], "warnings": [], "failures": []}
    report["configuration"]["goose"] = str(args.goose)
    report["configuration"]["output_dir"] = str(output)
    if args.smoke:
        report["warnings"].append("Smoke mode uses deliberately small workloads and cannot establish a performance ranking.")
    if min(args.samples, args.compile_samples) < 5:
        report["warnings"].append("Fewer than five samples were collected in at least one category; treat dispersion and medians as preliminary.")
    report["warnings"].append("The direct backend supports a documented fragment of Goose. Results do not establish full-language parity or compilation of arbitrary programs.")
    report["warnings"].append("Native and C-Wasm use different C compilers; engine tiering, host-call costs, machine load, and CPU frequency can affect results.")
    workloads = {}
    for name in args.workloads:
        settings = WORKLOADS[name]
        count = settings["smoke_input"] if args.smoke else settings["input"]
        source = ROOT / "bench" / "fixtures" / f"{name}.goose"
        workloads[name] = {"input": count, "checksum": checksum(name, count), "source": source,
                           "sha256": digest(source), "description": settings["description"]}
    artifacts = {}
    compile_samples = {}
    rng = random.Random(87123)
    tasks = [(name, backend, sample) for sample in range(args.compile_samples)
             for name in args.workloads for backend in args.backends]
    rng.shuffle(tasks)
    for name, backend, sample in tasks:
        directory = output / "compile" / name / backend / str(sample)
        directory.mkdir(parents=True, exist_ok=True)
        artifact = directory / ("program.bin" if backend == "native" else "program.wasm")
        stats = directory / "driver-stats.json"
        command = [sys.executable, ROOT / "scripts" / "goose_wasm.py", "build", workloads[name]["source"], "-o", artifact,
                   "--backend", backend, "-O2", "--no-cache", "--offline", "--goose", args.goose, "--stats", stats]
        if backend != "direct":
            command += ["--c-source", ROOT / "bench" / "host_input.c", "--cc", args.cc, "--emcc", args.emcc]
        try:
            _, seconds = run(command, directory=directory, name="build")
            data = {"seconds": seconds, "artifact": str(artifact), "bytes": artifact.stat().st_size,
                    "sha256": digest(artifact), "driver_stats": json.loads(stats.read_text())}
            compile_samples.setdefault((name, backend), []).append(data)
            artifacts[(name, backend)] = artifact
            print(f"BUILD {name}/{backend}/{sample}: {seconds * 1000:.3f} ms", flush=True)
        except (OSError, RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
            report["failures"].append(f"compile {name}/{backend}/{sample}: {error}")
            print(report["failures"][-1], flush=True)
    for (name, backend), values in sorted(compile_samples.items()):
        report["compile"].append({"workload": name, "backend": backend, "source_sha256": workloads[name]["sha256"],
                                  "wall_seconds": summary([value["seconds"] for value in values]), "bytes": values[-1]["bytes"],
                                  "samples": values})
    runtime_samples = {}
    cells = [(name, backend, engine) for name, backend in artifacts
             for engine in (["native"] if backend == "native" else args.engines)]
    for round_number in range(-args.warmups, args.samples):
        shuffled = cells.copy()
        rng.shuffle(shuffled)
        for name, backend, engine in shuffled:
            artifact = artifacts[(name, backend)]
            if engine == "native":
                command = [artifact]
            elif engine == "v8":
                command = [args.node, ROOT / "scripts" / "run_wasm.mjs", artifact]
            else:
                command = [sys.executable, ROOT / "scripts" / "run_wasmtime.py", artifact]
            label = f"warmup{-round_number}" if round_number < 0 else f"sample{round_number}"
            directory = output / "runtime" / name / backend / engine
            stdin = f"{workloads[name]['input']} {args.kernel_warmups}\n"
            try:
                result, process_seconds = run(command, directory=directory, stdin=stdin, name=label)
                fields = result.stdout.splitlines()
                if len(fields) != 2:
                    raise RuntimeError(f"expected checksum and duration, received {result.stdout!r}")
                actual, nanoseconds = map(int, fields)
                if actual != workloads[name]["checksum"]:
                    raise RuntimeError(f"checksum {actual} != reference {workloads[name]['checksum']}")
                if nanoseconds <= 0:
                    raise RuntimeError(f"nonpositive measured duration: {nanoseconds}")
                if round_number >= 0:
                    runtime_samples.setdefault((name, backend, engine), []).append({"process_seconds": process_seconds,
                                                                                  "timed_region_seconds": nanoseconds / 1e9})
                print(f"RUN {name}/{backend}/{engine}/{label}: {nanoseconds / 1e6:.3f} ms region, checksum {actual}", flush=True)
            except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
                report["failures"].append(f"runtime {name}/{backend}/{engine}/{label}: {error}")
                print(report["failures"][-1], flush=True)
    for (name, backend, engine), values in sorted(runtime_samples.items()):
        region = summary([value["timed_region_seconds"] for value in values])
        report["runtime"].append({"workload": name, "backend": backend, "engine": engine,
                                  "input": workloads[name]["input"], "checksum": workloads[name]["checksum"],
                                  "artifact": str(artifacts[(name, backend)]),
                                  "artifact_sha256": digest(artifacts[(name, backend)]),
                                  "timed_region_seconds": region,
                                  "process_wall_seconds": summary([value["process_seconds"] for value in values])})
        if not args.smoke and region["median"] < 0.01:
            report["warnings"].append(f"{name}/{backend}/{engine} timed region is below 10 ms; fixed overhead is material.")
    report["status"] = "failed" if report["failures"] else "passed"
    report["finished_utc"] = datetime.now(timezone.utc).isoformat()
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    (output / "report.md").write_text(render(report), encoding="utf-8")
    print(f"{report['status']}: {output / 'report.md'}")
    return int(bool(report["failures"]))


if __name__ == "__main__":
    sys.exit(main())
