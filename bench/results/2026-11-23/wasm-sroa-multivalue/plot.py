"""Plot Batch 11 compiler sizes, frozen rebuild times, and small-struct SROA/multi-value kernel speedup."""
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

directory = Path(__file__).resolve().parent
profiles = json.loads((directory / "profiles.json").read_text())
rebuilds = json.loads((directory / "rebuilds.json").read_text())

plt.rcParams.update({"font.size": 10, "svg.fonttype": "none", "svg.hashsalt": "wasm-sroa-multivalue"})

# 1. Release sizes and rebuild times
fig, (size, time) = plt.subplots(1, 2, figsize=(9.5, 3.8), layout="constrained")
fig.suptitle("Small-struct SROA & multi-value returns cut balanced cached rebuilds 2.2% (size 0.726 s)",
             x=.015, ha="left", fontsize=11.5, weight="bold")
keys = ["previous", "balanced", "size"]
labels = ["Previous\nbalanced", "SROA &\nmulti-value", "Size\nprofile"]

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
time.set_title("Rebuilding frozen 9a6040a", fontsize=12, loc="left")
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
plt.close(fig)

# 2. Small-struct SROA & multi-value kernel runtime & instructions before vs after
sk = rebuilds["sroa_kernel"]["medians"]
fig2, (ax_w, ax_i) = plt.subplots(1, 2, figsize=(9.5, 3.6), layout="constrained")
fig2.suptitle("Small-struct SROA & multi-value returns: 2.46× faster Wasmtime (1.08× of native Clang)",
              x=.015, ha="left", fontsize=11.5, weight="bold")
targets = ["Wasmtime\n(cached)", "Native\n(Clang -O2)"]
before_w = [sk["wasm-before"]["wall_seconds"] * 1e3, sk["native-before"]["wall_seconds"] * 1e3]
after_w = [sk["wasm-after"]["wall_seconds"] * 1e3, sk["native-after"]["wall_seconds"] * 1e3]
b1 = ax_w.bar([-0.18, 0.82], before_w, 0.34, label="Before (4da2994)", color="#496b95")
b2 = ax_w.bar([0.18, 1.18], after_w, 0.34, label="After (Batch 11)", color="#137c74")
ax_w.bar_label(b1, labels=[f"{v:.1f}" for v in before_w], padding=3)
ax_w.bar_label(b2, labels=[f"{v:.1f}" for v in after_w], padding=3)
ax_w.set_title("Elapsed runtime", fontsize=12, loc="left")
ax_w.set_ylabel("Milliseconds")
ax_w.set_ylim(0, max(before_w) * 1.28)
ax_w.legend(frameon=False, fontsize=9)

before_i = [sk["wasm-before"]["instructions"] / 1e9, sk["native-before"]["instructions"] / 1e9]
after_i = [sk["wasm-after"]["instructions"] / 1e9, sk["native-after"]["instructions"] / 1e9]
b3 = ax_i.bar([-0.18, 0.82], before_i, 0.34, label="Before (4da2994)", color="#496b95")
b4 = ax_i.bar([0.18, 1.18], after_i, 0.34, label="After (Batch 11)", color="#137c74")
ax_i.bar_label(b3, labels=[f"{v:.2f}" for v in before_i], padding=3)
ax_i.bar_label(b4, labels=[f"{v:.2f}" for v in after_i], padding=3)
ax_i.set_title("Retired instructions", fontsize=12, loc="left")
ax_i.set_ylabel("Billions")
ax_i.set_ylim(0, max(before_i) * 1.28)
ax_i.legend(frameon=False, fontsize=9)

for ax in (ax_w, ax_i):
    ax.set_xticks([0, 1], labels=targets)
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=4)
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#dce2e7", linewidth=.8)

fig2.savefig(directory / "sroa_kernel.png", dpi=150)
spath = directory / "sroa_kernel.svg"
fig2.savefig(spath, metadata={"Date": None})
spath.write_text("\n".join(line.rstrip() for line in spath.read_text().splitlines()) + "\n")
