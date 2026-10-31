#!/usr/bin/env python3
"""Compare the direct backend with the pinned C oracle on V8 and Wasmtime.

This suite qualifies an explicit supported fragment. Unsupported constructs
must be refused at compile time; they are never counted as passing executions.
Native C is the independent semantic oracle. Selected cases also have small
hand-derived answers; floating output is compared byte-for-byte with Goose.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import struct
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures"


@dataclass(frozen=True)
class Case:
    name: str
    fixture: str
    stdin: str = ""
    stdout: str | None = None
    exit_code: int = 0
    diagnostic: str = ""
    debug: bool = False
    group: str = "scalar"
    maximum_pages: int | None = None


def wrap(value, bits, signed=True):
    value &= (1 << bits) - 1
    if signed and value >= 1 << (bits - 1):
        value -= 1 << bits
    return value


def cases():
    result = [Case("checked-leaves/scalars", "checked_leaves", stdout="65 70 true\n25 63 4.25\n7 6 7 9\n-inf 1.25 -2.0\n")]
    result.append(Case("growable/minimal", "growable_minimal", stdout="1\n", group="aggregate"))
    result.append(Case("dynamic/forwarding", "dynamic_forwarding", stdout="1\n", group="aggregate"))
    for n in (-1, 0, 3):
        answer = (f"[{n}, {n + 1}] [{n + 10}, {n + 11}] [7, 8] 3\n"
                  f"[{n}, {n + 2}] " + (f"[{n}, {n + 1}]" if n > 0 else "[]") +
                  " " + ("[-1]" if n < 0 else f"[{n * 2}]") + "\n"
                  f"[{n + 3}, {n + 4}] [9, 10, 11]\n[{n + 5}] [1, 9]\n[20, 22] [41]\n" +
                  ("[7, 8] " if n > 0 else "[1, 2, 3] ") + (f"[{n + 100}]" if n > 0 else "[0]") +
                  f"\n44 55\n25010000 [{n}, {n + 1}] [{n + 10}, {n + 11}] 3\n")
        result.append(Case(f"dynamic/owned-results/{n}", "dynamic_returns", f"{n}\n", answer, group="aggregate"))
    for debug in (False, True):
        result.append(Case("growable/owners-and-stable-views" + ("-debug" if debug else ""), "growable_arrays",
                           stdout="[]\n[5]\n5001 5000 12 12 1 4999 -4999\n[77, 0, 1] 12\n5001 88 12\n"
                           "[1, 2, 3, 3, 3] 3\n[7, 9, 7, 9]\n[2, 3, 2, 3]\n"
                           "[1, 2] 9 [1, 2, 3]\n[1, 2, 3, 4, 3, 2, 1]\n[1, 2, 3, 4, 3, 2, 1, 6] [50]\n"
                           "abc!def\n[6, 6, 6]\n[0, 0, 0]\n[30, 31] 1\n1 4 1\n40 50\n25005000 210\n20 210\n",
                           debug=debug, group="aggregate"))
        for mode, diagnostic in enumerate(("negative", "pop", "pop", "pop", "fill", "bounds", "bounds", "bounds")):
            index = -1 if mode == 6 else 3 if mode == 7 else 2
            result.append(Case(f"growable/errors/{mode}" + ("-debug" if debug else ""), "growable_errors",
                               f"{mode}\n{index}\n", exit_code=1, diagnostic=diagnostic, debug=debug, group="aggregate"))
    result.append(Case("storage/locations-and-copies", "storage_locations",
                       stdout="30 40 10\n35 41 2\n12 8\n21 22 13\n35 41\n", group="aggregate"))
    result.append(Case("storage/cleanup-exits", "cleanup_exits", stdout="49995000\n",
                       group="aggregate", maximum_pages=1))
    result.append(Case("storage/cleanup-preserves-outer-print", "cleanup_nested_loop", stdout="abc 7 8\n",
                       group="aggregate", maximum_pages=1))
    limited_answer = ("0 8 []\n[1, 2, 3, 4] [1, 2] 4 8\n[1, 2, 3, 4, 9, 9]\n9\n[1, 2, 3]\n0\n"
                      "[7, 9]\n[7, 9]\n[7, 9, 7, 9]\n[10, 11, 12] [30, 31, 32] [20, 21, 22]\n"
                      "[77, 11, 12] [10, 11, 12]\n[1, 2] 5 [99, 2, 3]\n"
                      "[99, 2, 3] 5 [99, 2, 3, 3]\n[99, 2, 3, 3, 6] [50]\n"
                      "[6, 6, 6] 3\n0 0\n[] 4\nabc!\n"
                      "[10, 11, 12]\n2 5 42\n[14, 13] 14 0\n1\n[2, 3, 2, 3]\n"
                      "[10, 11, 12] [10, 11, 12]\n500532\n")
    for debug in (False, True):
        result.append(Case("limited/values" + ("-debug" if debug else ""), "limited_arrays",
                           stdout=limited_answer, debug=debug, group="aggregate"))
        result.append(Case("limited/paths" + ("-debug" if debug else ""), "limited_array_paths",
                           stdout="9\n9 1\n2 2\n1\n30 30 40 2\n10 23 23 10\n6\n6\n1\n6\n6\n6\n", debug=debug, group="aggregate"))
        for mode, diagnostic in enumerate(("capacity", "capacity", "capacity", "negative", "pop", "pop",
                                           "pop", "fill", "bounds", "bounds", "capacity")):
            result.append(Case(f"limited/errors/{mode}" + ("-debug" if debug else ""), "limited_array_errors",
                               f"{mode}\n2\n", exit_code=1, diagnostic=diagnostic, debug=debug, group="aggregate"))
    result.append(Case("checked-callers/diamond", "scalar_callers", stdout="18 0 22 72\n"))
    for n in (-1, 0, 4):
        result.append(Case(f"enums/layouts/{n}", "fixed_enums", f"{n}\n",
                           f"20 11.5\n10 {n + 0.5}\n20 0.0\n50\n{n + 2}\n7 9\n77\n8\n10\n1 2 5\n{2 * n + 1}\n{n + 200}\n", group="aggregate"))
        def score(value):
            return -1 if value < 0 else 30 if value == 0 else 3 * value + 3
        result.append(Case(f"enums/returns/{n}", "enum_returns", f"{n}\n",
                           f"{score(n)} {score(n + 1)} 57\n{score(n)} {n * 2} {n + 7}\n{n + 50}\n"
                           f"-1 {n} 6\n{9 if n > 0 else 19} {22 if n == 0 else 12}\n{n + 100}\n", group="aggregate"))
        result.append(Case(f"enums/snapshots/{n}", "enum_snapshots", f"{n}\n",
                           f"66 -1 66\n{n} {n + 1} {n + 2} -1\n15 99 -1\n6 123\n6\n", group="aggregate"))
    for a, b in ((17, 5), (-7, 3), (-7, -3), (0, 2), (1099511627779, 17)):
        quotient = abs(a) // abs(b)
        if (a < 0) != (b < 0):
            quotient = -quotient
        numbers = f"{a + b} {a - b} {a * b} {quotient} {a % abs(b)}\n"
        comparisons = " ".join(str(x).lower() for x in (a < b, a <= b, a == b, a != b, a > b, a >= b))
        bits = f"{a & b} {a | b} {a ^ b}\n"
        result.append(Case(f"arithmetic/{a}/{b}", "scalar_arithmetic", f"{a} {b}\n", numbers + comparisons + "\n" + bits))
    for n in (0, 1, 8, 20):
        total = sum(i * i for i in range(min(n, 12)) if i % 3 != 1) + n * (n + 1) // 2
        answer = total - 100 if total > 100 else total + 100
        result.append(Case(f"control/{n}", "control_flow", f"{n}\n", f"{answer}\n"))
    for n, answer in ((0, 0), (1, 1), (10, 55), (20, 6765)):
        result.append(Case(f"recursion/{n}", "recursion", f"{n}\n", f"{answer} {n * 2}\n"))
    for n in (127, 255, -129, 65535, 2147483648, 4294967295):
        values = [wrap(n, 8), wrap(n, 8, False), wrap(n, 16), wrap(n, 16, False), wrap(n, 32), wrap(n, 32, False)]
        a, b = wrap(values[0] + 1, 8), wrap(values[1] + 1, 8, False)
        text = " ".join(map(str, values)) + f"\n{a} {b}\n{wrap(a << 1, 8)} {a >> 1} {b >> 1}\n"
        result.append(Case(f"narrow/{n}", "narrow_integers", f"{n}\n", text))
    result.extend([
        Case("narrow/division-wrap", "narrow_division", "-2147483648 -1\n", "-2147483648 0\n"),
        Case("narrow/debug-division", "narrow_division", "-2147483648 -1\n", exit_code=1, diagnostic="overflow", debug=True),
        Case("narrow/debug-add", "narrow_integers", "127\n", "127 127 127 127 127 127\n", 1, "overflow", True),
        Case("float/exact", "float_operations", "2.5 0.5\n", "3.0 2.0 1.25 5.0\n3.0 1.25 5.0\nfalse false true\n"),
        Case("float/rounding", "float_operations", "9 0.1\n"),
        Case("float/nan", "float_operations", "nan 1\n"),
        Case("float/cast-release", "float_to_integer", "1.5\n", "1\n"),
        Case("float/cast-debug", "float_to_integer", "1.5\n", exit_code=1, diagnostic="conversion", debug=True),
        Case("short-circuit/false", "short_circuit", "-5\n", "false\ntrue\n5\n"),
        Case("short-circuit/true", "short_circuit", "5\n", "called\ntrue\ncalled\ntrue\n15\n"),
        Case("assert/pass", "assertion", "1\n", "accepted\n"),
        Case("assert/fail", "assertion", "0\n", exit_code=1, diagnostic="assert"),
        Case("abort/message", "abort", exit_code=1, diagnostic="custom abort message"),
        Case("division/zero", "scalar_arithmetic", "7 0\n", exit_code=1, diagnostic="division by zero"),
        Case("division/i64-overflow", "scalar_arithmetic", "-9223372036854775808 -1\n", exit_code=1, diagnostic="overflow"),
        Case("remainder/minus-one", "remainder", "-9223372036854775808 -1\n", "0\n"),
        Case("remainder/minimum-divisor", "remainder", "-7 -9223372036854775808\n", "9223372036854775801\n"),
        Case("exit/seven", "exit", "7\n", "before exit\n", exit_code=7),
        Case("arrays/fixed", "fixed_arrays", "4\n", "12 33 180\n4 90\n", group="aggregate"),
        Case("storage/sparse-data", "static_data", "255\n", "0 0 17 29\n255 0 20\nA\0B\n\0C\0D\0\n", group="aggregate"),
        Case("arrays/valid-index", "array_bounds", "1\n", "5\n", group="aggregate"),
        Case("arrays/upper-bound", "array_bounds", "3\n", exit_code=1, diagnostic="bounds", group="aggregate"),
        Case("arrays/negative-index", "array_bounds", "-1\n", exit_code=1, diagnostic="bounds", group="aggregate"),
        Case("struct/fields", "struct_values", "5\n", "25 17\n", group="aggregate"),
        Case("values/references-match-and-snapshots", "value_forms", "3\n", "6 10 1\n30 10 11\n10 10 6 2\ninner\nabc 9\n", group="aggregate"),
        Case("values/nullable-identity-copy", "nullable_and_copy", "4\n", "true\ntrue\n4\ntrue false\n[1, 2, 3] [9, 2, 3]\n", group="aggregate"),
        Case("values/inline-print-unwind", "inline_print_unwind", "1\n", "50005000\n", group="aggregate"),
        Case("values/implicit-references", "implicit_references", stdout="6 [1, 6, 3] 9\n", group="aggregate"),
        Case("unsigned/u64-boundaries", "unsigned_wide", "-1 -9223372036854775808\n", "18446744073709551615 9223372036854775808 1 9223372036854775807 9223372036854775807 0\n"),
    ])
    values = ["0", "-0.0", "nan", "inf", "-inf", "0.1", "0.0001", "0.00001", "1e15", "1e14", "1e20", "1.2345678901234567", "3.4028234663852886e38", "1.401298464324817e-45", "5e-324", "1.7976931348623157e308"]
    rng = random.Random(7931)
    for _ in range(96):
        value = struct.unpack("<f", struct.pack("<I", rng.randrange(1 << 32)))[0]
        values.append(repr(value))
    for _ in range(96):
        value = struct.unpack("<d", struct.pack("<Q", rng.randrange(1 << 64)))[0]
        values.append(repr(value))
    result.append(Case("float/render-corpus", "float_render", str(len(values)) + "\n" + "\n".join(values) + "\n"))
    edges = [0.0, -0.0, 1.0, -1.0, 5.5, -5.5, float("inf"), float("-inf"), float("nan"),
             5e-324, 1.5e-323, 2.2250738585072014e-308, 2.225073858507201e-308,
             1.7976931348623157e308, 1e308, 1.401298464324817e-45, 4.203895392974451e-45,
             1.1754943508222875e-38, 1.1754942106924411e-38, 3.4028234663852886e38]
    pairs = [(a, b) for a in edges for b in edges]
    for fmt, integer, bits in (("<f", "<I", 32), ("<d", "<Q", 64)):
        for _ in range(128):
            pairs.append(tuple(struct.unpack(fmt, struct.pack(integer, rng.randrange(1 << bits)))[0] for _ in range(2)))
    # Values immediately around the subtraction/scaling boundaries.
    for value in (1.0, 1e308, 2.2250738585072014e-308):
        pairs.extend([(math.nextafter(value, 0.0), value), (math.nextafter(value, float("inf")), value)])
        if math.isfinite(2 * value):
            pairs.extend([(math.nextafter(2 * value, 0.0), value), (math.nextafter(2 * value, float("inf")), value)])
    data = str(len(pairs)) + "\n" + "".join(f"{a!r} {b!r}\n" for a, b in pairs)
    result.append(Case("float/remainder-corpus", "float_remainder", data))
    return result


def execute(command, *, cwd, stdin="", timeout=180):
    started = time.perf_counter_ns()
    result = subprocess.run([str(x) for x in command], cwd=cwd, input=stdin, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, check=False)
    return result, (time.perf_counter_ns() - started) / 1e9


def save_log(directory, name, command, result):
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f"{name}.command.json").write_text(json.dumps([str(x) for x in command], indent=2) + "\n", encoding="utf-8")
    (directory / f"{name}.stdout").write_text(result.stdout, encoding="utf-8")
    (directory / f"{name}.stderr").write_text(result.stderr, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=ROOT / "build" / "bin" / "goose")
    parser.add_argument("--emcc", default=os.environ.get("EMCC", "emcc"))
    parser.add_argument("--cc", default=os.environ.get("CC", "cc"))
    parser.add_argument("--node", default="node")
    parser.add_argument("--engines", nargs="+", choices=("v8", "wasmtime"), default=["v8", "wasmtime"])
    parser.add_argument("--backends", nargs="+", choices=("direct", "c-wasm", "native"), default=["direct", "c-wasm", "native"])
    parser.add_argument("--levels", nargs="+", type=int, choices=(0, 1, 2), default=[0, 2])
    parser.add_argument("--scalar-only", action="store_true")
    parser.add_argument("--filter", default="")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build" / "differential")
    args = parser.parse_args()
    args.goose = args.goose.resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    selected = [case for case in cases() if args.filter in case.name and (not args.scalar_only or case.group == "scalar")]
    if not selected:
        parser.error("no cases selected")
    compiled = {}
    rows = []
    native_observations = {}
    order = [name for name in ("native", "c-wasm", "direct") if name in args.backends]
    for level in args.levels:
        for backend in order:
            for case in selected:
                key = (backend, case.fixture, case.debug, level, case.maximum_pages)
                directory = output / f"O{level}" / ("debug" if case.debug else "release") / case.fixture / backend
                if case.maximum_pages is not None:
                    directory = directory / f"memory-{case.maximum_pages}"
                if key not in compiled:
                    directory.mkdir(parents=True, exist_ok=True)
                    suffix = ".bin" if backend == "native" else ".wasm"
                    artifact = directory / ("program" + suffix)
                    build = [sys.executable, ROOT / "scripts" / "goose_wasm.py", "build", FIXTURES / f"{case.fixture}.goose", "-o", artifact,
                             "--backend", backend, f"-O{level}", "--goose", args.goose, "--no-cache", "--offline"]
                    if backend != "direct":
                        build += ["--c-source", ROOT / "bench" / "host_input.c", "--cc", args.cc, "--emcc", args.emcc]
                    if case.debug:
                        build.append("--debug")
                    if backend == "direct" and case.maximum_pages is not None:
                        build += ["--initial-pages", "1", "--maximum-pages", str(case.maximum_pages)]
                    result, seconds = execute(build, cwd=ROOT)
                    save_log(directory, "compile", build, result)
                    compiled[key] = (artifact, result, seconds)
                artifact, built, compile_seconds = compiled[key]
                engines = ["native"] if backend == "native" else args.engines
                for engine in engines:
                    row = {"case": case.name, "fixture": case.fixture, "backend": backend, "engine": engine,
                           "optimization": level, "debug": case.debug, "compile_seconds": compile_seconds,
                           "direct_maximum_pages": case.maximum_pages if backend == "direct" else None}
                    try:
                        if built.returncode:
                            raise AssertionError("compile failed: " + (built.stdout + built.stderr)[-2000:])
                        if engine == "native":
                            command = [artifact]
                        elif engine == "v8":
                            command = [args.node, ROOT / "scripts" / "run_wasm.mjs", artifact]
                        else:
                            command = [sys.executable, ROOT / "scripts" / "run_wasmtime.py", artifact]
                        result, seconds = execute(command, cwd=directory, stdin=case.stdin, timeout=30)
                        label = case.name.replace("/", "_") + "_" + engine
                        save_log(directory, label, command, result)
                        row.update(run_seconds=seconds, exit_code=result.returncode, stdout=result.stdout, stderr=result.stderr)
                        if result.returncode != case.exit_code:
                            raise AssertionError(f"exit {result.returncode}, expected {case.exit_code}: {result.stderr[-1500:]}")
                        if case.diagnostic and case.diagnostic not in result.stderr.lower():
                            raise AssertionError(f"missing {case.diagnostic!r} diagnostic: {result.stderr[-1500:]}")
                        if case.stdout is not None and result.stdout != case.stdout:
                            raise AssertionError(f"stdout {result.stdout!r}, expected {case.stdout!r}")
                        reference_key = (case.name, level, case.debug)
                        if backend == "native":
                            native_observations[reference_key] = result.stdout
                        elif reference_key in native_observations and result.stdout != native_observations[reference_key]:
                            raise AssertionError(f"stdout differs from native Goose: {result.stdout!r} != {native_observations[reference_key]!r}")
                        row.update(status="pass", module_bytes=artifact.stat().st_size,
                                   sha256=hashlib.sha256(artifact.read_bytes()).hexdigest())
                    except (AssertionError, OSError, subprocess.TimeoutExpired) as failure:
                        row.update(status="fail", error=str(failure))
                    rows.append(row)
                    print(f"{row['status'].upper()} O{level} {backend}/{engine} {case.name}", flush=True)
                    if row["status"] == "fail":
                        print(row["error"], flush=True)
    # The direct fragment must explicitly refuse these valid Goose programs.
    if "direct" in args.backends and not args.filter:
        for fixture in ("unsupported_dynamic_parameters", "unsupported_pointer_extern", "invalid_source"):
            directory = output / "refusals" / fixture
            directory.mkdir(parents=True, exist_ok=True)
            artifact = directory / "program.wasm"
            command = [sys.executable, ROOT / "scripts" / "goose_wasm.py", "build", FIXTURES / f"{fixture}.goose",
                       "-o", artifact, "--backend", "direct", "--goose", args.goose, "--no-cache", "--offline"]
            result, seconds = execute(command, cwd=ROOT)
            save_log(directory, "compile", command, result)
            passed = result.returncode != 0 and not artifact.exists()
            diagnostic = result.stdout + result.stderr
            if fixture == "invalid_source":
                passed = passed and "unknown escape" in diagnostic
            else:
                passed = passed and any(word in diagnostic.lower() for word in ("unsupported", "does not support", "not supported", "direct target"))
            rows.append({"case": fixture, "backend": "direct", "kind": "compile-refusal", "status": "pass" if passed else "fail",
                         "compile_seconds": seconds, "diagnostic": diagnostic})
            print(("PASS " if passed else "FAIL ") + fixture, flush=True)
    failures = sum(row["status"] != "pass" for row in rows)
    report = {"schema": "goose-direct-differential-v1", "platform": platform.platform(),
              "python": sys.version, "toolchain": json.loads((ROOT / "toolchain.json").read_text()),
              "compiler_sha256": hashlib.sha256(args.goose.read_bytes()).hexdigest(),
              "cases": len(selected), "observations": len(rows), "failures": failures, "results": rows}
    report_path = output / "report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"{len(rows) - failures}/{len(rows)} observations passed; {report_path}")
    return int(failures != 0)


if __name__ == "__main__":
    sys.exit(main())
