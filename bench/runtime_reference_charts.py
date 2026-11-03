#!/usr/bin/env python3
"""Plot fresh confirmation rounds against the frozen selected native target."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET

import langarena as arena

GROUPS = (
    ("Adapted LangArena workloads", (
        ("CLBG::Fannkuchredux", "Fannkuch"), ("CLBG::Mandelbrot", "Mandelbrot"),
        ("Etc::Sieve", "Sieve"), ("Hash::CRC32", "CRC32"),
        ("Hash::SHA256", "Custom hash"), ("Sort::Merge", "Merge sort"),
        ("Sort::Quick", "Quicksort"))),
    ("Example kernel adapters", (
        ("Example::Life", "Life"), ("Example::Sorting", "Insertion sort"),
        ("Example::Sudoku", "Sudoku"))),
)
SERIES = (("anchor", "Native GCC -O2", "#727b8e"),
          ("direct", "Direct Wasm", "#087f8c"),
          ("wasm", "Selected Wasm", "#ce862a"))


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def validate(report):
    assert report["schema"] == "goose-runtime-reference-v1"
    assert report["status"] == "passed" and not report["failures"]
    config = report["configuration"]
    assert not config["smoke"] and config["samples"] >= 9 and config["pilot_samples"] >= 3
    assert config["engines"] == ["wasmtime"] and config["wasmtime_mode"] == "precompiled"
    expected_tasks = {task for _, group in GROUPS for task, _ in group}
    assert {case["name"] for case in report["workloads"]} == expected_tasks
    for path, expected in report["inputs"].items():
        assert digest(path) == expected, path
    rows = [row for row in report["observations"] if row["phase"] == "confirm"]
    assert all(row["status"] == "passed" for row in rows)
    indexed = {}
    for row in rows:
        key = row["task"], row["variant"], row["engine"], row["round"]
        assert key not in indexed, key
        assert math.isfinite(row["timed_region_seconds"]) and 0 < row["timed_region_seconds"] <= row["wall_seconds"]
        indexed[key] = row["timed_region_seconds"]
    table = []
    for _, group in GROUPS:
        for task, label in group:
            selection = report["selection"][task]
            native = selection["native"]["variant"]
            wasm = selection["wasm"]["wasmtime"]["variant"]
            variants = {"anchor": ("native-gcc-O2-generic", "native"),
                        "native": (native, "native"), "direct": ("direct-O2", "wasmtime"),
                        "wasm": (wasm, "wasmtime")}
            row = {"task": task, "label": label, "native_reference": native, "wasm_reference": wasm,
                   "wasm_self_reference": wasm == "direct-O2", "times": {}, "relative_to_native": {}}
            for name, (variant, engine) in variants.items():
                samples = [indexed[task, variant, engine, round_] for round_ in range(config["samples"])]
                row["times"][name] = arena.summarize(samples)
                ratios = [indexed[task, variant, engine, round_] / indexed[task, native, "native", round_]
                          for round_ in range(config["samples"])]
                row["relative_to_native"][name] = arena.summarize(ratios)
            row["direct_over_selected_wasm"] = arena.summarize([
                indexed[task, "direct-O2", "wasmtime", round_] / indexed[task, wasm, "wasmtime", round_]
                for round_ in range(config["samples"])])
            table.append(row)
    return table


def apply_climb(table, report, reference, reference_sha256):
    assert report["schema"] == "goose-runtime-climb-v1" and report["status"] == "passed"
    assert report["reference_sha256"] == reference_sha256
    assert report["workloads"] == reference["workloads"]
    assert report["selection"] == reference["selection"]
    assert report["configuration"]["cpu"] == reference["configuration"]["cpu"]
    assert report["baseline_compiler_sha256"] == reference["inputs"][reference["configuration"]["goose"]]
    pins = report["input_sha256"]
    assert pins[report["configuration"]["reference"]] == reference_sha256
    assert pins[report["configuration"]["goose"]] == report["candidate_compiler_sha256"]
    assert all(pins.get(path) == expected for path, expected in reference["inputs"].items())
    assert all(command["returncode"] == 0 and not command["error"] for command in report["commands"])
    samples = report["configuration"]["samples"]
    assert type(samples) is int and samples >= 9
    for path, expected in pins.items():
        assert digest(path) == expected, path
    cases = {case["name"]: case for case in report["workloads"]}
    assert set(cases) == {row["task"] for row in table}
    assert set(report["artifacts"]) == set(cases)
    expected_rows = set()
    for task, case in cases.items():
        selection = reference["selection"][task]
        variants = {"direct-O2", "native-gcc-O2-generic", selection["native"]["variant"],
                    selection["wasm"]["wasmtime"]["variant"]}
        artifacts = report["artifacts"][task]
        assert set(artifacts) == variants | {"candidate-O2"}
        for variant in variants:
            assert artifacts[variant] == reference["artifacts"][case["id"] + "/" + variant]
        candidate = artifacts["candidate-O2"]
        assert candidate["variant"] == "candidate-O2" and candidate["family"] == "direct"
        for artifact in artifacts.values():
            assert pins[artifact["path"]] == artifact["sha256"]
            if artifact["family"] != "native":
                assert pins[artifact["aot_path"]] == artifact["aot_sha256"]
        expected_rows.add((task, "candidate-O2", "qualify", 0))
        expected_rows.update((task, variant, "measure", i)
                             for variant in artifacts for i in range(samples))
    indexed = {}
    observed_rows = set()
    for observation in report["observations"]:
        task, variant, round_ = observation["task"], observation["variant"], observation["round"]
        phase = observation["phase"]
        identity = task, variant, phase, round_
        assert type(round_) is int and identity in expected_rows and identity not in observed_rows
        observed_rows.add(identity)
        profile = "run"
        if phase == "qualify":
            profile = "test"
        engine = "wasmtime"
        if report["artifacts"][task][variant]["family"] == "native":
            engine = "native"
        assert observation["engine"] == engine and observation["profile"] == profile
        expected = cases[task][profile]["checksum"]
        assert observation["checksum"] == observation["expected_checksum"] == expected
        assert observation["revision_exit"] == 0
        elapsed, wall = observation["timed_region_seconds"], observation["process_wall_seconds"]
        assert math.isfinite(elapsed) and math.isfinite(wall) and 0 < elapsed <= wall
        if phase != "measure":
            continue
        key = task, variant, round_
        assert key not in indexed
        indexed[key] = elapsed
    assert observed_rows == expected_rows
    for row in table:
        task = row["task"]
        variants = {"anchor": "native-gcc-O2-generic", "native": row["native_reference"],
                    "direct": "candidate-O2", "wasm": row["wasm_reference"], "baseline": "direct-O2"}
        for name, variant in variants.items():
            row["times"][name] = arena.summarize([indexed[task, variant, i] for i in range(samples)])
            row["relative_to_native"][name] = arena.summarize([
                indexed[task, variant, i] / indexed[task, row["native_reference"], i]
                for i in range(samples)])
        row["direct_over_selected_wasm"] = arena.summarize([
            indexed[task, "candidate-O2", i] / indexed[task, row["wasm_reference"], i]
            for i in range(samples)])
        row["baseline_over_current"] = arena.summarize([
            indexed[task, "direct-O2", i] / indexed[task, "candidate-O2", i] for i in range(samples)])
        row["wasm_reference_is_baseline"] = row.pop("wasm_self_reference")
    return samples


def validate_kernels(report, reference, reference_sha256, compiler):
    """Use fresh named-compiler rounds while preserving historical byte paths."""
    assert reference["schema"] == "goose-runtime-reference-v1"
    assert reference["status"] == "passed" and not reference["failures"]
    assert reference["configuration"]["pilot_samples"] >= 3
    assert reference["configuration"]["engines"] == ["wasmtime"]
    assert reference["configuration"]["wasmtime_mode"] == "precompiled"
    assert report["schema"] == "goose-frozen-kernel-pairs-v1"
    assert report["status"] == "passed" and not report["failures"] and report["coverage_exact"]
    config = report["configuration"]
    samples = config["samples"]
    assert type(samples) is int and samples >= 9 and config["references"]
    assert config["cpu"] == reference["configuration"]["cpu"] == 2
    assert compiler in config["compilers"] and set(config["compilers"]) == set(report["compilers"])
    assert report["workloads"] == reference["workloads"] and report["selection"] == reference["selection"]
    cases = {case["name"]: case for case in report["workloads"]}
    assert len(cases) == 10 and set(cases) == {task for _, group in GROUPS for task, _ in group}
    assert set(report["artifacts"]) == set(report["reference_roles"]) == set(cases)
    pins = report["input_sha256"]
    assert pins == report["input_sha256_after"]
    assert pins[config["reference"]] == reference_sha256
    for path, expected in pins.items():
        assert digest(path) == expected, path
    # Historical scripts may have changed in the workspace. Only matched old
    # bytes in the recorded resolution map stand in for their original paths.
    for path, expected in reference["inputs"].items():
        checked = report["historical_input_resolution"][path + "@" + expected]
        assert pins[checked] == expected, path
    assert report["host_build"] == reference["host_build"]
    host = report["host_build"]
    assert pins[config["host"]] == host["host_sha256"]
    assert pins[host["library"]] == host["library_sha256"]
    for name, build in report["compilers"].items():
        assert config["compilers"][name] == build["binary"]
        assert pins[build["binary"]] == build["sha256"]
        for category in ("headers", "patches"):
            for path, expected in build["source"][category].items():
                assert pins[build["resolved_source_inputs"][category + "/" + path]] == expected
    assert report["commands"] and all(row["returncode"] == 0 and not row["error"] for row in report["commands"])
    expected_rows = set()
    for task, case in cases.items():
        selected = reference["selection"][task]
        roles = {"original_direct": "direct-O2", "gcc_O2_anchor": "native-gcc-O2-generic",
                 "selected_native": selected["native"]["variant"],
                 "selected_wasm": selected["wasm"]["wasmtime"]["variant"]}
        assert report["reference_roles"][task] == {role: "ref--" + variant for role, variant in roles.items()}
        artifacts = report["artifacts"][task]
        assert set(artifacts) == set(config["compilers"]) | set(report["reference_roles"][task].values())
        for variant in set(roles.values()):
            artifact = artifacts["ref--" + variant]
            original = reference["artifacts"][case["id"] + "/" + variant]
            for field in ("variant", "family", "sha256"):
                assert artifact[field] == original[field]
            if artifact["family"] != "native":
                assert artifact["aot_sha256"] == original["aot_sha256"]
        for name in config["compilers"]:
            assert artifacts[name]["family"] == "direct" and artifacts[name]["variant"] == name
            assert artifacts[name]["compiler_sha256"] == report["compilers"][name]["sha256"]
        for artifact in artifacts.values():
            assert pins[artifact["path"]] == artifact["sha256"]
            if artifact["family"] != "native":
                assert pins[artifact["aot_path"]] == artifact["aot_sha256"]
        expected_rows.update((task, variant, "qualify", 0) for variant in artifacts)
        expected_rows.update((task, variant, "measure", i) for variant in artifacts for i in range(samples))
    indexed = {}
    observed = set()
    for row in report["observations"]:
        task, variant, phase, round_ = row["task"], row["variant"], row["phase"], row["round"]
        identity = task, variant, phase, round_
        assert type(round_) is int and identity in expected_rows and identity not in observed
        observed.add(identity)
        artifact = report["artifacts"][task][variant]
        engine = "wasmtime"
        if artifact["family"] == "native":
            engine = "native"
        profile = "run"
        if phase == "qualify":
            profile = "test"
        assert row["profile"] == profile and row["engine"] == engine and row["runtime_affinity"] == [2]
        assert row["checksum"] == row["expected_checksum"] == cases[task][profile]["checksum"]
        assert row["revision_exit"] == 0 and row["artifact_sha256"] == artifact["sha256"]
        assert row["aot_sha256"] == artifact.get("aot_sha256")
        elapsed, wall = row["timed_region_seconds"], row["process_wall_seconds"]
        assert math.isfinite(elapsed) and math.isfinite(wall) and 0 < elapsed <= wall
        if phase == "measure":
            indexed[task, variant, round_] = elapsed
    assert observed == expected_rows and report["observations_expected"] == len(expected_rows)
    table = []
    for _, group in GROUPS:
        for task, label in group:
            roles = report["reference_roles"][task]
            variants = {"anchor": roles["gcc_O2_anchor"], "native": roles["selected_native"],
                        "direct": compiler, "wasm": roles["selected_wasm"], "baseline": roles["original_direct"]}
            row = {"task": task, "label": label, "native_reference": roles["selected_native"],
                   "wasm_reference": roles["selected_wasm"], "direct_compiler": compiler,
                   "baseline_reference": roles["original_direct"],
                   "wasm_reference_is_baseline": roles["selected_wasm"] == roles["original_direct"],
                   "times": {}, "relative_to_native": {}}
            for name, variant in variants.items():
                row["times"][name] = arena.summarize([indexed[task, variant, i] for i in range(samples)])
                row["relative_to_native"][name] = arena.summarize([
                    indexed[task, variant, i] / indexed[task, roles["selected_native"], i] for i in range(samples)])
            for name, numerator, denominator in [("direct_over_selected_wasm", compiler, roles["selected_wasm"]),
                                                   ("baseline_over_current", roles["original_direct"], compiler)]:
                row[name] = arena.summarize([indexed[task, numerator, i] / indexed[task, denominator, i]
                                           for i in range(samples)])
            table.append(row)
    return table


def render(report, table, destination):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    matplotlib.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10,
                               "svg.fonttype": "none", "svg.hashsalt": "goose-runtime-targets"})
    lookup = {row["task"]: row for row in table}
    figure, axes = plt.subplots(2, 1, figsize=(13.5, 8.6), gridspec_kw={"height_ratios": [1, 1]})
    figure.patch.set_facecolor("white")
    labels = []
    for axis, (title, group) in zip(axes, GROUPS):
        for spine in ("top", "right", "left"):
            axis.spines[spine].set_visible(False)
        axis.spines["bottom"].set_color("#9aabc3")
        axis.tick_params(axis="both", length=0, colors="#405372")
        axis.set_axisbelow(True)
        axis.grid(axis="y", color="#e3eaf3", linewidth=.8)
        axis.set_yscale("log", base=2)
        axis.set_ylabel("time / selected native time")
        axis.set_title(title, loc="left", fontweight="bold", color="#111b30", pad=18)
        maximum = 1.0
        minimum = .5
        for series_index, (name, _, color) in enumerate(SERIES):
            values = [lookup[task]["relative_to_native"][name] for task, _ in group]
            centers = [index + (series_index - 1) * .245 for index in range(len(group))]
            medians = [value["median"] for value in values]
            errors = [value["mad"] for value in values]
            axis.bar(centers, medians, width=.225, color=color, zorder=3)
            axis.errorbar(centers, medians, yerr=errors, fmt="none", color="#405372", capsize=2, linewidth=.8)
            for (task, _), center, value in zip(group, centers, values):
                label = f"{value['median']:.2f}×"
                labels.append({"task": task, "series": name, "label": label,
                               "median": value["median"], "mad": value["mad"]})
                annotation = axis.annotate(label, (center, value["median"] + value["mad"]), xytext=(0, 5),
                                           textcoords="offset points", ha="center", fontsize=8, color="#405372")
                annotation.set_gid(f"target-label-{len(labels)}")
                maximum = max(maximum, value["median"] + value["mad"])
                minimum = min(minimum, value["median"] - value["mad"])
        axis.axhline(1, color="#30415c", linewidth=1.1, linestyle=(0, (4, 3)))
        axis.set_ylim(minimum * .7, maximum * 1.7)
        ticks = [2.0 ** exponent for exponent in range(-5, 9) if minimum * .7 < 2.0 ** exponent < maximum * 1.7]
        axis.set_yticks(ticks, [f"{tick:g}×" for tick in ticks])
        axis.set_xticks(range(len(group)), [label for _, label in group])
        axis.set_xlim(-.65, len(group) - .35)
    figure.suptitle("Warmed execution targets", x=.075, y=.97, ha="left", fontsize=22,
                    fontweight="bold", color="#111b30")
    figure.text(.075, .923, "Fresh confirmation rounds · lower is better · selected native reference = 1×",
                color="#405372")
    handles = [plt.Rectangle((0, 0), 1, 1, color=color) for _, _, color in SERIES]
    figure.legend(handles, [label for _, label, _ in SERIES], loc="upper left", bbox_to_anchor=(.07, .905),
                  ncol=3, frameon=False)
    config = report["configuration"]
    rounds = f"{config['pilot_samples']} selection rounds · {config['samples']} fresh confirmation rounds"
    if report.get("climb_comparison"):
        rounds = f"{config['pilot_samples']} prior selection rounds · {config['samples']} fresh paired rounds"
    date = report["started_utc"][:10]
    figure.text(.075, .056, date + " · " + rounds + " · bars: median paired ratios · whiskers: ±MAD",
                fontsize=9, color="#405372")
    cpu = "unknown CPU"
    for line in report["environment"].get("cpuinfo", "").splitlines():
        if line.startswith("model name"):
            cpu = line.partition(":")[2].strip().replace(" 8-Core Processor", "")
            break
    version = report["host_build"]["version"]
    figure.text(.075, .032, f"{cpu}, shared host · CPU {config['cpu']} · Wasmtime {version} AOT · preparation excluded · empirical references",
                fontsize=9, color="#405372")
    figure.subplots_adjust(left=.075, right=.98, top=.80, bottom=.115, hspace=.56)
    destination.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(destination, metadata={"Date": None})
    destination.write_text("\n".join(line.rstrip() for line in destination.read_text().splitlines()) + "\n")
    plt.close(figure)
    return labels


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--climb", "--climb-report", type=Path, help="fresh candidate comparisons using the prior frozen references")
    parser.add_argument("--compiler", help="named compiler to show from a frozen kernel-pairs report")
    parser.add_argument("--output", type=Path, default=Path("bench/charts/runtime-targets.svg"))
    parser.add_argument("--verification", type=Path, required=True)
    args = parser.parse_args()
    report = json.loads(args.report.read_text())
    climb = None
    if args.climb:
        climb = json.loads(args.climb.read_text())
    named = climb is not None and climb["schema"] == "goose-frozen-kernel-pairs-v1"
    if named:
        if not args.compiler:
            parser.error("--compiler is required for a named kernel-pairs report")
        table = validate_kernels(climb, report, digest(args.report), args.compiler)
        report["configuration"]["samples"] = climb["configuration"]["samples"]
    else:
        if args.compiler:
            parser.error("--compiler requires a named kernel-pairs report")
        table = validate(report)
        if climb:
            report["configuration"]["samples"] = apply_climb(table, climb, report, digest(args.report))
    if climb:
        report["started_utc"] = climb["started_utc"]
        report["climb_comparison"] = True
    labels = render(report, table, args.output)
    svg = ET.parse(args.output).getroot()
    observed = []
    for element in svg.iter():
        if element.attrib.get("id", "").startswith("target-label-"):
            observed.append("".join(element.itertext()).strip())
    assert observed == [row["label"] for row in labels], observed
    verification = {"status": "passed", "report_sha256": digest(args.report),
                    "chart_sha256": digest(args.output), "numeric_labels": labels, "table": table,
                    "method": "Raw confirmation samples only. Each series uses per-round ratios to the frozen selected native reference. Source fingerprints and positive timing intervals verified."}
    if climb:
        compiler_sha256 = climb.get("candidate_compiler_sha256")
        if named:
            compiler_sha256 = climb["compilers"][args.compiler]["sha256"]
        verification.update(climb_sha256=digest(args.climb),
                            current_compiler_sha256=compiler_sha256,
                            method="Fresh paired candidate comparisons against previously frozen references; no selection on the new measurements. Current direct Wasm, native anchor and selected references share the same rounds. Source fingerprints, workload checksums and timing intervals verified.")
        if named:
            verification.update(current_compiler_name=args.compiler, reference_roles=climb["reference_roles"])
    args.verification.parent.mkdir(parents=True, exist_ok=True)
    args.verification.write_text(json.dumps(verification, indent=2) + "\n")
    print(f"Verified {len(labels)} labels; wrote {args.output}")


if __name__ == "__main__":
    main()
