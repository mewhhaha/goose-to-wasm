#!/usr/bin/env python3
"""Generate clean consumer & technical SVG charts for the 2026-11-27 lifetime optimization campaign."""
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

lt = json.loads((DIR / "lifetime_turnaround.json").read_text())
paired_nopgo = json.loads((DIR / "paired_nopgo_j8.json").read_text())
paired_pgo = json.loads((DIR / "paired_pgo_j8.json").read_text())
prev_turn = json.loads((ROOT / "bench/results/2026-11-27/blot2-turnaround/blot2_turnaround.json").read_text())
prev_nopgo = json.loads((ROOT / "bench/results/2026-11-27/blot2-turnaround/paired_nopgo_j8.json").read_text())
v4 = json.loads((ROOT / "bench/results/2026-11-25/release-v2026.4-4/results.json").read_text())
blot_nov25 = json.loads((ROOT / "bench/results/2026-11-25/blot2-head-98f277f2/metrics.json").read_text())

plt.rcParams.update({
    "font.size": 10.2,
    "font.family": "DejaVu Sans",
    "svg.fonttype": "none",
    "svg.hashsalt": "goose-to-wasm-2026-11-27-lifetime-campaign",
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
gw_chk_nopgo = lt["progression_nopgo_j8"]["selfhost_check"]["batch2_nopgo"]["median_ms"] / 1000.0
gw_wasm_o2_nopgo = paired_nopgo["workloads"]["selfhost_o2_wasm64"]["cand"]["median_wall_ms"] / 1000.0
gw_wasm_nopgo = paired_nopgo["workloads"]["selfhost_o0_wasm64"]["cand"]["median_wall_ms"] / 1000.0
gw_wasm_pgo = paired_pgo["workloads"]["selfhost_o0_wasm64"]["cand"]["median_wall_ms"] / 1000.0

b_up_chk = blot_nov25["upstream_check_pin7"]["median_s"]
b_up_rel = 98.831
b_up_dbg = 30.64
b_nov25_dev = blot_nov25["emit_wasm64_O0_pin7"]["median_s"] + blot_nov25["wasmtime_cold_O0_unpinned"]["median_s"]
b_now_chk = lt["blot2_emit"]["final_nopgo_check_patched"]["median_ms"] / 1000.0
b_now_emit_nopgo = lt["blot2_emit"]["final_nopgo_emit_o0"]["median_ms"] / 1000.0
b_now_emit_pgo = lt["blot2_emit"]["final_pgo_emit_o0"]["median_ms"] / 1000.0
b_now_jit = lt["blot2_jit_and_run"]["cold_final_o0_fast_jit"]["median_ms"] / 1000.0
b_now_nopgo = b_now_emit_nopgo + b_now_jit
b_now_pgo = b_now_emit_pgo + b_now_jit
b_cache_hit = lt["blot2_incremental_cache"]["final_nopgo"]["warm_hit_o0_same_out"]["median_ms"] / 1000.0
b_cache_chk_ms = lt["blot2_incremental_cache"]["final_nopgo"]["warm_hit_check"]["median_ms"]

fig, (ax1, ax2) = plt.subplots(
    1, 2, figsize=(13.4, 4.9), gridspec_kw={"width_ratios": [1.0, 1.24]}, layout="constrained"
)
fig.suptitle(
    "Large real-world Goose codebases: edit-compile-run turnaround (seconds, lower is faster)",
    x=0.01, ha="left", fontsize=12.6, weight="bold", color=INK,
)

left_rows = [
    ("Upstream C++ · check", up_chk, UPSTREAM_LT, f"{up_chk:.2f} s"),
    ("goosew · --check (--jobs 8)", gw_chk_nopgo, NAVY, f"{gw_chk_nopgo:.2f} s  ({up_chk/gw_chk_nopgo:.1f}× faster)"),
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
ax1.set_xlim(0, up_emit * 1.58)
clean_ax(ax1, "x")

right_rows = [
    ("Upstream + Clang -O2 (release)*", b_up_rel, UPSTREAM, f"{b_up_rel:.1f} s"),
    ("Upstream + Clang -O0 (debug)*", b_up_dbg, UPSTREAM_LT, f"{b_up_dbg:.1f} s"),
    ("Upstream C++ · check", b_up_chk, "#e09f8f", f"{b_up_chk:.1f} s"),
    ("Nov 25 Direct Wasm64 + JIT (-O0)", b_nov25_dev, AMBER, f"{b_nov25_dev:.2f} s  (3.84 + 2.40 s)"),
    ("Now: Wasm64 + --fast-jit (-O0)", b_now_nopgo, TEAL, f"{b_now_nopgo:.2f} s  ({b_up_dbg/b_now_nopgo:.0f}×–{b_up_rel/b_now_nopgo:.0f}× faster)"),
    ("Now: Wasm64 + --fast-jit (PGO*)", b_now_pgo, TEAL_LT, f"{b_now_pgo:.2f} s  ({b_up_dbg/b_now_pgo:.0f}×–{b_up_rel/b_now_pgo:.0f}× faster)"),
    ("Now: goosew --check", b_now_chk, NAVY, f"{b_now_chk:.2f} s  ({b_up_chk/b_now_chk:.1f}× vs upstream)"),
    ("Now: --cache-dir (unchanged)", b_cache_hit, BLUE, f"{b_cache_hit*1000:.0f} ms  ({b_cache_chk_ms:.0f} ms --check)"),
]
ry = [0.0, 0.78, 1.56, 2.52, 3.30, 4.08, 4.86, 5.64]
rbars = ax2.barh(ry, [r[1] for r in right_rows], height=0.58, color=[r[2] for r in right_rows])
ax2.bar_label(rbars, labels=[f" {r[3]}" for r in right_rows], padding=4, fontsize=8.7, weight="bold", color=INK)
ax2.set_title("mewhhaha/blot2 compiler (79.0k LOC · 16/16 bit-exact)", fontsize=10.4, loc="left", color=INK, pad=8)
ax2.set_xlabel(
    f"Seconds (*separate ref. C / PGO runs · Now -O0: {b_now_emit_nopgo:.2f} s / {b_now_emit_pgo:.2f} s emit + {b_now_jit:.2f} s JIT+run)",
    fontsize=8.3, color=SLATE,
)
ax2.set_yticks(ry, labels=[r[0] for r in right_rows], fontsize=8.8, color=INK)
ax2.invert_yaxis()
ax2.set_xlim(0, b_up_rel * 1.48)
clean_ax(ax2, "x")

save(fig, "large_codebase_turnaround")


# =============================================================================
# 2. lifetime_campaign_breakdown.svg — Lifetime Progression + Cold Blot2 Stack
# =============================================================================
fig, (ax1, ax2) = plt.subplots(
    1, 2, figsize=(13.6, 5.1), gridspec_kw={"width_ratios": [1.05, 1.25]}, layout="constrained"
)
fig.suptitle(
    "Lifetime optimization campaign: -20% to -62% lifetime time · Blot2 turnaround down to 2.17–2.36 s",
    x=0.01, ha="left", fontsize=12.2, weight="bold", color=INK,
)

# Left panel: Lifetime analysis stage progression (Blot2 -O0 & selfhost --check, same 5-round interleaved run + PGO* ref)
p_bl = lt["progression_nopgo_j8"]["blot2_o0_wasm64"]
p_sh = lt["progression_nopgo_j8"]["selfhost_check"]
lf_rows = [
    ("Blot2 -O0 · v2026.4-4 (unprof.)", p_bl["v2026_4_4_nopgo"]["stages_ms"]["lifetime_ms"], UPSTREAM_LT),
    ("Blot2 -O0 · Batch 1 (unprof.)", p_bl["batch1_nopgo"]["stages_ms"]["lifetime_ms"], AMBER),
    ("Blot2 -O0 · Batch 2 (unprof.)", p_bl["batch2_nopgo"]["stages_ms"]["lifetime_ms"], TEAL),
    ("Blot2 -O0 · Batch 2 (PGO*)", lt["blot2_emit"]["final_pgo_emit_o0"]["stages_ms"]["lifetime_ms"], TEAL_LT),
    ("selfhost --check · v2026.4-4", p_sh["v2026_4_4_nopgo"]["stages_ms"]["lifetime_ms"], UPSTREAM_LT),
    ("selfhost --check · Batch 1", p_sh["batch1_nopgo"]["stages_ms"]["lifetime_ms"], AMBER),
    ("selfhost --check · Batch 2", p_sh["batch2_nopgo"]["stages_ms"]["lifetime_ms"], TEAL),
    ("selfhost --check · Batch 2 (PGO*)", lt["blot2_emit"]["final_pgo_selfhost_check"]["stages_ms"]["lifetime_ms"], TEAL_LT),
]
ly2 = [0.0, 0.78, 1.56, 2.34, 3.44, 4.22, 5.00, 5.78]
bl_base_lf = lf_rows[0][1]
sh_base_lf = lf_rows[4][1]
bars_lf = ax1.barh(ly2, [r[1] for r in lf_rows], height=0.58, color=[r[2] for r in lf_rows])
lf_labels = []
for i, (_, ms, _) in enumerate(lf_rows):
    if i == 0 or i == 4:
        lf_labels.append(f" {ms:.0f} ms")
    elif i < 4:
        lf_labels.append(f" {ms:.0f} ms ({(ms - bl_base_lf)/bl_base_lf*100:+.0f}%)")
    else:
        lf_labels.append(f" {ms:.0f} ms ({(ms - sh_base_lf)/sh_base_lf*100:+.0f}%)")
ax1.bar_label(bars_lf, labels=lf_labels, padding=4, fontsize=8.4, weight="bold", color=INK)
ax1.set_title("Lifetime checker stage time (--jobs 8, ms, lower is faster)", fontsize=9.8, loc="left", color=INK, pad=10)
ax1.set_xlabel("Milliseconds (*separate fresh Clang-23 PGO ref. run)", fontsize=8.4, color=SLATE)
ax1.set_yticks(ly2, labels=[r[0] for r in lf_rows], fontsize=8.5, color=INK)
ax1.invert_yaxis()
ax1.set_xlim(0, bl_base_lf * 1.45)
clean_ax(ax1, "x")

# Right panel: Complete Blot2 turnaround progression (stacked Emit + Cold JIT/Run)
b4d_o0_emit = prev_nopgo["workloads"]["blot2_o0_wasm64"]["base"]["median_wall_ms"] / 1000.0
v4_o0_emit = prev_turn["blot2_emit"]["final_nopgo_emit_o0"]["median_ms"] / 1000.0
v4_o0_pgo = prev_turn["blot2_emit"]["final_pgo_emit_o0"]["median_ms"] / 1000.0
v4_jit_fj = prev_turn["blot2_jit_and_run"]["cold_final_o0_fast_jit"]["median_ms"] / 1000.0
now_o0_emit = lt["blot2_emit"]["final_nopgo_emit_o0"]["median_ms"] / 1000.0
now_o0_pgo = lt["blot2_emit"]["final_pgo_emit_o0"]["median_ms"] / 1000.0
now_o2_emit = lt["blot2_emit"]["final_nopgo_emit_o2"]["median_ms"] / 1000.0
now_o2_pgo = paired_pgo["workloads"]["blot2_o2_wasm64"]["cand"]["median_wall_ms"] / 1000.0
now_jit_fj = lt["blot2_jit_and_run"]["cold_final_o0_fast_jit"]["median_ms"] / 1000.0
now_jit_o2_fj = lt["blot2_jit_and_run"]["cold_final_o2_fast_jit"]["median_ms"] / 1000.0

stack_rows = [
    ("Nov 25 -O0\n(speed JIT)", blot_nov25["emit_wasm64_O0_pin7"]["median_s"], blot_nov25["wasmtime_cold_O0_unpinned"]["median_s"]),
    ("Nov 26 Batch 4D -O0\n(speed JIT)", b4d_o0_emit, prev_turn["blot2_jit_and_run"]["cold_batch4d_o0_speed"]["median_ms"] / 1000.0),
    ("v2026.4-4 unprof. -O0\n(--fast-jit)", v4_o0_emit, v4_jit_fj),
    ("v2026.4-4 PGO* -O0\n(--fast-jit)", v4_o0_pgo, v4_jit_fj),
    ("Now unprof. -O0\n(--fast-jit)", now_o0_emit, now_jit_fj),
    ("Now PGO* -O0\n(--fast-jit)", now_o0_pgo, now_jit_fj),
    ("Nov 25 -O2\n(speed JIT)", blot_nov25["emit_wasm64_O2_pin7"]["median_s"], blot_nov25["wasmtime_cold_O2_unpinned"]["median_s"]),
    ("Now unprof. -O2\n(--fast-jit)", now_o2_emit, now_jit_o2_fj),
    ("Now PGO* -O2\n(--fast-jit)", now_o2_pgo, now_jit_o2_fj),
]
sy = [0.0, 0.85, 1.70, 2.55, 3.40, 4.25, 5.40, 6.25, 7.10]
emits = [r[1] for r in stack_rows]
runs = [r[2] for r in stack_rows]
ax2.barh(sy, emits, height=0.62, color=NAVY, label="Compile to Direct Wasm64")
ax2.barh(sy, runs, left=emits, height=0.62, color=TEAL, label="Cold JIT/decode + run (fibonacci.blot)")

for yv, e, r in zip(sy, emits, runs):
    tot = e + r
    ax2.text(tot + 0.14, yv, f"{tot:.2f} s  ({e:.2f} + {r:.2f})", va="center", fontsize=8.4, weight="bold", color=INK)

ax2.set_title("Cold Blot2 edit → compile → run turnaround (seconds, lower is faster)", fontsize=9.8, loc="left", color=INK, pad=22)
ax2.set_xlabel("Seconds (*fresh Clang-23 PGO ref. run · Warm .cwasm: 73 ms · --cache-dir: 72 ms)", fontsize=8.3, color=SLATE)
ax2.set_yticks(sy, labels=[r[0] for r in stack_rows], fontsize=8.4, color=INK)
ax2.invert_yaxis()
ax2.set_xlim(0, 12.2)
ax2.legend(frameon=False, fontsize=8.3, loc="lower left", bbox_to_anchor=(0.0, 1.005), ncol=2)
clean_ax(ax2, "x")

save(fig, "lifetime_campaign_breakdown")
print("Saved SVG charts in", DIR)
