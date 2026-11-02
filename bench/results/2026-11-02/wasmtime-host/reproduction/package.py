#!/usr/bin/env python3
"""Freeze the Wasmtime native-host experiment as a compact evidence package."""
from __future__ import annotations

import gzip
import hashlib
import io
import json
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "build/wasmtime-host"
OUT = ROOT / "bench/results/2026-11-02/wasmtime-host"
COMPILER = ROOT / "build/bin/goose"
EXPECTED_COMPILER = "3316710bb9d2b3100e94c2023000f0cb1b7517010ef04076314b4703fdcfcbba"


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def read(path: Path):
    return json.loads(path.read_text())


def require(path: Path) -> Path:
    if not path.is_file():
        raise SystemExit(f"missing required input: {path}")
    return path


def verify_source_pins(report, paths):
    recorded = report.get("input_sha256", {})
    for path in paths:
        key = str(path)
        if key not in recorded:
            raise SystemExit(f"report does not pin source input: {key}")
        if sha(require(path)) != recorded[key]:
            raise SystemExit(f"measured source input drifted: {key}")


def verify_tree_source_pins(report):
    prefixes = tuple(str(ROOT / part) + "/" for part in ("host", "scripts", "bench", "examples", "stdlib", "tests"))
    fixed = {str(ROOT / "toolchain.json"), str(ROOT / "AGENTS.md")}
    for key, expected in report.get("input_sha256", {}).items():
        if key in fixed or key.startswith(prefixes):
            path = Path(key)
            if path.is_file() and sha(path) != expected:
                raise SystemExit(f"measured source input drifted: {key}")


def selected_reference_artifacts(ref):
    candidates = {}
    for observation in ref["observations"]:
        if observation.get("kind") != "build" or observation.get("status") != "passed":
            continue
        key = (observation.get("name"), observation.get("backend"))
        if key in candidates:
            continue
        path = Path(observation["artifact"])
        if path.is_file():
            candidates[key] = (path, observation.get("artifact_sha256", sha(path)))
    examples = [e["name"] for e in ref["examples"]]
    required = {(n, be) for n in examples for be in ("direct", "c-wasm", "native")}
    if set(candidates) != required:
        raise SystemExit(f"reference report did not resolve all 30 artifacts: {sorted(required - set(candidates))}")
    if sum(backend != "native" for _, backend in candidates) != 20:
        raise SystemExit("reference cohort does not resolve 20 Wasm and 10 native artifacts")
    for path, expected in candidates.values():
        if sha(path) != expected:
            raise SystemExit(f"reference artifact drifted: {path}")
    return candidates


def verify_benchmark_guest_inputs(ref, bench):
    old = selected_reference_artifacts(ref)
    for (name, backend), (_, expected) in old.items():
        suffix = ".bin" if backend == "native" else ".wasm"
        prefix = f"{ROOT}/build/native-gap/example-benchmarks/compile/{name}/{backend}/"
        matches = [digest for path, digest in bench.get("input_sha256", {}).items()
                   if path.startswith(prefix) and path.endswith(suffix)]
        if not matches or set(matches) != {expected}:
            raise SystemExit(f"final benchmark guest input differs from frozen compact-example artifact: {name}/{backend}")


def build_source_pins(q, bench, old, boundary):
    maps = (q.get("input_sha256", {}), bench.get("input_sha256", {}),
            boundary.get("source_sha256", {}))
    paths = (
        ROOT / "host/wasmtime.cpp", ROOT / "host/wasmtime-sdk.json",
        ROOT / "scripts/build_wasmtime_host.py", ROOT / "scripts/run_wasmtime.py",
        ROOT / "bench/qualify_wasmtime_host.py", ROOT / "tests/test_native_wasmtime.py",
        WORK / "qualify_boundaries.py", COMPILER,
    )
    pins = {}
    for path in paths:
        key = str(path)
        found = [source_map[key] for source_map in maps if key in source_map]
        if not found or len(set(found)) != 1:
            raise SystemExit(f"no consistent measured source pin for {key}")
        label = path.relative_to(ROOT).as_posix() if path.is_relative_to(ROOT) else str(path)
        pins[label] = found[0]
    bench_key = str(ROOT / "bench/wasmtime_host.py")
    if bench.get("input_sha256", {}).get(bench_key) != sha(require(ROOT / "bench/wasmtime_host.py")):
        raise SystemExit("final benchmark script source pin does not match current file")
    pins["bench/wasmtime_host.py"] = bench["input_sha256"][bench_key]
    chart_path = require(ROOT / "bench/wasmtime_host_charts.py")
    pins["bench/wasmtime_host_charts.py (post-measurement)"] = sha(chart_path)
    serial_key = str(ROOT / "bench/wasmtime_host.py")
    if old.get("input_sha256", {}).get(serial_key) != sha(require(WORK / "measure-serial-aot.py")):
        raise SystemExit("frozen serial-AOT harness does not match the old report's recorded script SHA")
    pins["frozen serial-AOT harness"] = sha(WORK / "measure-serial-aot.py")
    pins["old serial-AOT measured script identity"] = old["input_sha256"][serial_key]
    return pins


def preflight():
    if OUT.exists():
        raise SystemExit(f"refusing to overwrite existing evidence: {OUT}")
    q = read(require(WORK / "qualification/report.json"))
    b = read(require(WORK / "bench/report.json"))
    old = read(require(WORK / "bench-serial-aot/report.json"))
    ref = read(require(ROOT / "bench/results/2026-11-02/compact-examples/report.json"))
    boundary = read(require(WORK / "boundary-report.json"))
    current_host = read(require(ROOT / "build/bin/goose-wasmtime.json"))
    wrapper = require(WORK / "qualify_boundaries.py")
    if q.get("status") != "pass" or q.get("observations") != 11340 or q.get("failures") != 0:
        raise SystemExit("new-host qualification is not pass / 11340 observations / zero failures")
    if q.get("aot_sha256") != q.get("aot_sha256_after") or q.get("input_sha256") != q.get("input_sha256_after"):
        raise SystemExit("qualification inputs or AOT set changed during qualification")
    if boundary.get("schema") != "goose-native-host-boundaries-v1" or boundary.get("status") != "pass":
        raise SystemExit("boundary attestation is missing or not pass")
    if (boundary.get("methods") != 10 or boundary.get("exit_code") != 0
            or not boundary.get("command") or boundary.get("log") != "boundaries.log"):
        raise SystemExit("boundary attestation is not 10 methods with exit code zero")
    if boundary.get("input_sha256") != boundary.get("input_sha256_after"):
        raise SystemExit("boundary attestation inputs changed during tests")
    boundary_sources = boundary.get("source_sha256", {})
    for path in (ROOT / "host/wasmtime.cpp", ROOT / "tests/test_native_wasmtime.py",
                 ROOT / "scripts/build_wasmtime_host.py", ROOT / "host/wasmtime-sdk.json",
                 ROOT / "scripts/run_wasmtime.py", wrapper):
        if boundary_sources.get(str(path)) != sha(require(path)):
            raise SystemExit(f"boundary attestation does not pin current source: {path}")
    if sha(require(ROOT / "build/bin/goose-wasmtime")) != boundary.get("host_sha256"):
        raise SystemExit("boundary attestation host SHA does not match current executable")
    host_fields = ("host_sha256", "library_sha256", "sdk_archive_sha256", "library", "command", "input_sha256")
    q_host = q.get("host_build", {})
    b_host = b.get("host_build", {})
    for field in host_fields:
        if q_host.get(field) != b_host.get(field) or q_host.get(field) != current_host.get(field):
            raise SystemExit(f"qualification/benchmark/current host metadata differs: {field}")
    library_path = Path(q["host_build"]["library"])
    if sha(require(library_path)) != boundary.get("library_sha256"):
        raise SystemExit("boundary attestation library SHA does not match Wasmtime library")
    for key, expected in boundary["input_sha256"].items():
        if sha(require(Path(key))) != expected:
            raise SystemExit(f"boundary attestation input drifted: {key}")
    if q.get("compiler_sha256") != EXPECTED_COMPILER or sha(COMPILER) != EXPECTED_COMPILER:
        raise SystemExit("qualification/compiler hash mismatch")
    for key, expected in q.get("host_build", {}).get("input_sha256", {}).items():
        path = require(Path(key))
        if sha(path) != expected:
            raise SystemExit(f"host build input drifted: {path}")
    sdk_archive = WORK / "wasmtime-v50.0.1-x86_64-linux-c-api.tar.xz"
    if sha(require(sdk_archive)) != q.get("host_build", {}).get("sdk_archive_sha256"):
        raise SystemExit("Wasmtime SDK archive hash does not match host build pin")
    if b.get("status") != "passed" or len(b.get("observations", [])) != 1440 or len(b.get("preparation", [])) != 200:
        raise SystemExit("final benchmark is not passed with 1440 runtime and 200 preparation observations")
    if len(b.get("artifact_qualification", [])) != 40:
        raise SystemExit("final benchmark artifact qualification count is not 40")
    qualified = {}
    for item in b["artifact_qualification"]:
        key = (item.get("name"), item.get("backend"), item.get("configuration"))
        if key in qualified or item.get("status") != "passed" or not item.get("sha256"):
            raise SystemExit("benchmark artifact qualification has duplicate or failed cells")
        qualified[key] = item["sha256"]
    example_names = {example["name"] for example in b.get("examples", [])}
    expected_qualification = {(name, backend, config) for name in example_names
                              for backend in ("direct", "c-wasm") for config in ("parallel", "serial")}
    if len(example_names) != 10 or set(qualified) != expected_qualification:
        raise SystemExit("artifact qualification does not cover all 10 x 2 x 2 backend/config cells")
    if len({item["sha256"] for item in b["artifact_qualification"]}) != 20:
        raise SystemExit("the 40 qualified configs should represent 20 distinct serialized artifacts")
    preparation_keys = set()
    for item in b["preparation"]:
        path = require(Path(item["artifact"]))
        key = (item.get("name"), item.get("backend"), item.get("configuration"))
        sample_key = (*key, item.get("sample"))
        if sample_key in preparation_keys:
            raise SystemExit("duplicate prepared artifact sample")
        preparation_keys.add(sample_key)
        if qualified.get(key) != item.get("sha256") or sha(path) != item.get("sha256"):
            raise SystemExit(f"prepared artifact is not frozen/qualified: {path}")
    expected_preparations = {(name, backend, config, sample) for name, backend, config in expected_qualification
                             for sample in range(5)}
    if preparation_keys != expected_preparations:
        raise SystemExit("prepared artifacts do not cover all 200 expected samples")
    if old.get("status") != "passed" or len(old.get("observations", [])) != 1440:
        raise SystemExit("serial-AOT reference cohort is incomplete")
    if ref.get("status") != "passed" or len(ref.get("observations", [])) != 1600:
        raise SystemExit("compact-examples reference cohort is incomplete")
    selected_reference_artifacts(ref)
    verify_benchmark_guest_inputs(ref, b)
    for name in ("goose-wasmtime", "goose-wasmtime.json"):
        require(ROOT / "build/bin" / name)
    for path in (ROOT / "host/wasmtime.cpp", ROOT / "host/wasmtime-sdk.json",
                 WORK / "measure-serial-aot.py", WORK / "boundaries.log"):
        require(path)
    boundary_log = (WORK / "boundaries.log").read_text().lower()
    if "ran 10 tests" not in boundary_log or "ok" not in boundary_log:
        raise SystemExit("boundary-method log does not record a pass")
    host = ROOT / "build/bin/goose-wasmtime"
    if sha(require(host)) != q.get("host_build", {}).get("host_sha256"):
        raise SystemExit("built host binary does not match qualification host SHA-256")
    if not b.get("input_sha256") or not q.get("input_sha256"):
        raise SystemExit("reports lack frozen input hashes")
    verify_source_pins(q, (ROOT / "host/wasmtime.cpp", ROOT / "host/wasmtime-sdk.json",
                           ROOT / "scripts/build_wasmtime_host.py", ROOT / "scripts/run_wasmtime.py"))
    verify_source_pins(b, (ROOT / "host/wasmtime.cpp", ROOT / "host/wasmtime-sdk.json",
                           ROOT / "scripts/run_wasmtime.py", ROOT / "bench/wasmtime_host.py"))
    verify_tree_source_pins(q)
    verify_tree_source_pins(b)
    example_sources = [ROOT / "examples/manifest.json"]
    for example in ref["examples"]:
        example_sources.extend((ROOT / "examples" / example["file"], ROOT / "examples" / example["expected"]))
    verify_source_pins(b, example_sources)
    for path in (ROOT / "LICENSE", ROOT / "toolchain.json", ROOT / "requirements.txt",
                 ROOT / "bench/wasmtime-host.md", ROOT / "bench/wasmtime_host_charts.py", WORK / "qualify_boundaries.py",
                 WORK / "package.py", ROOT / "scripts/run_wasmtime.py",
                 ROOT / "scripts/build_wasmtime_host.py", ROOT / "bench/qualify_wasmtime_host.py",
                 ROOT / "tests/test_native_wasmtime.py"):
        require(path)
    sdk_dir = WORK / "wasmtime-v50.0.1-x86_64-linux-c-api"
    if sdk_dir.is_dir():
        for path in (sdk_dir / "LICENSE", sdk_dir / "README.md", sdk_dir / "include"):
            if not path.exists():
                raise SystemExit(f"missing SDK archive source: {path}")
    source_pins = build_source_pins(q, b, old, boundary)
    return q, b, old, ref, boundary, source_pins


class Package:
    def __init__(self):
        self.members = []
        self.archive = ""
        self.binary_members = {}

    def start_archive(self, path: Path):
        self.archive = path.name
        self.binary_members = {}

    def add_file(self, tar: tarfile.TarFile, path: Path, name: str):
        data = path.read_bytes()
        try:
            source = path.relative_to(ROOT).as_posix()
        except ValueError:
            source = str(path)
        self.add_bytes(tar, name, data, source)

    def add_bytes(self, tar: tarfile.TarFile, name: str, data: bytes, source: str):
        info = tarfile.TarInfo(name)
        info.size = len(data)
        info.mtime = 0
        tar.addfile(info, io.BytesIO(data))
        self.members.append({
            "source": source,
            "archive": self.archive,
            "member": name,
            "sha256": hashlib.sha256(data).hexdigest(),
        })

    def add_alias(self, source: str, requested: str, canonical: str, digest: str):
        self.members.append({
            "source": source,
            "archive": self.archive,
            "member": canonical,
            "requested_member": requested,
            "alias_of": canonical,
            "sha256": digest,
        })

    def add_tree(self, tar: tarfile.TarFile, base: Path, prefix: str, omit_aot=False):
        for path in sorted(base.rglob("*")):
            if not path.is_file():
                continue
            rel = path.relative_to(base)
            if omit_aot and (rel.parts[0] == "aot" or path.suffix in (".cwasm", ".wasm", ".bin")):
                continue
            if omit_aot and rel.as_posix() == "report.json":
                continue
            member = f"{prefix}/{rel.as_posix()}"
            if path.suffix in (".cwasm", ".wasm", ".bin"):
                digest = sha(path)
                canonical = self.binary_members.get(digest)
                if canonical:
                    self.add_alias(path.relative_to(ROOT).as_posix(), member, canonical, digest)
                else:
                    self.add_file(tar, path, member)
                    self.binary_members[digest] = member
            else:
                self.add_file(tar, path, member)


def snapshot_inputs(ref, pkg, tar):
    candidates = selected_reference_artifacts(ref)
    canonical = {}
    aliases = {}
    for (name, backend), (path, expected) in sorted(candidates.items()):
        dedup_key = expected if backend == "native" else f"{name}/{backend}/{expected}"
        dest = canonical.get(dedup_key)
        if dest is None:
            dest = f"guest/old-compact/{name}/{backend}/" + path.name
            pkg.add_file(tar, path, dest)
            canonical[dedup_key] = dest
        aliases[f"{name}/{backend}"] = {"member": dest, "sha256": expected}
    pkg.add_bytes(tar, "guest/old-compact/aliases.json",
                  (json.dumps(aliases, indent=2, sort_keys=True) + "\n").encode(),
                  "bench/results/2026-11-02/compact-examples/report.json artifact aliases")


def main():
    q, bench, serial, ref, boundary, source_pins = preflight()
    OUT.mkdir(parents=True)
    pkg = Package()

    # Human-facing reports and the exact prior serial harness are separate files.
    copies = {
        WORK / "bench/report.json": OUT / "report.json",
        WORK / "bench-serial-aot/report.json": OUT / "serial-aot-experiment.json",
        WORK / "boundaries.log": OUT / "boundary-tests.log",
        WORK / "boundary-report.json": OUT / "boundary-report.json",
        WORK / "measure-serial-aot.py": OUT / "measure-serial-aot.py",
        ROOT / "host/wasmtime.cpp": OUT / "wasmtime.cpp",
        ROOT / "host/wasmtime-sdk.json": OUT / "wasmtime-sdk.json",
        ROOT / "build/bin/goose-wasmtime.json": OUT / "goose-wasmtime.json",
    }
    for src, dst in copies.items():
        dst.write_bytes(require(src).read_bytes())
    (OUT / "host-build.json").write_text(json.dumps(q["host_build"], indent=2) + "\n")
    (OUT / "goose-wasmtime").write_bytes((ROOT / "build/bin/goose-wasmtime").read_bytes())
    with gzip.open(OUT / "qualification-report.json.gz", "wb", compresslevel=9) as f:
        f.write((WORK / "qualification/report.json").read_bytes())

    # Keep source + exact inputs compact; compiled engine and compiler are deliberately absent.
    source_tar = OUT / "source-and-guest-inputs.tar.gz"
    pkg.start_archive(source_tar)
    with tarfile.open(source_tar, "w:gz", compresslevel=9) as tar:
        for path in (ROOT / "LICENSE", ROOT / "toolchain.json", ROOT / "requirements.txt",
                     ROOT / "bench/wasmtime-host.md",
                     ROOT / "host/wasmtime.cpp", ROOT / "host/wasmtime-sdk.json",
                     ROOT / "scripts/run_wasmtime.py", ROOT / "scripts/build_wasmtime_host.py",
                     ROOT / "bench/wasmtime_host.py", ROOT / "bench/qualify_wasmtime_host.py",
                     ROOT / "bench/wasmtime_host_charts.py", ROOT / "tests/test_native_wasmtime.py",
                     WORK / "qualify_boundaries.py",
                     WORK / "package.py", WORK / "measure-serial-aot.py"):
            pkg.add_file(tar, require(path), "source/" + path.relative_to(ROOT).as_posix())
        for directory in (ROOT / "examples", ROOT / "bench/results/2026-11-02/native-gap/reproduction"):
            for path in sorted(directory.rglob("*")):
                if path.is_file() and (directory.name == "examples" or path.suffix == ".py"):
                    pkg.add_file(tar, path, "source/" + path.relative_to(ROOT).as_posix())
        snapshot_inputs(ref, pkg, tar)

    # Runtime and preparation evidence includes stdout/stderr/commands and serialized AOT.
    samples_tar = OUT / "bench-samples.tar.gz"
    pkg.start_archive(samples_tar)
    with tarfile.open(samples_tar, "w:gz", compresslevel=6) as tar:
        pkg.add_tree(tar, WORK / "bench", "final")
        pkg.add_tree(tar, WORK / "bench-serial-aot", "serial-aot")
    # Qualification logs are retained, but rebuildable AOT objects are not.
    qualification_tar = OUT / "qualification-logs.tar.gz"
    pkg.start_archive(qualification_tar)
    with tarfile.open(qualification_tar, "w:gz", compresslevel=6) as tar:
        pkg.add_tree(tar, WORK / "qualification", "qualification", omit_aot=True)

    # Include small official SDK headers; omit the ~100 MB libraries and full SDK bundle.
    sdk = WORK / "wasmtime-v50.0.1-x86_64-linux-c-api"
    if sdk.is_dir():
        sdk_tar = OUT / "wasmtime-sdk-headers.tar.gz"
        pkg.start_archive(sdk_tar)
        with tarfile.open(sdk_tar, "w:gz", compresslevel=9) as tar:
            for path in (sdk / "LICENSE", sdk / "README.md"):
                pkg.add_file(tar, require(path), path.name)
            for base in (sdk / "include", sdk / "min/include"):
                if base.is_dir():
                    pkg.add_tree(tar, base, base.relative_to(sdk).as_posix())

    summary = {
        "schema": "goose-wasmtime-host-qualification-summary-v1",
        "status": "pass", "observations": q["observations"], "expected_observations": q["expected_observations"],
        "failures": q["failures"], "runtime_failures": q["runtime_failures"],
        "preparation_failures": q["preparation_failures"], "compile_refusals": q["compile_refusals"],
        "baseline_cases": q["baseline_cases"], "baseline_observations": q["baseline_observations"],
        "unique_wasm": q["unique_wasm"], "coverage_exact": q["coverage_exact"],
        "compiler_sha256": q["compiler_sha256"], "qualification_report_sha256": sha(WORK / "qualification/report.json"),
        "boundary_report_sha256": sha(WORK / "boundary-report.json"),
        "boundary_methods": boundary["methods"], "boundary_exit_code": boundary["exit_code"],
        "final_benchmark_script_sha256": sha(ROOT / "bench/wasmtime_host.py"),
        "python_host_bench_observations": len(bench["observations"]),
        "python_host_preparations": len(bench["preparation"]),
        "artifact_qualification_cells": len(bench["artifact_qualification"]),
        "unique_serialized_artifacts": len({item["sha256"] for item in bench["artifact_qualification"]}),
        "serial_aot_prior_report_sha256": sha(WORK / "bench-serial-aot/report.json"),
        "serial_aot_harness_sha256": sha(WORK / "measure-serial-aot.py"),
        "serial_aot_report_recorded_script_sha256": serial["input_sha256"][str(ROOT / "bench/wasmtime_host.py")],
        "old_compact_report_sha256": sha(ROOT / "bench/results/2026-11-02/compact-examples/report.json"),
        "qualification_modes": q["mode_configuration"],
        "benchmark_modes": sorted({o["mode"] for o in bench["observations"]}),
        "source_pin_sha256": source_pins, "sdk_pin": read(ROOT / "host/wasmtime-sdk.json"),
        "note": "Prior serial-AOT cohort uses its frozen exact harness; it is not attributed to the current harness.",
    }
    (OUT / "qualification-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    archive_map = pkg.members
    with gzip.open(OUT / "archive-map.json.gz", "wt", encoding="utf-8", compresslevel=9) as f:
        json.dump(archive_map, f, sort_keys=True, separators=(",", ":"))
    top = {p.name: sha(p) for p in sorted(OUT.iterdir()) if p.is_file() and p.name != "SHA256.json"}
    (OUT / "SHA256.json").write_text(json.dumps(top, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
