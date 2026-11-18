"""Plot the resident compiler trials with their own matched native controls."""
from hashlib import sha256
import json
from pathlib import Path
from statistics import median

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

folder = Path(__file__).resolve().parents[1]
plt.rcParams.update({"svg.fonttype": "none", "svg.hashsalt": "goose-wasm-lowering"})
fig, axes = plt.subplots(1, 2, figsize=(10, 4.6), sharey=True)
fig.subplots_adjust(left=0.08, right=0.985, bottom=0.18, top=0.78, wspace=0.06)
colors = ("#475569", "#a2aab5", "#087f8c")
files = ("lowering-samples.json", "wide-samples.json")
for axis, filename, title in zip(axes, files, ("Profiled memory32", "Default memory64")):
    report = json.loads((folder / filename).read_text())
    for group, workload in enumerate(("check", "emit")):
        native = median(row["wall_ns"] for row in report["samples"] if row["label"] == "native" and row["workload"] == workload)
        for index, (label, key) in enumerate(zip(("Native", "Previous Wasm", "Current Wasm"), ("native", "direct", "combined"))):
            rows = [row for row in report["samples"] if row["label"] == key and row["workload"] == workload]
            assert sorted(row["round"] for row in rows) == [1, 2, 3]
            if workload == "emit":
                assert all(row["emitted_sha256"] == report["expected_emission_sha256"] for row in rows)
            value = median(row["wall_ns"] for row in rows) / native
            x = group + (index - 1) * 0.245
            axis.bar(x, value, width=0.22, color=colors[index], label=label if group == 0 else None)
            axis.text(x, value + 0.055, f"{value:.2f}×", fontsize=10, ha="center", va="bottom")
    axis.axhline(1.9, color="#8a6239", linewidth=1, linestyle=(0,(4,3)), zorder=0)
    axis.set_title(title, fontsize=13)
    axis.set_xticks([0, 1], ["Check", "Emit Wasm"])
    axis.set_axisbelow(True)
    axis.grid(axis="y", alpha=0.16)
    axis.spines[["top", "left", "right"]].set_visible(False)
    axis.tick_params(length=0, pad=5)
axes[0].set_ylabel("Execution time relative to native")
axes[0].set_ylim(bottom=0, top=axes[0].get_ylim()[1] * 1.08)
fig.suptitle("Wasmtime compiler runtime", x=0.08, y=0.98, ha="left", fontsize=18, fontweight="bold")
fig.legend(*axes[0].get_legend_handles_labels(), loc="upper right", bbox_to_anchor=(0.99,0.985), ncol=3, frameon=False)
fig.text(0.08, 0.05, "Dashed line marks the 1.9× target. Ratios use three interleaved rounds on the same frozen project.", fontsize=10)
sources = ", ".join(f"{name} sha256:{sha256((folder / name).read_bytes()).hexdigest()}" for name in files)
chart = folder / "runtime.svg"
fig.savefig(folder / "runtime.png", dpi=155)
fig.savefig(chart, metadata={"Date": None, "Title": "Frozen Goose compiler workload", "Source": sources})
chart.write_text("\n".join(line.rstrip() for line in chart.read_text().splitlines()) + "\n")
