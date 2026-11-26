#!/usr/bin/env python3
"""Generate SVG charts for the 2026-11-26 compiler-throughput campaign.

Reads pinned dated JSON measurements from this directory:
  - batch4_paired_nopgo_j8.json   (matched unprofiled Clang 23 -O2, 5 alt. rounds)
  - batch4_cgen_paired.json       (matched unprofiled --target c, 5 alt. rounds)
  - batch4_scaling.json           (flat_multi_100k_o0 thread scaling, 5 rounds)
  - batch4_scale_250k.json        (flat_multi_250k_o0 sustained scale ref, 5 rounds)
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

paired = json.loads((DIR / "batch4_paired_nopgo_j8.json").read_text())
cgen = json.loads((DIR / "batch4_cgen_paired.json").read_text())
scaling = json.loads((DIR / "batch4_scaling.json").read_text())
scale250 = json.loads((DIR / "batch4_scale_250k.json").read_text())

plt.rcParams.update({
    "font.size": 10.2,
    "font.family": "DejaVu Sans",
    "svg.fonttype": "none",
    "svg.hashsalt": "goose-to-wasm-2026-11-26-throughput-v4",
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
    1, 2, figsize=(13.6, 5.0), gridspec_kw={"width_ratios": [1.16, 1.0]}, layout="constrained"
)
fig.suptitle(
    "Compiler throughput: up to 2.32M LOC/s wall & 2.59M LOC/s compile (100% SHA-256 bit-identical)",
    x=0.01, ha="left", fontsize=12.4, weight="bold", color=INK,
)

# Left panel: LOC/s scaling (matched unprofiled Clang 23 -O2 on Ryzen 7 7800X3D)
base_100k = paired["workloads"]["flat_multi_100k_o0"]["base"]
base_loc_m = base_100k["loc_per_sec"] / 1e6
base_cmp_m = base_100k["compile_loc_per_sec"] / 1e6

s_nopgo = scaling["nopgo"]["jobs"]
r250_j8 = next(r for r in scale250["runs"] if r["label"] == "batch4d-nopgo j=8")
r250_j12 = next(r for r in scale250["runs"] if r["label"] == "batch4d-nopgo j=12")

labels = [
    "v2026.4-3\n(1 core)",
    "New\n--jobs 1",
    "New\n--jobs 2",
    "New\n--jobs 4",
    "New\n--jobs 8\n(auto)",
    "247k LOC*\n--jobs 8",
    "247k LOC*\n--jobs 12",
]
wall_m = [
    base_loc_m,
    s_nopgo["1"]["wall_loc_per_sec"] / 1e6,
    s_nopgo["2"]["wall_loc_per_sec"] / 1e6,
    s_nopgo["4"]["wall_loc_per_sec"] / 1e6,
    s_nopgo["8"]["wall_loc_per_sec"] / 1e6,
    r250_j8["wall_loc_per_sec"] / 1e6,
    r250_j12["wall_loc_per_sec"] / 1e6,
]
cmp_m = [
    base_cmp_m,
    s_nopgo["1"]["compile_loc_per_sec"] / 1e6,
    s_nopgo["2"]["compile_loc_per_sec"] / 1e6,
    s_nopgo["4"]["compile_loc_per_sec"] / 1e6,
    s_nopgo["8"]["compile_loc_per_sec"] / 1e6,
    r250_j8["compile_loc_per_sec"] / 1e6,
    r250_j12["compile_loc_per_sec"] / 1e6,
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
        i - w / 2 - 0.03, wv + 0.045, f"{wv:.2f}",
        ha="center", va="bottom", fontsize=7.9, weight="bold", color=w_col,
        bbox={"facecolor": "#ffffff", "edgecolor": "none", "pad": 0.4, "alpha": 0.85},
    )
    ax1.text(
        i + w / 2 + 0.03, cv + 0.045, f"{cv:.2f}",
        ha="center", va="bottom", fontsize=7.9, color=c_col,
        bbox={"facecolor": "#ffffff", "edgecolor": "none", "pad": 0.4, "alpha": 0.85},
    )

ax1.axhline(1.50, color=SLATE, linestyle="--", linewidth=1.1, alpha=0.75)
ax1.text(0.02, 1.555, "1.50M LOC/s reference", fontsize=8.3, color=SLATE, style="italic")

ax1.set_title(
    "Multi-file Goose → Direct Wasm -O0 (98.7k LOC · *246.8k LOC scale ref · higher is faster)",
    fontsize=9.5, loc="left", color=INK, pad=8,
)
ax1.set_ylabel("Million LOC / second (unprofiled Clang 23 -O2)", color=INK)
ax1.set_xticks(x, labels=labels, fontsize=8.5, color=INK)
ax1.set_ylim(0, 3.12)
ax1.legend(
    handles=[
        Patch(facecolor=TEAL, label="End-to-end process wall (incl. OS/I/O)"),
        Patch(facecolor=NAVY, label="Compile stages (parse→check→opt→wasm)"),
        Patch(facecolor=UPSTREAM, label="v2026.4-3 baseline (1 core)"),
    ],
    frameon=False, fontsize=8.5, loc="upper left",
)
clean_ax(ax1, "y")

# Right panel: Real large codebases (Direct Wasm64 + Native C, matched unprofiled --jobs 8)
wls = [
    ("selfhost -O0\nWasm64", paired["workloads"]["selfhost_o0_wasm64"]),
    ("selfhost -O2\nWasm64", paired["workloads"]["selfhost_o2_wasm64"]),
    ("selfhost -O0\nNative C", cgen["workloads"]["selfhost_o0_c"]),
    ("blot2 -O0\nWasm64", paired["workloads"]["blot2_o0_wasm64"]),
    ("blot2 -O2\nWasm64", paired["workloads"]["blot2_o2_wasm64"]),
    ("blot2 -O0\nNative C", cgen["workloads"]["blot2_o0_c"]),
]
y = [i * 1.12 for i in range(len(wls))]
h = 0.40
b_vals = [row["base"]["median_wall_ms"] / 1000.0 for _, row in wls]
c_vals = [row["cand"]["median_wall_ms"] / 1000.0 for _, row in wls]

hb_base = ax2.barh([p - h / 2 for p in y], b_vals, height=h, color=UPSTREAM, label="v2026.4-3 (single-core)")
hb_cand = ax2.barh([p + h / 2 for p in y], c_vals, height=h, color=TEAL, label="New (default --jobs auto)")

ax2.bar_label(hb_base, labels=[f" {v:.2f} s" for v in b_vals], padding=3, fontsize=8.5, color=SLATE)
ax2.bar_label(
    hb_cand,
    labels=[f" {c:.2f} s  ({b/c:.2f}× faster)" for b, c in zip(b_vals, c_vals)],
    padding=3, fontsize=8.5, weight="bold", color=TEAL,
)

ax2.set_title(
    "Real codebases: selfhost (47.4k) & blot2 (79.0k) · seconds, lower is faster",
    fontsize=9.5, loc="left", color=INK, pad=22,
)
ax2.set_xlabel("Seconds (Blot2 backend: 6.4× Wasm / 6.9× C · -O2 opt: 7.0× · Peak RSS -12%..-50%)", fontsize=8.3, color=SLATE)
ax2.set_yticks(y, labels=[lbl for lbl, _ in wls], fontsize=8.6, color=INK)
ax2.invert_yaxis()
ax2.set_xlim(0, max(b_vals) * 1.44)
ax2.legend(frameon=False, fontsize=8.5, loc="lower left", bbox_to_anchor=(0.0, 1.005), ncol=2)
clean_ax(ax2, "x")

save(fig, "compiler_throughput")


# =============================================================================
# 2. stage_breakdown.svg — Per-stage wall-time breakdown (flat_multi_100k & real)
# =============================================================================
fig, (ax1, ax2) = plt.subplots(
    1, 2, figsize=(13.4, 4.6), gridspec_kw={"width_ratios": [1.14, 1.0]}, layout="constrained"
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
    ("backend_ms", "Backend (Wasm/C)", "#b4533c"),
    ("other_ms", "OS / I/O / exit", "#94a3b8"),
]


def extract_row(wall_ms: float, st: dict) -> list[float]:
    cmp_ms = st["parse_ms"] + st["typecheck_ms"] + st["optimize_ms"] + st["backend_ms"]
    other = max(0.0, wall_ms - cmp_ms)
    return [other if k == "other_ms" else st[k] for k, _, _ in STAGES]


# Left: flat_multi_100k_o0 progression
f_rows = [
    ("v2026.4-3 (j=1)", base_100k["median_wall_ms"], base_100k["stages_ms"]),
    ("New (j=1)", s_nopgo["1"]["median_wall_ms"], s_nopgo["1"]["stages_ms"]),
    ("New (j=2)", s_nopgo["2"]["median_wall_ms"], s_nopgo["2"]["stages_ms"]),
    ("New (j=4)", s_nopgo["4"]["median_wall_ms"], s_nopgo["4"]["stages_ms"]),
    ("New (j=8 auto)", s_nopgo["8"]["median_wall_ms"], s_nopgo["8"]["stages_ms"]),
    ("New (j=12)", s_nopgo["12"]["median_wall_ms"], s_nopgo["12"]["stages_ms"]),
]
fy = list(range(len(f_rows)))
left_acc = [0.0] * len(f_rows)
for idx, (key, label, color) in enumerate(STAGES):
    seg = [extract_row(w_ms, st)[idx] for _, w_ms, st in f_rows]
    ax1.barh(fy, seg, left=left_acc, height=0.60, color=color, label=label)
    left_acc = [a + b for a, b in zip(left_acc, seg)]

for i, (_, w_ms, _) in enumerate(f_rows):
    loc_s = 98749 / (w_ms / 1000.0) / 1e6
    ax1.text(w_ms + 4, i, f"{w_ms:.1f} ms ({loc_s:.2f}M/s)", va="center", fontsize=8.6, weight="bold", color=INK)

ax1.set_title("flat_multi_100k -O0 (98,749 LOC · ms, lower is faster)", fontsize=9.8, loc="left", color=INK, pad=8)
ax1.set_xlabel("Milliseconds (Peak RSS: 313 → 201 MiB at j=8, 141 MiB at j=1)", fontsize=8.5, color=SLATE)
ax1.set_yticks(fy, labels=[r[0] for r in f_rows], fontsize=8.9, color=INK)
ax1.invert_yaxis()
ax1.set_xlim(0, 385)
ax1.legend(frameon=False, fontsize=8.1, loc="lower right", ncol=2)
clean_ax(ax1, "x")

# Right: selfhost -O2 Wasm64, blot2 -O2 Wasm64, and blot2 -O0 Native C
r_rows = [
    ("selfhost -O2 Wasm\nv2026.4-3", paired["workloads"]["selfhost_o2_wasm64"]["base"]),
    ("selfhost -O2 Wasm\nNew j=8", paired["workloads"]["selfhost_o2_wasm64"]["cand"]),
    ("blot2 -O2 Wasm\nv2026.4-3", paired["workloads"]["blot2_o2_wasm64"]["base"]),
    ("blot2 -O2 Wasm\nNew j=8", paired["workloads"]["blot2_o2_wasm64"]["cand"]),
    ("blot2 -O0 Native C\nv2026.4-3", cgen["workloads"]["blot2_o0_c"]["base"]),
    ("blot2 -O0 Native C\nNew j=8", cgen["workloads"]["blot2_o0_c"]["cand"]),
]
ry = [0.0, 0.78, 1.88, 2.66, 3.76, 4.54]
left_acc2 = [0.0] * len(r_rows)
for idx, (key, label, color) in enumerate(STAGES):
    seg = [extract_row(d["median_wall_ms"], d["stages_ms"])[idx] for _, d in r_rows]
    ax2.barh(ry, seg, left=left_acc2, height=0.58, color=color)
    left_acc2 = [a + b for a, b in zip(left_acc2, seg)]

for i, (_, d) in enumerate(r_rows):
    w_ms = d["median_wall_ms"]
    ax2.text(w_ms + 75, ry[i], f"{w_ms/1000:.2f} s", va="center", fontsize=8.8, weight="bold", color=INK)

ax2.set_title("selfhost & blot2 stage breakdown (ms, lower is faster)", fontsize=9.8, loc="left", color=INK, pad=8)
ax2.set_xlabel("Milliseconds (Blot2 -O2 opt: 840→120 ms · Blot2 C backend: 1,722→251 ms)", fontsize=8.4, color=SLATE)
ax2.set_yticks(ry, labels=[r[0] for r in r_rows], fontsize=8.4, color=INK)
ax2.invert_yaxis()
ax2.set_xlim(0, 5600)
clean_ax(ax2, "x")

save(fig, "stage_breakdown")
print("Saved SVG charts to", DIR)
