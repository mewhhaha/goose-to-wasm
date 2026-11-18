"""Compare exclusive native and Wasmtime CPU samples on identical source input (Linux x86-64)."""
import argparse
from bisect import bisect_right
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import ctypes
import fcntl
from importlib.metadata import version
import json
import mmap
import os
from pathlib import Path
import struct
import subprocess
import sys
import threading
import time

root = Path(__file__).resolve().parents[5]
sys.path[:0] = [str(root / "scripts"), str(root / "bench"),
                str(root / "bench/results/2026-11-18/selfhost-wasm-runtime/tools")]
from measure import LIBC, PERF_EVENT_OPEN, PERF_ENABLE, PERF_DISABLE
from selfhost_comparison import identity, verify_frozen_source, SOURCE, WASM_FLAGS
from run_wasmtime import HOSTED_STACK_BYTES, PreparedModule, create_engine, create_hosted_config, run_module
import wasmtime
from wasmtime import _ffi

def sample(call, pid):
    attr = ctypes.create_string_buffer(128)
    # PERF_COUNT_SW_TASK_CLOCK, IP samples, disabled until enabled here, user mode.
    struct.pack_into("IIQQQQQ", attr, 0, 1, 128, 1, 2_000_000, 1, 0, 1 | 32 | 64)
    fd = LIBC.syscall(PERF_EVENT_OPEN, ctypes.byref(attr), pid, -1, -1, 0)
    if fd < 0:
        raise OSError(ctypes.get_errno(), "perf_event_open")
    try:
        with mmap.mmap(fd, 257 * mmap.PAGESIZE, flags=mmap.MAP_SHARED,
                       prot=mmap.PROT_READ | mmap.PROT_WRITE) as ring:
            fcntl.ioctl(fd, PERF_ENABLE)
            result = call()
            fcntl.ioctl(fd, PERF_DISABLE)
            head, tail, base, size = struct.unpack_from("QQQQ", ring, 1024)
            assert tail == 0 and head < size, "sampling ring overflow"
            ips = []
            while tail < head:
                kind, _, length = struct.unpack_from("IHH", ring, base + tail)
                assert length >= 8 and kind != 2, "invalid record or samples lost"
                if kind == 9:
                    ips.append(struct.unpack_from("Q", ring, base + tail + 8)[0])
                tail += length
            assert ips and tail == head
    finally:
        os.close(fd)
    return result, ips

def lookup(ips, symbols, relocation=0):
    symbols.sort()
    starts = [a for a, _, _ in symbols]
    counts = Counter()
    offsets = {}
    for ip in ips:
        pc = ip - relocation
        i = bisect_right(starts, pc) - 1
        if i >= 0 and pc < symbols[i][0] + symbols[i][1]:
            start, length, name = symbols[i]
            counts[name] += 1
            if a.pc_check and name.startswith("life_"):
                offsets.setdefault((name, length), Counter())[pc - start] += 1
        else:
            counts["[unmapped]"] += 1
    result = {"samples": len(ips), "counts": dict(counts.most_common())}
    if a.pc_check:
        result["sampled_offsets"] = [{"name": name, "length": length, "offsets": hits.most_common()}
                                      for (name, length), hits in sorted(offsets.items())]
    return result

def native(arguments):
    # Wait on a pipe so the sample window starts before exec of the compiler.
    with subprocess.Popen(["sh", "-c", 'read -r go && exec "$@"', "sh", binary, *arguments],
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as proc:
        def run():
            proc.stdin.write(b"go\n")
            proc.stdin.flush()
            for _ in range(1000):
                for line in Path(f"/proc/{proc.pid}/maps").read_text().splitlines():
                    parts = line.split()
                    if parts[-1] == str(binary) and int(parts[2], 16) == 0:
                        base = int(parts[0].split("-")[0], 16)
                        stdout, stderr = proc.communicate()
                        assert (proc.returncode, stdout, stderr) == (0, b"", b""), stderr
                        return base
                time.sleep(.001)
            raise RuntimeError("native image base unavailable")
        base, ips = sample(run, proc.pid)
    return lookup(ips, native_symbols, base)

def guest(arguments):
    result, ips = sample(lambda: run_module(data, b"", prepared=prepared, arguments=["compiler", *arguments]), 0)
    assert (result["exit_code"], result["stdout"], result["stderr"]) == (0, b"", ""), result
    row = lookup(ips, wasm_symbols)
    row["timing"] = result["timing"]
    return row

p = argparse.ArgumentParser(description=__doc__)
for field in ("compiler_stage", "workload_stage", "named_wasm", "output"):
    p.add_argument(field, type=lambda x: Path(x).resolve())
p.add_argument("--expected-emission", type=lambda x: Path(x).resolve(),
               help="output from the frozen native compiler when the backend changes module bytes")
p.add_argument("--cpu", type=int, default=7)
p.add_argument("--rounds", type=int, default=2)
p.add_argument("--pc-check", action="store_true", help="sample only checks and retain per-function instruction offsets")
a = p.parse_args()
built = json.loads((a.compiler_stage / "builds.json").read_text())
input_build = json.loads((a.workload_stage / "builds.json").read_text())
verify_frozen_source(a.compiler_stage / "source", built["source_commit"], built["source_archive_sha256"])
source = a.workload_stage / "source"
verify_frozen_source(source, input_build["source_commit"], input_build["source_archive_sha256"])
os.chdir(source)
native_dir = a.compiler_stage / "build-1"
binary = native_dir / "compiler-native"
wasm = native_dir / "compiler.wasm"
artifacts = built["samples"][0]["artifacts"]
assert identity(binary) == artifacts["compiler-native"] and identity(wasm) == artifacts["compiler.wasm"]
mapping = json.loads((native_dir / "build.json").read_text())
assert mapping["output_sha256"] == identity(binary)["sha256"]
names = {"g_fn" + str(n["id"]): n["name"] for n in mapping["backend_stats"]["function_names"]}
native_symbols = []
for line in subprocess.check_output(["nm", "-nS", binary], text=True).splitlines():
    parts = line.split()
    if len(parts) == 4 and parts[2] in ("T", "t"):
        addr, length, _, symbol = parts
        native_symbols.append((int(addr, 16), int(length, 16), names.get(symbol.partition(".")[0], symbol)))
data = a.named_wasm.read_bytes()
plain = wasm.read_bytes()
assert data.startswith(plain) and data[len(plain)] == 0
size, shift, at = 0, 0, len(plain) + 1
while True:
    byte = data[at]
    at += 1
    size |= (byte & 127) << shift
    if byte < 128:
        break
    shift += 7
assert at + size == len(data) and data[at:at+5] == b"\x04name"
cfg = create_hosted_config()
cfg.profiler = "perfmap"
cfg.cache = True
engine = create_engine(cfg)
prepared = PreparedModule(engine, wasmtime.Module(engine, data), identity(a.named_wasm)["sha256"], None, {})
maps = Path("/tmp") / f"perf-{os.getpid()}.map"
if not maps.exists():
    maps = Path(os.environ["TMPDIR"]) / maps.name
wasm_symbols = []
for line in maps.read_text().splitlines():
    addr, length, name = line.split(" ", 2)
    wasm_symbols.append((int(addr, 16), int(length, 16), name))
assert all(any(n == "life_replay" for _, _, n in sym) for sym in (native_symbols, wasm_symbols))
os.sched_setaffinity(0, {a.cpu})
threading.stack_size(HOSTED_STACK_BYTES + (64 << 20))
out = a.output.with_suffix(".wasm")
expected = input_build["samples"][0]["artifacts"]["compiler.wasm"]
if a.expected_emission:
    expected = identity(a.expected_emission)
report = dict(compiler=built["source_commit"], workload=input_build["source_commit"], workload_archive_sha256=input_build["source_archive_sha256"],
              native=identity(binary), wasm=identity(wasm), named=identity(a.named_wasm), wasmtime=version("wasmtime"),
              engine=identity(Path(_ffi.dll._name)), expected_emission=expected, cpu=a.cpu, interval_ns=2_000_000, runs=[])
with ThreadPoolExecutor(1) as worker:
    for n in range(a.rounds):
        order = ["wasmtime", "native"]
        if n % 2:
            order.reverse()
        modes = ["check", "emit"]
        if a.pc_check:
            modes = ["check"]
        for mode in modes:
            args = [*SOURCE, "--check"]
            if mode == "emit":
                args = [*SOURCE, *WASM_FLAGS, "-o", str(out)]
            for host in order:
                out.unlink(missing_ok=True)
                if host == "native":
                    row = native(args)
                else:
                    row = worker.submit(guest, args).result()
                if mode == "emit":
                    assert identity(out) == expected
                row.update(round=n+1, host=host, mode=mode)
                report["runs"].append(row)
                a.output.write_text(json.dumps(report, indent=2) + "\n")
                print(host, mode, row["samples"], list(row["counts"].items())[:5], flush=True)
maps.unlink()
