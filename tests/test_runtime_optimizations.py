#!/usr/bin/env python3
"""Exercise numeric/control optimizations against independent integer models.

Both optimization levels and both engines must retain narrow integer wrapping,
Euclidean modulo, lazy traps/effects, condition ordering, and loop exits. Debug
cases additionally prove that untaken checked operations remain unevaluated.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from run_differential import execute, save_log

ROOT = Path(__file__).resolve().parents[1]


def signed(value: int, bits: int) -> int:
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def line(*values: int) -> str:
    return " ".join(map(str, values)) + "\n"


def numeric_answer(x: int) -> str:
    u = x & ((1 << 64) - 1)
    answer = line(*(x % d for d in (1, 2, 8, 256, 65536, 1 << 62)))
    answer += line(*(u % d for d in (1, 2, 8, 1 << 63)))
    answer += line(*(u // d for d in (1, 2, 8, 1 << 63)))
    answer += line(signed(x, 8) % 8, signed(x, 16) % 256, signed(x, 32) % 65536)
    shifts = []
    for bits in (8, 16, 32, 64):
        value = (1 << (bits - 1)) + 1
        count = x & (bits - 1)
        shifts += [(value << count) & ((1 << bits) - 1), value >> count]
    answer += line(*shifts[:4]) + line(*shifts[4:])
    answer += line(-127 >> (x & 7), -2147483647 >> (x & 31))
    answer += line(signed(signed(x, 8) << 1, 8), signed(x, 8) >> 7, signed(x, 32), u >> 1)
    return answer + line(x % 8, 1)


def control_answer(x: int) -> str:
    flag = bool(x & 1)
    u = x & 0xFFFFFFFF
    selected = ((u << 5) + u + 1) & 0xFFFFFFFF if flag else u >> 3
    result = x
    for i in range(8):
        if i == 2:
            continue
        if i == 6:
            break
        result = result ^ (i << 1) if result & 1 else result + i
    changed = x + 1
    changed ^= 85 if changed & 1 else 170
    quotient = (123 // abs(x)) * (-1 if x < 0 else 1) if flag else 7
    return (line(selected, result) + line(changed, 1) +
            line(5 if flag else 7, quotient, 7, 9, 2) +
            line(126 if flag else -128) + line(24, 28, 224, 10))


def fill_answer(count: int) -> str:
    color = (count * 17 + 3) & 255
    checksum = 170 * (67 * 68 // 2) + (color - 170) * count * (count + 3) // 2
    return line(checksum, 44 * 9 + 256, signed(color, 8) * 4, 55, 5, 33)


def loop_answer(n: int) -> str:
    total = sum(sum(i * i + 1 for i in range(n + repeat)) for repeat in range(3))
    triangular = n * (n - 1) // 2
    return line(total, triangular, 5 + 3 * triangular, 103 if n > 3 else -1, 7 + triangular)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=ROOT / "build/bin/goose")
    parser.add_argument("--node", default="node")
    parser.add_argument("--case", choices=("numeric_strength", "scalar_control", "byte_fill", "loop_calls"), action="append")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/runtime-optimizations")
    args = parser.parse_args()
    compiler = args.goose.resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    before = hashlib.sha256(compiler.read_bytes()).hexdigest()
    sources = [Path(__file__).resolve(), ROOT / "scripts/run_wasm.mjs", ROOT / "scripts/run_wasmtime.py",
               *(ROOT / "tests/fixtures" / (case + ".goose")
                 for case in ("numeric_strength", "scalar_control", "byte_fill", "loop_calls"))]
    source_hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
    rows = []

    def record(label, action):
        try:
            details = action() or {}
            row = {"name": label, "status": "pass", **details}
        except (AssertionError, OSError, ValueError, subprocess.TimeoutExpired) as error:
            row = {"name": label, "status": "fail", "error": str(error)}
        rows.append(row)
        print(f"{row['status'].upper()} {label}" + (": " + row["error"] if "error" in row else ""), flush=True)
        return row["status"] == "pass"

    values = (-9223372036854775808, -65537, -257, -129, -9, -1, 0, 1, 7, 8, 31, 32, 63, 64, 127, 255,
              65536, 2147483647, 9223372036854775807)
    for level, debug in ((0, False), (2, False), (2, True)):
        for fixture, inputs, answer in (("numeric_strength", values, numeric_answer),
                                        ("scalar_control", (1, -9) if debug else (0, 1, 8, -9, 255), control_answer),
                                        ("byte_fill", (0, 1, 7, 31, 32), fill_answer),
                                        ("loop_calls", (0, 1, 3, 4, 10), loop_answer)):
            if args.case and fixture not in args.case:
                continue
            # Function-value captures require the existing Goose inliner;
            # this case qualifies the new policy only where inlining is on.
            if fixture == "loop_calls" and level < 2:
                continue
            for backend in ("native", "direct"):
                directory = output / (f"O{level}" + ("-debug" if debug else "")) / fixture / backend
                directory.mkdir(parents=True, exist_ok=True)
                artifact = directory / ("program.bin" if backend == "native" else "program.wasm")
                command = [sys.executable, ROOT / "scripts/goose_wasm.py", "build", ROOT / "tests/fixtures" / (fixture + ".goose"),
                           "--backend", backend, f"-O{level}", "--goose", compiler, "--offline", "--no-cache", "-o", artifact,
                           "--stats", directory / "build-stats.json"]
                if debug:
                    command += ["--debug"]
                if backend == "native":
                    command += ["--c-source", ROOT / "bench/host_input.c"]

                def build():
                    result, seconds = execute(command, cwd=ROOT, timeout=120)
                    save_log(directory, "compile", command, result)
                    assert result.returncode == 0, (result.stdout + result.stderr)[-6000:]
                    if fixture == "loop_calls" and backend == "direct":
                        stats = json.loads((directory / "build-stats.json").read_text())
                        names = [function["name"] for function in stats.get("backend_stats", {}).get("function_info", [])]
                        assert any(name.startswith("kernel#") for name in names), names
                        assert not any(name.startswith("forced#") for name in names), names
                    return {"wall_seconds": seconds, "artifact_sha256": hashlib.sha256(artifact.read_bytes()).hexdigest()}

                if not record(f"{directory.relative_to(output)}/compile", build):
                    continue
                for engine in (("native",) if backend == "native" else ("v8", "wasmtime")):
                    for x in inputs:
                        def run():
                            invocation = ([artifact] if engine == "native" else
                                          [args.node, ROOT / "scripts/run_wasm.mjs", artifact] if engine == "v8" else
                                          [sys.executable, ROOT / "scripts/run_wasmtime.py", artifact])
                            result, seconds = execute(invocation, cwd=directory, stdin=f"{x}\n", timeout=30)
                            save_log(directory, engine + "-" + str(x), invocation, result)
                            assert result.returncode == 0, result.stderr
                            expected = answer(x)
                            assert result.stdout == expected, {"expected": expected, "actual": result.stdout, "stderr": result.stderr}
                            return {"input": x, "stdout": result.stdout, "wall_seconds": seconds}
                        record(f"{directory.relative_to(output)}/{engine}/{x}", run)

    after = hashlib.sha256(compiler.read_bytes()).hexdigest()
    sources_unchanged = all(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == value
                            for name, value in source_hashes.items())
    failures = sum(row["status"] == "fail" for row in rows)
    report = {"schema": "goose-runtime-optimizations-v1", "compiler_sha256": before,
              "compiler_unchanged": before == after, "source_hashes": source_hashes, "sources_unchanged": sources_unchanged,
              "observations": len(rows), "failures": failures, "results": rows}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"{len(rows) - failures}/{len(rows)} checks passed; {output / 'report.json'}")
    return int(failures != 0 or before != after or not sources_unchanged)


if __name__ == "__main__":
    raise SystemExit(main())
