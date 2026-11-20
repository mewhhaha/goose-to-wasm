"""Render Wasmtime measurements for the branch-folding experiment."""
import gzip
import json
from pathlib import Path
from statistics import median

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

directory = Path(__file__).resolve().parent
report = json.loads(gzip.decompress((directory / "size-trials.json.gz").read_bytes()))
cold = report["cold"]["rows"]
cached = report["cached"]["branches"]["samples"]
sizes = [report["wasm"][k]["identity"]["bytes"] / 1e6 for k in ("rewrite", "code-fold")]
prepare = [median(r["engine"]["compile_instantiate_ns"] for r in cold if r["name"] == k) / 1e9
           for k in ("rewrite", "branch-fold")]
rebuild = [median(r["wall_ns"] for r in cached if r["case"] == k) / 1e9
           for k in ("rewrite", "branch-fold")]
plt.rcParams["svg.hashsalt"] = "compiler-size-branch-endings"
fig, axes = plt.subplots(1, 3, figsize=(9.3, 3.35), layout="constrained")
fig.suptitle("Sharing error paths shrinks the compiler and speeds up cold preparation",
             fontsize=13, weight="bold")
for ax, values, heading, unit in zip(axes, (sizes, prepare, rebuild),
                                    ("Wasm module", "Cold preparation", "Cached rebuild"), ("MB", "s", "s")):
    bars = ax.bar([0, 1], values, color=["#344b61", "#008478"], width=.63)
    ax.bar_label(bars, labels=[f"{v:.2f} {unit}" for v in values], padding=4, fontsize=11)
    ax.set_title(heading, fontsize=11)
    ax.set_xticks([0, 1], ["Control", "Folded"])
    ax.set_ylim(0, max(values) * 1.23)
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#dce2e7", linewidth=.8)
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=4)
fig.savefig(directory / "compiler-size.png", dpi=155)
svg = directory / "compiler-size.svg"
fig.savefig(svg, metadata={"Date": None})
svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
