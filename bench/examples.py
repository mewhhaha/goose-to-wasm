#!/usr/bin/env python3
"""Measure ordinary builds and fresh-process execution of the example catalog."""
import argparse
from datetime import datetime, timezone
import hashlib
import itertools
import json
import os
from pathlib import Path
import random
import shutil
import subprocess
import sys

import benchmark as common

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "examples/manifest.json"
BACKENDS = ("direct", "c-wasm", "native")


def input_paths(examples, goose):
    paths = [CATALOG, Path(__file__), ROOT / "bench/benchmark.py", ROOT / "toolchain.json",
             ROOT / "scripts/goose_wasm.py", ROOT / "oracle/goose_wasm.py",
             ROOT / "scripts/run_wasm.mjs", ROOT / "scripts/run_wasmtime.py"]
    for example in examples:
        paths += [ROOT / "examples" / example["file"], ROOT / "examples" / example["expected"]]
    roots = [goose.parent / "stdlib", ROOT / "stdlib"]
    if os.environ.get("GOOSE_STDLIB"):
        roots.append(Path(os.environ["GOOSE_STDLIB"]).expanduser())
    for directory in roots:
        paths += sorted(directory.rglob("*.goose"))
    return paths


def engine_names(backend):
    if backend == "native":
        return ("native",)
    return ("v8", "wasmtime")


def validate_timing(timing, process_seconds):
    for name in ("compile_instantiate_ns", "start_function_ns", "engine_total_ns"):
        if type(timing[name]) is not int or timing[name] < 0:
            raise ValueError("invalid engine timing: " + name)
    if timing["engine_total_ns"] != timing["compile_instantiate_ns"] + timing["start_function_ns"]:
        raise ValueError("engine timing intervals do not add up")
    if timing["engine_total_ns"] / 1e9 > process_seconds:
        raise ValueError("engine timing exceeds process wall time")


def hashes_match(paths):
    try:
        return all(common.digest(Path(path)) == sha for path, sha in paths.items())
    except OSError:
        return False


def tool_paths(args):
    tools = {"python": str(Path(sys.executable).resolve())}
    names = []
    if "native" in args.backends:
        names.append(("cc", args.cc))
    if "c-wasm" in args.backends:
        names.append(("emcc", args.emcc))
    if any(backend != "native" for backend in args.backends):
        names.append(("node", args.node))
        try:
            import wasmtime._ffi as ffi
            tools["wasmtime_library"] = str(Path(ffi.dll._name).resolve())
        except ImportError:
            pass
    for name, executable in names:
        found = shutil.which(executable)
        if found:
            tools[name] = str(Path(found).resolve())
    return tools


def render(report):
    cfg, env = report["configuration"], report["environment"]
    host = env["supplied_machine_label"] or env["cpu"]
    lines = ["# Example program benchmarks", "", "Status: **" + report["status"] + "**.", "",
             report["started_utc"][:10] + " · " + host + ".", "",
             "Goose O2. Direct Wasm uses memory32; C-Wasm uses memory64. "
             "The selected programs, their constant inputs and all printing are unchanged from the "
             "[example catalog](../../../../examples/README.md). Compiler constant folding is allowed.", "",
             "Builds are complete uncached Python-driver invocations, including any C compilation/linking. "
             "OS page caches and Emscripten's installed system-library cache remain warm.", "",
             "Runtime is **whole-process launch-to-exit time**, including host startup, Wasm compilation/instantiation, "
             "program initialization, computation, output delivery and teardown. Each observation starts a fresh "
             "process/instance and calls the entrypoint once. This measures CLI cost, not warmed kernel throughput.", "",
             f"Each cell has {cfg['compile_samples']} build samples or {cfg['samples']} runtime samples. "
             f"Untimed fresh-process warmups per runtime cell: {cfg['warmups']}. Orders are shuffled "
             "with the recorded seed; builds and runtime never overlap. Every used artifact must pass its golden output. "
             "Values are median milliseconds ± median absolute deviation (MAD).", "",
             "Headline runtime samples use the ordinary runners without timing-file instrumentation. "
             "The Wasm supplements use a separate shuffled set of fresh processes, with the same sample count; "
             "timing files are written after their engine intervals end.", "",
             "## Compilation", "", "| Example | Direct | C-Wasm | Native C |", "| --- | ---: | ---: | ---: |"]
    builds = {(r["name"], r["backend"]): r for r in report["compile_summary"]}
    runs = {(r["name"], r["backend"], r["engine"]): r for r in report["runtime_summary"]}

    def cell(summary):
        return f"{summary['median']*1000:.3f} ±{summary['mad']*1000:.3f}"

    for example in report["examples"]:
        name = example["name"]
        values = []
        for backend in BACKENDS:
            value = "—"
            if (name, backend) in builds:
                value = cell(builds[(name, backend)]["wall_seconds"])
            values.append(value)
        lines.append("| " + " | ".join([name, *values]) + " |")
    lines += ["", "## Whole-process runtime", "",
              "| Example | Direct / V8 | C-Wasm / V8 | Direct / Wasmtime | C-Wasm / Wasmtime | Native C |",
              "| --- | ---: | ---: | ---: | ---: | ---: |"]
    columns = (("direct", "v8"), ("c-wasm", "v8"), ("direct", "wasmtime"), ("c-wasm", "wasmtime"), ("native", "native"))
    for example in report["examples"]:
        name = example["name"]
        values = []
        for backend, engine in columns:
            value = "—"
            if (name, backend, engine) in runs:
                value = cell(runs[(name, backend, engine)]["process_wall_seconds"])
            values.append(value)
        lines.append("| " + " | ".join([name, *values]) + " |")
    for metric, title in (("entry_function_seconds", "Supplement: Wasm entrypoint"),
                          ("engine_compile_instantiate_seconds", "Supplement: Wasm engine compilation and instantiation")):
        lines += ["", "## " + title, "",
                  "| Example | Direct / V8 | C-Wasm / V8 | Direct / Wasmtime | C-Wasm / Wasmtime |",
                  "| --- | ---: | ---: | ---: | ---: |"]
        for example in report["examples"]:
            name = example["name"]
            values = []
            for backend, engine in columns[:4]:
                value = "—"
                if (name, backend, engine) in runs:
                    value = cell(runs[(name, backend, engine)][metric])
                values.append(value)
            lines.append("| " + " | ".join([name, *values]) + " |")
    lines += ["", "The entrypoint interval includes Goose initialization, host output callbacks and any lazy JIT work. It excludes final "
              "Wasm-host output concatenation/delivery. Native Goose prints unbuffered, so no native entrypoint "
              "column or cross-boundary speedup is presented. Process time minus engine time also includes loading, "
              "bookkeeping and teardown; it is not a pure startup measurement.", "",
              "These fresh-process examples have different timing rules from LangArena's warmed computational "
              "regions. Raw samples, commands, artifact/source/compiler identities and engine versions are in "
              "[report.json](report.json). [Method and reproduction](../../../examples.md).", ""]
    return "\n".join(lines)


def main():
    manifest = json.loads(CATALOG.read_text())
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", nargs="*")
    parser.add_argument("--goose", type=Path, default=ROOT / "build/bin/goose")
    parser.add_argument("--cc", default=os.environ.get("CC", "gcc"))
    parser.add_argument("--emcc", default=os.environ.get("EMCC", "emcc"))
    parser.add_argument("--node", default="node")
    parser.add_argument("--machine-label", default="")
    parser.add_argument("--compile-samples", type=int, default=5)
    parser.add_argument("--samples", type=int, default=15)
    parser.add_argument("--warmups", type=int, default=1)
    parser.add_argument("--seed", type=int, default=761204)
    parser.add_argument("--smoke", action="store_true", help="allow small correctness-only sample counts")
    parser.add_argument("--backends", nargs="+", choices=BACKENDS, default=list(BACKENDS))
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/example-benchmarks")
    args = parser.parse_args()
    names = {e["name"] for e in manifest["examples"]}
    if manifest["schema"] != "goose-examples-v1" or not names or len(names) != len(manifest["examples"]):
        parser.error("invalid or empty example catalog")
    if manifest["upstream"]["revision"] != json.loads((ROOT / "toolchain.json").read_text())["revision"]:
        parser.error("example catalog does not match the compiler source pin")
    if set(args.examples) - names:
        parser.error("unknown example names")
    if len(args.backends) != len(set(args.backends)):
        parser.error("duplicate backends")
    if min(args.compile_samples, args.samples) < 1 or args.warmups < 0:
        parser.error("sample counts must be positive and warmups nonnegative")
    if not args.smoke and min(args.compile_samples, args.samples) < 5:
        parser.error("performance evidence requires at least five samples; use --smoke for correctness checks")
    args.goose = args.goose.resolve()
    if not args.goose.is_file():
        parser.error("compiler not found; run scripts/bootstrap.py first")
    args.output_dir = args.output_dir.resolve()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "README.md").unlink(missing_ok=True)
    examples = [e for e in manifest["examples"] if not args.examples or e["name"] in args.examples]
    for example in examples:
        origin = example.get("upstream")
        if origin and origin["unchanged"]:
            if common.digest(ROOT / "examples" / example["file"]) != origin["sha256"] or common.digest(ROOT / "examples" / example["expected"]) != origin["expected_sha256"]:
                parser.error("unchanged upstream example was modified: " + example["name"])
    environment = common.metadata(args)
    paths = input_paths(examples, args.goose)
    environment["tool_paths"] = tool_paths(args)
    paths += [Path(p) for p in environment["tool_paths"].values()]
    environment["input_sha256"] = {str(p.resolve()): common.digest(p) for p in paths}
    environment["env_overrides"] = {key: os.environ.get(key) for key in ("NODE_OPTIONS", "CC", "CFLAGS", "EMCC_CFLAGS", "EMCC_CORES", "EM_CACHE", "GOOSE_STDLIB")}
    source_identity = args.goose.parent.parent / "source.json"
    if source_identity.is_file():
        environment["compiler_source_identity"] = json.loads(source_identity.read_text())
    report = {"schema": "goose-example-benchmarks-v1", "status": "running",
              "started_utc": datetime.now(timezone.utc).isoformat(), "environment": environment,
              "configuration": vars(args), "examples": examples, "upstream": manifest["upstream"],
              "observations": [], "compile_summary": [], "runtime_summary": [], "failures": []}
    output = args.output_dir

    def checkpoint(force=False):
        if not force and len(report["observations"]) % 10:
            return
        (output / "report.json").write_text(json.dumps(report, indent=2, default=str) + "\n")

    def execute_example(example, build, engine, phase, sample):
        artifact = Path(build["artifact"])
        row = {"kind": "execution", "phase": phase, "name": example["name"], "backend": build["backend"],
               "engine": engine, "sample": sample, "artifact_sha256": build["artifact_sha256"]}
        directory = output / "runtime" / phase / example["name"] / build["backend"] / engine / str(sample)
        directory.mkdir(parents=True, exist_ok=True)
        command = [artifact]
        timing = directory / "timing.json"
        timing.unlink(missing_ok=True)
        if engine == "v8":
            command = [args.node, ROOT / "scripts/run_wasm.mjs", artifact]
        if engine == "wasmtime":
            command = [sys.executable, ROOT / "scripts/run_wasmtime.py", artifact]
        instrumented = engine != "native" and phase == "measure-engine"
        if instrumented:
            command += ["--timing-json", timing]
        row["command"] = [str(x) for x in command]
        report["observations"].append(row)
        if common.digest(artifact) != build["artifact_sha256"]:
            raise ValueError("artifact changed before execution")
        result, seconds = common.run(command, directory=directory, name="run")
        expected = (ROOT / "examples" / example["expected"]).read_text()
        if result.stdout != expected:
            raise ValueError("golden output mismatch: " + example["name"])
        row.update(status="passed", process_wall_seconds=seconds, stdout_sha256=hashlib.sha256(result.stdout.encode()).hexdigest())
        if instrumented:
            row["wasm_timing"] = json.loads(timing.read_text())
            validate_timing(row["wasm_timing"], seconds)
        checkpoint()
        print("PASS", phase, example["name"], build["backend"], engine, sample, flush=True)

    checkpoint()
    rng = random.Random(args.seed)
    artifacts, unique = {}, {}
    try:
        jobs = list(itertools.product(range(args.compile_samples), examples, args.backends))
        rng.shuffle(jobs)
        for sample, example, backend in jobs:
            directory = output / "compile" / example["name"] / backend / str(sample)
            artifact = directory / "program.wasm"
            if backend == "native":
                artifact = directory / "program.bin"
            stats = directory / "driver-stats.json"
            command = [sys.executable, ROOT / "scripts/goose_wasm.py", "build", ROOT / "examples" / example["file"],
                       "--backend", backend, "--goose", args.goose, "--offline", "--no-cache", "-O2", "-o", artifact, "--stats", stats]
            if backend != "direct":
                command += ["--cc", args.cc, "--emcc", args.emcc]
            row = {"kind": "build", "name": example["name"], "backend": backend, "sample": sample,
                   "command": [str(x) for x in command], "artifact": str(artifact)}
            report["observations"].append(row)
            _, seconds = common.run(command, directory=directory, name="build")
            row.update(status="passed", wall_seconds=seconds, artifact_sha256=common.digest(artifact),
                       module_bytes=artifact.stat().st_size, driver_stats=json.loads(stats.read_text()))
            artifacts[(example["name"], backend)] = row
            unique[(example["name"], backend, row["artifact_sha256"])] = (example, row)
            checkpoint()
            print("PASS build", example["name"], backend, sample, flush=True)
        for number, (example, build) in enumerate(unique.values()):
            for engine in engine_names(build["backend"]):
                execute_example(example, build, engine, "qualification", number)
        cells = [(e, artifacts[(e["name"], b)], engine) for e in examples for b in args.backends for engine in engine_names(b)]
        for phase, count in (("warmup", args.warmups), ("measure", args.samples)):
            jobs = list(itertools.product(range(count), cells))
            rng.shuffle(jobs)
            for sample, (example, build, engine) in jobs:
                execute_example(example, build, engine, phase, sample)
        jobs = list(itertools.product(range(args.samples), [cell for cell in cells if cell[2] != "native"]))
        rng.shuffle(jobs)
        for sample, (example, build, engine) in jobs:
            execute_example(example, build, engine, "measure-engine", sample)
        for example, backend in itertools.product(examples, args.backends):
            rows = [r for r in report["observations"] if r["kind"] == "build" and r["name"] == example["name"] and r["backend"] == backend]
            report["compile_summary"].append({"name": example["name"], "backend": backend,
                "wall_seconds": common.summary([r["wall_seconds"] for r in rows]), "module_bytes": rows[-1]["module_bytes"],
                "unique_artifacts": len({r["artifact_sha256"] for r in rows})})
        for example, build, engine in cells:
            rows = [r for r in report["observations"] if r["kind"] == "execution" and r["phase"] == "measure" and
                    r["name"] == example["name"] and r["backend"] == build["backend"] and r["engine"] == engine]
            summary = {"name": example["name"], "backend": build["backend"], "engine": engine,
                       "process_wall_seconds": common.summary([r["process_wall_seconds"] for r in rows])}
            if engine != "native":
                engine_rows = [r for r in report["observations"] if r["kind"] == "execution" and r["phase"] == "measure-engine" and
                               r["name"] == example["name"] and r["backend"] == build["backend"] and r["engine"] == engine]
                summary["entry_function_seconds"] = common.summary([r["wasm_timing"]["start_function_ns"] / 1e9 for r in engine_rows])
                summary["engine_compile_instantiate_seconds"] = common.summary([r["wasm_timing"]["compile_instantiate_ns"] / 1e9 for r in engine_rows])
            report["runtime_summary"].append(summary)
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.TimeoutExpired) as error:
        report["failures"].append(str(error))
        if report["observations"]:
            report["observations"][-1].update(status="failed", error=str(error))
    report["source_hashes_still_match"] = hashes_match(environment["input_sha256"])
    discovered = {str(p.resolve()) for p in input_paths(examples, args.goose)}
    discovered.update(environment["tool_paths"].values())
    report["input_paths_still_match"] = discovered == set(environment["input_sha256"])
    report["compiler_hash_still_matches"] = hashes_match({str(args.goose): environment["compiler_sha256"]})
    report["artifact_hashes_still_match"] = hashes_match({r["artifact"]: r["artifact_sha256"] for r in report["observations"] if r["kind"] == "build" and r.get("status") == "passed"})
    passed = not report["failures"] and report["source_hashes_still_match"] and report["input_paths_still_match"] and report["compiler_hash_still_matches"] and report["artifact_hashes_still_match"]
    report["status"] = "failed"
    if passed:
        report["status"] = "passed"
        if args.smoke:
            report["status"] = "passed-smoke"
    report["finished_utc"] = datetime.now(timezone.utc).isoformat()
    checkpoint(force=True)
    if passed:
        (output / "README.md").write_text(render(report))
    print(report["status"], len(report["observations"]), "observations;", output / "report.json")
    return int(not passed)


if __name__ == "__main__":
    sys.exit(main())
