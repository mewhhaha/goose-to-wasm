#!/usr/bin/env python3
"""Render the compiler build and execution bars from checked self-hosting runs."""
import argparse
import hashlib
import json
from pathlib import Path
from statistics import median

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch
from matplotlib.ticker import MaxNLocator

from selfhost_comparison import ENGINES, ROOT, WORKLOADS


COLORS = {"native": "#475569", "wasmtime": "#087f8c", "v8": "#d39b28", "wasm": "#087f8c"}
NAME = "compiler-selfhost-execution.svg"


def seconds(values):
    if any(value <= 0 for value in values):
        raise ValueError("elapsed time must be positive")
    return {"median": median(values) / 1e9, "min": min(values) / 1e9, "max": max(values) / 1e9}


def timings(report):
    if report["schema"] != "goose-selfhost-comparison-v1":
        raise ValueError("unsupported self-hosting report")
    builds = report["build"]["samples"]
    artifact = builds[0]["artifacts"]["compiler.wasm"]
    if any(sample["artifacts"] != builds[0]["artifacts"] for sample in builds):
        raise ValueError("build artifacts differ")
    if report["v8"]["source_sha256"] != artifact["sha256"]:
        raise ValueError("V8 module differs")
    build_times = {target: seconds([sample[target]["wall_ns"] for sample in builds])
                   for target in ("native", "wasm")}

    cells = {(workload, engine): [] for workload in WORKLOADS for engine in ENGINES}
    proofs = {}
    groups = report["execution"]["samples"]
    if not isinstance(groups, list) or not groups:
        raise ValueError("missing execution rounds")
    for group in groups:
        if not isinstance(group, list):
            raise ValueError("expected execution samples grouped by round")
        if len(group) != len(cells) or {(row["workload"], row["engine"]) for row in group} != cells.keys():
            raise ValueError("incomplete execution round")
        for row in group:
            workload, engine = row["workload"], row["engine"]
            result = row["result"]
            if result["exit_code"] != 0 or result != proofs.setdefault(workload, result):
                raise ValueError("different execution results")
            if workload == "emit" and result["emitted_wasm"] != artifact:
                raise ValueError("self-emission did not reproduce the input module")
            cells[workload, engine].append(row["wall_ns"])
    execution = {workload: {engine: seconds(cells[workload, engine]) for engine in ENGINES}
                 for workload in WORKLOADS}
    return {"build": build_times, "execution": execution}


def panel(ax, title, labels, positions, ceiling):
    ax.set_title(title, loc="left", fontsize=13, fontweight="bold", pad=11)
    ax.set_axisbelow(True)
    ax.grid(axis="x", color="#e2e8f0", linewidth=0.8)
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=8, colors="#475569")
    ax.set_xlim(0, ceiling)
    ax.xaxis.set_major_locator(MaxNLocator(5, integer=True))
    ax.set_yticks(positions, labels)
    ax.set_ylim(positions[-1] + 0.6, -0.6)


def bar(ax, position, engine, stats, ceiling):
    value = stats["median"]
    ax.barh(position, value, height=0.68, color=COLORS[engine],
            xerr=[[value - stats["min"]], [stats["max"] - value]],
            error_kw={"ecolor": "#1e293b", "elinewidth": 0.9, "capsize": 2.5})
    ax.text(stats["max"] + ceiling * 0.016, position, f"{value:.2f} s",
            va="center", color="#0f172a", fontsize=10, fontweight="bold")


def render(path, output, preview):
    raw = path.read_bytes()
    report = json.loads(raw)
    values = timings(report)
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10.5, "text.color": "#0f172a",
                        "svg.fonttype": "none", "svg.hashsalt": "goose-selfhost-execution-v1"})
    fig = plt.figure(figsize=(9.6, 6.1), facecolor="white")
    build, execution = fig.subplots(2, 1, gridspec_kw={"height_ratios": [2.1, 5.3]})
    fig.subplots_adjust(left=0.20, right=0.94, top=0.75, bottom=0.20, hspace=0.59)
    fig.text(0.05, 0.925, "Build and run the Goose-to-Wasm compiler", fontsize=20, fontweight="bold")
    source = report["build"]["source_commit"][:7]
    fig.text(0.05, 0.873, f"Compiler self-hosting on the frozen project sources at {source}",
             color="#475569", fontsize=11)
    ceiling = 1.16 * max([row["max"] for row in values["build"].values()] +
                         [row["max"] for cases in values["execution"].values() for row in cases.values()])

    panel(build, "Build from source", ["Native via Clang", "Direct Wasm"], [0, 1], ceiling)
    for position, (name, row) in enumerate(values["build"].items()):
        bar(build, position, name, row, ceiling)

    panel(execution, "Run on the same project", ["Check project", "Emit compiler.wasm"], [1, 4.65], ceiling)
    execution.set_ylim(6.23, -0.57)
    for start, workload in ((0, "check"), (3.65, "emit")):
        for index, engine in enumerate(ENGINES):
            bar(execution, start + index, engine, values["execution"][workload][engine], ceiling)
    execution.legend([Patch(color=COLORS[engine]) for engine in ENGINES],
                     ["Native", "Wasm · Wasmtime", "Wasm · V8"], ncols=3,
                     loc="lower left", bbox_to_anchor=(0.0, -0.37), frameon=False, borderaxespad=0.0)
    builds, runs = len(report["build"]["samples"]), len(report["execution"]["samples"])
    fig.text(0.05, 0.062,
             f"Wall seconds · {builds} build samples · {runs} execution samples · median and range per bar",
             color="#475569", fontsize=9.4)
    fig.text(0.05, 0.027,
             "Wasm execution starts after engine preparation and instantiation. Native includes process launch.",
             color="#475569", fontsize=9.4)

    source_path = str(path)
    if path.is_relative_to(ROOT):
        source_path = str(path.relative_to(ROOT))
    digest = hashlib.sha256(raw).hexdigest()
    output.mkdir(parents=True, exist_ok=True)
    chart = output / NAME
    fig.savefig(chart, metadata={"Date": None, "Title": "Goose-to-Wasm self-hosted compiler comparison",
                                "Source": f"{source_path} sha256:{digest}"})
    chart.write_text("\n".join(line.rstrip() for line in chart.read_text().splitlines()) + "\n")
    if preview:
        fig.savefig(preview, dpi=130)
    plt.close(fig)
    return {"report": source_path, "report_sha256": digest, "chart": NAME,
            "chart_sha256": hashlib.sha256(chart.read_bytes()).hexdigest(), "seconds": values}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "bench/charts")
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    args.receipt.write_text(json.dumps(render(args.report.resolve(), args.output_dir, args.preview), indent=2) + "\n")
