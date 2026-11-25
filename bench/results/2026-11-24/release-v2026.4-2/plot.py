#!/usr/bin/env python3
"""Generate consumer comparison charts: goose-to-wasm v2026.4-2 vs v2026.4-1 vs upstream C++ Goose."""
from __future__ import annotations

import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

DIR = Path(__file__).resolve().parent
res = json.loads((DIR / "results.json").read_text())

plt.rcParams.update({
    "font.size": 10,
    "font.family": "DejaVu Sans",
    "svg.fonttype": "none",
    "svg.hashsalt": "goose-to-wasm-v2026.4-2",
    "axes.edgecolor": "#cbd5e1",
    "figure.facecolor": "#ffffff",
    "axes.facecolor": "#ffffff",
})

UPSTREAM = "#9b5946"
UPSTREAM_LT = "#b87a68"
TEAL = "#0f766e"
TEAL_LT = "#2d9d92"
NAVY = "#1e3a5f"
BLUE = "#3b6fa0"
AMBER = "#c47d2b"
SLATE = "#64748b"
SLATE_LT = "#94a3b8"


def save(fig, stem: str) -> None:
    fig.savefig(DIR / f"{stem}.png", dpi=150, bbox_inches="tight", pad_inches=0.18)
    svg = DIR / f"{stem}.svg"
    fig.savefig(svg, metadata={"Date": None}, bbox_inches="tight", pad_inches=0.18)
    svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
    plt.close(fig)


def clean_ax(ax, grid_axis: str = "x") -> None:
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=5)
    ax.set_axisbelow(True)
    ax.grid(axis=grid_axis, color="#e2e8f0", linewidth=0.8)


# =============================================================================
# 1. compile_turnaround_vs_goose.svg
# =============================================================================
s1 = res["suite1_selfcompile"]
s4 = res["suite4_blot2"]

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12.6, 4.8), gridspec_kw={"width_ratios": [1.35, 1.0]}, layout="constrained")
fig.suptitle(
    "Compiler turnaround: goose-to-wasm v2026.4-2 vs v2026.4-1 & upstream C++ Goose (CPU 7, lower is faster)",
    x=0.01, ha="left", fontsize=12.2, weight="bold", color="#0f172a",
)

rows = [
    ("Upstream C++ · emit C (-O2)", s1["upstream_emit_c"]["median_wall_s"], UPSTREAM, ""),
    ("Upstream C++ · check", s1["upstream_check"]["median_wall_s"], UPSTREAM_LT, ""),
    ("v2026.4-2 (Wasm64) · emit Wasm", s1["g2w_wasmtime_emit_wasm64"]["median_wall_s"], TEAL_LT, f"{s1['upstream_emit_c']['median_wall_s']/s1['g2w_wasmtime_emit_wasm64']['median_wall_s']:.1f}× vs upstream"),
    ("v2026.4-2 (Wasm64) · check", s1["g2w_wasmtime_check"]["median_wall_s"], "#5cb8ad", f"{s1['upstream_check']['median_wall_s']/s1['g2w_wasmtime_check']['median_wall_s']:.1f}× vs upstream"),
    ("v2026.4-1 (Native) · emit C (-O2)", s1["v1_emit_c"]["median_wall_s"], SLATE_LT, "prior release"),
    ("v2026.4-2 (Native) · emit C (-O2)", s1["g2w_emit_c"]["median_wall_s"], BLUE, f"{s1['upstream_emit_c']['median_wall_s']/s1['g2w_emit_c']['median_wall_s']:.1f}× ({(s1['g2w_emit_c']['median_wall_s']-s1['v1_emit_c']['median_wall_s'])/s1['v1_emit_c']['median_wall_s']*100:+.0f}% vs -1)"),
    ("v2026.4-2 (Native) · emit Wasm", s1["g2w_wasm64"]["median_wall_s"], TEAL, f"{s1['upstream_emit_c']['median_wall_s']/s1['g2w_wasm64']['median_wall_s']:.1f}× vs upstream"),
    ("v2026.4-2 (Native) · check", s1["g2w_check"]["median_wall_s"], NAVY, f"{s1['upstream_check']['median_wall_s']/s1['g2w_check']['median_wall_s']:.1f}× vs upstream"),
]
ys = list(range(len(rows)))
vals = [r[1] for r in rows]
bars = ax1.barh(ys, vals, height=0.64, color=[r[2] for r in rows])
labels = [f" {r[1]:.2f} s" + (f"  ({r[3]})" if r[3] else "") for r in rows]
ax1.bar_label(bars, labels=labels, padding=3, fontsize=8.4, weight="bold", color="#0f172a")
ax1.set_title("Self-hosting compiler (~30k LOC, 5 alt. rounds)", fontsize=11, loc="left", color="#1e293b")
ax1.set_xlabel("Elapsed seconds")
ax1.set_yticks(ys, labels=[r[0] for r in rows], fontsize=8.7)
ax1.invert_yaxis()
ax1.set_xlim(0, max(vals) * 1.48)
clean_ax(ax1, "x")

cb_v1 = s4["cb1e9e15"]["g2w_v1"]["median_wall_s"]
cb_v2 = s4["cb1e9e15"]["g2w_v2"]["median_wall_s"]
a6_v1 = s4["6ad5fbb"]["g2w_v1"]["median_wall_s"]
a6_v2 = s4["6ad5fbb"]["g2w_v2"]["median_wall_s"]

b_rows = [
    ("cb1e9e15 · Upstream (--header)*", 180.0, UPSTREAM, ">180 s (timeout)"),
    ("cb1e9e15 · v2026.4-1", cb_v1, SLATE, f"{cb_v1:.1f} s"),
    ("cb1e9e15 · v2026.4-2", cb_v2, TEAL, f"{cb_v2:.1f} s ({(cb_v2-cb_v1)/cb_v1*100:+.0f}% vs -1)"),
    ("6ad5fbb · Upstream (check)*", 240.0, UPSTREAM_LT, ">240 s (timeout)"),
    ("6ad5fbb · v2026.4-1", a6_v1, SLATE_LT, f"{a6_v1:.1f} s"),
    ("6ad5fbb · v2026.4-2", a6_v2, NAVY, f"{a6_v2:.1f} s ({(a6_v2-a6_v1)/a6_v1*100:+.0f}% vs -1)"),
]
by = [0, 1, 2, 3.4, 4.4, 5.4]
bvals = [r[1] for r in b_rows]
bbars = ax2.barh(by, bvals, height=0.65, color=[r[2] for r in b_rows])
for idx in (0, 3):
    bbars[idx].set_hatch("//")
    bbars[idx].set_edgecolor("#ffffff")
ax2.bar_label(bbars, labels=[f" {r[3]}" for r in b_rows], padding=3, fontsize=8.4, weight="bold", color="#0f172a")
ax2.set_title("Blot2 compiler check (default 2 GiB stack)", fontsize=11, loc="left", color="#1e293b")
ax2.set_xlabel("Elapsed seconds (*ref. timeout from v2026.4-1 run)")
ax2.set_yticks(by, labels=[r[0] for r in b_rows], fontsize=8.6)
ax2.invert_yaxis()
ax2.set_xlim(0, 355)
clean_ax(ax2, "x")

save(fig, "compile_turnaround_vs_goose")


# =============================================================================
# 2. dev_build_examples_vs_goose.svg
# =============================================================================
s2 = res["suite2_examples_build"]
exs = ["squares", "sieve", "sudoku", "vm", "life", "tour", "maze", "sorting"]

fig, (ax_b, ax_c) = plt.subplots(1, 2, figsize=(12.2, 4.4), layout="constrained")
fig.suptitle(
    "Everyday dev turnaround on 8 Goose programs: v2026.4-2 Direct Wasm (-O2) vs upstream C++ Goose (CPU 7, 5 rounds)",
    x=0.01, ha="left", fontsize=11.8, weight="bold", color="#0f172a",
)

x = list(range(len(exs)))
up_bld = [s2[e]["upstream_build_o2"]["median_wall_s"] * 1000.0 for e in exs]
g2w_wasm = [s2[e]["g2w_wasm_o2"]["median_wall_s"] * 1000.0 for e in exs]

w = 0.38
b_up = ax_b.bar([i - w / 2 for i in x], up_bld, width=w, color=UPSTREAM, label="Upstream C++ · build -O2 (Clang)")
b_gw = ax_b.bar([i + w / 2 for i in x], g2w_wasm, width=w, color=TEAL, label="v2026.4-2 · Direct Wasm -O2")
ax_b.bar_label(b_up, labels=[f"{v:.0f}" for v in up_bld], padding=2, fontsize=8, color="#475569")
ax_b.bar_label(b_gw, labels=[f"{v:.1f}" for v in g2w_wasm], padding=2, fontsize=8, weight="bold", color=TEAL)
for i in x:
    ratio = up_bld[i] / g2w_wasm[i]
    ax_b.text(i, max(up_bld[i], g2w_wasm[i]) + 15, f"{ratio:.0f}×", ha="center", va="bottom", fontsize=8.2, weight="bold", color=NAVY)
ax_b.set_title("Compile to runnable artifact (ms, lower is faster)", fontsize=11, loc="left", color="#1e293b")
ax_b.set_ylabel("Milliseconds")
ax_b.set_xticks(x, labels=exs, fontsize=9)
ax_b.set_ylim(0, max(up_bld) * 1.28)
ax_b.legend(frameon=False, fontsize=8.8, loc="upper left")
clean_ax(ax_b, "y")

up_chk = [s2[e]["upstream_check"]["median_wall_s"] * 1000.0 for e in exs]
g2w_chk = [s2[e]["g2w_check"]["median_wall_s"] * 1000.0 for e in exs]
c_up = ax_c.bar([i - w / 2 for i in x], up_chk, width=w, color=UPSTREAM_LT, label="Upstream C++ · check")
c_gw = ax_c.bar([i + w / 2 for i in x], g2w_chk, width=w, color=NAVY, label="v2026.4-2 · --check")
ax_c.bar_label(c_up, labels=[f"{v:.1f}" for v in up_chk], padding=2, fontsize=8, color="#475569")
ax_c.bar_label(c_gw, labels=[f"{v:.1f}" for v in g2w_chk], padding=2, fontsize=8, weight="bold", color=NAVY)
ax_c.set_title("Type & lifetime check only (ms, lower is faster)", fontsize=11, loc="left", color="#1e293b")
ax_c.set_ylabel("Milliseconds")
ax_c.set_xticks(x, labels=exs, fontsize=9)
ax_c.set_ylim(0, max(up_chk) * 1.25)
ax_c.legend(frameon=False, fontsize=8.8, loc="upper left")
clean_ax(ax_c, "y")

save(fig, "dev_build_examples_vs_goose")


# =============================================================================
# 3. runtime_vs_goose.svg
# =============================================================================
s3 = res["suite3_runtime"]

fig, (ax_r, ax_m) = plt.subplots(1, 2, figsize=(12.2, 4.2), gridspec_kw={"width_ratios": [1.35, 1.0]}, layout="constrained")
fig.suptitle(
    "Compiled program runtime: goose-to-wasm v2026.4-2 vs upstream C++ Goose (CPU 7, 5 rounds, lower is faster)",
    x=0.01, ha="left", fontsize=12.0, weight="bold", color="#0f172a",
)

rt_exs = ["sorting", "life", "sudoku", "sieve", "maze"]
rx = list(range(len(rt_exs)))
w3 = 0.26
u_rt = [s3[e]["upstream_native_o2"]["median_wall_s"] * 1000.0 for e in rt_exs]
n_rt = [s3[e]["g2w_native_o2"]["median_wall_s"] * 1000.0 for e in rt_exs]
w_rt = [s3[e]["g2w_wasm_wasmtime"]["median_wall_s"] * 1000.0 for e in rt_exs]

b1 = ax_r.bar([i - w3 for i in rx], u_rt, width=w3, color=UPSTREAM, label="Upstream C++ · Native -O2")
b2 = ax_r.bar(rx, n_rt, width=w3, color=NAVY, label="v2026.4-2 · Native -O2 (Clang)")
b3 = ax_r.bar([i + w3 for i in rx], w_rt, width=w3, color=TEAL, label="v2026.4-2 · Direct Wasm (Wasmtime)")
ax_r.bar_label(b1, labels=[f"{v:.1f}" for v in u_rt], padding=2, fontsize=7.6, color="#475569")
ax_r.bar_label(b2, labels=[f"{v:.1f}" for v in n_rt], padding=2, fontsize=7.6, weight="bold", color=NAVY)
ax_r.bar_label(b3, labels=[f"{v:.1f}" for v in w_rt], padding=2, fontsize=7.6, weight="bold", color=TEAL)
ax_r.set_title("Example programs (ms; bit-exact output)", fontsize=11, loc="left", color="#1e293b")
ax_r.set_ylabel("Milliseconds")
ax_r.set_xticks(rx, labels=rt_exs, fontsize=9.2)
ax_r.set_ylim(0, max(max(u_rt), max(n_rt), max(w_rt)) * 1.24)
ax_r.legend(frameon=False, fontsize=8.4, loc="upper right")
clean_ax(ax_r, "y")

mb = s3["mandelbrot"]
mb_rows = [
    ("Upstream C++\nNative -O2", mb["upstream_native_o2"]["median_wall_s"], UPSTREAM),
    ("v2026.4-2\nNative -O2", mb["g2w_native_o2"]["median_wall_s"], NAVY),
    ("v2026.4-2\nWasmtime", mb["g2w_wasm_wasmtime"]["median_wall_s"], TEAL),
    ("v2026.4-2\nNode V8", mb["g2w_wasm_node"]["median_wall_s"], AMBER),
]
mx = list(range(len(mb_rows)))
mvals = [r[1] for r in mb_rows]
mbars = ax_m.bar(mx, mvals, width=0.56, color=[r[2] for r in mb_rows])
ax_m.bar_label(mbars, labels=[f"{v:.2f} s" for v in mvals], padding=3, fontsize=9, weight="bold", color="#0f172a")
ax_m.set_title("Mandelbrot 2048×2048 (kernel clock, checksum verified)", fontsize=10.6, loc="left", color="#1e293b")
ax_m.set_ylabel("Seconds")
ax_m.set_xticks(mx, labels=[r[0] for r in mb_rows], fontsize=8.8)
ax_m.set_ylim(0, max(mvals) * 1.24)
clean_ax(ax_m, "y")

save(fig, "runtime_vs_goose")
print("Generated 3 SVG + PNG charts cleanly!")
