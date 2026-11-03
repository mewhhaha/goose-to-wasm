#!/usr/bin/env python3
"""Render the fresh-process and resident-worker lifecycle comparison."""

import argparse
import hashlib
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
FRESH_MODES = ("ordinary", "cache-hit", "precompiled", "native-C")
MODE_LABELS = {"ordinary": "cold (--no-cache)", "cache-hit": "disk cache hit",
               "precompiled": "precompiled", "native-C": "native C"}
COLORS = {"ordinary": "#64748b", "cache-hit": "#0ea5e9", "precompiled": "#8b5cf6",
          "native-C": "#f97316", "worker-hit": "#14b8a6"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def render(report_path, output_path):
    report_bytes = report_path.read_bytes()
    report = json.loads(report_bytes)
    require(report.get("schema") == "goose-runtime-lifecycle-v1", "unexpected lifecycle report schema")
    require(report.get("status") == "passed", "only a complete passed report can be charted")
    examples = report["examples"]
    names = [item["name"] for item in examples]
    require(len(names) == 10 and len(set(names)) == 10, "chart requires all 10 unique examples")
    samples = report["configuration"]["samples"]
    require(all(all(item["modes"][mode]["n"] == samples for mode in (*FRESH_MODES, "worker-hit"))
                 for item in examples), "chart sample counts are incomplete")

    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 9,
                         "text.color": "#0f172a", "axes.labelcolor": "#475569",
                         "xtick.color": "#334155", "ytick.color": "#475569",
                         "svg.fonttype": "none", "svg.hashsalt": "goose-runtime-lifecycle-v1"})
    fig, axes = plt.subplots(2, 1, figsize=(14, 11), facecolor="white",
                             gridspec_kw={"height_ratios": [3.1, 1.2]})
    fig.subplots_adjust(left=0.19, right=0.91, top=0.88, bottom=0.18, hspace=0.5)
    title = "Wasmtime lifecycle · cold process and resident worker"
    fig.text(0.06, 0.95, title, fontsize=20, weight="bold")
    fig.text(0.06, 0.915, "Example catalog · wall-clock milliseconds · lower is better · log scale",
             fontsize=11, color="#475569")

    numeric_labels = []
    y_base = np.arange(len(names), dtype=float)
    offsets = np.linspace(-0.27, 0.27, len(FRESH_MODES))
    ax = axes[0]
    for mode, offset in zip(FRESH_MODES, offsets):
        medians = [item["modes"][mode]["median_seconds"] * 1000 for item in examples]
        mads = [item["modes"][mode]["mad_seconds"] * 1000 for item in examples]
        bars = ax.barh(y_base + offset, medians, height=0.13, color=COLORS[mode],
                       label=MODE_LABELS[mode],
                       xerr=mads, error_kw={"elinewidth": 0.8, "capsize": 2, "ecolor": "#334155"})
        for bar, value, mad in zip(bars, medians, mads):
            label = f"{value:.2f}"
            numeric_labels.append(label)
            ax.text((value + mad) * 1.08, bar.get_y() + bar.get_height() / 2, label,
                    va="center", ha="left", fontsize=7, color="#334155")
    ax.set_yticks(y_base, names)
    ax.invert_yaxis()
    ax.set_xscale("log")
    ax.set_xlabel("Fresh-process wall time (ms)")
    ax.set_title("Fresh processes · one launch per sample",
                 loc="left", fontsize=12, weight="bold", pad=12)
    ax.grid(axis="x", color="#e2e8f0", linewidth=0.8)
    ax.set_axisbelow(True)
    ax.spines[["top", "right", "left"]].set_visible(False)
    ax.legend(ncols=4, frameon=False, loc="lower right", bbox_to_anchor=(1, 1.01))

    ax = axes[1]
    medians = [item["modes"]["worker-hit"]["median_seconds"] * 1000 for item in examples]
    mads = [item["modes"]["worker-hit"]["mad_seconds"] * 1000 for item in examples]
    bars = ax.barh(y_base, medians, height=0.48, color=COLORS["worker-hit"],
                   xerr=mads, error_kw={"elinewidth": 0.8, "capsize": 2, "ecolor": "#334155"})
    for bar, value, mad in zip(bars, medians, mads):
        label = f"{value:.2f}"
        numeric_labels.append(label)
        ax.text((value + mad) * 1.08, bar.get_y() + bar.get_height() / 2, label,
                va="center", ha="left", fontsize=8, color="#334155")
    ax.set_yticks(y_base, names)
    ax.invert_yaxis()
    ax.set_xscale("log")
    ax.set_xlabel("Request round trip (ms)")
    ax.set_title("Resident worker · already-running process, fresh Store and instance per request",
                 loc="left", fontsize=12, weight="bold", pad=12)
    ax.grid(axis="x", color="#e2e8f0", linewidth=0.8)
    ax.set_axisbelow(True)
    ax.spines[["top", "right", "left"]].set_visible(False)

    config = report["configuration"]
    prep_values = [item["cache_warm"]["wall_ns"] / 1e9 for item in report["preparation"].values()]
    aot_values = [item["precompile"]["wall_ns"] / 1e9 for item in report["preparation"].values()]
    prep_note = (f"{config['samples']} samples/mode · ±MAD · {report['started_utc'][:10]} · "
                 f"{report['environment']['cpu']} · cache/AOT prep excluded "
                 f"(median {np.median(prep_values):.3f}s / {np.median(aot_values):.3f}s) · "
                 f"worker startup and first request recorded separately")
    fig.text(0.06, 0.105, prep_note, fontsize=8, color="#475569")
    fig.text(0.06, 0.075, "Cache-miss fresh launches are retained in raw evidence; the chart focuses on ordinary and reusable states.",
             fontsize=8, color="#475569")

    label_payload = json.dumps(numeric_labels, separators=(",", ":")).encode()
    label_hash = hashlib.sha256(label_payload).hexdigest()
    description = {"report_sha256": hashlib.sha256(report_bytes).hexdigest(),
                   "numeric_label_sha256": label_hash, "numeric_label_count": len(numeric_labels),
                   "numeric_labels": numeric_labels, "examples": names,
                   "method": "fresh-process and resident worker are separate panels; not a matched comparison"}
    output_path.parent.mkdir(parents=True, exist_ok=True)
    require(not output_path.exists(), "refusing to overwrite an existing lifecycle chart")
    fig.savefig(output_path, facecolor="white", metadata={"Date": None, "Title": title,
                 "Description": json.dumps(description, sort_keys=True),
                 "Source": str(report_path) + " sha256:" + hashlib.sha256(report_bytes).hexdigest()})
    plt.close(fig)
    svg = output_path.read_text()
    require(all(label in svg for label in set(numeric_labels)), "rendered SVG is missing a numeric bar label")
    require(hashlib.sha256(label_payload).hexdigest() == description["numeric_label_sha256"],
            "numeric label digest mismatch")
    require(report_path.read_bytes() == report_bytes, "measurement report changed during rendering")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "bench/charts/runtime-lifecycle.svg")
    args = parser.parse_args()
    if not __debug__:
        parser.error("chart validation requires Python without -O")
    render(args.report.resolve(), args.output.resolve())


if __name__ == "__main__":
    main()
