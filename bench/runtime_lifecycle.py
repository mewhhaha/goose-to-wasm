#!/usr/bin/env python3
"""Measure Wasmtime compilation and request lifecycle costs on the example catalog."""

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
import time
import tomllib

import process
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from wasmtime_session import RuntimeSession

MODES = ("ordinary", "cache-miss", "cache-hit", "precompiled", "native-C", "worker-hit")
EXPECTED_EXAMPLES = 10


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def summary(values):
    middle = statistics.median(values)
    return {"n": len(values), "median_seconds": middle,
            "mad_seconds": statistics.median(abs(value - middle) for value in values),
            "samples_seconds": values}


def run_command(command, *, stdin=b"", cwd=ROOT):
    started = time.perf_counter_ns()
    result = process.run([str(value) for value in command], input=stdin,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            cwd=cwd, check=False)
    wall_ns = time.perf_counter_ns() - started
    return result, wall_ns


def record_command(command, result):
    return {"command": [str(value) for value in command], "returncode": result.returncode,
            "stdout": result.stdout.decode(errors="replace"),
            "stderr": result.stderr.decode(errors="replace")}


def metadata(args, example_report, examples):
    example_build_report = json.loads(example_report.read_text())
    host = args.host.resolve()
    host_metadata_path = host.with_suffix(".json")
    host_metadata = json.loads(host_metadata_path.read_text())
    host_sha = digest(host)
    if host_metadata.get("schema") != "goose-native-wasmtime-host-v1":
        raise ValueError("native host metadata schema is invalid")
    if host_metadata.get("host_sha256") != host_sha:
        raise ValueError("native host metadata does not match the selected CLI")
    affinity = None
    if hasattr(os, "sched_getaffinity"):
        affinity = sorted(os.sched_getaffinity(0))
    input_paths = {str(Path(__file__).resolve()), str(Path(process.__file__).resolve()),
                   str((ROOT / "scripts/wasmtime_session.py").resolve()),
                   str((ROOT / "host/wasmtime.cpp").resolve()), str((ROOT / "host/wasmtime-sdk.json").resolve()),
                   str(example_report.resolve()), str(host_metadata_path),
                   str((ROOT / "examples/manifest.json").resolve()), str(host)}
    for path in host_metadata.get("input_sha256", {}):
        input_paths.add(str(Path(path).resolve()))
    sdk_library = Path(host_metadata["library"]).resolve()
    sdk_archive = Path(host_metadata["sdk_archive"]).resolve()
    input_paths.add(str(sdk_library))
    input_paths.add(str(sdk_archive))
    for path in example_build_report.get("environment", {}).get("input_sha256", {}):
        input_paths.add(str(Path(path).resolve()))
    compiler_path = Path(report_compiler_path(example_report)).resolve()
    if compiler_path.is_file():
        input_paths.add(str(compiler_path))
    for example in examples:
        input_paths.add(str((ROOT / "examples" / example["file"]).resolve()))
        input_paths.add(str((ROOT / "examples" / example["expected"]).resolve()))
    input_hashes = {path: digest(path) for path in sorted(input_paths) if Path(path).is_file()}
    for path, expected_hash in host_metadata.get("input_sha256", {}).items():
        resolved = str(Path(path).resolve())
        if input_hashes.get(resolved) != expected_hash:
            raise ValueError("native host build input changed since host build: " + resolved)
    for path, expected_hash in example_build_report.get("environment", {}).get("input_sha256", {}).items():
        resolved = str(Path(path).resolve())
        if input_hashes.get(resolved) != expected_hash:
            raise ValueError("example build input changed since compilation: " + resolved)
    compiler = None
    if compiler_path.is_file():
        compiler = {"path": str(compiler_path), "sha256": digest(compiler_path)}
    return {"platform": platform.platform(), "machine": platform.machine(),
            "cpu": next((line.partition(":")[2].strip() for line in Path("/proc/cpuinfo").read_text().splitlines()
                         if line.startswith("model name")), "unknown"),
            "logical_cpu_count": os.cpu_count(), "cpu_affinity": affinity,
            "python": sys.version, "host_build": host_metadata,
            "host_build_metadata_path": str(host_metadata_path),
            "host_build_metadata_sha256": digest(host_metadata_path),
            "sdk_library": {"path": str(sdk_library), "sha256": digest(sdk_library)},
            "sdk_archive": {"path": str(sdk_archive), "sha256": digest(sdk_archive)},
            "native_host": {"path": str(host), "sha256": host_sha},
            "machine_label": args.machine_label,
            "compiler": compiler,
            "compiler_source_identity": example_build_report.get("environment", {}).get("compiler_source_identity"),
            "example_build_report_sha256": digest(example_report),
            "input_sha256": input_hashes}


def report_compiler_path(report_path):
    report = json.loads(Path(report_path).read_text())
    return report.get("configuration", {}).get("goose", ROOT / "build/bin/goose")


def choose_artifacts(report, names):
    if report.get("schema") != "goose-example-benchmarks-v1":
        raise ValueError("example report schema is not goose-example-benchmarks-v1")
    builds = {}
    for row in report.get("observations", []):
        if row.get("kind") != "build" or row.get("status") != "passed":
            continue
        key = (row.get("name"), row.get("backend"))
        if key in {(name, backend) for name in names for backend in ("direct", "native")}:
            builds[key] = row
    artifacts = {}
    for name in names:
        for backend in ("direct", "native"):
            row = builds.get((name, backend))
            if row is None:
                raise ValueError("missing successful " + backend + " build for " + name)
            path = Path(row["artifact"]).resolve()
            if not path.is_file() or digest(path) != row["artifact_sha256"]:
                raise ValueError("artifact missing or changed: " + str(path))
            artifacts[name, backend] = {"path": path, "sha256": row["artifact_sha256"],
                                        "build_observation": row}
    return artifacts


def expected_bytes(example):
    return (ROOT / "examples" / example["expected"]).read_bytes()


def check_output(actual, expected, name):
    if actual != expected:
        raise ValueError("golden output mismatch: " + name)


def cache_config(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("[cache]\ndirectory = " + json.dumps(str(path.parent / "entries")) + "\n")
    parsed = tomllib.loads(path.read_text())
    if Path(parsed["cache"]["directory"]) != path.parent / "entries":
        raise ValueError("cache config did not round trip")
    return path


def timed_fresh(args, example, mode, artifact, expected, root, round_number):
    command = [args.host.resolve()]
    if mode in ("ordinary", "precompiled"):
        command.append("--no-cache")
    cache_state_expected = None
    cache_config_identity = None
    if mode == "cache-miss":
        cfg = cache_config(root / "cache.toml")
        command += ["--cache-config", cfg]
        cache_state_expected = "miss"
        cache_config_identity = {"path": str(cfg), "sha256": digest(cfg)}
    elif mode == "cache-hit":
        cfg = root / "cache.toml"
        command += ["--cache-config", cfg]
        cache_state_expected = "hit"
        cache_config_identity = {"path": str(cfg), "sha256": digest(cfg)}
    elif mode == "precompiled":
        command += ["--precompiled"]
    command += [artifact["path"]]
    result, wall_ns = run_command(command)
    row = {"name": example["name"], "mode": mode, "round": round_number,
            "wall_ns": wall_ns, "wall_seconds": wall_ns / 1e9, "cache_hit": None,
            "cache_state_expected": cache_state_expected,
            "cache_config": cache_config_identity,
            "module_cache_hit_reported": None,
            "golden_match": result.stdout == expected, "stderr_empty": not result.stderr,
            **record_command(command, result)}
    row["status"] = "failed"
    if result.returncode == 0 and row["golden_match"]:
        row["status"] = "passed"
    return row


def worker_start(args, example, artifact, expected, root):
    started = time.perf_counter_ns()
    session = RuntimeSession(args.host.resolve())
    startup_ns = time.perf_counter_ns() - started
    first_started = time.perf_counter_ns()
    first = session.run(artifact["path"])
    first_wall_ns = time.perf_counter_ns() - first_started
    check_output(first.stdout, expected, example["name"])
    if first.returncode or first.stderr or first.module_cache_hit:
        session.close()
        raise RuntimeError("worker cold request failed or reported unexpected stderr/cache hit: " +
                           first.stderr.decode(errors="replace"))
    lifecycle = {"startup_ns": startup_ns, "first_request_ns": first_wall_ns,
                 "first_cache_hit": first.module_cache_hit, "first_prepare_ns": first.prepare_ns,
                 "first_start_ns": first.start_ns,
                 "first_stdout": first.stdout.decode(errors="replace"),
                 "first_stderr": first.stderr.decode(errors="replace"),
                 "first_returncode": first.returncode, "first_stderr_empty": not first.stderr,
                 "resident_process_count": 1,
                 "session_command": [str(args.host.resolve()), "--serve", "--no-cache"]}
    return session, lifecycle


def worker_request(session, example, artifact, expected, index, command):
    request_started = time.perf_counter_ns()
    result = session.run(artifact["path"])
    wall_ns = time.perf_counter_ns() - request_started
    check_output(result.stdout, expected, example["name"])
    if result.returncode or result.stderr or not result.module_cache_hit:
        raise RuntimeError("worker request failed: " + result.stderr.decode(errors="replace"))
    return {"name": example["name"], "mode": "worker-hit", "round": index,
            "wall_ns": wall_ns, "wall_seconds": wall_ns / 1e9,
            "cache_hit": result.module_cache_hit, "prepare_ns": result.prepare_ns,
            "start_ns": result.start_ns, "stdout_sha256": hashlib.sha256(result.stdout).hexdigest(),
            "stdout": result.stdout.decode(errors="replace"),
            "stderr": result.stderr.decode(errors="replace"), "stderr_empty": not result.stderr,
            "returncode": result.returncode,
            "process_command": command, "request_module": str(artifact["path"])}


def cache_manifest(output):
    entries = {}
    for config_path in output.rglob("*cache.toml"):
        entries[str(config_path)] = {"bytes": config_path.stat().st_size,
                                     "sha256": digest(config_path), "kind": "config"}
        settings = tomllib.loads(config_path.read_text())
        cache_dir = Path(settings["cache"]["directory"])
        if not cache_dir.is_dir():
            continue
        for path in cache_dir.rglob("*"):
            if path.is_file():
                entries[str(path)] = {"bytes": path.stat().st_size,
                                      "sha256": digest(path), "kind": "cache-entry-or-stat"}
    return entries


def prepare(args, examples, artifacts, expected_by_name, output):
    preparation = {}
    for example in examples:
        name = example["name"]
        wasm = artifacts[name, "direct"]["path"]
        cache_root = output / "prepared-cache" / name
        cfg = cache_config(cache_root / "cache.toml")
        cache_command = [args.host.resolve(), "--cache-config", cfg, wasm]
        cache_result, cache_ns = run_command(cache_command)
        check_output(cache_result.stdout, expected_by_name[name], name)
        if cache_result.returncode or cache_result.stderr:
            raise RuntimeError("cache warm failed: " + cache_result.stderr.decode(errors="replace"))
        precompiled = output / "precompiled" / (name + ".cwasm")
        precompiled.parent.mkdir(parents=True, exist_ok=True)
        compile_command = [args.host.resolve(), "--compile", wasm, precompiled]
        compile_command.insert(1, "--no-cache")
        compile_result, compile_ns = run_command(compile_command)
        if compile_result.returncode or compile_result.stderr:
            raise RuntimeError("AOT preparation failed: " + compile_result.stderr.decode(errors="replace"))
        preparation[name] = {"cache_warm": {"wall_ns": cache_ns, "cache_hit": False,
                                               **record_command(cache_command, cache_result)},
                             "cache_config": str(cfg), "cache_directory": str(cache_root / "entries"),
                             "cache_config_sha256": digest(cfg),
                             "precompiled": str(precompiled), "precompiled_sha256": digest(precompiled),
                             "precompiled_bytes": precompiled.stat().st_size,
                             "precompile": {"wall_ns": compile_ns, **record_command(compile_command, compile_result)}}
    return preparation


def environment(args):
    affinity = None
    loadavg = None
    if hasattr(os, "sched_getaffinity"):
        affinity = sorted(os.sched_getaffinity(0))
    if hasattr(os, "getloadavg"):
        loadavg = os.getloadavg()
    return {"OMP_NUM_THREADS": os.environ.get("OMP_NUM_THREADS"),
            "OPENBLAS_NUM_THREADS": os.environ.get("OPENBLAS_NUM_THREADS"),
            "PYTHONHASHSEED": os.environ.get("PYTHONHASHSEED"),
            "cpu_affinity": affinity, "system_loadavg": loadavg,
            "machine_label": args.machine_label}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", nargs="*", help="example names; use only with --smoke")
    parser.add_argument("--example-report", required=True, type=Path)
    parser.add_argument("--host", type=Path, default=ROOT / "build/bin/goose-wasmtime")
    parser.add_argument("--samples", type=int, default=15)
    parser.add_argument("--warmups", type=int, default=1)
    parser.add_argument("--seed", type=int, default=17931)
    parser.add_argument("--machine-label", default="")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/runtime-lifecycle")
    parser.add_argument("--smoke", action="store_true", help="allow subset reports and small sample counts")
    args = parser.parse_args()
    minimum_samples = 1
    if not args.smoke:
        minimum_samples = 5
    if args.samples < minimum_samples or args.warmups < 0:
        parser.error("samples must be at least " + str(minimum_samples) + " and warmups nonnegative")
    if args.examples and not args.smoke:
        parser.error("example subsets require --smoke")
    args.example_report = args.example_report.resolve()
    args.host = args.host.resolve()
    if not args.example_report.is_file() or not args.host.is_file():
        parser.error("example report and native Wasmtime host must exist")
    report_in = json.loads(args.example_report.read_text())
    if report_in.get("status") not in ("passed", "passed-smoke"):
        parser.error("example build report must be passed")
    if report_in.get("status") == "passed-smoke" and not args.smoke:
        parser.error("smoke build reports require --smoke")
    all_examples = report_in.get("examples", [])
    if not all_examples:
        parser.error("example build report contains no examples")
    if not args.smoke and len(all_examples) != EXPECTED_EXAMPLES:
        parser.error("expected all 10 examples in the supplied build report")
    available = {item["name"] for item in all_examples}
    if set(args.examples) - available:
        parser.error("unknown examples: " + ", ".join(sorted(set(args.examples) - available)))
    if len(args.examples) != len(set(args.examples)):
        parser.error("duplicate example names")
    examples = all_examples
    if args.examples:
        selected = set(args.examples)
        examples = [item for item in all_examples if item["name"] in selected]
    artifacts = choose_artifacts(report_in, [item["name"] for item in examples])
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()):
        parser.error("output directory is nonempty; preserve existing attempts")
    output.mkdir(parents=True, exist_ok=True)
    for folder in ("samples", "prepared-cache", "precompiled"):
        (output / folder).mkdir(exist_ok=True)

    expected_by_name = {item["name"]: expected_bytes(item) for item in examples}
    pinned_environment = metadata(args, args.example_report, examples)
    prep = prepare(args, examples, artifacts, expected_by_name, output)
    report = {"schema": "goose-runtime-lifecycle-v1", "status": "running",
              "started_utc": datetime.now(timezone.utc).isoformat(),
              "configuration": {"samples": args.samples, "warmups": args.warmups,
                                "seed": args.seed, "smoke": args.smoke,
                                "example_names": [item["name"] for item in examples],
                                "modes": list(MODES),
                                "worker_mode": "already-running RuntimeSession; fresh Store and instance per request"},
              "environment": pinned_environment,
              "runtime_environment": environment(args), "examples": [],
              "preparation": prep, "observations": [], "failures": []}
    rng = random.Random(args.seed)
    try:
        example_order = list(examples)
        rng.shuffle(example_order)
        for example in example_order:
            name = example["name"]
            expected = expected_by_name[name]
            direct = artifacts[name, "direct"]
            native = artifacts[name, "native"]
            worker_root = output / "samples" / name / "worker-hit"
            worker_root.mkdir(parents=True, exist_ok=True)
            worker_session, worker = worker_start(args, example, direct, expected, worker_root)
            report.setdefault("worker_lifecycle", {})[name] = worker
            # Each round is one randomized six-mode cohort; cache-miss uses a fresh directory.
            try:
                for round_number in range(args.warmups + args.samples):
                    jobs = list(MODES)
                    rng.shuffle(jobs)
                    for mode in jobs:
                        if mode == "worker-hit":
                            row = worker_request(worker_session, example, direct, expected, round_number,
                                                 worker["session_command"])
                            row["phase"] = "measure"
                            if round_number < args.warmups:
                                row["phase"] = "warmup"
                            if row["phase"] == "measure":
                                row["sample"] = round_number - args.warmups
                            report["observations"].append(row)
                            continue
                        root = output / "samples" / name / mode / str(round_number)
                        root.mkdir(parents=True, exist_ok=True)
                        artifact = direct
                        if mode == "native-C":
                            artifact = native
                        if mode == "cache-miss":
                            root = root / "miss"
                            root.mkdir()
                        if mode == "cache-hit":
                            root = Path(prep[name]["cache_config"]).parent
                        if mode == "precompiled":
                            artifact = {"path": Path(prep[name]["precompiled"]),
                                        "sha256": prep[name]["precompiled_sha256"]}
                        if mode == "native-C":
                            command = [native["path"]]
                            started = time.perf_counter_ns()
                            result = process.run([str(native["path"])], stdout=subprocess.PIPE,
                                                    stderr=subprocess.PIPE, cwd=ROOT, check=False)
                            wall_ns = time.perf_counter_ns() - started
                            row = {"name": name, "mode": mode, "round": round_number,
                                   "wall_ns": wall_ns, "wall_seconds": wall_ns / 1e9,
                                   "cache_hit": None, "golden_match": result.stdout == expected,
                                   "stderr_empty": not result.stderr,
                                   **record_command(command, result)}
                        else:
                            row = timed_fresh(args, example, mode, artifact, expected, root, round_number)
                        row["phase"] = "measure"
                        if round_number < args.warmups:
                            row["phase"] = "warmup"
                        if row["phase"] == "measure":
                            row["sample"] = round_number - args.warmups
                        report["observations"].append(row)
                        if row["returncode"] != 0 or not row["golden_match"] or not row["stderr_empty"]:
                            raise RuntimeError(mode + " failed correctness for " + name)
            finally:
                worker_session.close()
            print("PASS", name, flush=True)
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.TimeoutExpired) as error:
        report["failures"].append(str(error))

    for example in examples:
        name = example["name"]
        summaries = {}
        for mode in MODES:
            rows = [row for row in report["observations"] if row["name"] == name and row["mode"] == mode
                    and row["phase"] == "measure"]
            if rows:
                summaries[mode] = summary([row["wall_seconds"] for row in rows])
        report["examples"].append({"name": name,
            "artifacts": {backend: {"path": str(artifacts[name, backend]["path"]),
                                    "sha256": artifacts[name, backend]["sha256"]}
                          for backend in ("direct", "native")},
            "modes": summaries})
    expected_count = len(examples) * len(MODES) * (args.samples + args.warmups)
    passed = (not report["failures"] and len(report["observations"]) == expected_count and
              all(len(item["modes"]) == len(MODES) and all(item["modes"][mode]["n"] == args.samples
                  for mode in MODES) for item in report["examples"]))
    report["status"] = "failed"
    if passed and args.smoke:
        report["status"] = "passed-smoke"
    elif passed:
        report["status"] = "passed"
    report["finished_utc"] = datetime.now(timezone.utc).isoformat()
    for path, sha in report["environment"]["input_sha256"].items():
        if digest(path) != sha:
            report["failures"].append("input changed during run: " + path)
            report["status"] = "failed"
    compiler = report["environment"].get("compiler")
    if compiler and digest(compiler["path"]) != compiler["sha256"]:
        report["failures"].append("compiler changed during run: " + compiler["path"])
        report["status"] = "failed"
    report["artifact_sha256_still_match"] = all(
        digest(item["path"]) == item["sha256"] for item in artifacts.values())
    precompiled_match = True
    for item in prep.values():
        if digest(item["precompiled"]) != item["precompiled_sha256"]:
            precompiled_match = False
    report["precompiled_sha256_still_match"] = precompiled_match
    report["final_cache_file_manifest"] = cache_manifest(output)
    if not report["artifact_sha256_still_match"] or not precompiled_match:
        report["status"] = "failed"
    (output / "report.json").write_text(json.dumps(report, indent=2, default=str) + "\n")
    print(report["status"], len(report["observations"]), "observations;", output / "report.json")
    return int(report["status"] not in ("passed", "passed-smoke"))


if __name__ == "__main__":
    sys.exit(main())
