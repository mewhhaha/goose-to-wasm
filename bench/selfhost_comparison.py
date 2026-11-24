#!/usr/bin/env python3
"""Measure building the compiler and running it on a frozen copy of itself."""
from __future__ import annotations

import argparse
from base64 import b64decode
from concurrent.futures import ThreadPoolExecutor
import hashlib
from importlib.metadata import version
import io
import json
import os
from pathlib import Path
import platform
import select
import shutil
import subprocess
import sys
import tarfile
import threading
import time


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ["selfhost/main.goose", "--stdlib", "stdlib"]
NATIVE_SOURCES = ("stdlib", "native")
OBJECTS = ("compiler-native", "compiler.wasm", "compiler.c")
WASM_FLAGS = ["--target", "wasm-direct", "-O2", "--wasm-memory64", "--wasm-max-pages", "262144"]
ENGINES = ("native", "wasmtime", "v8")
ALL_ENGINES = ("native", "wasmtime", "v8", "wtime-aot")
WORKLOADS = {"check": [*SOURCE, "--check"], "emit": [*SOURCE, *WASM_FLAGS, "-o", "../emitted.wasm"]}


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def identity(path):
    return {"sha256": sha256(path), "bytes": path.stat().st_size}


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def frozen_archive(commit):
    files = git("ls-tree", "-r", "--name-only", commit, "selfhost").decode().splitlines()
    return git("archive", commit, *(file for file in files if file.endswith(".goose")), *NATIVE_SOURCES)


def verify_frozen_source(source, commit, expected_sha256):
    archive = frozen_archive(commit)
    if hashlib.sha256(archive).hexdigest() != expected_sha256:
        raise RuntimeError("frozen source archive changed")
    verify_source_files(source, archive)


def verify_source_files(source, archive, *, check_extra=False):
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        expected = set()
        for item in tar:
            if not item.isfile():
                continue
            path = source / item.name
            expected.add(path)
            if tar.extractfile(item).read() != path.read_bytes():
                raise RuntimeError(f"frozen source changed: {item.name}")
    if check_extra:
        for path in source.rglob("*"):
            if path.is_file() and path not in expected:
                raise RuntimeError(f"extra file in frozen build source: {path.relative_to(source)}")


def preparation_options(parser):
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--cold-preparation", action="store_true", help="disable the Wasmtime compilation cache")
    group.add_argument("--cache-config", type=lambda path: Path(path).resolve(), help="Wasmtime cache TOML")


def benchmark_engine(args):
    from run_wasmtime import create_engine, create_hosted_config

    config = create_hosted_config()
    if args.cache_config:
        config.cache = str(args.cache_config)
    elif not args.cold_preparation:
        config.cache = True
    return create_engine(config)


def write_report(path, report):
    path.write_text(json.dumps(report, indent=2) + "\n")


def run(argv, cwd, cpus):
    command = ["taskset", "-c", cpus, *map(str, argv)]
    started = time.perf_counter_ns()
    result = subprocess.run(command, cwd=cwd, capture_output=True, timeout=600)
    elapsed = time.perf_counter_ns() - started
    if result.returncode:
        raise RuntimeError(f"{command} exited {result.returncode}\n{result.stderr.decode(errors='replace')}")
    return elapsed, result


def build(args):
    stage = args.stage
    source = stage / "source"
    commit = git("rev-parse", args.commit + "^{commit}").decode().strip()
    archive = frozen_archive(commit)
    archive_sha = hashlib.sha256(archive).hexdigest()
    build_source = source
    if args.build_source:
        build_source = args.build_source
        if stage.is_relative_to(build_source):
            raise ValueError("use an output stage outside the frozen build source")
        verify_source_files(build_source, archive, check_extra=True)
    source.mkdir(parents=True)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(source, filter="data")
    emitter = stage / "emitter"
    shutil.copy2(args.emitter, emitter)
    cc = Path(shutil.which(args.cc)).resolve()
    report = {
        "source_commit": commit,
        "source_archive_sha256": archive_sha,
        "build_working_directory": str(build_source),
        "emitter": identity(emitter),
        "clang": {**identity(cc), "version": subprocess.check_output([cc, "--version"], text=True).strip()},
        "cpu_sets": {"native": args.build_cpus, "wasm": args.cpu},
        "samples": [],
    }
    for round_id in range(args.rounds):
        trial = stage / f"build-{round_id + 1}"
        trial.mkdir()
        native = [sys.executable, ROOT / "scripts/goose_wasm.py", "build", *SOURCE, "--goose", emitter,
                  "--backend", "native", "--cc", cc, "--jobs", args.jobs, "--no-cache", "-O2",
                  "--emit-c", trial / "compiler.c", "--stats", trial / "build.json", "-o", trial / "compiler-native"]
        wasm = [emitter, *SOURCE, *WASM_FLAGS, "-o", trial / "compiler.wasm"]
        commands = [("native", native, args.build_cpus), ("wasm", wasm, args.cpu)]
        if round_id % 2:
            commands.reverse()
        row = {}
        for name, command, cpus in commands:
            elapsed, _ = run(command, build_source, cpus)
            row[name] = {"wall_ns": elapsed, "argv": list(map(str, command))}
            if name == "native":
                stats = json.loads((trial / "build.json").read_text())
                for key in ("frontend_ms", "cc_compile_ms", "cc_link_ms", "total_ms", "native_units", "runtime_unit"):
                    row[name][key] = stats[key]
            print(f"build {round_id + 1} {name}: {elapsed / 1e9:.3f} s", flush=True)
        row["artifacts"] = {filename: identity(trial / filename) for filename in OBJECTS}
        report["samples"].append(row)
        write_report(stage / "builds.json", report)
    if any(row["artifacts"] != report["samples"][0]["artifacts"] for row in report["samples"]):
        raise RuntimeError("repeated builds produced different artifacts")


def receive(child):
    if not select.select([child.stdout], [], [], 600)[0]:
        raise TimeoutError("resident V8 worker stopped responding")
    message = child.stdout.readline()
    if not message:
        raise RuntimeError("resident V8 worker exited without a result")
    return json.loads(message)


def trial(engine, workload, source, native, cpu, run_wasmtime, worker, output, aot_bin=None, stage=None):
    argv = WORKLOADS[workload]
    output.unlink(missing_ok=True)
    if engine == "native":
        elapsed, result = run([native, *argv], source, str(cpu))
        stdout, stderr, status = result.stdout, result.stderr, result.returncode
        sample = {"wall_ns": elapsed}
    elif engine == "wtime-aot":
        timing_file = stage / f"wtime-aot-{workload}.timing.json"
        timing_file.unlink(missing_ok=True)
        cmd = [aot_bin, "--timing-json", timing_file, "--allow-files", source, "--allow-files", stage,
               "--", str(aot_bin), *argv]
        elapsed, result = run(cmd, source, str(cpu))
        stdout, stderr, status = result.stdout, result.stderr, result.returncode
        timing = json.loads(timing_file.read_text()) if timing_file.is_file() else {}
        sample = {
            "wall_ns": int(timing.get("start_function_ns", elapsed)),
            "instantiate_ns": int(timing.get("compile_instantiate_ns", 0)),
            "process_wall_ns": elapsed,
        }
    else:
        if engine == "wasmtime":
            result = run_wasmtime(argv)
            stdout, status = result["stdout"], result["exit_code"]
        else:
            worker.stdin.write(json.dumps(argv) + "\n")
            worker.stdin.flush()
            result = receive(worker)
            stdout, status = b64decode(result["stdout"]), result["exitCode"]
        stderr = result["stderr"].encode()
        sample = {"wall_ns": result["timing"]["start_function_ns"],
                  "instantiate_ns": result["timing"]["compile_instantiate_ns"]}
    if status or stderr:
        raise RuntimeError(f"{engine} {workload} exit {status}: {stderr.decode(errors='replace')}")
    sample["result"] = {
        "exit_code": status,
        "stdout_sha256": hashlib.sha256(stdout).hexdigest(),
        "stderr_sha256": hashlib.sha256(stderr).hexdigest(),
    }
    if workload == "emit":
        sample["result"]["emitted_wasm"] = identity(output)
    elif output.exists():
        raise RuntimeError(f"{engine} --check emitted a Wasm artifact")
    return sample


def measure(args):
    os.sched_setaffinity(0, {args.cpu})
    stage = args.stage
    source = stage / "source"
    builds = json.loads((stage / "builds.json").read_text())
    verify_frozen_source(source, builds["source_commit"], builds["source_archive_sha256"])
    artifacts = builds["samples"][0]["artifacts"]
    binaries = stage / "build-1"
    if any(identity(binaries / name) != digest for name, digest in artifacts.items()):
        raise RuntimeError("build artifact changed")
    if any(row["artifacts"] != artifacts for row in builds["samples"]):
        raise RuntimeError("repeated builds produced different artifacts")
    native, wasm = binaries / "compiler-native", binaries / "compiler.wasm"
    output = stage / "emitted.wasm"
    node = Path(shutil.which("node")).resolve()
    v8_argv = ["taskset", "-c", builds["cpu_sets"]["native"], node, "--no-liftoff",
               "--no-wasm-lazy-compilation", ROOT / "bench/selfhost_v8.mjs", wasm]
    scripts = ["scripts/goose_wasm.py", "scripts/run_wasmtime.py", "scripts/run_wasm.mjs",
               "scripts/run_wtime_aot.py", "bench/selfhost_comparison.py", "bench/selfhost_v8.mjs"]
    selected_engines = tuple(getattr(args, "engines", None) or ENGINES)
    aot_bin = None
    aot_report = None
    if "wtime-aot" in selected_engines:
        sys.path.insert(0, str(ROOT / "scripts"))
        import run_wtime_aot as wtime_aot_runner
        aot_bin, aot_build_ns = wtime_aot_runner.prepare_binary(
            wasm,
            backend="rust",
            cache_dir=stage / "wtime-aot-cache",
            wtime_aot=getattr(args, "wtime_aot", None),
            target_cpu=getattr(args, "wtime_aot_target_cpu", "native"),
            toolchain=getattr(args, "wtime_aot_toolchain", None),
        )
        aot_report = {
            **wtime_aot_runner.wtime_aot_identity(
                getattr(args, "wtime_aot", None),
                backend="rust",
                target_cpu=getattr(args, "wtime_aot_target_cpu", "native"),
                toolchain=getattr(args, "wtime_aot_toolchain", None),
            ),
            "compiled_binary": identity(aot_bin),
            "compile_ns": aot_build_ns,
        }
        print(f"wtime-aot prepared: {aot_build_ns / 1e9:.3f} s ({aot_bin})", flush=True)
    report = {
        "schema": "goose-selfhost-comparison-v1",
        "host": {"platform": platform.platform(), "cpu": args.cpu, "python": sys.version,
                 "cpu_model": next(line.split(":", 1)[1].strip() for line in
                                   Path("/proc/cpuinfo").read_text().splitlines() if line.startswith("model name"))},
        "workloads": WORKLOADS,
        "engines": list(selected_engines),
        "scripts": {script: identity(ROOT / script) for script in scripts},
        "build": builds,
        "execution": {"warmup": {}, "samples": []},
    }
    if aot_report is not None:
        report["wtime_aot"] = aot_report

    sys.path.insert(0, str(ROOT / "scripts"))
    import wasmtime
    from wasmtime import _ffi
    from run_wasmtime import PreparedModule, run_module, HOSTED_STACK_BYTES

    data = wasm.read_bytes()
    # File imports in both runtime hosts resolve relative to the guest's working directory.
    os.chdir(source)
    started = time.perf_counter_ns()
    engine = benchmark_engine(args)
    compiled = wasmtime.Module(engine, data)
    compile_ns = time.perf_counter_ns() - started
    prepared = PreparedModule(engine, compiled, artifacts["compiler.wasm"]["sha256"], None, {})
    report["wasmtime"] = {
        "version": version("wasmtime"), "library": identity(Path(_ffi.dll._name)),
        "preparation_cache_enabled": not args.cold_preparation,
        "cache_config_sha256": sha256(args.cache_config) if args.cache_config else None,
        "config": "hosted config, Cranelift speed", "engine_and_module_ns": compile_ns,
    }
    print(f"Wasmtime prepared: {compile_ns / 1e9:.3f} s", flush=True)

    def run_wasmtime(argv):
        return run_module(data, b"", prepared=prepared, arguments=[str(wasm), *argv])

    def timed(worker):
        ready = receive(worker)
        if ready["source_sha256"] != artifacts["compiler.wasm"]["sha256"]:
            raise RuntimeError("V8 opened a different Wasm module")
        # The eager compilation may use multiple workers. Pin them all for the runs.
        subprocess.run(["taskset", "-apc", str(args.cpu), str(worker.pid)], check=True, capture_output=True)
        report["v8"] = {**ready, "binary": identity(node), "argv": list(map(str, v8_argv)),
                       "node_options": os.environ.get("NODE_OPTIONS", "")}
        print(f"V8 prepared: {ready['module_compile_ns'] / 1e9:.3f} s", flush=True)
        timing = report["execution"]
        expected = {}

        def record(engine_name, workload):
            sample = trial(engine_name, workload, source, native, args.cpu, run_wasmtime, worker, output,
                           aot_bin=aot_bin, stage=stage)
            proof = sample["result"]
            if proof != expected.setdefault(workload, proof):
                raise RuntimeError(f"{engine_name} {workload} result differs")
            if workload == "emit" and proof["emitted_wasm"] != artifacts["compiler.wasm"]:
                raise RuntimeError(f"{engine_name} emitted a different self-hosted module")
            return sample

        for name in selected_engines:
            timing["warmup"][name] = record(name, "check")
            print(f"warmup {name}: {timing['warmup'][name]['wall_ns'] / 1e9:.3f} s", flush=True)
        for round_id in range(args.rounds):
            samples = []
            for index, workload in enumerate(WORKLOADS):
                shift = (round_id + index) % len(selected_engines)
                for name in selected_engines[shift:] + selected_engines[:shift]:
                    sample = record(name, workload)
                    samples.append({"engine": name, "workload": workload, **sample})
                    print(f"run {round_id + 1} {workload} {name}: {sample['wall_ns'] / 1e9:.3f} s", flush=True)
            timing["samples"].append(samples)
            write_report(stage / "measurements.json", report)

    # Mirror the project's hosted runner stack allowance on a dedicated thread.
    threading.stack_size(HOSTED_STACK_BYTES + (64 << 20))
    with subprocess.Popen(v8_argv, cwd=source, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True) as worker:
        try:
            with ThreadPoolExecutor(1) as pool:
                pool.submit(timed, worker).result()
            worker.stdin.close()
            if worker.wait(timeout=5):
                raise RuntimeError("resident V8 process failed")
        finally:
            if worker.poll() is None:
                worker.kill()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(required=True)
    command = sub.add_parser("build")
    command.add_argument("stage", type=lambda path: Path(path).resolve())
    command.add_argument("--emitter", type=Path, default=ROOT / "build/bin/goose")
    command.add_argument("--commit", default="HEAD")
    command.add_argument("--build-source", type=lambda path: Path(path).resolve(), metavar="DIR",
                         help="build from a previous stage's frozen source directory to retain native diagnostic paths")
    command.add_argument("--cc", default="clang-23")
    command.add_argument("--rounds", type=int, default=3)
    command.add_argument("--jobs", type=int, default=8)
    command.add_argument("--build-cpus", required=True)
    command.add_argument("--cpu", required=True)
    command.set_defaults(action=build)
    command = sub.add_parser("run")
    command.add_argument("stage", type=lambda path: Path(path).resolve())
    command.add_argument("--cpu", type=int, required=True)
    command.add_argument("--rounds", type=int, default=3)
    command.add_argument("--engines", nargs="+", choices=ALL_ENGINES, default=list(ENGINES))
    command.add_argument("--wtime-aot", type=Path, default=None, help="optional path to wtime-aot binary")
    command.add_argument("--wtime-aot-target-cpu", default="native")
    command.add_argument("--wtime-aot-toolchain", default=None)
    preparation_options(command)
    command.set_defaults(action=measure)
    args = parser.parse_args()
    args.action(args)


if __name__ == "__main__":
    main()
