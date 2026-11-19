"""Plot full compiler-process timings for programs with many distinct calls."""
import argparse
from pathlib import Path
import json
from statistics import median

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("directory", type=Path, help="directory containing scaling.json")
directory = parser.parse_args().directory
report = json.loads((directory / "scaling.json").read_bytes())
sizes = sorted(int(size) for size in report["sizes"])
groups = [("baseline", "Original scan", "#345369"), ("indexed", "Indexed lookup", "#087d73")]
plt.rcParams.update({"font.size": 10, "svg.hashsalt": "wasm-function-lookup", "svg.fonttype": "none"})
fig, ax = plt.subplots(figsize=(7.8, 3.7), layout="constrained")
for index, (name, label, color) in enumerate(groups):
    values = []
    for size in sizes:
        case = report["sizes"][str(size)]
        samples = [row for row in case["samples"] if row["case"] == name]
        if {row["round"] for row in samples} != {1, 2, 3} or len(samples) != 3:
            raise ValueError(f"Incomplete sample for {size} functions")
        if int(case["stdout"]) != size * (size + 1) // 2:
            raise ValueError(f"Wrong output for {size} functions")
        values.append(median(row["wall_ns"] for row in samples) / 1e6)
    positions = [i + (index - 0.5) * 0.34 for i in range(len(sizes))]
    bars = ax.bar(positions, values, width=0.32, label=label, color=color)
    ax.bar_label(bars, fmt="%.0f", padding=3, weight="bold")
fig.suptitle("Time to compile a project with many different calls", fontsize=14, weight="bold")
ax.set_title("Three fresh Wasmtime processes per compiler and size · generated programs at -O0", loc="left", fontsize=10)
ax.set_ylabel("Elapsed milliseconds")
ax.set_xticks(range(len(sizes)), [f"{size:,} functions" for size in sizes])
ax.set_ylim(0, ax.get_ylim()[1] * 1.10)
ax.grid(axis="y", color="#dce2e7")
ax.set_axisbelow(True)
ax.spines[:].set_visible(False)
ax.tick_params(length=0, pad=6)
ax.legend(loc="upper left", frameon=False)
fig.savefig(directory / "scaling.png", dpi=150)
svg = directory / "scaling.svg"
fig.savefig(svg, metadata={"Date": None})
svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
plt.close(fig)
