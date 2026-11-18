"""Summarize sampled CPU and reproduce the read-miss chart from the raw evidence."""
import argparse
import json
from pathlib import Path
from statistics import mean, median

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("folder", nargs="?", type=Path, default=Path(__file__).resolve().parents[1])
folder = parser.parse_args().folder
phase_groups = {
    "Construct, dispatch and stamp": [1],
    "Compute propagation reach": [2],
    "Check or record prior offer": [3],
    "Walk caller chain": [4],
    "Merge into offering frame": [5, 6, 7, 8],
    "Merge into caller frames": [9, 10, 11, 12],
}
labels = ["released", "grouped"]
reports = {}
for kind in ("phases", "outer"):
    rows = json.loads((folder / f"{kind}.json").read_text())["runs"]
    assert all(len(row["samples"]) == 16 and sum(row["samples"]) > 0 for row in rows)
    reports[kind] = {}
    for label in labels:
        runs = [r for r in rows if r["label"] == label]
        assert sorted(r["round"] for r in runs) == list(range(1, len(runs) + 1))
        # Weight samples by CPU time per tick in their own run. Timer periods vary.
        estimates = []
        shares = []
        for row in runs:
            bins = row["samples"]
            assert not any(bins[13:]) and not (kind == "outer" and any(bins[2:]))
            ms_per_sample = row["lifetime_cpu_ns"] / 1e6 / sum(bins)
            estimates.append([count * ms_per_sample for count in bins])
            shares.append(100 * sum(estimates[-1][1:]) / (row["invocation_cpu_ns"] / 1e6))
        by_bin = [mean(bin_ms) for bin_ms in zip(*estimates)]
        total = sum(by_bin[1:])
        scope_ms = [sum(sample[1:]) for sample in estimates]
        result = {
            "rounds": len(runs),
            "mean_scoped_cpu_ms": total,
            "scoped_cpu_ms_range": [min(scope_ms), max(scope_ms)],
            "mean_share_of_invocation_cpu_percent": mean(shares),
            "median_invocation_cpu_ms": median(r["invocation_cpu_ns"] for r in runs) / 1e6,
            "samples_in_scope": sum(sum(r["samples"][1:]) for r in runs),
            "timer_overruns": sum(r["overruns"] for r in runs),
        }
        if kind == "phases":
            result["phase_ms"] = by_bin[1:13]
            result["category_ms"] = {name: sum(by_bin[i] for i in indexes) for name, indexes in phase_groups.items()}
            result["category_percent"] = {name: 100 * ms / total for name, ms in result["category_ms"].items()}
        reports[kind][label] = result

(folder / "summary.json").write_text(json.dumps(reports, indent=2) + "\n")
plt.rcParams.update({"svg.hashsalt": "lifetime-read-misses", "svg.fonttype": "none"})
fig, ax = plt.subplots(figsize=(9, 4.3))
fig.subplots_adjust(left=.32, right=.92, top=.73, bottom=.15)
grouped = reports["phases"]["grouped"]["category_percent"]
names = sorted(grouped, key=grouped.get, reverse=True)
for i, name in enumerate(names):
    color = "#a95434" if name == "Merge into caller frames" else "#176c70"
    value = grouped[name]
    ax.barh(i, value, height=.60, color=color)
    ax.text(value + .4, i, f"{value:.1f}%", va="center", fontsize=11)
ax.set_yticks(range(len(names)), names, fontsize=11)
ax.invert_yaxis()
ax.set_xlim(0, max(grouped.values()) * 1.16)
ax.set_xticks([])
ax.tick_params(axis="y", length=0)
ax.spines[:].set_visible(False)
fig.text(.04, .91, "Where Wasmtime spends CPU on the 1.65M fallback reads", fontsize=16, weight="bold")
fig.text(.04, .83, "Share of CPU sampled inside individual reads after an eight-read cache miss", fontsize=11)
outer = reports["outer"]["grouped"]
fig.text(.04, .055, f"Measured at entry and return, these reads took {outer['mean_share_of_invocation_cpu_percent']:.1f}% of the full compiler self-check.", fontsize=10)
fig.savefig(folder / "profile.png", dpi=150)
path = folder / "profile.svg"
fig.savefig(path, metadata={"Date": None})
path.write_text("\n".join(line.rstrip() for line in path.read_text().splitlines()) + "\n")
