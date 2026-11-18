"""Pair fresh-process self-builds on frozen sources, with a primed Wasmtime cache."""

import argparse
import json
import os
from pathlib import Path
import resource
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path[:0] = [str(ROOT / "bench"), str(ROOT / "scripts"),
                str(ROOT / "bench/results/2026-11-18/selfhost-wasm-runtime/tools")]
from selfhost_comparison import SOURCE, WASM_FLAGS, identity, verify_frozen_source
from measure import measured


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path, help="frozen selfhost_comparison build")
    parser.add_argument("work", type=Path, help="scratch output and module caches")
    parser.add_argument("cases", nargs="+", metavar="NAME=COMPILER")
    parser.add_argument("--rounds", type=int, default=6)
    parser.add_argument("--cpu", type=int, default=7)
    parser.add_argument("--host", action="append", default=[], metavar="NAME=HOST",
                        help="use an alternative Wasmtime executable for a named Wasm case")
    args = parser.parse_args()
    stage, work = args.stage.resolve(), args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    source = stage / "source"
    manifest = json.loads((stage / "builds.json").read_bytes())
    verify_frozen_source(source, manifest["source_commit"], manifest["source_archive_sha256"])
    host = ROOT / "host/rust/target/release/goose-wasmtime"
    hosts = {}
    for override in args.host:
        name, path = override.split("=", 1)
        if name in hosts:
            parser.error(f"Duplicate host override for {name}")
        hosts[name] = Path(path).resolve()
    output, timer = work / "output.wasm", work / "engine.json"
    reference = identity(stage / "build-1/compiler.wasm")
    report = dict(source_commit=manifest["source_commit"],
                  source_archive_sha256=manifest["source_archive_sha256"],
                  expected=reference, host=identity(host), cpu=args.cpu,
                  arguments=[*SOURCE, *WASM_FLAGS], cases={}, samples=[])
    resource.setrlimit(resource.RLIMIT_STACK, (256 << 20, resource.getrlimit(resource.RLIMIT_STACK)[1]))
    commands = {}
    for case in args.cases:
        label, path = case.split("=", 1)
        compiler = Path(path).resolve()
        if label in commands or not label.replace("-", "").isalnum():
            raise ValueError(f"Invalid or duplicate case {label}")
        command = [compiler]
        meta = dict(compiler=identity(compiler))
        if compiler.suffix == ".wasm":
            case_host = hosts.pop(label, host)
            meta["host"] = identity(case_host)
            cache = work / (label + "-" + meta["host"]["sha256"][:16] + ".cwasm")
            subprocess.run([case_host, compiler, "--cache", cache, "--", "--version"],
                           cwd=source, check=True, stdout=subprocess.DEVNULL)
            assert cache.with_suffix(".cwasm.sha256").read_text().strip() == meta["compiler"]["sha256"]
            meta["cache"] = identity(cache)
            command = [case_host, compiler, "--cache", cache, "--timing-json", timer, "--"]
        commands[label] = [*command, *SOURCE, *WASM_FLAGS, "-o", output]
        report["cases"][label] = meta
    if hosts:
        parser.error(f"Host override without a matching Wasm case: {', '.join(hosts)}")
    os.sched_setaffinity(0, {args.cpu})
    for i in range(args.rounds):
        labels = list(commands)
        if i % 2:
            labels.reverse()
        for label in labels:
            output.unlink(missing_ok=True)
            timer.unlink(missing_ok=True)
            before = resource.getrusage(resource.RUSAGE_CHILDREN)
            proc, wall, counters = measured(
                lambda: subprocess.run(commands[label], cwd=source, capture_output=True), child=True)
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            if proc.returncode or proc.stderr:
                raise RuntimeError((label, proc.returncode, proc.stderr.decode(errors="replace")))
            actual = identity(output)
            if actual != reference:
                raise ValueError((label, actual, reference))
            row = dict(round=i+1, case=label, wall_ns=wall, output=actual,
                       cpu_s=after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime,
                       counters=counters)
            if timer.is_file():
                row["engine"] = json.loads(timer.read_bytes())
            report["samples"].append(row)
            (work / "paired.json").write_text(json.dumps(report, indent=2) + "\n")
            print(i + 1, label, round(wall / 1e9, 3), flush=True)


if __name__ == "__main__":
    main()
