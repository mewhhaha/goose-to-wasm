"""Render the machine instructions used to compile the frozen project."""
import json
from pathlib import Path
from statistics import median
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

directory = Path(sys.argv[1])
result = json.loads((directory / "engine-control.json").read_bytes())
rows = result["rows"]
groups = {}
for row in rows:
    if row["sha256"] != result["expected"]:
        raise ValueError("A measured compiler emitted a different module")
    group = groups.setdefault(row["label"], {})
    if row["round"] in group:
        raise ValueError("Duplicate measurement")
    group[row["round"]] = row["ctr"]["instructions"]["value"] / 1e9

order = ["native", "wasmtime", "wasm2c-clang"]
rounds = set(groups["native"])
if not rounds or any(set(groups[name]) != rounds for name in order):
    raise ValueError("Incomplete paired engine runs")
values = [median(groups[name].values()) for name in order]
names = ["Native Goose\nClang", "Same Wasm\nWasmtime", "Same Wasm\nwasm2c + Clang"]
plt.rcParams.update({"font.size": 10, "svg.hashsalt": "same-guest-instructions", "svg.fonttype": "none"})
fig, ax = plt.subplots(figsize=(7.2, 3.65), layout="constrained")
fig.suptitle("CPU instructions to rebuild the Goose compiler", weight="bold", fontsize=14)
ax.set_title(f"Frozen project {result['source_commit'][:7]} · {len(rounds)} runs per configuration", loc="left", fontsize=10)
bars = ax.bar(names, values, width=0.58, color=["#345369", "#087d73", "#5773a6"])
ax.bar_label(bars, fmt="%.2f B", padding=3, weight="bold")
ax.set_ylabel("Billions of retired instructions")
ax.set_ylim(0, max(values)*1.22)
ax.grid(axis="y", color="#dce2e7")
ax.set_axisbelow(True)
ax.spines[:].set_visible(False)
ax.tick_params(length=0, pad=5)
fig.savefig(directory / "engine-control.png", dpi=150)
svg = directory / "engine-control.svg"
fig.savefig(svg, metadata={"Date": None})
svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
plt.close(fig)
