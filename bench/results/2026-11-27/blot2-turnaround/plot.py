#!/usr/bin/env python3
"""Generate clean consumer & technical SVG charts for the 2026-11-27 Blot2 turnaround campaign."""
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

blot = json.loads((DIR / "blot2_turnaround.json").read_text())
paired_nopgo = json.loads((DIR / "paired_nopgo_j8.json").read_text())
paired_pgo = json.loads((DIR / "paired_pgo_j8.json").read_text())
selfhost_nopgo = json.loads((DIR / "paired_selfhost_nopgo_j8.json").read_text())
v4 = json.loads((ROOT / "bench/results/2026-11-25/release-v2026.4-4/results.json").read_text())
blot_nov25 = json.loads((ROOT / "bench/results/2026-11-25/blot2-head-98f277f2/metrics.json").read_text())

plt.rcParams.update({
    "font.size": 10.2,
    "font.family": "DejaVu Sans",
    "svg.fonttype": "none",
    "svg.hashsalt": "goose-to-wasm-2026-11-27-blot2",
    "axes.edgecolor": "#cbd5e1",
    "figure.facecolor": "#ffffff",
    "axes.facecolor": "#ffffff",
})

UPSTREAM = "#b4533c"
UPSTREAM_LT = "#d0826f"
TEAL = "#0f766e"
TEAL_LT = "#14b8a6"
NAVY = "#1e3a5f"
BLUE = "#2563eb"
AMBER = "#d97706"
SLATE = "#475569"
INK = "#0f172a"


def save(fig, stem: str) -> None:
    fig.savefig(PREVIEW / f"{stem}.png", dpi=150, bbox_inches="tight", pad_inches=0.22)
    svg = DIR / f"{stem}.svg"
    fig.savefig(svg, metadata={"Date": None}, bbox_inches="tight", pad_inches=0.22)
    svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
    plt.close(fig)


def clean_ax(ax, grid_axis: str = "x") -> None:
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=6)
    ax.set_axisbelow(True)
    ax.grid(axis=grid_axis, color="#e2e8f0", linewidth=0.9)


# =============================================================================
# 1. large_codebase_turnaround.svg — README Section 2 updated consumer chart
# =============================================================================
s1 = v4["suite1_selfcompile"]
up_chk = s1["upstream_check"]["median_wall_s"]
up_emit = s1["upstream_emit_c"]["median_wall_s"]
gw_chk = s1["g2w_check"]["median_wall_s"]
gw_wasm_nopgo = selfhost_nopgo["workloads"]["selfhost_o0_wasm64"]["cand"]["median_wall_ms"] / 1000.0
gw_wasm_pgo = paired_pgo["workloads"]["selfhost_o0_wasm64"]["cand"]["median_wall_ms"] / 1000.0
gw_wasm_o2_nopgo = selfhost_nopgo["workloads"]["selfhost_o2_wasm64"]["cand"]["median_wall_ms"] / 1000.0

b_up_chk = blot_nov25["upstream_check_pin7"]["median_s"]
b_up_rel = 98.831
b_up_dbg = 30.64
b_nov25_dev = blot_nov25["emit_wasm64_O0_pin7"]["median_s"] + blot_nov25["wasmtime_cold_O0_unpinned"]["median_s"]
b_now_chk = blot["blot2_emit"]["final_nopgo_check_patched"]["median_ms"] / 1000.0
b_now_nopgo = (blot["blot2_emit"]["final_nopgo_emit_o0"]["median_ms"] +
               blot["blot2_jit_and_run"]["cold_final_o0_fast_jit"]["median_ms"]) / 1000.0
b_now_pgo = (blot["blot2_emit"]["final_pgo_emit_o0"]["median_ms"] +
             blot["blot2_jit_and_run"]["cold_final_o0_fast_jit"]["median_ms"]) / 1000.0
b_cache_hit = blot["blot2_incremental_cache"]["final_nopgo"]["warm_hit_o0_same_out"]["median_ms"] / 1000.0

fig, (ax1, ax2) = plt.subplots(
    1, 2, figsize=(13.2, 4.9), gridspec_kw={"width_ratios": [1.0, 1.22]}, layout="constrained"
)
fig.suptitle(
    "Large real-world Goose codebases: edit-compile-run turnaround (seconds, lower is faster)",
    x=0.01, ha="left", fontsize=12.6, weight="bold", color=INK,
)

left_rows = [
    ("Upstream C++ · check", up_chk, UPSTREAM_LT, f"{up_chk:.2f} s"),
    ("goosew · --check", gw_chk, NAVY, f"{gw_chk:.2f} s  ({up_chk/gw_chk:.1f}× faster)"),
    ("Upstream C++ · emit C (-O2)", up_emit, UPSTREAM, f"{up_emit:.2f} s"),
    ("goosew · Wasm64 -O2 (--jobs 8)", gw_wasm_o2_nopgo, BLUE, f"{gw_wasm_o2_nopgo:.2f} s  ({up_emit/gw_wasm_o2_nopgo:.1f}× faster)"),
    ("goosew · Wasm64 -O0 (--jobs 8)", gw_wasm_nopgo, TEAL, f"{gw_wasm_nopgo:.2f} s  ({up_emit/gw_wasm_nopgo:.1f}× faster)"),
    ("goosew · Wasm64 -O0 (PGO*)", gw_wasm_pgo, TEAL_LT, f"{gw_wasm_pgo:.2f} s  ({up_emit/gw_wasm_pgo:.1f}× faster)"),
]
ly = [0.0, 0.82, 1.92, 2.74, 3.56, 4.38]
lbars = ax1.barh(ly, [r[1] for r in left_rows], height=0.60, color=[r[2] for r in left_rows])
ax1.bar_label(lbars, labels=[f" {r[3]}" for r in left_rows], padding=4, fontsize=8.8, weight="bold", color=INK)
ax1.set_title("Our own compiler (selfhost/, 47.4k LOC)", fontsize=10.4, loc="left", color=INK, pad=8)
ax1.set_xlabel("Seconds (*fresh Clang-23 PGO ref. run; unprofiled matched)", fontsize=8.5, color=SLATE)
ax1.set_yticks(ly, labels=[r[0] for r in left_rows], fontsize=8.9, color=INK)
ax1.invert_yaxis()
ax1.set_xlim(0, up_emit * 1.54)
clean_ax(ax1, "x")

right_rows = [
    ("Upstream + Clang -O2 (release)*", b_up_rel, UPSTREAM, f"{b_up_rel:.1f} s"),
    ("Upstream + Clang -O0 (debug)*", b_up_dbg, UPSTREAM_LT, f"{b_up_dbg:.1f} s"),
    ("Upstream C++ · check", b_up_chk, "#e09f8f", f"{b_up_chk:.1f} s"),
    ("Nov 25 Direct Wasm64 + JIT (-O0)", b_nov25_dev, AMBER, f"{b_nov25_dev:.2f} s  (3.84 + 2.40 s)"),
    ("Now: Wasm64 + --fast-jit (-O0)", b_now_nopgo, TEAL, f"{b_now_nopgo:.2f} s  ({b_up_dbg/b_now_nopgo:.0f}×–{b_up_rel/b_now_nopgo:.0f}× faster)"),
    ("Now: Wasm64 + --fast-jit (PGO*)", b_now_pgo, TEAL_LT, f"{b_now_pgo:.2f} s  ({b_up_dbg/b_now_pgo:.0f}×–{b_up_rel/b_now_pgo:.0f}× faster)"),
    ("Now: goosew --check", b_now_chk, NAVY, f"{b_now_chk:.2f} s  ({b_up_chk/b_now_chk:.1f}× vs upstream)"),
    ("Now: --cache-dir (unchanged)", b_cache_hit, BLUE, f"{b_cache_hit*1000:.0f} ms  (41 ms --check)"),
]
ry = [0.0, 0.78, 1.56, 2.52, 3.30, 4.08, 4.86, 5.64]
rbars = ax2.barh(ry, [r[1] for r in right_rows], height=0.58, color=[r[2] for r in right_rows])
ax2.bar_label(rbars, labels=[f" {r[3]}" for r in right_rows], padding=4, fontsize=8.7, weight="bold", color=INK)
ax2.set_title("mewhhaha/blot2 compiler (79.0k LOC · 16/16 bit-exact)", fontsize=10.4, loc="left", color=INK, pad=8)
ax2.set_xlabel("Seconds (*separate ref. C / PGO runs · Now -O0: 2.10 s / 1.95 s emit + 0.69 s JIT+run)", fontsize=8.3, color=SLATE)
ax2.set_yticks(ry, labels=[r[0] for r in right_rows], fontsize=8.8, color=INK)
ax2.invert_yaxis()
ax2.set_xlim(0, b_up_rel * 1.46)
clean_ax(ax2, "x")

save(fig, "large_codebase_turnaround")


# =============================================================================
# 2. blot2_turnaround_breakdown.svg — Emit + JIT/Run stacked breakdown & Size/RSS
# =============================================================================
fig, (ax1, ax2) = plt.subplots(
    1, 2, figsize=(13.6, 5.1), gridspec_kw={"width_ratios": [1.32, 1.0]}, layout="constrained"
)
fig.suptitle(
    "Blot2 HEAD 98f277f2 turnaround breakdown: from 6.24 s (-O0) / 9.11 s (-O2) down to 2.63–2.79 s",
    x=0.01, ha="left", fontsize=12.2, weight="bold", color=INK,
)

# Left panel: stacked Emit + Cold JIT/Run
b4d_o0_emit = paired_nopgo["workloads"]["blot2_o0_wasm64"]["base"]["median_wall_ms"] / 1000.0
fin_o0_emit = blot["blot2_emit"]["final_nopgo_emit_o0"]["median_ms"] / 1000.0
fin_o0_pgo = blot["blot2_emit"]["final_pgo_emit_o0"]["median_ms"] / 1000.0
fin_o2_emit = blot["blot2_emit"]["final_nopgo_emit_o2"]["median_ms"] / 1000.0
fin_o2_pgo = blot["blot2_emit"]["final_pgo_emit_o2"]["median_ms"] / 1000.0

jit = blot["blot2_jit_and_run"]
stack_rows = [
    ("Nov 25 -O0\n(speed JIT)", blot_nov25["emit_wasm64_O0_pin7"]["median_s"], blot_nov25["wasmtime_cold_O0_unpinned"]["median_s"]),
    ("Nov 26 Batch 4D -O0\n(speed JIT)", b4d_o0_emit, jit["cold_batch4d_o0_speed"]["median_ms"] / 1000.0),
    ("Final unprof. -O0\n(speed JIT)", fin_o0_emit, jit["cold_final_o0_speed"]["median_ms"] / 1000.0),
    ("Final unprof. -O0\n(--fast-jit)", fin_o0_emit, jit["cold_final_o0_fast_jit"]["median_ms"] / 1000.0),
    ("Final PGO* -O0\n(--fast-jit)", fin_o0_pgo, jit["cold_final_o0_fast_jit"]["median_ms"] / 1000.0),
    ("Nov 25 -O2\n(speed JIT)", blot_nov25["emit_wasm64_O2_pin7"]["median_s"], blot_nov25["wasmtime_cold_O2_unpinned"]["median_s"]),
    ("Final unprof. -O2\n(--fast-jit)", fin_o2_emit, jit["cold_final_o2_fast_jit"]["median_ms"] / 1000.0),
    ("Final PGO* -O2\n(--fast-jit)", fin_o2_pgo, jit["cold_final_o2_fast_jit"]["median_ms"] / 1000.0),
    ("Nov 25 -O2 +\nwtime register", blot_nov25["emit_wasm64_O2_pin7"]["median_s"], 3.733),
    ("Final unprof. -O2 +\nwtime register", fin_o2_emit, jit["wtime_register_final_o2"]["median_ms"] / 1000.0),
]

sy = [0.0, 0.85, 1.70, 2.55, 3.40, 4.55, 5.40, 6.25, 7.40, 8.25]
emits = [r[1] for r in stack_rows]
runs = [r[2] for r in stack_rows]
ax1.barh(sy, emits, height=0.62, color=NAVY, label="Compile to Direct Wasm64")
ax1.barh(sy, runs, left=emits, height=0.62, color=TEAL, label="Cold JIT/decode + run (fibonacci.blot)")

for yv, e, r in zip(sy, emits, runs):
    tot = e + r
    ax1.text(tot + 0.14, yv, f"{tot:.2f} s  ({e:.2f} + {r:.2f})", va="center", fontsize=8.4, weight="bold", color=INK)

ax1.set_title("Cold edit → compile → run turnaround (seconds, lower is faster)", fontsize=9.8, loc="left", color=INK, pad=22)
ax1.set_xlabel("Seconds (*fresh Clang-23 PGO ref. run · Warm .cwasm: 72 ms · --cache-dir: 71 ms)", fontsize=8.4, color=SLATE)
ax1.set_yticks(sy, labels=[r[0] for r in stack_rows], fontsize=8.4, color=INK)
ax1.invert_yaxis()
ax1.set_xlim(0, 12.2)
ax1.legend(frameon=False, fontsize=8.3, loc="lower left", bbox_to_anchor=(0.0, 1.005), ncol=2)
clean_ax(ax1, "x")

# Right panel: Wasm64 size & Host Peak RSS before vs after
ws = blot["wasm_sizes"]
metrics = [
    ("Wasm64 -O0\n(MiB)", ws["batch4d_o0_bytes"] / 1048576.0, ws["final_o0_bytes"] / 1048576.0, "MiB"),
    ("Wasm64 -O2\n(MiB)", ws["batch4d_o2_bytes"] / 1048576.0, ws["final_o2_bytes"] / 1048576.0, "MiB"),
    ("JIT -O0\nPeak RSS\n(×0.01 GiB)", jit["cold_batch4d_o0_speed"]["median_max_rss_mib"] / 102.4,
     jit["cold_final_o0_fast_jit"]["median_max_rss_mib"] / 102.4, "rss"),
    ("JIT -O2\nPeak RSS\n(×0.01 GiB)", jit["cold_batch4d_o2_speed"]["median_max_rss_mib"] / 102.4,
     jit["cold_final_o2_fast_jit"]["median_max_rss_mib"] / 102.4, "rss"),
    ("wtime -O2\nPeak RSS\n(×0.01 GiB)", jit["wtime_register_batch4d_o2"]["median_max_rss_mib"] / 102.4,
     jit["wtime_register_final_o2"]["median_max_rss_mib"] / 102.4, "rss"),
]
# Plot normalized % of baseline so MiB and RSS sit cleanly on one readable chart with exact labels!
pct_labels = [
    ("Wasm64 -O0 size", ws["batch4d_o0_bytes"]/1048576.0, ws["final_o0_bytes"]/1048576.0, "MiB"),
    ("Wasm64 -O2 size", ws["batch4d_o2_bytes"]/1048576.0, ws["final_o2_bytes"]/1048576.0, "MiB"),
    ("Wasmtime -O0 JIT", jit["cold_batch4d_o0_speed"]["median_ms"]/1000.0, jit["cold_final_o0_fast_jit"]["median_ms"]/1000.0, "s"),
    ("Wasmtime -O0 RSS", jit["cold_batch4d_o0_speed"]["median_max_rss_mib"], jit["cold_final_o0_fast_jit"]["median_max_rss_mib"], "MiB"),
    ("Wasmtime -O2 JIT", jit["cold_batch4d_o2_speed"]["median_ms"]/1000.0, jit["cold_final_o2_fast_jit"]["median_ms"]/1000.0, "s"),
    ("Wasmtime -O2 RSS", jit["cold_batch4d_o2_speed"]["median_max_rss_mib"], jit["cold_final_o2_fast_jit"]["median_max_rss_mib"], "MiB"),
    ("wtime -O2 run", jit["wtime_register_batch4d_o2"]["median_ms"]/1000.0, jit["wtime_register_final_o2"]["median_ms"]/1000.0, "s"),
    ("wtime -O2 RSS", jit["wtime_register_batch4d_o2"]["median_max_rss_mib"], jit["wtime_register_final_o2"]["median_max_rss_mib"], "MiB"),
]
py = list(range(len(pct_labels)))
h = 0.36
pct_after = [100.0 * after / before for _, before, after, _ in pct_labels]
ax2.barh([p - h/2 for p in py], [100.0] * len(py), height=h, color=UPSTREAM_LT, label="Before (Batch 4D / speed JIT = 100%)")
ax2.barh([p + h/2 for p in py], pct_after, height=h, color=TEAL, label="After (de-bloated Wasm64 + --fast-jit)")

for i, (_, before, after, unit) in enumerate(pct_labels):
    delta = (after - before) / before * 100.0
    if unit == "s":
        lbl_b = f" {before:.2f} s"
        lbl_a = f" {after:.2f} s ({delta:+.0f}%)"
    elif before >= 100:
        lbl_b = f" {before:.0f} {unit}"
        lbl_a = f" {after:.0f} {unit} ({delta:+.0f}%)"
    else:
        lbl_b = f" {before:.2f} {unit}"
        lbl_a = f" {after:.2f} {unit} ({delta:+.0f}%)"
    ax2.text(101.5, i - h/2, lbl_b, va="center", fontsize=8.0, color=SLATE)
    ax2.text(pct_after[i] + 1.5, i + h/2, lbl_a, va="center", fontsize=8.2, weight="bold", color=TEAL)

ax2.set_title("Impact of Wasm64 de-bloating + --fast-jit (% of before)", fontsize=9.8, loc="left", color=INK, pad=22)
ax2.set_xlabel("% of Batch 4D baseline (lower is smaller / faster)", fontsize=8.4, color=SLATE)
ax2.set_yticks(py, labels=[r[0] for r in pct_labels], fontsize=8.6, color=INK)
ax2.invert_yaxis()
ax2.set_xlim(0, 145)
ax2.legend(frameon=False, fontsize=8.0, loc="lower left", bbox_to_anchor=(0.0, 1.005), ncol=2)
clean_ax(ax2, "x")

save(fig, "blot2_turnaround_breakdown")
print("Saved SVG charts in", DIR)
