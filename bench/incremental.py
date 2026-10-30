#!/usr/bin/env python3
"""Measure compile/rebuild paths without conflating caching and incremental analysis.

Edits recheck callers and run the backend again. Optional caches skip parsing
unchanged modules or checking closed scalar leaves. Function fingerprints expose future reuse
opportunities but are not counted as cached function compilation work.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]


def summary(samples: list[float]) -> dict:
    ordered = sorted(samples)
    median = statistics.median(samples)
    return {"samples_ms": samples, "median_ms": median, "min_ms": min(samples),
            "max_ms": max(samples), "mad_ms": statistics.median(abs(x - median) for x in samples),
            "p90_ms": ordered[min(len(ordered) - 1, int(len(ordered) * 0.9))]}


def program(delta: int, count: int, shape: str = "chain") -> str:
    lines = ["import std;", *(["import helpers;"] if shape == "leaves" else []), "extern fn bench_input() -> i64;",
             f"fn step0(x: i64) -> i64 {{ return x + {delta}; }}"]
    if shape == "leaves":
        total = " + ".join(f"helpers::leaf{i}(x)" for i in range(count))
        return "\n".join([*lines, f"fn main() {{ let x = bench_input(); print(step0(x) + {total}); }}"]) + "\n"
    lines += [f"fn step{i}(x: i64) -> i64 {{ return step{i-1}(x) * 3 + {i}; }}"
              for i in range(1, count)]
    lines += [f"fn main() {{ print(step{count-1}(bench_input())); }}"]
    return "\n".join(lines) + "\n"


def expected(delta: int, count: int, value: int = 3, shape: str = "chain") -> str:
    if shape == "leaves":
        return str(value + delta + sum(((value * 3 + i) ^ (value << 1)) + ((value * 5 - i) & 255)
                                      for i in range(count))) + "\n"
    value += delta
    for i in range(1, count):
        value = (value * 3 + i) & ((1 << 64) - 1)
        if value >= 1 << 63:
            value -= 1 << 64
    return str(value) + "\n"


def call(command: list[str]) -> tuple[float, subprocess.CompletedProcess]:
    started = time.perf_counter_ns()
    process = subprocess.run(command, capture_output=True, text=True, check=False)
    elapsed = (time.perf_counter_ns() - started) / 1_000_000
    if process.returncode:
        raise RuntimeError(process.stderr + process.stdout)
    return elapsed, process


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=ROOT / "build" / "bin" / "goose")
    parser.add_argument("--node", default="node")
    parser.add_argument("--machine-label", help="independently observed hardware description")
    parser.add_argument("--samples", type=int, default=15)
    parser.add_argument("--functions", type=int, default=32)
    parser.add_argument("--optimization", choices=("O0", "O1", "O2"), default="O0")
    parser.add_argument("--shape", choices=("chain", "leaves"), default="chain",
                        help="a call chain, or independent scalar leaves in an unchanged helper module")
    parser.add_argument("--output", type=Path, default=ROOT / "build" / "incremental-benchmark.json")
    parser.add_argument("--native-worker", action="store_true", help="retain the native compiler in the server")
    parser.add_argument("--lexical-cache", action="store_true", help="reuse unchanged source tokens in the worker")
    parser.add_argument("--syntax-cache", action="store_true", help="reuse parsed modules in the worker")
    parser.add_argument("--checked-leaf-cache", action="store_true", help="reuse checked closed scalar leaves in the worker")
    args = parser.parse_args()
    if (args.lexical_cache or args.syntax_cache or args.checked_leaf_cache) and not args.native_worker:
        parser.error("--lexical-cache, --syntax-cache and --checked-leaf-cache require --native-worker")
    if args.samples < 3 or args.functions < 2 or args.functions > 128:
        parser.error("use at least three samples and 2..128 functions")
    compiler = args.goose.resolve()
    optimization = "-" + args.optimization
    (ROOT / "build").mkdir(exist_ok=True)
    report = {"schema": "goose-incremental-benchmark-v1", "python": platform.python_version(),
              "started_utc": datetime.now(timezone.utc).isoformat(),
              "platform": platform.platform(), "machine": platform.machine(), "cpu_count": os.cpu_count(),
              "supplied_machine_label": args.machine_label,
              "compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
              "input_sha256": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                               for path in (Path(__file__).resolve(), ROOT / "scripts" / "goose_wasm.py")},
              "optimization": optimization, "source_functions": args.functions + (args.shape == "leaves"),
              "shape": args.shape, "generated_leaf_functions": args.functions if args.shape == "leaves" else 0,
              "native_worker": args.native_worker,
              "lexical_cache": args.lexical_cache,
              "syntax_cache": args.syntax_cache,
              "checked_leaf_cache": args.checked_leaf_cache,
              "policy": "content-checked module cache; edits recheck callers; optional checked scalar leaves; full backend",
              "notes": ["Warm cache samples exclude the first warming request.",
                        "Raw compiler includes native process startup and module output.",
                        "Wrapper samples include Python process startup, dependency checks and output handling.",
                        "Server samples include JSON request/response round-trip and content validation.",
                        "Bytecode hashes describe unchanged functions; no function emission is skipped yet."],
              "measurements": {}}
    with tempfile.TemporaryDirectory(prefix="incremental-bench-", dir=ROOT / "build") as temporary:
        directory = Path(temporary)
        source, output = directory / "program.goose", directory / "program.wasm"
        stats = directory / "stats.json"
        if args.shape == "leaves":
            helpers = ["namespace helpers;"] + [
                f"fn leaf{i}(x: i64) -> i64 {{ ((x * 3 + {i}) ^ (x << 1)) + ((x * 5 - {i}) & 255) }}"
                for i in range(args.functions)]
            (directory / "helpers.goose").write_text("\n".join(helpers) + "\n")
        source.write_text(program(1, args.functions, args.shape))
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
        report["raw_phase_medians_ms"] = {
            key: statistics.median(row[key] / 1_000_000 for row in phases)
            for key in ("parse_ns", "resolve_ns", "typecheck_ns", "optimize_ns", "bce_ns", "backend_ns")
        }
        report["module_bytes"] = output.stat().st_size
        report["emitted_functions"] = phases[-1]["functions"]
        samples = [call(wrapper + ["--no-cache"])[0] for _ in range(args.samples)]
        report["measurements"]["uncached_wrapper"] = summary(samples)
        call(wrapper)
        samples = []
        for _ in range(args.samples):
            elapsed, result = call(wrapper)
            assert json.loads(result.stdout)["cache"] == "hit"
            samples.append(elapsed)
        report["measurements"]["unchanged_wrapper_cache"] = summary(samples)

        server = subprocess.Popen([sys.executable, str(ROOT / "scripts" / "goose_wasm.py"), "serve",
                                   *(["--native-worker"] if args.native_worker else []),
                                   *(["--lexical-cache"] if args.lexical_cache else []),
                                   *(["--syntax-cache"] if args.syntax_cache else []),
                                   *(["--checked-leaf-cache"] if args.checked_leaf_cache else [])],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            serial = 0
            def request(extra=()):
                nonlocal serial
                serial += 1
                started = time.perf_counter_ns()
                server.stdin.write(json.dumps({"id": serial, "args": [*wrapper_args, *extra]}) + "\n")
                server.stdin.flush()
                result = json.loads(server.stdout.readline())
                elapsed = (time.perf_counter_ns() - started) / 1_000_000
                if not result.get("ok"):
                    raise RuntimeError(result)
                return elapsed, result["result"]
            if args.native_worker:
                first_ms, first = request(["--no-cache"])
                assert not first["compiler_process_reused"]
                report["native_worker_first_uncached_request_ms"] = first_ms
            request()
            samples = []
            for _ in range(args.samples):
                elapsed, result = request()
                assert result["cache"] == "hit"
                samples.append(elapsed)
            report["measurements"]["unchanged_persistent_server"] = summary(samples)
            samples, edits = [], []
            previous = {f["name"]: f["body_hash"] for f in phases[-1]["function_info"]}
            for index in range(args.samples):
                delta = index + 2
                source.write_text(program(delta, args.functions, args.shape))
                elapsed, result = request()
                assert result["cache"] == "miss"
                current = {f["name"]: f["body_hash"] for f in result["backend_stats"]["function_info"]}
                edits.append({"delta": delta,
                              "unchanged_body_hashes": sum(previous.get(k) == v for k, v in current.items()),
                              "changed_body_hashes": sum(previous.get(k) != v for k, v in current.items()),
                              "full_frontend_ran": not (result["backend_stats"].get("parsed_syntax_reused", False) or
                                                        result["backend_stats"].get("semantic_reused", False)),
                              "full_semantic_analysis_ran": not result["backend_stats"].get("semantic_reused", False),
                              "full_backend_ran": True,
                              "backend_stats": result["backend_stats"]})
                previous = current
                samples.append(elapsed)
            report["measurements"]["single_function_edit_server"] = summary(samples)
            report["edits"] = edits
            report["edited_phase_medians_ms"] = {
                key: statistics.median(row["backend_stats"][key] / 1_000_000 for row in edits)
                for key in ("parse_ns", "resolve_ns", "typecheck_ns", "optimize_ns", "bce_ns", "backend_ns")
            }
            execution = subprocess.run([args.node, str(ROOT / "scripts" / "run_wasm.mjs"), str(output)],
                                       input="3\n", text=True, capture_output=True, check=False)
            assert execution.returncode == 0, execution.stderr
            assert execution.stdout == expected(args.samples + 1, args.functions, shape=args.shape), execution.stdout
            report["last_edit_output_verified"] = True
            report["last_edit_stdin"] = "3\n"
            report["last_edit_stdout"] = execution.stdout
            report["last_edit_expected_stdout"] = expected(args.samples + 1, args.functions, shape=args.shape)
        finally:
            server.stdin.close()
            server.wait(timeout=30)
            server.stdout.close()
            stderr = server.stderr.read()
            server.stderr.close()
            if server.returncode:
                raise RuntimeError(stderr)
    report["finished_utc"] = datetime.now(timezone.utc).isoformat()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    for name, row in report["measurements"].items():
        print(f"{name}: median {row['median_ms']:.3f} ms, MAD {row['mad_ms']:.3f} ms")
    print(f"Report: {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
