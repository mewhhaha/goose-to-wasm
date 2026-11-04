#!/usr/bin/env python3
"""Render the complete, qualified Wasmtime host comparison as three SVGs."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import statistics

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

from example_charts import LABELS, index_rows, milliseconds, plot

ROOT = Path(__file__).resolve().parents[1]
BACKENDS = ("direct",)
MODES = ("python", "native", "native-serial", "precompiled")
RUNTIME_PROFILES = (
    ("python", "Python host", "#b76562"),
    ("native", "Native host", "#087f8c"),
    ("precompiled", "Precompiled", "#479b58"),
    ("native-C", "Goose → C → native", "#727b8e"),
)
PREPARATION_PROFILES = (
    ("parallel", "Parallel compilation", "#087f8c"),
    ("serial", "Serial compilation", "#ce862a"),
)
MINIMAL_RUNTIME_PROFILE = ("precompiled-minimal", "Minimal AOT", "#7461a8")
MINIMAL_PREPARATION_PROFILE = ("minimal", "Minimal AOT profile", "#7461a8")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def input_path(path):
    path = Path(path)
    if path.is_absolute():
        return path.resolve()
    return (ROOT / path).resolve()


def check_summary(summary, samples, count, label):
    require(len(samples) == count and summary["n"] == count, "Wrong sample count: " + label)
    require(summary["samples"] == samples, "Summary samples differ from raw observations: " + label)
    require(all(math.isfinite(value) and value > 0 for value in samples), "Invalid raw timing: " + label)
    median = statistics.median(samples)
    mad = statistics.median(abs(value - median) for value in samples)
    require(summary["median"] == median and summary["mad"] == mad, "Incorrect median or MAD: " + label)
    milliseconds(summary)


def validate(report, *, allow_smoke=False):
    require(report["schema"] == "goose-wasmtime-host-benchmarks-v1", "Unexpected report schema")
    config = report["configuration"]
    require(report["status"] == "passed" or (allow_smoke and report["status"] == "passed-smoke"),
            "Only a passed full report can produce charts")
    if not allow_smoke:
        require(not config["smoke"] and config["samples"] >= 5 and config["prepare_samples"] >= 5,
                "Charts require at least five runtime and preparation samples per cell")
    samples = config["samples"]
    prepare_samples = config["prepare_samples"]
    require(type(samples) is int and samples > 0 and type(prepare_samples) is int and prepare_samples > 0,
            "Invalid sample counts")
    require(isinstance(config["warmups"], int) and config["warmups"] >= 0, "Invalid warmup count")
    pins = report["input_sha256"]
    require(bool(pins), "Measurement report has no input fingerprints")
    for name, expected in pins.items():
        require(digest(input_path(name)) == expected, "Measurement input changed: " + name)
    catalog_path = ROOT / "examples/manifest.json"
    require(str(catalog_path) in pins, "Catalog manifest is not fingerprinted")
    catalog = json.loads(catalog_path.read_text())
    require(report["examples"] == catalog["examples"], "Report must contain the exact current example catalog")
    names = [example["name"] for example in report["examples"]]
    require(len(names) == 10 and len(set(names)) == 10 and set(names) == set(LABELS),
            "Expected exactly the ten named source examples")
    goldens = {}
    for example in report["examples"]:
        for field in ("file", "expected"):
            path = ROOT / "examples" / example[field]
            require(str(path) in pins and digest(path) == pins[str(path)], "Unpinned example source or golden: " + str(path))
        goldens[example["name"]] = digest(ROOT / "examples" / example["expected"])
    host = report["host_build"]
    require(host["version"] == report["environment"]["wasmtime"] == "50.0.1", "Expected Wasmtime 50.0.1")
    require(digest(input_path(config["host"])) == host["host_sha256"], "Host binary changed")
    require(digest(input_path(host["library"])) == host["library_sha256"], "Wasmtime library bytes changed")
    for path, sha in host["input_sha256"].items():
        require(path in pins and pins[path] == sha, "Host build inputs differ from measurement pins: " + path)
    minimal = bool(config.get("aot_host"))
    if minimal:
        companion = report["aot_host_build"]
        require(companion["runtime_only"] and companion["aot_profiles"] == ["minimal"]
                and companion["supported_modes"] == ["precompiled"], "Expected a minimal AOT-only companion")
        require(companion["version"] == host["version"] and "minimal" in host["aot_profiles"],
                "Preparation host and companion profiles differ")
        for path, expected in ((input_path(config["aot_host"]), companion["host_sha256"]),
                               (input_path(companion["library"]), companion["library_sha256"])):
            require(str(path) in pins and pins[str(path)] == expected and digest(path) == expected,
                    "Unpinned or changed minimal companion input: " + str(path))
        require(str(input_path(config["aot_host"]).with_suffix(".json")) in pins,
                "Minimal companion build metadata is not fingerprinted")
        for path, sha in companion["input_sha256"].items():
            require(path in pins and pins[path] == sha, "Minimal companion build inputs differ from measurement pins: " + path)

    runtime = index_rows(report["runtime_summary"], ("name", "backend", "mode"))
    cells = {(name, backend, mode) for name in names for backend in BACKENDS for mode in MODES}
    cells.update((name, "native", "native-C") for name in names)
    count = len(names) * (len(BACKENDS) * len(MODES) + 1)
    if minimal:
        cells.update((name, backend, "precompiled-minimal") for name in names for backend in BACKENDS)
        count += len(names) * len(BACKENDS)
    require(set(runtime) == cells and len(runtime) == count, f"Expected exactly {count} runtime summary cells")
    raw_runtime = index_rows(report["observations"], ("name", "backend", "mode", "phase", "sample"))
    expected_runtime = {(*cell, "measure", sample) for cell in cells for sample in range(samples)}
    expected_runtime.update((*cell, "warmup", sample) for cell in cells for sample in range(config["warmups"]))
    require(set(raw_runtime) == expected_runtime, "Incomplete or extra raw runtime observations")
    for row in raw_runtime.values():
        require(row["exit_code"] == 0 and row["stdout_sha256"] == goldens[row["name"]], "Unqualified runtime observation")
    for key, row in runtime.items():
        values = [item["wall_seconds"] for item in report["observations"]
                   if (item["name"], item["backend"], item["mode"]) == key and item["phase"] == "measure"]
        check_summary(row["wall_seconds"], values, samples, str(key))

    preparation = index_rows(report["preparation_summary"], ("name", "backend", "configuration"))
    prep_cells = {(name, backend, configuration) for name in names for backend in BACKENDS for configuration in ("parallel", "serial")}
    count = len(names) * len(BACKENDS) * 2
    if minimal:
        prep_cells.update((name, backend, "minimal") for name in names for backend in BACKENDS)
        count += len(names) * len(BACKENDS)
    require(set(preparation) == prep_cells and len(preparation) == count, f"Expected exactly {count} preparation summary cells")
    raw_prep = index_rows(report["preparation"], ("name", "backend", "configuration", "sample"))
    require(set(raw_prep) == {(*cell, sample) for cell in prep_cells for sample in range(prepare_samples)}, "Incomplete or extra preparation observations")
    artifacts = set()
    for row in raw_prep.values():
        require(digest(input_path(row["artifact"])) == row["sha256"], "Prepared native artifact changed: " + row["artifact"])
        require(row["wasm_sha256"] in pins.values(), "Preparation source Wasm is not fingerprinted")
        artifacts.add((row["name"], row["backend"], row["configuration"], row["sha256"]))
    qualified = index_rows(report["artifact_qualification"], ("name", "backend", "configuration", "sha256"))
    require(set(qualified) == artifacts and all(row["status"] == "passed" for row in qualified.values()),
            "Preparation artifacts lack exact runtime qualification")
    for key, row in preparation.items():
        values = [item["wall_seconds"] for item in report["preparation"]
                   if (item["name"], item["backend"], item["configuration"]) == key]
        check_summary(row["wall_seconds"], values, prepare_samples, str(key))
    return names, runtime, preparation


def footer(report, count, phase):
    environment = report["environment"]
    host = environment.get("supplied_machine_label") or environment["cpu"]
    if "shared" not in host.lower():
        host += ", shared host"
    return f"{report['started_utc'][:10]} · {host} · {count} {phase} samples per bar · labels: median ms ±MAD"


def save(fig, output, name, title, note, report_path, report_bytes, report):
    provenance = [f"{report_path} sha256:{hashlib.sha256(report_bytes).hexdigest()}"]
    for path in (Path(__file__).resolve(), ROOT / "bench/example_charts.py"):
        provenance.append(f"{path} sha256:{digest(path)}")
    for path, sha in sorted(report["input_sha256"].items()):
        provenance.append(f"{path} sha256:{sha}")
    host = report["host_build"]
    provenance.extend((f"native host sha256:{host['host_sha256']}",
                       f"Wasmtime {host['version']} {host['library']} sha256:{host['library_sha256']}"))
    companion = report.get("aot_host_build")
    if companion:
        provenance.extend((f"minimal AOT host sha256:{companion['host_sha256']}",
                           f"minimal Wasmtime library {companion['library']} sha256:{companion['library_sha256']}"))
    description = {"note": note, "method": report["method"], "environment": report["environment"],
                   "host_build": host, "aot_host_build": companion, "configuration": report["configuration"]}
    path = output / name
    fig.savefig(path, facecolor="white", metadata={
        "Date": None, "Title": title, "Description": json.dumps(description, sort_keys=True),
        "Source": "; ".join(provenance),
    })
    plt.close(fig)
    path.write_text("\n".join(line.rstrip() for line in path.read_text().splitlines()) + "\n")


def render(report_path, output):
    report_bytes = report_path.read_bytes()
    report = json.loads(report_bytes)
    names, runtime, preparation = validate(report)
    plt.rcParams.update({
        "font.family": "DejaVu Sans", "font.size": 10, "text.color": "#0f172a",
        "axes.labelcolor": "#475569", "xtick.color": "#334155", "ytick.color": "#475569",
        "svg.fonttype": "none", "svg.hashsalt": "goose-wasmtime-host-charts-v1",
    })
    output.mkdir(parents=True, exist_ok=True)
    for backend, label, filename in (
        ("direct", "Direct Wasm", "wasmtime-host-runtime.svg"),
    ):
        profiles = list(RUNTIME_PROFILES)
        if report["configuration"].get("aot_host"):
            profiles.insert(-1, MINIMAL_RUNTIME_PROFILE)
        rows = {}
        for name in names:
            for mode, _, _ in profiles:
                row_backend = backend
                if mode == "native-C":
                    row_backend = "native"
                rows[name, mode] = runtime[name, row_backend, mode]
        fig, ax = plt.subplots(figsize=(16, 8), facecolor="white")
        fig.subplots_adjust(left=0.075, right=0.985, top=0.78, bottom=0.22)
        title = "Wasmtime host runtime · " + label
        fig.text(0.075, 0.945, title, fontsize=20, weight="bold")
        fig.text(0.075, 0.897, "Fresh launch to exit · Wasmtime 50.0.1 · O2 · lower is better", fontsize=11, color="#475569")
        handles, clipped = plot(ax, names, rows, "wall_seconds", profiles, True)
        fig.legend(handles, [profile[1] for profile in profiles], loc="upper left",
                   bbox_to_anchor=(0.068, 0.87), ncols=len(profiles), frameon=False, fontsize=11)
        note = "Precompiled runtime excludes preparation; the preparation figure includes that cost. Goose compilation is separate."
        if len(profiles) == 5:
            note += " Minimal AOT uses separately qualified artifacts and a smaller runtime."
        fig.text(0.075, 0.115, footer(report, report["configuration"]["samples"], "runtime"), fontsize=9, color="#475569")
        fig.text(0.075, 0.077, note, fontsize=9, color="#475569")
        detail = "Bars include host startup, module loading, execution, output and process teardown."
        if clipped:
            detail += " Lower MAD whiskers clipped at the positive logarithmic floor."
        fig.text(0.075, 0.043, detail, fontsize=9, color="#475569")
        save(fig, output, filename, title, note + " " + detail, report_path, report_bytes, report)

    fig, axes = plt.subplots(len(BACKENDS), 1, figsize=(16, 9), facecolor="white", squeeze=False)
    fig.subplots_adjust(left=0.075, right=0.985, top=0.81, bottom=0.15, hspace=0.65)
    title = "Wasmtime preparation"
    fig.text(0.075, 0.955, title, fontsize=20, weight="bold")
    fig.text(0.075, 0.918, "Fresh host launch + Wasm compilation + serialization + file writing · lower is better", fontsize=11, color="#475569")
    clipped = False
    for ax, backend, label in zip(axes[:, 0], BACKENDS, ("Direct Wasm",)):
        profiles = list(PREPARATION_PROFILES)
        if report["configuration"].get("aot_host"):
            profiles.append(MINIMAL_PREPARATION_PROFILE)
        ax.set_title(label, loc="left", fontsize=12, weight="bold", pad=15)
        rows = {(name, configuration): preparation[name, backend, configuration]
                for name in names for configuration, _, _ in profiles}
        panel_handles, panel_clipped = plot(ax, names, rows, "wall_seconds", profiles, True)
        if backend == "direct":
            handles = panel_handles
            legend_profiles = profiles
        clipped = clipped or panel_clipped
    fig.legend(handles, [profile[1] for profile in legend_profiles], loc="upper left",
               bbox_to_anchor=(0.068, 0.891), ncols=len(legend_profiles), frameon=False, fontsize=11)
    note = "Complete preparation cost for trusted native artifacts; guest execution is separate. Goose compilation is unchanged and separate."
    fig.text(0.075, 0.087, footer(report, report["configuration"]["prepare_samples"], "preparation"), fontsize=9, color="#475569")
    fig.text(0.075, 0.057, note, fontsize=9, color="#475569")
    detail = "Wasmtime 50.0.1 · compilation profile and parallelism recorded separately."
    if clipped:
        detail += " Lower MAD whiskers clipped at the positive logarithmic floor."
    fig.text(0.075, 0.028, detail, fontsize=9, color="#475569")
    save(fig, output, "wasmtime-host-preparation.svg", title, note + " " + detail, report_path, report_bytes, report)
    require(report_path.read_bytes() == report_bytes, "Measurement report changed during rendering")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    if not __debug__:
        parser.error("chart validation requires Python without -O")
    render(args.report.resolve(), args.output_dir.resolve())


if __name__ == "__main__":
    main()
