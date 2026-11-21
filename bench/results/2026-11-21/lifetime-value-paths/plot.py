"""Render the paired compiler rebuild results."""
import gzip
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

directory = Path(__file__).resolve().parent
summary = json.loads((directory / "rebuilds.json").read_text())
frozen = summary["frozen"]
current = summary["current"]
plt.rcParams.update({"font.size": 10, "svg.fonttype": "none", "svg.hashsalt": "lifetime-value-paths"})
fig, (change, own) = plt.subplots(1, 2, figsize=(9.5, 3.7), layout="constrained", width_ratios=[1.2, 1])
fig.suptitle("Lifetime checking and compiler rebuilds", x=.02, ha="left", fontsize=15, weight="bold")

for y, engine, color in [(1, "wasm", "#137c74"), (0, "native", "#496b95")]:
    for offset, metric, marker in [(.11, "wall_seconds", "o"), (-.11, "instructions", "s")]:
        result = frozen["paired"][f"{engine}-after / {engine}-before"][metric]
        value, (low, high) = result["median"], result["interval95"]
        change.errorbar(100 * (value - 1), y + offset,
                        xerr=[[100 * (value - low)], [100 * (high - value)]], fmt=marker,
                        color=color, capsize=3, label={"wall_seconds": "Elapsed time", "instructions": "Instructions"}[metric] if y == 1 else None)
change.axvline(0, color="#556879", linewidth=.8)
change.set_ylim(-.6, 1.6)
change.set_yticks([0, 1], labels=["Native", "Cached Wasmtime"])
change.set_title("Change on identical source", loc="left", fontsize=12)
change.set_xlabel(f'Percent change · {frozen["rounds"]} paired rebuilds')
change.legend(frameon=False, loc="lower right", fontsize=9)

times = [current["medians"][k]["wall_seconds"] for k in ("native", "wasm")]
ratio = current["paired"]["wasm / native"]["wall_seconds"]["median"]
bars = own.bar(["Native", "Cached Wasmtime"], times, width=.6, color=["#496b95", "#137c74"])
own.bar_label(bars, labels=[f"{v:.2f} s" for v in times], padding=4, weight="bold")
own.set_ylim(0, max(times) * 1.25)
own.set_ylabel("Elapsed seconds")
own.set_title("Current compiler on its own source", loc="left", fontsize=12)
own.set_xlabel(f'{current["rounds"]} paired rebuilds · Wasmtime/native {ratio:.2f}×')
for ax, grid in [(change, "x"), (own, "y")]:
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=4)
    ax.set_axisbelow(True)
    ax.grid(axis=grid, color="#dce2e7", linewidth=.8)
fig.savefig(directory / "rebuild.png", dpi=150)
path = directory / "rebuild.svg"
fig.savefig(path, metadata={"Date": None})
path.write_text("\n".join(line.rstrip() for line in path.read_text().splitlines()) + "\n")

plt.close(fig)
modules = json.loads((directory / "modules.json").read_text())["profiles"]
with gzip.open(directory / "profiles.json.gz", "rt") as stream:
    profiles = json.load(stream)["medians"]
formats = ["fixed", "balanced", "size"]
labels = ["Direct", "Balanced", "Size"]
fig, (download, speed) = plt.subplots(1, 2, figsize=(9.5, 3.7), layout="constrained")
fig.suptitle("Compiler size and cached rebuild time", x=.02, ha="left", fontsize=15, weight="bold")
for key, label, offset, color in [("bytes", "Wasm module", -.18, "#496b95"),
                                  ("gzip_bytes", "Gzip download", .18, "#137c74")]:
    values = [modules[name][key] / 1e6 for name in formats]
    bars = download.bar([i + offset for i in range(3)], values, .34, label=label, color=color)
    download.bar_label(bars, labels=[f"{v:.2f}" for v in values], padding=3, fontsize=9)
download.set_xticks(range(3), labels=labels)
download.set_ylim(0, 7.3)
download.set_ylabel("Megabytes")
download.set_title("Module and download size", fontsize=12, loc="left")
download.legend(frameon=False, loc="upper right", fontsize=9)
times = [profiles[key]["wall_seconds"] for key in ["native", *formats]]
bars = speed.bar(["Native", *labels], times, width=.65, color=["#445665", "#496b95", "#137c74", "#538786"])
speed.bar_label(bars, labels=[f"{v:.2f} s" for v in times], padding=3, fontsize=9, weight="bold")
speed.set_title("Rebuilding one frozen project", fontsize=12, loc="left")
speed.set_ylabel("Elapsed seconds")
speed.set_ylim(0, max(times) * 1.22)
speed.set_xlabel("Seven runs per compiler · primed Wasmtime cache")
for ax in (download, speed):
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=4)
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#dce2e7", linewidth=.8)
path = directory / "downloads.svg"
fig.savefig(path, metadata={"Date": None})
path.write_text("\n".join(line.rstrip() for line in path.read_text().splitlines()) + "\n")
