"""Regenerate the optimizer work figure from the archived hardware and call counts."""
import gzip
import json
from pathlib import Path
from statistics import median

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

here = Path(__file__).resolve().parent
reports = json.loads(gzip.decompress((here / "frozen-phases.json.gz").read_bytes()))["reports"]
fixtures = json.loads((here / "cost-scaling.json").read_bytes())["fixtures"]
plt.rcParams.update({"font.size": 10, "svg.hashsalt": "optimizer-node", "svg.fonttype": "none"})
fig, (phases, visits) = plt.subplots(1, 2, figsize=(9.6, 3.8), layout="constrained")
fig.suptitle("Work done by the Goose optimizer", fontsize=16, weight="bold")
phases.set_title("Frozen compiler build", loc="left")
phases.set_ylabel("Billions of retired instructions")
visits.set_title("Inlining cost for one function", loc="left")
visits.set_xlabel("Assignments in the function")
visits.set_ylabel("Calls to count the cost")

for version, report, label, offset, color in [
    ("baseline", "phase-previous", "Previous", -0.19, "#526778"),
    ("candidate", "phase-native-after", "Current", 0.19, "#087d73"),
]:
    counts = []
    for engine in ["native", "wasm"]:
        sample = [r["phases"]["optimize"]["instructions"]
                  for r in reports[report]["samples"] if r["engine"] == engine]
        counts.append(median(sample) / 1e9)
    bars = phases.bar([i + offset for i in range(2)], counts, 0.36, color=color, label=label)
    phases.bar_label(bars, fmt="%.2f", padding=3)
    calls = [f[version]["visits"] for f in fixtures]
    bars = visits.bar([i + offset for i in range(len(calls))], calls, 0.36, color=color)
    visits.bar_label(bars, labels=[f"{v:,}" for v in calls], padding=3, fontsize=9)

phases.set_xticks([0, 1], ["Native", "Cached Wasmtime"])
visits.set_xticks(range(len(fixtures)), [f"{row['flat_assignment_statements']:,}" for row in fixtures])
for ax in [phases, visits]:
    ax.margins(y=0.22)
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#dce2e7", linewidth=0.8)
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=5)
phases.legend(loc="upper left", frameon=False)
fig.savefig(here / "optimizer-work.png", dpi=150)
svg = here / "optimizer-work.svg"
fig.savefig(svg, metadata={"Date": None})
svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
