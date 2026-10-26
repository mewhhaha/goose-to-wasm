#!/usr/bin/env python3
"""Qualify stable dynamic storage, ownership, and rendering on both engines.

Native Goose C is the independent semantic reference. The same source runs
at Goose O0 and O2 on V8 and Wasmtime. Direct runs use a one-MiB memory limit
to expose abandoned loop/return allocations; deliberate exhaustion has its
own bounded direct-only case, never an uncontrolled native allocation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

from run_differential import execute, save_log

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=ROOT / "build" / "bin" / "goose")
    parser.add_argument("--native-goose", type=Path)
    parser.add_argument("--node", default="node")
    parser.add_argument("--cc", default="cc")
    parser.add_argument("--emcc", default=os.environ.get("EMCC", "emcc"))
    parser.add_argument("--backends", nargs="+", choices=("native", "c-wasm", "direct"),
                        default=["native", "c-wasm", "direct"])
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build" / "dynamic-results")
    parser.add_argument("--filter", default="")
    args = parser.parse_args()
    args.goose = args.goose.resolve()
    native = (args.native_goose or args.goose).resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    compiler_hash = hashlib.sha256(args.goose.read_bytes()).hexdigest()
    rows = []
    reference = {}
    fixtures = {
        "dynamic_arrays": [(str(n), f"{n}\n", 0) for n in (3, 8)],
        "dynamic_lifetimes": [(str(n), f"{n}\n", 0) for n in (0, 8)],
        "dynamic_strings": [(str(n), f"{n}\n", 0) for n in (-7, 42)],
        "dynamic_variants": [(str(n), f"{n}\n", 0) for n in (-1, 4, 7)],
        "dynamic_limited_reuse": [("retained", "", 0)],
        "dynamic_errors": [(str(mode), f"{mode}\n", 1) for mode in (0, 1, 2, 3, 4, 6, 7, 8, 9, 10, 11)],
    }

    def record(name, action):
        try:
            row = {"name": name, "status": "pass", **(action() or {})}
        except (AssertionError, OSError, subprocess.TimeoutExpired) as failure:
            row = {"name": name, "status": "fail", "error": str(failure)}
        rows.append(row)
        print(f"{row['status'].upper()} {name}" + (f": {row['error']}" if "error" in row else ""), flush=True)

    for level in (0, 2):
        for fixture, cases in fixtures.items():
            if args.filter not in fixture:
                continue
            for backend in (name for name in ("native", "c-wasm", "direct") if name in args.backends):
                directory = output / f"O{level}" / fixture / backend
                directory.mkdir(parents=True, exist_ok=True)
                artifact = directory / ("program.bin" if backend == "native" else "program.wasm")
                source = FIXTURES / (fixture + ".goose")
                if backend == "native":
                    generated = directory / "program.c"
                    command = [native, source, "--standalone", "--target", "native", "--offline", f"-O{level}", "-o", generated]
                    result, compile_seconds = execute(command, cwd=ROOT)
                    save_log(directory, "generate", command, result)
                    if result.returncode == 0:
                        command = [args.cc, "-O2", "-fno-strict-aliasing", "-ffp-contract=off", generated,
                                   ROOT / "bench" / "host_input.c", "-lm", "-pthread", "-o", artifact]
                        result, c_seconds = execute(command, cwd=ROOT)
                        compile_seconds += c_seconds
                elif backend == "direct":
                    command = [args.goose, source, "--target", "wasm-direct", "--offline", f"-O{level}",
                               "--wasm-initial-pages", "1", "--wasm-max-pages", "16", "-o", artifact]
                    result, compile_seconds = execute(command, cwd=ROOT)
                else:
                    command = [sys.executable, ROOT / "scripts" / "goose_wasm.py", "build", source,
                               "--backend", "c-wasm", "--goose", args.goose, "--emcc", args.emcc,
                               "--cc", args.cc, "--c-source", ROOT / "bench" / "host_input.c",
                               "--offline", "--no-cache", f"-O{level}", "-o", artifact]
                    result, compile_seconds = execute(command, cwd=ROOT)
                save_log(directory, "compile", command, result)
                if result.returncode:
                    record(f"O{level}/{fixture}/{backend}/compile", lambda r=result: (_ for _ in ()).throw(AssertionError((r.stdout + r.stderr)[-5000:])))
                    continue
                artifact_hash = hashlib.sha256(artifact.read_bytes()).hexdigest()
                for engine in (("native",) if backend == "native" else ("v8", "wasmtime")):
                    for label, stdin, expected_exit in cases:
                        def run_case():
                            command = ([artifact] if engine == "native" else
                                       [args.node, ROOT / "scripts" / "run_wasm.mjs", artifact] if engine == "v8" else
                                       [sys.executable, ROOT / "scripts" / "run_wasmtime.py", artifact])
                            observed, duration = execute(command, cwd=directory, stdin=stdin, timeout=60)
                            save_log(directory, label + "-" + engine, command, observed)
                            assert observed.returncode == expected_exit, (observed.returncode, expected_exit, observed.stderr[-2000:])
                            key = (fixture, label, level)
                            if engine == "native":
                                reference[key] = observed.stdout
                            elif "native" in args.backends:
                                assert key in reference, "native reference did not pass"
                                assert observed.stdout == reference[key], (observed.stdout, reference[key])
                                if expected_exit:
                                    assert "wasm trap" not in observed.stderr.lower(), observed.stderr
                                    assert observed.stderr.strip(), "missing checked runtime diagnostic"
                            return {"stdin": stdin, "stdout": observed.stdout, "stderr": observed.stderr,
                                    "exit_code": observed.returncode, "sha256": artifact_hash,
                                    "compile_seconds": compile_seconds, "run_seconds": duration}
                        record(f"O{level}/{fixture}/{engine}/{label}", run_case)

    if not args.filter and "direct" in args.backends:
        for name, count in (("memory-exhaustion", 1000000), ("length-overflow", 9223372036854775807)):
            directory = output / name
            directory.mkdir(parents=True, exist_ok=True)
            source, artifact = directory / "main.goose", directory / "program.wasm"
            if name == "memory-exhaustion":
                source.write_text("fn main() { var a: u8[>..<] = []; var b: u8[>..<] = []; var c: u8[>..<] = []; "
                                  "a.resize(100000, 1); b.resize(100000, 2); c.resize(100000, 3); print(a.len, b.len, c.len); }\n")
            else:
                source.write_text(f"fn main() {{ var values: i64[>..<] = []; values.resize({count}, 1); print(values.len); }}\n")
            command = [args.goose, source, "--target", "wasm-direct", "--offline", "-O2",
                       "--wasm-initial-pages", "1", "--wasm-max-pages", "4", "-o", artifact]
            result, _ = execute(command, cwd=ROOT)
            save_log(directory, "compile", command, result)
            for engine in ("v8", "wasmtime"):
                def exhausted():
                    assert result.returncode == 0, result.stdout + result.stderr
                    command = ([args.node, ROOT / "scripts" / "run_wasm.mjs", artifact] if engine == "v8" else
                               [sys.executable, ROOT / "scripts" / "run_wasmtime.py", artifact])
                    observed, _ = execute(command, cwd=ROOT)
                    save_log(directory, engine, command, observed)
                    assert observed.returncode == 1, observed.stderr
                    assert not observed.stdout, observed.stdout
                    assert "memory" in observed.stderr.lower() and "wasm trap" not in observed.stderr.lower(), observed.stderr
                    return {"stderr": observed.stderr, "exit_code": observed.returncode}
                record(f"{name}/{engine}", exhausted)

    current_hash = hashlib.sha256(args.goose.read_bytes()).hexdigest()
    record("compiler-identity", lambda: {"sha256": compiler_hash} if current_hash == compiler_hash else
           (_ for _ in ()).throw(AssertionError("compiler changed during qualification")))
    failures = sum(row["status"] != "pass" for row in rows)
    report = {"schema": "goose-dynamic-qualification-v1", "compiler_sha256": compiler_hash,
              "native_compiler_sha256": hashlib.sha256(native.read_bytes()).hexdigest(),
              "observations": len(rows), "failures": failures, "results": rows}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"{len(rows) - failures}/{len(rows)} checks passed; {output / 'report.json'}")
    return int(failures != 0)


if __name__ == "__main__":
    sys.exit(main())
