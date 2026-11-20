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
for ax in (checks, own):
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=4)
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#dce2e7", linewidth=.8)
fig.savefig(directory / "ordered-effects.png", dpi=150)
path = directory / "ordered-effects.svg"
fig.savefig(path, metadata={"Date": None})
path.write_text("\n".join(line.rstrip() for line in path.read_text().splitlines()) + "\n")
