#!/usr/bin/env python3
"""Render the example catalog's retained compilation and runtime measurements."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import textwrap

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter, MaxNLocator


ROOT = Path(__file__).resolve().parents[1]
BACKENDS = (
    ("direct", "Direct Wasm", "#087f8c"),
    ("c-wasm", "C → Wasm", "#ce862a"),
    ("native", "C → native", "#727b8e"),
)
LABELS = {
    "squares": "Squares", "tour": "Tour", "functions": "Functions", "errors": "Errors",
    "sieve": "Sieve", "sorting": "Sorting", "sudoku": "Sudoku", "maze": "Maze",
    "vm": "VM", "life": "Life",
}


def milliseconds(summary):
    median = float(summary["median"]) * 1000
    mad = float(summary["mad"]) * 1000
    if not math.isfinite(median) or not math.isfinite(mad) or median <= 0 or mad < 0:
        raise ValueError(f"Invalid timing summary: {summary}")
    return median, mad


def index_rows(rows, fields):
    result = {}
    for row in rows:
        key = tuple(row[field] for field in fields)
        if key in result:
            raise ValueError(f"Duplicate measurement: {key}")
        result[key] = row
    return result


def plot(ax, names, rows, metric, backends, logarithmic):
    samples = {}
    for backend, _, _ in backends:
        samples[backend] = [milliseconds(rows[name, backend][metric]) for name in names]
    maximum = max(value + error for values in samples.values() for value, error in values)
    minimum = min(value for values in samples.values() for value, _ in values)
    floor = 0
    if logarithmic:
        floor = minimum / 3
        ax.set_yscale("log")
        ax.set_ylim(floor, maximum * 25)
        ax.set_ylabel("milliseconds · logarithmic scale", labelpad=10)
    else:
        ax.set_ylim(0, maximum * 1.38)
        ax.set_ylabel("milliseconds", labelpad=10)
        ax.yaxis.set_major_locator(MaxNLocator(6))
    if logarithmic:
        ax.yaxis.set_major_formatter(FuncFormatter(lambda value, _: f"{value:,.3g}"))
    else:
        ax.yaxis.set_major_formatter(FuncFormatter(lambda value, _: f"{value:,.0f}"))
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#e2e8f0", linewidth=0.8)
    ax.spines[["top", "right", "left"]].set_visible(False)
    ax.spines["bottom"].set_color("#94a3b8")
    ax.tick_params(axis="both", length=0, pad=8)
    ax.set_xticks(range(len(names)), [LABELS[name.lower()] for name in names])
    ax.set_xlim(-0.55,len(names)-0.45)
    handles = []
    width = 0.72 / len(backends)
    clipped = False
    for index, (backend, label, color) in enumerate(backends):
        positions = [position + (index - (len(backends) - 1) / 2) * width for position in range(len(names))]
        values = [value for value, _ in samples[backend]]
        errors = [error for _, error in samples[backend]]
        lower_errors = []
        for value, error in zip(values, errors):
            lower = min(error, value - floor)
            if lower < error:
                clipped = True
            lower_errors.append(lower)
        bars = ax.bar(
            positions, [value-floor for value in values], bottom=floor,
            width=width * 0.86, color=color, label=label,
            yerr=[lower_errors, errors],
            error_kw={"ecolor": "#334155", "elinewidth": 0.8, "capsize": 2},
        )
        handles.append(bars[0])
        for position, value, error in zip(positions, values, errors):
            offset = maximum * 0.012
            if logarithmic:
                offset = (value + error) * 0.07
            ax.text(position, value + error + offset, f"{value:.3g} ±{error:.2g}",
                    ha="center", va="bottom", rotation=90, fontsize=8, color="#334155")
    return handles, clipped


def runtime_rows(report, engine, backends):
    indexed = index_rows(report["runtime_summary"], ("name", "backend", "engine"))
    rows = {}
    for example in report["examples"]:
        name = example["name"]
        for backend, _, _ in backends:
            row_engine = engine
            if backend == "native":
                row_engine = "native"
            rows[name, backend] = indexed[name, backend, row_engine]
    return rows


def validate_measurements(report, names):
    config = report["configuration"]
    builds = index_rows(report["compile_summary"], ("name", "backend"))
    expected_builds = {(name, backend) for name in names for backend, _, _ in BACKENDS}
    if set(builds) != expected_builds:
        raise ValueError("Expected all 30 example/backend compilation summaries")
    runtime = index_rows(report["runtime_summary"], ("name", "backend", "engine"))
    expected_runtime = {(name, "native", "native") for name in names}
    expected_runtime.update((name, backend, engine) for name in names
                            for backend in ("direct", "c-wasm") for engine in ("v8", "wasmtime"))
    if set(runtime) != expected_runtime:
        raise ValueError("Expected all 50 example/backend/engine runtime summaries")

    def check(summary, expected, description):
        if summary["n"] != expected:
            raise ValueError(f"Wrong sample count for {description}: {summary['n']} != {expected}")
        if "samples" in summary and len(summary["samples"]) != expected:
            raise ValueError(f"Incomplete retained samples for {description}")
        milliseconds(summary)

    for key, row in builds.items():
        check(row["wall_seconds"], config["compile_samples"], f"build {key}")
    for key, row in runtime.items():
        check(row["process_wall_seconds"], config["samples"], f"process {key}")
        if row["backend"] != "native":
            for metric in ("entry_function_seconds", "engine_compile_instantiate_seconds"):
                check(row[metric], config["samples"], f"{metric} {key}")


def footer(report, samples, *, runtime=False):
    config = report["configuration"]
    date = report["started_utc"][:10]
    environment = report["environment"]
    host = environment.get("supplied_machine_label")
    if not host:
        host = environment["cpu"]
    warmups = ""
    if runtime:
        warmups = f" · {config['warmups']} runtime warmup(s)"
    return f"{date} · {host} · {samples} measured samples{warmups} · labels: median ±MAD"


def save(fig, output, name, title, note, report_path, report_bytes, report):
    report_hash = hashlib.sha256(report_bytes).hexdigest()
    provenance = [f"{report_path} sha256:{report_hash}",
                  f"{Path(__file__).resolve()} sha256:{hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}"]
    for path, digest in report["environment"]["input_sha256"].items():
        provenance.append(f"{path} sha256:{digest}")
    provenance.append(f"compiler sha256:{report['environment']['compiler_sha256']}")
    environment = json.dumps(report.get("environment", {}), sort_keys=True)
    path = output / name
    fig.savefig(path, facecolor="white", metadata={
        "Date": None, "Title": title,
        "Description": note + " Environment: " + environment,
        "Source": "; ".join(provenance),
    })
    plt.close(fig)
    path.write_text("\n".join(line.rstrip() for line in path.read_text().splitlines()) + "\n")


def render(report_path, output):
    report_bytes = report_path.read_bytes()
    report = json.loads(report_bytes)
    if report["status"] != "passed":
        raise ValueError("Only a passed measurement report can produce charts")
    for source, expected in report["environment"]["input_sha256"].items():
        if hashlib.sha256((ROOT / source).read_bytes()).hexdigest() != expected:
            raise ValueError(f"Measurement input changed: {source}")
    names = [example["name"] for example in report["examples"]]
    if len(names) != len(set(names)) or set(name.lower() for name in names) != set(LABELS):
        raise ValueError("Expected exactly the ten named catalog examples")
    validate_measurements(report,names)
    plt.rcParams.update({
        "font.family": "DejaVu Sans", "font.size": 10, "text.color": "#0f172a",
        "axes.labelcolor": "#475569", "xtick.color": "#334155", "ytick.color": "#475569",
        "svg.fonttype": "none", "svg.hashsalt": "goose-example-charts",
    })
    output.mkdir(parents=True, exist_ok=True)
    config = report["configuration"]
    compile_rows = index_rows(report["compile_summary"], ("name", "backend"))
    fig, ax = plt.subplots(figsize=(14, 7), facecolor="white")
    fig.subplots_adjust(left=0.075, right=0.98, top=0.80, bottom=0.19)
    title = "Example compilation"
    fig.text(0.075, 0.945, title, fontsize=20, weight="bold")
    fig.text(0.075, 0.905, "Complete ordinary uncached Goose builds · O2 · lower is better", fontsize=11, color="#475569")
    handles, _ = plot(ax, names, compile_rows, "wall_seconds", BACKENDS, False)
    fig.legend(handles, [backend[1] for backend in BACKENDS], loc="upper left",
               bbox_to_anchor=(0.068, 0.88), ncols=3, frameon=False, fontsize=11)
    note = "Complete uncached builds, including C compiler/linker work for the reference backends."
    fig.text(0.075, 0.075, footer(report, config["compile_samples"]), fontsize=9, color="#475569")
    fig.text(0.075, 0.04, note, fontsize=9, color="#475569")
    save(fig, output, "examples-compilation.svg", title, note, report_path, report_bytes, report)

    for metric, suffix, title, subtitle, note, backends in (
        ("process_wall_seconds", "runtime", "Example runtime · full process",
         "Startup, engine compile/instantiation, execution and output included · O2 · lower is better",
         "Native process timings are repeated unchanged in both panels; all three backends include their complete CLI cost.", BACKENDS),
        ("entry_function_seconds", "entry", "Example runtime · Wasm entry only",
         "Supplement: entry execution, including lazy JIT work · excludes final output delivery · O2 · lower is better",
         "Separate fresh-process Wasm probes: entry excludes host startup, initial module compilation/instantiation and final output delivery. Lazy JIT work remains included. No native entry comparison; stdout buffering differs.", BACKENDS[:2]),
    ):
        fig, axes = plt.subplots(2, 1, figsize=(14, 12), facecolor="white")
        fig.subplots_adjust(left=0.075, right=0.98, top=0.80, bottom=0.14, hspace=0.52)
        fig.text(0.075, 0.95, title, fontsize=20, weight="bold")
        fig.text(0.075, 0.915, subtitle, fontsize=11, color="#475569")
        clipped = False
        for ax, engine, label in zip(axes, ("v8", "wasmtime"), ("V8", "Wasmtime")):
            ax.set_title(label, loc="left", fontsize=12, weight="bold", pad=14)
            handles, panel_clipped = plot(ax, names, runtime_rows(report, engine, backends), metric, backends, True)
            clipped = clipped or panel_clipped
        fig.legend(handles, [backend[1] for backend in backends], loc="upper left",
                   bbox_to_anchor=(0.068, 0.89), ncols=len(backends), frameon=False, fontsize=11)
        if clipped:
            note += " Lower MAD whiskers are clipped at the positive log-axis limit."
        fig.text(0.075, 0.075, footer(report, config["samples"],runtime=True), fontsize=9, color="#475569")
        fig.text(0.075, 0.035, textwrap.fill(note, 155), fontsize=9, color="#475569")
        save(fig, output, f"examples-{suffix}.svg", title, note, report_path, report_bytes, report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "bench/charts")
    args = parser.parse_args()
    render(args.report.resolve(), args.output_dir.resolve())
    print(f"Rendered three example charts from {args.report}")


if __name__ == "__main__":
    main()
