#!/usr/bin/env python3
"""Generate the updated Production Runtime Speed chart including wtime-aot (x64 & safe-Rust).

Reads pinned CPU-7, 5-alternating-round measurements from ./results.json.
"""
from __future__ import annotations

import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

DIR = Path(__file__).resolve().parent
data = json.loads((DIR / "results.json").read_text())

plt.rcParams.update({
    "font.size": 10.2,
    "font.family": "DejaVu Sans",
    "svg.fonttype": "none",
    "svg.hashsalt": "goose-to-wasm-runtime-wtime-v1",
    "axes.edgecolor": "#cbd5e1",
    "figure.facecolor": "#ffffff",
    "axes.facecolor": "#ffffff",
})

UPSTREAM = "#b4533c"
NAVY = "#1e3a5f"
TEAL = "#0f766e"
PURPLE = "#6d28d9"
AMBER = "#d97706"
SLATE = "#475569"
INK = "#0f172a"


def clean_ax(ax, grid_axis: str = "y") -> None:
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=6)
    ax.set_axisbelow(True)
    ax.grid(axis=grid_axis, color="#e2e8f0", linewidth=0.9)


s3 = data["suite3_runtime"]
rt_exs = ["sorting", "life", "sudoku", "sieve", "maze"]
rx = [i * 1.12 for i in range(len(rt_exs))]
w = 0.185

u_rt = [s3[e]["upstream_native_o2"]["median_wall_s"] * 1000.0 for e in rt_exs]
n_rt = [s3[e]["g2w_native_o2"]["median_wall_s"] * 1000.0 for e in rt_exs]
wt_rt = [s3[e]["g2w_wasm_wasmtime"]["median_wall_s"] * 1000.0 for e in rt_exs]
wx_rt = [s3[e]["g2w_wtime_aot_x64"]["median_wall_s"] * 1000.0 for e in rt_exs]
wr_rt = [s3[e]["g2w_wtime_aot_rust"]["median_wall_s"] * 1000.0 for e in rt_exs]

fig, (ax_r, ax_m) = plt.subplots(
    1, 2, figsize=(14.8, 4.7), gridspec_kw={"width_ratios": [1.80, 1.0]}, layout="constrained"
)
fig.suptitle(
    "Compiled program runtime: Native -O2, Wasmtime, and wtime-aot (CPU 7, lower is faster)",
    x=0.01, ha="left", fontsize=13.0, weight="bold", color=INK,
)

b1 = ax_r.bar([i - 2 * w for i in rx], u_rt, width=w * 0.94, color=UPSTREAM, label="Upstream C++ · Native -O2")
b2 = ax_r.bar([i - 1 * w for i in rx], n_rt, width=w * 0.94, color=NAVY, label="Goose to Wasm · Native -O2")
b3 = ax_r.bar([i + 0 * w for i in rx], wt_rt, width=w * 0.94, color=TEAL, label="Goose to Wasm · Wasmtime (cached)")
b4 = ax_r.bar([i + 1 * w for i in rx], wx_rt, width=w * 0.94, color=PURPLE, label="Goose to Wasm · wtime-aot (x64, zero-LLVM)")
b5 = ax_r.bar([i + 2 * w for i in rx], wr_rt, width=w * 0.94, color=AMBER, label="Goose to Wasm · wtime-aot (safe Rust)")

ax_r.bar_label(b1, labels=[f"{v:.1f}" for v in u_rt], padding=2.5, fontsize=7.4, color=SLATE)
ax_r.bar_label(b2, labels=[f"{v:.1f}" for v in n_rt], padding=2.5, fontsize=7.4, weight="bold", color=NAVY)
ax_r.bar_label(b3, labels=[f"{v:.1f}" for v in wt_rt], padding=2.5, fontsize=7.4, weight="bold", color=TEAL)
ax_r.bar_label(b4, labels=[f"{v:.1f}" for v in wx_rt], padding=2.5, fontsize=7.4, weight="bold", color=PURPLE)
ax_r.bar_label(b5, labels=[f"{v:.1f}" for v in wr_rt], padding=2.5, fontsize=7.4, weight="bold", color=AMBER)

ax_r.set_title("Example programs (ms, bit-exact · Wasmtime in-process, others whole-process)", fontsize=10.2, loc="left", color=INK)
ax_r.set_ylabel("Milliseconds", color=SLATE)
ax_r.set_xticks(rx, labels=rt_exs, fontsize=10.2, color=INK)
ax_r.set_ylim(0, max(max(u_rt), max(n_rt), max(wt_rt), max(wx_rt), max(wr_rt)) * 1.32)
ax_r.legend(frameon=False, fontsize=8.6, loc="upper right", ncol=1)
clean_ax(ax_r, "y")

mb = s3["mandelbrot"]
mb_rows = [
    ("Upstream\nNative -O2", mb["upstream_native_o2"]["median_wall_s"], UPSTREAM),
    ("g2w\nNative -O2", mb["g2w_native_o2"]["median_wall_s"], NAVY),
    ("g2w\nWasmtime", mb["g2w_wasm_wasmtime"]["median_wall_s"], TEAL),
    ("g2w\nwtime x64", mb["g2w_wtime_aot_x64"]["median_wall_s"], PURPLE),
    ("g2w\nwtime Rust", mb["g2w_wtime_aot_rust"]["median_wall_s"], AMBER),
]
mx = list(range(len(mb_rows)))
mvals = [r[1] for r in mb_rows]
mbars = ax_m.bar(mx, mvals, width=0.58, color=[r[2] for r in mb_rows])
ax_m.bar_label(mbars, labels=[f"{v:.2f} s" for v in mvals], padding=4, fontsize=9.0, weight="bold", color=INK)
ax_m.set_title("Mandelbrot 2048×2048 (kernel clock)", fontsize=10.2, loc="left", color=INK)
ax_m.set_ylabel("Seconds", color=SLATE)
ax_m.set_xticks(mx, labels=[r[0] for r in mb_rows], fontsize=8.8, color=INK)
ax_m.set_ylim(0, max(mvals) * 1.24)
clean_ax(ax_m, "y")

fig.savefig(DIR / "runtime_speed.png", dpi=150, bbox_inches="tight", pad_inches=0.20)
svg = DIR / "runtime_speed.svg"
fig.savefig(svg, metadata={"Date": None}, bbox_inches="tight", pad_inches=0.20)
svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
plt.close(fig)
print("Generated", svg)
