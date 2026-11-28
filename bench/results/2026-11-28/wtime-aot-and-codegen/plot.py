#!/usr/bin/env python3
"""Generate clean SVG comparison charts for the 2026-11-28 wtime-aot & Direct Wasm codegen/BCE report.

Reads pinned measurements from ./results.json and writes:
  1. wasm_size_and_aot_build.svg   — Suite A: .wasm size, x64 ELF size, wtime-aot x64 cold build (Base vs Cand)
  2. runtime_comparison.svg        — Suite A: Wasmtime, wtime-aot x64 (Base vs Cand), and Native Clang -O2
  3. large_wasm64_comparison.svg   — Suite B: selfhost (57.5k LOC) & blot2 (79.0k LOC) sizes and build/self-compile times
  4. blot2_hosted_engines.svg      — Suite B: 84-import blot2 hosted execution (Winch vs goose-wtime-aot)
"""
from __future__ import annotations

import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

DIR = Path(__file__).resolve().parent
ROOT = DIR.parents[3]
PREVIEW = ROOT / "build" / "chart-preview"
PREVIEW.mkdir(parents=True, exist_ok=True)

data = json.loads((DIR / "results.json").read_text())

plt.rcParams.update({
    "font.size": 10.0,
    "font.family": "DejaVu Sans",
    "svg.fonttype": "none",
    "svg.hashsalt": "goose-to-wasm-2026-11-28-wtime-aot-codegen-v1",
    "axes.edgecolor": "#cbd5e1",
    "figure.facecolor": "#ffffff",
    "axes.facecolor": "#ffffff",
})

BASE_WARM = "#b4533c"
BASE_MUTED = "#94a3b8"
BASE_TEAL_LT = "#5eead4"
BASE_PURPLE_LT = "#c4b5fd"
TEAL = "#0f766e"
EMERALD = "#059669"
NAVY = "#1e3a5f"
BLUE = "#2563eb"
PURPLE = "#6d28d9"
AMBER = "#d97706"
SLATE = "#475569"
INK = "#0f172a"


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
# 1. wasm_size_and_aot_build.svg — Suite A: .wasm size, x64 ELF size, AOT build
# =============================================================================
sa_sz = data["suite_a_sizes_and_aot"]
exs6 = ["sorting", "life", "sudoku", "sieve", "maze", "mandelbrot"]
x6 = [i * 1.32 for i in range(len(exs6))]
w2 = 0.44
gap = 0.035

wasm_base_kb = [sa_sz[e]["base_wasm_bytes"] / 1000.0 for e in exs6]
wasm_cand_kb = [sa_sz[e]["cand_wasm_bytes"] / 1000.0 for e in exs6]
wasm_pct = [(c - b) / b * 100.0 for b, c in zip(wasm_base_kb, wasm_cand_kb)]

elf_base_kb = [sa_sz[e]["base_x64_bin_bytes"] / 1000.0 for e in exs6]
elf_cand_kb = [sa_sz[e]["cand_x64_bin_bytes"] / 1000.0 for e in exs6]
elf_pct = [(c - b) / b * 100.0 for b, c in zip(elf_base_kb, elf_cand_kb)]

aot_base_ms = [sa_sz[e]["base_aot_cold_ms"] for e in exs6]
aot_cand_ms = [sa_sz[e]["cand_aot_cold_ms"] for e in exs6]
aot_pct = [(c - b) / b * 100.0 for b, c in zip(aot_base_ms, aot_cand_ms)]

fig, (ax1, ax2, ax3) = plt.subplots(1, 3, figsize=(16.6, 5.2), layout="constrained")
fig.suptitle(
    "Direct Wasm codegen & BCE: -O2 binary sizes and wtime-aot x64 cold builds (lower is better)",
    x=0.01, ha="left", fontsize=12.8, weight="bold", color=INK,
)

HALO = {"facecolor": "#ffffff", "edgecolor": "none", "pad": 0.45, "alpha": 0.90}

# Panel 1: .wasm size (KB)
b1 = ax1.bar([i - w2 / 2 - gap for i in x6], wasm_base_kb, width=w2, color=BASE_MUTED, label="Baseline (e0d95bd)")
b2 = ax1.bar([i + w2 / 2 + gap for i in x6], wasm_cand_kb, width=w2, color=TEAL, label="Candidate (codegen + BCE)")
ax1.bar_label(b1, labels=[f"{v:.1f}" for v in wasm_base_kb], padding=3, fontsize=7.5, color=SLATE)
ax1.bar_label(b2, labels=[f"{v:.1f}\n({p:.1f}%)" for v, p in zip(wasm_cand_kb, wasm_pct)], padding=3, fontsize=7.2, weight="bold", color=TEAL, bbox=HALO)
ax1.set_title("Emitted -O2 .wasm size (KB)", fontsize=10.3, loc="left", color=INK, pad=8)
ax1.set_ylabel("Kilobytes (decimal)", color=SLATE)
ax1.set_xticks(x6, labels=exs6, fontsize=8.8, color=INK, rotation=14, ha="right")
ax1.set_ylim(0, max(wasm_base_kb) * 1.30)
ax1.legend(frameon=False, fontsize=8.4, loc="upper right")
clean_ax(ax1, "y")

# Panel 2: wtime-aot x64 static ELF size (KB)
b3 = ax2.bar([i - w2 / 2 - gap for i in x6], elf_base_kb, width=w2, color=BASE_MUTED, label="Baseline (e0d95bd)")
b4 = ax2.bar([i + w2 / 2 + gap for i in x6], elf_cand_kb, width=w2, color=NAVY, label="Candidate (codegen + BCE)")
ax2.bar_label(b3, labels=[f"{v:.1f}" for v in elf_base_kb], padding=3, fontsize=7.4, color=SLATE)
ax2.bar_label(b4, labels=[f"{v:.1f}\n({p:.1f}%)" for v, p in zip(elf_cand_kb, elf_pct)], padding=3, fontsize=7.1, weight="bold", color=NAVY, bbox=HALO)
ax2.set_title("wtime-aot x64 static ELF size (KB)", fontsize=10.3, loc="left", color=INK, pad=8)
ax2.set_ylabel("Kilobytes (decimal)", color=SLATE)
ax2.set_xticks(x6, labels=exs6, fontsize=8.8, color=INK, rotation=14, ha="right")
ax2.set_ylim(0, max(elf_base_kb) * 1.30)
ax2.legend(frameon=False, fontsize=8.4, loc="upper right")
clean_ax(ax2, "y")

# Panel 3: wtime-aot x64 cold build time (ms)
b5 = ax3.bar([i - w2 / 2 - gap for i in x6], aot_base_ms, width=w2, color=BASE_MUTED, label="Baseline (e0d95bd)")
b6 = ax3.bar([i + w2 / 2 + gap for i in x6], aot_cand_ms, width=w2, color=PURPLE, label="Candidate (codegen + BCE)")
ax3.bar_label(b5, labels=[f"{v:.1f}" for v in aot_base_ms], padding=3, fontsize=7.5, color=SLATE)
ax3.bar_label(b6, labels=[f"{v:.1f}\n({p:.1f}%)" for v, p in zip(aot_cand_ms, aot_pct)], padding=3, fontsize=7.2, weight="bold", color=PURPLE, bbox=HALO)
ax3.set_title("wtime-aot --backend x64 cold build (ms, CPU 7)", fontsize=10.3, loc="left", color=INK, pad=8)
ax3.set_ylabel("Milliseconds (median of 3 alt. rounds)", color=SLATE)
ax3.set_xticks(x6, labels=exs6, fontsize=8.8, color=INK, rotation=14, ha="right")
ax3.set_ylim(0, max(aot_base_ms) * 1.30)
ax3.legend(frameon=False, fontsize=8.4, loc="upper right")
clean_ax(ax3, "y")

save(fig, "wasm_size_and_aot_build")


# =============================================================================
# 2. runtime_comparison.svg — Suite A: Wasmtime, wtime-aot x64, Native -O2
# =============================================================================
sa_rt = data["suite_a_runtime"]
rt_exs = ["sorting", "life", "sudoku", "sieve", "maze"]
rx = [i * 1.28 for i in range(len(rt_exs))]
w5 = 0.205

wt_base = [sa_rt[e]["base_wasmtime"]["median_wall_s"] * 1000.0 for e in rt_exs]
wt_cand = [sa_rt[e]["cand_wasmtime"]["median_wall_s"] * 1000.0 for e in rt_exs]
x64_base = [sa_rt[e]["base_wtime_aot_x64"]["median_wall_s"] * 1000.0 for e in rt_exs]
x64_cand = [sa_rt[e]["cand_wtime_aot_x64"]["median_wall_s"] * 1000.0 for e in rt_exs]
nat_cand = [sa_rt[e]["cand_native_o2"]["median_wall_s"] * 1000.0 for e in rt_exs]

fig, (ax_r, ax_m) = plt.subplots(
    1, 2, figsize=(15.2, 4.9), gridspec_kw={"width_ratios": [1.85, 1.0]}, layout="constrained"
)
fig.suptitle(
    "Suite A runtime speed: Baseline vs Candidate across Wasmtime, wtime-aot x64, and Native -O2 (CPU 7, lower is faster)",
    x=0.01, ha="left", fontsize=12.4, weight="bold", color=INK,
)

r1 = ax_r.bar([i - 2 * w5 for i in rx], wt_base, width=w5 * 0.92, color=BASE_TEAL_LT, edgecolor=TEAL, linewidth=0.6, label="Wasmtime · Baseline (cached .cwasm)*")
r2 = ax_r.bar([i - 1 * w5 for i in rx], wt_cand, width=w5 * 0.92, color=TEAL, label="Wasmtime · Candidate (cached .cwasm)*")
r3 = ax_r.bar([i + 0 * w5 for i in rx], x64_base, width=w5 * 0.92, color=BASE_PURPLE_LT, edgecolor=PURPLE, linewidth=0.6, label="wtime-aot x64 · Baseline (static ELF)")
r4 = ax_r.bar([i + 1 * w5 for i in rx], x64_cand, width=w5 * 0.92, color=PURPLE, label="wtime-aot x64 · Candidate (static ELF)")
r5 = ax_r.bar([i + 2 * w5 for i in rx], nat_cand, width=w5 * 0.92, color=NAVY, label="Native Clang -O2 · Candidate (ref.)")

ax_r.bar_label(r1, labels=[f"{v:.1f}" for v in wt_base], padding=2.5, fontsize=7.2, color=SLATE)
ax_r.bar_label(r2, labels=[f"{v:.1f}" for v in wt_cand], padding=2.5, fontsize=7.2, weight="bold", color=TEAL)
ax_r.bar_label(r3, labels=[f"{v:.1f}" for v in x64_base], padding=2.5, fontsize=7.2, color=SLATE)
ax_r.bar_label(r4, labels=[f"{v:.1f}" for v in x64_cand], padding=2.5, fontsize=7.2, weight="bold", color=PURPLE)
ax_r.bar_label(r5, labels=[f"{v:.1f}" for v in nat_cand], padding=2.5, fontsize=7.2, weight="bold", color=NAVY)

ax_r.set_title("5 Example programs (ms, median of 5 alt. rounds · *Wasmtime in-process, others whole-process)", fontsize=9.8, loc="left", color=INK)
ax_r.set_ylabel("Milliseconds", color=SLATE)
ax_r.set_xticks(rx, labels=rt_exs, fontsize=10.0, color=INK)
ax_r.set_ylim(0, max(max(wt_base), max(x64_base), max(nat_cand)) * 1.32)
ax_r.legend(frameon=False, fontsize=8.3, loc="upper right", ncol=1)
clean_ax(ax_r, "y")

mb = sa_rt["mandelbrot"]
mb_rows = [
    ("Wasmtime\nBase", mb["base_wasmtime"]["median_wall_s"], BASE_TEAL_LT, TEAL),
    ("Wasmtime\nCand", mb["cand_wasmtime"]["median_wall_s"], TEAL, TEAL),
    ("wtime x64\nBase", mb["base_wtime_aot_x64"]["median_wall_s"], BASE_PURPLE_LT, PURPLE),
    ("wtime x64\nCand", mb["cand_wtime_aot_x64"]["median_wall_s"], PURPLE, PURPLE),
    ("Native -O2\nCand (ref)", mb["cand_native_o2"]["median_wall_s"], NAVY, NAVY),
]
mx = list(range(len(mb_rows)))
mvals = [r[1] for r in mb_rows]
mbars = ax_m.bar(mx, mvals, width=0.58, color=[r[2] for r in mb_rows], edgecolor=[r[3] for r in mb_rows], linewidth=0.8)
ax_m.bar_label(mbars, labels=[f"{v:.3f} s" for v in mvals], padding=4, fontsize=8.5, weight="bold", color=INK)
ax_m.set_title("Mandelbrot 2048×2048 (kernel clock, checksum 1038538536)", fontsize=9.8, loc="left", color=INK)
ax_m.set_ylabel("Seconds", color=SLATE)
ax_m.set_xticks(mx, labels=[r[0] for r in mb_rows], fontsize=8.5, color=INK)
ax_m.set_ylim(0, max(mvals) * 1.24)
clean_ax(ax_m, "y")

save(fig, "runtime_comparison")


# =============================================================================
# 3. large_wasm64_comparison.svg — Suite B: selfhost (57.5k) & blot2 (79.0k)
# =============================================================================
sb = data["suite_b_large_wasm64"]
sh = sb["selfhost64"]
bl = sb["blot2"]

fig, (ax1, ax2) = plt.subplots(
    1, 2, figsize=(14.4, 4.9), gridspec_kw={"width_ratios": [1.0, 1.22]}, layout="constrained"
)
fig.suptitle(
    "Suite B large Wasm64 workloads: selfhost (57.5k LOC) & blot2 (79.0k LOC, 84 imports) — Baseline vs Candidate",
    x=0.01, ha="left", fontsize=12.4, weight="bold", color=INK,
)

# Left panel: Emitted Wasm64 size (MiB)
sz_rows = [
    ("selfhost -O2\n(57.5k LOC)", sh["base_wasm_bytes"] / 1048576.0, sh["cand_wasm_bytes"] / 1048576.0, sh["wasm_delta_pct"]),
    ("blot2 -O0\n(79.0k LOC)", bl["base_o0_bytes"] / 1048576.0, bl["cand_o0_bytes"] / 1048576.0, bl["o0_delta_pct"]),
    ("blot2 -O2\n(79.0k LOC)", bl["base_o2_bytes"] / 1048576.0, bl["cand_o2_bytes"] / 1048576.0, bl["o2_delta_pct"]),
]
sy = [i * 1.15 for i in range(len(sz_rows))]
bh = 0.40
sb1 = ax1.barh([p - bh / 2 for p in sy], [r[1] for r in sz_rows], height=bh * 0.92, color=BASE_MUTED, label="Baseline (e0d95bd)")
sb2 = ax1.barh([p + bh / 2 for p in sy], [r[2] for r in sz_rows], height=bh * 0.92, color=TEAL, label="Candidate (codegen + BCE)")
ax1.bar_label(sb1, labels=[f" {r[1]:.2f} MiB" for r in sz_rows], padding=4, fontsize=8.4, color=SLATE)
ax1.bar_label(sb2, labels=[f" {r[2]:.2f} MiB  ({r[3]:+.1f}%)" for r in sz_rows], padding=4, fontsize=8.5, weight="bold", color=TEAL)
ax1.set_title("Emitted Wasm64 module size (MiB, lower is smaller)", fontsize=10.1, loc="left", color=INK, pad=28)
ax1.set_xlabel("MiB (100% bit-exact output across engines)", fontsize=8.4, color=SLATE)
ax1.set_yticks(sy, labels=[r[0] for r in sz_rows], fontsize=8.9, color=INK)
ax1.invert_yaxis()
ax1.set_xlim(0, max(r[1] for r in sz_rows) * 1.46)
ax1.legend(frameon=False, fontsize=8.4, loc="lower left", bbox_to_anchor=(-0.01, 1.015), ncol=2)
clean_ax(ax1, "x")

# Right panel: Compile, AOT build, and standalone self-compile times (seconds)
tm_rows = [
    ("selfhost -O2 emit\n(--jobs 8, unpinned)", sh["emit_o2_8j"]["base_selfhost_o2"]["median_wall_s"], sh["emit_o2_8j"]["cand_selfhost_o2"]["median_wall_s"]),
    ("selfhost x64 self-compile\n(standalone ELF, CPU 7)", sh["self_compile_x64_run"]["base_selfhost_x64_run"]["median_wall_s"], sh["self_compile_x64_run"]["cand_selfhost_x64_run"]["median_wall_s"]),
    ("selfhost wtime-aot x64\n(cold build, CPU 7)", sh["wtime_aot_x64_build"]["base_x64_aot"]["median_wall_s"], sh["wtime_aot_x64_build"]["cand_x64_aot"]["median_wall_s"]),
    ("blot2 -O0 emit\n(--jobs 8, unpinned)", bl["emit_o0_8j"]["base_blot2_o0"]["median_wall_s"], bl["emit_o0_8j"]["cand_blot2_o0"]["median_wall_s"]),
    ("blot2 -O2 emit\n(--jobs 8, unpinned)", bl["emit_o2_8j"]["base_blot2_o2"]["median_wall_s"], bl["emit_o2_8j"]["cand_blot2_o2"]["median_wall_s"]),
]
ty = [i * 1.15 for i in range(len(tm_rows))]
tb1 = ax2.barh([p - bh / 2 for p in ty], [r[1] for r in tm_rows], height=bh * 0.92, color=BASE_MUTED, label="Baseline (e0d95bd)")
tb2 = ax2.barh([p + bh / 2 for p in ty], [r[2] for r in tm_rows], height=bh * 0.92, color=NAVY, label="Candidate (codegen + BCE)")
ax2.bar_label(tb1, labels=[f" {r[1]:.3f} s" for r in tm_rows], padding=4, fontsize=8.2, color=SLATE)
ax2.bar_label(
    tb2,
    labels=[f" {r[2]:.3f} s  ({(r[2]-r[1])/r[1]*100.0:+.1f}%)" for r in tm_rows],
    padding=4, fontsize=8.3, weight="bold", color=NAVY,
)
ax2.set_title("Compile, AOT build & standalone self-compile times (seconds, median of 3 alt. rounds)", fontsize=10.1, loc="left", color=INK, pad=28)
ax2.set_xlabel(f"Seconds · selfhost aarch64 cross-AOT: {sh['cand_aarch64_aot_ms']/1000.0:.2f} s ({sh['cand_aarch64_bin_bytes']/1048576.0:.2f} MiB static ELF)", fontsize=8.3, color=SLATE)
ax2.set_yticks(ty, labels=[r[0] for r in tm_rows], fontsize=8.6, color=INK)
ax2.invert_yaxis()
ax2.set_xlim(0, max(max(r[1], r[2]) for r in tm_rows) * 1.46)
ax2.legend(frameon=False, fontsize=8.4, loc="lower left", bbox_to_anchor=(-0.01, 1.015), ncol=2)
clean_ax(ax2, "x")

save(fig, "large_wasm64_comparison")


# =============================================================================
# 4. blot2_hosted_engines.svg — Suite B: Hosted 84-import blot2 (CPU 7)
# =============================================================================
bc = bl["cases"]
bnames = [("fibonacci", "fibonacci.blot\n(sha e60d8276e536…)"), ("matrix_multiply", "matrix_multiply.blot\n(sha 1c9da72962f9…)")]

fig, (ax1, ax2) = plt.subplots(
    1, 2, figsize=(14.0, 4.4), gridspec_kw={"width_ratios": [1.35, 1.0]}, layout="constrained"
)
fig.suptitle(
    "84-import blot2 Wasm64 hosted execution: goose-wasmtime (Winch) vs goose-wtime-aot (CPU 7, bit-exact)",
    x=0.01, ha="left", fontsize=12.4, weight="bold", color=INK,
)

# Left panel: All 4 modes (cold + warm, ms)
engines = [
    ("goose-wtime-aot · O2 cold", "wtime_aot_o2_cand_o2_cold", AMBER),
    ("goose-wtime-aot --fast · -O0 cold", "wtime_aot_fast_cand_o0_cold", PURPLE),
    ("goose-wasmtime Winch · -O0 cold", "winch_cand_o0_cold", BLUE),
    ("goose-wtime-aot · O2 --cache warm", "wtime_aot_o2_cand_o2_warm", EMERALD),
]
ey = [i * 1.15 for i in range(len(engines))]
eh = 0.40

fib_ms = [bc["fibonacci"]["runs"][k]["median_wall_s"] * 1000.0 for _, k, _ in engines]
mat_ms = [bc["matrix_multiply"]["runs"][k]["median_wall_s"] * 1000.0 for _, k, _ in engines]

eb1 = ax1.barh([p - eh / 2 for p in ey], fib_ms, height=eh * 0.92, color=TEAL, label="fibonacci.blot")
eb2 = ax1.barh([p + eh / 2 for p in ey], mat_ms, height=eh * 0.92, color=NAVY, label="matrix_multiply.blot")
ax1.bar_label(eb1, labels=[f" {v:,.1f} ms" for v in fib_ms], padding=4, fontsize=8.3, weight="bold", color=TEAL)
ax1.bar_label(eb2, labels=[f" {v:,.1f} ms" for v in mat_ms], padding=4, fontsize=8.3, weight="bold", color=NAVY)
ax1.set_title("End-to-end compile + instantiate + run wall time (ms, single CPU 7)", fontsize=10.0, loc="left", color=INK, pad=28)
ax1.set_xlabel("Milliseconds (single-core pinned; median of 3 alternating rounds)", fontsize=8.3, color=SLATE)
ax1.set_yticks(ey, labels=[lbl for lbl, _, _ in engines], fontsize=8.8, color=INK)
ax1.invert_yaxis()
ax1.set_xlim(0, max(max(fib_ms), max(mat_ms)) * 1.32)
ax1.legend(frameon=False, fontsize=8.6, loc="lower left", bbox_to_anchor=(-0.01, 1.015), ncol=2)
clean_ax(ax1, "x")

# Right panel: Zoom on fast dev loop (Winch cold vs wtime-aot --fast cold vs wtime-aot --cache warm)
zoom_keys = [
    ("Winch -O0\ncold", "winch_cand_o0_cold", BLUE),
    ("wtime-aot\n--fast cold", "wtime_aot_fast_cand_o0_cold", PURPLE),
    ("wtime-aot O2\n--cache warm", "wtime_aot_o2_cand_o2_warm", EMERALD),
]
zx = [i * 1.15 for i in range(len(zoom_keys))]
zw = 0.40
zf = [bc["fibonacci"]["runs"][k]["median_wall_s"] * 1000.0 for _, k, _ in zoom_keys]
zm = [bc["matrix_multiply"]["runs"][k]["median_wall_s"] * 1000.0 for _, k, _ in zoom_keys]

zb1 = ax2.bar([i - zw / 2 for i in zx], zf, width=zw * 0.92, color=TEAL, label="fibonacci.blot")
zb2 = ax2.bar([i + zw / 2 for i in zx], zm, width=zw * 0.92, color=NAVY, label="matrix_multiply.blot")
ax2.bar_label(zb1, labels=[f"{v:,.0f}" if v >= 200 else f"{v:.1f}" for v in zf], padding=3, fontsize=8.3, weight="bold", color=TEAL)
ax2.bar_label(zb2, labels=[f"{v:,.0f}" if v >= 200 else f"{v:.1f}" for v in zm], padding=3, fontsize=8.3, weight="bold", color=NAVY)
ax2.set_title("Interactive turnaround zoom: cold --fast vs warm --cache (ms)", fontsize=10.0, loc="left", color=INK, pad=28)
ax2.set_ylabel("Milliseconds (CPU 7)", color=SLATE)
ax2.set_xticks(zx, labels=[lbl for lbl, _, _ in zoom_keys], fontsize=8.8, color=INK)
ax2.set_ylim(0, max(max(zf), max(zm)) * 1.24)
ax2.legend(frameon=False, fontsize=8.5, loc="upper right")
clean_ax(ax2, "y")

save(fig, "blot2_hosted_engines")
