"""Plot Batch 12 native C codegen improvements vs Batch 11 and upstream C++ Goose."""
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

directory = Path(__file__).resolve().parent
data = json.loads((directory / "results.json").read_text())

plt.rcParams.update({"font.size": 10, "svg.fonttype": "none", "svg.hashsalt": "native-c-codegen-gap"})

# 1. Self-compilation (selfhost/main.goose -> Wasm -O2) wall time & instructions
sw = data["selfhost_wasm"]["medians"]
fig, (ax_w, ax_i) = plt.subplots(1, 2, figsize=(10.2, 4.0), layout="constrained")
fig.suptitle("Native C codegen closes 86–93% of the self-compile gap to upstream C++ Goose",
             x=.015, ha="left", fontsize=11.5, weight="bold")

groups = ["Clang -O2", "GCC -O2"]
b11_w = [sw["b11-clang"]["wall_seconds"], sw["b11-gcc"]["wall_seconds"]]
b12_w = [sw["b12-clang"]["wall_seconds"], sw["b12-gcc"]["wall_seconds"]]
up_w = [sw["upstream-clang"]["wall_seconds"], sw["upstream-gcc"]["wall_seconds"]]

x = [0, 1]
w = 0.25
for offset, vals, label, color in [
    (-w, b11_w, "Before (Batch 11)", "#496b95"),
    (0.0, b12_w, "After (Batch 12)", "#137c74"),
    (w, up_w, "Upstream C++ C ref", "#8e6c88"),
]:
    bars = ax_w.bar([i + offset for i in x], vals, w - 0.02, label=label, color=color)
    ax_w.bar_label(bars, labels=[f"{v:.3f}" for v in vals], padding=3, fontsize=9)
ax_w.set_title("selfhost/main.goose → Wasm (-O2)", fontsize=11.5, loc="left")
ax_w.set_ylabel("Elapsed seconds")
ax_w.set_ylim(0, max(b11_w) * 1.28)
ax_w.legend(frameon=False, fontsize=8.5)

b11_i = [sw["b11-clang"]["instructions"] / 1e9, sw["b11-gcc"]["instructions"] / 1e9]
b12_i = [sw["b12-clang"]["instructions"] / 1e9, sw["b12-gcc"]["instructions"] / 1e9]
up_i = [sw["upstream-clang"]["instructions"] / 1e9, sw["upstream-gcc"]["instructions"] / 1e9]
for offset, vals, label, color in [
    (-w, b11_i, "Before (Batch 11)", "#496b95"),
    (0.0, b12_i, "After (Batch 12)", "#137c74"),
    (w, up_i, "Upstream C++ C ref", "#8e6c88"),
]:
    bars = ax_i.bar([i + offset for i in x], vals, w - 0.02, label=label, color=color)
    ax_i.bar_label(bars, labels=[f"{v:.2f}" for v in vals], padding=3, fontsize=9)
ax_i.set_title("Retired instructions", fontsize=11.5, loc="left")
ax_i.set_ylabel("Billions")
ax_i.set_ylim(0, max(b11_i) * 1.28)
ax_i.legend(frameon=False, fontsize=8.5)

for ax in (ax_w, ax_i):
    ax.set_xticks(x, labels=groups)
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=4)
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#dce2e7", linewidth=.8)

fig.savefig(directory / "native_selfcompile.png", dpi=150)
p1 = directory / "native_selfcompile.svg"
fig.savefig(p1, metadata={"Date": None})
p1.write_text("\n".join(line.rstrip() for line in p1.read_text().splitlines()) + "\n")
plt.close(fig)

# 2. Emitted C size & C compile time + runtime kernels
fig2, (ax_c, ax_k) = plt.subplots(1, 2, figsize=(10.2, 3.8), layout="constrained")
fig2.suptitle("Emitted C shrinks 45.9% (38.8 → 21.0 MB) and native kernels speed up across Clang & GCC",
              x=.015, ha="left", fontsize=11.5, weight="bold")

ec = data["build_meta"]["emitted_c"]
c_labels = ["Before\n(Batch 11)", "After\n(Batch 12)", "Upstream\nC++ ref"]
c_mb = [ec["b11"]["bytes"] / 1e6, ec["b12"]["bytes"] / 1e6, ec["upstream"]["bytes"] / 1e6]
c_colors = ["#496b95", "#137c74", "#8e6c88"]
bars = ax_c.bar(range(3), c_mb, 0.52, color=c_colors)
ax_c.bar_label(bars, labels=[f"{v:.1f} MB" for v in c_mb], padding=3, fontsize=9)
ax_c.set_xticks(range(3), labels=c_labels)
ax_c.set_title("Emitted C for selfhost/main.goose", fontsize=11.5, loc="left")
ax_c.set_ylabel("Megabytes")
ax_c.set_ylim(0, max(c_mb) * 1.25)

ks = data["kernels"]
knames = ["sorting", "owner_kernel", "sroa_kernel"]
klabels = ["sorting", "owner_kernel", "sroa_kernel"]
b11_kc = [ks[k]["medians"]["b11-clang"]["wall_seconds"] * 1e3 for k in knames]
b12_kc = [ks[k]["medians"]["b12-clang"]["wall_seconds"] * 1e3 for k in knames]
b11_kg = [ks[k]["medians"]["b11-gcc"]["wall_seconds"] * 1e3 for k in knames]
b12_kg = [ks[k]["medians"]["b12-gcc"]["wall_seconds"] * 1e3 for k in knames]

kx = [0, 1, 2]
kw = 0.2
for offset, vals, label, color in [
    (-1.5 * kw, b11_kc, "B11 Clang", "#496b95"),
    (-0.5 * kw, b12_kc, "B12 Clang", "#137c74"),
    (0.5 * kw, b11_kg, "B11 GCC", "#8b9db5"),
    (1.5 * kw, b12_kg, "B12 GCC", "#4ca69e"),
]:
    bars = ax_k.bar([i + offset for i in kx], vals, kw - 0.015, label=label, color=color)
    ax_k.bar_label(bars, labels=[f"{v:.0f}" for v in vals], padding=2, fontsize=8)
ax_k.set_xticks(kx, labels=klabels)
ax_k.set_title("Native kernel runtime (ms)", fontsize=11.5, loc="left")
ax_k.set_ylabel("Milliseconds")
ax_k.set_ylim(0, max(b11_kc + b11_kg) * 1.28)
ax_k.legend(frameon=False, fontsize=8, ncol=2)

for ax in (ax_c, ax_k):
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=4)
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#dce2e7", linewidth=.8)

fig2.savefig(directory / "native_c_and_kernels.png", dpi=150)
p2 = directory / "native_c_and_kernels.svg"
fig2.savefig(p2, metadata={"Date": None})
p2.write_text("\n".join(line.rstrip() for line in p2.read_text().splitlines()) + "\n")
plt.close(fig2)
