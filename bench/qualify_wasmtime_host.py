#!/usr/bin/env python3
"""Replay SHA-verified retained differential modules through the native host.

This is concurrent correctness qualification, not a performance benchmark.
Native and Python references are separately collected retained observations.
The unchanged compiler's compile-refusal cases are not rerun here.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import asdict
import hashlib
import importlib.metadata
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
BACKENDS = ("direct", "c-wasm")
LEVELS = (0, 2)
MODES = ("wasm", "wasm-no-parallel", "precompiled-no-parallel")
REFUSALS = {"unsupported_varint_array", "unsupported_pointer_extern", "invalid_source"}
CONFIG = {
    "optimization": "cranelift speed", "memory64": True, "tail_call": True,
    "exceptions": True, "simd": True, "bulk_memory": True, "multi_value": True,
    "threads": False, "relaxed_simd": False, "compilation_cache": False,
}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def bytes_digest(value):
    return hashlib.sha256(value).hexdigest()


def json_bytes(value):
    return (json.dumps(value, sort_keys=True, indent=2) + "\n").encode()


def save_report(output, report):
    report["observations"] = len(report["results"])
    report["runtime_failures"] = sum(row["status"] != "pass" for row in report["results"])
    report["preparation_failures"] = sum(row["status"] != "pass" for row in report["preparations"])
    report["failures"] = report["runtime_failures"] + report["preparation_failures"] + int(bool(report.get("error")))
    temporary = output / "report.tmp"
    temporary.write_bytes(json_bytes(report))
    temporary.replace(output / "report.json")


def execute(command, log, stdin=b"", timeout=60):
    command = [str(part) for part in command]
    log.mkdir(parents=True, exist_ok=True)
    (log / "command.json").write_bytes(json_bytes(command))
    result = {"exit_code": None, "stdout": b"", "stderr": b"", "error": ""}
    try:
        process = subprocess.run(command, cwd=ROOT, input=stdin, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, timeout=timeout, check=False)
        result.update(exit_code=process.returncode, stdout=process.stdout, stderr=process.stderr)
    except subprocess.TimeoutExpired as error:
        result.update(stdout=error.stdout or b"", stderr=error.stderr or b"", error=str(error))
    except OSError as error:
        result["error"] = str(error)
    (log / "stdout").write_bytes(result["stdout"])
    (log / "stderr").write_bytes(result["stderr"])
    (log / "result.json").write_bytes(json_bytes({
        "exit_code": result["exit_code"], "error": result["error"],
        "stdout_sha256": bytes_digest(result["stdout"]),
        "stderr_sha256": bytes_digest(result["stderr"]),
    }))
    return result


def identity(row):
    return (row["case"], row["optimization"], row["debug"], row["backend"], row["engine"])


def verify_pins(pins):
    for name, expected in pins.items():
        require(digest(name) == expected, "input SHA256 changed: " + name)


def artifact_path(baseline, case, level, backend):
    profile = "release"
    if case.debug:
        profile = "debug"
    path = baseline / "shards" / f"{backend}-O{level}" / f"O{level}" / profile / case.fixture / backend
    if case.maximum_pages is not None:
        path /= f"memory-{case.maximum_pages}"
    return path / "program.wasm"


def verify_baseline(baseline, report, cases):
    require(report["failures"] == 0, "baseline contains failures")
    require(report["cases"] == len(cases), "baseline case count differs from current cases()")
    require(report["observations"] == len(report["results"]), "baseline observation count mismatch")
    expected = set()
    by_name = {case.name: case for case in cases}
    require(len(by_name) == len(cases), "duplicate current case name")
    for case in cases:
        for level in LEVELS:
            if level not in case.levels:
                continue
            expected.add((case.name, level, case.debug, "native", "native"))
            for backend in BACKENDS:
                for engine in ("v8", "wasmtime"):
                    expected.add((case.name, level, case.debug, backend, engine))
    observed, refusals = {}, set()
    for row in report["results"]:
        require(row["status"] == "pass", "nonpassing baseline row")
        if row.get("kind") == "compile-refusal":
            require(row["case"] not in refusals, "duplicate baseline refusal")
            refusals.add(row["case"])
            continue
        key = identity(row)
        require(key not in observed, "duplicate baseline observation: " + str(key))
        require(key in expected, "unexpected baseline observation: " + str(key))
        case = by_name[row["case"]]
        require(row["fixture"] == case.fixture and row["exit_code"] == case.exit_code,
                "baseline fixture or exit differs from current case: " + str(key))
        if case.stdout is not None:
            require(row["stdout"] == case.stdout, "baseline differs from golden output: " + str(key))
        if case.diagnostic:
            require(case.diagnostic.lower() in row["stderr"].lower(), "baseline diagnostic missing: " + str(key))
        observed[key] = row
    require(set(observed) == expected, "baseline coverage differs from exact current matrix")
    require(refusals == REFUSALS, "baseline compile-refusal coverage differs")
    for key, row in observed.items():
        native = observed[key[:3] + ("native", "native")]
        require(row["stdout"] == native["stdout"] and row["exit_code"] == native["exit_code"],
                "baseline disagrees with its native reference: " + str(key))
    for shard, metadata in report["qualification_execution"]["shards"].items():
        path = baseline / "shards" / shard / "report.json"
        require(digest(path) == metadata["report_sha256"], "baseline shard SHA256 differs: " + shard)
    return observed


def prepare(host, output, sha, item):
    aot = output / "aot" / (sha + ".cwasm")
    aot.parent.mkdir(parents=True, exist_ok=True)
    aot.unlink(missing_ok=True)
    log = output / "preparation" / sha
    source = Path(item["module"])
    require(digest(source) == sha, "Wasm changed before serialization: " + str(source))
    result = execute([host, "--no-parallel-compilation", "--compile", source, aot], log, timeout=180)
    row = {"module": str(source), "wasm_sha256": sha, "artifact": str(aot), "logs": str(log),
           "exit_code": result["exit_code"], "status": "fail", "error": result["error"]}
    if result["exit_code"] == 0 and not result["error"] and aot.is_file():
        row.update(status="pass", sha256=digest(aot), bytes=aot.stat().st_size)
    else:
        row["error"] += " serialization failed or artifact missing"
    require(digest(source) == sha, "Wasm changed during serialization: " + str(source))
    return row


def replay(index, unit, mode, host, output, compiled):
    case, level, backend, module, sha, native, python = unit
    command = [host, module]
    if mode == "wasm-no-parallel":
        command += ["--no-parallel-compilation"]
    elif mode == "precompiled-no-parallel":
        command = [host, "--no-parallel-compilation", "--precompiled", compiled[sha]["artifact"]]
    log = output / "runs" / f"{index:05d}" / mode
    row = {"case": case.name, "fixture": case.fixture, "optimization": level, "debug": case.debug,
           "backend": backend, "mode": mode, "engine": "native C API", "module": str(module),
           "wasm_sha256": sha, "stdin_sha256": bytes_digest(case.stdin.encode()), "logs": str(log),
           "status": "fail", "errors": []}
    result = execute(command, log, case.stdin.encode(), timeout=30)
    row.update(exit_code=result["exit_code"], stdout=result["stdout"].decode(errors="replace"),
               stderr=result["stderr"].decode(errors="replace"),
               stdout_sha256=bytes_digest(result["stdout"]), stderr_sha256=bytes_digest(result["stderr"]))
    if result["error"]:
        row["errors"].append(result["error"])
    comparisons = {}
    for label, reference in (("native", native), ("python_wasmtime", python)):
        comparisons[label + "_exit"] = result["exit_code"] == reference["exit_code"]
        comparisons[label + "_stdout"] = result["stdout"] == reference["stdout"].encode()
    comparisons["case_exit"] = result["exit_code"] == case.exit_code
    if not python["stderr"]:
        comparisons["python_wasmtime_empty_stderr"] = not result["stderr"]
    if case.stdout is not None:
        comparisons["case_golden"] = result["stdout"] == case.stdout.encode()
    if case.diagnostic:
        comparisons["case_diagnostic"] = case.diagnostic.lower() in row["stderr"].lower()
    row["comparisons"] = comparisons
    row["errors"] += [name + " mismatch" for name, passed in comparisons.items() if not passed]
    if not row["errors"]:
        row["status"] = "pass"
    return row


def qualify(args, output, report):
    baseline = args.baseline_dir.resolve()
    host = args.host.resolve()
    baseline_path = baseline / "report.json"
    old = json.loads(baseline_path.read_text())
    old_pins = old["qualification_execution"]["input_sha256"]
    require(bool(old_pins), "baseline has no source input pins")
    verify_pins(old_pins)
    require(digest(ROOT / "build/bin/goose") == old["compiler_sha256"], "baseline compiler changed")
    require(json.loads((ROOT / "toolchain.json").read_text()) == old["toolchain"], "baseline toolchain changed")
    manifest_path = host.with_suffix(".json")
    manifest = json.loads(manifest_path.read_text())
    verify_pins(manifest["input_sha256"])
    require(digest(host) == manifest["host_sha256"], "host differs from its build manifest")
    import wasmtime._ffi as ffi
    library = Path(ffi.dll._name).resolve()
    version = importlib.metadata.version("wasmtime")
    require(str(library) == manifest["library"] and digest(library) == manifest["library_sha256"],
            "native host and Python do not use the same pinned Wasmtime library")
    require(version == manifest["version"] == old["toolchain"]["wasmtime_python"], "Wasmtime version mismatch")
    sdk_pin_path = ROOT / "host/wasmtime-sdk.json"
    sdk_pin = json.loads(sdk_pin_path.read_text())
    sdk_target = sdk_pin["targets"][manifest["target"]]
    archive = ROOT / "build/wasmtime-host" / sdk_target["asset"]
    require(sdk_pin["version"] == version and digest(archive) == sdk_target["sha256"] == manifest["sdk_archive_sha256"],
            "Wasmtime SDK identity mismatch")
    # Detect additions/removals as well as edits to the baseline fixture set.
    fixture_paths = sorted((ROOT / "tests/fixtures").glob("*.goose")) + sorted((ROOT / "tests/fixtures").glob("*.json"))
    require({str(path) for path in fixture_paths} == {name for name in old_pins if Path(name).parent == ROOT / "tests/fixtures"},
            "baseline fixture inventory changed")
    sys.path.insert(0, str(ROOT / "tests"))
    from run_differential import cases
    all_cases = cases()
    rows = verify_baseline(baseline, old, all_cases)
    selected = [case for case in all_cases if args.filter in case.name]
    require(bool(selected), "no cases selected")
    case_data = [asdict(case) for case in all_cases]
    report.update(cases=len(selected), baseline_cases=len(all_cases), baseline_observations=len(old["results"]),
                  case_inputs_sha256=bytes_digest(json_bytes(case_data)), compiler_sha256=old["compiler_sha256"],
                  reference_method="Retained native and Python Wasmtime rows; separately collected by the pinned baseline compiler.",
                  compile_refusals="Not rerun: compiler and all baseline input pins are unchanged.",
                  wasmtime=version, host_build=manifest, engine_configuration=CONFIG,
                  mode_configuration={
                      "wasm": {"module_mode": "wasm", "parallel_compilation": True},
                      "wasm-no-parallel": {"module_mode": "wasm", "parallel_compilation": False},
                      "precompiled-no-parallel": {"module_mode": "precompiled", "parallel_compilation": False},
                  }, serialization_configuration={**CONFIG, "parallel_compilation": False})
    units, modules, unique = [], {}, {}
    for case in selected:
        for level in LEVELS:
            if level not in case.levels:
                continue
            native = rows[(case.name, level, case.debug, "native", "native")]
            for backend in BACKENDS:
                python = rows[(case.name, level, case.debug, backend, "wasmtime")]
                module = artifact_path(baseline, case, level, backend)
                sha = python["sha256"]
                require(module.stat().st_size == python["module_bytes"] and digest(module) == sha,
                        "retained module differs from baseline SHA256: " + str(module))
                require(rows[(case.name, level, case.debug, backend, "v8")]["sha256"] == sha,
                        "baseline engine rows disagree on module SHA256")
                modules[str(module)] = {"module": str(module), "sha256": sha, "bytes": module.stat().st_size}
                unique.setdefault(sha, {"module": str(module)})
                units.append((case, level, backend, module, sha, native, python))
    require(bool(units), "selected cases have no O0/O2 runtime observations")
    report.update(expected_observations=len(units) * len(MODES), modules=list(modules.values()), unique_wasm=len(unique))
    inputs = set(old_pins) | set(manifest["input_sha256"])
    inputs.update(str(path) for path in (host, manifest_path, library, sdk_pin_path, archive,
                                        baseline_path, Path(__file__).resolve()))
    inputs.update(str(baseline / "shards" / shard / "report.json") for shard in old["qualification_execution"]["shards"])
    inputs.update(modules)
    before = {name: digest(name) for name in sorted(inputs)}
    require(all(before[name] == sha for name, sha in old_pins.items()), "baseline inputs changed while preparing replay")
    require(all(before[name] == sha for name, sha in manifest["input_sha256"].items()), "host inputs changed while preparing replay")
    report["input_sha256"] = before
    save_report(output, report)
    version_result = execute([host, "--version"], output / "version")
    require(version_result["exit_code"] == 0 and version_result["stdout"] == ("Wasmtime " + version + "\n").encode(),
            "host --version does not match pinned Wasmtime")
    compiled = {}
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        pending = {pool.submit(prepare, host, output, sha, item): sha for sha, item in unique.items()}
        for future in as_completed(pending):
            sha = pending[future]
            try:
                row = future.result()
            except Exception as error:
                row = {"wasm_sha256": sha, "status": "fail", "error": str(error)}
            report["preparations"].append(row)
            if row["status"] == "pass":
                compiled[sha] = row
            if len(report["preparations"]) % 100 == 0:
                save_report(output, report)
    save_report(output, report)
    require(set(compiled) == set(unique), "one or more native artifact preparations failed")
    aot_pins = {row["artifact"]: row["sha256"] for row in compiled.values()}
    report["aot_sha256"] = aot_pins
    for item in report["modules"]:
        item["precompiled"] = compiled[item["sha256"]]["artifact"]
        item["precompiled_sha256"] = compiled[item["sha256"]]["sha256"]
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        pending = {pool.submit(replay, index, unit, mode, host, output, compiled): (index, mode)
                   for index, unit in enumerate(units) for mode in MODES}
        for future in as_completed(pending):
            index, mode = pending[future]
            try:
                row = future.result()
            except Exception as error:
                case, level, backend, *_ = units[index]
                row = {"case": case.name, "optimization": level, "debug": case.debug, "backend": backend,
                       "mode": mode, "status": "fail", "errors": [str(error)]}
            report["results"].append(row)
            if len(report["results"]) % 250 == 0:
                save_report(output, report)
                print(len(report["results"]), "/", report["expected_observations"], "runtime observations", flush=True)
    expected = {(case.name, level, case.debug, backend, mode)
                for case, level, backend, *_ in units for mode in MODES}
    actual = [(row["case"], row["optimization"], row["debug"], row["backend"], row["mode"]) for row in report["results"]]
    require(len(actual) == len(set(actual)) and set(actual) == expected, "runtime coverage differs from exact selected matrix")
    after = {name: digest(name) for name in before}
    report["input_sha256_after"] = after
    report["aot_sha256_after"] = {name: digest(name) for name in aot_pins}
    require(before == after, "qualification inputs changed during replay")
    require(aot_pins == report["aot_sha256_after"], "native artifacts changed during replay")
    require(bytes_digest(json_bytes([asdict(case) for case in cases()])) == report["case_inputs_sha256"], "case inputs changed")
    require(all(row["status"] == "pass" for row in report["results"]), "runtime observations failed")
    report["coverage_exact"] = True
    report["status"] = "pass"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-dir", type=Path, default=ROOT / "build/native-gap/differential")
    parser.add_argument("--host", type=Path, default=ROOT / "build/bin/goose-wasmtime")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--filter", default="", help="case-name substring for an exact reduced smoke matrix")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be at least one")
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    report = {"schema": "goose-native-wasmtime-qualification-v1", "status": "running", "coverage_exact": False,
              "configuration": {"jobs": args.jobs, "filter": args.filter, "modes": MODES,
                                "baseline_dir": str(args.baseline_dir.resolve()), "host": str(args.host.resolve())},
              "measurement": "Concurrent correctness run; timings are not performance evidence.",
              "results": [], "preparations": []}
    save_report(output, report)
    started = time.monotonic()
    try:
        qualify(args, output, report)
    except BaseException as error:
        report.update(status="fail", error=type(error).__name__ + ": " + str(error))
    report["wall_seconds"] = time.monotonic() - started
    report["results"].sort(key=lambda row: (row["case"], row["optimization"], row["debug"], row["backend"], row["mode"]))
    save_report(output, report)
    print(report["status"].upper(), report["observations"], "observations;", output / "report.json", flush=True)
    if report["status"] != "pass":
        print(report.get("error", "qualification failed"), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
