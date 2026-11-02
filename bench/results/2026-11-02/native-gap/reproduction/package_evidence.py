"""Package native-gap evidence once all final reports are present."""
import gzip
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build/native-gap"
RESULTS = ROOT / "bench/results/2026-11-02"
NATIVE = RESULTS / "native-gap"
COMPACT = RESULTS / "compact-examples"
BASE_COMMIT = "fe884fa9c2e92b3b0eb5d07701ef432bbcaa590e"
PATH_MAP = {"native-gap": [], "compact-examples": []}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def repo_path(path):
    return str(path.relative_to(ROOT))


def add_file(archive, path, member, artifact, destination):
    archive.add(path, arcname=member, recursive=False)
    destination.append({"source": repo_path(path), "artifact": artifact, "member": member,
                        "sha256": sha256(path)})


def add_tree(archive, path, prefix, artifact, destination, *, omit_compiler_bins=False, omit_generated_bins=False):
    assert path.exists(), path
    files = [path] if path.is_file() else sorted(item for item in path.rglob("*") if item.is_file())
    count = 0
    for source in files:
        if source.suffix == ".pyc" or "__pycache__" in source.parts:
            continue
        relative = Path(source.name) if path.is_file() else source.relative_to(path)
        if omit_compiler_bins:
            parts = relative.parts
            if "bin" in parts:
                index = parts.index("bin")
                if len(parts) > index + 1 and parts[index + 1] in ("goose", "tcclib"):
                    continue
        if omit_generated_bins:
            with source.open('rb') as file:
                magic = file.read(4)
            if magic in (b'\x7fELF', b'\0asm'):
                destination.append({'source':repo_path(source),'omitted_binary':True,
                                    'sha256':sha256(source),
                                    'reason':'Rebuildable differential artifact; source, commands and output retained.'})
                continue
        member = Path(prefix).as_posix() if path.is_file() else (Path(prefix) / relative).as_posix()
        add_file(archive, source, member, artifact, destination)
        count += 1
    assert count, path


def make_tar(output, sources, destination, *, omit_compiler_bins=False, omit_generated_bins=False):
    with tarfile.open(output, "w:gz", compresslevel=9) as archive:
        for path, prefix in sources:
            add_tree(archive, path, prefix, output.name, destination,
                     omit_compiler_bins=omit_compiler_bins, omit_generated_bins=omit_generated_bins)


def root_files(prefix, excluded=()):
    return [(path, path.name) for path in sorted(BUILD.glob(prefix + "*"))
            if path.is_file() and path.name not in excluded]


def add_gzip(source, output, destination, artifact):
    with source.open("rb") as input_file, output.open("wb") as output_file:
        with gzip.GzipFile(filename="", mode="wb", fileobj=output_file, compresslevel=9, mtime=0) as compressed:
            while block := input_file.read(1024 * 1024):
                compressed.write(block)
    destination.append({"source": repo_path(source), "artifact": artifact,
                        "sha256": sha256(source)})


def record_output(output):
    return {path.relative_to(output).as_posix(): sha256(path)
            for path in sorted(output.rglob("*"))
            if path.is_file() and path.name != "SHA256.json"}


def copy_evidence(source, output, destination, *, content=None):
    target = output / destination
    target.parent.mkdir(parents=True, exist_ok=True)
    if content is None:
        shutil.copyfile(source, target)
    else:
        target.write_text(content)
    PATH_MAP[output.name].append({"source": repo_path(source), "artifact": destination,
                                 "source_sha256": sha256(source), "artifact_sha256": sha256(target)})
    return target


def json_copy(source, output, destination):
    report = json.loads(source.read_text())
    return copy_evidence(source, output, destination, content=json.dumps(report, indent=2) + "\n")


def load_report(path):
    return json.loads(path.read_text())


def assert_differential_coverage(report):
    import sys

    sys.path.insert(0, str(ROOT / "tests"))
    from run_differential import cases

    expected = set()
    for case in cases():
        for level in (0, 2):
            if level not in case.levels:
                continue
            for backend in ("native", "c-wasm", "direct"):
                engines = ("native",)
                if backend != "native":
                    engines = ("v8", "wasmtime")
                for engine in engines:
                    expected.add((case.name, level, case.debug, backend, engine))
    observed = set()
    refusals = set()
    native_stdout = {}
    comparisons = 0
    for row in report["results"]:
        if row.get("kind") == "compile-refusal":
            assert row["backend"] == "direct" and row["status"] == "pass"
            assert row["case"] not in refusals
            refusals.add(row["case"])
            continue
        key = (row["case"], row["optimization"], row["debug"], row["backend"], row["engine"])
        assert key not in observed, ("duplicate differential row", key)
        observed.add(key)
        reference = key[:3]
        if row["backend"] == "native":
            native_stdout[reference] = row["stdout"]
        else:
            assert reference in native_stdout and row["stdout"] == native_stdout[reference], key
            comparisons += 1
    assert observed == expected, ("differential coverage mismatch", expected - observed, observed - expected)
    assert refusals == {"unsupported_varint_array", "unsupported_pointer_extern", "invalid_source"}
    assert comparisons == 7560


def main():
    assert not NATIVE.exists(), NATIVE
    assert not COMPACT.exists(), COMPACT

    hybrid_trial = BUILD / "hybrid"
    dispatch = BUILD / "dispatch"
    for required in (
        BUILD / "block-pairs/report.json", BUILD / "outline-pairs/report.json",
        BUILD / "images-pairs/report.json", BUILD / "mode-pairs/report.json",
        BUILD / "hybrid-pairs/report.json", BUILD / "hybrid-modes/report.json",
        BUILD / "dispatch-pairs/report.json", BUILD / "dispatch-modes/report.json",
        BUILD / "floor/report.json", BUILD / "empty.goose", BUILD / "empty.wasm", BUILD / "empty.bin",
        BUILD / "dispatch-empty.wasm", BUILD / "startup-artifact-comparison.json",
        BUILD / "qualification/report.json", BUILD / "qualification.log", BUILD / "differential/report.json",
        BUILD / "differential/shards", BUILD / "langarena/report.json",
        BUILD / "langarena.log", BUILD / "example-benchmarks/report.json", BUILD / "example-benchmarks.log",
        BUILD / "block-pairs.log", BUILD / "outline-pairs.log", BUILD / "images-pairs.log",
        BUILD / "mode-pairs.log", BUILD / "hybrid-pairs.log", BUILD / "hybrid-modes.log",
        BUILD / "dispatch-pairs.log", BUILD / "dispatch-modes.log", BUILD / "dispatch-build.log",
        BUILD / "hybrid-build.log", hybrid_trial / "headers", hybrid_trial / "source.json",
        hybrid_trial / "toolchain.json", dispatch / "headers", dispatch / "source.json",
        dispatch / "toolchain.json", BUILD / "langarena/report.md",
        BUILD / "example-benchmarks/README.md", BUILD / "measure_dispatch_modes.py",
        BUILD / "measure_modes.py", BUILD / "qualify.py", BUILD / "measure_hybrid_modes.py",
        ROOT / "build/sorting-climb/measure_pairs.py", ROOT / "patches/direct-target.patch",
        ROOT / "oracle/patches/0001-webassembly-target.patch", ROOT / "scripts/bootstrap.py",
        BUILD / "merge-controls.json", BUILD / "replay-merge-controls.py", BUILD / "finalize_reports.py",
        BUILD / "measure_build_control.py", BUILD / "build-control/report.json",
        dispatch / "bin/goose", Path(__file__).resolve(),
    ):
        assert required.exists(), f"missing final evidence: {required}"

    dispatch_sha = sha256(dispatch / "bin/goose")
    dispatch_source = load_report(dispatch / "source.json")
    qualification = load_report(BUILD / "qualification/report.json")
    differential = load_report(BUILD / "differential/report.json")
    paired = load_report(BUILD / "dispatch-pairs/report.json")
    modes = load_report(BUILD / "dispatch-modes/report.json")
    examples = load_report(BUILD / "example-benchmarks/report.json")
    langarena = load_report(BUILD / "langarena/report.json")
    build_control = load_report(BUILD / "build-control/report.json")
    startup_comparison = load_report(BUILD / "startup-artifact-comparison.json")
    trial_reports = [
        BUILD / "block-pairs/report.json", BUILD / "outline-pairs/report.json",
        BUILD / "images-pairs/report.json", BUILD / "mode-pairs/report.json",
        BUILD / "hybrid-pairs/report.json", BUILD / "hybrid-modes/report.json",
        BUILD / "floor/report.json",
    ]
    for report_path in trial_reports:
        assert load_report(report_path)["status"] == "passed", report_path

    assert qualification["status"] == "passed"
    assert len(qualification["commands"]) == 44
    assert all(row["exit_status"] == 0 for row in qualification["commands"])
    assert differential["failures"] == 0
    assert differential["observations"] == 9453 and len(differential["results"]) == 9453
    assert all(row["status"] == "pass" for row in differential["results"])
    assert_differential_coverage(differential)
    assert differential["qualification_execution"]["native_stdout_comparisons"] == 7560
    assert differential["compiler_sha256"] == dispatch_sha
    assert qualification["compiler_sha256"] == dispatch_sha

    candidate_path = str(Path(paired["configuration"]["candidate"]).resolve())
    assert paired["status"] == "passed"
    assert len(paired["builds"]) == 50 and len(paired["runs"]) == 160 and len(paired["summary"]) == 10
    assert paired["input_sha256"][candidate_path] == dispatch_sha
    assert paired["compiler_sources"]["candidate"] == dispatch_source
    assert modes["status"] == "passed"
    assert len(modes["builds"]) == 12 and len(modes["runs"]) == 144 and len(modes["summary"]) == 12
    assert modes["compiler_sha256"]["candidate"] == dispatch_sha

    expected_life = {}
    for variant in ("baseline", "candidate"):
        hashes = {row["sha256"] for row in paired["builds"]
                  if row["name"] == "life" and row["variant"] == variant}
        assert len(hashes) == 1
        expected_life[variant] = next(iter(hashes))
    assert build_control["status"] == "passed"
    assert build_control["compiler_sha256"]["candidate"] == dispatch_sha
    assert build_control["compiler_sha256"]["baseline"] == sha256(BUILD / "baseline/bin/goose")
    assert build_control["compiler_sources"]["candidate"] == dispatch_source
    assert build_control["compiler_sources"] == paired["compiler_sources"]
    assert build_control["expected_life_module_sha256"] == expected_life
    assert len(build_control["warmups"]) == 2 and len(build_control["builds"]) == 30
    assert len(build_control["summary"]) == 3 and build_control["pairs"] == 15
    assert all(row["artifact_sha256"] == expected_life[row["variant"]]
               for row in build_control["warmups"] + build_control["builds"])
    for input_path, expected_hash in build_control["input_sha256"].items():
        assert sha256(Path(input_path)) == expected_hash, f"build control input changed: {input_path}"

    assert examples["status"] == "passed" and examples["failures"] == []
    assert len(examples["observations"]) == 1600
    assert len(examples["compile_summary"]) == 30 and len(examples["runtime_summary"]) == 50
    assert examples["environment"]["compiler_sha256"] == dispatch_sha
    assert examples["environment"]["compiler_source_identity"] == dispatch_source
    assert langarena["status"] == "passed" and langarena["failures"] == []
    assert len(langarena["observations"]) == 315
    assert langarena["environment"]["compiler_sha256"] == dispatch_sha
    assert sha256(BUILD / "dispatch-empty.wasm") == sha256(BUILD / "empty.wasm")
    assert startup_comparison["status"] == "passed"
    assert startup_comparison["candidate_compiler_sha256"] == dispatch_sha
    assert startup_comparison["artifacts"]["empty.wasm"] == sha256(BUILD / "empty.wasm")
    assert startup_comparison["artifacts"]["dispatch-empty.wasm"] == sha256(BUILD / "dispatch-empty.wasm")

    NATIVE.mkdir(parents=True)
    COMPACT.mkdir(parents=True)

    diff_result = subprocess.run(["git", "diff", "--binary", BASE_COMMIT, "--", "compiler"],
                                 cwd=ROOT, check=True, stdout=subprocess.PIPE)
    patch_path = NATIVE / "compiler-changes.patch"
    patch_path.write_bytes(diff_result.stdout)
    PATH_MAP["native-gap"].append({"source": f"git:{BASE_COMMIT}:compiler to current compiler worktree",
                                   "artifact": patch_path.name, "sha256": sha256(patch_path)})

    make_tar(NATIVE / "trial-snapshots.tar.gz", [
        (BUILD / "block", "block"), (BUILD / "outline", "outline"), (BUILD / "images", "images"),
        (hybrid_trial, "hybrid-rejected"),
        *root_files("block-", ("block-pairs.log",)),
        *root_files("outline-", ("outline-pairs.log",)),
        *root_files("images-", ("images-pairs.log",)),
    ], PATH_MAP["native-gap"], omit_compiler_bins=True)
    make_tar(NATIVE / "paired-trials.tar.gz", [
        (BUILD / "block-pairs", "block-pairs"), (BUILD / "outline-pairs", "outline-pairs"),
        (BUILD / "images-pairs", "images-pairs"), (BUILD / "mode-pairs", "mode-pairs"),
        (BUILD / "hybrid-pairs", "hybrid-pairs"), (BUILD / "hybrid-modes", "hybrid-modes"),
        (BUILD / "dispatch-pairs", "dispatch-pairs"), (BUILD / "dispatch-modes", "dispatch-modes"),
        (BUILD / "block-pairs.log", "block-pairs.log"),
        (BUILD / "outline-pairs.log", "outline-pairs.log"),
        (BUILD / "images-pairs.log", "images-pairs.log"),
        (BUILD / "mode-pairs.log", "mode-pairs.log"),
        (BUILD / "hybrid-pairs.log", "hybrid-pairs.log"),
        (BUILD / "hybrid-modes.log", "hybrid-modes.log"),
        (BUILD / "hybrid-build.log", "hybrid-build.log"),
        (BUILD / "dispatch-pairs.log", "dispatch-pairs.log"),
        (BUILD / "dispatch-modes.log", "dispatch-modes.log"),
        (BUILD / "dispatch-build.log", "dispatch-build.log"),
    ], PATH_MAP["native-gap"])
    make_tar(NATIVE / "build-control.tar.gz", [
        (BUILD / "build-control", "build-control"),
    ], PATH_MAP["native-gap"])
    make_tar(NATIVE / "compiler-source.tar.gz", [
        (dispatch / "headers", "dispatch/headers"),
        (dispatch / "source.json", "dispatch/source.json"),
        (dispatch / "toolchain.json", "dispatch/toolchain.json"),
        (dispatch / "bin/include", "dispatch/bin/include"),
        (dispatch / "bin/stdlib", "dispatch/bin/stdlib"),
    ], PATH_MAP["native-gap"])
    make_tar(NATIVE / "floor.tar.gz", [
        (BUILD / "floor", "floor"), (BUILD / "empty.goose", "empty.goose"),
        (BUILD / "empty.wasm", "empty.wasm"), (BUILD / "dispatch-empty.wasm", "dispatch-empty.wasm"),
        (BUILD / "empty.bin", "empty.bin"),
    ], PATH_MAP["native-gap"])
    make_tar(NATIVE / "qualification.tar.gz", [
        (BUILD / "qualification", "qualification"), (BUILD / "qualification.log", "qualification.log"),
    ], PATH_MAP["native-gap"])
    add_gzip(BUILD / "differential/report.json", NATIVE / "differential.json.gz",
             PATH_MAP["native-gap"], "differential.json.gz")
    make_tar(NATIVE / "differential-shards.tar.gz", [
        (BUILD / "differential/shards", "shards"),
        *[(BUILD / "differential" / f"{name}.log", f"{name}.log")
          for name in ("native-O0", "native-O2", "c-wasm-O0", "c-wasm-O2", "direct-O0", "direct-O2")],
    ], PATH_MAP["native-gap"], omit_generated_bins=True)
    make_tar(NATIVE / "langarena.tar.gz", [
        (BUILD / "langarena", "langarena"), (BUILD / "langarena.log", "langarena.log"),
    ], PATH_MAP["native-gap"])
    report_path = BUILD / "example-benchmarks/report.json"
    report = examples
    make_tar(NATIVE / "example-samples.tar.gz", [
        (BUILD / "example-benchmarks", "example-benchmarks"),
    ], PATH_MAP["native-gap"])
    copy_evidence(BUILD / "example-benchmarks.log", NATIVE, "example-benchmarks.log")

    paired_reports = {
        "block-paired.json": BUILD / "block-pairs/report.json",
        "outline-paired.json": BUILD / "outline-pairs/report.json",
        "images-paired.json": BUILD / "images-pairs/report.json",
        "mode-paired.json": BUILD / "mode-pairs/report.json",
        "hybrid-paired.json": BUILD / "hybrid-pairs/report.json",
        "paired.json": BUILD / "dispatch-pairs/report.json",
        "startup.json": BUILD / "floor/report.json",
        "startup-artifact-comparison.json": BUILD / "startup-artifact-comparison.json",
        "hybrid-mode-controls.json": BUILD / "hybrid-modes/report.json",
        "mode-controls.json": BUILD / "dispatch-modes/report.json",
        "compilation-control.json": BUILD / "build-control/report.json",
        "qualification.json": BUILD / "qualification/report.json",
        "cohort.json": BUILD / "langarena/report.json",
    }
    for destination, source in paired_reports.items():
        json_copy(source, NATIVE, destination)
    copy_evidence(BUILD / "langarena/report.md", NATIVE, "langarena.md")

    scripts = [
        (ROOT / "build/sorting-climb/measure_pairs.py", "measure_pairs.py"),
        (BUILD / "measure_modes.py", "measure_modes.py"),
        (BUILD / "measure_dispatch_modes.py", "measure_dispatch_modes.py"),
        (BUILD / "qualify.py", "qualify.py"),
        (ROOT / "bench/qualify_compiler.py", "qualify_compiler.py"),
        (BUILD / "replay-merge-controls.py", "replay-merge-controls.py"),
        (BUILD / "merge-controls.json", "merge-controls.json"),
        (BUILD / "measure_hybrid_modes.py", "measure_hybrid_modes.py"),
        (BUILD / "finalize_reports.py", "finalize_reports.py"),
        (BUILD / "measure_build_control.py", "measure_build_control.py"),
        (Path(__file__).resolve(), "package_evidence.py"),
        (ROOT / "scripts/bootstrap.py", "bootstrap.py"),
    ]
    for source, destination in scripts:
        copy_evidence(source, NATIVE, f"reproduction/{destination}")

    inputs = []
    input_sources = set()

    def add_input(source, member):
        source = source.resolve()
        if source in input_sources:
            return
        input_sources.add(source)
        inputs.append((source, member))

    tool_paths = {}
    for name, value in report["environment"].get("tool_paths", {}).items():
        path_value = value
        if isinstance(value, dict):
            path_value = value.get("path", "")
        if path_value:
            tool_paths[Path(path_value).resolve()] = name
    configuration = report.get("configuration", {})
    compiler_value = configuration.get("goose")
    if compiler_value is None:
        compiler_value = configuration.get("compiler")
    compiler_path = None
    if compiler_value:
        compiler_path = Path(compiler_value).resolve()
    if compiler_path is None:
        compiler_path = dispatch / "bin/goose"
    compiler_path = compiler_path.resolve()
    omitted_inputs = []
    for source_text, expected_hash in report["environment"]["input_sha256"].items():
        source = Path(source_text).resolve()
        assert source.is_file() and sha256(source) == expected_hash, f"benchmark input changed: {source}"
        reason = None
        if source == compiler_path:
            reason = "compiler binary; identity is recorded"
        elif source in tool_paths:
            reason = f"installed tool: {tool_paths[source]}"
        else:
            try:
                source.relative_to(ROOT)
            except ValueError:
                reason = "external input; identity is recorded"
        if reason:
            omitted_inputs.append({"path": str(source), "sha256": expected_hash, "reason": reason})
            continue
        add_input(source, repo_path(source))

    for source, member in (
        (ROOT / "compiler", "compiler"),
        (BUILD / "baseline/source.json", "baseline/source.json"),
        (BUILD / "baseline/toolchain.json", "baseline/toolchain.json"),
        (BUILD / "baseline/bin/include", "baseline/bin/include"),
        (BUILD / "baseline/bin/stdlib", "baseline/bin/stdlib"),
        (dispatch / "source.json", "dispatch/source.json"),
        (dispatch / "toolchain.json", "dispatch/toolchain.json"),
        (dispatch / "headers", "dispatch/headers"),
        (ROOT / "tests", "tests"),
        (ROOT / "bench/qualify_compiler.py", "bench/qualify_compiler.py"),
        (ROOT / "bench/langarena.py", "bench/langarena.py"),
        (ROOT / "build/sorting-climb/measure_pairs.py", "harnesses/measure_pairs.py"),
        (BUILD / "measure_modes.py", "harnesses/measure_modes.py"),
        (BUILD / "measure_dispatch_modes.py", "harnesses/measure_dispatch_modes.py"),
        (BUILD / "measure_hybrid_modes.py", "harnesses/measure_hybrid_modes.py"),
        (BUILD / "qualify.py", "harnesses/qualify.py"),
        (BUILD / "replay-merge-controls.py", "harnesses/replay-merge-controls.py"),
        (BUILD / "finalize_reports.py", "harnesses/finalize_reports.py"),
        (BUILD / "measure_build_control.py", "harnesses/measure_build_control.py"),
        (Path(__file__).resolve(), "harnesses/package_evidence.py"),
        (ROOT / "scripts/bootstrap.py", "scripts/bootstrap.py"),
        (ROOT / "patches/direct-target.patch", "patches/direct-target.patch"),
        (ROOT / "oracle/patches/0001-webassembly-target.patch", "patches/0001-webassembly-target.patch"),
    ):
        if source.is_file() or source.is_dir():
            add_input(source, member)
    for trial in (BUILD / "block", BUILD / "outline", BUILD / "images", hybrid_trial, dispatch):
        patch = trial / "compiler-changes.patch"
        if patch.exists():
            inputs.append((patch, f"patches/{trial.name}-compiler-changes.patch"))
    add_input(patch_path, "patches/compiler-changes.patch")
    identity = {"compiler_path": str(compiler_path),
                "compiler_sha256": report["environment"]["compiler_sha256"],
                "compiler_source_identity": report["environment"].get("compiler_source_identity"),
                "tool_paths": {name: str(path) for path, name in tool_paths.items()},
                "omitted_input_identities": omitted_inputs}
    identity_path = NATIVE / "reproduction/compiler-identity.json"
    identity_path.parent.mkdir(parents=True, exist_ok=True)
    identity_path.write_text(json.dumps(identity, indent=2) + "\n")
    PATH_MAP["native-gap"].append({"source": repo_path(report_path),
                                   "artifact": "reproduction/compiler-identity.json",
                                   "source_sha256": sha256(report_path),
                                   "artifact_sha256": sha256(identity_path)})
    add_input(identity_path, "reproduction/compiler-identity.json")
    make_tar(NATIVE / "example-inputs.tar.gz", inputs, PATH_MAP["native-gap"], omit_compiler_bins=True)

    report_copy = copy_evidence(report_path, COMPACT, "report.json")
    generated_readme = BUILD / "example-benchmarks/README.md"
    shutil.copyfile(generated_readme, COMPACT / "README.md")
    readme = (COMPACT / "README.md").read_text()
    for target in re.findall(r"\]\(([^)]+)\)", readme):
        if target.startswith(("https://", "http://", "#")):
            continue
        if target in ("SHA256.json", "report.json"):
            continue
        packaged_target = (COMPACT / target).resolve()
        if packaged_target.exists():
            continue
        raise AssertionError(f"Packaged README link target missing: {target} ({packaged_target})")
    with (COMPACT / "README.md").open("a") as readme_file:
        readme_file.write(
            "\n\nRetained evidence: [raw example samples and logs](../native-gap/example-samples.tar.gz) · "
            "[example inputs and source snapshots](../native-gap/example-inputs.tar.gz) · "
            "[checksums](../native-gap/SHA256.json).\n"
        )
    PATH_MAP["compact-examples"].append({"source": repo_path(generated_readme),
                                         "artifact": "README.md", "source_sha256": sha256(BUILD / "example-benchmarks/README.md"),
                                         "artifact_sha256": sha256(COMPACT / "README.md")})
    readme_native = NATIVE / "README.md"
    readme_native.write_text(
        "# Native-gap evidence\n\n"
        "Final candidate: dispatch-table lowering. The hybrid variant is retained as a rejected trial.\n\n"
        "`paired.json` is the final dispatch paired report; `startup.json` retains startup controls. "
        "The floor archive keeps its original raw commands/logs/report; `startup-artifact-comparison.json` records the byte-identical dispatch empty guest. "
        "No new startup timings were collected. "
        "`cohort.json` and `langarena.md` retain the LangArena cohort; `differential.json.gz` is the full differential matrix. "
        "`compilation-control.json` summarizes 15 additional Life build-only pairs; `build-control.tar.gz` retains their raw logs and stats. "
        "Differential archives retain sources, commands, outputs and binary hashes; executable and Wasm bytes can be rebuilt. Archives retain raw samples, "
        "logs, inputs, source snapshots, harnesses, and SDK pins. `archive-path-map.json.gz` maps each archive member "
        "back to its source path and SHA256. `SHA256.json` hashes each packaged artifact.\n\n"
        "The `reproduction/` directory retains the measurement and qualification scripts. `example-inputs.tar.gz` contains "
        "the compiler sources, exact compiler diff, source and SDK pins, baseline SDK metadata and standard library, "
        "test fixtures/oracles, and the benchmark harnesses in `example-inputs.tar.gz`.\n"
    )
    PATH_MAP["native-gap"].append({"source": "generated packaging notes", "artifact": "README.md",
                                   "artifact_sha256": sha256(readme_native)})

    for name, output, entries in (("native-gap", NATIVE, PATH_MAP["native-gap"]),
                                  ("compact-examples", COMPACT, PATH_MAP["compact-examples"])):
        map_path = output / "archive-path-map.json.gz"
        with map_path.open('wb') as target:
            with gzip.GzipFile(filename='', mode='wb', fileobj=target, mtime=0) as compressed:
                compressed.write((json.dumps({'artifacts':entries},indent=2)+'\n').encode())
        hashes = record_output(output)
        (output / "SHA256.json").write_text(json.dumps(hashes, indent=2) + "\n")

    total_compressed = sum(path.stat().st_size for directory in (NATIVE, COMPACT)
                           for path in directory.iterdir() if path.is_file() and path.name != "SHA256.json")
    assert total_compressed < 24 * 1024 * 1024, f"compressed package is {total_compressed} bytes"
    pointer = {"schema": "goose-example-benchmarks-latest-v1",
               "report": "2026-11-02/compact-examples/report.json", "sha256": sha256(report_copy)}
    pointer_path = ROOT / "bench/results/examples-latest.json"
    pointer_path.write_text(json.dumps(pointer, indent=2) + "\n")
    print("Packaged", total_compressed, "compressed bytes")


if __name__ == "__main__":
    main()
