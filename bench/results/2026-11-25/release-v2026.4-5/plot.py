#!/usr/bin/env python3
"""Generate clean, legible consumer README charts for goose-to-wasm v2026.4-5.

Reads pinned dated measurements from:
  - ../release-v2026.4-4/results.json  (CPU 7, 5 alt. rounds; unchanged codegen in v2026.4-5)
  - ../blot2-head-98f277f2/metrics.json (CPU 7 + parallel Cranelift on Blot2 HEAD 98f277f2)
"""
from __future__ import annotations

import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

DIR = Path(__file__).resolve().parent
v4 = json.loads((DIR.parent / "release-v2026.4-4" / "results.json").read_text())
blot = json.loads((DIR.parent / "blot2-head-98f277f2" / "metrics.json").read_text())

plt.rcParams.update({
    "font.size": 10.5,
    "font.family": "DejaVu Sans",
    "svg.fonttype": "none",
    "svg.hashsalt": "goose-to-wasm-v2026.4-5",
    "axes.edgecolor": "#cbd5e1",
    "figure.facecolor": "#ffffff",
    "axes.facecolor": "#ffffff",
})

UPSTREAM = "#b4533c"
UPSTREAM_LT = "#d0826f"
TEAL = "#0f766e"
NAVY = "#1e3a5f"
SLATE = "#475569"
INK = "#0f172a"


def save(fig, stem: str) -> None:
    fig.savefig(DIR / f"{stem}.png", dpi=150, bbox_inches="tight", pad_inches=0.20)
    svg = DIR / f"{stem}.svg"
    fig.savefig(svg, metadata={"Date": None}, bbox_inches="tight", pad_inches=0.20)
    svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
    plt.close(fig)


def clean_ax(ax, grid_axis: str = "x") -> None:
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=6)
    ax.set_axisbelow(True)
    ax.grid(axis=grid_axis, color="#e2e8f0", linewidth=0.9)


# =============================================================================
# 1. everyday_dev_loop.svg — Single clean chart: 8 everyday Goose programs
# =============================================================================
s2 = v4["suite2_examples_build"]
exs = ["squares", "sieve", "sudoku", "vm", "life", "tour", "maze", "sorting"]
up_ms = [s2[e]["upstream_build_o2"]["median_wall_s"] * 1000.0 for e in exs]
gw_ms = [s2[e]["g2w_wasm_o2"]["median_wall_s"] * 1000.0 for e in exs]

fig, ax = plt.subplots(figsize=(10.6, 4.3), layout="constrained")
fig.suptitle(
    "Everyday dev loop: compile to a runnable artifact (ms, lower is faster)",
    x=0.01, ha="left", fontsize=13.0, weight="bold", color=INK,
)
ax.set_title(
    "8 real Goose programs at -O2 · Direct Wasm skips the C compiler & linker (CPU 7, median of 5 rounds)",
    loc="left", fontsize=10.0, color=SLATE, pad=10,
)

x = list(range(len(exs)))
w = 0.37
b_up = ax.bar([i - w / 2 for i in x], up_ms, width=w, color=UPSTREAM, label="Upstream C++ Goose (build -O2 via Clang)")
b_gw = ax.bar([i + w / 2 for i in x], gw_ms, width=w, color=TEAL, label="Goose to Wasm (Direct Wasm -O2)")

ax.bar_label(b_up, labels=[f"{v:.0f} ms" for v in up_ms], padding=3, fontsize=8.8, color=SLATE)
ax.bar_label(b_gw, labels=[f"{v:.1f} ms" for v in gw_ms], padding=3, fontsize=8.8, weight="bold", color=TEAL)

for i in x:
    ratio = up_ms[i] / gw_ms[i]
    top = max(up_ms[i], gw_ms[i])
    ax.text(
        i, top + 16, f"{ratio:.0f}× faster",
        ha="center", va="bottom", fontsize=8.8, weight="bold", color=NAVY,
        bbox={"boxstyle": "round,pad=0.22", "facecolor": "#f1f5f9", "edgecolor": "#cbd5e1", "linewidth": 0.7},
    )

ax.set_ylabel("Milliseconds", color=INK)
ax.set_xticks(x, labels=exs, fontsize=10.2, color=INK)
ax.set_ylim(0, max(up_ms) * 1.28)
ax.legend(frameon=False, fontsize=9.8, loc="upper left")
clean_ax(ax, "y")

save(fig, "everyday_dev_loop")


# =============================================================================
# 2. large_codebase_turnaround.svg — Self-hosting compiler & mewhhaha/blot2
# =============================================================================
s1 = v4["suite1_selfcompile"]

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12.6, 4.4), gridspec_kw={"width_ratios": [1.0, 1.15]}, layout="constrained")
fig.suptitle(
    "Large real-world Goose codebases: edit-compile-run turnaround (seconds, lower is faster)",
    x=0.01, ha="left", fontsize=12.8, weight="bold", color=INK,
)

# Left panel: goose-to-wasm itself (~32k LOC)
up_chk = s1["upstream_check"]["median_wall_s"]
gw_chk = s1["g2w_check"]["median_wall_s"]
up_emit = s1["upstream_emit_c"]["median_wall_s"]
gw_wasm = s1["g2w_wasm64"]["median_wall_s"]
gw_c = s1["g2w_emit_c"]["median_wall_s"]

left_rows = [
    ("Upstream C++ · check", up_chk, UPSTREAM_LT, f"{up_chk:.2f} s"),
    ("Goose to Wasm · --check", gw_chk, NAVY, f"{gw_chk:.2f} s  ({up_chk/gw_chk:.1f}× faster)"),
    ("Upstream C++ · emit C (-O2)", up_emit, UPSTREAM, f"{up_emit:.2f} s"),
    ("Goose to Wasm · emit C (-O2)", gw_c, "#2b6cb0", f"{gw_c:.2f} s  ({up_emit/gw_c:.1f}× faster)"),
    ("Goose to Wasm · Direct Wasm", gw_wasm, TEAL, f"{gw_wasm:.2f} s  ({up_emit/gw_wasm:.1f}× faster)"),
]
ly = [0.0, 0.85, 2.05, 2.90, 3.75]
lbars = ax1.barh(ly, [r[1] for r in left_rows], height=0.64, color=[r[2] for r in left_rows])
ax1.bar_label(lbars, labels=[f" {r[3]}" for r in left_rows], padding=4, fontsize=9.2, weight="bold", color=INK)
ax1.set_title("Our own compiler (selfhost/, ~32k LOC · CPU 7)", fontsize=10.8, loc="left", color=INK, pad=8)
ax1.set_xlabel("Seconds", color=SLATE)
ax1.set_yticks(ly, labels=[r[0] for r in left_rows], fontsize=9.3, color=INK)
ax1.invert_yaxis()
ax1.set_xlim(0, up_emit * 1.48)
clean_ax(ax1, "x")

# Right panel: mewhhaha/blot2 (~135k LOC)
b_up_chk = blot["upstream_check_pin7"]["median_s"]
b_gw_chk = blot["check_patched_pin7"]["median_s"]
b_up_rel = 98.831  # blot2 recorded stages/emit-program.json (15.333) + compile-and-link-program.json (83.498)
b_up_dbg = 30.64   # separate reference run: 13.30s emit + 17.34s clang -O0
b_gw_dev = blot["emit_wasm64_O0_pin7"]["median_s"] + blot["wasmtime_cold_O0_unpinned"]["median_s"]

right_rows = [
    ("Upstream C++ · check", b_up_chk, UPSTREAM_LT, f"{b_up_chk:.1f} s"),
    ("Goose to Wasm · --check", b_gw_chk, NAVY, f"{b_gw_chk:.1f} s  ({b_up_chk/b_gw_chk:.1f}× faster)"),
    ("Upstream + Clang -O2 (release)*", b_up_rel, UPSTREAM, f"{b_up_rel:.1f} s"),
    ("Upstream + Clang -O0 (debug)*", b_up_dbg, UPSTREAM_LT, f"{b_up_dbg:.1f} s"),
    ("Direct Wasm64 + Wasmtime (-O0)", b_gw_dev, TEAL, f"{b_gw_dev:.1f} s  ({b_up_dbg/b_gw_dev:.1f}×–{b_up_rel/b_gw_dev:.0f}× faster)"),
]
ry = [0.0, 0.85, 2.05, 2.90, 3.75]
rbars = ax2.barh(ry, [r[1] for r in right_rows], height=0.64, color=[r[2] for r in right_rows])
ax2.bar_label(rbars, labels=[f" {r[3]}" for r in right_rows], padding=4, fontsize=9.2, weight="bold", color=INK)
ax2.set_title("mewhhaha/blot2 compiler (~135k LOC · 16/16 bit-exact)", fontsize=10.8, loc="left", color=INK, pad=8)
ax2.set_xlabel("Seconds (*separate ref. C builds; Wasm64 = 3.8 s emit + 2.4 s JIT+run)", fontsize=8.8, color=SLATE)
ax2.set_yticks(ry, labels=[r[0] for r in right_rows], fontsize=9.3, color=INK)
ax2.invert_yaxis()
ax2.set_xlim(0, b_up_rel * 1.38)
clean_ax(ax2, "x")

save(fig, "large_codebase_turnaround")


# =============================================================================
# 3. runtime_speed.svg — Production runtime speed (Native -O2 & Wasmtime)
# =============================================================================
s3 = v4["suite3_runtime"]
rt_exs = ["sorting", "life", "sudoku", "sieve", "maze"]
rx = list(range(len(rt_exs)))
w3 = 0.26

u_rt = [s3[e]["upstream_native_o2"]["median_wall_s"] * 1000.0 for e in rt_exs]
n_rt = [s3[e]["g2w_native_o2"]["median_wall_s"] * 1000.0 for e in rt_exs]
w_rt = [s3[e]["g2w_wasm_wasmtime"]["median_wall_s"] * 1000.0 for e in rt_exs]

fig, (ax_r, ax_m) = plt.subplots(1, 2, figsize=(11.8, 4.1), gridspec_kw={"width_ratios": [1.45, 1.0]}, layout="constrained")
fig.suptitle(
    "Compiled program runtime: fast builds without slowing down your code (CPU 7, lower is faster)",
    x=0.01, ha="left", fontsize=12.6, weight="bold", color=INK,
)

b1 = ax_r.bar([i - w3 for i in rx], u_rt, width=w3, color=UPSTREAM, label="Upstream C++ · Native -O2")
b2 = ax_r.bar(rx, n_rt, width=w3, color=NAVY, label="Goose to Wasm · Native -O2")
b3 = ax_r.bar([i + w3 for i in rx], w_rt, width=w3, color=TEAL, label="Goose to Wasm · Direct Wasm (Wasmtime)")

ax_r.bar_label(b1, labels=[f"{v:.1f}" for v in u_rt], padding=2, fontsize=8.2, color=SLATE)
ax_r.bar_label(b2, labels=[f"{v:.1f}" for v in n_rt], padding=2, fontsize=8.2, weight="bold", color=NAVY)
ax_r.bar_label(b3, labels=[f"{v:.1f}" for v in w_rt], padding=2, fontsize=8.2, weight="bold", color=TEAL)

ax_r.set_title("Example programs (ms, bit-exact output)", fontsize=10.8, loc="left", color=INK)
ax_r.set_ylabel("Milliseconds", color=SLATE)
ax_r.set_xticks(rx, labels=rt_exs, fontsize=10.0, color=INK)
ax_r.set_ylim(0, max(max(u_rt), max(n_rt), max(w_rt)) * 1.24)
ax_r.legend(frameon=False, fontsize=9.0, loc="upper right")
clean_ax(ax_r, "y")

mb = s3["mandelbrot"]
mb_rows = [
    ("Upstream\nNative -O2", mb["upstream_native_o2"]["median_wall_s"], UPSTREAM),
    ("Goose to Wasm\nNative -O2", mb["g2w_native_o2"]["median_wall_s"], NAVY),
    ("Goose to Wasm\nWasmtime", mb["g2w_wasm_wasmtime"]["median_wall_s"], TEAL),
]
mx = list(range(len(mb_rows)))
mvals = [r[1] for r in mb_rows]
mbars = ax_m.bar(mx, mvals, width=0.52, color=[r[2] for r in mb_rows])
ax_m.bar_label(mbars, labels=[f"{v:.2f} s" for v in mvals], padding=4, fontsize=9.5, weight="bold", color=INK)
ax_m.set_title("Mandelbrot 2048×2048 (kernel clock)", fontsize=10.8, loc="left", color=INK)
ax_m.set_ylabel("Seconds", color=SLATE)
ax_m.set_xticks(mx, labels=[r[0] for r in mb_rows], fontsize=9.4, color=INK)
ax_m.set_ylim(0, max(mvals) * 1.24)
clean_ax(ax_m, "y")

save(fig, "runtime_speed")
print("Generated 3 clean README SVG + PNG charts in", DIR)
