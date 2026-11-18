"""Test one memory32 layout trained on both the frozen self-emitter and the Blot2 parser."""
import argparse
import json
import os
from pathlib import Path
import resource
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("repo", "compiler_stage", "project_stage", "controls", "out"):
        parser.add_argument(name, type=Path)
    parser.add_argument("--cpu", type=int, default=3)
    args = parser.parse_args()
    repo, compiler, project, controls, out = [
        p.resolve() for p in (args.repo, args.compiler_stage, args.project_stage, args.controls, args.out)
    ]
    sys.path.insert(0, str(repo / "bench"))
    from selfhost_comparison import identity, verify_frozen_source
    from diagnose import region_table

    os.sched_setaffinity(0, {args.cpu})
    resource.setrlimit(resource.RLIMIT_STACK, (256 << 20, resource.getrlimit(resource.RLIMIT_STACK)[1]))
    validation = json.loads((out / "validation-root.json").read_text())
    diagnostics = json.loads((out / "diagnosis.json").read_text())
    for stage in [compiler, project]:
        manifest = json.loads((stage / "builds.json").read_text())
        verify_frozen_source(stage / "source", manifest["source_commit"], manifest["source_archive_sha256"])
    profiles = {"self-emit": controls / "regions.txt", "blot-parse": out / "diagnostics/blot.profile"}
    assert identity(profiles["self-emit"])["sha256"] == validation["calibrated_profile_sha256"]
    assert identity(profiles["blot-parse"]) == diagnostics["blot_256gib"]["profile"]
    maximum = {}
    for profile in profiles.values():
        for line in profile.read_text().splitlines():
            i, value = map(int, line.split())
            maximum[i] = max(maximum.get(i, 0), value)
    combined = out / "two-project-fit.profile"
    combined.write_text("".join(f"{i} {n}\n" for i, n in sorted(maximum.items())))
    native = compiler / "build-1/compiler-native"
    host = repo / "host/rust/target/release/goose-wasmtime"
    assert identity(native) == validation["native"] and identity(host) == validation["rust_host"]
    module = out / "two-project-fit.wasm"
    source = ["selfhost/main.goose", "--stdlib", "stdlib"]
    flags = ["--target", "wasm-direct", "-O2"]
    subprocess.run([native, *source, *flags, "--wasm-max-pages", "65535", "--wasm-region-profile",
                    combined, "-o", module], cwd=compiler / "source", check=True)
    emitted = out / "two-project-emission.wasm"
    cases = {
        "self-check": (project / "source", [*source, "--check"]),
        "self-emit": (project / "source", [*source, *flags, "--wasm-memory64", "--wasm-max-pages",
                                           "262144", "-o", emitted]),
        "blot-parse": (out / "heldout/blot/compiler-goose",
                       ["src/main.goose", "--stdlib", "../stdlib", "--target", "native", "--parse"]),
    }
    width, _, bounds = region_table(module.read_bytes())
    assert width == 4 and bounds[-1] == 65535 * 65536
    report = {
        "classification": "Capacity control trained on both evaluation projects",
        "policy": "Per-region maximum of the two measured memory64 high-water profiles, with the release layout floor",
        "compiler_commit": validation["compiler_commit"], "self_project_commit": validation["workload"],
        "blot2_archive_sha256": validation["fixture_sha256"], "cpu": args.cpu,
        "native": identity(native), "host": identity(host), "profiles": {k: identity(p) for k, p in profiles.items()},
        "combined_profile": identity(combined), "module": identity(module), "regions": len(bounds) - 1,
        "usable_bytes": {i: bounds[i + 1] - bounds[i] - 3 * width for i in [6, 7, 53]},
        "results": {},
    }
    matches = []
    for name, (cwd, argv) in cases.items():
        outcomes = {}
        for engine, cmd in [
            ("native", [native]),
            ("wasm", [host, module, "--cache", out / "two-project-fit.cwasm", "--"]),
        ]:
            emitted.unlink(missing_ok=True)
            result = subprocess.run([*cmd, *argv], cwd=cwd, capture_output=True, timeout=120)
            observed = {"status": result.returncode, "stdout": result.stdout.decode(), "stderr": result.stderr.decode()}
            if emitted.exists():
                observed["emission"] = identity(emitted)
            outcomes[engine] = observed
        reference = outcomes["native"]
        assert (reference["status"], reference["stdout"], reference["stderr"]) == (0, "", "")
        if name == "self-emit":
            assert reference["emission"] == validation["correctness"][name]["reference"]["emission"]
        match = outcomes["wasm"] == reference
        matches.append(match)
        report["results"][name] = dict(matches_native=match, **outcomes)
        (out / "two-project-fit.json").write_text(json.dumps(report, indent=2) + "\n")
        print(name, match, flush=True)
    if not all(matches):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
