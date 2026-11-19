"""Chart paired instruction changes and the observed pass counts on a fixed project."""

import gzip
import json
from pathlib import Path
from statistics import median

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

directory = Path(__file__).resolve().parents[1]
samples = json.loads(gzip.decompress((directory / "experiments.json.gz").read_bytes()))


def change(series, name):
    rows = samples[series]["rows"]
    old = {row["round"]: row for row in rows if row["label"] == "baseline"}
    new = {row["round"]: row for row in rows if row["label"] == name}
    if set(old) != set(new) or not old:
        raise ValueError(f"Incomplete rounds for {series}/{name}")
    ratios = []
    for ident, row in new.items():
        if row["output"] != old[ident]["output"]:
            raise ValueError(f"Output mismatch in round {ident}")
        ratios.append(row["ins"] / old[ident]["ins"])
    return (median(ratios) - 1) * 100


rows = [
    ("Reuse summaries outside predicted set", "replay", "verified-screen", "#a24a43"),
    ("Replay only empty-summary leaves", "clean-leaf", "controls", "#75838e"),
    ("Cache argument bounds · shipped", "shipping", "verified-screen", "#13766e"),
    ("Replay with recorded state restored¹", "repaired", "verified-screen", "#567394"),
]
plt.rcParams.update({"font.size": 10, "svg.hashsalt": "lifetime-callers", "svg.fonttype": "none"})
fig, ax = plt.subplots(figsize=(8.25, 3.2), layout="constrained")
values = [change(series, name) for _, name, series, _ in rows]
ax.barh(range(len(rows)), values, color=[color for _, _, _, color in rows], height=0.53)
ax.set_yticks(range(len(rows)), [text for text, _, _, _ in rows])
ax.invert_yaxis()
ax.axvline(0, color="#59646d", linewidth=1)
ax.set_axisbelow(True)
ax.grid(axis="x", color="#dce2e7", linewidth=0.8)
ax.set_xlim(-4.2, 3.4)
for i, v in enumerate(values):
    x, align = (v + 0.08, "left") if v > 0 else (v - 0.08, "right")
    ax.text(x, i, f"{v:+.2f}%", ha=align, va="center", weight="bold")
ax.set_xticks([-4,-3,-2,-1,0,1,2,3], ["−4%","−3%","−2%","−1%","0%","+1%","+2%","+3%"])
ax.spines[:].set_visible(False)
ax.tick_params(length=0, pad=5)
fig.suptitle("Cost of a full compiler rebuild in cached Wasmtime", weight="bold", fontsize=15)
ax.set_title("Change in CPU instructions on the same frozen input. Lower is better.", loc="left", fontsize=10)
fig.supxlabel("¹ Diagnostic run supplied with the correct final bindings and caller state.", fontsize=9)
fig.savefig(directory / "calls.png", dpi=150)
target = directory / "calls.svg"
fig.savefig(target, metadata={"Date": None})
target.write_text("\n".join(line.rstrip() for line in target.read_text().splitlines()) + "\n")
