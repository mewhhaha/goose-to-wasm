"""Render paired Wasmtime work and the share of reusable eight-read groups."""
import json
from pathlib import Path
from statistics import median

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

folder = Path(__file__).resolve().parents[1]
cache = json.loads((folder / "counts.json").read_text())["variants"]
timing = json.loads((folder / "samples.json").read_text())
names = {"bounded": "4,096 slots", "retained": "All groups",
         "bounded_leaf_version": "4,096 slots", "retained_leaf_version": "All groups"}
hits, work = [], []
for key in names:
    counters = cache[key]["counters"]
    hits.append(100 * counters["hits"] / counters["lookups"])
    samples = timing[key]["samples"]
    check = [row for row in samples if row["host"] == "wasmtime" and row["mode"] == "check"]
    def instructions(label):
        return median(row["counters"]["instructions"]["value"] for row in check if row["label"] == label)
    work.append(100 * (instructions("candidate") / instructions("baseline") - 1))
plt.rcParams.update({"svg.hashsalt": "goose-lifetime-read-groups", "svg.fonttype": "none"})
fig, (left, right) = plt.subplots(1, 2, figsize=(9.6, 3.9))
fig.subplots_adjust(left=0.20, right=0.96, bottom=0.19, top=0.80, wspace=0.25)
positions = [3.7, 2.7, 1.3, 0.3]
for axis, values, title in [(left, hits, "Group hit rate"), (right, work, "Change in Wasmtime instructions")]:
    axis.set_title(title, loc="left", fontsize=12, pad=14, weight="bold")
    axis.axvline(0, color="#6b7280", linewidth=0.7)
    axis.set_ylim(-0.45, 4.45)
    lo, hi = min(0, min(values)), max(0, max(values))
    span = max(hi - lo, 0.1)
    axis.set_xlim(lo - span * 0.22, hi + span * 0.32)
    for y, val in zip(positions, values):
        color = "#126a6e"
        if axis is right and val > 0:
            color = "#ac583c"
        axis.barh(y, val, height=0.5, color=color)
        x = val + span * 0.02
        align = "left"
        if val < 0:
            x = val - span * 0.02
            align = "right"
        label = f"{val:.2f}%"
        if axis is right and val > 0:
            label = "+" + label
        axis.text(x, y, label, ha=align, va="center", fontsize=10)
    axis.set_xticks([])
    axis.tick_params(axis="y", length=0)
    axis.spines[:].set_visible(False)
left.set_yticks(positions, ["Append invalidates\n4,096 slots", "All groups", "Append preserves\n4,096 slots", "All groups"], fontsize=10)
right.set_yticks([])
fig.text(0.025, 0.945, "Eight-read groups on the frozen compiler self-check", fontsize=16, weight="bold")
fig.text(0.025, 0.065, "Each instruction change uses its own unmodified control. Lower is better.", fontsize=10)
fig.savefig(folder / "groups.png", dpi=150)
path = folder / "groups.svg"
fig.savefig(path, metadata={"Date": None})
path.write_text("\n".join(line.rstrip() for line in path.read_text().splitlines()) + "\n")

# The independent confirmation times both compilers on the same CPU.
confirmation = json.loads((folder / "confirmation.json").read_text())
memory = json.loads((folder / "memory.json").read_text())
check, emit, rss = [], [], []
for label in ("baseline", "candidate"):
    rows = [row for row in confirmation["samples"] if row["host"] == "wasmtime" and row["label"] == label]
    for mode, series in (("check", check), ("emit", emit)):
        observed = [row["wall_ns"] / 1e9 for row in rows if row["mode"] == mode]
        if len(observed) != 4:
            raise ValueError("expected four confirmation rounds")
        series.append(median(observed))
    rss.append(median(row["max_rss_kib"] / 1024 for row in memory["samples"]
                      if row["host"] == "wasmtime" and row["label"] == label))
fig, panels = plt.subplots(1, 3, figsize=(9.2, 3.3))
fig.subplots_adjust(left=0.13, right=0.97, top=0.72, bottom=0.19, wspace=0.40)
for i, (axis, values, title, unit) in enumerate(zip(panels, (check, emit, rss),
        ("Check the compiler", "Emit the compiler", "Peak memory on check"), ("s", "s", "MiB"))):
    maximum = max(values)
    axis.set_title(title, loc="left", pad=10, weight="bold", fontsize=11)
    axis.barh([1, 0], values, height=0.53, color=["#475569", "#087f8c"])
    for y, value in zip([1, 0], values):
        label = f"{value:.2f} s"
        if unit == "MiB":
            label = f"{value:.0f} MiB"
        axis.text(0.04 * maximum, y, label, va="center", color="white", fontsize=11, weight="bold")
    labels = ["Current", "Grouped"]
    if i:
        labels = ["", ""]
    axis.set_yticks([1, 0], labels, fontsize=10)
    axis.set_xlim(0, maximum * 1.04)
    axis.set_xticks([])
    axis.tick_params(axis="y", length=0)
    axis.spines[:].set_visible(False)
fig.text(0.035, 0.91, "Wasmtime on the frozen compiler project", fontsize=16, weight="bold")
fig.text(0.035, 0.055, "Median of four paired timings. Peak RSS uses two fresh processes per compiler.", fontsize=10)
fig.savefig(folder / "confirmation.png", dpi=150)
path = folder / "confirmation.svg"
fig.savefig(path, metadata={"Date": None})
path.write_text("\n".join(line.rstrip() for line in path.read_text().splitlines()) + "\n")
