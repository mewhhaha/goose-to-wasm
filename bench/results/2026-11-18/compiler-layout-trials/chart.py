"""Render the guest-execution medians from the four alternating memory trials."""
import json
from pathlib import Path
from statistics import median

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

folder = Path(__file__).resolve().parent
data = json.loads((folder / "memory/validation-root.json").read_text())
series = [
    ("general64", "Default 64-bit", "#73879b"),
    ("root32", "32-bit · three examples", "#087d71"),
    ("calibrated32", "32-bit · compiler profile", "#40526d"),
]
plt.rcParams.update({"font.size": 11, "svg.fonttype": "none", "svg.hashsalt": "layout-trials"})
fig, axes = plt.subplots(1, 2, figsize=(8.6, 3.8), sharey=True)
fig.subplots_adjust(left=.08, right=.98, top=.74, bottom=.18, wspace=.15)
fig.text(.08, .93, "Time to check and emit the frozen compiler", fontsize=16, weight="bold")
fig.text(.08, .83, "Prepared Wasmtime · guest seconds · lower is faster", color="#374151")
for ax, mode, title in zip(axes, ["self-check", "self-emit"], ["Check", "Emit Wasm"]):
    for idx, (key, label, color) in enumerate(series):
        times = data["self_timing_s"][mode][key]
        assert len(times) == 4
        value = median(times)
        ax.bar(idx, value, color=color, width=.65, label=label, zorder=2)
        ax.text(idx, value + .15, f"{value:.2f}", ha="center")
    ax.set_xlabel(title, weight="bold")
    ax.set_ylim(0, 8)
    ax.set_yticks([0, 2, 4, 6, 8])
    ax.set_xticks([])
    ax.tick_params(length=0)
    ax.spines[:].set_visible(False)
    ax.grid(axis="y", color="#d9dfe6", linewidth=.7)
fig.legend(*axes[0].get_legend_handles_labels(), loc="lower center", ncols=3, frameon=False)
fig.savefig(folder / "memory.png", dpi=150)
svg = folder / "memory.svg"
fig.savefig(svg, metadata={"Date": None})
svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
