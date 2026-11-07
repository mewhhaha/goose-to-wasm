#!/usr/bin/env python3
"""Chart checked computation times from the resident langbench trial."""
import argparse
import hashlib
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

import langbench
import langbench_charts as charts
import langbench_hot as hot

ROOT = Path(__file__).resolve().parents[1]


def checked_rows(report):
    if report.get("schema") != "goose-langbench-hot-v1" or report.get("status") != "passed":
        raise ValueError("a complete passing resident trial is required")
    rows = hot.summaries(report)
    if rows != report.get("summary") or not all(row["qualified"] for row in rows):
        raise ValueError("summaries differ from complete raw observations")
    wasmtime = report["preparation"]["wasmtime"]
    v8 = report["preparation"]["v8"]
    if (wasmtime["module_compile_count"] != 1 or wasmtime["module_deserialize_count"] != 1
            or v8["module_construction_count"] != 1):
        raise ValueError("resident modules were not prepared exactly once")
    source_hashes = {wasmtime["source_sha256"], v8["source_sha256"]}
    source_hashes.update(value["sha256"] for cell, value in report["reference_receipts"]["artifacts"].items()
                         if cell.startswith("goose-wasm-"))
    if len(source_hashes) != 1:
        raise ValueError("resident engines do not use the same referenced module")
    for row in report["runs"]:
        expected = report["manifest"]["profiles"][row["profile"]]["checksum"]
        parsed = langbench.parse_result(row["stdout"], row["exit_code"], expected, row["cell"])
        if row["checksum"] != parsed["checksum"] or row["timed_region_ns"] != parsed["timed_region_ns"]:
            raise ValueError("runtime record differs from its checked output")
        if row["cell"].startswith("goose-wasm-"):
            engine = row["cell"].removeprefix("goose-wasm-")
            if row["pid"] != report["preparation"][engine]["pid"] or row["source_sha256"] not in source_hashes:
                raise ValueError("resident process or module identity changed between calls")
            if engine == "wasmtime" and (row["module_compile_count"] != 1 or row["module_deserialize_count"] != 1):
                raise ValueError("Wasmtime prepared code again during execution")
            if engine == "v8" and row["module_construction_count"] != 1:
                raise ValueError("V8 constructed another module during execution")
    return {(row["profile"], row["cell"]): row for row in rows}


def render(report_path, output):
    raw = report_path.read_bytes()
    report = json.loads(raw)
    rows = checked_rows(report)
    output.mkdir(parents=True, exist_ok=True)
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10,
                        "text.color": "#0f172a", "axes.labelcolor": "#475569",
                        "svg.fonttype": "none", "svg.hashsalt": "goose-langbench-hot-v1"})
    fig, axes = plt.subplots(1, len(report["profiles"]), figsize=(13.5, 5.4), squeeze=False)
    fig.subplots_adjust(left=0.06, right=0.985, bottom=0.27, top=0.72, wspace=0.28)
    fig.text(0.06, 0.93, "Hot execution · langbench Mandelbrot", fontsize=20, weight="bold")
    fig.text(0.06, 0.865, "Prepared modules · warmup before measurement · setup excluded · lower is better", color="#475569")
    values_receipt = []
    for ax, profile in zip(axes[0], report["profiles"]):
        config = report["manifest"]["profiles"][profile]
        values = [rows[profile, cell]["timed_region_ns"]["median"] / 1e6 for cell in langbench.CELLS]
        errors = [rows[profile, cell]["timed_region_ns"]["mad"] / 1e6 for cell in langbench.CELLS]
        charts.bars(ax, values, errors, charts.LABELS, charts.COLORS)
        title = f"{config['n']}² · {config['max_iter']:,} iterations"
        if profile == "official":
            title += " · official input"
        ax.set_title(title, fontsize=11, pad=13)
        values_receipt.append({"profile": profile, "cells": list(langbench.CELLS),
                               "median_ms": values, "mad_ms": errors})
    fig.text(0.06, 0.13, f"Medians of {report['samples']} samples · whiskers: ±MAD · independent panel scales · shared host, CPU {report['cpu']}", fontsize=10, color="#475569")
    fig.text(0.06, 0.08, "Wasm engines stay resident and reuse compiled modules; fresh instances reset state before each kernel.", fontsize=10, color="#475569")
    fig.text(0.06, 0.03, "C includes one pthread/row queue; Goose is scalar. V8 uses default tiering. Native process setup is excluded.", fontsize=10, color="#475569")
    source = str(report_path)
    if report_path.is_relative_to(ROOT):
        source = str(report_path.relative_to(ROOT))
    digest = hashlib.sha256(raw).hexdigest()
    name = "langbench-hot-runtime.svg"
    charts.save_svg(fig, output / name, {"Date": None, "Title": "Resident langbench Mandelbrot execution",
                    "Source": f"{source} sha256:{digest}",
                    "Description": "Kernel clocks exclude startup, module compilation/deserialization, instantiation, input, output and IPC. Both Wasm engines reuse prepared modules after checked warmups."})
    return {"schema": "goose-langbench-hot-chart-v1", "report": source, "report_sha256": digest,
            "charts": {name: {"values": values_receipt, "sha256": langbench.sha256(output / name)}}}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "bench/charts")
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    args.receipt.write_text(json.dumps(render(args.report.resolve(), args.output_dir), indent=2) + "\n")
