#!/usr/bin/env python3
"""Resident-engine execution trial using only verified artifacts from a qualified run.

Wasmtime compiles/serializes its own trusted local module, deserializes it once,
then reuses that module. V8 constructs one module in a persistent Node process.
Each invocation creates a fresh instance and imports outside the kernel timer.
Native controls remain fresh processes; their own kernel timers exclude startup.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import random
import selectors
import shutil
import signal
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import langbench as cold

ROOT = cold.ROOT
CELLS = cold.CELLS
summaries = cold.summaries
HOST_SPEC = importlib.util.spec_from_file_location("langbench_prepared_host", ROOT / "scripts/run_wasmtime.py")
host = importlib.util.module_from_spec(HOST_SPEC)
sys.modules[HOST_SPEC.name] = host
HOST_SPEC.loader.exec_module(host)


def verify_reference(path: Path, artifacts_dir: Path | None = None) -> tuple[dict, dict, dict]:
    reference = json.loads(path.read_text())
    if reference["schema"] != "goose-langbench-local-v1" or reference["status"] != "passed":
        raise ValueError("reference must be a qualified cold local trial")
    if not all(row["qualified"] for row in cold.summaries(reference)):
        raise ValueError("reference has incomplete sample coverage")
    manifest = cold.load_manifest()
    if reference["manifest"] != manifest:
        raise ValueError("frozen workload manifest differs from reference")
    artifacts, receipts = {}, {}
    for cell in CELLS:
        builds = [build for build in reference["builds"] if build["cell"] == cell and build["status"] == "passed"]
        build = max(builds, key=lambda item: item["round"])
        suffix = "program"
        if cell.startswith("goose-wasm-"):
            suffix = "program.wasm"
        candidates = [(Path(name), details) for name, details in build["artifacts"].items()
                      if Path(name).name == suffix]
        if len(candidates) != 1:
            raise ValueError(f"ambiguous reference artifact for {cell}")
        artifact, details = candidates[0]
        if artifacts_dir is not None:
            artifact = artifacts_dir / cell / str(build["round"]) / suffix
        if not artifact.is_file() or cold.sha256(artifact) != details["sha256"]:
            raise ValueError(f"reference artifact fingerprint changed: {cell}")
        artifacts[cell] = artifact.resolve()
        receipts[cell] = {"path": str(artifact.resolve()), "sha256": details["sha256"],
                          "reference_build_round": build["round"], "reference_build": build}
    if receipts["goose-wasm-v8"]["sha256"] != receipts["goose-wasm-wasmtime"]["sha256"]:
        raise ValueError("both resident engines must use byte-identical Wasm")
    checked = {}
    engine_library = reference["metadata"].get("wasmtime", {}).get("library")
    frozen = reference["metadata"]["fingerprints"]
    for relative in ("bench/langbench/mandelbrot.goose", "bench/langbench/mandelbrot.c",
                     "bench/langbench/manifest.json", "bench/langbench/workload.yaml", "bench/host_input.c"):
        matches = [details for name, details in frozen.items() if name.endswith("/" + relative)]
        if len(matches) != 1 or cold.sha256(ROOT / relative) != matches[0]["sha256"]:
            raise ValueError(f"frozen workload source changed: {relative}")
        checked[str(ROOT / relative)] = matches[0]
    active_runtimes = {}
    for name, current in (("node", shutil.which("node")), ("python", sys.executable)):
        if current is None:
            raise ValueError(f"missing active runtime: {name}")
        previous = str(Path(reference["metadata"]["tools"][name]).resolve())
        current = Path(current).resolve()
        previous_identity = frozen.get(previous)
        if previous_identity is None:
            matches = [details for path, details in frozen.items() if Path(path).name == current.name]
            if len(matches) != 1:
                raise ValueError(f"ambiguous frozen runtime identity: {name}")
            previous_identity = matches[0]
        expected = previous_identity["sha256"]
        if cold.sha256(current) != expected:
            raise ValueError(f"active {name} differs from the verified reference")
        active_runtimes[name] = {"path": str(current), "sha256": expected}
    import importlib.metadata
    import wasmtime._ffi as ffi

    library = Path(ffi.dll._name).resolve()
    expected_library = reference["metadata"]["fingerprints"][engine_library]["sha256"]
    if cold.sha256(library) != expected_library:
        raise ValueError("active Wasmtime library differs from the verified reference")
    active_runtimes["wasmtime"] = {"library": str(library), "sha256": expected_library,
                                   "package_version": importlib.metadata.version("wasmtime"),
                                   "python_version": sys.version}
    return reference, artifacts, {"artifacts": receipts, "verified_reference_inputs": checked,
                                  "frozen_reference_tools": reference["metadata"]["tools"],
                                  "frozen_reference_fingerprints": frozen,
                                  "active_runtimes": active_runtimes}


class V8Worker:
    def __init__(self, artifact: Path, digest: str, cpu: int | None, timeout=600, node=None):
        self.timeout = timeout
        self.sequence = 0
        self.digest = digest
        self.available = False
        self.shutdown = None
        if node is None:
            node = shutil.which("node")
        self.command = [str(node), str(ROOT / "bench/langbench_hot_v8.mjs"), str(artifact), digest]
        if cpu is not None:
            self.command = ["taskset", "-c", str(cpu), *self.command]
        self.child = cold.process.Process(self.command, cwd=ROOT, text=True,
                                          stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                          stderr=subprocess.PIPE, start_new_session=True)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.child.stdout, selectors.EVENT_READ)
        try:
            self.ready = self.receive()
            if (self.ready.get("type") != "ready" or self.ready.get("pid") != self.child.pid
                    or self.ready.get("source_sha256") != digest
                    or self.ready.get("module_construction_count") != 1):
                raise ValueError("invalid resident V8 readiness receipt")
            self.available = True
        except BaseException:
            self.close(force=True)
            raise

    def receive(self):
        if not self.selector.select(self.timeout):
            raise TimeoutError("resident V8 response timeout")
        line = self.child.stdout.readline()
        if not line:
            raise ValueError("resident V8 exited without a result")
        return json.loads(line)

    def run(self, stdin: str) -> dict:
        if not self.available:
            raise ValueError("resident V8 unavailable after earlier failure; worker is not restarted")
        try:
            sequence = self.sequence
            self.sequence += 1
            self.child.stdin.write(json.dumps({"id": sequence, "stdin": stdin}) + "\n")
            self.child.stdin.flush()
            result = self.receive()
            if (result.get("type") != "result" or result.get("id") != sequence
                    or result.get("pid") != self.child.pid or result.get("source_sha256") != self.digest
                    or result.get("module_construction_count") != 1):
                raise ValueError("resident V8 request/result identity changed")
            return result
        except BaseException:
            self.close(force=True)
            raise

    def close(self, *, force=False):
        if self.shutdown is not None:
            return self.shutdown
        self.available = False
        try:
            if self.child.poll() is None:
                try:
                    if force:
                        raise subprocess.TimeoutExpired(self.command, 0)
                    if not self.child.stdin.closed:
                        self.child.stdin.close()
                    self.child.wait(timeout=5)
                except (OSError, subprocess.TimeoutExpired):
                    try:
                        os.killpg(self.child.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    self.child.wait()
            self.shutdown = {"exit_code": self.child.returncode, "stderr": self.child.stderr.read()}
            return self.shutdown
        finally:
            self.selector.close()
            for stream in (self.child.stdin, self.child.stdout, self.child.stderr):
                if not stream.closed:
                    stream.close()


def execute(cell: str, values: list[int], artifact: Path, prepared, wasm: bytes, worker, cpu) -> dict:
    stdin = " ".join(map(str, values)) + "\n"
    if not cell.startswith("goose-wasm-"):
        if cell.startswith("c-"):
            result = cold.invoke([artifact, *map(str, values)], stdin=None, cpu=cpu)
        else:
            result = cold.invoke([artifact], stdin=stdin, cpu=cpu)
        result["lifecycle"] = "fresh native process; internal kernel timer excludes startup"
        return result
    started = time.perf_counter()
    if cell == "goose-wasm-wasmtime":
        result = host.run_module(wasm, stdin, prepared=prepared)
        result["stdout"] = result["stdout"].decode()
        result.update(pid=os.getpid(), module_compile_count=1, module_deserialize_count=1,
                      source_sha256=prepared.source_sha256)
    else:
        result = worker.run(stdin)
    result.update(wall_seconds=time.perf_counter() - started, stdin=stdin,
                  status="passed", lifecycle="resident engine/module, fresh instance and imports per invocation")
    return result


def trial(args) -> int:
    reference, artifacts, receipts = verify_reference(args.reference_report, args.artifacts_dir)
    if args.cpu is not None and args.cpu not in os.sched_getaffinity(0):
        raise ValueError("requested CPU is outside process affinity")
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {"schema": "goose-langbench-hot-v1", "status": "running", "scope": __doc__,
              "profiles": list(reference["profiles"]), "manifest": reference["manifest"],
              "samples": args.samples, "compile_samples": 0, "builds": [], "runs": [],
              "cpu": args.cpu, "seed": args.seed,
              "reference_report": str(args.reference_report.resolve()),
              "reference_report_sha256": cold.sha256(args.reference_report),
              "reference_receipts": receipts, "preparation": {},
              "metadata": {"environment": {name: os.environ.get(name, "") for name in
                                            ("NODE_OPTIONS", "LD_PRELOAD", "LD_LIBRARY_PATH")},
                           "python_flags": repr(sys.flags), "fingerprints": cold.fingerprint([
                  Path(__file__), ROOT / "bench/langbench_hot_v8.mjs", ROOT / "scripts/run_wasmtime.py",
                  ROOT / "scripts/run_wasm.mjs", ROOT / "bench/langbench.py", ROOT / "bench/process.py"])},
              "machine_before": cold.machine_state(),
              "limitations": ["Local single-thread shared-host trial, not an official Docker campaign.",
                              "Resident Wasm modules with fresh instances; native controls remain fresh processes.",
                              "Internal kernel clocks exclude input, instance creation, compilation and startup.",
                              "One full-kernel warmup per cell/profile precedes seeded interleaved measurements.",
                              "V8 can tier during warmups or measurements; one module construction does not mean one machine-code compilation.",
                              "C includes one pthread spawn/join and an atomic row queue; Goose is scalar without either.",
                              "wall_seconds means resident request wall for Wasm and process wall for native; compare kernel clocks.",
                              "No compiler builds are performed. Previous build timings are references, not new measurements.",
                              "Small shared-host differences do not establish a backend advantage."]}
    cold.save(report, output)
    previous_affinity = os.sched_getaffinity(0)
    worker = None
    try:
        if args.cpu is not None:
            os.sched_setaffinity(0, {args.cpu})
        report["parent_execution_affinity"] = sorted(os.sched_getaffinity(0))
        wasm = artifacts["goose-wasm-wasmtime"].read_bytes()
        prepared = host.prepare_module(wasm, output / "trusted-local.cwasm")
        report["preparation"]["wasmtime"] = {**prepared.preparation, "pid": os.getpid(),
            "source_sha256": prepared.source_sha256, "serialized_sha256": prepared.serialized_sha256,
            "serialized_trust": "Compiled locally from the verified Wasm, exclusive-created, read and hash-verified before deserializing.",
            "engine_config": "Exact scripts/run_wasmtime.py create_engine configuration"}
        worker = V8Worker(artifacts["goose-wasm-v8"], prepared.source_sha256, args.cpu,
                          node=receipts["active_runtimes"]["node"]["path"])
        report["preparation"]["v8"] = {**worker.ready, "command": worker.command}
        cold.save(report, output)
        rng = random.Random(args.seed)
        for phase, count in (("warmup", 1), ("measurement", args.samples)):
            for round_index in range(count):
                jobs = [(profile, cell) for profile in report["profiles"] for cell in CELLS]
                if phase == "measurement":
                    rng.shuffle(jobs)
                for profile, cell in jobs:
                    config = report["manifest"]["profiles"][profile]
                    values = [config["n"], config["max_iter"], config["threads"]]
                    record = {"profile": profile, "cell": cell, "phase": phase, "round": round_index,
                              "expected_checksum": config["checksum"], "status": "failed"}
                    try:
                        record.update(execute(cell, values, artifacts[cell], prepared, wasm, worker, args.cpu))
                        if record["stderr"]:
                            raise ValueError("unexpected stderr; raw output retained")
                        record.update(cold.parse_result(record["stdout"], record["exit_code"], config["checksum"], cell))
                        if cell.startswith("goose-wasm-"):
                            timing = record["timing"]
                            if not 0 < record["timed_region_ns"] <= timing["start_function_ns"]:
                                raise ValueError("kernel clock interval exceeds its host execution interval")
                            record["instance_preparation_ns"] = timing["compile_instantiate_ns"]
                        record["status"] = "passed"
                    except (OSError, ValueError, TimeoutError) as error:
                        record.update(status="failed", error=str(error))
                    report["runs"].append(record)
                    cold.save(report, output)
                    print(f"{phase} {round_index + 1}/{count} {profile} {cell}: {record['status']}", flush=True)
    except BaseException as error:
        report.update(status="failed", error=str(error))
        cold.save(report, output)
        raise
    finally:
        try:
            if worker is not None:
                report["v8_shutdown"] = worker.close()
        finally:
            os.sched_setaffinity(0, previous_affinity)
            report["machine_after"] = cold.machine_state()
            report["cpu_activity"] = {}
            for cpu, before in report["machine_before"]["cpu_ticks"].items():
                after = report["machine_after"]["cpu_ticks"].get(cpu)
                if after is None:
                    continue
                delta = [end - start for start, end in zip(before, after)]
                total = sum(delta[:8])
                idle = delta[3] + delta[4]
                report["cpu_activity"][cpu] = {"ticks_delta": delta, "total_ticks": total,
                                               "busy_fraction": (total - idle) / max(total, 1)}
            cold.save(report, output)
    report["status"] = "passed"
    if not all(row["qualified"] for row in summaries(report)) or report["v8_shutdown"] != {"exit_code": 0, "stderr": ""}:
        report["status"] = "failed"
    cold.save(report, output)
    return int(report["status"] != "passed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference-report", type=Path, required=True)
    parser.add_argument("--artifacts-dir", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--samples", type=cold.positive, default=7)
    parser.add_argument("--cpu", type=int, default=7)
    parser.add_argument("--seed", type=int, default=20261107)
    args = parser.parse_args()
    try:
        return trial(args)
    except (OSError, ValueError, TimeoutError) as error:
        parser.exit(2, f"langbench hot trial: {error}\n")


if __name__ == "__main__":
    sys.exit(main())
