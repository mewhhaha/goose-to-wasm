#!/usr/bin/env python3
"""Generate SVG charts for the 2026-11-26 compiler-throughput campaign.

Reads pinned dated JSON measurements from this directory:
  - batch3c_paired_nopgo_j8.json  (matched unprofiled Clang 23 -O2, 5 alt. rounds)
  - batch3c_scaling.json          (flat_multi_100k_o0 thread scaling, 5 rounds)
  - batch3c_scale_250k.json       (flat_multi_250k_o0 sustained scale ref, 5 rounds)
"""
from __future__ import annotations

import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
from matplotlib.patches import Patch
import matplotlib.pyplot as plt

DIR = Path(__file__).resolve().parent
PREVIEW = DIR.parents[3] / "build" / "chart-preview"
PREVIEW.mkdir(parents=True, exist_ok=True)

paired = json.loads((DIR / "batch3c_paired_nopgo_j8.json").read_text())
scaling = json.loads((DIR / "batch3c_scaling.json").read_text())
scale250 = json.loads((DIR / "batch3c_scale_250k.json").read_text())

plt.rcParams.update({
    "font.size": 10.2,
    "font.family": "DejaVu Sans",
    "svg.fonttype": "none",
    "svg.hashsalt": "goose-to-wasm-2026-11-26-throughput",
    "axes.edgecolor": "#cbd5e1",
    "figure.facecolor": "#ffffff",
    "axes.facecolor": "#ffffff",
})

UPSTREAM = "#b4533c"
UPSTREAM_LT = "#d0826f"
TEAL = "#0f766e"
TEAL_LT = "#5eead4"
NAVY = "#1e3a5f"
BLUE = "#2563eb"
AMBER = "#d97706"
PURPLE = "#7c3aed"
SLATE = "#475569"
GRAY = "#94a3b8"
INK = "#0f172a"


def save(fig, stem: str) -> None:
    fig.savefig(PREVIEW / f"{stem}.png", dpi=150, bbox_inches="tight", pad_inches=0.22)
    svg = DIR / f"{stem}.svg"
    fig.savefig(svg, metadata={"Date": None}, bbox_inches="tight", pad_inches=0.22)
    svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
    plt.close(fig)


def clean_ax(ax, grid_axis: str = "y") -> None:
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=6)
    ax.set_axisbelow(True)
    ax.grid(axis=grid_axis, color="#e2e8f0", linewidth=0.9)


# =============================================================================
# 1. compiler_throughput.svg — Multi-core LOC/s scaling & real-codebase speedup
# =============================================================================
fig, (ax1, ax2) = plt.subplots(
    1, 2, figsize=(13.2, 4.7), gridspec_kw={"width_ratios": [1.18, 1.0]}, layout="constrained"
)
fig.suptitle(
    "Compiler throughput: up to 1.50M LOC/s end-to-end & 1.62M LOC/s compile stages (bit-identical Direct Wasm)",
    x=0.01, ha="left", fontsize=12.4, weight="bold", color=INK,
)

# Left panel: LOC/s scaling (matched unprofiled Clang 23 -O2 on Ryzen 7 7800X3D)
base_100k = paired["workloads"]["flat_multi_100k_o0"]["base"]
base_loc_m = (base_100k["loc"] / (base_100k["median_wall_ms"] / 1000.0)) / 1e6
base_cmp_ms = (
    base_100k["stages_ms"]["parse_ms"]
    + base_100k["stages_ms"]["typecheck_ms"]
    + base_100k["stages_ms"]["optimize_ms"]
    + base_100k["stages_ms"]["backend_ms"]
)
base_cmp_m = (base_100k["loc"] / (base_cmp_ms / 1000.0)) / 1e6

s_nopgo = scaling["nopgo"]["jobs"]
r250_j10 = next(r for r in scale250["runs"] if r["label"] == "batch3c-nopgo j=10")

labels = [
    "v2026.4-3\n(1 core)",
    "New\n--jobs 1",
    "New\n--jobs 2",
    "New\n--jobs 4",
    "New\n--jobs 8\n(auto)",
    "New\n--jobs 10",
    "247k LOC*\n--jobs 10",
]
wall_m = [
    base_loc_m,
    s_nopgo["1"]["wall_loc_per_sec"] / 1e6,
    s_nopgo["2"]["wall_loc_per_sec"] / 1e6,
    s_nopgo["4"]["wall_loc_per_sec"] / 1e6,
    s_nopgo["8"]["wall_loc_per_sec"] / 1e6,
    s_nopgo["10"]["wall_loc_per_sec"] / 1e6,
    r250_j10["wall_loc_per_sec"] / 1e6,
]
cmp_m = [
    base_cmp_m,
    s_nopgo["1"]["compile_loc_per_sec"] / 1e6,
    s_nopgo["2"]["compile_loc_per_sec"] / 1e6,
    s_nopgo["4"]["compile_loc_per_sec"] / 1e6,
    s_nopgo["8"]["compile_loc_per_sec"] / 1e6,
    s_nopgo["10"]["compile_loc_per_sec"] / 1e6,
    r250_j10["compile_loc_per_sec"] / 1e6,
]

x = list(range(len(labels)))
w = 0.38
b_wall = ax1.bar([i - w / 2 for i in x], wall_m, width=w, color=TEAL)
b_cmp = ax1.bar([i + w / 2 for i in x], cmp_m, width=w, color=NAVY)
b_wall[0].set_color(UPSTREAM)
b_cmp[0].set_color(UPSTREAM_LT)

for i, (wv, cv) in enumerate(zip(wall_m, cmp_m)):
    w_col = UPSTREAM if i == 0 else TEAL
    c_col = SLATE if i == 0 else NAVY
    ax1.text(
        i - w / 2 - 0.03, wv + 0.03, f"{wv:.2f}",
        ha="center", va="bottom", fontsize=7.9, weight="bold", color=w_col,
        bbox={"facecolor": "#ffffff", "edgecolor": "none", "pad": 0.4, "alpha": 0.85},
    )
    ax1.text(
        i + w / 2 + 0.03, cv + 0.03, f"{cv:.2f}",
        ha="center", va="bottom", fontsize=7.9, color=c_col,
        bbox={"facecolor": "#ffffff", "edgecolor": "none", "pad": 0.4, "alpha": 0.85},
    )

ax1.axhline(1.50, color=SLATE, linestyle="--", linewidth=1.1, alpha=0.75)
ax1.text(0.02, 1.535, "1.50M LOC/s reference", fontsize=8.4, color=SLATE, style="italic")

ax1.set_title(
    "Multi-file Goose → Direct Wasm -O0 (98.7k LOC · *246.8k LOC scale ref · higher is faster)",
    fontsize=9.6, loc="left", color=INK, pad=8,
)
ax1.set_ylabel("Million LOC / second", color=INK)
ax1.set_xticks(x, labels=labels, fontsize=8.6, color=INK)
ax1.set_ylim(0, 2.02)
ax1.legend(
    handles=[
        Patch(facecolor=TEAL, label="End-to-end process wall (incl. OS/I/O)"),
        Patch(facecolor=NAVY, label="Compile stages (parse→check→opt→wasm)"),
        Patch(facecolor=UPSTREAM, label="v2026.4-3 baseline (1 core)"),
    ],
    frameon=False, fontsize=8.5, loc="upper left",
)
clean_ax(ax1, "y")

# Right panel: Real large codebases (matched unprofiled Clang 23 -O2, --jobs 8)
wls = [
    ("selfhost -O0\n(47.4k LOC)", "selfhost_o0_wasm64"),
    ("selfhost -O2\n(47.4k LOC)", "selfhost_o2_wasm64"),
    ("blot2 -O0\n(79.0k LOC)", "blot2_o0_wasm64"),
    ("blot2 -O2\n(79.0k LOC)", "blot2_o2_wasm64"),
]
y = [i * 1.18 for i in range(len(wls))]
h = 0.40
b_vals = [paired["workloads"][k]["base"]["median_wall_ms"] / 1000.0 for _, k in wls]
c_vals = [paired["workloads"][k]["cand"]["median_wall_ms"] / 1000.0 for _, k in wls]

hb_base = ax2.barh([p - h / 2 for p in y], b_vals, height=h, color=UPSTREAM, label="v2026.4-3 (single-core)")
hb_cand = ax2.barh([p + h / 2 for p in y], c_vals, height=h, color=TEAL, label="New (default --jobs auto)")

ax2.bar_label(hb_base, labels=[f" {v:.2f} s" for v in b_vals], padding=3, fontsize=8.8, color=SLATE)
ax2.bar_label(
    hb_cand,
    labels=[f" {c:.2f} s  ({b/c:.2f}× faster)" for b, c in zip(b_vals, c_vals)],
    padding=3, fontsize=8.8, weight="bold", color=TEAL,
)

ax2.set_title(
    "Real large codebases → Direct Wasm64 (seconds, lower is faster · 100% SHA-256 identical)",
    fontsize=9.6, loc="left", color=INK, pad=22,
)
ax2.set_xlabel("Seconds (Blot2 backend 6.2× faster, -O2 optimizer 6.6× faster)", fontsize=8.6, color=SLATE)
ax2.set_yticks(y, labels=[lbl for lbl, _ in wls], fontsize=9.0, color=INK)
ax2.invert_yaxis()
ax2.set_xlim(0, max(b_vals) * 1.42)
ax2.legend(frameon=False, fontsize=8.6, loc="lower left", bbox_to_anchor=(0.0, 1.005), ncol=2)
clean_ax(ax2, "x")

save(fig, "compiler_throughput")


# =============================================================================
# 2. stage_breakdown.svg — Per-stage wall-time breakdown (flat_multi_100k & blot2)
# =============================================================================
fig, (ax1, ax2) = plt.subplots(
    1, 2, figsize=(13.0, 4.3), gridspec_kw={"width_ratios": [1.15, 1.0]}, layout="constrained"
)
fig.suptitle(
    "Stage-by-stage wall time breakdown (matched unprofiled Clang 23 -O2, Ryzen 7 7800X3D)",
    x=0.01, ha="left", fontsize=12.4, weight="bold", color=INK,
)

STAGES = [
    ("parse_ms", "Parse/Lex", "#2563eb"),
    ("typecheck_excl_life_ms", "Typecheck", "#0f766e"),
    ("lifetime_ms", "Lifetimes", "#d97706"),
    ("optimize_ms", "Optimize", "#7c3aed"),
    ("backend_ms", "Wasm backend", "#b4533c"),
    ("other_ms", "OS / I/O / exit", "#94a3b8"),
]


def extract_row(wall_ms: float, st: dict) -> list[float]:
    cmp_ms = st["parse_ms"] + st["typecheck_ms"] + st["optimize_ms"] + st["backend_ms"]
    other = max(0.0, wall_ms - cmp_ms)
    vals = []
    for k, _, _ in STAGES:
        vals.append(other if k == "other_ms" else st[k])
    return vals


# Left: flat_multi_100k_o0 progression
f_rows = [
    ("v2026.4-3 (j=1)", base_100k["median_wall_ms"], base_100k["stages_ms"]),
    ("Batch 3C (j=1)", s_nopgo["1"]["median_wall_ms"], s_nopgo["1"]["stages_ms"]),
    ("Batch 3C (j=2)", s_nopgo["2"]["median_wall_ms"], s_nopgo["2"]["stages_ms"]),
    ("Batch 3C (j=4)", s_nopgo["4"]["median_wall_ms"], s_nopgo["4"]["stages_ms"]),
    ("Batch 3C (j=8)", s_nopgo["8"]["median_wall_ms"], s_nopgo["8"]["stages_ms"]),
    ("Batch 3C (j=10)", s_nopgo["10"]["median_wall_ms"], s_nopgo["10"]["stages_ms"]),
]
fy = list(range(len(f_rows)))
left_acc = [0.0] * len(f_rows)
for idx, (key, label, color) in enumerate(STAGES):
    seg = [extract_row(w_ms, st)[idx] for _, w_ms, st in f_rows]
    ax1.barh(fy, seg, left=left_acc, height=0.60, color=color, label=label)
    left_acc = [a + b for a, b in zip(left_acc, seg)]

for i, (_, w_ms, _) in enumerate(f_rows):
    loc_s = 98749 / (w_ms / 1000.0) / 1e6
    ax1.text(w_ms + 4, i, f"{w_ms:.1f} ms ({loc_s:.2f}M/s)", va="center", fontsize=8.8, weight="bold", color=INK)

ax1.set_title("flat_multi_100k -O0 (98,749 LOC · ms, lower is faster)", fontsize=10.0, loc="left", color=INK, pad=8)
ax1.set_xlabel("Milliseconds", color=SLATE)
ax1.set_yticks(fy, labels=[r[0] for r in f_rows], fontsize=9.0, color=INK)
ax1.invert_yaxis()
ax1.set_xlim(0, 365)
ax1.legend(frameon=False, fontsize=8.2, loc="lower right", ncol=2)
clean_ax(ax1, "x")

# Right: selfhost & blot2 -O2 stage breakdown (v2026.4-3 vs Batch 3C j=8)
r_rows = [
    ("selfhost -O2\nv2026.4-3", paired["workloads"]["selfhost_o2_wasm64"]["base"]),
    ("selfhost -O2\nBatch 3C j=8", paired["workloads"]["selfhost_o2_wasm64"]["cand"]),
    ("blot2 -O2\nv2026.4-3", paired["workloads"]["blot2_o2_wasm64"]["base"]),
    ("blot2 -O2\nBatch 3C j=8", paired["workloads"]["blot2_o2_wasm64"]["cand"]),
]
ry = [0.0, 0.82, 2.0, 2.82]
left_acc2 = [0.0] * len(r_rows)
for idx, (key, label, color) in enumerate(STAGES):
    seg = [extract_row(d["median_wall_ms"], d["stages_ms"])[idx] for _, d in r_rows]
    ax2.barh(ry, seg, left=left_acc2, height=0.60, color=color)
    left_acc2 = [a + b for a, b in zip(left_acc2, seg)]

for i, (_, d) in enumerate(r_rows):
    w_ms = d["median_wall_ms"]
    ax2.text(w_ms + 70, ry[i], f"{w_ms/1000:.2f} s", va="center", fontsize=9.0, weight="bold", color=INK)

ax2.set_title("selfhost & blot2 -O2 Wasm64 (ms, lower is faster)", fontsize=10.0, loc="left", color=INK, pad=8)
ax2.set_xlabel("Milliseconds (Blot2 -O2 opt: 820→125 ms, backend: 554→119 ms)", fontsize=8.6, color=SLATE)
ax2.set_yticks(ry, labels=[r[0] for r in r_rows], fontsize=8.8, color=INK)
ax2.invert_yaxis()
ax2.set_xlim(0, 5400)
clean_ax(ax2, "x")

save(fig, "stage_breakdown")
print("Saved SVG charts to", DIR)
