#!/usr/bin/env python3
"""Qualify the unchanged LangArena Sieve kernel using an isolated entrypoint.

This does not qualify the original benchmark driver or its other 49 tasks.
The harness supplies runtime configuration and replaces the unused bench module.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / "bench/langarena"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=ROOT / "build/bin/goose")
    parser.add_argument("--upstream", type=Path, default=ROOT / "build/langarena-upstream")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/isolated-sieve")
    parser.add_argument("--profiles", nargs="+", choices=("test", "run"), default=["test"])
    parser.add_argument("--node", default="node")
    args = parser.parse_args()
    if "run" in args.profiles and "test" not in args.profiles:
        parser.error("production qualification also requires --profiles test")
    compiler = args.goose.resolve()
    manifest = json.loads((PROFILE / "manifest.json").read_text())
    case = next(task for task in manifest["cases"] if task["name"] == "Etc::Sieve")
    kernel = args.upstream.resolve() / "goose/src/sieve.goose"
    expected_hash = manifest["upstream"]["source_sha256"]["goose/src/sieve.goose"]
    if not kernel.is_file() or digest(kernel) != expected_hash:
        parser.error("missing or changed pinned kernel; run bench/langarena.py fetch first")
    output = args.output_dir.resolve()
    protected = [kernel, compiler, PROFILE / "manifest.json", PROFILE / "isolated/sieve.goose", PROFILE / "isolated/bench.goose"]
    if any(path.resolve().is_relative_to(output) for path in protected):
        parser.error("output directory contains an input")
    def guard(path):
        if any(path.resolve() == source.resolve() or (path.exists() and path.samefile(source)) for source in protected):
            parser.error(f"output would overwrite an input: {path}")
    def write(path, text):
        guard(path); path.write_text(text)
    output.mkdir(parents=True, exist_ok=True)
    for name, source in (("sieve.goose", kernel), ("main.goose", PROFILE / "isolated/sieve.goose"),
                         ("bench.goose", PROFILE / "isolated/bench.goose")):
        target = output / name
        guard(target)
        shutil.copyfile(source, target)
    compiler_hash = digest(compiler)
    rows = []
    for level in (0, 2):
        for backend in ("native", "c-wasm", "direct"):
            directory = output / f"O{level}" / backend
            directory.mkdir(parents=True, exist_ok=True)
            artifact = directory / ("program.bin" if backend == "native" else "program.wasm")
            guard(artifact)
            build = [sys.executable, str(ROOT / "scripts/goose_wasm.py"), "build", str(output / "main.goose"),
                     "--backend", backend, "--goose", str(compiler), f"-O{level}", "--no-cache", "--offline", "-o", str(artifact)]
            if backend != "direct":
                build += ["--c-source", str(ROOT / "bench/host_input.c")]
            compiled = subprocess.run(build, capture_output=True, text=True, timeout=180, cwd=ROOT)
            write(directory / "compile.log", compiled.stdout + compiled.stderr)
            if compiled.returncode:
                rows.append({"optimization": level, "backend": backend, "status": "fail", "build_command": build,
                             "error": (compiled.stdout + compiled.stderr)[-4000:]})
                continue
            artifact_hash = digest(artifact)
            for profile in args.profiles:
                config = case[profile]
                warmup = config.get("warmup_iterations", max(int(config["iterations"] * 0.2), 1))
                stdin = f"{config['limit']} {config['iterations'] + warmup}\n"
                for engine in (("native",) if backend == "native" else ("v8", "wasmtime")):
                    command = ([str(artifact)] if engine == "native" else
                               [args.node, str(ROOT / "scripts/run_wasm.mjs"), str(artifact)] if engine == "v8" else
                               [sys.executable, str(ROOT / "scripts/run_wasmtime.py"), str(artifact)])
                    observed = subprocess.run(command, input=stdin, capture_output=True, text=True, timeout=600, cwd=directory)
                    passed = observed.returncode == 0 and observed.stdout == f"{config['checksum']}\n"
                    write(directory / f"{profile}-{engine}.log", observed.stdout + observed.stderr)
                    rows.append({"optimization": level, "backend": backend, "engine": engine, "profile": profile,
                                 "limit": config["limit"], "iterations": config["iterations"], "warmup": warmup,
                                 "status": "pass" if passed else "fail", "stdin": stdin, "stdout": observed.stdout,
                                 "stderr": observed.stderr, "exit_code": observed.returncode, "artifact_sha256": artifact_hash,
                                 "build_command": build, "run_command": command})
                    print(("PASS" if passed else "FAIL"), f"O{level}", backend, engine, profile, flush=True)
    unchanged = digest(compiler) == compiler_hash
    failures = sum(row["status"] != "pass" for row in rows) + int(not unchanged)
    report = {"schema": "goose-isolated-original-kernel-v1", "full_suite_qualified": False,
              "scope": "Unchanged Sieve kernel; isolated runtime-input entrypoint and unused configuration stub.",
              "catalog_tasks": 50, "isolated_tasks": 1, "upstream_revision": manifest["upstream"]["revision"],
              "kernel_sha256": expected_hash, "compiler_sha256": compiler_hash, "compiler_unchanged": unchanged,
              "entrypoint_sha256": digest(output / "main.goose"), "configuration_stub_sha256": digest(output / "bench.goose"),
              "toolchain": json.loads((ROOT / "toolchain.json").read_text()),
              "observations": len(rows), "failures": failures, "results": rows}
    write(output / "report.json", json.dumps(report, indent=2) + "\n")
    print(f"{len(rows) - sum(row['status'] != 'pass' for row in rows)}/{len(rows)} observations passed; {output / 'report.json'}")
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
