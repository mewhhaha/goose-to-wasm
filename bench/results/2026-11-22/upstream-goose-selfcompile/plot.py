"""Plot head-to-head self-compilation of selfhost/main.goose: upstream C++ Goose vs Goose-to-Wasm."""
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

directory = Path(__file__).resolve().parent
data = json.loads((directory / "results.json").read_text())
med = data["head_to_head"]["medians"]

plt.rcParams.update({
    "font.size": 10,
    "svg.fonttype": "none",
    "svg.hashsalt": "upstream-goose-selfcompile",
})

fig, ax = plt.subplots(figsize=(9.6, 4.0), layout="constrained")
fig.suptitle("Compiling the Goose compiler (selfhost/main.goose): upstream C++ vs Goose-to-Wasm",
             x=.015, ha="left", fontsize=12.5, weight="bold")
ax.set_title("Median elapsed seconds on CPU 7 · 5 alternating rounds · byte-identical Wasm output",
             loc="left", fontsize=10, color="#4a5568")

items = [
    ("Upstream C++\nemit C", med["upstream-cpp-emit-c"]["wall_seconds"], "#b07d47"),
    ("Upstream C++\ncheck only", med["upstream-cpp-check"]["wall_seconds"], "#c89b6e"),
    ("Wasmtime\nemit C", med["wasmtime-balanced-emit-c"]["wall_seconds"], "#496b95"),
    ("Selfhost native\nemit C", med["selfhost-native-emit-c"]["wall_seconds"], "#345369"),
    ("Wasmtime\nemit Wasm", med["wasmtime-balanced-emit-wasm"]["wall_seconds"], "#087d73"),
    ("Selfhost native\nemit Wasm", med["selfhost-native-emit-wasm"]["wall_seconds"], "#1f6f8b"),
    ("C++-built ours\nemit Wasm", med["cppbuilt-native-emit-wasm"]["wall_seconds"], "#2b4c7e"),
]

labels = [x[0] for x in items]
vals = [x[1] for x in items]
colors = [x[2] for x in items]

bars = ax.bar(range(len(items)), vals, color=colors, width=0.62)
ax.bar_label(bars, labels=[f"{v:.2f} s" for v in vals], padding=4, weight="bold")
ax.set_xticks(range(len(items)), labels=labels)
ax.set_ylabel("Elapsed seconds (lower is better)")
ax.set_ylim(0, max(vals) * 1.18)
ax.spines[:].set_visible(False)
ax.tick_params(length=0, pad=5)
ax.set_axisbelow(True)
ax.grid(axis="y", color="#dce2e7", linewidth=.8)

fig.savefig(directory / "upstream-selfcompile.png", dpi=150)
svg = directory / "upstream-selfcompile.svg"
fig.savefig(svg, metadata={"Date": None})
svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
