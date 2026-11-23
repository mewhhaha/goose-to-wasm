"""Plot Batch 13 release sizes/rebuilds, Wasmtime vs wtime-aot vs Native self-compilation,
and runtime kernels + upstream C++ head-to-head.
"""
from __future__ import annotations

import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

DIR = Path(__file__).resolve().parent
res = json.loads((DIR / "results.json").read_text())
profiles = res["profiles"]

plt.rcParams.update({
    "font.size": 10,
    "svg.fonttype": "none",
    "svg.hashsalt": "batch13-wasm-peephole-wtime-aot",
})

NAVY = "#345369"
BLUE = "#496b95"
TEAL = "#137c74"
AMBER = "#c47d2b"
RUST = "#b8502e"
SLATE = "#6e7f8d"


def save(fig, stem: str) -> None:
    fig.savefig(DIR / f"{stem}.png", dpi=150)
    svg = DIR / f"{stem}.svg"
    fig.savefig(svg, metadata={"Date": None})
    svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
    plt.close(fig)


def style_ax(ax) -> None:
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=4)
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#dce2e7", linewidth=0.8)


# 1. release.svg: Compiler package sizes & frozen 9a6040a cold/cached rebuild times
fig, (ax_sz, ax_tm) = plt.subplots(1, 2, figsize=(10.2, 4.0), layout="constrained")
bal_mb = profiles["balanced"]["bytes"] / 1e6
sz_mb = profiles["size"]["bytes"] / 1e6
bal_cached = profiles["balanced"]["cached"]["wall_seconds"]
sz_cached = profiles["size"]["cached"]["wall_seconds"]
fig.suptitle(
    f"Batch 13 shrinks balanced Wasm to {bal_mb:.2f} MB (size {sz_mb:.2f} MB) and cached rebuilds to {sz_cached:.2f}–{bal_cached:.2f} s",
    x=0.015, ha="left", fontsize=12.0, weight="bold",
)
keys = ["previous", "direct", "balanced", "size"]
labels = ["Batch 11\nbalanced", "Batch 13\ndirect", "Batch 13\nbalanced", "Batch 13\nsize"]

for field, label, off, color in [
    ("bytes", "Wasm module", -0.19, BLUE),
    ("gzip_bytes", "Gzip download", 0.19, TEAL),
]:
    vals = [profiles[k][field] / 1e6 for k in keys]
    bars = ax_sz.bar([i + off for i in range(len(keys))], vals, 0.35, label=label, color=color)
    ax_sz.bar_label(bars, labels=[f"{v:.2f}" for v in vals], padding=3, fontsize=9)
ax_sz.set_title("Compiler package size (MB)", fontsize=11.5, loc="left")
ax_sz.set_ylabel("Megabytes")
ax_sz.set_ylim(0, max(profiles[k]["bytes"] / 1e6 for k in keys) * 1.25)
ax_sz.set_xticks(range(len(keys)), labels=labels)
ax_sz.legend(frameon=False, fontsize=9)
style_ax(ax_sz)

for field, label, off, color in [
    ("cold", "Cold (1 core)", -0.19, BLUE),
    ("cached", "Cached (1 core)", 0.19, TEAL),
]:
    vals = [profiles[k][field]["wall_seconds"] for k in keys]
    bars = ax_tm.bar([i + off for i in range(len(keys))], vals, 0.35, label=label, color=color)
    ax_tm.bar_label(bars, labels=[f"{v:.2f}" for v in vals], padding=3, fontsize=9)
ax_tm.set_title("Frozen 9a6040a rebuild (CPU 7, 5 rounds)", fontsize=11.5, loc="left")
ax_tm.set_ylabel("Elapsed seconds")
ax_tm.set_ylim(0, max(profiles[k]["cold"]["wall_seconds"] for k in keys) * 1.25)
ax_tm.set_xticks(range(len(keys)), labels=labels)
ax_tm.legend(frameon=False, fontsize=9)
style_ax(ax_tm)
save(fig, "release")


# 2. engines_selfcompile.svg: Wasmtime vs wtime-aot (safe Rust) vs Native Clang/GCC on frozen & own source
fig, (ax_fr, ax_own) = plt.subplots(1, 2, figsize=(11.2, 4.3), sharey=False, layout="constrained")
fig.suptitle(
    "Same-Wasm engines vs native C: Wasmtime 50.0.1, wtime-aot (safe Rust) and native Clang/GCC (CPU 7, 7 rounds)",
    x=0.015, ha="left", fontsize=11.8, weight="bold",
)
eng_keys = [
    ("wasm_prev_bal", "Batch 11\nWasmtime", SLATE),
    ("wasm_cand_bal", "Batch 13\nWasmtime", TEAL),
    ("wtime_aot_32", "wtime-aot\n32-bit Rust", RUST),
    ("wtime_aot_64", "wtime-aot\n64-bit Rust", AMBER),
    ("native_clang", "Native\nClang -O2", NAVY),
    ("native_gcc", "Native\nGCC -O2", BLUE),
]

for ax, sec, title in [
    (ax_fr, "frozen", "Frozen 9a6040a → memory64 Wasm"),
    (ax_own, "own", "Own source selfhost/main.goose → memory64 Wasm"),
]:
    meds = res[sec]["medians"]
    vals = [meds[k]["wall_seconds"] for k, _, _ in eng_keys]
    ins = [meds[k]["instructions"] / 1e9 for k, _, _ in eng_keys]
    colors = [c for _, _, c in eng_keys]
    xlabs = [lbl for _, lbl, _ in eng_keys]
    bars = ax.bar(range(len(eng_keys)), vals, width=0.62, color=colors)
    ax.bar_label(
        bars,
        labels=[f"{v:.2f} s\n({i:.2f}B)" for v, i in zip(vals, ins)],
        padding=3, fontsize=8.5,
    )
    ax.set_title(title, fontsize=11, loc="left")
    ax.set_ylabel("Wall seconds (retired B instr)")
    ax.set_xticks(range(len(eng_keys)), labels=xlabs, fontsize=8.8)
    ax.set_ylim(0, max(vals) * 1.28)
    style_ax(ax)
save(fig, "engines_selfcompile")


# 3. upstream_selfcompile.svg: Head-to-head vs upstream C++ Goose (compiling selfhost/main.goose)
fig, (ax_w, ax_i) = plt.subplots(1, 2, figsize=(11.2, 4.2), sharey=True, layout="constrained")
up = res["upstream"]["medians"]
own = res["own"]["medians"]
up_rows = [
    ("Upstream C++ · emit C (-O2)", up["upstream_cpp_c"]["wall_seconds"], up["upstream_cpp_c"]["instructions"] / 1e9, "#8c5a4f"),
    ("Upstream C++ · check only", up["upstream_cpp_check"]["wall_seconds"], up["upstream_cpp_check"]["instructions"] / 1e9, SLATE),
    ("Wasmtime bal · emit C", up["wasm_cand_bal_c"]["wall_seconds"], up["wasm_cand_bal_c"]["instructions"] / 1e9, "#2d9d92"),
    ("Wasmtime bal · emit Wasm", own["wasm_cand_bal"]["wall_seconds"], own["wasm_cand_bal"]["instructions"] / 1e9, TEAL),
    ("Native Clang · emit C", up["native_clang_c"]["wall_seconds"], up["native_clang_c"]["instructions"] / 1e9, BLUE),
    ("wtime-aot 32 · emit Wasm", own["wtime_aot_32"]["wall_seconds"], own["wtime_aot_32"]["instructions"] / 1e9, RUST),
    ("Native GCC · emit Wasm", own["native_gcc"]["wall_seconds"], own["native_gcc"]["instructions"] / 1e9, NAVY),
]
fig.suptitle(
    "Compiling selfhost/main.goose: upstream C++ Goose vs Batch 13 Goose-to-Wasm (CPU 7)",
    x=0.015, ha="left", fontsize=12.0, weight="bold",
)
ys = list(range(len(up_rows)))
xl = [r[0] for r in up_rows]
ws = [r[1] for r in up_rows]
ins = [r[2] for r in up_rows]
cols = [r[3] for r in up_rows]

b1 = ax_w.barh(ys, ws, height=0.62, color=cols)
ax_w.bar_label(b1, labels=[f" {v:.2f} s" for v in ws], padding=2, fontsize=9, weight="bold")
ax_w.set_title("Elapsed wall time (lower is faster)", fontsize=11, loc="left")
ax_w.set_xlabel("Seconds")
ax_w.set_yticks(ys, labels=xl, fontsize=9.2)
ax_w.invert_yaxis()
ax_w.set_xlim(0, max(ws) * 1.24)
ax_w.spines[:].set_visible(False)
ax_w.tick_params(length=0, pad=5)
ax_w.set_axisbelow(True)
ax_w.grid(axis="x", color="#dce2e7", linewidth=0.8)

b2 = ax_i.barh(ys, ins, height=0.62, color=cols)
ax_i.bar_label(b2, labels=[f" {v:.1f} B" for v in ins], padding=2, fontsize=9, weight="bold")
ax_i.set_title("Retired CPU instructions (billions)", fontsize=11, loc="left")
ax_i.set_xlabel("Billions of instructions")
ax_i.set_xlim(0, max(ins) * 1.24)
ax_i.spines[:].set_visible(False)
ax_i.tick_params(length=0, pad=5)
ax_i.set_axisbelow(True)
ax_i.grid(axis="x", color="#dce2e7", linewidth=0.8)
save(fig, "upstream_selfcompile")


# 4. kernels_engines.svg: 3 runtime kernels across Wasmtime, wtime-aot, Native Clang, Native GCC
fig, axes = plt.subplots(1, 3, figsize=(11.4, 3.9), layout="constrained")
fig.suptitle(
    "Runtime kernels across Wasmtime 50.0.1, wtime-aot (safe Rust) and native C (CPU 7, 7 rounds)",
    x=0.015, ha="left", fontsize=11.8, weight="bold",
)
k_meta = [
    ("sorting", "examples/sorting.goose"),
    ("owner_kernel", "Growable-owner loop kernel"),
    ("sroa_kernel", "Small-struct SROA & multi-value"),
]
k_engs = [
    ("wasm_cand_bal", "Wasmtime\nbalanced", TEAL),
    ("wtime_aot", "wtime-aot\nsafe Rust", RUST),
    ("native_clang", "Native\nClang -O2", NAVY),
    ("native_gcc", "Native\nGCC -O2", BLUE),
]
for ax, (kname, ktitle) in zip(axes, k_meta):
    km = res["kernels"][kname]["medians"]
    vals = [km[k]["wall_seconds"] * 1000.0 for k, _, _ in k_engs]
    ins = [km[k]["instructions"] / 1e9 for k, _, _ in k_engs]
    bars = ax.bar(range(len(k_engs)), vals, width=0.6, color=[c for _, _, c in k_engs])
    ax.bar_label(bars, labels=[f"{v:.1f} ms\n({i:.2f}B)" for v, i in zip(vals, ins)], padding=3, fontsize=8.4)
    ax.set_title(ktitle, fontsize=10.8, loc="left")
    ax.set_ylabel("Milliseconds")
    ax.set_xticks(range(len(k_engs)), labels=[l for _, l, _ in k_engs], fontsize=8.6)
    ax.set_ylim(0, max(vals) * 1.30)
    style_ax(ax)
save(fig, "kernels_engines")

print("Plotted release, engines_selfcompile, upstream_selfcompile, kernels_engines!")
