"""Run and merge the complete differential matrix in backend/level shards."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

BACKENDS = ("native", "c-wasm", "direct")
LEVELS = (0, 2)
ENGINES = ("v8", "wasmtime")
REFUSALS = {"unsupported_varint_array", "unsupported_pointer_extern", "invalid_source"}
ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def expected_configuration(backend, level, filter_text):
    return {"backends": [backend], "levels": [level], "filter": filter_text,
            "skip_refusals": not (backend == "direct" and level == 0)}


def combine(reports, cases, configurations, compiler_hash, filtered):
    assert set(reports) == {(backend, level) for backend in BACKENDS for level in LEVELS}
    first = reports[("native", 0)]
    expected = set()
    for case in cases:
        for level in LEVELS:
            if level not in case.levels:
                continue
            for backend in BACKENDS:
                engines = ENGINES
                if backend == "native":
                    engines = ("native",)
                for engine in engines:
                    expected.add((case.name, level, case.debug, backend, engine))

    rows = []
    references = {}
    observed = set()
    refusals = set()
    shard_summaries = {}
    for key, report in reports.items():
        backend, level = key
        configuration = configurations[key]
        assert report["configuration"] == configuration, (key, report["configuration"], configuration)
        for field in ("compiler_sha256", "toolchain", "platform", "python", "cases"):
            assert report[field] == first[field], (key, field)
        assert report["compiler_sha256"] == compiler_hash
        assert report["failures"] == 0, (key, report["failures"])
        assert report["observations"] == len(report["results"]), key
        assert report["cases"] == len(cases)
        for row in report["results"]:
            assert row["status"] == "pass" and row["backend"] == backend, (key, row)
            if row.get("kind") == "compile-refusal":
                assert backend == "direct" and level == 0 and not filtered
                assert row["case"] not in refusals, ("duplicate refusal", row["case"])
                refusals.add(row["case"])
            else:
                assert row["optimization"] == level, (key, row)
                observation = (row["case"], level, row["debug"], backend, row["engine"])
                assert observation not in observed, ("duplicate", observation)
                observed.add(observation)
                reference = observation[:3]
                if backend == "native":
                    references[reference] = row["stdout"]
                else:
                    assert reference in references, ("missing native reference", observation)
                    assert row["stdout"] == references[reference], ("native stdout mismatch", observation)
            rows.append(row)
        shard_summaries[f"{backend}-O{level}"] = {
            "configuration": configuration,
            "report_sha256": report["_report_sha256"],
            "command": report["_command"],
        }

    assert observed == expected, ("missing", expected - observed, "extra", observed - expected)
    if filtered:
        assert not refusals
    else:
        assert refusals == REFUSALS, ("refusals", refusals)
    assert first["cases"] == len(cases)
    result = {key: value for key, value in first.items()
              if key not in ("configuration", "results", "observations", "failures") and not key.startswith("_")}
    result.update(observations=len(rows), failures=0, results=rows)
    return result, shard_summaries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=ROOT / "build" / "bin" / "goose")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--filter", default="", help="optional case-name substring for a reduced smoke run")
    parser.add_argument("--jobs", type=int, default=6)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be at least 1")

    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    combined_path = output / "report.json"
    if combined_path.exists():
        combined_path.unlink()
    goose = args.goose.resolve()
    sys.path.insert(0, str(ROOT / "tests"))
    from run_differential import cases

    selected = [case for case in cases() if args.filter in case.name]
    if not selected:
        parser.error("no cases selected")

    inputs = [ROOT / "tests/run_differential.py", Path(__file__).resolve(), goose]
    inputs += [ROOT / name for name in ("scripts/goose_wasm.py", "oracle/goose_wasm.py",
               "scripts/run_wasm.mjs", "scripts/run_wasmtime.py", "bench/host_input.c", "toolchain.json")]
    inputs += sorted((ROOT / "tests/fixtures").glob("*.goose"))
    inputs += sorted((ROOT / "tests/fixtures").glob("*.json"))
    inputs += [path for path in (goose.parent / "source.json", goose.parent / "toolchain.json") if path.exists()]
    inputs += sorted((goose.parent / "stdlib").glob("*.goose"))
    source_hashes = {str(path): digest(path) for path in inputs}
    started = time.monotonic()
    reports = {}
    configurations = {}
    failures = []
    jobs = []

    shards = [(backend, level) for backend in BACKENDS for level in LEVELS]
    try:
        for start in range(0, len(shards), args.jobs):
            batch = shards[start:start + args.jobs]
            for backend, level in batch:
                key = (backend, level)
                name = f"{backend}-O{level}"
                shard_output = output / "shards" / name
                shard_output.mkdir(parents=True, exist_ok=True)
                report_path = shard_output / "report.json"
                if report_path.exists():
                    report_path.unlink()
                configuration = expected_configuration(backend, level, args.filter)
                configurations[key] = configuration
                command = [sys.executable, str(ROOT / "tests/run_differential.py"),
                           "--goose", str(goose), "--backends", backend,
                           "--levels", str(level), "--output-dir", str(shard_output)]
                if args.filter:
                    command += ["--filter", args.filter]
                if configuration["skip_refusals"]:
                    command.append("--skip-refusals")
                log_path = output / f"{name}.log"
                log = log_path.open("w")
                try:
                    process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
                except BaseException:
                    log.close()
                    raise
                jobs.append((key, process, log, command, report_path))

            for key, process, log, command, report_path in jobs:
                status = process.wait()
                log.close()
                print(f"{key[0]} O{key[1]} exit {status}", flush=True)
                if status:
                    failures.append((key, status))
                    continue
                if not report_path.exists():
                    failures.append((key, "missing report"))
                    continue
                report = json.loads(report_path.read_text())
                report["_report_sha256"] = digest(report_path)
                report["_command"] = command
                reports[key] = report
            jobs = []
    finally:
        for _key, process, log, _command, _report_path in jobs:
            if process.poll() is None:
                process.terminate()
            process.wait()
            if not log.closed:
                log.close()

    assert not failures, failures
    compiler_hash = digest(goose)
    report, shard_summaries = combine(reports, selected, configurations, compiler_hash, bool(args.filter))
    assert source_hashes == {str(path): digest(path) for path in inputs}
    comparisons = sum(row["backend"] != "native" and row.get("kind") != "compile-refusal"
                      for row in report["results"])
    report["qualification_execution"] = {
        "method": "Concurrent backend/optimization shards; exact coverage and native stdout compared after all shards pass.",
        "wall_seconds": time.monotonic() - started,
        "jobs": args.jobs,
        "shards": shard_summaries,
        "native_stdout_comparisons": comparisons,
        "input_sha256": source_hashes,
    }
    combined_path.write_text(json.dumps(report, indent=2) + "\n")
    print(report["observations"], "observations passed with full native-output comparison", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
