#!/usr/bin/env python3
"""Separate Goose and GCC optimization of the existing Fibonacci workload.

This is a diagnostic experiment, separate from the LangArena gauntlet. It
retains emitted C, compiler optimization reports, checksums, and raw samples.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
from functools import lru_cache
import hashlib
import json
from pathlib import Path
import platform
import random
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
    result = subprocess.run(list(map(str, command)), capture_output=True, text=True, check=False, **kwargs)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result


def kernel(text: str) -> str:
    start = text.rfind("static int64_t kernel_g(int64_t n_g) {")
    if start < 0:
        raise RuntimeError("cannot identify emitted Fibonacci kernel")
    end = text.index("\n}\n", start) + 3
    return text[start:end]


def summary(values: list[float]) -> dict:
    median = statistics.median(values)
    return {"samples_ms": values, "median_ms": median,
            "mad_ms": statistics.median(abs(x - median) for x in values)}


def fibonacci(n: int) -> int:
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a


@lru_cache(None)
def naive_calls(n: int) -> int:
    return 1 if n < 2 else 1 + naive_calls(n - 1) + naive_calls(n - 2)


@lru_cache(None)
def basecase_calls(n: int) -> int:
    if n < 2:
        return 1
    return 1 + sum(basecase_calls(k) for k in (n - 1, n - 2) if k >= 2)


@lru_cache(None)
def retained_assembly_calls(n: int) -> int:
    """Model the exact previously retained GCC13.3 assembly, not new timing.

    Base cases0..4 return without a child call. Case5 calls F(2); case6
    calls F(3),F(2),F(2). The generic path calls n-3,n-4,n-5 and loops
    on n-4, so the loop removes the fourth invocation's own entry count.
    """
    if n <= 4:
        return 1
    if n == 5:
        return 2
    if n == 6:
        return 4
    return (retained_assembly_calls(n - 3) + 2 * retained_assembly_calls(n - 4)
            + retained_assembly_calls(n - 5))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=ROOT / "build/bin/goose")
    parser.add_argument("--cc", default="gcc")
    parser.add_argument("--input", type=int, default=35)
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--machine-label")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/fibonacci-diagnostic")
    args = parser.parse_args()
    if not 2 <= args.input <= 40 or args.samples < 3:
        parser.error("use input2..40 and at least3samples")
    out = args.output_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    source = ROOT / "bench/fixtures/recursive_fibonacci.goose"
    host = ROOT / "bench/host_input.c"
    report = {"schema": "goose-fibonacci-diagnostic-v1", "started_utc": datetime.now(timezone.utc).isoformat(),
              "platform": platform.platform(), "supplied_machine_label": args.machine_label,
              "compiler_sha256": digest(args.goose), "source_sha256": digest(source),
              "host_sha256": digest(host), "harness_sha256": digest(Path(__file__)),
              "cc": run([args.cc, "--version"]).stdout.strip(), "input": args.input,
              "samples_per_cell": args.samples, "rows": [], "commands": [],
              "notes": ["All cells use the same opaque runtime input and sink; host shim is always GCC-O2.",
                        "Two in-process warmup calculations precede each timed call.",
                        "These small timed regions diagnose optimization effects, not universal native/Wasm speed.",
                        "Derived activation counts model the retained baseline assembly, not instrumented executions."]}
    def command(values):
        report["commands"].append(list(map(str, values)))
        return run(values)
    command([args.cc, "-O2", "-c", host, "-o", out / "host.o"])
    cells = []
    for frontend in ("O0", "O2"):
        cfile = out / ("goose-" + frontend + ".c")
        process = command([args.goose.resolve(), source, "--target", "native", "--standalone",
                           "-" + frontend, "-o", cfile])
        (out / ("goose-" + frontend + ".log")).write_text(process.stdout + process.stderr)
        (out / ("goose-" + frontend + ".kernel.c")).write_text(kernel(cfile.read_text()))
        for copt in ("O0", "O2"):
            label = frontend + "-" + copt
            inline, optimized = out / (label + ".inline.txt"), out / (label + ".optimized.txt")
            inline.unlink(missing_ok=True)
            object_file, binary = out / (label + ".o"), out / label
            command([args.cc, "-" + copt, "-fno-strict-aliasing", "-ffp-contract=off", "-c", cfile,
                     "-o", object_file, "-fopt-info-inline=" + str(inline),
                     "-fdump-tree-optimized=" + str(optimized)])
            command([args.cc, object_file, out / "host.o", "-lm", "-pthread", "-ldl", "-o", binary])
            text = optimized.read_text()
            start = text.find(";; Function kernel_g")
            if start >= 0:
                end = text.find(";; Function ", start + 12)
                (out / (label + ".kernel.gimple.txt")).write_text(text[start:end if end >= 0 else None])
            (out / (label + ".disassembly.txt")).write_text(command(["objdump", "-d", "--disassemble=kernel_g", binary]).stdout)
            cells.append({"goose_optimization": frontend, "gcc_optimization": copt, "label": label,
                          "binary": str(binary), "binary_sha256": digest(binary), "c_sha256": digest(cfile),
                          "samples": []})
    expected = fibonacci(args.input)
    if not args.build_only:
        tasks = [cell for _ in range(args.samples) for cell in cells]
        random.Random(87123).shuffle(tasks)
        for cell in tasks:
            process = run([cell["binary"]], input=f"{args.input} 2\n")
            fields = process.stdout.splitlines()
            if len(fields) != 2 or int(fields[0]) != expected or int(fields[1]) <= 0:
                raise RuntimeError("invalid Fibonacci observation: " + process.stdout)
            cell["samples"].append(int(fields[1]) / 1_000_000)
        for cell in cells:
            cell["timing"] = summary(cell.pop("samples"))
            cell["verified_checksum"] = expected
            print(f"{cell['label']}: {cell['timing']['median_ms']:.3f} ms", flush=True)
    report["rows"] = cells
    report["derived_activation_counts"] = {
        "input": args.input, "naive": naive_calls(args.input),
        "basecase_inlining_only": basecase_calls(args.input),
        "retained_native_assembly_model": retained_assembly_calls(args.input),
        "retained_assembly_source": "bench/results/2026-10-26/native-fibonacci-disassembly.txt"}
    report["finished_utc"] = datetime.now(timezone.utc).isoformat()
    report["status"] = "built-only" if args.build_only else "passed"
    (out / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
