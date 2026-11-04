#!/usr/bin/env python3
"""Compile the example catalog and compare each execution with its golden output."""
import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
HERE = ROOT / "examples"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def execute(command, directory, label):
    directory.mkdir(parents=True, exist_ok=True)
    command = [str(x) for x in command]
    try:
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
        code, stdout, stderr = result.returncode, result.stdout, result.stderr
    except (OSError, subprocess.TimeoutExpired) as error:
        code, stdout, stderr = -1, "", str(error)
    (directory / (label + ".command.json")).write_text(json.dumps(command, indent=2) + "\n")
    (directory / (label + ".stdout")).write_text(stdout)
    (directory / (label + ".stderr")).write_text(stderr)
    return {"command": command, "exit_code": code,
            "stdout_sha256": hashlib.sha256(stdout.encode()).hexdigest(), "stderr": stderr}, stdout


def main():
    manifest_path = HERE / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    assert manifest["schema"] == "goose-examples-v1"
    catalog = manifest["examples"]
    names = [entry["name"] for entry in catalog]
    assert names and len(names) == len(set(names))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("names", nargs="*", help="example names; omit to check the complete catalog")
    parser.add_argument("--goose", type=Path, default=ROOT / "build/bin/goose")
    parser.add_argument("--backends", nargs="+", choices=("direct", "native"), default=["direct"])
    parser.add_argument("--engines", nargs="+", choices=("v8", "wasmtime"), default=["v8", "wasmtime"])
    parser.add_argument("--levels", nargs="+", type=int, choices=(0, 1, 2), default=[2])
    parser.add_argument("--node", default="node")
    parser.add_argument("--cc", default=os.environ.get("CC", "cc"))
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/examples")
    args = parser.parse_args()
    unknown = set(args.names) - set(names)
    if unknown:
        parser.error("unknown examples: " + ", ".join(sorted(unknown)))
    if not args.goose.is_file():
        parser.error("compiler not found; run scripts/bootstrap.py first")
    selected = [entry for entry in catalog if not args.names or entry["name"] in args.names]
    inputs = [manifest_path, Path(__file__).resolve(), ROOT / "scripts/goose_wasm.py",
              ROOT / "scripts/run_wasm.mjs", ROOT / "scripts/run_wasmtime.py",
              ROOT / "toolchain.json", ROOT / "LICENSE", ROOT / "selfhost/bootstrap.py",
              ROOT / "bootstrap/seed.json", ROOT / "bootstrap/seed.c.gz", ROOT / "bootstrap/sources.tar.gz"]
    inputs += sorted((ROOT / "selfhost").glob("*.goose"))
    for entry in selected:
        source, expected = HERE / entry["file"], HERE / entry["expected"]
        inputs.extend((source, expected))
        origin = entry.get("upstream")
        if origin and origin["unchanged"]:
            assert sha256(source) == origin["sha256"], entry["name"]
            assert sha256(expected) == origin["expected_sha256"], entry["name"]
    stdlib = args.goose.resolve().parent / "stdlib"
    inputs.extend(sorted(stdlib.rglob("*.goose")))
    hashes = {str(path.resolve()): sha256(path) for path in inputs}
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    identities = {}
    version_commands = {"node": [args.node, "-p", "JSON.stringify(process.versions)"]}
    if "native" in args.backends:
        version_commands["cc"] = [args.cc, "--version"]
    for name, command in version_commands.items():
        observation, stdout = execute(command, output / "identities", name)
        identities[name] = {**observation, "stdout": stdout}
    try:
        identities["wasmtime"] = importlib.metadata.version("wasmtime")
    except importlib.metadata.PackageNotFoundError:
        identities["wasmtime"] = "unavailable"
    report = {"schema": "goose-examples-qualification-v1", "status": "running",
              "compiler_sha256": sha256(args.goose), "upstream": manifest["upstream"],
              "configuration": {**vars(args), "goose": str(args.goose.resolve()), "output_dir": str(output)},
              "input_sha256": hashes, "identities": identities, "builds": [], "executions": []}
    report_path = output / "report.json"

    def checkpoint():
        report_path.write_text(json.dumps(report, indent=2, default=str) + "\n")

    checkpoint()
    native_outputs = {}
    for level in dict.fromkeys(args.levels):
        for backend in ("native", "direct"):
            if backend not in args.backends:
                continue
            for entry in selected:
                name = entry["name"]
                directory = output / ("O" + str(level)) / backend / name
                suffix = ".wasm"
                if backend == "native":
                    suffix = ".bin"
                artifact = directory / (name + suffix)
                command = [sys.executable, ROOT / "scripts/goose_wasm.py", "build", HERE / entry["file"],
                           "--goose", args.goose.resolve(), "--backend", backend, "-O" + str(level),
                           "--no-cache", "-o", artifact]
                if backend == "native":
                    command += ["--cc", args.cc]
                built, _ = execute(command, directory, "build")
                build = {"name": name, "backend": backend, "level": level, **built, "status": "failed"}
                if built["exit_code"] == 0 and artifact.is_file():
                    build.update(status="passed", artifact_sha256=sha256(artifact), module_bytes=artifact.stat().st_size)
                report["builds"].append(build)
                engines = args.engines
                if backend == "native":
                    engines = ["native"]
                for engine in dict.fromkeys(engines):
                    row = {"name": name, "backend": backend, "engine": engine, "level": level, "status": "failed"}
                    if build["status"] != "passed":
                        row["error"] = "compilation failed; see " + str(directory / "build.stderr")
                    else:
                        command = [artifact]
                        if engine == "v8":
                            command = [args.node, ROOT / "scripts/run_wasm.mjs", artifact]
                        if engine == "wasmtime":
                            command = [sys.executable, ROOT / "scripts/run_wasmtime.py", artifact]
                        observed, stdout = execute(command, directory, engine)
                        row.update(observed, artifact_sha256=build["artifact_sha256"])
                        expected = (HERE / entry["expected"]).read_text()
                        if observed["exit_code"] != 0:
                            row["error"] = "execution failed"
                        elif stdout != expected:
                            row["error"] = "stdout differs from " + entry["expected"]
                        elif backend != "native" and (name, level) in native_outputs and stdout != native_outputs[(name, level)]:
                            row["error"] = "stdout differs from native C"
                        else:
                            row["status"] = "passed"
                            if backend == "native":
                                native_outputs[(name, level)] = stdout
                    report["executions"].append(row)
                    print(row["status"].upper(), "O" + str(level), backend + "/" + engine, name, flush=True)
                    if row["status"] != "passed":
                        print(row["error"], row.get("stderr", "")[-1200:], flush=True)
                    checkpoint()
    unchanged = all(sha256(Path(path)) == value for path, value in hashes.items())
    report["input_hashes_still_match"] = unchanged
    report["compiler_hash_still_matches"] = sha256(args.goose) == report["compiler_sha256"]
    passed = unchanged and report["compiler_hash_still_matches"] and all(row["status"] == "passed" for row in report["builds"] + report["executions"])
    report["status"] = "passed"
    if not passed:
        report["status"] = "failed"
    checkpoint()
    print(report["status"], len(report["executions"]), "executions;", report_path)
    return int(not passed)


if __name__ == "__main__":
    sys.exit(main())
