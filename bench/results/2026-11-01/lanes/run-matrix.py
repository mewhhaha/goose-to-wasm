"""Run the complete differential matrix by backend; restore cross-backend checks."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

BACKENDS = ("native", "c-wasm", "direct")
REFUSALS = {"unsupported_varint_array", "unsupported_pointer_extern", "invalid_source"}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def combine(reports, cases):
    first = reports["native"]
    expected = set()
    for case in cases:
        for level in (0, 2):
            if level not in case.levels:
                continue
            for backend in BACKENDS:
                engines = ("v8", "wasmtime")
                if backend == "native":
                    engines = ("native",)
                for engine in engines:
                    expected.add((case.name, level, case.debug, backend, engine))
    rows, references, observed, refusals = [], {}, set(), set()
    for backend in BACKENDS:
        report = reports[backend]
        for key in ("compiler_sha256", "toolchain", "platform", "python", "cases"):
            assert report[key] == first[key], (backend, key)
        assert report["failures"] == 0
        assert report["observations"] == len(report["results"])
        for row in report["results"]:
            assert row["status"] == "pass" and row["backend"] == backend
            if row.get("kind") == "compile-refusal":
                assert backend == "direct" and row["case"] not in refusals
                refusals.add(row["case"])
            else:
                key = (row["case"], row["optimization"], row["debug"], backend, row["engine"])
                assert key not in observed, ("duplicate", key)
                observed.add(key)
                if backend == "native":
                    references[key[:3]] = row["stdout"]
                else:
                    assert row["stdout"] == references[key[:3]], ("native stdout mismatch", key)
            rows.append(row)
    assert observed == expected, ("missing", expected - observed, "extra", observed - expected)
    assert refusals == REFUSALS
    assert first["cases"] == len(cases)
    return {**first, "observations": len(rows), "results": rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=Path("build/bin/goose"))
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    root, output = Path.cwd(), args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    sys.path.insert(0, str(root / "tests"))
    from run_differential import cases

    paths = [root / "tests/run_differential.py", Path(__file__).resolve(), args.goose.resolve()]
    paths += [root / name for name in ("scripts/goose_wasm.py", "oracle/goose_wasm.py",
              "scripts/run_wasm.mjs", "scripts/run_wasmtime.py", "bench/host_input.c", "toolchain.json")]
    paths += sorted((root / "tests/fixtures").glob("*.goose"))
    source_hashes = {str(path): digest(path) for path in paths}
    jobs, started = {}, time.monotonic()
    for backend in BACKENDS:
        command = [sys.executable, str(root / "tests/run_differential.py"), "--goose", str(args.goose.resolve()),
                   "--backends", backend, "--output-dir", str(output / backend)]
        log = (output / (backend + ".log")).open("w")
        jobs[backend] = (subprocess.Popen(command, cwd=root, stdout=log, stderr=subprocess.STDOUT), log, command)
    reports, shards = {}, {}
    failures = []
    for backend, (process, log, command) in jobs.items():
        status = process.wait()
        log.close()
        if status:
            failures.append((backend, status))
        path = output / backend / "report.json"
        if path.exists():
            reports[backend] = json.loads(path.read_text())
            shards[backend] = {"report_sha256": digest(path), "command": command}
        print(backend, "exit", status, flush=True)
    assert not failures, failures
    report = combine(reports, cases())
    assert report["compiler_sha256"] == digest(args.goose.resolve())
    assert source_hashes == {str(path): digest(path) for path in paths}
    report["qualification_execution"] = {"method": "Concurrent backend shards; exact coverage and native stdout compared after all shards pass.",
                                         "wall_seconds": time.monotonic() - started, "shards": shards,
                                         "native_stdout_comparisons": sum(row["backend"] != "native" and row.get("kind") != "compile-refusal" for row in report["results"]),
                                         "input_sha256": source_hashes}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(report["observations"], "observations passed with full native-output comparison", flush=True)


if __name__ == "__main__":
    main()
