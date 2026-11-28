#!/usr/bin/env python3
"""Generate deterministic SVG comparison charts for the 2026-11-28 v2026.4-7 report.

Reads pinned measurements from ./results.json and writes:
  1. blot2_subsecond_turnaround.svg  — Blot2 79.0k LOC sub-second edit -> native x64 turnaround
  2. blot2_hosted_engines.svg        — Edited 8.08 MiB Blot2 hosted compile + run across engines
  3. runtime_wtime_aot_v2026_4_7.svg — 6 runtime benchmarks: Prior vs New wtime-aot x64, Wasmtime 50.0.1, Native Clang -O2
"""
from __future__ import annotations

import json
from pathlib import Path
import statistics

import matplotlib
matplotlib.use("Agg")
from matplotlib.patches import Patch
import matplotlib.pyplot as plt

DIR = Path(__file__).resolve().parent
ROOT = DIR.parents[3]
PREVIEW = ROOT / "build" / "chart-preview-v7"
PREVIEW.mkdir(parents=True, exist_ok=True)

data = json.loads((DIR / "results.json").read_text())

plt.rcParams.update({
    "font.size": 10.0,
    "font.family": "DejaVu Sans",
    "svg.fonttype": "none",
    "svg.hashsalt": "goose-to-wasm-2026-11-28-subsecond-wtime-aot-v1",
    "axes.edgecolor": "#cbd5e1",
    "figure.facecolor": "#ffffff",
    "axes.facecolor": "#ffffff",
})

BASE_MUTED = "#94a3b8"
BASE_PURPLE_LT = "#c4b5fd"
TEAL = "#0f766e"
EMERALD = "#059669"
NAVY = "#1e3a5f"
BLUE = "#2563eb"
PURPLE = "#6d28d9"
AMBER = "#d97706"
SLATE = "#475569"
INK = "#0f172a"
RED = "#dc2626"
HALO = {"facecolor": "#ffffff", "edgecolor": "none", "pad": 0.45, "alpha": 0.92}


def clean_ax(ax, grid_axis: str = "y") -> None:
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=6)
    ax.set_axisbelow(True)
    ax.grid(axis=grid_axis, color="#e2e8f0", linewidth=0.9)


def save(fig, stem: str) -> None:
    fig.savefig(PREVIEW / f"{stem}.png", dpi=150, bbox_inches="tight", pad_inches=0.22)
    svg = DIR / f"{stem}.svg"
    fig.savefig(svg, metadata={"Date": None}, bbox_inches="tight", pad_inches=0.22)
    svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
    plt.close(fig)
    print("Generated", svg)


# =============================================================================
# 1. blot2_subsecond_turnaround.svg
# =============================================================================
s1 = data["suite1_blot2"]
cold_u = s1["cold_emit_8c"]["unprof_o0_cold"]["median_wall_s"]
cold_p = s1["cold_emit_8c"]["pgo_o0_cold"]["median_wall_s"]

ed_comp = s1["edits"]["compile_goose"]
ed_chk = s1["edits"]["check_goose"]

cu_emit = ed_comp["emit"]["unprof_o0_edited"]["median_wall_s"]
cp_emit = ed_comp["emit"]["pgo_o0_edited"]["median_wall_s"]
ku_emit = ed_chk["emit"]["unprof_o0_edited"]["median_wall_s"]
kp_emit = ed_chk["emit"]["pgo_o0_edited"]["median_wall_s"]

c_fib_o2_cold = ed_comp["hosted_8c"]["fibonacci"]["wtime_aot_o2_cold_8c"]["median_wall_s"]
c_fib_winch = ed_comp["hosted_8c"]["fibonacci"]["winch_o0_cold_8c"]["median_wall_s"]
c_fib_inc = ed_comp["hosted_8c"]["fibonacci"]["wtime_aot_o2_inc_cache_8c"]["median_wall_s"]
k_fib_inc = ed_chk["hosted_8c"]["fibonacci"]["wtime_aot_o2_inc_cache_8c"]["median_wall_s"]
c_mat_inc = ed_comp["hosted_8c"]["matrix_multiply"]["wtime_aot_o2_inc_cache_8c"]["median_wall_s"]

rows = [
    ("Cold -O0 + wtime-aot O2\n(unprofiled, 8 cores)", cold_u, c_fib_o2_cold, BASE_MUTED, AMBER),
    ("Edited compile.goose + Winch\n(.life hit + --fast-jit, unprof.)", cu_emit, c_fib_winch, TEAL, BLUE),
    ("Edited check.goose + --inc-cache\n(.life + per-fn O2 x64, unprof.)", ku_emit, k_fib_inc, TEAL, PURPLE),
    ("Edited compile.goose + --inc-cache\n(.life + per-fn O2 x64, unprof.)", cu_emit, c_fib_inc, TEAL, PURPLE),
    ("Edited compile.goose + --inc-cache\n(.life + per-fn O2 x64, PGO*)", cp_emit, c_fib_inc, EMERALD, PURPLE),
]

with matplotlib.rc_context({"hatch.linewidth": 1.4}):
    fig, ax1 = plt.subplots(figsize=(8.8, 4.7), layout="constrained")
    fig.suptitle(
        "Blot2 (79.0k LOC): breaking 1 second from Goose edit to O2 native x64 run",
        x=0.01, ha="left", fontsize=12.0, weight="bold", color=INK,
    )

    y = [i * 1.15 for i in range(len(rows))]
    bh = 0.56
    stripe_kw = {"edgecolor": "#ffffff", "hatch": "////", "linewidth": 0.6}
    for idx, (lbl, em, run, c_em, c_run) in enumerate(rows):
        yi = y[idx]
        ax1.barh(yi, em, height=bh, color=c_em)
        ax1.barh(yi, run, left=em, height=bh, facecolor=c_run, **stripe_kw)
        tot = em + run
        ax1.annotate(
            f"{tot:.3f} s  ({em*1000:.0f} + {run*1000:.0f} ms)",
            (tot, yi), xytext=(6, 0), textcoords="offset points",
            va="center", fontsize=9.1, weight="bold" if tot < 1.0 else "normal",
            color=EMERALD if tot < 0.80 else INK,
            bbox=HALO,
        )

    ax1.axvline(1.0, color=RED, linestyle="--", linewidth=1.25, alpha=0.8)
    ax1.text(1.03, -0.44, "1.0 s", color=RED, fontsize=9.1, weight="bold", va="bottom", bbox=HALO)
    ax1.set_title("End-to-end edit -> compile -> run fibonacci.blot (seconds, 8 cores, median of 5 alt. rounds)", fontsize=9.6, loc="left", color=SLATE, pad=12)
    ax1.set_xlabel("Seconds (upstream C++ Goose: 30.6 s Clang -O0 · 98.8 s Clang -O2 · bit-exact sha e60d8276…)", fontsize=8.8, color=SLATE)
    ax1.set_yticks(y, labels=[r[0] for r in rows], fontsize=9.1, color=INK)
    ax1.set_ylim(y[-1] + 0.65, -0.78)
    ax1.set_xlim(0, max(r[1] + r[2] for r in rows) * 1.48)
    legend_handles = [
        Patch(facecolor=BASE_MUTED, edgecolor="none", label="goosew -O0 emit (cold)"),
        Patch(facecolor=TEAL, edgecolor="none", label="goosew -O0 emit (.life hit)"),
        Patch(facecolor=EMERALD, edgecolor="none", label="goosew -O0 emit (.life, PGO*)"),
        Patch(facecolor=AMBER, label="wtime-aot O2 cold", **stripe_kw),
        Patch(facecolor=BLUE, label="goose-wasmtime Winch", **stripe_kw),
        Patch(facecolor=PURPLE, label="goose-wtime-aot O2 --inc-cache", **stripe_kw),
    ]
    ax1.legend(handles=legend_handles, frameon=True, facecolor="#ffffff", edgecolor="#e2e8f0", fontsize=8.5, loc="lower right", ncol=1)
    clean_ax(ax1, "x")

    save(fig, "blot2_subsecond_turnaround")


# =============================================================================
# 2. blot2_hosted_engines.svg
# =============================================================================
h_fib = ed_comp["hosted_8c"]["fibonacci"]
h_mat = ed_comp["hosted_8c"]["matrix_multiply"]
eng_rows = [
    ("wtime-aot O2\ncold", "wtime_aot_o2_cold_8c"),
    ("wtime-aot\n--fast cold", "wtime_aot_fast_o0_cold_8c"),
    ("Winch -O0\ncold", "winch_o0_cold_8c"),
    ("wtime-aot O2\n--inc-cache", "wtime_aot_o2_inc_cache_8c"),
    ("wtime-aot O2\n--cache warm", "wtime_aot_o2_warm_unchanged_8c"),
]
ex = [i * 1.15 for i in range(len(eng_rows))]
ew = 0.40
fv = [h_fib[k]["median_wall_s"] * 1000.0 for _, k in eng_rows]
mv = [h_mat[k]["median_wall_s"] * 1000.0 for _, k in eng_rows]

fig, ax2 = plt.subplots(figsize=(8.0, 4.6), layout="constrained")
fig.suptitle(
    "Blot2 (8.08 MiB Wasm64, 7,961 fns, 84 imports): hosted compile + run",
    x=0.01, ha="left", fontsize=12.0, weight="bold", color=INK,
)

b1 = ax2.bar([i - ew / 2 for i in ex], fv, width=ew * 0.90, color=TEAL, label="fibonacci.blot")
b2 = ax2.bar([i + ew / 2 for i in ex], mv, width=ew * 0.90, color=NAVY, label="matrix_multiply.blot")
ax2.bar_label(b1, labels=[f"{v:.0f}" for v in fv], padding=3, fontsize=9.0, weight="bold", color=TEAL)
ax2.bar_label(b2, labels=[f"{v:.0f}" for v in mv], padding=3, fontsize=9.0, weight="bold", color=NAVY)

inc_comp_ms = statistics.median([e["compile_ms"] for e in h_fib["wtime_aot_o2_inc_cache_8c"]["extras"]])
ax2.set_title("Edited compile.goose across engines (ms, 8 cores, median of 5 alternating rounds)", fontsize=9.6, loc="left", color=SLATE, pad=12)
ax2.set_ylabel("Milliseconds (lower is faster)", fontsize=9.4, color=SLATE)
ax2.set_xlabel(f"--inc-cache compiles 1 edited fn in {inc_comp_ms:.0f} ms (3.7 KB .delta) + runs full O2 x64", fontsize=8.9, color=SLATE)
ax2.set_xticks(ex, labels=[lbl for lbl, _ in eng_rows], fontsize=9.2, color=INK)
ax2.set_ylim(0, max(max(fv), max(mv)) * 1.24)
ax2.legend(frameon=False, fontsize=9.3, loc="upper right")
clean_ax(ax2, "y")

save(fig, "blot2_hosted_engines")


# =============================================================================
# 2. runtime_wtime_aot_v2026_4_7.svg — 6 runtime benchmarks on CPU 7
# =============================================================================
s2 = data["suite2_runtime_cpu7"]
rt = s2["runtime"]
prior = s2["prior_wtime_aot_x64_s"]
rt_exs = ["sorting", "life", "sudoku", "sieve", "maze"]
rx = [i * 1.32 for i in range(len(rt_exs))]
w4 = 0.24

x64_old = [prior[e] * 1000.0 for e in rt_exs]
x64_new = [rt[e]["wtime_aot_x64"]["median_wall_s"] * 1000.0 for e in rt_exs]
wt_new = [rt[e]["wasmtime"]["median_wall_s"] * 1000.0 for e in rt_exs]
nat_new = [rt[e]["native_o2"]["median_wall_s"] * 1000.0 for e in rt_exs]

fig, (ax_r, ax_m) = plt.subplots(
    1, 2, figsize=(15.4, 5.0), gridspec_kw={"width_ratios": [1.82, 1.0]}, layout="constrained"
)
fig.suptitle(
    "wtime-aot x64 codegen improvements (v2026.4-7, CPU 7, 5 alternating rounds — lower is faster)",
    x=0.01, ha="left", fontsize=12.4, weight="bold", color=INK,
)

r1 = ax_r.bar([i - 1.5 * w4 for i in rx], x64_old, width=w4 * 0.90, color=BASE_PURPLE_LT, edgecolor=PURPLE, linewidth=0.7, label="wtime-aot x64 · Prior (2026-11-28)")
r2 = ax_r.bar([i - 0.5 * w4 for i in rx], x64_new, width=w4 * 0.90, color=PURPLE, label="wtime-aot x64 · New (v2026.4-7)")
r3 = ax_r.bar([i + 0.5 * w4 for i in rx], wt_new, width=w4 * 0.90, color=TEAL, label="Wasmtime 50.0.1 (cached .cwasm)*")
r4 = ax_r.bar([i + 1.5 * w4 for i in rx], nat_new, width=w4 * 0.90, color=NAVY, label="Native Clang -O2 (ref.)")

ax_r.bar_label(r1, labels=[f"{v:.1f}" for v in x64_old], padding=2.5, fontsize=7.4, color=SLATE)
ax_r.bar_label(
    r2,
    labels=[f"{n:.1f}\n({(n-o)/o*100:.0f}%)" if abs((n - o) / o) >= 0.05 else f"{n:.1f}" for o, n in zip(x64_old, x64_new)],
    padding=2.5, fontsize=7.4, weight="bold", color=PURPLE, bbox=HALO,
)
ax_r.bar_label(r3, labels=[f"{v:.1f}" for v in wt_new], padding=2.5, fontsize=7.4, color=TEAL)
ax_r.bar_label(r4, labels=[f"{v:.1f}" for v in nat_new], padding=2.5, fontsize=7.4, weight="bold", color=NAVY)

ax_r.set_title("5 Example programs (ms · *Wasmtime in-process, others whole-process ELF)", fontsize=9.8, loc="left", color=INK)
ax_r.set_ylabel("Milliseconds", color=SLATE)
ax_r.set_xticks(rx, labels=rt_exs, fontsize=10.0, color=INK)
ax_r.set_ylim(0, max(max(x64_old), max(wt_new), max(nat_new)) * 1.28)
ax_r.legend(frameon=False, fontsize=8.4, loc="upper right")
clean_ax(ax_r, "y")

mb_old = prior["mandelbrot"]
mb_new = rt["mandelbrot"]["wtime_aot_x64"]["median_wall_s"]
mb_wt = rt["mandelbrot"]["wasmtime"]["median_wall_s"]
mb_nat = rt["mandelbrot"]["native_o2"]["median_wall_s"]
mb_delta = (mb_new - mb_old) / mb_old * 100.0

mb_rows = [
    ("wtime x64\nPrior", mb_old, BASE_PURPLE_LT, PURPLE, f"{mb_old:.3f} s"),
    ("wtime x64\nNew", mb_new, PURPLE, PURPLE, f"{mb_new:.3f} s\n({mb_delta:.1f}%)"),
    ("Wasmtime\n50.0.1", mb_wt, TEAL, TEAL, f"{mb_wt:.3f} s"),
    ("Native -O2\n(Clang 23)", mb_nat, NAVY, NAVY, f"{mb_nat:.3f} s"),
]
mx = list(range(len(mb_rows)))
mvals = [r[1] for r in mb_rows]
mbars = ax_m.bar(mx, mvals, width=0.56, color=[r[2] for r in mb_rows], edgecolor=[r[3] for r in mb_rows], linewidth=0.9)
ax_m.bar_label(mbars, labels=[r[4] for r in mb_rows], padding=4, fontsize=8.5, weight="bold", color=INK)
ax_m.set_title("Mandelbrot 2048×2048×1000 (strict IEEE-754: 1038538536)", fontsize=9.8, loc="left", color=INK)
ax_m.set_ylabel("Seconds (kernel clock)", color=SLATE)
ax_m.set_xticks(mx, labels=[r[0] for r in mb_rows], fontsize=8.7, color=INK)
ax_m.set_ylim(0, max(mvals) * 1.26)
clean_ax(ax_m, "y")

save(fig, "runtime_wtime_aot_v2026_4_7")
