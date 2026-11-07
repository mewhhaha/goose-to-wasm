#!/usr/bin/env python3
"""Render the local langbench trial from its checked raw observations."""
import argparse
import hashlib
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import MaxNLocator

import langbench

ROOT = Path(__file__).resolve().parents[1]
LABELS = ("C\nGCC", "C\nClang", "Upstream\nGoose", "Goose\nnative", "Wasm\nWasmtime", "Wasm\nV8")
COLORS = ("#94a3b8", "#64748b", "#b58a56", "#475569", "#087f8c", "#d39b28")


def save_svg(fig, path, metadata):
    fig.savefig(path, metadata=metadata)
    path.write_text("\n".join(line.rstrip() for line in path.read_text().splitlines()) + "\n")
    plt.close(fig)


def checked_rows(report):
    if report.get("schema") != "goose-langbench-local-v1" or report.get("status") != "passed":
        raise ValueError("a complete passing local trial is required")
    rows = langbench.summaries(report)
    if rows != report.get("summary") or not all(row["qualified"] for row in rows):
        raise ValueError("published summaries differ from the complete raw observations")
    for row in report["runs"]:
        expected = report["manifest"]["profiles"][row["profile"]]["checksum"]
        actual = langbench.parse_result(row["stdout"], row["exit_code"], expected, row["cell"])
        if row["checksum"] != actual["checksum"] or row["timed_region_ns"] != actual["timed_region_ns"]:
            raise ValueError("runtime record differs from its checked output")
    return {(row["profile"], row["cell"]): row for row in rows}


def bars(ax, values, errors, labels, colors):
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#e2e8f0", linewidth=0.8)
    ax.spines[["top", "right", "left"]].set_visible(False)
    ax.spines["bottom"].set_color("#94a3b8")
    ax.tick_params(length=0, pad=8)
    ax.set_xticks(range(len(labels)), labels, fontsize=8.5)
    ax.yaxis.set_major_locator(MaxNLocator(5))
    ax.set_ylabel("milliseconds", fontsize=10, color="#475569")
    ceiling = max(value + error for value, error in zip(values, errors)) * 1.25
    ax.set_ylim(0, ceiling)
    ax.bar(range(len(values)), values, color=colors, width=0.7, yerr=errors,
           error_kw={"ecolor": "#334155", "elinewidth": 0.8, "capsize": 3})
    ax.axvline(1.5, color="#cbd5e1", linewidth=0.8, linestyle="--")
    for position, value, error in zip(range(len(values)), values, errors):
        ax.text(position, value + error + ceiling * 0.025, f"{value:,.1f}",
                ha="center", fontsize=9, color="#334155")


def render(report_path, output):
    raw = report_path.read_bytes()
    report = json.loads(raw)
    rows = checked_rows(report)
    wasm_hashes = set()
    for row in report["builds"]:
        if row["cell"].startswith("goose-wasm-"):
            wasm_hashes.update(value["sha256"] for path, value in row["artifacts"].items() if path.endswith(".wasm"))
    if not report.get("identical_wasm_artifacts") or len(wasm_hashes) != 1:
        raise ValueError("engine build cells do not contain one identical Wasm artifact")
    output.mkdir(parents=True, exist_ok=True)
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10,
                        "text.color": "#0f172a", "axes.labelcolor": "#475569",
                        "svg.fonttype": "none", "svg.hashsalt": "goose-langbench-local-v1"})
    source = str(report_path)
    if report_path.is_relative_to(ROOT):
        source = str(report_path.relative_to(ROOT))
    metadata = {"Date": None, "Source": f"{source} sha256:{hashlib.sha256(raw).hexdigest()}"}
    receipt = {"schema": "goose-langbench-chart-v1", "report": source,
               "report_sha256": hashlib.sha256(raw).hexdigest(), "charts": {}}

    fig, axes = plt.subplots(1, len(report["profiles"]), figsize=(13.5, 5.4), squeeze=False)
    fig.subplots_adjust(left=0.06, right=0.985, bottom=0.27, top=0.72, wspace=0.28)
    fig.text(0.06, 0.93, "Runtime · langbench Mandelbrot", fontsize=20, weight="bold")
    fig.text(0.06, 0.865, "Fresh-process computation · excludes engine startup · lower is better", color="#475569")
    chart_values = []
    for ax, profile in zip(axes[0], report["profiles"]):
        config = report["manifest"]["profiles"][profile]
        values = [rows[profile, cell]["timed_region_ns"]["median"] / 1e6 for cell in langbench.CELLS]
        errors = [rows[profile, cell]["timed_region_ns"]["mad"] / 1e6 for cell in langbench.CELLS]
        bars(ax, values, errors, LABELS, COLORS)
        title = f"{config['n']}² · {config['max_iter']:,} iterations"
        if profile == "official":
            title += " · official input"
        ax.set_title(title, fontsize=11, pad=13)
        chart_values.append({"profile": profile, "cells": list(langbench.CELLS), "median_ms": values, "mad_ms": errors})
    fig.text(0.06, 0.13, f"Medians of {report['samples']} samples · whiskers: ±MAD · each panel has its own scale · shared host, CPU {report['cpu']}", fontsize=10, color="#475569")
    fig.text(0.06, 0.08, "C includes one pthread and an atomic row queue; Goose uses a scalar port. V8 uses default tiering.", fontsize=10, color="#475569")
    fig.text(0.06, 0.03, "Local single-thread trial; no Docker campaign or parallel-performance claim. Small gaps may be noise.", fontsize=10, color="#475569")
    name = "langbench-runtime.svg"
    save_svg(fig, output / name, {**metadata, "Title": "Local langbench Mandelbrot runtime", "Description": report["scope"]})
    receipt["charts"][name] = {"values": chart_values, "sha256": langbench.sha256(output / name)}

    # Both engines execute byte-identical Wasm; one five-build cell represents emission.
    profile = report["profiles"][0]
    cells = langbench.CELLS[:5]
    values = [rows[profile, cell]["build_wall_seconds"]["median"] * 1000 for cell in cells]
    errors = [rows[profile, cell]["build_wall_seconds"]["mad"] * 1000 for cell in cells]
    fig, ax = plt.subplots(figsize=(10.5, 4.7))
    fig.subplots_adjust(left=0.09, right=0.98, bottom=0.28, top=0.72)
    fig.text(0.09, 0.92, "Compilation · langbench Mandelbrot", fontsize=20, weight="bold")
    fig.text(0.09, 0.85, "Source → native executable / Wasm module · milliseconds · lower is better", color="#475569")
    bars(ax, values, errors, (*LABELS[:4], "Direct\nWasm"), COLORS[:5])
    fig.text(0.09, 0.13, f"Medians of {report['compile_samples']} builds · whiskers: ±MAD · native C: -O3, x86-64-v3, strict floating point", fontsize=10, color="#475569")
    fig.text(0.09, 0.075, "Goose frontend: -O2. Wasm emission is shared by both engines; engine preparation is excluded.", fontsize=10, color="#475569")
    fig.text(0.09, 0.025, "Toolchains already installed · filesystem caches retained · compiler bootstrap excluded", fontsize=10, color="#475569")
    name = "langbench-compilation.svg"
    save_svg(fig, output / name, {**metadata, "Title": "Local langbench Mandelbrot compilation", "Description": report["scope"]})
    receipt["charts"][name] = {"cells": list(cells), "median_ms": values, "mad_ms": errors,
                               "wasm_sha256": next(iter(wasm_hashes)), "sha256": langbench.sha256(output / name)}
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "bench/charts")
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    args.receipt.write_text(json.dumps(render(args.report.resolve(), args.output_dir), indent=2) + "\n")
