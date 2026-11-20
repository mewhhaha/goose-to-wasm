"""Render the CPU 5 fresh-copy catalog measurements."""
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

plt.rcParams["svg.hashsalt"] = "small-build-frontend"

directory = Path(__file__).resolve().parent
study = json.loads((directory / "small-summary.json").read_text())
primary = study["cpus"]["5"]

def saved(run, name, metric):
    return 100 * (1 - run[name]["instructions"][metric])

workloads = primary["workloads"]
names = sorted((key.split("/")[0] for key in workloads if key.endswith("/check")),
               key=lambda name: -saved(workloads, name + "/check", "ratio"))
series = [("check", "Check only", "#243b50"), ("wasm-direct", "Emit Wasm", "#008478"),
          ("native-c", "Emit C", "#bc7243")]
fig, (left, right) = plt.subplots(1, 2, figsize=(10.7, 4.25), width_ratios=[3, 1],
                                  layout="constrained")
fig.suptitle("Compiler instructions saved on small programs", fontsize=17, weight="bold")
left.set_title("11 programs · 30 pairs on CPU 5", loc="left", fontsize=11)
right.set_title("Catalog average", loc="left", fontsize=11)
for i, (target, label, color) in enumerate(series):
    values = [saved(workloads, name + "/" + target, "ratio") for name in names]
    left.bar([n + (i - 1) * .26 for n in range(len(names))], values, width=.25,
             color=color, label=label)
    value = saved(primary["summary"], target, "ratio")
    right.bar(i, value, color=color, width=.7)
    right.text(i, value + .15, f"{value:.2f}%", ha="center", fontsize=10)
left.set_xticks(range(len(names)), names, rotation=42, ha="right")
right.set_xticks(range(3), ["Check", "Wasm", "C"])
left.set_ylabel("Fewer instructions (%)")
right.set_ylim(0, 5.1)
for ax in (left, right):
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#dce2e7", linewidth=.8)
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=5)
left.legend(frameon=False, loc="upper right")
fig.savefig(directory / "small-builds.png", dpi=165)
svg = directory / "small-builds.svg"
fig.savefig(svg, metadata={"Date": None})
svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
