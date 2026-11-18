"""Sample the release code under Wasmtime and aggregate CPU samples by Wasm function."""
from bisect import bisect_right
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import sys
import threading

root = Path(__file__).resolve().parents[5]
stage = root / "build/one-x-binaryen"
sys.path.insert(0, str(root / "scripts"))
sys.path.insert(0, str(root / "bench/results/2026-11-18/selfhost-wasm-runtime/tools"))
from sample import sample, INTERVAL_NS
from measure import HOSTED_STACK_BYTES, PreparedModule, create_engine, create_hosted_config, run_module, sha256, wasmtime

def uleb(buf, pos):
    value, shift = 0, 0
    while True:
        byte = buf[pos]
        pos += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, pos
        shift += 7

data = (stage / "named32.wasm").read_bytes()
plain = (root / "build/lifetime-exit-index-2026-11-18/candidate32.wasm").read_bytes()
assert data.startswith(plain)
pos = len(plain)
assert data[pos] == 0
length, pos = uleb(data, pos + 1)
assert pos + length == len(data) and data[pos:pos+5] == b"\x04name"
os.chdir(root / "build/wasm-copy-2026-11-18/selfhost-chart/source")
os.sched_setaffinity(0, {7})
conf = create_hosted_config()
conf.profiler = "perfmap"
engine = create_engine(conf)
digest = sha256(data)
module = PreparedModule(engine, wasmtime.Module(engine, data), digest, None, {})
threading.stack_size(HOSTED_STACK_BYTES + (64 << 20))
results = {"named_module_sha256": digest, "release_module_sha256": sha256(plain), "name_section_only": True,
           "cpu": 7, "sample_interval_ns": INTERVAL_NS, "workloads": {}}
with ThreadPoolExecutor(1) as pool:
    for mode in ("check", "emit"):
        args = ["compiler", "selfhost/main.goose", "--stdlib", "stdlib"]
        out = stage / "profile-emitted.wasm"
        if mode == "check":
            args += ["--check"]
        else:
            out.unlink(missing_ok=True)
            args += ["--target", "wasm-direct", "-O2", "--wasm-memory64", "--wasm-max-pages", "262144", "-o", str(out)]
        result, ips, lost = pool.submit(sample, lambda: run_module(data, b"", prepared=module, arguments=args)).result()
        assert (result["exit_code"],result["stdout"], result["stderr"]) == (0, b"", ""), result
        assert not lost
        if mode == "emit":
            assert sha256(out.read_bytes()) == "31783c320929638535d7c50da591954cdf1eebf3af83f2d1f5c3ab5a7089e468"
        maps = Path("/tmp") / f"perf-{os.getpid()}.map"
        if not maps.exists():
            maps = Path(os.environ["TMPDIR"]) / maps.name
        entries = []
        for line in maps.read_text().splitlines():
            addr, size, label = line.split(" ", 2)
            entries.append((int(addr, 16), int(size, 16), label))
        entries.sort()
        starts = [r[0] for r in entries]
        counts = Counter()
        for ip in ips:
            index = bisect_right(starts, ip) - 1
            if index < 0 or ip >= starts[index] + entries[index][1]:
                counts["[outside mapped functions]"] += 1
            else:
                counts[entries[index][2]] += 1
        results["workloads"][mode] = {"samples": len(ips), "lost": lost, "counts": dict(counts.most_common())}
        (stage / "profile.json").write_text(json.dumps(results, indent=2) + "\n")
        print(mode, len(ips), counts.most_common(8), flush=True)
maps.unlink()
