"""Summarize the scores and medians already recorded by run.sh."""

import argparse
import json
from pathlib import Path
from statistics import median

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("out", type=Path)
args = parser.parse_args()
data = json.loads((args.out / "evidence.json").read_text())
shapes = json.loads((args.out / "shape.json").read_text())
modes = ["baseline", "estimate", "sampled"]
for mode in modes:
    works = sum(
        all(r["matches_native"] for r in rows if r["mode"] == mode)
        for rows in data["results"].values()
    )
    extra = sum(
        row["outcomes"][mode]["status"] == row["outcomes"]["native"]["status"]
        and row["outcomes"][mode]["stdout"] == row["outcomes"]["native"]["stdout"]
        and row["outcomes"][mode]["stderr"] == row["outcomes"]["native"]["stderr"]
        for row in shapes.values()
    )
    print(mode, works + extra, "/", len(data["results"]) + len(shapes))
for name in ["blot-parse", "self-check", "self-emit"]:
    print(name)
    for mode in modes:
        rows = [r for r in data["results"][name] if r["mode"] == mode]
        seconds = median(r["timing"]["start_function_ns"] for r in rows) / 1e9
        engine = median(r["timing"]["engine_total_ns"] for r in rows) / 1e9
        cost = median(r["metrics"].get("full_sizing_ns", 0) for r in rows) / 1e6
        work = median(r["metrics"].get("inventory_ns", 0) for r in rows) / 1e6
        print(
            f"  {mode} n={len(rows)} start={seconds:.3f}s engine={engine:.3f}s sizing={cost:.2f}ms inventory={work:.2f}ms"
        )
for name, shape in shapes.items():
    print(name, shape["input_bytes"])
    for mode in modes:
        r = shape["outcomes"][mode]
        print(
            mode,
            r["status"],
            r["stderr"].strip(),
            r["metrics"].get("rooms"),
            r["metrics"].get("full_sizing_ns", 0) / 1e6,
        )
