"""Plot Batch 6 compiler sizes and frozen rebuild times."""
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

directory = Path(__file__).resolve().parent
profiles = json.loads((directory / "profiles.json").read_text())
plt.rcParams.update({"font.size": 10, "svg.fonttype": "none", "svg.hashsalt": "lifetime-compaction-and-codegen-fastpaths"})
fig, (size, time) = plt.subplots(1, 2, figsize=(9.5, 3.8), layout="constrained")
fig.suptitle("Lifetime compaction, inline scopes and Wasm fast paths halve baseline instructions",
             x=.015, ha="left", fontsize=12.5, weight="bold")
keys = ["previous", "balanced", "size"]
labels = ["Previous\nbalanced", "Compaction & fast paths\nbalanced", "Compaction & fast paths\nsize profile"]

for field, label, offset, color in [("bytes", "Wasm module", -.18, "#496b95"),
                                    ("gzip_bytes", "Gzip download", .18, "#137c74")]:
    values = [profiles[k][field] / 1e6 for k in keys]
    bars = size.bar([i + offset for i in range(3)], values, .34, label=label, color=color)
    size.bar_label(bars, labels=[f"{v:.2f}" for v in values], padding=3)
size.set_title("Compiler package size", fontsize=12, loc="left")
size.set_ylabel("Megabytes")
size.set_ylim(0, 3.8)
size.legend(frameon=False, fontsize=9)

for field, label, offset, color in [("cold", "Cold", -.18, "#496b95"),
                                    ("cached", "Cached", .18, "#137c74")]:
    values = [profiles[k][field]["wall_seconds"] for k in keys]
    bars = time.bar([i + offset for i in range(3)], values, .34, label=label, color=color)
    time.bar_label(bars, labels=[f"{v:.2f}" for v in values], padding=3)
time.set_title("Rebuilding the same frozen project", fontsize=12, loc="left")
time.set_ylabel("Elapsed seconds")
time.set_ylim(0, max(v["cold"]["wall_seconds"] for v in profiles.values()) * 1.3)
time.legend(frameon=False, fontsize=9)

for ax in (size, time):
    ax.set_xticks(range(3), labels=labels)
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=4)
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#dce2e7", linewidth=.8)

fig.savefig(directory / "release.png", dpi=150)
path = directory / "release.svg"
fig.savefig(path, metadata={"Date": None})
path.write_text("\n".join(line.rstrip() for line in path.read_text().splitlines()) + "\n")
