#!/usr/bin/env python3
"""Qualify owned aggregate returns and Wasm math against native Goose.

O0 and O2 run the same fixtures on native C, V8, and Wasmtime. The math
module's import list additionally proves its operations do not call a host
math implementation. The report retains all commands, results, and hashes.
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
FIXTURES = ROOT / "tests" / "fixtures"


def aggregate_answer(n):
    return (f"{n} {100 * n + n * (n + 1) // 2} 1000 2000\n"
            "8 16 [10, 11, 12] [20, 21, 22]\n"
            f"{n + 1} {2 * (n + 1)} {2 * (n + 1)} {4 * (n + 1)} {3 * (n + 1)}\n"
            "11 22 99 99 77\n"
            "[1, 2, 3] 9 [42, 2, 3]\n"
            "25\n"
            "19 7 14\n"
            f"{n} {2 * n} {3 * n}\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=ROOT / "build" / "bin" / "goose")
    parser.add_argument("--node", default="node")
    parser.add_argument("--cc", default="cc")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build" / "backend-extensions")
    args = parser.parse_args()
    args.goose = args.goose.resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    rows = []
    reference = {}
    cases = {
        "aggregate_returns": [(str(n), f"{n}\n", aggregate_answer(n)) for n in (0, 1, 4, 7)],
        "math_intrinsics": [(str(i), f"{value} {bits}\n", None)
                            for i, (value, bits) in enumerate((
                                ("2.5", 0), ("-2.5", 1), ("0", -1), ("-0.0", -9223372036854775808),
                                ("nan", 256), ("inf", 65536), ("-inf", 2147483647),
                                ("1.401298464324817e-45", 3), ("5e-324", 127),
                                ("3.4028234663852886e38", 9223372036854775807),
                            ))],
    }

    def record(name, action):
        try:
            details = action() or {}
            row = {"name": name, "status": "pass", **details}
        except (AssertionError, OSError, subprocess.TimeoutExpired) as failure:
            row = {"name": name, "status": "fail", "error": str(failure)}
        rows.append(row)
        print(f"{row['status'].upper()} {name}" + (f": {row['error']}" if "error" in row else ""), flush=True)
        return row["status"] == "pass"

    for level in (0, 2):
        for fixture, inputs in cases.items():
            for backend in ("native", "direct"):
                directory = output / f"O{level}" / fixture / backend
                directory.mkdir(parents=True, exist_ok=True)
                artifact = directory / ("program.bin" if backend == "native" else "program.wasm")
                build = [sys.executable, ROOT / "scripts" / "goose_wasm.py", "build", FIXTURES / (fixture + ".goose"),
                         "--backend", backend, f"-O{level}", "--goose", args.goose, "--offline", "--no-cache", "-o", artifact]
                if backend == "native":
                    build += ["--cc", args.cc, "--c-source", ROOT / "bench" / "host_input.c"]
                result, seconds = execute(build, cwd=ROOT)
                save_log(directory, "compile", build, result)
                if result.returncode:
                    def compile_failure():
                        raise AssertionError((result.stdout + result.stderr)[-5000:])
                    record(f"O{level}/{fixture}/{backend}/compile", compile_failure)
                    continue
                artifact_hash = hashlib.sha256(artifact.read_bytes()).hexdigest()
                if backend == "direct" and fixture == "math_intrinsics":
                    def imports_check():
                        command = [args.node, "-e", "const fs=require('node:fs');console.log(JSON.stringify(WebAssembly.Module.imports(new WebAssembly.Module(fs.readFileSync(process.argv[1])))))", artifact]
                        observed, _ = execute(command, cwd=directory)
                        save_log(directory, "imports", command, observed)
                        assert observed.returncode == 0, observed.stderr
                        imports = json.loads(observed.stdout)
                        host = {(item["module"], item["name"]) for item in imports if item["module"] != "goose"}
                        assert host == {("env", "bench_input"), ("env", "bench_input_f64")}, imports
                        return {"imports": imports, "sha256": artifact_hash}
                    record(f"O{level}/{fixture}/no-host-math", imports_check)
                for engine in (("native",) if backend == "native" else ("v8", "wasmtime")):
                    for label, stdin, expected in inputs:
                        def run_case():
                            command = ([artifact] if engine == "native" else
                                       [args.node, ROOT / "scripts" / "run_wasm.mjs", artifact] if engine == "v8" else
                                       [sys.executable, ROOT / "scripts" / "run_wasmtime.py", artifact])
                            observed, duration = execute(command, cwd=directory, stdin=stdin, timeout=30)
                            save_log(directory, label + "-" + engine, command, observed)
                            assert observed.returncode == 0, observed.stderr
                            if expected is not None:
                                assert observed.stdout == expected, (observed.stdout, expected)
                            if fixture == "math_intrinsics":
                                bits = int(stdin.split()[1]) & ((1 << 64) - 1)
                                assert observed.stdout.splitlines()[-1] == f"{64 - bits.bit_length()} 104", observed.stdout
                            key = (fixture, label, level)
                            if engine == "native":
                                reference[key] = observed.stdout
                            else:
                                assert key in reference, "native reference did not pass"
                                assert observed.stdout == reference[key], (observed.stdout, reference[key])
                            return {"stdin": stdin, "stdout": observed.stdout, "stderr": observed.stderr,
                                    "sha256": artifact_hash, "compile_seconds": seconds, "run_seconds": duration}
                        record(f"O{level}/{fixture}/{engine}/{label}", run_case)

    # Returning aggregates stays an internal Goose ABI, never an implicit
    # contract with an arbitrary host function or public Wasm export.
    refusals = {
        "aggregate-extern": ('struct Pair { x: i64, y: i64 }\nextern fn foreign() -> Pair;\nfn main() { let p = foreign(); print(p.x); }\n',
                             "externs currently return numeric and bool values only"),
        "aggregate-export": ('struct Pair { x: i64, y: i64 }\nexport fn exported() -> Pair { Pair { 1, 2 } }\nfn main() {}\n',
                             "public exports currently return numeric and bool values only"),
    }
    for label, (source, diagnostic) in refusals.items():
        def refuse():
            directory = output / "refusals" / label
            directory.mkdir(parents=True, exist_ok=True)
            path = directory / "main.goose"
            path.write_text(source)
            artifact = directory / "program.wasm"
            artifact.unlink(missing_ok=True)
            command = [args.goose, path, "--target", "wasm-direct", "--offline", "-o", artifact]
            result, _ = execute(command, cwd=ROOT)
            save_log(directory, "compile", command, result)
            assert result.returncode != 0 and not artifact.exists(), result.stdout
            assert diagnostic in result.stdout + result.stderr, result.stdout + result.stderr
            return {"diagnostic": result.stdout + result.stderr}
        record(label, refuse)

    failures = sum(row["status"] != "pass" for row in rows)
    report = {"schema": "goose-backend-extensions-v1", "compiler_sha256": hashlib.sha256(args.goose.read_bytes()).hexdigest(),
              "observations": len(rows), "failures": failures, "results": rows}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"{len(rows) - failures}/{len(rows)} checks passed; {output / 'report.json'}")
    return int(failures != 0)


if __name__ == "__main__":
    sys.exit(main())
