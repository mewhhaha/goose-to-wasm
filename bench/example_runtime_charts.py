#!/usr/bin/env python3
"""Render the catalog runtime comparison from a qualified native-host report."""

import argparse
import hashlib
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

from example_charts import BACKENDS, plot
from wasmtime_host_charts import digest, footer, require, validate

ROOT = Path(__file__).resolve().parents[1]


def panel_rows(names, runtime, mode):
    rows = {}
    for name in names:
        for backend, _, _ in BACKENDS:
            row_mode = mode
            if backend == "native":
                row_mode = "native-C"
            rows[name, backend] = runtime[name, backend, row_mode]
    require(len(rows) == 30, "Expected 30 runtime bars per panel")
    return rows


def save(fig, output, title, note, report_path, report_bytes, report):
    provenance = [f"{report_path} sha256:{hashlib.sha256(report_bytes).hexdigest()}"]
    for path in (Path(__file__).resolve(), ROOT / "bench/example_charts.py",
                 ROOT / "bench/wasmtime_host_charts.py"):
        provenance.append(f"{path} sha256:{digest(path)}")
    for path, sha in sorted(report["input_sha256"].items()):
        provenance.append(f"{path} sha256:{sha}")
    host = report["host_build"]
    provenance.extend((f"native host sha256:{host['host_sha256']}",
                       f"Wasmtime {host['version']} {host['library']} sha256:{host['library_sha256']}"))
    description = {"note": note, "method": report["method"], "environment": report["environment"],
                   "host_build": host, "configuration": report["configuration"],
                   "bar_count": 60, "native_C_cohort_repeated": True}
    path = output / "examples-runtime.svg"
    fig.savefig(path, facecolor="white", metadata={
        "Date": None, "Title": title, "Description": json.dumps(description, sort_keys=True),
        "Source": "; ".join(provenance),
    })
    plt.close(fig)
    path.write_text("\n".join(line.rstrip() for line in path.read_text().splitlines()) + "\n")


def render(report_path, output):
    report_bytes = report_path.read_bytes()
    report = json.loads(report_bytes)
    names, runtime, _ = validate(report)
    plt.rcParams.update({
        "font.family": "DejaVu Sans", "font.size": 10, "text.color": "#0f172a",
        "axes.labelcolor": "#475569", "xtick.color": "#334155", "ytick.color": "#475569",
        "svg.fonttype": "none", "svg.hashsalt": "goose-example-runtime-charts-v1",
    })
    fig, axes = plt.subplots(2, 1, figsize=(14, 12), facecolor="white")
    fig.subplots_adjust(left=0.075, right=0.98, top=0.80, bottom=0.16, hspace=0.65)
    title = "Example runtime · full process"
    fig.text(0.075, 0.95, title, fontsize=20, weight="bold")
    fig.text(0.075, 0.915, "Fresh launch to exit · Wasmtime 50.0.1 · O2 · lower is better",
             fontsize=11, color="#475569")
    clipped = False
    for ax, mode, label in zip(axes, ("native", "precompiled"), (
        "Wasmtime native host · compile on launch", "Wasmtime native host · precompiled",
    )):
        ax.set_title(label, loc="left", fontsize=12, weight="bold", pad=14)
        handles, panel_clipped = plot(ax, names, panel_rows(names, runtime, mode),
                                     "wall_seconds", BACKENDS, True)
        clipped = clipped or panel_clipped
    fig.legend(handles, [backend[1] for backend in BACKENDS], loc="upper left",
               bbox_to_anchor=(0.068, 0.89), ncols=3, frameon=False, fontsize=11)
    note = "Precompiled runtime excludes preparation. C → native uses the same measured cohort in both panels."
    detail = "Startup, loading, execution, output and process teardown included."
    if clipped:
        detail += " Lower MAD whiskers clipped at the positive log-axis limit."
    config = report["configuration"]
    fig.text(0.075, 0.095, footer(report, config["samples"], "runtime") +
             f" · {config['warmups']} warmup(s)", fontsize=9, color="#475569")
    fig.text(0.075, 0.062, note, fontsize=9, color="#475569")
    fig.text(0.075, 0.032, detail, fontsize=9, color="#475569")
    require(report_path.read_bytes() == report_bytes, "Measurement report changed during rendering")
    output.mkdir(parents=True, exist_ok=True)
    save(fig, output, title, note + " " + detail, report_path, report_bytes, report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "bench/charts")
    args = parser.parse_args()
    if not __debug__:
        parser.error("chart validation requires Python without -O")
    render(args.report.resolve(), args.output_dir.resolve())


if __name__ == "__main__":
    main()
