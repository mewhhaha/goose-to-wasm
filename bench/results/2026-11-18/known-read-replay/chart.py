"""Chart the confirmed per-invocation CPU times on the frozen compiler project."""
import json
from pathlib import Path
from statistics import median

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

folder = Path(__file__).resolve().parent
runs = json.loads((folder / "confirmation.json").read_text())["samples"]
plt.rcParams.update({"svg.hashsalt": "known-read-replay", "svg.fonttype": "none"})
fig, ax = plt.subplots(figsize=(9.1, 4.5))
fig.subplots_adjust(left=.22, right=.88, top=.78, bottom=.15)
names = ["Wasmtime check", "Wasmtime emit", "Native check", "Native emit"]
for i, (host, mode) in enumerate((("wasmtime", "check"), ("wasmtime", "emit"), ("native", "check"), ("native", "emit"))):
    for version, offset, color, label in (("baseline", -.16, "#9aa9b5", "Released baseline"),
                                           ("candidate", .16, "#176b70", "Direct read")):
        values = [r["counters"]["invocation_cpu_ns"] / 1e9 for r in runs
                  if r["host"] == host and r["mode"] == mode and r["label"] == version]
        value = median(values)
        if i > 0:
            label = None
        y = i + offset
        ax.barh(y, value, height=.28, color=color, label=label)
        ax.text(value + .12, y, f"{value:.2f} s", va="center", fontsize=10)
ax.set_yticks(range(4), names, fontsize=11)
ax.invert_yaxis()
ax.tick_params(axis="both", length=0)
ax.spines[:].set_visible(False)
ax.set_xticks([])
ax.set_xlim(0, max(p.get_width() for p in ax.patches) * 1.13)
ax.legend(loc="lower left", bbox_to_anchor=(0, 1), ncol=2, frameon=False, fontsize=10, borderaxespad=0)
fig.text(.035, .93, "Checking and compiling the same Goose project", fontsize=17, weight="bold")
rounds = len({r["round"] for r in runs})
fig.text(.035, .055, f"Median CPU seconds across {rounds} alternating pairs. Wasmtime reuses a prepared memory64 module.", fontsize=10)
fig.savefig(folder / "comparison.png", dpi=150)
svg = folder / "comparison.svg"
fig.savefig(svg, metadata={"Date": None})
svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
