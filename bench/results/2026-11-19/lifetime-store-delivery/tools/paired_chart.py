"""Plot median within-round savings from the frozen project measurements."""

import json
from pathlib import Path
from statistics import median

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

directory = Path(__file__).resolve().parents[1]
report = json.loads((directory / "frozen.json").read_text())
samples = {}
for item in report["samples"]:
    if item["output"] != report["expected"]:
        raise ValueError("Unexpected output from rebuild")
    samples[item["case"], item["round"]] = item
rounds = sorted({n for _, n in samples})
metrics = [
    ("Lifetime analysis time", "life_ns"),
    ("Full rebuild time", "wall_ns"),
    ("CPU instructions", "ins"),
    ("Peak memory", "rss_kib"),
]
plt.rcParams.update({"font.size": 11, "svg.hashsalt": "lifetime-delivery", "svg.fonttype": "none"})
fig, ax = plt.subplots(figsize=(7.5, 3.9), layout="constrained")
for engine, name, color, offset in [("native", "Native", "#345369", 0.18), ("wasm", "Cached Wasmtime", "#087d73", -0.18)]:
    savings = []
    for _, key in metrics:
        ratios = [samples[engine + "-after", n][key] / samples[engine + "-before", n][key] for n in rounds]
        savings.append(100 * (1 - median(ratios)))
    bars = ax.barh([3-i+offset for i in range(len(metrics))], savings, height=0.32, label=name, color=color)
    ax.bar_label(bars, fmt="%.1f%%", padding=4)
ax.set_yticks([3, 2, 1, 0], [label for label, _ in metrics])
ax.set_xlim(0, 26)
ax.set_xticks([0, 5, 10, 15, 20, 25], ["0%", "5%", "10%", "15%", "20%", "25%"])
ax.set_axisbelow(True)
ax.grid(axis="x", color="#dce2e7", linewidth=0.8)
ax.spines[:].set_visible(False)
ax.tick_params(length=0)
ax.set_title(f"Median reduction across {len(rounds)} paired frozen compiler rebuilds", loc="left", fontsize=11, pad=8)
fig.suptitle("What the lifetime changes saved", fontsize=16, weight="bold")
ax.legend(loc="lower right", frameon=False)
fig.savefig(directory / "savings.png", dpi=150)
svg = directory / "savings.svg"
fig.savefig(svg, metadata={"Date": None})
svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
