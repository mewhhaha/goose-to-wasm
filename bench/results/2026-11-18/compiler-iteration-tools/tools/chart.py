"""Plot measured preparation and memory64 conformance costs."""
import hashlib
import json
from pathlib import Path
from statistics import median

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

folder = Path(__file__).resolve().parents[1]
inputs = [folder / "host-parity.json", folder / "preparation.json"]
parity, prep = [json.loads(path.read_text()) for path in inputs]
assert parity["compared"] == 4777 and not parity["differences"]
times = {row["host"]: row["seconds"] for row in parity["times"] if row["exit"] == 0}
def seconds(name):
    run = prep[name]
    assert len(run["samples"]) == 1 and run["samples"][0]["mode"] == "check"
    return run["compilers"]["candidate"]["preparation_ns"] / 1e9

warm = median([seconds("hit1"), seconds("hit2")])
rows = [
    ("Prepare the compiler in Wasmtime", ("Cache disabled", "Cached"),
     (seconds("cold"), warm), (f'{seconds("cold"):.1f} s', f"{warm * 1000:.0f} ms")),
    ("Run all 4,777 memory64 contracts", ("Python host", "Rust host"),
     (times["python"], times["rust"]), (f'{times["python"]:.0f} s', f'{times["rust"]:.0f} s')),
]
plt.rcParams.update({"svg.fonttype": "none", "svg.hashsalt": "goose-iteration-tools"})
fig, axes = plt.subplots(2, 1, figsize=(8, 4.1))
fig.subplots_adjust(left=0.20, right=0.96, top=0.87, bottom=0.08, hspace=0.84)
for ax, (title, labels, values, printed) in zip(axes, rows):
    ax.set_title(title, loc="left", fontsize=14, fontweight="bold", pad=6)
    ax.barh([0, 1], values, color=["#64748b", "#087f8c"], height=0.58)
    top = max(values)
    ax.set_xlim(0, top * 1.21)
    ax.set_yticks([0, 1], labels)
    ax.invert_yaxis()
    ax.set_xticks([])
    for pos, (value, label) in enumerate(zip(values, printed)):
        ax.text(value + top * 0.018, pos, label, va="center", fontsize=12)
    ax.tick_params(axis="y", length=0)
    ax.spines[:].set_visible(False)
fig.savefig(folder / "iteration.png", dpi=150)
plot = folder / "iteration.svg"
fig.savefig(plot, metadata={"Date": None, "Source": ", ".join(hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs)})
plot.write_text("\n".join(line.rstrip() for line in plot.read_text().splitlines()) + "\n")
