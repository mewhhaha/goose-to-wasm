"""Verify benchmark toolchain pins and the resident Mandelbrot input artifacts."""

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

import wasmtime._ffi


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read(path):
    return json.loads(path.read_text())


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def checked_files(expected):
    actual = {}
    for path, sha in expected.items():
        path = Path(path)
        found = digest(path)
        if found != sha:
            raise ValueError(f"expected {sha}, got {found}: {path}")
        actual[str(path)] = found
    return actual


def commit_tree(commit, tree):
    tracked = subprocess.check_output(
        ["git", "ls-tree", "-r", "--name-only", commit, "--", "selfhost", "stdlib", "native"],
        text=True,
    ).splitlines()
    result = {}
    for name in tracked:
        if name.startswith("selfhost/") and (name.count("/") != 1 or not name.endswith(".goose")):
            continue
        reference = subprocess.check_output(["git", "show", f"{commit}:{name}"])
        expected = hashlib.sha256(reference).hexdigest()
        result[name] = checked_files({tree / name: expected})[str(tree / name)]
    return result


def pins(prior, commit, frozen, parent, output, parent_commit, cpu, candidate, bootstrap_receipt):
    receipt = read(bootstrap_receipt)
    if receipt["status"] != "passed" or not receipt["fixed_point"]:
        raise ValueError("candidate compiler requires a passing fixed-point bootstrap")
    candidate_identity = checked_files({candidate: receipt["executable_sha256"]})
    frozen_identity = commit_tree(commit, frozen)
    claimed_sources = {
        **{f"selfhost/{name}": sha for name, sha in receipt["source_sha256"].items()},
        **{f"stdlib/{name}": sha for name, sha in receipt["stdlib_sha256"].items()},
        **receipt["asset_sha256"],
    }
    for name, sha in claimed_sources.items():
        if frozen_identity[name] != sha:
            raise ValueError(f"bootstrap input mismatch: {name}")
    installed_stdlib = {
        candidate.parent / "stdlib" / name: sha
        for name, sha in receipt["stdlib_sha256"].items()
    }
    old = read(prior / "langbench-build.json")
    metadata = old["metadata"]
    old_goose = Path(metadata["tools"]["goose"])
    library = Path(wasmtime._ffi.dll._name).resolve()
    expected = {
        name: info["sha256"]
        for name, info in metadata["fingerprints"].items()
        if Path(name) != old_goose and not name.endswith("/selfhost/checker_lifetimes.goose")
    }
    expected.update(installed_stdlib)
    for name in ("gcc", "clang", "node", "python"):
        path = sys.executable if name == "python" else shutil.which(name)
        identity = Path(path).resolve()
        reference = Path(metadata["tools"][name]).resolve()
        expected[str(identity)] = expected[str(reference)]
    expected[str(library)] = expected[metadata["wasmtime"]["library"]]
    host = read(prior / "host.json")
    for key in ("host_build", "aot_host_build"):
        expected.update(host[key]["input_sha256"])
        path = host["configuration"]["host" if key == "host_build" else "aot_host"]
        expected[path] = host[key]["host_sha256"]
    for name, details in read(prior / "compiler-comparison.json")["input_fingerprints"].items():
        if name.startswith(str(Path.cwd() / "examples")) or name.endswith("/bench/compare_compilers.py"):
            expected[name] = details["sha256"]
    upstream = Path("build/upstream-goose")
    upstream_commit = metadata["upstream_goose_revision"]
    upstream_tree = Path("build/langbench-goose-source")
    stdlib_paths = subprocess.check_output(
        ["git", "-C", upstream, "ls-tree", "-r", "--name-only", upstream_commit, "--", "stdlib"], text=True
    ).splitlines()
    for name in stdlib_paths:
        source = subprocess.check_output(["git", "-C", upstream, "show", f"{upstream_commit}:{name}"])
        expected[str(upstream_tree / name)] = hashlib.sha256(source).hexdigest()
    write(output, {
        "previous_reports": {
            str(path.relative_to(Path.cwd())): digest(path)
            for path in sorted(prior.glob("*.json"))
        },
        "candidate_source_commit": commit,
        "candidate_source_sha256": frozen_identity,
        "candidate_executable_sha256": candidate_identity,
        "candidate_bootstrap_receipt_sha256": digest(bootstrap_receipt),
        "parent_source_commit": parent_commit,
        "parent_source_sha256": commit_tree(parent_commit, parent),
        "upstream_source_commit": upstream_commit,
        "machine": subprocess.check_output(["uname", "-srm"], text=True).strip(),
        "timed_cpu": cpu,
        "smt_siblings": Path(f"/sys/devices/system/cpu/cpu{cpu}/topology/thread_siblings_list").read_text().strip(),
        "matched_input_sha256": checked_files(expected),
    })


def numbered_artifacts(report):
    result = {}
    for build in report["builds"]:
        cell = build["cell"]
        round_number = build["round"]
        if build["status"] != "passed" or (cell, round_number) in result:
            raise ValueError(f"incomplete or duplicate build {cell}/{round_number}")
        result[cell, round_number] = {Path(name).name: details for name, details in build["artifacts"].items()}
    return result


def artifacts(prior, hot_path, new_path, output):
    old_path = prior / "langbench-build.json"
    old = read(old_path)
    hot = read(hot_path)
    new = read(new_path)
    if new["status"] != "passed" or new["manifest"] != hot["manifest"]:
        raise ValueError("Mandelbrot build failed or used a different workload manifest")
    old_builds = numbered_artifacts(old)
    new_builds = numbered_artifacts(new)
    if set(old_builds) != set(new_builds) or len(new_builds) != 30:
        raise ValueError("expected the prior six cells with five complete builds each")
    for build in new["builds"]:
        for name, details in build["artifacts"].items():
            path = Path(name)
            checked_files({path: details["sha256"]})
            if path.stat().st_size != details["bytes"]:
                raise ValueError(f"artifact size drift: {name}")
    verified_runtimes = hot["reference_receipts"]["active_runtimes"]
    new_meta = new["metadata"]
    engine_paths = {
        "node": str(Path(new_meta["tools"]["node"]).resolve()),
        "python": str(Path(new_meta["tools"]["python"]).resolve()),
        "wasmtime": new_meta["wasmtime"]["library"],
    }
    for runtime, name in engine_paths.items():
        if new_meta["fingerprints"][name]["sha256"] != verified_runtimes[runtime]["sha256"]:
            raise ValueError(f"resident engine fingerprint changed: {runtime}")
    measurements = hot["reference_receipts"]["artifacts"]
    rows = {}
    identical_builds = 0
    hot_matches = 0
    for (cell, round_number), current in sorted(new_builds.items()):
        previous = old_builds[cell, round_number]
        if set(previous) != set(current):
            raise ValueError(f"build output set changed: {cell}/{round_number}")
        hot_artifact = measurements[cell]
        executable = Path(hot_artifact["path"]).name
        same_build = current == previous
        same_hot_artifact = current[executable]["sha256"] == hot_artifact["sha256"]
        identical_builds += same_build
        hot_matches += same_hot_artifact
        rows[f"{cell}/{round_number}"] = {
            "current": current,
            "previous_build": previous,
            "matches_previous_build": same_build,
            "resident_program": executable,
            "resident_program_sha256": hot_artifact["sha256"],
            "matches_resident_program": same_hot_artifact,
        }
    write(output, {
        "previous_build_report": str(old_path.relative_to(Path.cwd())),
        "previous_build_sha256": digest(old_path),
        "current_build_report": new_path.name,
        "current_build_sha256": digest(new_path),
        "resident_report": str(hot_path.relative_to(Path.cwd())),
        "resident_report_sha256": digest(hot_path),
        "resident_runtimes": verified_runtimes,
        "identical_build_samples": identical_builds,
        "samples_matching_resident_artifacts": hot_matches,
        "samples": rows,
    })
    print(f"{identical_builds}/30 builds identical, {hot_matches}/30 resident artifacts identical")


if __name__ == "__main__":
    mode, *args = sys.argv[1:]
    if mode == "pins":
        prior, commit, frozen, parent, output, parent_commit, cpu, candidate, receipt = args
        pins(Path(prior), commit, Path(frozen), Path(parent), Path(output), parent_commit,
             int(cpu), Path(candidate), Path(receipt))
    elif mode == "artifacts":
        artifacts(*map(Path, args))
    else:
        raise ValueError(mode)
