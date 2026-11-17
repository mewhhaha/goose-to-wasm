"""Record Wasmtime worker CPU instruction pointers with Linux task-clock."""
from bisect import bisect_right
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from ctypes import byref, create_string_buffer, get_errno, string_at
import fcntl
import json
import mmap
import os
from pathlib import Path
import struct
import threading

from measure import (
    ARTIFACT, BASE, HERE, HOSTED_STACK_BYTES, LIBC, PERF_DISABLE, PERF_ENABLE,
    PERF_EVENT_OPEN, SOURCE, PreparedModule, create_engine, create_hosted_config, run_module, sha256, wasmtime,
)

INTERVAL_NS = 2_000_000


def sample(call):
    attr = create_string_buffer(128)
    # Software task-clock, sample IP, disabled until entry, user space.
    struct.pack_into("IIQQQQQ", attr, 0, 1, 128, 1, INTERVAL_NS, 1, 0, 1 | 32 | 64)
    fd = LIBC.syscall(PERF_EVENT_OPEN, byref(attr), 0, -1, -1, 0)
    if fd < 0:
        raise OSError(get_errno(), "perf_event_open")
    try:
        with mmap.mmap(fd, 129 * mmap.PAGESIZE, flags=mmap.MAP_SHARED,
                       prot=mmap.PROT_READ | mmap.PROT_WRITE) as queue:
            fcntl.ioctl(fd, PERF_ENABLE)
            result = call()
            fcntl.ioctl(fd, PERF_DISABLE)
            head, _, base, size = struct.unpack_from("QQQQ", queue, 1024)
            if head >= size:
                raise ValueError("sampling buffer filled")
            pos, ips, lost = 0, [], 0
            while pos < head:
                event, _, record = struct.unpack_from("IHH", queue, base + pos)
                if record <= 0:
                    raise ValueError("invalid sample record size")
                if event == 9:  # PERF_RECORD_SAMPLE
                    ips.append(struct.unpack_from("Q", queue, base + pos + 8)[0])
                if event == 2:  # PERF_RECORD_LOST
                    lost += struct.unpack_from("Q", queue, base + pos + 16)[0]
                pos += record
    finally:
        os.close(fd)
    return result, ips, lost


def main():
    os.chdir(BASE / "source")
    os.sched_setaffinity(0, {7})
    config = create_hosted_config()
    config.profiler = "perfmap"
    engine = create_engine(config)
    data = ARTIFACT.read_bytes()
    module = wasmtime.Module(engine, data)
    sha = sha256(data)
    prepared = PreparedModule(engine, module, sha, None, {})

    def check():
        return run_module(data, b"", prepared=prepared, arguments=[str(ARTIFACT), *SOURCE, "--check"])

    threading.stack_size(HOSTED_STACK_BYTES + (64 << 20))
    with ThreadPoolExecutor(1) as pool:
        result, ips, lost = pool.submit(sample, check).result()
    if (result["exit_code"], result["stdout"], result["stderr"]) != (0, b"", ""):
        raise RuntimeError(result)
    mapname = f"perf-{os.getpid()}.map"
    path = Path("/tmp") / mapname
    if not path.is_file():
        path = Path(os.environ["TMPDIR"]) / mapname
    entries = []
    for line in path.read_text().splitlines():
        address, size, label = line.split(" ", 2)
        entries.append((int(address, 16), int(size, 16), label))
    entries.sort()
    addresses = [entry[0] for entry in entries]
    counts = Counter()
    offsets = {}
    for ip in ips:
        index = bisect_right(addresses, ip) - 1
        if index < 0 or ip >= entries[index][0] + entries[index][1]:
            counts["[host]"] += 1
            continue
        address, _, name = entries[index]
        counts[name] += 1
        offsets.setdefault(index, Counter())[ip - address] += 1
    heads = {}
    for index in sorted(offsets, key=lambda k: sum(offsets[k].values()), reverse=True)[:8]:
        address, length, name = entries[index]
        heads[name] = {"length": length, "offsets": dict(offsets[index].most_common())}
        (HERE / f"clif-hot-{index}.bin").write_bytes(string_at(address, length))
    report = {"module_sha256": sha, "cpu": 7, "interval_ns": INTERVAL_NS, "lost": lost,
              "samples": len(ips), "timing": result["timing"], "counts": dict(counts.most_common()),
              "hot_functions": heads}
    (HERE / "wasmtime-check-profile.json").write_text(json.dumps(report, indent=2) + "\n")
    print(report["samples"], report["lost"], report["timing"], counts.most_common(12))
    path.unlink()


if __name__ == "__main__":
    main()
