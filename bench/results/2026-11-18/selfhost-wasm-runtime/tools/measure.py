"""Paired check and emission timing for the frozen self-hosted compiler."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack
from ctypes import CDLL, create_string_buffer, get_errno, byref
import fcntl
import hashlib
from importlib.metadata import version
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import threading
from time import perf_counter_ns

import wasmtime
from wasmtime import _ffi

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from run_wasmtime import HOSTED_STACK_BYTES, PreparedModule, create_engine, create_hosted_config, run_module

BASE = ROOT / "build/selfhost-comparison-2026-11-17"
SOURCE = ["selfhost/main.goose", "--stdlib", "stdlib"]
NATIVE = BASE / "build-1/compiler-native"
OUTPUT = HERE / "emit.wasm"
ARTIFACT = BASE / "build-1/compiler.wasm"
MODULES = {
    "equal64": ARTIFACT,
    "profile64": HERE / "profiled64.wasm",
    "profile32": HERE / "profiled32.wasm",
    "checked32": HERE / "profiled32.wasm",
}
EVENTS = {"cycles": 0, "instructions": 1, "branches": 4, "branch_misses": 5}
LIBC = CDLL(None, use_errno=True)
PERF_EVENT_OPEN = 298  # Linux x86-64
DISABLED, INHERIT, EXCLUDE_KERNEL, EXCLUDE_HV = 1, 2, 32, 64
PERF_ENABLE, PERF_DISABLE = 0x2400, 0x2401


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def counter(event, inherit):
    attributes = create_string_buffer(128)
    flags = DISABLED | EXCLUDE_KERNEL | EXCLUDE_HV
    if inherit:
        flags |= INHERIT
    # Hardware type, event index, enabled/running time reporting.
    struct.pack_into("IIQQQQQ", attributes, 0, 0, 128, event, 0, 0, 3, flags)
    fd = LIBC.syscall(PERF_EVENT_OPEN, byref(attributes), 0, -1, -1, 0)
    if fd < 0:
        raise OSError(get_errno(), "perf_event_open")
    return fd


def measured(call, child=False):
    with ExitStack() as stack:
        fds = {}
        for name, event in EVENTS.items():
            fd = counter(event, child)
            stack.callback(os.close, fd)
            fds[name] = fd
        for fd in fds.values():
            fcntl.ioctl(fd, PERF_ENABLE)
        started = perf_counter_ns()
        result = call()
        wall = perf_counter_ns() - started
        for fd in fds.values():
            fcntl.ioctl(fd, PERF_DISABLE)
        counts = {}
        for name, fd in fds.items():
            count, enabled, running = struct.unpack("QQQ", os.read(fd, 24))
            counts[name] = dict(value=count, time_enabled_ns=enabled, time_running_ns=running)
        return result, wall, counts


def main():
    os.chdir(BASE / "source")
    os.sched_setaffinity(0, {3, 4, 5})
    config = create_hosted_config()
    engine = create_engine(config)
    config = create_hosted_config()
    config.signals_based_traps = False
    explicit = create_engine(config)
    prepared = {}
    report = {
        "source_commit": "38826b425b68eebb6593ec9ff366a0de08723bf2",
        "source_archive_sha256": json.loads((BASE / "builds.json").read_text())["source_archive_sha256"],
        "engine_sha256": sha256(Path(_ffi.dll._name).read_bytes()),
        "engine_version": version("wasmtime"),
        "prepare_cpus": [3, 4, 5],
        "run_cpu": 6,
        "native_sha256": sha256(NATIVE.read_bytes()),
        "modules": {},
        "runs": [],
    }
    for label, path in MODULES.items():
        data = path.read_bytes()
        sha = sha256(data)
        instance_engine = explicit if label == "checked32" else engine
        started = perf_counter_ns()
        module = wasmtime.Module(instance_engine, data)
        report["modules"][label] = {
            "sha256": sha, "bytes": len(data), "prepare_ns": perf_counter_ns() - started,
            "signals_based_traps": label != "checked32",
        }
        prepared[label] = (data, PreparedModule(instance_engine, module, sha, None, {}))
        print("prepared", label, report["modules"][label]["prepare_ns"] / 1e9, flush=True)

    def trials():
        os.sched_setaffinity(0, {6})

        def run_case(workload, label, round_id):
            OUTPUT.unlink(missing_ok=True)
            argv = [*SOURCE, "--check"]
            if workload == "emit":
                argv = [*SOURCE, "--target", "wasm-direct", "-O2", "--wasm-memory64",
                        "--wasm-max-pages", "262144", "-o", str(OUTPUT)]
            if label == "native":
                def invoke():
                    return subprocess.run([NATIVE, *argv], capture_output=True, timeout=90)

                result, elapsed, counts = measured(invoke, child=True)
                status, stdout, stderr = result.returncode, result.stdout, result.stderr
                setup = None
            else:
                data, module = prepared[label]

                def invoke():
                    return run_module(data, b"", prepared=module, arguments=[str(MODULES[label]), *argv])

                result, _, counts = measured(invoke)
                elapsed = result["timing"]["start_function_ns"]
                setup = result["timing"]["compile_instantiate_ns"]
                status, stdout, stderr = result["exit_code"], result["stdout"], result["stderr"].encode()
            if (status, stdout, stderr) != (0, b"", b""):
                raise RuntimeError((label, workload, status, stdout[:1000], stderr[:1000]))
            returned = None
            if workload == "emit":
                returned = sha256(OUTPUT.read_bytes())
                if returned != report["modules"]["equal64"]["sha256"]:
                    raise RuntimeError(f"{label} emitted a different target: {returned}")
            sample = dict(round=round_id, cell=label, workload=workload, elapsed_ns=elapsed,
                          instantiate_ns=setup, counters=counts, exit_code=status,
                          stdout_sha256=sha256(stdout), stderr_sha256=sha256(stderr), emitted_sha256=returned)
            report["runs"].append(sample)
            (HERE / "measurements.json").write_text(json.dumps(report, indent=2) + "\n")
            print(workload, label, round_id, round(elapsed / 1e9, 3),
                  counts["instructions"]["value"], counts["branch_misses"]["value"], flush=True)

        orders = [
            ["native", "equal64", "profile32", "profile64", "checked32"],
            ["checked32", "profile64", "profile32", "equal64", "native"],
            ["profile64", "equal64", "native", "checked32", "profile32"],
        ]
        for index, order in enumerate(orders, 1):
            for label in order:
                run_case("check", label, index)
        for index, order in enumerate((("equal64", "profile32"), ("profile32", "equal64")), 1):
            for label in order:
                run_case("emit", label, index)

    threading.stack_size(HOSTED_STACK_BYTES + (64 << 20))
    with ThreadPoolExecutor(1) as pool:
        pool.submit(trials).result()


if __name__ == "__main__":
    main()
