"""Plot end-to-end wall times for cold, resident and precompiled launches."""

import json
from pathlib import Path
from statistics import median

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

folder = Path(__file__).resolve().parent
navy = "#2b5169"
teal = "#00796b"
gray = "#64748b"


def draw(filename, title, subtitle, values, *, width=8.2, height=3.1, left=0.28):
    plt.rcParams.update(
        {
            "svg.fonttype": "none",
            "svg.hashsalt": "compiler-request-" + filename,
            "font.size": 11,
        }
    )
    fig, ax = plt.subplots(figsize=(width, height))
    fig.subplots_adjust(left=left, right=0.89, bottom=0.17, top=0.70)
    fig.text(0.045, 0.91, title, fontsize=16, weight="bold")
    fig.text(0.045, 0.80, subtitle)
    for i, (label, values_ns, color) in enumerate(values):
        assert len(values_ns) == 3, label
        bars = ax.barh(i, median(values_ns) / 1e9, color=color, height=0.62)
        ax.bar_label(bars, fmt="%.2f s", padding=5)
    ax.set_yticks(range(len(values)), [label for label, _, _ in values])
    ax.invert_yaxis()
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0)
    ax.set_axisbelow(True)
    ax.grid(axis="x", color="#dce2e7", linewidth=0.7)
    fig.savefig(folder / (filename + ".png"), dpi=150)
    svg = folder / (filename + ".svg")
    fig.savefig(svg, metadata={"Date": None})
    svg.write_text(
        "\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n"
    )
    plt.close(fig)


rows = json.loads((folder / "self-emit.json").read_bytes())["samples"]
cases = [
    ("New Wasmtime process", "wasmtime", "cold", navy),
    ("Resident Wasmtime", "wasmtime", "hot", teal),
    ("Resident after edit", "wasmtime", "edited", teal),
    ("Native compiler process", "native", "fresh", gray),
]
draw(
    "latency",
    "Our Goose compiler rebuilding itself",
    "Seconds to emit complete Wasm · median of three rounds · warm filesystem",
    [
        (
            label,
            [r["ns"] for r in rows if r["host"] == host and r["mode"] == mode],
            color,
        )
        for label, host, mode, color in cases
    ],
)

rows = json.loads((folder / "launch.json").read_bytes())["samples"]
cases = [
    ("Cold, one core", "cold1", navy),
    ("Cold, eight cores", "cold8", navy),
    ("Cold, eight cores, bundled 32-bit", "cold8_bundled32", navy),
    ("Cached compiler", "cached64", teal),
    ("Cached, bundled memory64", "cached_bundled64", teal),
    ("Cached, bundled memory32", "cached_bundled32", teal),
    ("Native compiler", "native", gray),
]
draw(
    "launch",
    "Where self-compilation time goes",
    "Fresh process to complete Wasm · seconds · median of three rounds",
    [
        (
            label,
            [r["wall_ns"] for r in rows if r["case"] == case and r["kind"] == "emit"],
            color,
        )
        for label, case, color in cases
    ],
    width=9.0,
    height=4.5,
    left=0.35,
)
