#!/usr/bin/env python3
"""Generate Blot2 lifetime-checker algorithmic redesign comparison chart."""
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
    "svg.hashsalt": "goose-to-wasm-blot2-algo-2026-11-25",
    "axes.edgecolor": "#cbd5e1",
    "figure.facecolor": "#ffffff",
    "axes.facecolor": "#ffffff",
})

UPSTREAM = "#9b5946"
UPSTREAM_LT = "#b87a68"
SLATE = "#64748b"
SLATE_LT = "#94a3b8"
BLUE = "#3b6fa0"
TEAL = "#0f766e"
NAVY = "#1e3a5f"


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


cb_v2 = res["blot2"]["cb1e9e15"]["v2026.4-2"]["median_wall_s"]
cb_new = res["blot2"]["cb1e9e15"]["blot2-algo"]["median_wall_s"]
cb_v2_rss = res["blot2"]["cb1e9e15"]["v2026.4-2"]["median_rss_gib"]
cb_new_rss = res["blot2"]["cb1e9e15"]["blot2-algo"]["median_rss_gib"]

a6_v2 = res["blot2"]["6ad5fbb"]["v2026.4-2"]["median_wall_s"]
a6_new = res["blot2"]["6ad5fbb"]["blot2-algo"]["median_wall_s"]
a6_v2_rss = res["blot2"]["6ad5fbb"]["v2026.4-2"]["median_rss_gib"]
a6_new_rss = res["blot2"]["6ad5fbb"]["blot2-algo"]["median_rss_gib"]

fig, (ax1, ax2) = plt.subplots(
    1, 2, figsize=(12.6, 4.7), gridspec_kw={"width_ratios": [1.35, 1.0]}, layout="constrained"
)
fig.suptitle(
    "Blot2 lifetime checker redesign: main vs v2026.4-2, Batch 3 & upstream C++ Goose (CPU 7, lower is better)",
    x=0.01, ha="left", fontsize=11.8, weight="bold", color="#0f172a",
)

# Left panel: Elapsed wall time on frozen Blot2 snapshots
t_rows = [
    ("cb1e9e15 · Upstream C++*", 180.0, UPSTREAM, ">180 s (timeout)"),
    ("cb1e9e15 · Batch 3*", 84.15, SLATE_LT, "84.2 s"),
    ("cb1e9e15 · v2026.4-2", cb_v2, BLUE, f"{cb_v2:.2f} s"),
    ("cb1e9e15 · main (algo)", cb_new, TEAL, f"{cb_new:.2f} s  ({cb_v2/cb_new:.2f}× vs -2)"),
    ("6ad5fbb · Upstream C++*", 240.0, UPSTREAM_LT, ">240 s (timeout)"),
    ("6ad5fbb · Batch 3*", 238.16, SLATE, "238.2 s"),
    ("6ad5fbb · v2026.4-2", a6_v2, BLUE, f"{a6_v2:.2f} s"),
    ("6ad5fbb · main (algo)", a6_new, NAVY, f"{a6_new:.2f} s  ({a6_v2/a6_new:.2f}× vs -2)"),
]
ys = [0, 1, 2, 3, 4.5, 5.5, 6.5, 7.5]
bars = ax1.barh(ys, [r[1] for r in t_rows], height=0.66, color=[r[2] for r in t_rows])
for idx in (0, 4):
    bars[idx].set_hatch("//")
    bars[idx].set_edgecolor("#ffffff")
ax1.bar_label(bars, labels=[f" {r[3]}" for r in t_rows], padding=3, fontsize=8.4, weight="bold", color="#0f172a")
ax1.set_title("Frozen Blot2 --check wall time (default 2 GiB stack)", fontsize=10.8, loc="left", color="#1e293b")
ax1.set_xlabel("Elapsed seconds (*separate dated ref. runs: upstream d5ae5bb, Batch 3 6ba2365f)")
ax1.set_yticks(ys, labels=[r[0] for r in t_rows], fontsize=8.6)
ax1.invert_yaxis()
ax1.set_xlim(0, 345)
clean_ax(ax1, "x")

# Right panel: Peak RSS (paired) + selfhost --check
r_rows = [
    ("cb1e9e15 · v2026.4-2", cb_v2_rss, BLUE, f"{cb_v2_rss:.2f} GiB"),
    ("cb1e9e15 · main (algo)", cb_new_rss, TEAL, f"{cb_new_rss:.2f} GiB  ({(cb_new_rss-cb_v2_rss)/cb_v2_rss*100:+.0f}%)"),
    ("6ad5fbb · v2026.4-2", a6_v2_rss, BLUE, f"{a6_v2_rss:.2f} GiB"),
    ("6ad5fbb · main (algo)", a6_new_rss, NAVY, f"{a6_new_rss:.2f} GiB  ({(a6_new_rss-a6_v2_rss)/a6_v2_rss*100:+.0f}%)"),
]
rys = [0, 1, 2.4, 3.4]
rbars = ax2.barh(rys, [r[1] for r in r_rows], height=0.62, color=[r[2] for r in r_rows])
ax2.bar_label(rbars, labels=[f" {r[3]}" for r in r_rows], padding=3, fontsize=8.6, weight="bold", color="#0f172a")
ax2.set_title("Blot2 peak RSS (3 paired CPU-7 rounds)", fontsize=10.8, loc="left", color="#1e293b")
ax2.set_xlabel("Max RSS (GiB)")
ax2.set_yticks(rys, labels=[r[0] for r in r_rows], fontsize=8.8)
ax2.invert_yaxis()
ax2.set_xlim(0, 11.4)
clean_ax(ax2, "x")

save(fig, "blot2_turnaround_vs_v2")
print("Generated blot2_turnaround_vs_v2.svg and .png cleanly!")
