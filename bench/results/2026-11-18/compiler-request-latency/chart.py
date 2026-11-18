"""Plot end-to-end wall time from the three measured self-emission rounds."""

import json
from pathlib import Path
from statistics import median

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

folder = Path(__file__).resolve().parent
rows = json.loads((folder / "self-emit.json").read_bytes())["samples"]
cases = [
    ("New Wasmtime process", "wasmtime", "cold", "#2b5169"),
    ("Resident Wasmtime", "wasmtime", "hot", "#00796b"),
    ("Resident after edit", "wasmtime", "edited", "#00796b"),
    ("Native compiler process", "native", "fresh", "#64748b"),
]
plt.rcParams.update(
    {
        "svg.fonttype": "none",
        "svg.hashsalt": "compiler-request-latency",
        "font.size": 11,
    }
)
fig, ax = plt.subplots(figsize=(8.2, 3.1))
fig.subplots_adjust(left=0.28, right=0.89, bottom=0.17, top=0.70)
fig.text(
    0.045, 0.91, "Our Goose compiler rebuilding itself", fontsize=16, weight="bold"
)
fig.text(
    0.045,
    0.80,
    "Seconds to emit complete Wasm · median of three rounds · warm filesystem",
)
for i, (name, host, mode, color) in enumerate(cases):
    samples = [r["ns"] for r in rows if r["host"] == host and r["mode"] == mode]
    assert len(samples) == 3
    bars = ax.barh(i, median(samples) / 1e9, color=color, height=0.62)
    ax.bar_label(bars, fmt="%.2f s", padding=5)
ax.set_yticks(range(len(cases)), [c[0] for c in cases])
ax.invert_yaxis()
ax.spines[:].set_visible(False)
ax.tick_params(length=0)
ax.set_axisbelow(True)
ax.grid(axis="x", color="#dce2e7", linewidth=0.7)
fig.savefig(folder / "latency.png", dpi=150)
svg = folder / "latency.svg"
fig.savefig(svg, metadata={"Date": None})
svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
