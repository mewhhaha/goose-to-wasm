#!/usr/bin/env python3
"""Render checked cold compiler emission timings, retaining unavailable cells."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import MaxNLocator

import compare_compilers as bench
import example_charts as charts
import langbench_charts as common

COMPILER_COLORS = ("#94a3b8", "#d39b28", "#087f8c")
DEFAULT_COMPILERS = tuple(zip(bench.COMPILERS,
    ("Previous C++", "Previous Goose", "Current Goose"), COMPILER_COLORS))
LEGACY_COMPILERS = {"cpp": "Previous C++", "goose56": "Goose 56", "goose57": "Goose 57"}
LABELS = {**charts.LABELS, "mandelbrot": "Mandelbrot"}


def command(record, report):
    words = record["command"]
    prefix = ["taskset", "-c", str(report["configuration"]["cpu"])]
    if words[:3] != prefix:
        raise ValueError("invocation does not retain the configured CPU binding")
    if not math.isfinite(record["wall_seconds"]) or record["wall_seconds"] <= 0:
        raise ValueError("invalid raw invocation duration")
    if record["status"] == "passed" and (record["exit_code"] != 0 or not isinstance(record["pid"], int) or record["pid"] <= 0):
        raise ValueError("successful invocation has no successful process record")
    return words[3:]


def checked_rows(report):
    schema = report.get("schema")
    if schema not in ("goose-compiler-comparison-v1", "goose-compiler-comparison-v2") or report.get("status") not in ("passed", "failed"):
        raise ValueError("a completed compiler comparison is required")
    if not report.get("inputs_unchanged") or not report.get("artifacts_unchanged"):
        raise ValueError("compiler comparison inputs or artifacts changed")
    order = bench.compiler_order(report)
    if schema == "goose-compiler-comparison-v1":
        if set(order) != {"cpp", "goose56", "goose57"}:
            raise ValueError("legacy report must contain its three compiler identities")
    else:
        labels = report.get("compiler_labels")
        if (order != bench.COMPILERS or not isinstance(labels, dict) or set(labels) != set(order) or
                any(not isinstance(label, str) or not label for label in labels.values())):
            raise ValueError("version 2 compiler order or labels are invalid")
    if set(report["compilers"]) != set(order):
        raise ValueError("compiler identities differ from declared order")
    for identity in report["compilers"].values():
        if bench.cold.sha256(Path(identity["path"])) != identity["sha256"]:
            raise ValueError("compiler binary changed")
    cases = {case["name"]: case for case in report["workloads"]}
    if len(cases) != len(report["workloads"]) or set(cases) != set(LABELS):
        raise ValueError("expected all eleven distinct workloads")
    for case in cases.values():
        if bench.cold.sha256(Path(case["source"])) != case["source_sha256"]:
            raise ValueError("workload source changed")
        if "expected_path" in case and bench.cold.sha256(Path(case["expected_path"])) != case["expected_sha256"]:
            raise ValueError("golden output changed")
    rows = bench.summaries(report)
    if rows != report.get("summary"):
        raise ValueError("published summaries differ from raw builds and validation proofs")
    if report["status"] == "passed" and not all(row["qualified"] for row in rows):
        raise ValueError("passing report contains unqualified cells")
    representatives = {}
    for record in report["builds"]:
        if record["compiler"] not in order or record["target"] not in bench.TARGETS or record["phase"] not in ("warmup", "measurement"):
            raise ValueError("unexpected compiler, target or sample phase")
        case = cases[record["workload"]]
        compiler = record["compiler"]
        expected = bench.build_command(report["compilers"][compiler]["path"], compiler, case,
            record["target"], record["artifact"], Path(report["configuration"]["stdlib"]).resolve())
        if command(record, report) != list(map(str, expected)):
            raise ValueError("build invocation differs from declared source, target or compiler")
        if record["status"] != "passed":
            continue
        if bench.cold.sha256(Path(record["artifact"])) != record["artifact_sha256"]:
            raise ValueError("emitted artifact changed")
        contract = case.get("expected_sha256", str(case.get("checksum")))
        key = ":".join([record["target"], record["artifact_sha256"], contract])
        if record["validation_key"] != key:
            raise ValueError("artifact validation is attached to another contract")
        representatives.setdefault(key, record)
    for key, record in representatives.items():
        proof = report["validations"].get(key)
        if not proof or proof["status"] != "passed":
            continue
        case = cases[record["workload"]]
        commands = proof["commands"]
        if len(commands) != 2 or any(item["status"] != "passed" for item in commands):
            raise ValueError("artifact proof lacks successful compilation/execution invocations")
        actual = [command(item, report) for item in commands]
        artifact = record["artifact"]
        if record["target"] == "wasm-direct":
            expected = [[report["configuration"]["node"], str(bench.ROOT / "scripts/run_wasm.mjs"), artifact],
                        [actual[1][0], str(bench.ROOT / "scripts/run_wasmtime.py"), artifact]]
            if Path(actual[1][0]).resolve() != Path(sys.executable).resolve() or actual != expected:
                raise ValueError("Wasm proof does not execute this artifact with both engines")
            outputs = commands
        else:
            executable = actual[1][0]
            expected = [report["configuration"]["cc"], *bench.C_FLAGS, artifact]
            if "checksum" in case:
                expected.append(str(bench.ROOT / "bench/host_input.c"))
            expected += ["-lm", "-ldl", "-pthread", "-o", executable]
            if actual != [expected, [executable]] or bench.cold.sha256(Path(executable)) != commands[0]["executable_sha256"]:
                raise ValueError("C proof does not compile and run this emitted artifact")
            outputs = commands[1:]
        if any(item["stdin"] != case["stdin"] or not bench.result_matches(item, case) for item in outputs):
            raise ValueError("artifact proof differs from the independent golden output")
    return charts.index_rows(rows, ("workload", "target", "compiler"))


def compiler_specs(report):
    specs = []
    for index, compiler in enumerate(bench.compiler_order(report)):
        if report["schema"] == "goose-compiler-comparison-v2":
            label = report["compiler_labels"][compiler]
        else:
            label = LEGACY_COMPILERS[compiler]
        specs.append((compiler, label, COMPILER_COLORS[index]))
    return tuple(specs)


def panel(ax, names, target, rows, compilers=DEFAULT_COMPILERS):
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#e2e8f0", linewidth=0.8)
    ax.spines[["top", "right", "left"]].set_visible(False)
    ax.spines["bottom"].set_color("#94a3b8")
    ax.tick_params(length=0, pad=8)
    ax.set_xticks(range(len(names)), [LABELS[name] for name in names], fontsize=9)
    ax.set_ylabel("source → artifact · milliseconds")
    ax.yaxis.set_major_locator(MaxNLocator(6))
    available = [charts.milliseconds(rows[name, target, compiler]["compile_wall_seconds"])
                 for name in names for compiler, _, _ in compilers if rows[name, target, compiler]["qualified"]]
    maximum = max((value + error for value, error in available), default=1)
    ax.set_ylim(0, maximum * 1.38)
    ax.set_xlim(-0.6, len(names) - 0.4)
    receipt = []
    width = 0.23
    for index, (compiler, label, color) in enumerate(compilers):
        for offset, name in enumerate(names):
            position = offset + (index - (len(compilers) - 1) / 2) * width
            row = rows[name, target, compiler]
            item = dict(workload=name, compiler=compiler, qualified=row["qualified"], median_ms=None, mad_ms=None)
            if row["qualified"]:
                value, error = charts.milliseconds(row["compile_wall_seconds"])
                ax.bar(position, value, width=width * 0.88, color=color, yerr=error,
                       error_kw=dict(ecolor="#334155", elinewidth=0.8, capsize=2))
                ax.text(position, value + error + maximum * 0.015, f"{value:.2f}",
                        ha="center", va="bottom", rotation=90, fontsize=8, color="#334155")
                item.update(median_ms=value, mad_ms=error)
            else:
                ax.text(position, maximum * 0.035, "unavailable", ha="center", va="bottom",
                        rotation=90, fontsize=8, color="#64748b")
            receipt.append(item)
    return receipt


def render(report_path, output):
    raw = report_path.read_bytes()
    report = json.loads(raw)
    rows = checked_rows(report)
    names = [case["name"] for case in report["workloads"]]
    compilers = compiler_specs(report)
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10,
                        "text.color": "#0f172a", "axes.labelcolor": "#475569",
                        "svg.fonttype": "none", "svg.hashsalt": "goose-compiler-comparison-v1"})
    fig, axes = plt.subplots(2, 1, figsize=(15, 10.5))
    fig.subplots_adjust(left=0.075, right=0.985, top=0.80, bottom=0.13, hspace=0.40)
    fig.text(0.075, 0.95, "Compiler source-to-artifact comparison", fontsize=21, weight="bold")
    fig.text(0.075, 0.91, "Fresh compiler process · Goose -O2 · source → artifact · lower is better", color="#475569")
    handles = [plt.Rectangle((0, 0), 1, 1, color=color) for _, _, color in compilers]
    fig.legend(handles, [label for _, label, _ in compilers], loc="upper left",
               bbox_to_anchor=(0.068, 0.88), ncols=len(compilers), frameon=False)
    values = {}
    for ax, target, title in zip(axes, bench.TARGETS, ("Direct WebAssembly", "Standalone C emission")):
        values[target] = panel(ax, names, target, rows, compilers)
        ax.set_title(title, loc="left", fontsize=13, pad=14)
    fig.text(0.075, 0.07, f"{report['samples']} measured builds per cell · labels: median ms · whiskers: ±MAD · independent panel scales · CPU {report['configuration']['cpu']}", fontsize=10, color="#475569")
    fig.text(0.075, 0.035, "OS caches retained · compiler bootstrap, downstream C compilation and output validation excluded · unavailable cells have no score", fontsize=10, color="#475569")
    output.mkdir(parents=True, exist_ok=True)
    path = output / "compiler-comparison.svg"
    digest = hashlib.sha256(raw).hexdigest()
    common.save_svg(fig, path, {"Date": None, "Title": "Compiler source-to-artifact comparison",
        "Source": f"{report_path} sha256:{digest}", "Description": report["method"]})
    return dict(schema="goose-compiler-comparison-chart-v1", report=str(report_path), report_sha256=digest,
                renderer_sha256=bench.cold.sha256(Path(__file__)),
                charts={path.name: dict(sha256=bench.cold.sha256(path), values=values)})


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("report", type=Path)
    cli.add_argument("--output-dir", type=Path, required=True)
    cli.add_argument("--receipt", type=Path, required=True)
    args = cli.parse_args()
    args.receipt.write_text(json.dumps(render(args.report.resolve(), args.output_dir), indent=2) + "\n")
