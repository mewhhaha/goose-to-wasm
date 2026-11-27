#!/usr/bin/env python3
"""Generate clean consumer & technical SVG charts for the 2026-11-27 Four-Levers Campaign."""
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

res = json.loads((DIR / "results.json").read_text())
prev_lt = json.loads((ROOT / "bench/results/2026-11-27/lifetime-campaign/lifetime_turnaround.json").read_text())
v4_ref = json.loads((ROOT / "bench/results/2026-11-25/release-v2026.4-4/results.json").read_text())
blot_nov25 = json.loads((ROOT / "bench/results/2026-11-25/blot2-head-98f277f2/metrics.json").read_text())

plt.rcParams.update({
    "font.size": 10.0,
    "font.family": "DejaVu Sans",
    "svg.fonttype": "none",
    "svg.hashsalt": "goose-to-wasm-2026-11-27-four-levers",
    "axes.edgecolor": "#cbd5e1",
    "figure.facecolor": "#ffffff",
    "axes.facecolor": "#ffffff",
})

UPSTREAM = "#b4533c"
UPSTREAM_LT = "#d0826f"
UPSTREAM_PALE = "#e09f8f"
TEAL = "#0f766e"
TEAL_LT = "#14b8a6"
EMERALD = "#059669"
NAVY = "#1e3a5f"
BLUE = "#2563eb"
SKY = "#0284c7"
AMBER = "#d97706"
SLATE = "#475569"
INK = "#0f172a"


def save(fig, stem: str) -> None:
    fig.savefig(PREVIEW / f"{stem}.png", dpi=150, bbox_inches="tight", pad_inches=0.24)
    svg = DIR / f"{stem}.svg"
    fig.savefig(svg, metadata={"Date": None}, bbox_inches="tight", pad_inches=0.24)
    svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
    plt.close(fig)


def clean_ax(ax, grid_axis: str = "x") -> None:
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=6)
    ax.set_axisbelow(True)
    ax.grid(axis=grid_axis, color="#e2e8f0", linewidth=0.9)


# =============================================================================
# 1. large_codebase_turnaround.svg — README Section 2 updated hero chart
# =============================================================================
s1 = v4_ref["suite1_selfcompile"]
up_chk = s1["upstream_check"]["median_wall_s"]
up_emit = s1["upstream_emit_c"]["median_wall_s"]

unp = res["paired_unprofiled_j8"]
pgo = res["paired_pgo_reference_j8"]
jit = res["blot2_jit_and_run"]
inc_u = res["blot2_incremental_and_edits"]["lever4_unprofiled"]
inc_p = res["blot2_incremental_and_edits"]["lever4_pgo_ref"]

gw_sh_chk = unp["selfhost_check"]["lever4"]["median_ms"] / 1000.0
gw_sh_chk_pgo = pgo["selfhost_check"]["lever4_pgo"]["median_ms"] / 1000.0
gw_sh_o2 = unp["selfhost_o2_wasm64"]["lever4"]["median_ms"] / 1000.0
gw_sh_o0 = unp["selfhost_o0_wasm64"]["lever4"]["median_ms"] / 1000.0
gw_sh_o0_pgo = pgo["selfhost_o0_wasm64"]["lever4_pgo"]["median_ms"] / 1000.0

b_up_chk = blot_nov25["upstream_check_pin7"]["median_s"]
b_up_rel = 98.831
b_up_dbg = 30.64
b_nov25_dev = blot_nov25["emit_wasm64_O0_pin7"]["median_s"] + blot_nov25["wasmtime_cold_O0_unpinned"]["median_s"]

b_winch = jit["cold_l4_o0_winch_fib"]["median_ms"] / 1000.0
b_cold_emit_u = unp["blot2_o0_wasm64"]["lever4"]["median_ms"] / 1000.0
b_cold_emit_p = pgo["blot2_o0_wasm64"]["lever4_pgo"]["median_ms"] / 1000.0
b_cold_u = b_cold_emit_u + b_winch
b_cold_p = b_cold_emit_p + b_winch

b_edit_emit_u = inc_u["edited_file_life_hits"]["compile_goose_o0_scalar_if_let"]["median_ms"] / 1000.0
b_edit_emit_p = inc_p["edited_file_life_hits"]["compile_goose_o0_scalar_if_let"]["median_ms"] / 1000.0
b_edit_u = b_edit_emit_u + b_winch
b_edit_p = b_edit_emit_p + b_winch
b_edit_chk_u = inc_u["edited_file_life_hits"]["check_goose_911k_check_scalar_if_let"]["median_ms"] / 1000.0

b_cold_chk_u = unp["blot2_check_patched"]["lever4"]["median_ms"] / 1000.0
b_cache_o0_ms = inc_u["warm_hit_o0_same_out"]["median_ms"]
b_cache_chk_ms = inc_u["warm_hit_check"]["median_ms"]

fig, (ax1, ax2) = plt.subplots(
    1, 2, figsize=(13.8, 5.2), gridspec_kw={"width_ratios": [1.0, 1.32]}, layout="constrained"
)
fig.suptitle(
    "Large real-world Goose codebases: edit-compile-run turnaround (seconds, lower is faster)",
    x=0.01, ha="left", fontsize=12.4, weight="bold", color=INK,
)

left_rows = [
    ("Upstream C++ · check", up_chk, UPSTREAM_LT, f"{up_chk:.2f} s"),
    ("goosew · --check (unprof.)", gw_sh_chk, NAVY, f"{gw_sh_chk:.2f} s  ({up_chk/gw_sh_chk:.1f}× faster)"),
    ("goosew · --check (PGO*)", gw_sh_chk_pgo, SKY, f"{gw_sh_chk_pgo:.2f} s  ({up_chk/gw_sh_chk_pgo:.1f}× faster)"),
    ("Upstream C++ · emit C (-O2)", up_emit, UPSTREAM, f"{up_emit:.2f} s"),
    ("goosew · Wasm64 -O2 (--jobs 8)", gw_sh_o2, BLUE, f"{gw_sh_o2:.2f} s  ({up_emit/gw_sh_o2:.1f}× faster)"),
    ("goosew · Wasm64 -O0 (--jobs 8)", gw_sh_o0, TEAL, f"{gw_sh_o0:.2f} s  ({up_emit/gw_sh_o0:.1f}× faster)"),
    ("goosew · Wasm64 -O0 (PGO*)", gw_sh_o0_pgo, TEAL_LT, f"{gw_sh_o0_pgo:.2f} s  ({up_emit/gw_sh_o0_pgo:.1f}× faster)"),
]
ly = [0.0, 0.78, 1.56, 2.58, 3.36, 4.14, 4.92]
lbars = ax1.barh(ly, [r[1] for r in left_rows], height=0.58, color=[r[2] for r in left_rows])
ax1.bar_label(lbars, labels=[f" {r[3]}" for r in left_rows], padding=4, fontsize=8.5, weight="bold", color=INK)
ax1.set_title("Our own compiler (selfhost/, 47.4k LOC)", fontsize=10.3, loc="left", color=INK, pad=8)
ax1.set_xlabel("Seconds (*fresh Clang-23 PGO ref. run; unprofiled matched)", fontsize=8.3, color=SLATE)
ax1.set_yticks(ly, labels=[r[0] for r in left_rows], fontsize=8.7, color=INK)
ax1.invert_yaxis()
ax1.set_xlim(0, up_emit * 1.66)
clean_ax(ax1, "x")

right_rows = [
    ("Upstream + Clang -O2 (release)*", b_up_rel, UPSTREAM, f"{b_up_rel:.1f} s"),
    ("Upstream + Clang -O0 (debug)*", b_up_dbg, UPSTREAM_LT, f"{b_up_dbg:.1f} s"),
    ("Upstream C++ · check", b_up_chk, UPSTREAM_PALE, f"{b_up_chk:.1f} s"),
    ("Nov 25 Direct Wasm64 + JIT (-O0)", b_nov25_dev, AMBER, f"{b_nov25_dev:.2f} s  (3.84 + 2.40 s)"),
    ("Now Cold: Wasm64 + Winch (-O0)", b_cold_u, TEAL, f"{b_cold_u:.2f} s  (PGO*: {b_cold_p:.2f} s · {b_up_dbg/b_cold_u:.0f}×–{b_up_rel/b_cold_u:.0f}×)"),
    ("Now Cold: goosew --check", b_cold_chk_u, NAVY, f"{b_cold_chk_u:.2f} s  ({b_up_chk/b_cold_chk_u:.1f}× vs upstream)"),
    ("Now Edited: .life + Winch (-O0)", b_edit_u, EMERALD, f"{b_edit_u:.2f} s  (PGO*: {b_edit_p:.2f} s · {b_edit_chk_u:.2f} s --check)"),
    ("Now Unchanged: --cache-dir", b_cache_o0_ms / 1000.0, BLUE, f"{b_cache_o0_ms:.0f} ms  ({b_cache_chk_ms:.0f} ms --check)"),
]
ry = [0.0, 0.78, 1.56, 2.52, 3.30, 4.08, 4.86, 5.64]
rbars = ax2.barh(ry, [r[1] for r in right_rows], height=0.58, color=[r[2] for r in right_rows])
ax2.bar_label(rbars, labels=[f" {r[3]}" for r in right_rows], padding=4, fontsize=8.4, weight="bold", color=INK)
ax2.set_title("mewhhaha/blot2 compiler (79.0k LOC · 16/16 bit-exact)", fontsize=10.3, loc="left", color=INK, pad=8)
ax2.set_xlabel(
    f"Seconds (*separate ref. C / PGO runs · Cold -O0: {b_cold_emit_u:.2f} s + {b_winch:.2f} s Winch · Edited: {b_edit_emit_u:.2f} s + {b_winch:.2f} s)",
    fontsize=8.1, color=SLATE,
)
ax2.set_yticks(ry, labels=[r[0] for r in right_rows], fontsize=8.6, color=INK)
ax2.invert_yaxis()
ax2.set_xlim(0, b_up_rel * 1.56)
clean_ax(ax2, "x")

save(fig, "large_codebase_turnaround")


# =============================================================================
# 2. four_levers_progression.svg — 4-Lever Waterfall + Cold JIT/Run Breakdown
# =============================================================================
fig, (ax1, ax2) = plt.subplots(
    1, 2, figsize=(14.0, 5.4), gridspec_kw={"width_ratios": [1.18, 1.0]}, layout="constrained"
)
fig.suptitle(
    "Four-levers campaign on mewhhaha/blot2 (79.0k LOC): 6.24 s → 1.87–1.98 s cold · 0.89–0.93 s edited",
    x=0.01, ha="left", fontsize=12.0, weight="bold", color=INK,
)

# Left panel: Blot2 -O0 Edit -> Compile -> JIT/Run stacked waterfall (seconds)
cran_fj_ref = prev_lt["blot2_jit_and_run"]["cold_final_o0_fast_jit"]["median_ms"] / 1000.0
stack_rows = [
    ("Nov 25 baseline\n(speed JIT, 21.8 MiB)", blot_nov25["emit_wasm64_O0_pin7"]["median_s"], blot_nov25["wasmtime_cold_O0_unpinned"]["median_s"]),
    ("v2026.4-4 unprof.\n(Cranelift fast-jit*, 9.5M)", unp["blot2_o0_wasm64"]["v2026_4_4"]["median_ms"] / 1000.0, cran_fj_ref),
    ("Lifetime B2 unprof.\n(Cranelift fast-jit*, 9.5M)", unp["blot2_o0_wasm64"]["life_b2"]["median_ms"] / 1000.0, cran_fj_ref),
    ("Lever 1 unprof.\n(Cranelift fast-jit*, 9.5M)", unp["blot2_o0_wasm64"]["lever1"]["median_ms"] / 1000.0, cran_fj_ref),
    ("Lever 4 cold unprof.\n(Winch --fast-jit, 8.3M)", b_cold_emit_u, b_winch),
    ("Lever 4 cold PGO*\n(Winch --fast-jit, 8.3M)", b_cold_emit_p, b_winch),
    ("Lever 3+4 edited unprof.\n(.life hit + Winch, 8.3M)", b_edit_emit_u, b_winch),
    ("Lever 3+4 edited PGO*\n(.life hit + Winch, 8.3M)", b_edit_emit_p, b_winch),
]
sy = [0.0, 0.86, 1.72, 2.58, 3.44, 4.30, 5.26, 6.12]
emits = [r[1] for r in stack_rows]
runs = [r[2] for r in stack_rows]

ax1.barh(sy, emits, height=0.62, color=NAVY, label="Compile to Direct Wasm64 (-O0, --jobs 8)")
ax1.barh(sy, runs, left=emits, height=0.62, color=TEAL, edgecolor="#ffffff", linewidth=0.8, label="Cold JIT + run (fibonacci.blot)")

for yv, e, r in zip(sy, emits, runs):
    tot = e + r
    ax1.text(tot + 0.10, yv, f"{tot:.2f} s  ({e:.2f} + {r:.2f})", va="center", fontsize=8.4, weight="bold", color=INK)

ax1.set_title("Blot2 -O0 edit → compile → run turnaround (seconds, lower is faster)", fontsize=9.8, loc="left", color=INK, pad=22)
ax1.set_xlabel("Seconds (*Cranelift --fast-jit ref. from 9ca5ad7; PGO* = fresh Clang-23 PGO ref.)", fontsize=8.0, color=SLATE)
ax1.set_yticks(sy, labels=[r[0] for r in stack_rows], fontsize=8.2, color=INK)
ax1.invert_yaxis()
ax1.set_xlim(0, 8.55)
ax1.legend(frameon=False, fontsize=8.1, loc="lower left", bbox_to_anchor=(0.0, 1.005), ncol=2)
clean_ax(ax1, "x")

# Right panel: Cold JIT + Run breakdown on fibonacci.blot (milliseconds)
jit_rows = [
    ("Nov 25 · 21.8 MiB\nCranelift speed*", 2404.0, 0.0, UPSTREAM_LT, "2,404 ms (1,257 MiB RSS)"),
    ("v2026.4-4 · 9.45 MiB\nCranelift speed", jit["cold_v4_o0_speed_fib"]["median_jit_ms"], jit["cold_v4_o0_speed_fib"]["median_run_ms"], AMBER,
     f"{jit['cold_v4_o0_speed_fib']['median_ms']:,.0f} ms ({jit['cold_v4_o0_speed_fib']['median_jit_ms']:.0f} + {jit['cold_v4_o0_speed_fib']['median_run_ms']:.0f})"),
    ("v2026.4-4 · 9.45 MiB\nCranelift fast-jit*", 505.0, 106.0, SLATE,
     f"{prev_lt['blot2_jit_and_run']['cold_final_o0_fast_jit']['median_ms']:.0f} ms (422 MiB RSS)"),
    ("v2026.4-4 · 9.45 MiB\nWinch --fast-jit", jit["cold_v4_o0_winch_fib"]["median_jit_ms"], jit["cold_v4_o0_winch_fib"]["median_run_ms"], BLUE,
     f"{jit['cold_v4_o0_winch_fib']['median_ms']:.0f} ms ({jit['cold_v4_o0_winch_fib']['median_jit_ms']:.0f} + {jit['cold_v4_o0_winch_fib']['median_run_ms']:.0f})"),
    ("Lever 4 · 8.34 MiB (-O0)\nWinch --fast-jit", jit["cold_l4_o0_winch_fib"]["median_jit_ms"], jit["cold_l4_o0_winch_fib"]["median_run_ms"], TEAL,
     f"{jit['cold_l4_o0_winch_fib']['median_ms']:.0f} ms ({jit['cold_l4_o0_winch_fib']['median_jit_ms']:.0f} + {jit['cold_l4_o0_winch_fib']['median_run_ms']:.0f}, 332 MiB)"),
    ("Lever 4 · 12.79 MiB (-O2)\nWinch --fast-jit", jit["cold_l4_o2_winch_fib"]["median_jit_ms"], jit["cold_l4_o2_winch_fib"]["median_run_ms"], SKY,
     f"{jit['cold_l4_o2_winch_fib']['median_ms']:.0f} ms ({jit['cold_l4_o2_winch_fib']['median_jit_ms']:.0f} + {jit['cold_l4_o2_winch_fib']['median_run_ms']:.0f})"),
    ("Warm .cwasm (-O0)\nWinch --fast-jit", jit["warm_l4_o0_winch_fib"]["median_jit_ms"], jit["warm_l4_o0_winch_fib"]["median_run_ms"], EMERALD,
     f"{jit['warm_l4_o0_winch_fib']['median_ms']:.0f} ms (126 MiB RSS)"),
    ("Warm .cwasm (-O2)\nCranelift speed", jit["warm_l4_o2_speed_fib"]["median_jit_ms"], jit["warm_l4_o2_speed_fib"]["median_run_ms"], NAVY,
     f"{jit['warm_l4_o2_speed_fib']['median_ms']:.0f} ms (126 MiB RSS)"),
]
jy = [0.0, 0.86, 1.72, 2.58, 3.44, 4.30, 5.26, 6.12]
j_comp = [r[1] for r in jit_rows]
j_exec = [r[2] for r in jit_rows]
ax2.barh(jy, j_comp, height=0.62, color=NAVY, label="JIT compile + instantiate")
ax2.barh(jy, j_exec, left=j_comp, height=0.62, color=TEAL, edgecolor="#ffffff", linewidth=0.8, label="Run blot_goose_main (fibonacci.blot)")

for yv, jc, je, _, lbl in zip(jy, j_comp, j_exec, [r[3] for r in jit_rows], [r[4] for r in jit_rows]):
    ax2.text(jc + je + 38, yv, lbl, va="center", fontsize=8.2, weight="bold", color=INK)

ax2.set_title("goose-wasmtime JIT + run breakdown (ms, lower is faster)", fontsize=9.8, loc="left", color=INK, pad=22)
ax2.set_xlabel("Milliseconds (host wall incl. ~17 ms startup; *prior pinned ref.)", fontsize=8.0, color=SLATE)
ax2.set_yticks(jy, labels=[r[0] for r in jit_rows], fontsize=8.2, color=INK)
ax2.invert_yaxis()
ax2.set_xlim(0, 3650)
ax2.legend(frameon=False, fontsize=8.1, loc="lower left", bbox_to_anchor=(0.0, 1.005), ncol=2)
clean_ax(ax2, "x")

save(fig, "four_levers_progression")
print("Saved SVG charts in", DIR)
