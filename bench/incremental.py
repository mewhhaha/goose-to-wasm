#!/usr/bin/env python3
"""Measure real edited-source builds through fresh and persistent native compilers.

Every edit runs the complete semantic frontend and emitter. The session retains
only the native process, compiler stack, and allocator; no AST or function body
reuse is claimed. Timed requests are verified against a fresh-process build.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
PHASES = ("parse_ns", "resolve_ns", "typecheck_ns", "optimize_ns", "bce_ns", "backend_ns")


def summary(samples: list[float]) -> dict:
    ordered = sorted(samples)
    median = statistics.median(samples)
    return {"samples_ms": samples, "median_ms": median, "min_ms": min(samples),
            "max_ms": max(samples), "mad_ms": statistics.median(abs(x - median) for x in samples),
            "p90_ms": ordered[min(len(ordered) - 1, int(len(ordered) * 0.9))]}


def program(delta: int, count: int, layout: str = "chain") -> str:
    lines = ["import std;", "extern fn bench_input() -> i64;"]
    if layout == "chain":
        lines += [f"fn step0(x: i64) -> i64 {{ return x + {delta}; }}"]
        lines += [f"fn step{i}(x: i64) -> i64 {{ return step{i-1}(x) * 3 + {i}; }}"
                  for i in range(1, count)]
        lines += [f"fn main() {{ print(step{count-1}(bench_input())); }}"]
    else:
        # Independent callees and a flat statement list scale the declaration
        # count without accidentally benchmarking maximum recursion depth.
        lines += [f"fn step{i}(x: i64) -> i64 {{ return x + {i} + {delta if i == 0 else 0}; }}"
                  for i in range(count)]
        lines += ["fn main() { let x = bench_input(); var total: i64 = 0;"]
        lines += [f"total += step{i}(x);" for i in range(count)]
        lines += ["print(total); }"]
    return "\n".join(lines) + "\n"


def expected(delta: int, count: int, value: int = 3, layout: str = "chain") -> str:
    if layout == "wide":
        return str(count * value + count * (count - 1) // 2 + delta) + "\n"
    value += delta
    for i in range(1, count):
        value = (value * 3 + i) & ((1 << 64) - 1)
        if value >= 1 << 63:
            value -= 1 << 64
    return str(value) + "\n"


def call(command: list[str], *, stdin: str | None = None) -> tuple[float, subprocess.CompletedProcess]:
    started = time.perf_counter_ns()
    process = subprocess.run(command, input=stdin, capture_output=True, text=True, check=False, timeout=120)
    elapsed = (time.perf_counter_ns() - started) / 1_000_000
    if process.returncode:
        raise RuntimeError(process.stderr + process.stdout)
    return elapsed, process


class Server:
    def __init__(self):
        self.process = subprocess.Popen([sys.executable, str(ROOT / "scripts" / "goose_wasm.py"), "serve"],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, text=True)
        self.serial = 0

    def request(self, arguments):
        self.serial += 1
        started = time.perf_counter_ns()
        self.process.stdin.write(json.dumps({"id": self.serial, "args": arguments}) + "\n")
        self.process.stdin.flush()
        response = self.process.stdout.readline()
        if not response:
            raise RuntimeError("build server exited before replying: " + self.process.stderr.read())
        result = json.loads(response)
        elapsed = (time.perf_counter_ns() - started) / 1_000_000
        if not result.get("ok") or result.get("id") != self.serial:
            raise RuntimeError(result)
        return elapsed, result["result"]

    def close(self):
        self.process.stdin.close()
        try:
            self.process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
            raise
        self.process.stdout.close()
        error = self.process.stderr.read()
        self.process.stderr.close()
        if self.process.returncode:
            raise RuntimeError(error)


def phase_medians(rows):
    return {key: statistics.median(row[key] / 1_000_000 for row in rows) for key in PHASES}


def measure(args, count: int, layout: str, optimization: str) -> dict:
    compiler = args.goose.resolve()
    report = {"source_functions": count, "layout": layout, "optimization": optimization,
              "measurements": {}, "edits": []}
    with tempfile.TemporaryDirectory(prefix="incremental-bench-", dir=ROOT / "build") as temporary:
        directory = Path(temporary)
        source, output = directory / "program.goose", directory / "program.wasm"
        stats = directory / "stats.json"
        initial = program(1, count, layout)
        source.write_text(initial)
        report["initial_source"] = initial
        raw = [str(compiler), str(source), "--target", "wasm-direct", optimization, "-o", str(output),
               "--wasm-stats", str(stats)]
        wrapper_args = ["build", str(source), "--goose", str(compiler), optimization, "-o", str(output),
                        "--cache-dir", str(directory / "cache"), "--json"]
        wrapper = [sys.executable, str(ROOT / "scripts" / "goose_wasm.py"), *wrapper_args]
        call(raw)
        samples, phases = [], []
        for _ in range(args.samples):
            elapsed, _ = call(raw)
            samples.append(elapsed)
            phases.append(json.loads(stats.read_text()))
        report["measurements"]["raw_compiler"] = summary(samples)
        report["raw_phase_medians_ms"] = phase_medians(phases)
        report["module_bytes"] = output.stat().st_size
        report["emitted_functions"] = phases[-1]["functions"]
        report["measurements"]["uncached_wrapper"] = summary(
            [call(wrapper + ["--no-cache", "--compiler-mode", "process"])[0] for _ in range(args.samples)])
        call(wrapper)
        samples = []
        for _ in range(args.samples):
            elapsed, result = call(wrapper)
            assert json.loads(result.stdout)["cache"] == "hit"
            samples.append(elapsed)
        report["measurements"]["unchanged_wrapper_cache"] = summary(samples)

        server = Server()
        try:
            modes = ("process", "session")
            commands = {mode: [*wrapper_args, "--compiler-mode", mode,
                               "--cache-dir", str(directory / ("cache-" + mode)),
                               "-o", str(directory / (mode + ".wasm"))] for mode in modes}
            # Warm both paths on the same initial input; these requests are not
            # samples. The session's native process genuinely exists afterward.
            for mode in modes:
                _, prime = server.request(commands[mode])
                assert prime["cache"] == "miss"
            session_pid = prime["native_session_pid"]
            samples = []
            for _ in range(args.samples):
                elapsed, result = server.request(commands["session"])
                assert result["cache"] == "hit"
                samples.append(elapsed)
            report["measurements"]["unchanged_persistent_server"] = summary(samples)
            timings = {mode: [] for mode in modes}
            phase_rows = {mode: [] for mode in modes}
            previous = {f["name"]: f["body_hash"] for f in phases[-1]["function_info"]}
            rng = random.Random(args.seed + count + int(optimization[-1]))
            for index in range(args.samples):
                delta = index + 2
                text = program(delta, count, layout)
                source.write_text(text)
                order = list(modes)
                rng.shuffle(order)
                edit = {"delta": delta, "source_sha256": hashlib.sha256(text.encode()).hexdigest(),
                        "execution_order": order, "modes": {}}
                for mode in order:
                    elapsed, result = server.request(commands[mode])
                    assert result["cache"] == "miss", "changed source unexpectedly hit a module cache"
                    assert result["full_frontend_ran"] and result["full_backend_ran"]
                    assert result["compiler_mode"] == mode
                    if mode == "session":
                        assert result["native_session_reused"] and result["native_session_pid"] == session_pid
                    timings[mode].append(elapsed)
                    phase_rows[mode].append(result["backend_stats"])
                    edit["modes"][mode] = {"wall_ms": elapsed, "driver": result}
                fresh, resident = directory / "process.wasm", directory / "session.wasm"
                assert fresh.read_bytes() == resident.read_bytes(), "session output differs from fresh native compilation"
                _, execution = call([args.node, str(ROOT / "scripts" / "run_wasm.mjs"), str(resident)], stdin="3\n")
                assert execution.stdout == expected(delta, count, layout=layout), execution.stdout
                current = {f["name"]: f["body_hash"] for f in phase_rows["session"][-1]["function_info"]}
                edit.update(unchanged_body_hashes=sum(previous.get(k) == v for k, v in current.items()),
                            changed_body_hashes=sum(previous.get(k) != v for k, v in current.items()),
                            fresh_process_bytes_match=True, output_verified=True,
                            full_frontend_ran=True, full_backend_ran=True)
                previous = current
                report["edits"].append(edit)
            report["measurements"]["single_function_edit_process_server"] = summary(timings["process"])
            report["measurements"]["single_function_edit_server"] = summary(timings["session"])
            report["edited_phase_medians_ms"] = {mode: phase_medians(phase_rows[mode]) for mode in modes}
            report["last_edit_output_verified"] = True
            report["every_edit_output_verified"] = True
            report["every_edit_matches_fresh_process"] = True
            report["final_source"] = text
        finally:
            server.close()
    return report


def render(report):
    lines = ["# Edited-source compilation measurements", "", report["policy"], "",
             "All timings below are request/process wall milliseconds (median ± MAD). "
             "Every edited build is a cache miss and is checked against fresh compiler bytes and executed.", "",
             "| Shape | Functions | Optimization | Raw compiler | Uncached wrapper | "
             "Unchanged server | Edit, fresh native process | Edit, resident native process |",
             "|---|---:|---|---:|---:|---:|---:|---:|"]
    for row in report["workloads"]:
        values = []
        for key in ("raw_compiler", "uncached_wrapper", "unchanged_persistent_server",
                    "single_function_edit_process_server", "single_function_edit_server"):
            metric = row["measurements"][key]
            values.append(f"{metric['median_ms']:.3f} ± {metric['mad_ms']:.3f}")
        lines.append(f"| {row['layout']} | {row['source_functions']} | {row['optimization']} | " + " | ".join(values) + " |")
    lines += ["", f"Samples per cell: {report['samples']}. Raw values, frontend phase times, source text, "
              "execution order, compiler/driver hashes, and every edit's validation are in the JSON report.", "",
              "The resident process does not retain parsed/typed ASTs or skip function emission. "
              "The separate unchanged-cache result must not be described as edited-source compile time.", ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=ROOT / "build" / "bin" / "goose")
    parser.add_argument("--node", default="node")
    parser.add_argument("--machine-label")
    parser.add_argument("--samples", type=int, default=15)
    parser.add_argument("--functions", type=int, default=32, help="single workload; retains the original 32-function chain by default")
    parser.add_argument("--sizes", type=int, nargs="+", help="scaling workloads, e.g. --sizes 32 512 2048 (uses wide shape)")
    parser.add_argument("--levels", choices=("O0", "O1", "O2"), nargs="+", default=["O0"])
    parser.add_argument("--layout", choices=("chain", "wide"), default="chain")
    parser.add_argument("--seed", type=int, default=20261026)
    parser.add_argument("--output", type=Path, default=ROOT / "build" / "incremental-benchmark.json")
    args = parser.parse_args()
    sizes = args.sizes or [args.functions]
    layout = "wide" if args.sizes else args.layout
    if args.samples < 3 or any(n < 2 or n > 4096 for n in sizes) or layout == "chain" and max(sizes) > 128:
        parser.error("use at least 3 samples, 2..4096 wide functions, or 2..128 chain functions")
    (ROOT / "build").mkdir(exist_ok=True)
    paths = [Path(__file__).resolve(), ROOT / "scripts" / "goose_wasm.py", ROOT / "scripts" / "build_support.py",
             ROOT / "compiler" / "compiler_session.h", ROOT / "patches" / "direct-target.patch"]
    report = {"schema": "goose-incremental-benchmark-v2", "status": "incomplete", "python": platform.python_version(),
              "started_utc": datetime.now(timezone.utc).isoformat(), "samples": args.samples, "seed": args.seed,
              "platform": platform.platform(), "machine": platform.machine(), "cpu_count": os.cpu_count(),
              "supplied_machine_label": args.machine_label,
              "compiler_sha256": hashlib.sha256(args.goose.read_bytes()).hexdigest(),
              "input_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},
              "policy": "Actual edits run the full frontend and emitter. Native session reuse removes process/thread "
                        "startup and retains allocator state; it does not reuse semantic analysis or function bodies.",
              "notes": ["Warm cache and worker samples exclude initial warming requests.",
                        "Raw compiler includes native process startup and module output.",
                        "Wrapper samples include Python process startup and transactional output handling.",
                        "Server samples include JSON request/response, content validation, and publication.",
                        "Fresh/resident edit modes are deterministically shuffled within each paired edit.",
                        "Both modes use the same source file and separate caches; every real edit misses both caches.",
                        "Byte comparison and program execution run outside each timed build interval."],
              "workloads": []}
    _, node_version = call([args.node, "-p", "JSON.stringify({node:process.versions.node,v8:process.versions.v8})"])
    report["validation_engine"] = json.loads(node_version.stdout)
    report["toolchain_pin"] = json.loads((ROOT / "toolchain.json").read_text())
    for identity_path in (args.goose.resolve().parent / "toolchain.json",
                          args.goose.resolve().parent.parent / "toolchain.json"):
        if identity_path.is_file():
            identity = json.loads(identity_path.read_text())
            if identity.get("compiler_sha256") == report["compiler_sha256"]:
                report["compiler_build_identity"] = identity
                break
    args.output.parent.mkdir(parents=True, exist_ok=True)
    def checkpoint():
        args.output.write_text(json.dumps(report, indent=2) + "\n")
        args.output.with_suffix(".md").write_text(render(report))
    try:
        for count in sizes:
            for level in args.levels:
                result = measure(args, count, layout, "-" + level)
                report["workloads"].append(result)
                checkpoint()
                for name, row in result["measurements"].items():
                    print(f"{layout}/{count}/{level} {name}: median {row['median_ms']:.3f} ms, MAD {row['mad_ms']:.3f} ms", flush=True)
        report["source_hashes_still_match"] = all(hashlib.sha256((ROOT / p).read_bytes()).hexdigest() == h
                                                  for p, h in report["input_sha256"].items())
        report["compiler_hash_still_matches"] = hashlib.sha256(args.goose.read_bytes()).hexdigest() == report["compiler_sha256"]
        assert report["source_hashes_still_match"] and report["compiler_hash_still_matches"], "measurement inputs changed"
        report["status"] = "passed"
    finally:
        report["finished_utc"] = datetime.now(timezone.utc).isoformat()
        checkpoint()
    print(f"Report: {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
