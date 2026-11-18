"""Plot the median wall times of full compiler rebuilds."""

import json
from pathlib import Path
from statistics import median

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import MaxNLocator

HERE = Path(__file__).resolve().parent
NATIVE = "#345369"
WASM = "#087d73"
OPT = "#4566a4"


def samples(name, rounds):
    data = json.loads((HERE / name).read_bytes())
    values = {}
    for row in data["samples"]:
        if row.get("kind", "emit") == "emit":
            assert row["output"] == data["expected"]
            values.setdefault(row["case"], []).append(row["wall_ns"] / 1e9)
    assert all(len(cell) == rounds for cell in values.values())
    return {key: median(cell) for key, cell in values.items()}


def bars(ax, names, values, colors):
    rects = ax.bar(names, values, width=0.63, color=colors)
    ax.bar_label(rects, fmt="%.2f s", padding=5, fontsize=10, weight="bold")
    ax.spines[:].set_visible(False)
    ax.yaxis.set_major_locator(MaxNLocator(nbins=5, integer=True))
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#dce2e7", linewidth=0.8)
    ax.tick_params(length=0, pad=6)
    ax.set_ylim(bottom=0, top=max(values) * 1.22)


def save(fig, stem):
    fig.savefig(HERE / (stem + ".png"), dpi=155)
    path = HERE / (stem + ".svg")
    fig.savefig(path, metadata={"Date": None})
    path.write_text("\n".join(line.rstrip() for line in path.read_text().splitlines()) + "\n")
    plt.close(fig)


def main():
    plt.rcParams.update({"font.size": 10, "svg.hashsalt": "compiler-frame-cost", "svg.fonttype": "none"})
    frozen = samples("frozen.json", 8)
    current = samples("deployment.json", 7)
    fig, axes = plt.subplots(1, 2, figsize=(10.6, 3.9), sharey=True)
    fig.subplots_adjust(left=0.055, right=0.99, top=0.73, bottom=0.19, wspace=0.15)
    fig.text(0.025, 0.925, "Seconds to rebuild the Goose compiler", fontsize=17, weight="bold")
    fig.text(0.025, 0.85, "Fresh process on one core · cached Wasmtime code · full compile from source")
    axes[0].set_title("Same frozen project · eight rounds", loc="left", fontsize=11)
    bars(axes[0], ["Previous\nnative", "Previous\nWasmtime", "Current\nnative", "Current\nWasmtime"],
         [frozen[k] for k in ("native-before", "wasm-before", "native-after", "wasm-after")],
         [NATIVE, WASM, NATIVE, WASM])
    axes[1].set_title("Compiler on its own sources · seven rounds", loc="left", fontsize=11)
    bars(axes[1], ["Native", "Wasmtime", "Wasmtime\nBinaryen -O3", "Wasmtime\nBinaryen -O4"],
         [current[k] for k in ("native", "direct", "O3", "O4")], [NATIVE, WASM, OPT, OPT])
    axes[0].set_ylim(0, max(*frozen.values(), *current.values()) * 1.22)
    save(fig, "rebuild")

    launch = samples("launch.json", 3)
    fig, ax = plt.subplots(figsize=(9.5, 3.9))
    fig.subplots_adjust(left=0.055, right=0.99, top=0.75, bottom=0.20)
    fig.text(0.025, 0.925, "First and subsequent compiler launches", fontsize=17, weight="bold")
    fig.text(0.025, 0.83, "Seconds to emit the complete compiler · median of three fresh processes · warm filesystem")
    keys = ("cold1", "cold8", "cached64", "cached_bundled64", "cold8_bundled32", "cached_bundled32", "native")
    names = ["64-bit cold\n1 core", "64-bit cold\n8 cores", "64-bit\ncached", "Bundled 64-bit\ncached",
             "Fixed 32-bit\ncold, 8 cores", "Fixed 32-bit\ncached", "Native"]
    bars(ax, names, [launch[k] for k in keys], [OPT, OPT, WASM, WASM, OPT, WASM, NATIVE])
    save(fig, "launch")


if __name__ == "__main__":
    main()
