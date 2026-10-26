#!/usr/bin/env python3
"""Qualify and measure a pinned LangArena suite without inventing leaderboard ranks.

The whole-suite track retains all 50 upstream Goose workloads. The adapted
track runs seven disclosed ports (six change storage), with identical source and
official runtime inputs across native C, C-Wasm, and direct Wasm. Unavailable
whole-suite targets remain visible; refusals are never successful timings.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
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


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "bench" / "langarena"
REVISION = "aab9b14998231ba905523b5ba3990ee03c46f64d"
SOURCE_URL = "https://github.com/kostya/LangArena.git"
PORT_MARKER = "let ARENA_REVISION = 0;"
WHOLE_MARKER = '"RECOMPILE_MARKER_0"'
MARKER_PATH = '"/tmp/recompile_marker"'
LOCAL_MARKER_PATH = '"recompile_marker"'


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def checkpoint(report: dict, output: Path, *, markdown=False):
    """Replace the consolidated record atomically; incomplete runs stay explicit."""
    temporary = output / "report.json.tmp"
    temporary.write_text(json.dumps(report, indent=2) + "\n")
    temporary.replace(output / "report.json")
    if markdown:
        temporary = output / "report.md.tmp"
        temporary.write_text(render_report(report))
        temporary.replace(output / "report.md")


def terminate_process_tree(process):
    if os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        if process.poll() is None:
            process.kill()
    else:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def load_manifest() -> dict:
    manifest = json.loads((DATA / "manifest.json").read_text())
    if manifest["upstream"]["revision"] != REVISION:
        raise ValueError("manifest upstream revision does not match the harness pin")
    cases = manifest["cases"]
    names = [case["name"] for case in cases]
    if len(cases) != 50 or len(set(names)) != 50:
        raise ValueError("the pinned catalog must retain exactly 50 distinct tasks")
    for profile in ("test", "run"):
        path = DATA / f"{profile}.json"
        expected = manifest["upstream"]["source_sha256"][f"{profile}.js"]
        if sha256(path) != expected:
            raise ValueError(f"pinned {profile} configuration has changed")
        official = {entry["name"]: entry for entry in json.loads(path.read_text())}
        if set(official) != set(names):
            raise ValueError("configuration and catalog task names differ")
        for case in cases:
            if case[profile] != official[case["name"]]:
                raise ValueError(f"manifest changes official inputs for {case['name']}/{profile}")
    if sum(case["port"] is not None for case in cases) != 7:
        raise ValueError("the adaptation catalog must contain exactly seven ports")
    return manifest


def warmup_count(config: dict) -> int:
    # Match upstream Goose's truncating conversion of iterations * 0.2.
    return config.get("warmup_iterations", max(int(config["iterations"] * 0.2), 1))


def port_stdin(case: dict, profile: str) -> str:
    config, port = case[profile], case["port"]
    if port is None:
        raise ValueError("task has no adapted port")
    values = []
    for field in port["fields"]:
        value = config[field]
        low, high = port["bounds"][field]
        if not isinstance(value, int) or not low <= value <= high:
            raise ValueError(f"{case['name']} {field} exceeds its disclosed port bound")
        values.append(value)
    iterations, warmups = config["iterations"], warmup_count(config)
    if iterations <= 0 or warmups < 0:
        raise ValueError("invalid iteration or warmup count")
    if case["name"] == "CLBG::Mandelbrot" and iterations + warmups > 120:
        raise ValueError("Mandelbrot cumulative output capacity permits at most 120 executions")
    return " ".join(map(str, [*values, iterations, warmups])) + "\n"


def parse_port_result(stdout: str, returncode: int, expected: int, revision: int = 0) -> dict:
    if returncode != revision:
        raise ValueError(f"exit {returncode}, expected revision exit {revision}")
    lines = stdout.splitlines()
    if len(lines) != 2 or not all(re.fullmatch(r"[0-9]+", line) for line in lines):
        raise ValueError("port must print exactly two decimal lines: checksum and nanoseconds")
    checksum, elapsed = map(int, lines)
    if checksum != expected:
        raise ValueError(f"checksum {checksum} != official {expected}")
    if elapsed <= 0:
        raise ValueError("timed region must have a positive duration")
    return {"checksum": checksum, "expected_checksum": expected,
            "timed_region_seconds": elapsed / 1e9, "revision_exit": revision}


def load_engine_timing(path: Path) -> dict:
    timings = json.loads(path.read_text())
    if not isinstance(timings, dict):
        raise ValueError("invalid engine timing metadata")
    for key in ("compile_instantiate_ns", "start_function_ns", "engine_total_ns"):
        value = timings.get(key)
        if type(value) not in (int, float) or value < 0 or value != value or value == float("inf"):
            raise ValueError("invalid engine timing metadata")
    return timings


def parse_whole_result(stdout: str, returncode: int, task: str) -> dict:
    if returncode:
        raise ValueError(f"whole-suite process exited {returncode}")
    matches = re.findall(rf"^{re.escape(task)}: OK in ([0-9]+(?:\.[0-9]+)?)s$", stdout, re.M)
    summaries = re.findall(r"^Summary: [0-9.]+s, ([0-9]+), ([0-9]+), ([0-9]+)$", stdout, re.M)
    if len(matches) != 1 or summaries != [("1", "1", "0")]:
        raise ValueError("whole-suite output does not verify exactly the requested task")
    if "ERR[" in stdout or "Warning:" in stdout:
        raise ValueError("whole-suite output contains a checksum error or missing task")
    return {"timed_region_seconds": float(matches[0]), "upstream_checksum_check": "passed",
            "timing_resolution_seconds": 0.001}


@contextmanager
def edited_marker(path: Path, old: str, new: str):
    original = path.read_bytes()
    before, after = old.encode(), new.encode()
    if original.count(before) != 1:
        raise ValueError(f"expected exactly one reachable marker in {path}")
    path.write_bytes(original.replace(before, after))
    try:
        yield
    finally:
        path.write_bytes(original)


def verify_upstream(path: Path, manifest: dict) -> None:
    result = subprocess.run(["git", "-C", str(path), "rev-parse", "HEAD"], text=True, capture_output=True)
    if result.returncode or result.stdout.strip() != REVISION:
        raise ValueError(f"upstream checkout must be at {REVISION}: {path}")
    for name, expected in manifest["upstream"]["source_sha256"].items():
        source = path / name
        if not source.is_file() or sha256(source) != expected:
            raise ValueError(f"pinned upstream file changed or missing: {source}")


def stage_whole(upstream: Path, destination: Path) -> Path:
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copytree(upstream / "goose" / "src", destination / "src", dirs_exist_ok=True)
    bench = destination / "src" / "bench.goose"
    text = bench.read_text()
    if text.count(MARKER_PATH) != 1:
        raise ValueError("upstream marker path does not match the disclosed path-only patch")
    bench.write_text(text.replace(MARKER_PATH, LOCAL_MARKER_PATH))
    for profile in ("test", "run"):
        shutil.copyfile(DATA / f"{profile}.json", destination / f"{profile}.json")
    return destination / "src" / "main.goose"


def summarize(values: list[float]) -> dict | None:
    if not values:
        return None
    middle = statistics.median(values)
    ordered = sorted(values)
    def percentile(fraction):
        position = fraction * (len(ordered) - 1)
        lo = int(position)
        hi = min(lo + 1, len(ordered) - 1)
        return ordered[lo] + (ordered[hi] - ordered[lo]) * (position - lo)
    return {"n": len(values), "median": middle,
            "mad": statistics.median(abs(value - middle) for value in values),
            "min": min(values), "max": max(values), "p25": percentile(0.25),
            "p75": percentile(0.75), "samples": values}


def tool_version(command: list[str]) -> dict:
    try:
        p = subprocess.run(command, capture_output=True, text=True, timeout=30)
        return {"command": command, "exit_code": p.returncode, "output": (p.stdout + p.stderr).strip()}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"command": command, "error": str(error)}


def metadata(args, manifest) -> dict:
    inputs = [Path(__file__), DATA / "manifest.json", DATA / "test.json", DATA / "run.json",
              ROOT / "scripts" / "goose_wasm.py", ROOT / "scripts" / "build_support.py",
              ROOT / "oracle" / "goose_wasm.py",
              ROOT / "scripts" / "run_wasm.mjs", ROOT / "scripts" / "run_wasmtime.py",
              ROOT / "bench" / "host_input.c", *sorted((DATA / "ports").glob("*.goose"))]
    try:
        wasmtime = importlib.metadata.version("wasmtime")
    except importlib.metadata.PackageNotFoundError:
        wasmtime = "not installed"
    cpu = "unknown"
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name"):
                cpu = line.partition(":")[2].strip()
                break
    except OSError:
        pass
    stdlib = args.goose.parent / "stdlib"
    return {"platform": platform.platform(), "python": sys.version, "cpu": cpu,
            "logical_cpu_count": os.cpu_count(), "supplied_machine_label": args.machine_label,
            "node": tool_version([args.node, "-p", "JSON.stringify(process.versions)"]),
            "native_cc": tool_version([args.cc, "--version"]), "emcc": tool_version([args.emcc, "--version"]),
            "wasmtime": wasmtime, "compiler_sha256": sha256(args.goose),
            "installed_stdlib_sha256": {str(p): sha256(p) for p in sorted(stdlib.rglob("*.goose"))},
            "input_sha256": {str(p.relative_to(ROOT)): sha256(p) for p in inputs},
            "upstream_revision": manifest["upstream"]["revision"],
            "toolchain": json.loads((ROOT / "toolchain.json").read_text()),
            "environment_overrides": {key: os.environ.get(key) for key in
                                      ("EM_NODE_JS", "EM_CONFIG", "EM_CACHE", "EMCC_CORES", "TMPDIR", "GOOSE_STDLIB")},
            "target_profiles": {"direct": "memory32; explicit bounds; no LLVM",
                                "c-wasm": "LP64 memory64; WASI64; standard Wasm EH",
                                "native": "native C; -O2 -fno-strict-aliasing -ffp-contract=off"}}


def execute(command, directory: Path, *, cwd: Path, stdin="", timeout=600) -> dict:
    directory.mkdir(parents=True, exist_ok=True)
    command = [str(value) for value in command]
    (directory / "command.json").write_text(json.dumps(command, indent=2) + "\n")
    (directory / "stdin.txt").write_text(stdin)
    started = time.perf_counter_ns()
    error = ""
    p = None
    try:
        p = subprocess.Popen(command, cwd=cwd, text=True, stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             start_new_session=os.name != "nt",
                             creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0)
        try:
            stdout, stderr = p.communicate(stdin, timeout=timeout)
            code = p.returncode
        except subprocess.TimeoutExpired:
            # Terminate the complete driver/compiler family, including tools
            # holding inherited output pipes. Killing only the Python driver
            # would leave clang/wasm-opt running into later timed samples.
            terminate_process_tree(p)
            stdout, stderr = p.communicate(timeout=10)
            code, error = -1, f"timeout after {timeout} seconds; process group terminated"
    except subprocess.TimeoutExpired as failure:
        code, error = -1, f"timeout after {timeout} seconds"
        stdout = failure.stdout or ""
        stderr = failure.stderr or ""
        if isinstance(stdout, bytes): stdout = stdout.decode(errors="replace")
        if isinstance(stderr, bytes): stderr = stderr.decode(errors="replace")
    except OSError as failure:
        code, stdout, stderr, error = -1, "", "", str(failure)
    except BaseException:
        if p is not None:
            terminate_process_tree(p)
            try:
                p.communicate(timeout=10)
            except (OSError, subprocess.TimeoutExpired):
                pass
        raise
    seconds = (time.perf_counter_ns() - started) / 1e9
    (directory / "stdout.txt").write_text(stdout)
    (directory / "stderr.txt").write_text(stderr)
    observation = {"command": command, "cwd": str(cwd), "stdin": stdin, "returncode": code,
                   "stdout": stdout, "stderr": stderr, "wall_seconds": seconds, "error": error}
    (directory / "execution.json").write_text(json.dumps(observation, indent=2) + "\n")
    return observation


def build_command(args, source, artifact, stats, *, port=False, cache=False):
    command = [sys.executable, ROOT / "scripts" / "goose_wasm.py", "build", source, "-o", artifact,
               "--backend", args.current_backend, "--goose", args.goose, "--offline", "-O2", "--stats", stats]
    if not cache:
        command.append("--no-cache")
    else:
        command += ["--cache-dir", args.output_dir / "noop-cache"]
    if args.current_backend != "direct":
        command += ["--cc", args.cc, "--emcc", args.emcc]
        if port:
            command += ["--c-source", ROOT / "bench" / "host_input.c"]
    return command


def engine_command(args, artifact, engine, timing_path=None):
    if engine == "native":
        return [artifact]
    if engine == "v8":
        command = [args.node, ROOT / "scripts" / "run_wasm.mjs", artifact]
    else:
        command = [sys.executable, ROOT / "scripts" / "run_wasmtime.py", artifact]
    if timing_path is not None:
        command += ["--timing-json", timing_path]
    return command


def known_whole_refusal(backend: str, diagnostic: str) -> bool:
    lower = diagnostic.lower()
    return (backend == "c-wasm" and "does not support threads or typed queues" in lower) or (
        backend == "direct" and "wasm-direct:" in lower and any(fragment in lower for fragment in
        ("only fixed-size owned arrays", "not supported", "not available", "currently accept", "currently return")))


def derive_summaries(report):
    compilation, runtime = {}, {}
    for row in report["observations"]:
        if row["status"] != "passed":
            continue
        if row["kind"] == "build":
            key = (row["track"], row["task"], row["backend"], row["phase"])
            compilation.setdefault(key, []).append(row)
        if row["kind"] == "execution" and row["phase"] == "normal":
            key = (row["track"], row["task"], row["backend"], row["engine"], row["profile"])
            runtime.setdefault(key, []).append(row)
    report["compile_summary"] = [
        {"track": track, "task": task, "backend": backend, "phase": phase,
         "wall_seconds": summarize([r["wall_seconds"] for r in rows]), "artifact_bytes": rows[-1]["artifact_bytes"]}
        for (track, task, backend, phase), rows in sorted(compilation.items())]
    report["runtime_summary"] = [
        {"track": track, "task": task, "backend": backend, "engine": engine, "profile": profile,
         "timed_region_seconds": summarize([r["timed_region_seconds"] for r in rows]),
         "process_wall_seconds": summarize([r["wall_seconds"] for r in rows]),
         "engine_compile_instantiate_seconds": summarize([r["engine_timing"]["compile_instantiate_ns"] / 1e9 for r in rows if "engine_timing" in r]),
         "entry_function_seconds": summarize([r["engine_timing"]["start_function_ns"] / 1e9 for r in rows if "engine_timing" in r]),
         "expected_checksum": rows[-1]["expected_checksum"]}
        for (track, task, backend, engine, profile), rows in sorted(runtime.items())]


def derive_coverage(report):
    refused = {row["backend"] for row in report["observations"]
               if row["track"] == "whole" and row["status"] == "unsupported"}
    for entry in report["coverage"]:
        name = entry["task"]
        for track, field in (("whole", "original_passed"), ("adapted", "adapted_passed")):
            entry[field] = sorted({f"{r['backend']}/{r.get('engine','')}/{r.get('profile','')}" for r in report["observations"]
                                   if r["kind"] == "execution" and r["track"] == track and r["task"] == name and
                                   r["status"] == "passed" and r["phase"] == "normal"})
        entry["whole_refused_backends"] = sorted(refused)


def render_report(report) -> str:
    settings, environment = report["configuration"], report["environment"]
    lines = ["# LangArena qualification and measurements", "", f"Status: **{report['status']}**.", "",
             f"Upstream pin: `{REVISION}`. Catalog: **50 tasks**. Adapted entrypoints: **7 tasks**, including six storage adaptations.", "",
             f"Mode: `{settings['command']}`. Machine: {environment['supplied_machine_label'] or environment['cpu']}.",
             f"Compiler SHA-256: `{environment['compiler_sha256']}`.", "",
             "## Measurement contract", "",
             "Whole-suite results use all original Goose kernel sources. The only staging patch changes the "
             "marker destination from `/tmp/recompile_marker` to a relative file inside the isolated run directory. "
             "The original checkout is hash-verified and never edited. Whole-suite compile times include all 50 tasks.", "",
             "The adapted track uses the same seven port sources across native C, direct Wasm, and C-Wasm. "
             "Six ports replace growable storage; Fannkuch keeps its original fixed-array kernel. Official test/run inputs and checksums "
             "are unchanged. Preparation stays outside the clock; warmups mutate the same state used for measurement; "
             "the deterministic RNG is reset before measured iterations. Existing checksum work retains its original placement.", "",
             "Cold builds and marker-edit builds launch fresh driver/compiler processes with `--no-cache`. "
             "OS caches and installed compiler/system-library caches are retained. A port marker edit changes its "
             "exit status from 0 to 1 after its two output lines, and the edited executable must retain the official "
             "checksum. Whole-suite edits change the actual marker file contents. Source bytes are restored in all cases. "
             "Optional unchanged cache hits are a separate phase. Edited sources still rerun the complete frontend.", "",
             "The official whole-suite timer prints milliseconds; adapted ports print integer nanoseconds. "
             "Timed regions exclude process startup and preparation. Process wall time is retained separately. "
             "Sample counts below five are preliminary estimates; raw values and MAD are provided. These are local comparisons, "
             "not LangArena leaderboard scores or claims of complete direct-backend language support.", "",
             "## Whole-suite compilation", "",
             "| Backend | Phase | Samples | Median ms | MAD ms | Artifact bytes |",
             "| --- | --- | ---: | ---: | ---: | ---: |"]
    for row in report["compile_summary"]:
        if row["track"] == "whole":
            stats = row["wall_seconds"]
            lines.append(f"| {row['backend']} | {row['phase']} | {stats['n']} | {stats['median']*1000:.3f} | {stats['mad']*1000:.3f} | {row['artifact_bytes']} |")
    for row in report["observations"]:
        if row["track"] == "whole" and row["status"] == "unsupported":
            diagnostic_lines = row["diagnostic"].splitlines()
            reason = next((line for line in diagnostic_lines if "wasm-direct:" in line or "does not support" in line),
                          diagnostic_lines[0] if diagnostic_lines else "explicit target refusal")
            lines += ["", f"- **{row['backend']} unavailable:** {reason}. Full diagnostic is in the raw report. No successful compile-time score is assigned."]
    lines += ["", "## Original-source correctness and runtime", "",
              "| Task | Backend / engine | Profile | Samples | Region median ms | MAD ms | Process median ms |",
              "| --- | --- | --- | ---: | ---: | ---: | ---: |"]
    for row in report["runtime_summary"]:
        if row["track"] != "whole": continue
        region, process = row["timed_region_seconds"], row["process_wall_seconds"]
        lines.append(f"| {row['task']} | {row['backend']} / {row['engine']} | {row['profile']} | {region['n']} | {region['median']*1000:.3f} | {region['mad']*1000:.3f} | {process['median']*1000:.3f} |")
    lines += ["", "## Adapted workload compilation", "",
              "| Task | Backend | Phase | Samples | Median ms | MAD ms | Artifact bytes |",
              "| --- | --- | --- | ---: | ---: | ---: | ---: |"]
    for row in report["compile_summary"]:
        if row["track"] != "adapted": continue
        stats = row["wall_seconds"]
        lines.append(f"| {row['task']} | {row['backend']} | {row['phase']} | {stats['n']} | {stats['median']*1000:.3f} | {stats['mad']*1000:.3f} | {row['artifact_bytes']} |")
    lines += ["", "## Adapted workload runtime", "",
              "| Task | Backend / engine | Profile | Samples | Region median ms | MAD ms | Engine compile + instantiate ms | Process median ms | Checksum |",
              "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for row in report["runtime_summary"]:
        if row["track"] != "adapted": continue
        region, process = row["timed_region_seconds"], row["process_wall_seconds"]
        engine = row["engine_compile_instantiate_seconds"]
        engine_text = f"{engine['median']*1000:.3f}" if engine else "—"
        lines.append(f"| {row['task']} | {row['backend']} / {row['engine']} | {row['profile']} | {region['n']} | {region['median']*1000:.3f} | {region['mad']*1000:.3f} | {engine_text} | {process['median']*1000:.3f} | {row['expected_checksum']} |")
    lines += ["", "## Qualification and limits", ""]
    lines += ["- " + warning for warning in report["warnings"]]
    lines += ["- Failure: " + failure for failure in report["failures"]]
    lines += ["", "The full 50-task coverage matrix, raw commands/output, source and artifact hashes, tool versions, "
              "input values, environment overrides (including `EM_NODE_JS`), and phase timings are in `report.json` "
              "and adjacent logs. `Hash::SHA256` retains LangArena's custom hash workload; it is not standard cryptographic SHA-256.", ""]
    return "\n".join(lines)


def run_gauntlet(args, manifest):
    verify_upstream(args.upstream, manifest)
    output = args.output_dir
    output.mkdir(parents=True, exist_ok=True)
    selected = [case for case in manifest["cases"] if args.filter.lower() in case["name"].lower()]
    if not selected:
        raise ValueError("no selected tasks")
    port_cases = [case for case in selected if case["port"]]
    if args.tracks == ["adapted"] and not port_cases:
        raise ValueError("selected tasks have no adapted ports; use the whole track to record original-source coverage")
    source_whole = stage_whole(args.upstream, output / "source" / "whole")
    source_ports = output / "source" / "ports"
    shutil.copytree(DATA / "ports", source_ports, dirs_exist_ok=True)
    report = {"schema": "goose-langarena-gauntlet-v1", "status": "incomplete", "started_utc": utc_now(),
              "configuration": {key: str(value) if isinstance(value, Path) else value for key, value in vars(args).items()},
              "environment": metadata(args, manifest), "catalog": manifest,
              "whole_staging_patch": {"file": "goose/src/bench.goose", "from": MARKER_PATH, "to": LOCAL_MARKER_PATH},
              "observations": [], "failures": [], "warnings": [
                  "Seven adapted entrypoints (six change storage, one changes only the harness) are a subset of the 50-task catalog; they do not establish unmodified whole-suite Wasm support.",
                  "No local result is a LangArena leaderboard rank: source/compiler versions, target layout, host, flags, and coverage differ.",
                  "Cold builds retain OS and compiler system-library caches; they are complete uncached driver builds, not disk-cold experiments.",
              ]}
    if args.command == "check":
        report["warnings"].append("Check mode is correctness qualification only; collected durations are not performance evidence.")
    if args.compile_samples < 5 or args.runtime_samples < 5:
        report["warnings"].append("At least one sample count is below five. Medians and dispersion are preliminary.")
    report["coverage"] = [{"task": case["name"], "adaptation_available": case["port"] is not None,
                            "selected": case in selected} for case in manifest["cases"]]
    checkpoint(report, output)
    args.report_started = True
    rng = random.Random(args.seed)
    artifacts = {}
    refused = set()

    def record(row):
        report["observations"].append(row)
        if row["status"] == "failed":
            report["failures"].append(f"{row['track']}/{row['task']}/{row['backend']}/{row.get('engine',row.get('phase',''))}: {row.get('error','failure')}")
        print(f"{row['status'].upper()} {row['track']} {row['task']} {row['backend']} {row.get('engine',row.get('phase',''))}", flush=True)
        report["completed_observations"] = len(report["observations"])
        checkpoint(report, output)

    def build(track, case, backend, sample, phase="cold", cache=False):
        task = case["name"] if case else "all-50"
        key = task.replace("::", "_")
        directory = output / "logs" / "compile" / track / key / backend / phase / str(sample)
        directory.mkdir(parents=True, exist_ok=True)
        artifact = directory / ("program.bin" if backend == "native" else "program.wasm")
        source = source_whole if track == "whole" else source_ports / Path(case["port"]["file"]).name
        args.current_backend = backend
        stats = directory / "driver-stats.json"
        command = build_command(args, source, artifact, stats, port=track == "adapted", cache=cache)
        result = execute(command, directory, cwd=ROOT, timeout=args.compile_timeout)
        staged_files = sorted(source.parent.glob("*.goose"))
        row = {"kind": "build", "track": track, "task": task, "backend": backend, "phase": phase,
               "sample": sample, "source_sha256": sha256(source),
               "staged_source_sha256": {p.name: sha256(p) for p in staged_files}, **result}
        if result["returncode"] or not artifact.is_file():
            diagnostic = result["stderr"] + result["stdout"]
            status = "unsupported" if track == "whole" and known_whole_refusal(backend, diagnostic) else "failed"
            row.update(status=status, diagnostic=diagnostic, error=result["error"] or diagnostic[-3000:])
            if status == "unsupported": refused.add(backend)
            record(row)
            return None
        try:
            driver_stats = json.loads(stats.read_text())
        except (OSError, ValueError) as error:
            row.update(status="failed", error=f"successful build did not produce valid phase statistics: {error}")
            record(row)
            return None
        row.update(status="passed", artifact=str(artifact), artifact_bytes=artifact.stat().st_size,
                   artifact_sha256=sha256(artifact), driver_stats=driver_stats)
        if phase == "noop" and row["driver_stats"].get("cache") != "hit":
            row.update(status="failed", error="unchanged direct build did not report a cache hit")
        record(row)
        if row["status"] != "passed": return None
        return artifact

    def run_port(case, backend, artifact, engine, profile, sample, phase="normal", revision=0):
        key = case["name"].replace("::", "_")
        directory = output / "logs" / "runtime" / "adapted" / key / backend / engine / profile / phase / str(sample)
        timing_path = directory / "engine-timing.json"
        timing_path.unlink(missing_ok=True)
        result = execute(engine_command(args, artifact, engine, timing_path if engine != "native" else None), directory, cwd=ROOT,
                         stdin=port_stdin(case, profile), timeout=args.run_timeout)
        row = {"kind": "execution", "track": "adapted", "task": case["name"], "backend": backend,
               "engine": engine, "profile": profile, "sample": sample, "phase": phase,
               "artifact_sha256": sha256(artifact), **result}
        try:
            row.update(parse_port_result(result["stdout"], result["returncode"], case[profile]["checksum"], revision))
            if engine != "native":
                row["engine_timing"] = load_engine_timing(timing_path)
            row["status"] = "passed"
        except (OSError, ValueError) as error:
            row.update(status="failed", error=str(error) + ": " + result["stderr"][-2000:])
        record(row)

    def run_whole(case, backend, artifact, profile, sample, phase="normal", marker="RECOMPILE_MARKER_0"):
        # Current Wasm whole-suite builds are refused before execution. Preserve
        # a clear refusal if future compilation exceeds the current host ABI.
        if backend != "native":
            record({"kind": "execution", "track": "whole", "task": case["name"], "backend": backend,
                    "phase": phase, "status": "failed", "error": "whole-suite Wasm host needs argv/filesystem support"})
            return
        key = case["name"].replace("::", "_")
        directory = output / "logs" / "runtime" / "whole" / key / backend / profile / phase / str(sample)
        directory.mkdir(parents=True, exist_ok=True)
        marker_file = directory / "recompile_marker"
        if marker_file.exists(): marker_file.unlink()  # only this run's private marker
        command = [artifact, output / "source" / "whole" / f"{profile}.json", case["name"]]
        result = execute(command, directory, cwd=directory, timeout=args.run_timeout)
        row = {"kind": "execution", "track": "whole", "task": case["name"], "backend": backend,
               "engine": "native", "profile": profile, "sample": sample, "phase": phase,
               "artifact_sha256": sha256(artifact), "expected_checksum": case[profile]["checksum"], **result}
        try:
            row.update(parse_whole_result(result["stdout"], result["returncode"], case["name"]))
            if not marker_file.is_file() or marker_file.read_text() != marker:
                raise ValueError(f"observable marker does not contain {marker}")
            row.update(status="passed", observed_marker=marker_file.read_text())
        except (OSError, ValueError) as error:
            row.update(status="failed", error=str(error) + ": " + result["stderr"][-2000:])
        record(row)

    # All build tasks are shuffled and sequential: no compiler contention is
    # deliberately introduced into a timed sample.
    tasks = []
    if "whole" in args.tracks:
        tasks += [("whole", None, backend, sample) for backend in args.backends for sample in range(args.compile_samples)]
    if "adapted" in args.tracks:
        tasks += [("adapted", case, backend, sample) for case in port_cases for backend in args.backends for sample in range(args.compile_samples)]
    rng.shuffle(tasks)
    for track, case, backend, sample in tasks:
        if track == "whole" and backend in refused: continue
        artifact = build(track, case, backend, sample)
        if artifact is not None:
            artifacts[(track, case["name"] if case else "all-50", backend)] = artifact

    # Official small cases always qualify production execution first.
    runtime_tasks = []
    for (track, task, backend), artifact in artifacts.items():
        cases = selected if track == "whole" else [next(c for c in selected if c["name"] == task)]
        for case in cases:
            engines = ["native"] if backend == "native" else args.engines
            for engine in engines:
                for profile in args.profiles:
                    count = args.runtime_samples if profile == "run" and args.command == "measure" else 1
                    for sample in range(count): runtime_tasks.append((track, case, backend, artifact, engine, profile, sample))
    # Keep qualification before performance, shuffle within each tier.
    for profile in ("test", "run"):
        tier = [task for task in runtime_tasks if task[5] == profile]
        rng.shuffle(tier)
        for track, case, backend, artifact, engine, _, sample in tier:
            if profile == "run":
                qualified = any(r["kind"] == "execution" and r["track"] == track and r["task"] == case["name"] and
                                r["backend"] == backend and r.get("engine") == engine and r.get("profile") == "test" and
                                r["status"] == "passed" for r in report["observations"])
                if not qualified:
                    record({"kind": "execution", "track": track, "task": case["name"], "backend": backend,
                            "engine": engine, "profile": profile, "phase": "normal", "status": "failed",
                            "error": "production run blocked by missing or failed official test qualification"})
                    continue
            if track == "whole": run_whole(case, backend, artifact, profile, sample)
            else: run_port(case, backend, artifact, engine, profile, sample)

    if not args.skip_edits:
        edit_tasks = [(track, task, backend, artifact, sample) for (track, task, backend), artifact in artifacts.items()
                      for sample in range(args.compile_samples)]
        rng.shuffle(edit_tasks)
        for track, task, backend, baseline, sample in edit_tasks:
            case = next((c for c in port_cases if c["name"] == task), None)
            source = source_whole.parent / "bench.goose" if track == "whole" else source_ports / Path(case["port"]["file"]).name
            old = WHOLE_MARKER if track == "whole" else PORT_MARKER
            new = '"RECOMPILE_MARKER_1"' if track == "whole" else "let ARENA_REVISION = 1;"
            with edited_marker(source, old, new):
                artifact = build(track, case, backend, sample, phase="marker-edit")
                if artifact is None: continue
                if sha256(artifact) == sha256(baseline):
                    record({"kind": "marker-validation", "track": track, "task": task, "backend": backend,
                            "status": "failed", "error": "actual marker edit produced byte-identical output"})
                    continue
                if track == "whole":
                    probe = next(c for c in manifest["cases"] if c["name"] == "Etc::Sieve")
                    run_whole(probe, backend, artifact, "test", sample, "marker-edit", "RECOMPILE_MARKER_1")
                else:
                    for engine in (["native"] if backend == "native" else args.engines):
                        run_port(case, backend, artifact, engine, "test", sample, "marker-edit", revision=1)

    if args.noop and "direct" in args.backends:
        for case in port_cases:
            if ("adapted", case["name"], "direct") not in artifacts: continue
            build("adapted", case, "direct", 0, "cache-prime", cache=True)
            for sample in range(args.compile_samples): build("adapted", case, "direct", sample, "noop", cache=True)

    derive_coverage(report)
    report["source_hashes_still_match"] = all(sha256(ROOT / path) == expected for path, expected in report["environment"]["input_sha256"].items())
    report["compiler_hash_still_matches"] = sha256(args.goose) == report["environment"]["compiler_sha256"]
    report["stdlib_hashes_still_match"] = all(sha256(Path(path)) == expected for path, expected in report["environment"]["installed_stdlib_sha256"].items())
    if not report["source_hashes_still_match"]:
        report["failures"].append("measured source files changed during the run; rerun with frozen inputs")
    if not report["compiler_hash_still_matches"]:
        report["failures"].append("compiler changed during the run; rerun with a frozen toolchain")
    if not report["stdlib_hashes_still_match"]:
        report["failures"].append("installed standard-library sources changed during the run")
    report["finished_utc"] = utc_now()
    report["status"] = "failed" if report["failures"] else ("passed-with-explicit-whole-suite-refusals" if refused else "passed")
    derive_summaries(report)
    checkpoint(report, output, markdown=True)
    print(f"{report['status']}: {output / 'report.md'}")
    return int(bool(report["failures"]))


def record_interruption(args, status, message):
    if not getattr(args, "report_started", False):
        return
    report = json.loads((args.output_dir / "report.json").read_text())
    report["status"] = status
    report["finished_utc"] = utc_now()
    report["failures"].append(message)
    derive_summaries(report)
    derive_coverage(report)
    checkpoint(report, args.output_dir, markdown=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("catalog", "fetch", "check", "measure"))
    parser.add_argument("--upstream", type=Path, default=ROOT / "build" / "langarena-upstream")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--goose", type=Path, default=ROOT / "build" / "bin" / "goose")
    parser.add_argument("--emcc", default=os.environ.get("EMCC", "emcc"))
    parser.add_argument("--cc", default=os.environ.get("CC", "cc"))
    parser.add_argument("--node", default="node")
    parser.add_argument("--machine-label")
    parser.add_argument("--tracks", nargs="+", choices=("whole", "adapted"), default=["whole", "adapted"])
    parser.add_argument("--backends", nargs="+", choices=("native", "c-wasm", "direct"), default=["native", "c-wasm", "direct"])
    parser.add_argument("--engines", nargs="+", choices=("v8", "wasmtime"), default=["v8", "wasmtime"])
    parser.add_argument("--profiles", nargs="+", choices=("test", "run"))
    parser.add_argument("--compile-samples", type=int)
    parser.add_argument("--runtime-samples", type=int)
    parser.add_argument("--compile-timeout", type=float, default=600)
    parser.add_argument("--run-timeout", type=float, default=600)
    parser.add_argument("--skip-edits", action="store_true")
    parser.add_argument("--noop", action="store_true", help="also report unchanged direct cache hits separately")
    parser.add_argument("--filter", default="")
    parser.add_argument("--seed", type=int, default=761204)
    args = parser.parse_args()
    args.upstream = args.upstream.expanduser().resolve()
    args.goose = args.goose.expanduser().resolve()
    args.output_dir = (args.output_dir or ROOT / "build" / f"langarena-{args.command}").expanduser().resolve()
    if args.compile_samples is None:
        args.compile_samples = 3 if args.command == "measure" else 1
    if args.runtime_samples is None:
        args.runtime_samples = 3 if args.command == "measure" else 1
    args.profiles = args.profiles or (["test", "run"] if args.command == "measure" else ["test"])
    if "run" in args.profiles and "test" not in args.profiles:
        parser.error("production runs require the official test profile first; include both test and run")
    if min(args.compile_samples, args.runtime_samples) < 1:
        parser.error("sample counts must be positive")
    if min(args.compile_timeout, args.run_timeout) <= 0:
        parser.error("timeouts must be positive")
    for name in ("cc", "emcc", "node"):
        value = getattr(args, name)
        resolved = shutil.which(value)
        if resolved or Path(value).is_file():
            setattr(args, name, str(Path(resolved or value).resolve()))
    # Convert graceful cancellation into normal unwinding: active process groups
    # are killed and an edited marker is restored before writing an interrupted
    # report. SIGKILL cannot be intercepted; atomic checkpoints retain earlier rows.
    def terminated(signum, _frame):
        raise SystemExit(128 + signum)
    signal.signal(signal.SIGTERM, terminated)
    try:
        manifest = load_manifest()
        if args.command == "catalog":
            for case in manifest["cases"]:
                print(case["name"], "adapted port" if case["port"] else "original only")
            print("50 original tasks; 7 explicitly adapted ports")
            return 0
        if args.command == "fetch":
            if args.upstream.exists():
                verify_upstream(args.upstream, manifest)
            else:
                args.upstream.parent.mkdir(parents=True, exist_ok=True)
                subprocess.run(["git", "clone", "--no-checkout", SOURCE_URL, str(args.upstream)], check=True)
                subprocess.run(["git", "-C", str(args.upstream), "checkout", "--detach", REVISION], check=True)
                verify_upstream(args.upstream, manifest)
            print(args.upstream)
            return 0
        return run_gauntlet(args, manifest)
    except (KeyboardInterrupt, SystemExit) as error:
        record_interruption(args, "interrupted", "run interrupted; only completed observations are retained")
        print("LangArena gauntlet interrupted; completed observations are checkpointed", file=sys.stderr)
        return error.code if isinstance(error, SystemExit) and isinstance(error.code, int) else 130
    except Exception as error:
        record_interruption(args, "failed", str(error))
        print(f"LangArena gauntlet: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
