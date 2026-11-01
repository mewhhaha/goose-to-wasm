#!/usr/bin/env python3
"""Render README charts from retained measurements; requires matplotlib."""

import hashlib
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import MultipleLocator, StrMethodFormatter


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "bench/results/2026-10-26/langarena/report.json"
OUTPUT = ROOT / "bench/charts"
TASKS = (
    "CLBG::Fannkuchredux",
    "CLBG::Mandelbrot",
    "Etc::Sieve",
    "Hash::CRC32",
    "Hash::SHA256",
    "Sort::Merge",
    "Sort::Quick",
)
LABELS = ("Fannkuch", "Mandelbrot", "Sieve", "CRC32", "Custom hash", "Merge sort", "Quicksort")
BACKENDS = (
    ("direct", "Direct Wasm", "#087f8c"),
    ("c-wasm", "C → Wasm", "#ce862a"),
    ("native", "C → native", "#727b8e"),
)


def figure(height, title, subtitle):
    fig = plt.figure(figsize=(11, height), facecolor="white")
    fig.text(0.075, 0.94, title, fontsize=20, weight="bold")
    fig.text(0.075, 0.89, subtitle, fontsize=11, color="#475569")
    return fig


def plot(ax, rows, metric, factor, ceiling, step, units, number_format):
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#e2e8f0", linewidth=0.8)
    ax.spines[["top", "right", "left"]].set_visible(False)
    ax.spines["bottom"].set_color("#94a3b8")
    ax.tick_params(axis="both", length=0, pad=9)
    ax.set_xticks(range(len(TASKS)), LABELS, fontsize=10)
    ax.set_ylim(0, ceiling)
    ax.set_xlim(-0.55, len(TASKS) - 0.45)
    ax.yaxis.set_major_locator(MultipleLocator(step))
    ax.yaxis.set_major_formatter(StrMethodFormatter("{x:,.0f}"))
    ax.set_ylabel(units, fontsize=11, labelpad=10, color="#475569")
    handles = []
    for index, (backend, label, color) in enumerate(BACKENDS):
        samples = [rows[(task, backend)][metric] for task in TASKS]
        values = [sample["median"] * factor for sample in samples]
        errors = [sample["mad"] * factor for sample in samples]
        positions = [x + (index - 1) * 0.24 for x in range(len(TASKS))]
        bars = ax.bar(
            positions, values, width=0.22, color=color, label=label,
            yerr=errors, error_kw={"ecolor": "#334155", "elinewidth": 0.8, "capsize": 2},
        )
        handles.append(bars[0])
        for x, value, error in zip(positions, values, errors):
            ax.text(
                x, value + error + ceiling * 0.018, format(value, number_format),
                ha="center", va="bottom", fontsize=8.5, color="#334155",
            )
    return handles


def save(fig, name, title, report_bytes):
    path = OUTPUT / name
    fig.savefig(
        path, facecolor="white",
        metadata={
            "Date": None,
            "Title": title,
            "Description": "Seven adapted LangArena workloads. Preliminary medians of three samples; "
            "whiskers show median absolute deviation. Lower is better.",
            "Source": f"bench/results/2026-10-26/langarena/report.json sha256:{hashlib.sha256(report_bytes).hexdigest()}",
        },
    )
    plt.close(fig)
    path.write_text("\n".join(line.rstrip() for line in path.read_text().splitlines()) + "\n")


def main():
    plt.rcParams.update({
        "font.family": "DejaVu Sans", "font.size": 10, "text.color": "#0f172a",
        "axes.labelcolor": "#475569", "xtick.color": "#334155", "ytick.color": "#475569",
        "svg.fonttype": "none", "svg.hashsalt": "goose-readme-charts",
    })
    report_bytes = REPORT.read_bytes()
    report = json.loads(report_bytes)
    builds = {
        (row["task"], row["backend"]): row
        for row in report["compile_summary"]
        if row["track"] == "adapted" and row["phase"] == "cold"
    }
    OUTPUT.mkdir(exist_ok=True)
    fig = figure(4.6, "Compilation", "Complete uncached builds · milliseconds · lower is better")
    ax = fig.add_axes((0.075, 0.19, 0.9, 0.58))
    handles = plot(ax, builds, "wall_seconds", 1000, 1250, 250, "milliseconds", ".0f")
    fig.legend(handles, [b[1] for b in BACKENDS], loc="upper left", bbox_to_anchor=(0.067, 0.87),
               ncols=3, frameon=False, fontsize=11)
    fig.text(0.075, 0.055, "2026-10-26 · AMD EPYC 9V74 KVM · 3 samples · whiskers: ±MAD", fontsize=10, color="#475569")
    save(fig, "compilation.svg", "Goose compilation time by backend", report_bytes)

    fig = figure(8, "Runtime", "Configured measured iterations · seconds · lower is better")
    for engine, y in (("v8", 0.50), ("wasmtime", 0.14)):
        rows = {}
        for row in report["runtime_summary"]:
            if row["track"] != "adapted" or row["profile"] != "run":
                continue
            if row["engine"] in (engine, "native"):
                rows[(row["task"], row["backend"])] = row
        ax = fig.add_axes((0.075, y, 0.9, 0.26))
        ax.set_title(engine.upper(), loc="left", fontsize=12, weight="bold", pad=12)
        handles = plot(ax, rows, "timed_region_seconds", 1, 10.5, 2, "seconds", ".2f")
    fig.legend(handles, [b[1] for b in BACKENDS], loc="upper left", bbox_to_anchor=(0.067, 0.87),
               ncols=3, frameon=False, fontsize=11)
    fig.text(0.075, 0.055, "2026-10-26 · AMD EPYC 9V74 KVM · 3 samples · whiskers: ±MAD", fontsize=10, color="#475569")
    fig.text(0.075, 0.025, "Preparation, warmups and startup excluded. Native reference repeated in both panels.", fontsize=10, color="#475569")
    save(fig, "runtime.svg", "Goose runtime by backend and Wasm engine", report_bytes)
    print(f"Rendered {OUTPUT.relative_to(ROOT)} from {REPORT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
