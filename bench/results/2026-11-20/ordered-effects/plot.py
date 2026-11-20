"""Plot whole-check instruction savings and elapsed self-build time."""
import gzip
import json
from pathlib import Path
from statistics import median

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import PercentFormatter

directory = Path(__file__).resolve().parent


def save_chart(figure, name, png=False):
    for ax in figure.axes:
        ax.spines[:].set_visible(False)
        ax.tick_params(length=0, pad=4)
        ax.set_axisbelow(True)
        ax.grid(axis="y", color="#dce2e7", linewidth=.8)
    if png:
        figure.savefig(directory / f"{name}.png", dpi=150)
    path = directory / f"{name}.svg"
    figure.savefig(path, metadata={"Date": None})
    path.write_text("\n".join(line.rstrip() for line in path.read_text().splitlines()) + "\n")
    plt.close(figure)


with gzip.open(directory / "effect-checks.json.gz", "rt") as stream:
    cases = json.load(stream)["cases"]
rebuild = json.loads((directory / "rebuilds.json").read_text())["current"]
plt.rcParams.update({"svg.hashsalt": "ordered-lifetime-effects", "svg.fonttype": "none", "font.size": 10})
fig, (checks, own) = plt.subplots(1, 2, figsize=(9.6, 3.8), width_ratios=[1.45, 1], layout="constrained")
fig.suptitle("Checking repeated edits and rebuilding the compiler", x=.015, ha="left", fontsize=15, weight="bold")
shapes = ["distinct", "stores", "mixed"]
for width, offset, color in [(512, -.18, "#496b95"), (1024, .18, "#137c74")]:
    values = []
    for shape in shapes:
        samples = next(c["samples"] for c in cases if c["width"] == width and c["shape"] == shape)
        before, after = [median(r["counters"]["instructions"]["value"] for r in samples if r["compiler"] == key)
                         for key in ("before", "after")]
        values.append(100 * (1 - after / before))
    bars = checks.bar([i + offset for i in range(3)], values, .34, label=f"{width:,} targets", color=color)
    checks.bar_label(bars, labels=[f"{v:.1f}%" for v in values], padding=3, fontsize=9)
checks.set_xticks(range(3), labels=["Clear arrays", "Store slices", "One clear,\nrest grow"])
checks.set_ylim(0, 109)
checks.set_yticks([0, 25, 50, 75, 100])
checks.yaxis.set_major_formatter(PercentFormatter(xmax=100))
checks.set_title("Fewer instructions per full check", fontsize=12, loc="left")
checks.legend(loc="upper right", frameon=False, ncols=1, fontsize=9)
times = [rebuild["medians"][k]["wall_seconds"] for k in ("native", "wasm")]
ratio = rebuild["paired"]["wasm / native"]["wall_seconds"]["median"]
bars = own.bar(["Native Goose", "Cached Wasmtime"], times, width=.56, color=["#445665", "#137c74"])
own.bar_label(bars, labels=[f"{v:.2f} s" for v in times], padding=4, weight="bold")
own.set_ylim(0, max(times) * 1.25)
own.set_title("Current compiler on its own source", fontsize=12, loc="left")
own.set_ylabel("Elapsed seconds")
own.set_xlabel(f'{rebuild["rounds"]} paired rebuilds · Wasmtime/native {ratio:.2f}×')
save_chart(fig, "ordered-effects", png=True)

profiles = json.loads((directory / "modules.json").read_text())["profiles"]
with gzip.open(directory / "profiles.json.gz", "rt") as stream:
    rebuilds = json.load(stream)["medians"]
names = ["fixed", "balanced", "size"]
labels = ["Direct", "Balanced", "Size"]
fig, (download, speed) = plt.subplots(1, 2, figsize=(9.6, 3.6), layout="constrained")
fig.suptitle("Compiler size and cached rebuild time", x=.015, ha="left", fontsize=15, weight="bold")
for key, label, offset, color in [("bytes", "Wasm module", -.18, "#496b95"),
                                  ("gzip_bytes", "Gzip download", .18, "#137c74")]:
    values = [profiles[name][key] / 1e6 for name in names]
    bars = download.bar([i + offset for i in range(3)], values, .34, label=label, color=color)
    download.bar_label(bars, labels=[f"{v:.2f}" for v in values], padding=3, fontsize=9)
download.set_xticks(range(3), labels=labels)
download.set_ylim(0, 7.3)
download.set_ylabel("Megabytes")
download.set_title("Module and download size", fontsize=12, loc="left")
download.legend(frameon=False, loc="upper right", fontsize=9)
times = [rebuilds[key]["wall_seconds"] for key in ["native", *names]]
bars = speed.bar(["Native", *labels], times, width=.65, color=["#445665", "#496b95", "#137c74", "#538786"])
speed.bar_label(bars, labels=[f"{v:.2f} s" for v in times], padding=3, fontsize=9, weight="bold")
speed.set_title("Rebuilding one frozen project", fontsize=12, loc="left")
speed.set_ylabel("Elapsed seconds")
speed.set_ylim(0, max(times) * 1.22)
speed.set_xlabel("Seven runs per release · primed Wasmtime cache")
save_chart(fig, "downloads")
