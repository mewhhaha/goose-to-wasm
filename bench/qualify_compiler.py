#!/usr/bin/env python3
"""Run the independent frozen-contract suite against one Goose compiler."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CONFORMANCE = ROOT / "tests" / "conformance.py"
MANIFEST = ROOT / "tests" / "conformance" / "cases.json"
ARCHIVE = ROOT / "tests" / "conformance" / "upstream.tar.gz"


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=ROOT / "build" / "bin" / "goose")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--filter", default="", help="optional case-id substring")
    parser.add_argument("--jobs", type=int, default=1,
                        help="accepted for old command lines; frozen conformance runs as one suite")
    parser.add_argument("--levels", nargs="+", type=int, choices=(0, 2), default=[0, 2])
    parser.add_argument("--engine", choices=("wasmtime", "v8"), default="wasmtime")
    parser.add_argument("--host", type=Path, help="optional Goose Wasmtime host")
    parser.add_argument("--cc", default="gcc")
    parser.add_argument("--frontend-only", action="store_true")
    args = parser.parse_args()

    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    run_name = datetime.now(timezone.utc).strftime("conformance-%Y%m%dT%H%M%S-%fZ")
    run_output = output / run_name
    compiler = args.goose.resolve()
    inputs = [Path(__file__).resolve(), CONFORMANCE, MANIFEST, ARCHIVE, compiler,
              ROOT / "toolchain.json", ROOT / "selfhost" / "bootstrap.py",
              ROOT / "bootstrap" / "seed.json", ROOT / "bootstrap" / "seed.c.gz",
              ROOT / "bootstrap" / "sources.tar.gz"]
    inputs += sorted((ROOT / "selfhost").glob("*.goose"))
    inputs += sorted((ROOT / "stdlib").rglob("*.goose"))
    fingerprints = {str(path.resolve()): digest(path) for path in inputs}
    report_path = output / "report.json"
    report = {"schema": "goose-compiler-qualification-v2", "status": "running",
              "started_utc": datetime.now(timezone.utc).isoformat(),
              "configuration": {"compiler": str(compiler), "output_dir": str(output),
                  "filter": args.filter, "levels": args.levels, "engine": args.engine,
                  "host": str(args.host.resolve()) if args.host else None,
                  "frontend_only": args.frontend_only},
              "input_sha256": fingerprints, "conformance_report": str(run_output / "report.json"),
              "log_file": str(output / "conformance.log"),
              "failures": []}
    report_path.write_text(json.dumps(report, indent=2) + "\n")

    command = [sys.executable, CONFORMANCE, "--compiler", compiler, "--output-dir", run_output,
               "--manifest", MANIFEST, "--stdlib", ROOT / "stdlib", "--filter", args.filter,
               "--levels", *map(str, args.levels), "--engine", args.engine, "--cc", args.cc]
    if args.host:
        command += ["--host", args.host.resolve()]
    if args.frontend_only:
        command.append("--frontend-only")
    report["command"] = list(map(str, command))
    try:
        with (output / "conformance.log").open("w") as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=False)
        report["exit_code"] = result.returncode
        report["log_sha256"] = digest(output / "conformance.log")
    except OSError as error:
        report["exit_code"] = -1
        report["failures"].append(str(error))

    child_path = run_output / "report.json"
    if child_path.is_file():
        child = json.loads(child_path.read_text())
        report["conformance_status"] = child.get("status")
        report["conformance_summary"] = child.get("summary")
        report["conformance_report_sha256"] = digest(child_path)
    after = {path: digest(path) for path in fingerprints}
    report["input_sha256_after"] = after
    if after != fingerprints:
        report["failures"].append("qualification inputs changed during the run")
    report["finished_utc"] = datetime.now(timezone.utc).isoformat()
    report["status"] = "passed"
    if report["exit_code"] != 0 or report["failures"] or report.get("conformance_status") != "passed":
        report["status"] = "failed"
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    print(report["status"], report.get("conformance_summary", {}), "report:", report_path)
    return int(report["status"] != "passed")


if __name__ == "__main__":
    sys.exit(main())
