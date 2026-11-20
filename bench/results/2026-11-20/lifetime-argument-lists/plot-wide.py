"""Plot the median lifetime instruction counts from measure-wide.py."""
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import PercentFormatter

directory = Path(__file__).resolve().parent
rows = json.loads((directory / "wide-summary.json").read_text())
widths = sorted(map(int, rows))
saved = [100 * (1 - rows[str(width)]["ratio"]) for width in widths]
plt.rcParams["svg.hashsalt"] = "lifetime-argument-lists"
fig, ax = plt.subplots(figsize=(7.4, 3.7), layout="constrained")
ax.set_title("Wider calls save more work in lifetime checking",
             loc="left", fontsize=14, weight="bold", pad=24)
ax.text(0, 1.02, "Ten calls per program · cached Wasmtime · eight paired compilations",
        transform=ax.transAxes, fontsize=10, color="#46566a")
bars = ax.bar(range(len(widths)), saved, color="#008478", width=.60)
ax.bar_label(bars, [f"{v:.1f}%" for v in saved], padding=4, fontsize=11, weight="bold")
ax.set_xticks(range(len(widths)), labels=list(map(str, widths)))
ax.set_xlabel("Arguments per call")
ax.set_ylabel("Reduction in lifetime instructions")
ax.yaxis.set_major_formatter(PercentFormatter(xmax=100))
ax.set_ylim(0, max(saved) * 1.18)
ax.set_axisbelow(True)
ax.grid(axis="y", linewidth=.8, color="#dce2e7")
ax.spines[:].set_visible(False)
ax.tick_params(length=0, pad=5)
fig.savefig(directory / "wide-arguments.png", dpi=160)
svg = directory / "wide-arguments.svg"
fig.savefig(svg, metadata={"Date": None})
svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
