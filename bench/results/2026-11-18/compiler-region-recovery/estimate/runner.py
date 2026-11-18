"""Run the pinned compiler using one cached executable, sizing two regions before _start."""

import hashlib
import json
import os
import re
from pathlib import Path
import struct
import sys
import time

HERE = Path(__file__).resolve().parent
REPO = Path(os.environ["ESTIMATE_REPO"])
sys.path.insert(0, str(REPO / "bench/results/2026-11-18/compiler-layout-trials/memory"))
from diagnose import leb, region_table

SHA = "7eb18697c0bd5c1737e48c7a190d7f6321c74a291b26e49113eab0ae7a7acb68"


def inspect_module(data):
    if hashlib.sha256(data).hexdigest() != SHA:
        raise ValueError("unknown compiler layout")
    width, span, bounds = region_table(data)
    assert width == 4
    pos = 8
    while pos < len(data):
        size, start = leb(data, pos + 1)
        if data[pos] == 6:
            count, i = leb(data, start)
            for _ in range(10):
                value, i = leb(data, i + 3)
                i += 1
            return value, bounds
        pos = start + size
    raise ValueError("missing globals")


def inventory(entry, stdlib):
    # No imports can occur without the literal ASCII keyword anywhere in the entry.
    # Otherwise count every Goose file in both declared roots. A string or comment
    # containing the keyword can trigger an unnecessarily broad scan.
    source = entry.read_bytes()
    if b"import" not in source:
        return {str(entry.resolve()): len(source)}
    files = {}
    for root in (entry.parent, stdlib):
        for p in root.rglob("*.goose"):
            files[str(p.resolve())] = p.stat().st_size
    return files


def distribute(total, weights):
    # Cumulative rounding keeps 8-byte alignment and spends exactly 'total'.
    parts = []
    cumsum = previous = 0
    weight = sum(weights)
    for w in weights:
        cumsum += w
        position = (total // 8 * cumsum // weight) * 8
        parts.append(position - previous)
        previous = position
    return parts


# Three stratified 4 KiB windows per file; delimiters and operators each count
# as a lexeme. Comments and strings can overestimate, nonrepresentative windows
# can underestimate. Slabs are deliberately counted without running a compiler.
LEXEME = re.compile(rb"[A-Za-z_][A-Za-z_0-9]*|[0-9]+|[^\s]")


def sample_lexemes(files):
    estimated = 0
    sampled = 0
    for path, size in files.items():
        if not size:
            continue
        with open(path, "rb") as f:
            chunks = []
            if size <= 12288:
                chunks.append(f.read())
            else:
                for at in (0, (size - 4096) // 2, size - 4096):
                    f.seek(at)
                    chunks.append(f.read(4096))
        count = sum(sum(1 for _ in LEXEME.finditer(b)) for b in chunks)
        read = sum(len(b) for b in chunks)
        sampled += read
        estimated += (count * size + read - 1) // read
    return estimated, sampled


def layout(bounds, required):
    sizes = [b - a for a, b in zip(bounds, bounds[1:])]
    # Cap tokens and AST together at half of the available bytes. These are limits
    # on fixed regions, not heap reservations. Other owners retain their relative share.
    budget = sum(sizes)
    semantic = [6, 7]
    requests = [
        max(sizes[i], ((n + 12 + 7) // 8) * 8) for i, n in zip(semantic, required)
    ]
    if sum(requests) > budget // 2:
        requests = distribute((budget // 16) * 8, requests)
    if all(request == sizes[i] for i, request in zip(semantic, requests)):
        return bounds
    donors = [i for i in range(len(sizes)) if i not in semantic]
    new_sizes = sizes[:]
    for i, size in zip(semantic, requests):
        new_sizes[i] = size
    for i, size in zip(
        donors, distribute(budget - sum(requests), [sizes[i] for i in donors])
    ):
        new_sizes[i] = size
    result = [bounds[0]]
    for size in new_sizes:
        assert size >= 16 and size % 8 == 0
        result.append(result[-1] + size)
    assert result[-1] == bounds[-1]
    return result


observed = {}
report = {}


def record_read(path, data):
    observed[str(path.resolve())] = len(data)
    return data


def configure(data, store, exports, arguments):
    if os.environ["POLICY"] == "baseline":
        return
    start = time.perf_counter_ns()
    addr, bounds = inspect_module(data)
    t = time.perf_counter_ns()
    entry = Path(os.fsdecode(arguments[1]))
    stdlib = Path(os.fsdecode(arguments[arguments.index("--stdlib") + 1]))
    predicted = inventory(entry, stdlib)
    byte_count = sum(predicted.values())
    ratios = json.loads(os.environ["RATIOS"])
    required = [byte_count * r for r in ratios]
    if (
        os.environ["POLICY"] == "sampled"
        and byte_count * 88 > bounds[7] - bounds[6] - 12
    ):
        lexemes, sampled_bytes = sample_lexemes(predicted)
        # Frozen compiler records have 88-byte tokens and 160-byte AST nodes.
        # Model one of each per estimated lexeme with 25% sampling headroom.
        padded = (lexemes * 5 + 3) // 4
        required = [max(required[0], padded * 88), max(required[1], padded * 160)]
        report.update(estimated_lexemes=lexemes, sampled_bytes=sampled_bytes)
    new_bounds = layout(bounds, required)
    packed = struct.pack("<" + "I" * len(bounds), *bounds)
    mem = exports["memory"]
    assert bytes(mem.read(store, addr, addr + len(packed))) == packed
    mem.write(store, struct.pack("<" + "I" * len(bounds), *new_bounds), addr)
    report.update(
        full_sizing_ns=time.perf_counter_ns() - start,
        inventory_ns=time.perf_counter_ns() - t,
        input_bytes=byte_count,
        count=len(predicted),
        predicted=predicted,
        changed=new_bounds != bounds,
        rooms=[new_bounds[i + 1] - new_bounds[i] - 12 for i in (6, 7)],
    )


def main():
    import atexit

    def finish():
        predicted = report.pop("predicted", {})
        report.update(
            read_files=len(observed),
            read_bytes=sum(observed.values()),
            missed_goose_bytes=sum(
                n
                for p, n in observed.items()
                if p.endswith(".goose") and p not in predicted
            ),
            excess_bytes=sum(n for p, n in predicted.items() if p not in observed),
            missed_bytes=sum(n for p, n in observed.items() if p not in predicted),
        )
        Path(os.environ["SIZING_JSON"]).write_text(json.dumps(report, indent=2) + "\n")

    atexit.register(finish)
    source = Path(os.environ["ESTIMATE_FROZEN_HOST"]).read_text()
    before = '        instantiated = time.perf_counter_ns()\n        exports["_start"](store)'
    assert source.count(before) == 1
    source = source.replace(
        before, "        configure(data, store, exports, arguments)\n" + before
    )
    before = "append_bytes(caller, control, Path(os.fsdecode(path)).read_bytes())"
    assert source.count(before) == 1
    source = source.replace(
        before,
        "p = Path(os.fsdecode(path))\n            append_bytes(caller, control, record_read(p,p.read_bytes()))",
    )
    ns = dict(
        configure=configure,
        record_read=record_read,
        __name__="experiment_host",
        __file__=str(REPO / "scripts/run_wasmtime.py"),
    )
    exec(compile(source, ns["__file__"], "exec"), ns)
    return ns["main"]()


if __name__ == "__main__":
    sys.exit(main())
