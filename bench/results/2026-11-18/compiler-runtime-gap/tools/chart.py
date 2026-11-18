"""Render the whole-project self-check times and verify the measured controls."""
import json
from pathlib import Path
from statistics import median

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

folder = Path(__file__).resolve().parents[1]
controls = json.loads((folder/"controls.json").read_text())
profile = json.loads((folder/"profile.json").read_text())
assert controls["workload_archive_sha256"] == profile["workload_archive_sha256"]
assert controls["modules"]["default64"] == profile["wasm"]
assert controls["v8"]["source_sha256"] == profile["wasm"]["sha256"]
rows = controls["runs"]
series = [("native", "Native · Clang"), ("default64", "Wasmtime · default 64-bit"),
          ("v8", "V8 · same 64-bit module"), ("profile64", "Wasmtime · project-sized 64-bit"),
          ("profile32", "Wasmtime · project-sized 32-bit")]
fig, ax = plt.subplots(figsize=(9, 4.25))
fig.subplots_adjust(left=.37, right=.87, top=.77, bottom=.15)
plt.rcParams.update({"svg.hashsalt": "goose-runtime-gap", "svg.fonttype": "none"})
for i, (label, name) in enumerate(series):
    checks = [r for r in rows if r["mode"] == "check" and r["label"] == label]
    assert sorted(r["round"] for r in checks) == [1, 2, 3, 4]
    emitted, = [r["emitted"] for r in rows if r["mode"] == "emit" and r["label"] == label]
    assert emitted == controls["expected_emission"]
    value = median(r["wall_ns"] for r in checks) / 1e9
    color = {"native": "#5c7081", "v8": "#62758e", "profile32": "#187469"}.get(label, "#327b94")
    ax.barh(i, value, height=.56, color=color)
    ax.text(value + .12, i, f"{value:.2f} s", va="center", fontsize=11)
ax.set_yticks(range(len(series)), [name for _, name in series], fontsize=11)
ax.invert_yaxis()
ax.tick_params(axis="both", length=0)
ax.spines[:].set_visible(False)
ax.set_xticks([])
fig.text(.04, .92, "Time to check the same compiler project", fontsize=17, weight="bold")
fig.text(.04, .82, "Four runs per configuration · median seconds · shorter is faster", fontsize=11)
fig.text(.04, .055, "Wasm engines time guest execution in fresh instances of prepared modules. Native includes process launch.", fontsize=9)
fig.savefig(folder/"comparison.png", dpi=150)
svg = folder/"comparison.svg"
fig.savefig(svg, metadata={"Date": None})
svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines())+"\n")
