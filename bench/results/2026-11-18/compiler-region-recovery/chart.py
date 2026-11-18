"""Plot paired guest times for one-pass growth and request CPU for retry-based sizing."""

import json
from pathlib import Path
from statistics import median

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

folder = Path(__file__).resolve().parent


def draw(filename, title, subtitle, labels, series):
    plt.rcParams.update(
        {"font.size": 11, "svg.fonttype": "none", "svg.hashsalt": filename}
    )
    fig, ax = plt.subplots(figsize=(8.3, 3.9))
    fig.subplots_adjust(left=0.08, right=0.98, top=0.73, bottom=0.21)
    fig.text(0.08, 0.92, title, fontsize=16, weight="bold")
    fig.text(0.08, 0.82, subtitle, fontsize=11)
    width = 0.7 / len(series)
    for i, (legend, color, values) in enumerate(series):
        x = [j + (i - (len(series) - 1) / 2) * width for j in range(len(labels))]
        bars = ax.bar(x, values, width * 0.93, label=legend, color=color, zorder=2)
        ax.bar_label(bars, fmt="%.2f", padding=3)
    ax.set_ylim(0, max(max(s[2]) for s in series) * 1.16)
    ax.set_xticks(range(len(labels)), labels)
    ax.tick_params(length=0)
    ax.spines[:].set_visible(False)
    ax.grid(axis="y", color="#dce2e7", linewidth=0.7)
    fig.legend(
        *ax.get_legend_handles_labels(),
        loc="lower center",
        ncols=len(series),
        frameon=False,
    )
    fig.savefig(folder / (filename + ".png"), dpi=150)
    svg = folder / (filename + ".svg")
    fig.savefig(svg, metadata={"Date": None})
    svg.write_text(
        "\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n"
    )
    plt.close(fig)


rows = json.loads((folder / "paired.json").read_text())["samples"]


def retry(case):
    times = []
    for dataset in ["blot-parse", "compact"]:
        samples = [r for r in rows if r["case"] == case and r["dataset"] == dataset]
        assert len(samples) == 4 and all(r["matches"] for r in samples)
        times.append(median(r["cpu_ns"] for r in samples) / 1e9)
    return times


draw(
    "retry",
    "Cost of recovering from a full region",
    "Prepared compiler · CPU seconds per complete request · four alternating rounds",
    ["Blot2 parse", "131,071-function parse"],
    [
        ("First request", "#647d94", retry("recover")),
        ("Learned layout", "#007d71", retry("warm")),
        ("Pre-sized control", "#384960", retry("fit")),
    ],
)

def both_runs(name):
    runs = []
    for prefix in ("", "rerun-"):
        runs.extend(json.loads((folder / "live" / (prefix + name)).read_text()))
    return runs


compiler_pairs = both_runs("pairs.json")
blot_pairs = both_runs("blot-only-pairs.json")


def live_seconds(mode):
    times = []
    for case, pairs in (
        ("blot", blot_pairs),
        ("self", compiler_pairs),
        ("emit", compiler_pairs),
    ):
        samples = [r for r in pairs if r["case"] == case and r["mode"] == mode]
        assert len(samples) == 6 and all(r["status"] == 0 for r in samples)
        times.append(median(r["time"]["start_function_ns"] for r in samples) / 1e9)
    return times


draw(
    "live",
    "Growing memory regions during compilation",
    "Wasmtime execution · seconds per run · median of six fixed/live pairs",
    ["Parse Blot2", "Check compiler", "Emit compiler"],
    [
        ("Fixed layout", "#566b80", live_seconds("fixed")),
        ("Live growth", "#007d71", live_seconds("live")),
    ],
)
