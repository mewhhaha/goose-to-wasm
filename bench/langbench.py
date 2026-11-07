#!/usr/bin/env python3
"""Local single-thread langbench Mandelbrot trial; not an official Docker campaign.

Fresh processes, one external warmup per cell/profile, no in-program warmup.
The unchanged C reference includes pthread spawn/join and an atomic row queue;
the scalar Goose port has neither. This trial makes no parallel runtime claims.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import random
import re
import shutil
import signal
import statistics
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import process

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "bench/langbench"
REVISION = "f00181bd514606b140bf76ac461694a438c88270"
UPSTREAM_GOOSE_REVISION = "2e2bedef5b980bf013cac5aaa0095bfea64e5569"
CELLS = ("c-gcc", "c-clang", "upstream-goose-native", "goose-native",
         "goose-wasm-wasmtime", "goose-wasm-v8")
NATIVE_FLAGS = ["-O3", "-march=x86-64-v3", "-ffp-contract=off",
                "-fno-fast-math", "-fno-strict-aliasing"]
C_FLAGS = ["-O3", "-march=x86-64-v3", "-ffp-contract=off", "-fno-fast-math", "-std=c11"]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_manifest() -> dict:
    manifest = json.loads((DATA / "manifest.json").read_text())
    if manifest["upstream"]["revision"] != REVISION:
        raise ValueError("langbench revision differs from the harness pin")
    for name, digest in manifest["vendored_sha256"].items():
        if sha256(DATA / name) != digest:
            raise ValueError(f"pinned upstream input changed: {name}")
    official = manifest["profiles"]["official"]
    if official != {"n": 2048, "max_iter": 1000, "threads": 1, "checksum": 1038538536}:
        raise ValueError("official workload parameters/checksum changed")
    return manifest


def parse_result(stdout: str, returncode: int, expected: int, cell: str) -> dict:
    if returncode:
        raise ValueError(f"process exit {returncode}")
    pattern = r"([0-9]+) ([0-9]+)\n?"
    if not cell.startswith("c-"):
        pattern = r"([0-9]+)\n([0-9]+)\n?"
    match = re.fullmatch(pattern, stdout)
    if match is None:
        raise ValueError("expected exactly checksum and nanoseconds in the cell's protocol")
    checksum, elapsed = map(int, match.groups())
    if checksum != expected:
        raise ValueError(f"checksum {checksum} != expected {expected}")
    if elapsed <= 0:
        raise ValueError("nonpositive timed region")
    return {"checksum": checksum, "timed_region_ns": elapsed}


def summarize(values: list[float]) -> dict | None:
    if not values:
        return None
    median = statistics.median(values)
    return {"n": len(values), "median": median,
            "mad": statistics.median(abs(value - median) for value in values),
            "min": min(values), "max": max(values), "samples": values}


def summaries(report: dict) -> list[dict]:
    """Keep every requested row visible; partial or failed rows never qualify."""
    rows = []
    for profile in report["profiles"]:
        for cell in CELLS:
            builds = [b for b in report["builds"] if b["cell"] == cell]
            runs = [r for r in report["runs"] if r["profile"] == profile and r["cell"] == cell]
            measured = [r for r in runs if r["phase"] == "measurement"]
            warmups = [r for r in runs if r["phase"] == "warmup"]
            good = [r for r in measured if r["status"] == "passed"]
            qualified = (len(builds) == report["compile_samples"]
                         and sorted(b["round"] for b in builds) == list(range(report["compile_samples"]))
                         and all(b["status"] == "passed" for b in builds)
                         and len(runs) == report["samples"] + 1
                         and len(warmups) == 1 and warmups[0]["round"] == 0
                         and len(measured) == report["samples"]
                         and sorted(r["round"] for r in measured) == list(range(report["samples"]))
                         and all(r["status"] == "passed" for r in runs))
            rows.append({"profile": profile, "cell": cell, "qualified": qualified,
                         "expected_samples": report["samples"], "valid_samples": len(good),
                         "build_wall_seconds": summarize([b["wall_seconds"] for b in builds
                                                           if b["status"] == "passed"]),
                         "timed_region_ns": summarize([r["timed_region_ns"] for r in good]),
                         "process_wall_seconds": summarize([r["wall_seconds"] for r in good])})
    return rows


def save(report: dict, output: Path) -> None:
    report["summary"] = summaries(report)
    temporary = output / "report.json.tmp"
    temporary.write_text(json.dumps(report, indent=2) + "\n")
    temporary.replace(output / "report.json")


def invoke(command, *, stdin=None, timeout=600, cpu=None) -> dict:
    command = list(map(str, command))
    if cpu is not None:
        command = ["taskset", "-c", str(cpu), *command]
    record = {"command": command, "stdin": stdin, "started_utc": datetime.now(timezone.utc).isoformat(),
              "status": "failed", "pid": None, "stdout": "", "stderr": ""}
    started = time.perf_counter()
    try:
        with process.Process(command, cwd=ROOT, text=True, stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True) as child:
            record["pid"] = child.pid
            try:
                stdout, stderr = child.communicate(stdin, timeout=timeout)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                stdout, stderr = child.communicate()
                record["error"] = f"timeout after {timeout}s"
            except BaseException:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                child.communicate()
                raise
            record.update(stdout=stdout, stderr=stderr, exit_code=child.returncode)
            if child.returncode == 0 and "error" not in record:
                record["status"] = "passed"
    except OSError as error:
        record.update(error=str(error), exit_code=None)
    record["wall_seconds"] = time.perf_counter() - started
    return record


def fingerprint(paths) -> dict:
    result = {}
    for path in paths:
        path = Path(path).resolve()
        if path.is_dir():
            result.update(fingerprint(sorted(p for p in path.rglob("*") if p.is_file())))
        elif path.is_file():
            result[str(path)] = {"sha256": sha256(path), "bytes": path.stat().st_size}
        else:
            result[str(path)] = {"missing": True}
    return result


def machine_state() -> dict:
    state = {"utc": datetime.now(timezone.utc).isoformat(), "uname": platform.uname()._asdict(),
             "parent_pid": os.getpid(), "parent_affinity": sorted(os.sched_getaffinity(0)),
             "load_average": os.getloadavg(), "cpu_count": os.cpu_count()}
    state["cpu_ticks"] = {line.split()[0]: list(map(int, line.split()[1:]))
                          for line in Path("/proc/stat").read_text().splitlines()
                          if re.match(r"cpu[0-9]+ ", line)}
    state["smt_siblings"] = {str(p): p.read_text().strip() for p in
                             sorted(Path("/sys/devices/system/cpu").glob("cpu*/topology/thread_siblings_list"))}
    state["commands"] = [invoke(cmd, timeout=30) for cmd in (
        ["lscpu"], ["ps", "-eo", "pid,ppid,psr,pcpu,pmem,etimes,comm", "--sort=-pcpu"],
        ["git", "status", "--short"], ["git", "rev-parse", "HEAD"], ["git", "diff", "--stat"])]
    state["cpu_policy"] = {str(p): p.read_text().strip() for p in
                           sorted(Path("/sys/devices/system/cpu").glob("cpu*/cpufreq/scaling_governor"))}
    return state


def metadata(args) -> dict:
    tools = {"gcc": shutil.which("gcc"), "clang": shutil.which("clang"),
             "node": shutil.which("node"), "python": sys.executable,
             "goose": str(args.goose), "upstream_goose": str(args.upstream_goose)}
    info = {"tools": tools, "native_c_flags": NATIVE_FLAGS, "reference_c_flags": C_FLAGS,
            "goose_semantic_optimization": "-O2 (inlining level); emitted C separately compiled at -O3",
            "versions": [invoke(cmd, timeout=30) for cmd in (
        ["gcc", "--version"], ["clang", "--version"], ["node", "-p", "JSON.stringify(process.versions)"],
        [sys.executable, "--version"], [args.goose, "--help"], [args.upstream_goose, "--help"],
        ["ldd", args.upstream_goose], ["ldd", args.goose])],
        "upstream_goose_revision": UPSTREAM_GOOSE_REVISION,
        "upstream_goose_revision_evidence": "caller-supplied compiler; inspect compiler hash and preparation evidence"}
    inputs = [Path(__file__), Path(process.__file__), DATA, ROOT / "bench/host_input.c",
              ROOT / "scripts/run_wasm.mjs", ROOT / "scripts/run_wasmtime.py",
              ROOT / "scripts/goose_wasm.py", ROOT / "toolchain.json",
              ROOT / "selfhost/bootstrap.py", *sorted((ROOT / "selfhost").glob("*.goose")),
              ROOT / "native", args.stdlib, args.upstream_stdlib,
              args.goose, args.upstream_goose, *[Path(p) for p in tools.values() if p]]
    try:
        import wasmtime._ffi as ffi
        library = Path(ffi.dll._name).resolve()
        inputs.append(library)
        info["wasmtime"] = {"package_version": importlib.metadata.version("wasmtime"),
                            "library": str(library), "optimization": "cranelift speed"}
    except (ImportError, OSError) as error:
        info["wasmtime"] = {"error": str(error)}
    info["fingerprints"] = fingerprint(inputs)
    return info


def build_commands(cell: str, destination: Path, args) -> tuple[list[list], Path]:
    c_source = DATA / "mandelbrot.c"
    goose_source = DATA / "mandelbrot.goose"
    artifact = destination / "program"
    if cell.startswith("c-"):
        compiler = cell.removeprefix("c-")
        return [[compiler, *C_FLAGS, c_source, "-pthread", "-o", artifact]], artifact
    if cell.startswith("goose-wasm-"):
        artifact = destination / "program.wasm"
        return [[args.goose, goose_source, "--target", "wasm-direct", "--stdlib", args.stdlib,
                 "-O2", "-o", artifact]], artifact
    generated = destination / "program.c"
    command = [args.goose, goose_source, "--target", "native", "--stdlib", args.stdlib,
               "-O2", "-o", generated]
    if cell == "upstream-goose-native":
        command = [args.upstream_goose, goose_source, "--stdlib", args.upstream_stdlib,
                   "-O2", "--standalone", "-o", generated]
    return [command, ["gcc", *NATIVE_FLAGS, generated, ROOT / "bench/host_input.c",
                      "-lm", "-ldl", "-pthread", "-rdynamic", "-o", artifact]], artifact


def trial(args) -> int:
    manifest = load_manifest()
    for profile in args.profiles:
        if profile not in manifest["profiles"]:
            raise ValueError(f"unknown profile {profile}")
    if len(set(args.profiles)) != len(args.profiles):
        raise ValueError("profiles must be distinct")
    if args.cpu is not None and args.cpu not in os.sched_getaffinity(0):
        raise ValueError("requested CPU is outside the process affinity")
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {"schema": "goose-langbench-local-v1", "status": "running",
              "scope": __doc__, "manifest": manifest,
              "profiles": args.profiles, "samples": args.samples, "compile_samples": args.compile_samples,
              "cpu": args.cpu, "seed": args.seed, "builds": [], "runs": [],
              "limitations": ["Local shared-host trial, not an official langbench Docker campaign.",
                              "C includes one pthread spawn/join and an atomic row queue; Goose is scalar without either.",
                              "Timed regions exclude input, output and startup; process wall includes taskset and engine startup.",
                              "No in-program warmup; each process computes the kernel once, including fresh JIT tiering.",
                              "Host may run other repository work; process snapshots disclose observed background load.",
                              "Compilation is uncached output generation with filesystem/toolchain caches allowed; no cold-cache claim.",
                              "Statistics report median/MAD/min/max; official langbench campaigns publish minimum-of-N results.",
                              "Small differences and shared-host variation do not establish a backend advantage."],
              "machine_before": machine_state(), "metadata": metadata(args)}
    save(report, output)
    rng = random.Random(args.seed)
    artifacts = {}
    for round_index in range(args.compile_samples):
        cells = list(CELLS)
        rng.shuffle(cells)
        for cell in cells:
            destination = output / "builds" / cell / str(round_index)
            destination.mkdir(parents=True)
            commands, artifact = build_commands(cell, destination, args)
            record = {"cell": cell, "round": round_index, "commands": [], "status": "passed"}
            started = time.perf_counter()
            for command in commands:
                result = invoke(command, cpu=args.cpu)
                record["commands"].append(result)
                if result["status"] != "passed":
                    record["status"] = "failed"
                    break
            record["wall_seconds"] = time.perf_counter() - started
            if record["status"] == "passed" and artifact.is_file():
                record["artifacts"] = fingerprint(destination.iterdir())
                artifacts[cell] = artifact
            else:
                record["status"] = "failed"
            report["builds"].append(record)
            save(report, output)
            print(f"build {round_index + 1}/{args.compile_samples} {cell}: {record['status']}", flush=True)
    for phase, rounds in (("warmup", 1), ("measurement", args.samples)):
        for round_index in range(rounds):
            jobs = [(profile, cell) for profile in args.profiles for cell in CELLS]
            rng.shuffle(jobs)
            for profile, cell in jobs:
                parameters = manifest["profiles"][profile]
                values = [parameters["n"], parameters["max_iter"], parameters["threads"]]
                record = {"profile": profile, "cell": cell, "phase": phase, "round": round_index,
                          "expected_checksum": parameters["checksum"], "status": "failed"}
                if cell not in artifacts:
                    record["error"] = "no successful build; requested cell retained"
                else:
                    artifact = artifacts[cell]
                    command = [artifact]
                    stdin = " ".join(map(str, values)) + "\n"
                    if cell.startswith("c-"):
                        command += list(map(str, values))
                        stdin = None
                    if cell == "goose-wasm-v8":
                        command = ["node", ROOT / "scripts/run_wasm.mjs", artifact]
                    if cell == "goose-wasm-wasmtime":
                        command = [sys.executable, ROOT / "scripts/run_wasmtime.py", artifact]
                    record.update(invoke(command, stdin=stdin, cpu=args.cpu))
                    try:
                        if record["status"] != "passed":
                            raise ValueError(record.get("error", f"exit {record['exit_code']}"))
                        if record["stderr"]:
                            raise ValueError("unexpected stderr; raw output retained")
                        record.update(parse_result(record["stdout"], record["exit_code"], parameters["checksum"], cell))
                    except ValueError as error:
                        record.update(status="failed", error=str(error))
                report["runs"].append(record)
                save(report, output)
                print(f"{phase} {round_index + 1}/{rounds} {profile} {cell}: {record['status']}", flush=True)
    report["machine_after"] = machine_state()
    wasm_hashes = {sha256(artifact) for cell, artifact in artifacts.items() if cell.startswith("goose-wasm-")}
    all_wasm_hashes = {entry["sha256"] for build in report["builds"]
                      if build["cell"].startswith("goose-wasm-")
                      for path, entry in build.get("artifacts", {}).items() if path.endswith(".wasm")}
    report["identical_wasm_artifacts"] = len(wasm_hashes) == 1 and len(all_wasm_hashes) == 1
    report["cpu_activity"] = {}
    for cpu, before in report["machine_before"]["cpu_ticks"].items():
        after = report["machine_after"]["cpu_ticks"].get(cpu)
        if after is None:
            continue
        delta = [end - start for start, end in zip(before, after)]
        # Linux guest ticks are already counted in user/nice; exclude their duplicate.
        total = sum(delta[:8])
        idle = delta[3] + delta[4]
        report["cpu_activity"][cpu] = {"ticks_delta": delta, "total_ticks": total,
                                       "busy_fraction": (total - idle) / max(total, 1)}
    report["status"] = "passed"
    if not all(row["qualified"] for row in summaries(report)) or not report["identical_wasm_artifacts"]:
        report["status"] = "failed"
    save(report, output)
    return int(report["status"] != "passed")


def positive(text: str) -> int:
    value = int(text)
    if value < 1:
        raise argparse.ArgumentTypeError("must be positive")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profiles", nargs="+", default=["small", "medium", "official"])
    parser.add_argument("--samples", type=positive, default=7)
    parser.add_argument("--compile-samples", type=positive, default=5)
    parser.add_argument("--cpu", type=int)
    parser.add_argument("--seed", type=int, default=20261107)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--goose", type=Path, default=ROOT / "build/bin/goose")
    parser.add_argument("--stdlib", type=Path, default=ROOT / "build/bin/stdlib")
    parser.add_argument("--upstream-goose", type=Path, required=True)
    parser.add_argument("--upstream-stdlib", type=Path, required=True)
    args = parser.parse_args()
    try:
        return trial(args)
    except (OSError, ValueError) as error:
        parser.exit(2, f"langbench trial: {error}\n")


if __name__ == "__main__":
    sys.exit(main())
