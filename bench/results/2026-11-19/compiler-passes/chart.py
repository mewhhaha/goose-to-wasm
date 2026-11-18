"""Regenerate the two README charts from the retained request samples."""

import json
from pathlib import Path
from statistics import median

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = Path(__file__).resolve().parent
NATIVE, WASM, COLD = "#345369", "#087d73", "#4566a4"


def medians(name, **filters):
    rows = json.loads((HERE / name).read_bytes())["samples"]
    cells = {}
    for row in rows:
        if all(row[k] == v for k, v in filters.items()):
            cells.setdefault(row["case"], []).append(row["wall_ns"] / 1e9)
    return {key: median(value) for key, value in cells.items()}


def panel(ax, labels, values, colors, unit):
    bars = ax.bar(labels, values, width=0.66, color=colors)
    fmt = "%.2f s"
    if unit == "ms":
        fmt = "%.0f ms"
    ax.bar_label(bars, fmt=fmt, padding=4, size=10, weight="bold")
    ax.set_ylim(0, max(values) * 1.18)
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#dce2e7", linewidth=0.8)
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=5)


def save(fig, name):
    fig.savefig(HERE / (name + ".png"), dpi=150)
    path = HERE / (name + ".svg")
    fig.savefig(path, metadata={"Date": None})
    path.write_text("\n".join(line.rstrip() for line in path.read_text().splitlines()) + "\n")
    plt.close(fig)


def main():
    plt.rcParams.update({"font.size": 10, "svg.hashsalt": "compiler-passes", "svg.fonttype": "none"})
    fig, axes = plt.subplots(1, 2, figsize=(9.8, 3.8), layout="constrained")
    fig.suptitle("Time to compile the same Goose sources", weight="bold", fontsize=16)
    labels = ["Previous\nnative", "Current\nnative", "Previous\nWasmtime", "Current\nWasmtime"]
    order = ["native-before", "native-after", "wasm-before", "wasm-after"]
    frozen = medians("frozen.json")
    axes[0].set_title("Compiler project · nine rounds", loc="left", fontsize=11)
    panel(axes[0], labels, [frozen[k] for k in order], [NATIVE, NATIVE, WASM, WASM], "s")
    literals = medians("literals.json", unique=8192)
    axes[1].set_title("8,192 unique string literals · seven rounds", loc="left", fontsize=11)
    panel(axes[1], labels, [1000 * literals[k.replace("-", "_")] for k in order],
          [NATIVE, NATIVE, WASM, WASM], "ms")
    save(fig, "compilation")

    launch = medians("launch.json", kind="emit")
    fig, ax = plt.subplots(figsize=(9.5, 3.7), layout="constrained")
    fig.suptitle("First and subsequent compiler launches", weight="bold", fontsize=16)
    ax.set_title("Seconds to rebuild its own source · three fresh processes per case", loc="left", fontsize=11)
    order = ["cold1", "cold8", "cached64", "cached_bundled64", "cold8_bundled32", "cached_bundled32", "native"]
    labels = ["64-bit cold\n1 core", "64-bit cold\n8 cores", "64-bit\ncached", "Bundled 64-bit\ncached",
              "Fixed 32-bit\ncold, 8 cores", "Fixed 32-bit\ncached", "Native"]
    panel(ax, labels, [launch[k] for k in order], [COLD, COLD, WASM, WASM, COLD, WASM, NATIVE], "s")
    save(fig, "launch")


if __name__ == "__main__":
    main()
