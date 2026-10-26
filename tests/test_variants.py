#!/usr/bin/env python3
"""Qualify fixed-payload enums and variants against both C reference paths."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from run_differential import execute, save_log

ROOT = Path(__file__).resolve().parents[1]


def shape(n):
    if n < 0:
        return "Shape.Empty", 0
    if n % 2 == 0:
        return f"Point {{ {n}, {n * 2} }}", n * 3
    return f"Samples {{ [{n}, {n + 1}, {n + 2}] }}", n * 3 + 3


def answer(n):
    text, value = shape(n)
    other, extra = shape(n + 1)
    return (f"{text} | {text} | {value}\n[{text}, {other}]\n"
            f"{value + extra} {10 if n < 0 else value}\n"
            "Point { 12, 9 } 21\nShape.Empty 0\nPoint { 11, 22 }\n"
            f"{n} {n + 1} Point {{ {n}, {n + 1} }}\nBox {{ 7, {text} }}\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=ROOT / "build/bin/goose")
    parser.add_argument("--node", default="node")
    parser.add_argument("--emcc", default="emcc")
    parser.add_argument("--backends", nargs="+", choices=["native", "c-wasm", "direct"],
                        default=["native", "c-wasm", "direct"])
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/variants")
    args = parser.parse_args()
    args.goose = args.goose.resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    rows = []

    def record(name, action):
        try:
            detail = action() or {}
            rows.append({"name": name, "status": "pass", **detail})
        except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
            rows.append({"name": name, "status": "fail", "error": str(error)})
        row = rows[-1]
        print(row["status"].upper(), name, row.get("error", ""), flush=True)
        return row["status"] == "pass"

    for level in (0, 2):
        for backend in args.backends:
            directory = output / f"O{level}" / backend
            directory.mkdir(parents=True, exist_ok=True)
            artifact = directory / ("program.bin" if backend == "native" else "program.wasm")
            def build():
                command = [sys.executable, ROOT / "scripts/goose_wasm.py", "build",
                           ROOT / "tests/fixtures/enum_values.goose", "--goose", args.goose,
                           "--backend", backend, f"-O{level}", "--no-cache", "--offline",
                           "--emcc", args.emcc, "-o", artifact]
                if backend != "direct":
                    command += ["--c-source", ROOT / "bench/host_input.c"]
                result, duration = execute(command, cwd=ROOT)
                save_log(directory, "compile", command, result)
                assert result.returncode == 0, result.stdout + result.stderr
                return {"seconds": duration, "bytes": artifact.stat().st_size,
                        "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest()}
            if not record(f"O{level}/{backend}/compile", build):
                continue
            for engine in (("native",) if backend == "native" else ("v8", "wasmtime")):
                for n in (-1, 0, 7, 42):
                    def run():
                        command = ([artifact] if engine == "native" else
                                   [args.node, ROOT / "scripts/run_wasm.mjs", artifact] if engine == "v8" else
                                   [sys.executable, ROOT / "scripts/run_wasmtime.py", artifact])
                        result, duration = execute(command, cwd=directory, stdin=f"{n}\n")
                        save_log(directory, f"{engine}-{n}", command, result)
                        assert result.returncode == 0, result.stderr
                        assert result.stdout == answer(n), (result.stdout, answer(n))
                        return {"input": n, "stdout": result.stdout, "seconds": duration}
                    record(f"O{level}/{backend}/{engine}/{n}", run)
    failures = sum(row["status"] != "pass" for row in rows)
    report = {"schema": "goose-variant-qualification-v1", "observations": len(rows),
              "failures": failures, "compiler_sha256": hashlib.sha256(args.goose.read_bytes()).hexdigest(),
              "results": rows}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"{len(rows) - failures}/{len(rows)} passed; {output / 'report.json'}")
    return int(failures != 0)


if __name__ == "__main__":
    sys.exit(main())
