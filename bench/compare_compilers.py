#!/usr/bin/env python3
"""Compare cold C++/Goose compiler processes emitting Wasm and standalone C.

C compilation and golden-output validation happen after the timed campaign.
The C++ compiler is a benchmark competitor, never a correctness oracle.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import importlib.metadata
import itertools
import json
import os
from pathlib import Path
import random
import resource
import shutil
import sys

import langbench as cold

ROOT = cold.ROOT
COMPILERS = ("cpp", "parent", "candidate")
TARGETS = ("wasm-direct", "native-c")
CPP = ROOT / "build/next-runtime-hills/final/bin/goose"
CPP_IDENTITY = ROOT / "bench/results/2026-11-04/leaf-and-loads/compiler-identity.json"
C_FLAGS = ["-std=gnu11", "-O2", "-fno-strict-aliasing", "-rdynamic"]


def workloads() -> list[dict]:
    manifest = json.loads((ROOT / "examples/manifest.json").read_text())
    cases = []
    for item in manifest["examples"]:
        source = ROOT / "examples" / item["file"]
        expected = ROOT / "examples" / item["expected"]
        cases.append(dict(name=item["name"], source=str(source), source_sha256=cold.sha256(source),
                          expected_path=str(expected), expected_sha256=cold.sha256(expected), stdin=""))
    source = ROOT / "bench/langbench/mandelbrot.goose"
    cases.append(dict(name="mandelbrot", source=str(source), source_sha256=cold.sha256(source),
                      checksum=636, stdin="8 25 1\n"))
    return cases


def build_command(compiler, name, case, target, artifact, stdlib):
    command = [compiler, case["source"], "--stdlib", stdlib, "-O2", "--target"]
    if target == "wasm-direct":
        command += ["wasm-direct", "--wasm-initial-pages", "16", "--wasm-max-pages", "256"]
    else:
        command += ["native"]
        if name == "cpp":
            command += ["--standalone"]
    return [*command, "-o", artifact]


def resource_usage_delta(before, after):
    utime = after.ru_utime - before.ru_utime
    stime = after.ru_stime - before.ru_stime
    return dict(utime_seconds=utime, stime_seconds=stime, total_cpu_seconds=utime + stime,
                major_faults=after.ru_majflt - before.ru_majflt,
                minor_faults=after.ru_minflt - before.ru_minflt,
                voluntary_context_switches=after.ru_nvcsw - before.ru_nvcsw,
                involuntary_context_switches=after.ru_nivcsw - before.ru_nivcsw,
                block_input_operations=after.ru_inblock - before.ru_inblock,
                block_output_operations=after.ru_oublock - before.ru_oublock)


def result_matches(result, case):
    if result["status"] != "passed" or result["stderr"]:
        return False
    if "checksum" in case:
        try:
            cold.parse_result(result["stdout"], result["exit_code"], case["checksum"], "goose-native")
        except ValueError:
            return False
        return True
    return result["stdout"] == Path(case["expected_path"]).read_text()


def summaries(report):
    rows = []
    for compiler, case, target in itertools.product(compiler_order(report), report["workloads"], TARGETS):
        builds = [b for b in report["builds"] if (b["compiler"], b["workload"], b["target"]) ==
                  (compiler, case["name"], target)]
        samples = [b for b in builds if b["phase"] == "measurement"]
        warmups = [b for b in builds if b["phase"] == "warmup"]
        valid = [b for b in samples if b["status"] == "passed" and
                 report["validations"].get(b.get("validation_key"), {}).get("status") == "passed"]
        all_valid = all(b["status"] == "passed" and report["validations"].get(
            b.get("validation_key"), {}).get("status") == "passed" for b in builds)
        qualified = (len(samples) == report["samples"] and len(valid) == report["samples"] and
                     sorted(b["round"] for b in samples) == list(range(report["samples"])) and
                     len(warmups) == 1 and warmups[0]["round"] == -1 and all_valid)
        row = dict(compiler=compiler, workload=case["name"], target=target, qualified=qualified,
                   expected_samples=report["samples"], valid_samples=len(valid),
                   compile_wall_seconds=None, failures=[b for b in builds if b["status"] != "passed"],
                   validation_failures=sorted({b["validation_key"] for b in builds if b.get("validation_key") and
                       report["validations"].get(b["validation_key"], {}).get("status") == "failed"}))
        if qualified:
            row["compile_wall_seconds"] = cold.summarize([b["wall_seconds"] for b in samples])
        rows.append(row)
    return rows


def compiler_order(report):
    if "compiler_order" in report:
        order = report["compiler_order"]
        if isinstance(order, (list, tuple)):
            return tuple(order)
        return ()
    if "compilers" in report:
        return tuple(report["compilers"])
    return COMPILERS


def validate(artifact, case, target, args, directory):
    commands = []
    if target == "native-c":
        executable = directory / "program"
        command = [args.cc, *C_FLAGS, artifact]
        if "checksum" in case:
            command.append(ROOT / "bench/host_input.c")
        command += ["-lm", "-ldl", "-pthread", "-o", executable]
        commands.append(cold.invoke(command, cpu=args.cpu, timeout=args.timeout))
        if commands[-1]["status"] == "passed" and executable.is_file():
            commands[-1]["executable_sha256"] = cold.sha256(executable)
            commands.append(cold.invoke([executable], stdin=case["stdin"], cpu=args.cpu, timeout=args.timeout))
        qualified = len(commands) == 2 and result_matches(commands[-1], case)
    else:
        for command in ([args.node, ROOT / "scripts/run_wasm.mjs", artifact],
                        [sys.executable, ROOT / "scripts/run_wasmtime.py", artifact]):
            commands.append(cold.invoke(command, stdin=case["stdin"], cpu=args.cpu, timeout=args.timeout))
        qualified = all(result_matches(result, case) for result in commands)
    return dict(status="passed" if qualified else "failed", commands=commands)


def save(report, output):
    report["summary"] = summaries(report)
    pending = output / "report.json.tmp"
    pending.write_text(json.dumps(report, indent=2) + "\n")
    pending.replace(output / "report.json")


def parser():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--cpp", type=Path, default=CPP)
    cli.add_argument("--parent", type=Path, required=True)
    cli.add_argument("--candidate", type=Path, required=True)
    cli.add_argument("--parent-source", type=Path, required=True)
    cli.add_argument("--candidate-source", type=Path, required=True, help="frozen candidate .goose source root; caller supplies binary/source linkage evidence")
    cli.add_argument("--parent-label", default="Previous Goose")
    cli.add_argument("--candidate-label", default="Current Goose")
    cli.add_argument("--stdlib", type=Path, default=ROOT / "stdlib")
    cli.add_argument("--samples", type=int, default=5)
    cli.add_argument("--cpu", type=int, default=7)
    cli.add_argument("--seed", type=int, default=580058)
    cli.add_argument("--timeout", type=float, default=120)
    cli.add_argument("--cc", default="gcc")
    cli.add_argument("--node", default="node")
    cli.add_argument("--filter", default="", help="optional workload name substring; selection is recorded")
    cli.add_argument("--output-dir", type=Path, required=True, help="must not already exist")
    return cli


def main():
    cli = parser()
    args = cli.parse_args()
    if args.samples < 1 or args.timeout <= 0:
        cli.error("samples and timeout must be positive")
    if args.cpu not in os.sched_getaffinity(0):
        cli.error("CPU is outside process affinity")
    compilers = {"cpp": args.cpp.resolve(), "parent": args.parent.resolve(), "candidate": args.candidate.resolve()}
    for source_root in (args.parent_source, args.candidate_source):
        if not (source_root / "main.goose").is_file():
            cli.error(f"compiler source root has no main.goose: {source_root}")
    for executable in [*compilers.values(), Path(shutil.which(args.cc) or args.cc), Path(shutil.which(args.node) or args.node)]:
        if not executable.is_file():
            cli.error(f"executable is missing: {executable}")
    cases = [case for case in workloads() if args.filter in case["name"]]
    if not cases:
        cli.error("no workloads selected")
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=False)
    paths = [Path(__file__), Path(cold.__file__), Path(cold.process.__file__),
             ROOT / "examples/manifest.json", ROOT / "bench/langbench/manifest.json", ROOT / "bench/host_input.c",
             ROOT / "scripts/run_wasm.mjs", ROOT / "scripts/run_wasmtime.py", args.stdlib, CPP_IDENTITY,
             *[Path(case["source"]) for case in cases],
             *[Path(case["expected_path"]) for case in cases if "expected_path" in case],
             *sorted(args.parent_source.glob("*.goose")), *sorted(args.candidate_source.glob("*.goose")),
             *sorted((ROOT / "native").rglob("*.h")),
             *compilers.values(), Path(sys.executable), Path(shutil.which(args.cc)), Path(shutil.which(args.node))]
    import wasmtime._ffi as ffi
    paths.append(Path(ffi.dll._name))
    identities = cold.fingerprint(paths)
    cpp_identity = json.loads(CPP_IDENTITY.read_text())
    report = dict(schema="goose-compiler-comparison-v2", status="incomplete",
                  started_utc=datetime.now(timezone.utc).isoformat(), samples=args.samples,
                  configuration={key: str(value) for key, value in vars(args).items()},
                  method="Fresh compiler process per build; retained OS caches; Goose -O2. One unmeasured warmup per cell, followed by shuffled balanced rounds. Front-end bars end after Wasm/C emission; C compiler and golden-output execution run only after the timed campaign. C++ is a benchmark competitor, never an oracle. No Zig compiler is measured.",
                  compiler_order=list(COMPILERS),
                  compiler_labels={"cpp": "Previous C++", "parent": args.parent_label,
                                   "candidate": args.candidate_label},
                  compilers={name: dict(path=str(path), sha256=cold.sha256(path)) for name, path in compilers.items()},
                  cpp_source_identity=cpp_identity,
                  cpp_source_identity_matches=cpp_identity["compiler_sha256"] == cold.sha256(args.cpp),
                  compiler_source_roots={"parent": str(args.parent_source.resolve()), "candidate": str(args.candidate_source.resolve())},
                  compiler_source_linkage="Caller-supplied frozen source roots; fingerprints identify those files. Binary/source build linkage belongs to the separate compiler qualification evidence.",
                  workloads=cases, builds=[], validations={}, summary=[], input_fingerprints=identities,
                  machine_before=cold.machine_state(),
                  toolchain=dict(c_flags=C_FLAGS, wasmtime=importlib.metadata.version("wasmtime"),
                                 versions=[cold.invoke(command, timeout=30) for command in (
                                     [args.cc, "--version"], [args.node, "-p", "JSON.stringify(process.versions)"],
                                     [sys.executable, "--version"], *[[p, "--help"] for p in compilers.values()])]))
    rng = random.Random(args.seed)
    cells = list(itertools.product(COMPILERS, cases, TARGETS))
    save(report, output)
    # No validation or machine-code C compilation enters this timing window.
    for sample in range(-1, args.samples):
        order = list(cells)
        rng.shuffle(order)
        for name, case, target in order:
            directory = output / "builds" / str(sample) / name / case["name"] / target
            directory.mkdir(parents=True)
            suffix = ".wasm" if target == "wasm-direct" else ".c"
            artifact = directory / ("program" + suffix)
            command = build_command(compilers[name], name, case, target, artifact, args.stdlib.resolve())
            row = dict(compiler=name, workload=case["name"], target=target, round=sample,
                       phase="measurement", artifact=str(artifact))
            if sample < 0:
                row["phase"] = "warmup"
            usage_before = resource.getrusage(resource.RUSAGE_CHILDREN)
            result = cold.invoke(command, cpu=args.cpu, timeout=args.timeout)
            usage_after = resource.getrusage(resource.RUSAGE_CHILDREN)
            row.update(result)
            row["resource_usage"] = resource_usage_delta(usage_before, usage_after)
            if row["status"] == "passed":
                if artifact.is_file() and artifact.stat().st_size:
                    row["artifact_sha256"] = cold.sha256(artifact)
                    contract = case.get("expected_sha256", str(case.get("checksum")))
                    row["validation_key"] = ":".join([target, row["artifact_sha256"], contract])
                else:
                    row.update(status="failed", error="compiler emitted no nonempty artifact")
            report["builds"].append(row)
        save(report, output)
    cases_by_name = {case["name"]: case for case in cases}
    for row in report["builds"]:
        if row["status"] != "passed" or row["validation_key"] in report["validations"]:
            continue
        artifact = Path(row["artifact"])
        if not artifact.is_file() or cold.sha256(artifact) != row["artifact_sha256"]:
            report["validations"][row["validation_key"]] = dict(status="failed", error="artifact changed before validation", commands=[])
            continue
        directory = output / "validations" / str(len(report["validations"]))
        directory.mkdir(parents=True)
        report["validations"][row["validation_key"]] = validate(artifact, cases_by_name[row["workload"]], row["target"], args, directory)
        save(report, output)
    report["machine_after"] = cold.machine_state()
    report["input_fingerprints_after"] = cold.fingerprint(paths)
    report["inputs_unchanged"] = report["input_fingerprints_after"] == identities
    report["artifacts_unchanged"] = all(Path(row["artifact"]).is_file() and cold.sha256(Path(row["artifact"])) == row["artifact_sha256"]
                                         for row in report["builds"] if "artifact_sha256" in row)
    report["finished_utc"] = datetime.now(timezone.utc).isoformat()
    save(report, output)
    report["status"] = "failed"
    if report["inputs_unchanged"] and report["artifacts_unchanged"] and all(row["qualified"] for row in report["summary"]):
        report["status"] = "passed"
    save(report, output)
    print(json.dumps(dict(status=report["status"], cells=len(report["summary"]),
                         qualified=sum(row["qualified"] for row in report["summary"]), report=str(output / "report.json"))))
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
