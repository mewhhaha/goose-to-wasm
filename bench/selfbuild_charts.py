"""Chart fresh compiler processes from paired rebuild and launch measurements."""

import argparse
from pathlib import Path
from statistics import median

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

from report_io import decode_report

NATIVE = "#345369"
WASM = "#087d73"
COLD = "#4566a4"


def rebuilds(path, cases):
    report = decode_report(path.read_bytes())
    samples = {case: {} for case in cases}
    for row in report["samples"]:
        if row.get("kind", "emit") != "emit":
            continue
        group = samples[row["case"]]
        if row["output"] != report["expected"] or row["round"] in group or row["wall_ns"] <= 0:
            raise ValueError(f"Invalid rebuild in {path}: {row['case']} round {row['round']}")
        group[row["round"]] = row["wall_ns"] / 1e9
    rounds = set(samples[cases[0]])
    if not rounds or any(set(group) != rounds for group in samples.values()):
        raise ValueError(f"Incomplete rebuild rounds in {path}")
    return [median(samples[case].values()) for case in cases], len(rounds)


def panel(ax, labels, times, colors):
    bars = ax.bar(labels, times, color=colors, width=0.63)
    ax.bar_label(bars, fmt="%.2f s", padding=4, weight="bold")
    ax.set_ylim(0, max(times) * 1.2)
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#dce2e7", linewidth=0.8)
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=5)


def save(fig, path):
    fig.savefig(path.with_suffix(".png"), dpi=150)
    svg = path.with_suffix(".svg")
    fig.savefig(svg, metadata={"Date": None})
    svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="directory containing frozen.json, current.json and launch.json")
    args = parser.parse_args()
    directory = args.directory
    plt.rcParams.update({"font.size": 10, "svg.hashsalt": "selfbuild", "svg.fonttype": "none"})

    frozen, pairs = rebuilds(directory / "frozen.json", ["native-before", "native-after", "wasm-before", "wasm-after"])
    current, own_pairs = rebuilds(directory / "current.json", ["native", "wasm"])
    fig, (left, right) = plt.subplots(1, 2, figsize=(9.0, 3.7), width_ratios=[2, 1], sharey=True, layout="constrained")
    fig.suptitle("Seconds to rebuild the Goose compiler", fontsize=16, weight="bold")
    left.set_title(f"Same frozen project · {pairs} rounds", loc="left", fontsize=11)
    right.set_title(f"Current compiler on itself · {own_pairs} rounds", loc="left", fontsize=11)
    panel(left, ["Previous\nnative", "Current\nnative", "Previous\nWasmtime", "Current\nWasmtime"], frozen, [NATIVE, NATIVE, WASM, WASM])
    panel(right, ["Native", "Wasmtime"], current, [NATIVE, WASM])
    left.set_ylim(0, max(*frozen, *current) * 1.2)
    save(fig, directory / "rebuild")

    cases = ["cold1", "cold8", "cached64", "cached_bundled64", "cold8_bundled32", "cached_bundled32", "native"]
    times, rounds = rebuilds(directory / "launch.json", cases)
    fig, ax = plt.subplots(figsize=(9.5, 3.8), layout="constrained")
    fig.suptitle("Cold and cached compiler launches", fontsize=16, weight="bold")
    ax.set_title(f"Seconds to rebuild its own sources · {rounds} fresh processes per configuration", loc="left", fontsize=11)
    labels = ["64-bit cold\n1 core", "64-bit cold\n8 cores", "64-bit\ncached", "Bundled 64-bit\ncached",
              "Fixed 32-bit\ncold, 8 cores", "Fixed 32-bit\ncached", "Native"]
    panel(ax, labels, times, [COLD, COLD, WASM, WASM, COLD, WASM, NATIVE])
    save(fig, directory / "launch")


if __name__ == "__main__":
    main()
