"""Plot elapsed CPU time relative to the paired native compiler."""
import json
from pathlib import Path
from statistics import median

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

folder = Path(__file__).resolve().parents[1]
report = json.loads((folder / "adjacent.json").read_text())
rows = report["samples"]

def seconds(label, mode):
    selected = [row for row in rows if row["label"] == label and row["mode"] == mode]
    assert sorted(row["round"] for row in selected) == [1, 2, 3, 4]
    if mode == "emit":
        assert all(row["emitted"] == report["expected"][label] for row in selected)
    return median(row["cpu_ns"] for row in selected) / 1e9

variants = [
    ("Default Wasmtime", "wasm-before", "wasm-after"),
    ("Bundled host · 32-bit¹", "bundled32-before", "bundled32"),
]
plt.rcParams.update({"svg.hashsalt": "compiler-replay-and-captures", "svg.fonttype": "none"})
fig, axes = plt.subplots(1, 2, figsize=(10.2, 4.8), sharey=True)
fig.subplots_adjust(left=.065, right=.98, bottom=.24, top=.74, wspace=.13)
handles = []
for ax, (mode, title) in zip(axes, [("check", "Check the compiler"), ("emit", "Emit the compiler as Wasm")]):
    ax.set_title(title, loc="left", fontsize=13, pad=12)
    for index, (_, old, new) in enumerate(variants):
        for offset, label, native, color, legend in [
            (-.19, old, "native-before", "#a3adb8", "Before"),
            (.19, new, "native-after", "#16696b", "After"),
        ]:
            value = seconds(label, mode) / seconds(native, mode)
            x = index + offset
            bars = ax.bar(x, value, .34, color=color, zorder=2)
            if ax is axes[0] and index == 0:
                handles.append((bars[0], legend))
            ax.text(x, value + .05, f"{value:.2f}×\n{seconds(label, mode):.2f} s", ha="center", va="bottom", fontsize=9)
    ax.axhline(1, color="#384451", lw=1, ls="--", zorder=3)
    ax.set_xticks([0, 1], ["Default memory64", "Bundled host · 32-bit¹"])
    ax.set_ylim(0, max(3.7, max(b.get_height() for b in ax.patches) + .35))
    ax.set_yticks([0, 1, 2, 3], ["0", "1×", "2×", "3×"])
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=4)
fig.text(.065, .915, "Wasmtime time relative to native on the frozen compiler project", size=17, weight="bold")
fig.text(.065, .84, "Four back-to-back comparisons per pair · lower is faster · dashed line is native", size=11)
fig.legend(*zip(*handles), loc="lower right", bbox_to_anchor=(.99,.815), frameon=False, ncols=2)
fig.text(.065, .055, "¹ The 32-bit layout is sized for this project. Each ratio uses the matching version of the native compiler.", size=9)
fig.savefig(folder / "comparison.png", dpi=150)
svg = folder / "comparison.svg"
fig.savefig(svg, metadata={"Date": None})
svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
