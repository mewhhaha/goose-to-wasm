"""Draw the median compiler CPU time from four alternating rounds."""
import json
from pathlib import Path
from statistics import median

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

folder = Path(__file__).resolve().parents[1]
receipt = json.loads((folder / "confirmation.json").read_text())
rows = receipt["samples"]
cases = [("native-before", "Native\nbefore"), ("native-after", "Native\nafter"),
         ("wasm-before", "Wasmtime\nbefore"), ("wasm-after", "Wasmtime\nafter"),
         ("bundled64", "Bundled host\n64-bit"), ("bundled32", "Bundled host\n32-bit¹")]
plt.rcParams.update({"svg.hashsalt": "compiler-record-access", "svg.fonttype": "none"})
fig, ax = plt.subplots(figsize=(9.7, 4.6))
fig.subplots_adjust(left=.05, right=.98, top=.77, bottom=.21)
for i, (case, _) in enumerate(cases):
    for mode, offset, color in [("check", -.205, "#247078"), ("emit", .205, "#7d91a1")]:
        selection = [r for r in rows if r["label"] == case and r["mode"] == mode]
        assert sorted(r["round"] for r in selection) == [1, 2, 3, 4]
        if mode == "emit":
            assert all(r["emitted"] == receipt["expected"][case] for r in selection)
        value = median(r["cpu_ns"] for r in selection) / 1e9
        x = i + offset
        legend = None
        if i == 0:
            legend = mode.capitalize()
        ax.bar(x, value, width=.365, color=color, label=legend)
        ax.text(x, value + .15, f"{value:.2f}", ha="center", va="bottom", fontsize=10)
ax.set_ylim(0, max(b.get_height() for b in ax.patches) * 1.13)
ax.set_xticks(range(len(cases)), [name for _, name in cases], fontsize=10)
ax.tick_params(length=0, pad=6)
ax.set_yticks([])
ax.spines[:].set_visible(False)
ax.legend(loc="upper right", bbox_to_anchor=(1, 1.20), ncols=2, frameon=False, borderaxespad=0)
fig.text(.05, .91, "Checking and compiling the same compiler project", fontsize=17, weight="bold")
fig.text(.05, .82, "Median CPU seconds · four alternating rounds · shorter is faster", fontsize=11)
fig.text(.05, .045, "Default Wasmtime uses memory64. ¹The 32-bit compiler uses a memory layout sized for this project.", fontsize=9)
fig.savefig(folder / "comparison.png", dpi=150)
svg = folder / "comparison.svg"
fig.savefig(svg, metadata={"Date": None})
svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
