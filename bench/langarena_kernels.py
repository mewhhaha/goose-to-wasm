#!/usr/bin/env python3
"""Run original LangArena kernels, including their dynamic storage.

Only the suite's configuration/entry/timing harness is replaced. The selected
kernel and helper sources are copied byte for byte from the pinned checkout.
This track complements the original whole program and bounded historical ports;
it does not count as running the whole 50-task application on Wasm.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import random
import shutil
import signal
import sys

from langarena import (ROOT, REVISION, build_command, engine_command, execute,
                      load_engine_timing, load_manifest, metadata, parse_port_result, port_stdin, sha256,
                      summarize, verify_upstream)

FACTORIES = {
    "CLBG::Fannkuchredux": ("fannkuchredux", "new_fannkuchredux"),
    "Etc::Sieve": ("sieve", "new_sieve"),
    "Sort::Quick": ("sort", "new_sort_quick"),
    "Sort::Merge": ("sort", "new_sort_merge"),
    "Hash::SHA256": ("buffer_hash", "new_buffer_hash_sha256"),
    "Hash::CRC32": ("buffer_hash", "new_buffer_hash_crc32"),
    "CLBG::Mandelbrot": ("mandelbrot", "new_mandelbrot"),
}
ACTIVE_CHECKPOINT = None


def stage(upstream, destination, case):
    source = destination / "source"
    shutil.copytree(upstream / "goose/src", source, dirs_exist_ok=True)
    fields = case["port"]["fields"]
    # Configuration lookup is outside the timed region. Match byte keys
    # explicitly so the adapter does not need the suite's JSON/file/argv host.
    body = ['var kernel_config: i64[8] = [0; 8];',
            'fn config_i64(name: const u8[:], key: const u8[:]) -> i64 {']
    for index, name in enumerate(fields):
        comparisons = [f"key.len == {len(name)}"] + [f"key[{i}] == {byte}" for i, byte in enumerate(name.encode())]
        body.append(f"    if {' && '.join(comparisons)} {{ return kernel_config[{index}]; }}")
    body += ['    abort("unmapped kernel configuration key");', '    0', '}']
    (source / "bench.goose").write_text("\n".join(body) + "\n")
    module, factory = FACTORIES[case["name"]]
    main = [f"import {module};", "import bench;", "import helper;",
            "extern fn bench_input() -> i64;", "extern fn bench_clock() -> i64;",
            "let ARENA_REVISION = 0;", "fn main() {"]
    main += [f"    kernel_config[{i}] = bench_input();" for i in range(len(fields))]
    main += ["    let iterations = bench_input();", "    let warmups = bench_input();",
             f"    var state = {module}::{factory}();", "    reset();",
             f"    {module}::prepare(state);",
             f"    for i in warmups {{ {module}::run(state, i); }}", "    reset();",
             "    let before = bench_clock();",
             f"    for i in iterations {{ {module}::run(state, i); }}",
             "    let elapsed = bench_clock() - before;",
             f"    print({module}::checksum(state));", "    print(elapsed);",
             "    exit(ARENA_REVISION);", "}"]
    entry = source / "main.goose"
    entry.write_text("\n".join(main) + "\n")
    unchanged = {}
    for path in source.glob("*.goose"):
        if path.name in ("main.goose", "bench.goose"):
            continue
        expected = sha256(upstream / "goose/src" / path.name)
        if sha256(path) != expected:
            raise ValueError(f"kernel source changed while staging: {path}")
        unchanged[path.name] = expected
    return entry, {"unchanged_source_sha256": unchanged,
                   "harness_sha256": {name: sha256(source / name) for name in ("main.goose", "bench.goose")}}


def main():
    global ACTIVE_CHECKPOINT
    def terminated(signum, _frame):
        raise SystemExit(128 + signum)
    signal.signal(signal.SIGTERM, terminated)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, default=ROOT / "build/langarena-upstream")
    parser.add_argument("--goose", type=Path, default=ROOT / "build/bin/goose")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/langarena-kernels")
    parser.add_argument("--profiles", nargs="+", choices=("test", "run"), default=["test", "run"])
    parser.add_argument("--backends", nargs="+", choices=("native", "c-wasm", "direct"), default=["native", "c-wasm", "direct"])
    parser.add_argument("--engines", nargs="+", choices=("v8", "wasmtime"), default=["v8", "wasmtime"])
    parser.add_argument("--samples", type=int, default=1)
    parser.add_argument("--maximum-pages", type=int, default=1024,
                        help="direct memory ceiling; original dynamic storage uses 64MiB by default")
    parser.add_argument("--filter", default="")
    parser.add_argument("--node", default="node")
    parser.add_argument("--cc", default="gcc")
    parser.add_argument("--emcc", default="emcc")
    parser.add_argument("--machine-label", default="")
    args = parser.parse_args()
    if args.samples < 1 or ("run" in args.profiles and "test" not in args.profiles):
        parser.error("positive sample count and test qualification before run are required")
    args.upstream = args.upstream.resolve()
    args.goose = args.goose.resolve()
    args.output_dir = args.output_dir.resolve()
    for name in ("node", "cc", "emcc"):
        value = getattr(args, name)
        found = shutil.which(value)
        if found or Path(value).is_file():
            setattr(args, name, str(Path(found or value).resolve()))
    manifest = load_manifest()
    verify_upstream(args.upstream, manifest)
    selected = [case for case in manifest["cases"] if case["name"] in FACTORIES and args.filter.lower() in case["name"].lower()]
    if not selected:
        parser.error("no selected original kernels")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    report = {"schema": "goose-langarena-original-kernels-v1", "status": "incomplete",
              "started_utc": datetime.now(timezone.utc).isoformat(), "upstream_revision": REVISION,
              "configuration": {k: str(v) if isinstance(v, Path) else v for k, v in vars(args).items()},
              "environment": metadata(args, manifest), "source_contract":
              "Original kernel/storage/helper bytes; generated entry/config/timing harness; same official inputs, RNG resets, warmup state, and checksums. Not the whole original application.",
              "coverage": [{"task": case["name"], "entrypoint_available": case["name"] in FACTORIES} for case in manifest["cases"]],
              "sources": {}, "observations": []}
    report["environment"]["kernel_harness_sha256"] = sha256(Path(__file__))

    def checkpoint():
        path = args.output_dir / "report.json"
        temporary = path.with_suffix(".tmp")
        temporary.write_text(json.dumps(report, indent=2) + "\n")
        temporary.replace(path)

    def record(row):
        report["observations"].append(row)
        print(row["status"].upper(), row["task"], row["backend"], row.get("engine", "build"), row.get("profile", ""),
              row.get("error", ""), flush=True)
        checkpoint()

    ACTIVE_CHECKPOINT = report, checkpoint
    checkpoint()
    artifacts = {}
    staged_hashes = {}
    for case in selected:
        name = case["name"]
        slug = name.lower().replace("::", "-")
        base = args.output_dir / slug
        entry, evidence = stage(args.upstream, base, case)
        report["sources"][name] = evidence
        staged_hashes.update({str(path): sha256(path) for path in entry.parent.glob("*.goose")})
        for backend in args.backends:
            directory = base / backend
            directory.mkdir(parents=True, exist_ok=True)
            artifact = directory / ("program.bin" if backend == "native" else "program.wasm")
            args.current_backend = backend
            command = build_command(args, entry, artifact, directory / "build-stats.json", port=True)
            command += ["--maximum-pages", str(args.maximum_pages)]
            observed = execute(command, directory / "build", cwd=ROOT)
            row = {"kind": "build", "task": name, "backend": backend, **observed}
            if observed["returncode"]:
                row.update(status="failed", error=observed["stderr"][-3000:] or observed["stdout"][-3000:])
            else:
                row.update(status="passed", artifact_bytes=artifact.stat().st_size, artifact_sha256=sha256(artifact))
                artifacts[(name, backend)] = artifact
            record(row)
    qualified = set()
    randomizer = random.Random(20261027)
    for profile in ("test", "run"):
        if profile not in args.profiles:
            continue
        jobs = [(case, backend, engine, sample) for case in selected for backend in args.backends
                for engine in (["native"] if backend == "native" else args.engines)
                for sample in range(1 if profile == "test" else args.samples)]
        randomizer.shuffle(jobs)
        for case, backend, engine, sample in jobs:
            key = case["name"], backend
            if key not in artifacts:
                continue
            if profile == "run" and (*key, engine) not in qualified:
                record({"kind": "execution", "task": case["name"], "backend": backend,
                        "engine": engine, "profile": profile, "sample": sample, "status": "failed",
                        "error": "production run blocked by failed official test qualification"})
                continue
            artifact = artifacts[key]
            directory = artifact.parent / f"{profile}-{engine}-{sample}"
            timing = directory / "timing.json"
            timing.unlink(missing_ok=True)
            observed = execute(engine_command(args, artifact, engine, timing), directory,
                               cwd=directory, stdin=port_stdin(case, profile))
            row = {"kind": "execution", "task": case["name"], "backend": backend, "engine": engine,
                   "profile": profile, "sample": sample, **observed}
            try:
                row.update(parse_port_result(observed["stdout"], observed["returncode"], case[profile]["checksum"]))
                if engine != "native":
                    row["engine_timing"] = load_engine_timing(timing)
                row["status"] = "passed"
                qualified.add((*key, engine))
            except (OSError, ValueError) as error:
                row.update(status="failed", error=str(error))
            record(row)
    summaries = {}
    for row in report["observations"]:
        if row["kind"] == "execution" and row["status"] == "passed":
            key = (row["task"], row["backend"], row["engine"], row["profile"])
            summaries.setdefault(key, []).append(row["timed_region_seconds"])
    report["runtime_summary"] = [{"task": k[0], "backend": k[1], "engine": k[2], "profile": k[3],
                                  "seconds": summarize(v)} for k, v in sorted(summaries.items())]
    expected_hashes = {str(ROOT / path): digest for path, digest in report["environment"]["input_sha256"].items()}
    expected_hashes.update(report["environment"]["installed_stdlib_sha256"])
    expected_hashes.update(staged_hashes)
    expected_hashes[str(args.goose)] = report["environment"]["compiler_sha256"]
    expected_hashes[str(Path(__file__).resolve())] = report["environment"]["kernel_harness_sha256"]
    changed = [path for path, digest in expected_hashes.items()
               if not Path(path).is_file() or sha256(Path(path)) != digest]
    report["changed_inputs"] = changed
    failures = sum(row["status"] != "passed" for row in report["observations"]) + bool(changed)
    report.update(failures=failures, status="failed" if failures else "passed",
                  finished_utc=datetime.now(timezone.utc).isoformat())
    checkpoint()
    print(f"{len(report['observations']) - failures}/{len(report['observations'])} observations passed; {args.output_dir / 'report.json'}")
    return int(failures != 0)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BaseException as error:
        if ACTIVE_CHECKPOINT is not None:
            report, checkpoint = ACTIVE_CHECKPOINT
            if report["status"] == "incomplete":
                report["status"] = "interrupted" if isinstance(error, (KeyboardInterrupt, SystemExit)) else "failed"
                report["error"] = str(error)
                report["finished_utc"] = datetime.now(timezone.utc).isoformat()
                checkpoint()
        raise
