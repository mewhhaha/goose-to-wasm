"""Sample the labeled portions of the Wasmtime thread on a frozen compiler check."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import ctypes
import hashlib
import json
import os
from pathlib import Path
import sys
import threading
import time
import types
from importlib.metadata import version

root = Path(__file__).resolve().parents[5]
sys.path[:0] = [str(root / "scripts"), str(root / "bench")]
from selfhost_comparison import benchmark_engine, preparation_options, verify_frozen_source
from run_wasmtime import HOSTED_STACK_BYTES, PreparedModule
import wasmtime
from wasmtime import _ffi

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("stage", type=lambda s: Path(s).resolve())
p.add_argument("frozen", type=lambda s: Path(s).resolve())
p.add_argument("--rounds", type=int, default=6)
p.add_argument("--cpu", type=int, required=True)
p.add_argument("--mode", choices=("counts", "phases", "outer"), required=True)
preparation_options(p)
args = p.parse_args()
if args.rounds < 1:
    p.error("--rounds must be positive")
build = json.loads((args.frozen / "builds.json").read_text())
source = args.frozen / "source"
verify_frozen_source(source, build["source_commit"], build["source_archive_sha256"])
os.sched_setaffinity(0, {args.cpu})
os.chdir(source)
engine = benchmark_engine(args)
def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

host_path = root / "scripts/run_wasmtime.py"
host = types.ModuleType("profiled_host")
host.__file__ = str(host_path)
host_code = host_path.read_text()
old = '("env", "gs_os_write_stdout"): (sliced("s", lambda _c, text: chunks.append(text)), True)'
# These probes all use the memory64 stdout ABI, which passes pointer and length separately.
new = '("env", "gs_os_write_stdout"): (lambda c, p, n: observe(c, p, memory_bytes(c, p, n), chunks), True)'
cleanup = "        if store is not None:\n            store.close()"
if host_code.count(old) != 1 or host_code.count(cleanup) != 1:
    raise ValueError("host write hook or store cleanup changed")
exec(compile(host_code.replace(old, new).replace(cleanup, "        abort_if_active()\n" + cleanup), str(host_path), "exec"), host.__dict__)
library = ctypes.CDLL(str(args.stage / "sampler.so"), use_errno=True)
library.start_sampler.argtypes = [ctypes.c_void_p, ctypes.c_long]
library.stop_sampler.argtypes = [ctypes.POINTER(ctypes.c_int)]
tick_counts = ctypes.c_int * 17
active = False
scope = {}
period = 0
def abort_if_active():
    global active
    if active:
        library.stop_sampler(tick_counts())
        active = False
        raise ValueError("profiling window ended before marker teardown")
def observe(caller, pointer, data, chunks):
    global active
    if args.mode == "counts":
        chunks.append(data)
        return
    if data == b"MPSAMPLE\0":
        if active or scope:
            raise ValueError("duplicate start marker")
        memory = caller.get("memory")
        base = ctypes.addressof(memory.data_ptr(caller).contents)
        if memory.type(caller).limits.max * 65536 > host.HOSTED_RESERVATION_BYTES:
            raise ValueError("guest exceeds fixed host reservation")
        if library.start_sampler(base + pointer + 8, period):
            raise OSError(ctypes.get_errno(), "start_sampler")
        active = True
        scope.update(start=time.thread_time_ns(), base=base)
    elif data == b"MPFINISH":
        if not active:
            raise ValueError("end marker before start")
        elapsed = time.thread_time_ns() - scope.pop("start")
        values = tick_counts()
        if library.stop_sampler(values):
            raise RuntimeError("stop_sampler")
        active = False
        if scope.pop("base") != ctypes.addressof(caller.get("memory").data_ptr(caller).contents):
            raise ValueError("guest memory moved")
        scope.update(lifetime_cpu_ns=elapsed, samples=list(values)[:16], overruns=values[16])
    else:
        chunks.append(data)
host.observe = observe
host.abort_if_active = abort_if_active
report = dict(mode=args.mode, cpu=args.cpu, wasmtime=version("wasmtime"), library_sha256=sha(Path(_ffi.dll._name)),
              workload_commit=build["source_commit"], workload_archive_sha256=build["source_archive_sha256"],
              host_sha256=sha(host_path), sampler_sha256=sha(args.stage / "sampler.so"), modules={}, runs=[])
modules = {}
for label in ("grouped", "released"):
    path = args.stage / f"{label}-{args.mode}/probe.wasm"
    data = path.read_bytes()
    digest = sha(path)
    compiled = wasmtime.Module(engine, data)
    modules[label] = data, PreparedModule(engine, compiled, digest, None, {})
    report["modules"][label] = dict(wasm_sha256=digest, lifetime_source_sha256=sha(path.parent / "selfhost/checker_lifetimes.goose"))
    print("ready", label, flush=True)

def run():
    global scope, period
    for n in range(args.rounds):
        period = (1000000, 1300000, 1700000)[n % 3]
        for label in sorted(modules, reverse=bool(n % 2)):
            scope = {}
            data, prepared = modules[label]
            start = time.thread_time_ns()
            result = host.run_module(data, b"", prepared=prepared, arguments=["compiler", "selfhost/main.goose", "--stdlib", "stdlib", "--check"])
            cpu_ns = time.thread_time_ns() - start
            if result["exit_code"] or result["stderr"]:
                raise ValueError(result)
            row = dict(label=label, round=n + 1, period_ns=period, guest_wall_ns=result["timing"]["start_function_ns"], invocation_cpu_ns=cpu_ns)
            if args.mode != "counts":
                if result["stdout"] or not scope or not sum(scope["samples"][1:13]) or any(scope["samples"][13:]):
                    raise ValueError((label, result["stdout"], scope))
                if args.mode == "outer" and any(scope["samples"][2:]):
                    raise ValueError("outer control observed an inner phase")
                row.update(scope)
            else:
                row["counts"] = json.loads(result["stdout"].decode().removeprefix("MISS_COUNTS "))
            report["runs"].append(row)
            (args.stage / f"{args.mode}.json").write_text(json.dumps(report, indent=2) + "\n")
            print(label, n + 1, row.get("samples", row.get("counts")), flush=True)
threading.stack_size(HOSTED_STACK_BYTES + (64 << 20))
with ThreadPoolExecutor(1) as pool:
    pool.submit(run).result()
