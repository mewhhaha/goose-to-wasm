#!/usr/bin/env python3
"""Compare diagnostics and structural fingerprints while evaluating every body."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import gzip
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess


root = Path.cwd()
work = root / "build/neon-shadow-scheduler"
inputs = work / "corpus-input"
manifest = inputs / "tests/conformance/cases.json"
upstream = inputs / "upstream"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def run(binary, source, cwd):
    result = subprocess.run([binary, source, "--stdlib", cwd / "stdlib",
                             "--target", "wasm-direct", "--check"],
                            cwd=cwd, capture_output=True, timeout=120)
    audit = []
    stdout = []
    for line in result.stdout.splitlines():
        if line.startswith((b"round ", b"validate ")):
            continue
        if line.startswith((b"shadow ", b"mismatch ")):
            audit.append(line.decode())
        else:
            stdout.append(line)
    if result.returncode < 0:
        raise RuntimeError((binary, source, result.returncode, result.stderr.decode()))
    if result.returncode == 0 and b"LIFEFP " not in result.stderr:
        raise RuntimeError((binary, source, result.stderr.decode()))
    return (result.returncode, digest(b"\n".join(stdout)), digest(result.stderr)), audit


def compare(key, limit):
    cwd = inputs
    rel = key
    if key.startswith("upstream:"):
        cwd = upstream
        rel = key.removeprefix("upstream:")
    source = cwd / rel
    assert source.is_file(), source
    baseline, control_rows = run(work / f"control-{limit}/compiler", source, cwd)
    assert not control_rows, control_rows
    current, candidate_rows = run(work / f"audit-{limit}/compiler", source, cwd)
    shadow = [list(map(int, line.split()[1:])) for line in candidate_rows if line.startswith("shadow ")]
    assert all(len(row) == 11 for row in shadow)
    return dict(source=key, sha256=digest(source.read_bytes()), equal=baseline == current,
                reference=baseline, audit=current, entered_class=any(row[1] > 0 for row in shadow),
                predictions=sum(row[7] for row in shadow), rejected=sum(row[8] for row in shadow),
                structural_mismatches=[line for line in candidate_rows if line.startswith("mismatch ")])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("limit", type=int, choices=(4096, 16))
    limit = parser.parse_args().limit
    resource.setrlimit(resource.RLIMIT_STACK, (256 << 20, resource.RLIM_INFINITY))
    catalog = json.loads(manifest.read_text())
    snapshot = inputs / catalog["upstream"]["archive"]
    assert digest(snapshot.read_bytes()) == catalog["upstream"]["sha256"]
    keys = sorted({case["source"] for case in catalog["cases"]})
    with ThreadPoolExecutor(max_workers=len(os.sched_getaffinity(0))) as pool:
        rows = list(pool.map(lambda key: compare(key, limit), keys))
    result = dict(limit=limit, upstream=catalog["upstream"], manifest_sha256=digest(manifest.read_bytes()),
                  tools={mode: digest((work / f"{mode}-{limit}/compiler").read_bytes())
                         for mode in ("control", "audit")},
                  sources=len(rows), equal=sum(r["equal"] for r in rows),
                  entered_class=sum(r["entered_class"] for r in rows),
                  predictions=sum(r["predictions"] for r in rows),
                  rejected=sum(r["rejected"] for r in rows),
                  structural_mismatches=[dict(source=r["source"], witnesses=r["structural_mismatches"])
                                         for r in rows if r["structural_mismatches"]])
    print(json.dumps(result), flush=True)
    with gzip.open(work / f"corpus-{limit}.json.gz", "wt") as output:
        json.dump(dict(result, rows=rows), output, indent=2)
        output.write("\n")
    assert result["equal"] == result["sources"], result


if __name__ == "__main__":
    main()
