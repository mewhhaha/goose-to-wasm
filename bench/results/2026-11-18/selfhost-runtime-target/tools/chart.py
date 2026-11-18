"""Plot each experiment relative to its own interleaved native control."""
from hashlib import sha256
import json
from pathlib import Path
from statistics import median

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

report = Path(__file__).resolve().parents[1]
experiments = [
    ("Skip return tracking\nCPU 0", "no-return-targets.json", "baseline", "candidate"),
    ("Two local passes\nCPU 7", "local-passes.json", "direct", "local-passes"),
    ("Binaryen -O3\nCPU 5", "O3.json", "direct", "O3"),
]
plt.rcParams.update({"svg.hashsalt": "goose-selfhost-1x", "svg.fonttype": "none", "font.family": "DejaVu Sans"})
fig, axes = plt.subplots(1, 2, figsize=(10, 4.3), sharey=True)
fig.subplots_adjust(left=.085, right=.98, top=.76, bottom=.26, wspace=.14)
fig.text(.085, .92, "Self-hosted compiler execution", fontsize=16, fontweight="bold")
fig.text(.085, .85, "Resident Wasmtime, profiled 32-bit memory  ·  lower is faster", fontsize=10, color="#475569")
sources = {}
for axis, mode, title in zip(axes, ("check", "emit"), ("Check project", "Emit compiler.wasm"), strict=True):
    for position, (_, name, direct, candidate) in enumerate(experiments):
        data = (report / name).read_bytes()
        sources[name] = sha256(data).hexdigest()
        rows = [r for r in json.loads(data)["samples"] if r["workload"] == mode]
        native = median(r["wall_ns"] for r in rows if r["label"] == "native")
        for label, offset, color, legend in [(direct, -.18, "#53667a", "Direct Wasm"), (candidate, .18, "#087f8c", "Experiment")]:
            value = median(r["wall_ns"] for r in rows if r["label"] == label) / native
            bar = axis.bar(position + offset, value, width=.34, color=color, label=legend)
            axis.bar_label(bar, labels=[f"{value:.2f}"], padding=3, fontsize=9)
    axis.set_title(title, loc="left", fontsize=11, fontweight="bold")
    axis.set_xticks(range(len(experiments)), [row[0] for row in experiments], fontsize=9)
    axis.axhline(1.9, linestyle="--", color="#9b5916", linewidth=1.5, label="1.9× target")
    axis.set_ylim(0, max(4, axis.get_ylim()[1]))
    axis.spines[["top", "right", "left"]].set_visible(False)
    axis.tick_params(axis="both", length=0)
    axis.set_axisbelow(True)
    axis.grid(axis="y", color="#e2e8f0")
axes[0].set_ylabel("Time / native", fontsize=10)
handles, labels = axes[0].get_legend_handles_labels()
legend = dict(zip(labels, handles))
order = ["Direct Wasm", "Experiment", "1.9× target"]
fig.legend([legend[label] for label in order], order, frameon=False, ncol=3, loc="lower left", bbox_to_anchor=(.075,.075))
fig.text(.085, .04, "Each pair uses the native median from its own run. Two rounds on CPU 0 and three on CPUs 7 and 5.", fontsize=9, color="#475569")
output = report / "runtime.svg"
fig.savefig(output, metadata={"Date": None, "Title": "Compiler execution time relative to native", "Source": json.dumps(sources, sort_keys=True)})
output.write_text("\n".join(line.rstrip() for line in output.read_text().splitlines()) + "\n")
