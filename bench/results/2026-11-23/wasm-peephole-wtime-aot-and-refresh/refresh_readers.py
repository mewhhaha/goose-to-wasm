"""Refresh all five reader-facing benchmark suites and bench/charts/*.svg on clean commit 949c5c0."""
from __future__ import annotations

import gzip
import hashlib
import json
import math
import os
from pathlib import Path
import random
import shutil
import statistics
import subprocess
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[4]
OUT_DIR = Path(__file__).resolve().parent
CHARTS = ROOT / "bench/charts"
STAGE = ROOT / "build/reader-refresh-batch13"
PY = str(ROOT / ".venv/bin/python")
COMMIT = "949c5c0e39b08221da7b43cf0baf2e4663b6a7e8"
PARENT_COMMIT = "fb15dbf"

PARENT_GOOSE = ROOT / "build/qualify-batch8/bootstrap/bin/goose"
CAND_GOOSE = ROOT / "build/qualify-batch13/bootstrap/bin/goose"
CAND_STDLIB = ROOT / "build/qualify-batch13/bootstrap/bin/stdlib"
UPSTREAM_GOOSE = ROOT / "build/native/goose"
UPSTREAM_STDLIB = ROOT / "build/bin/stdlib"
TRAIN_PROFILE = OUT_DIR / "training.profile"


def run(cmd: list, *, cwd: Path = ROOT) -> None:
    cmd_s = [str(c) for c in cmd]
    print("+", " ".join(cmd_s), flush=True)
    subprocess.run(cmd_s, cwd=cwd, stdin=subprocess.DEVNULL, check=True)


def gzip_copy(src: Path, dst: Path) -> None:
    with src.open("rb") as fin, gzip.open(dst, "wb", compresslevel=9) as fout:
        shutil.copyfileobj(fin, fout)


def extract_commit_selfhost(commit: str, dest: Path) -> Path:
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    archive = subprocess.check_output(["git", "-C", str(ROOT), "archive", commit, "selfhost"])
    p = subprocess.run(["tar", "-x", "-C", str(dest)], input=archive, check=True)
    assert p.returncode == 0
    return dest / "selfhost"


def plot_launch(launch_json: Path) -> None:
    report = json.loads(launch_json.read_text())
    cases = ["cold1", "cold8", "cached64", "cached_bundled64", "cold8_bundled32", "cached_bundled32", "native"]
    samples = {c: [] for c in cases}
    for row in report["samples"]:
        if row.get("kind", "emit") == "emit" and row["case"] in samples:
            assert row["output"] == report["expected"]
            samples[row["case"]].append(row["wall_ns"] / 1e9)
    times = [statistics.median(samples[c]) for c in cases]
    rounds = len(samples["native"])
    plt.rcParams.update({"font.size": 10, "svg.hashsalt": "selfbuild-batch13", "svg.fonttype": "none"})
    NATIVE, WASM, COLD = "#345369", "#087d73", "#4566a4"
    fig, ax = plt.subplots(figsize=(9.5, 3.8), layout="constrained")
    fig.suptitle("Cold and cached compiler launches", fontsize=16, weight="bold")
    ax.set_title(f"Seconds to rebuild its own sources ({COMMIT[:7]}) · {rounds} fresh processes per configuration", loc="left", fontsize=11)
    labels = [
        "64-bit cold\n1 core", "64-bit cold\n8 cores", "64-bit\ncached",
        "Bundled 64-bit\ncached", "Fixed 32-bit\ncold, 8 cores", "Fixed 32-bit\ncached", "Native",
    ]
    colors = [COLD, COLD, WASM, WASM, COLD, WASM, NATIVE]
    bars = ax.bar(labels, times, color=colors, width=0.63)
    ax.bar_label(bars, fmt="%.2f s", padding=4, weight="bold")
    ax.set_ylim(0, max(times) * 1.22)
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#dce2e7", linewidth=0.8)
    ax.spines[:].set_visible(False)
    ax.tick_params(length=0, pad=5)
    fig.savefig(OUT_DIR / "launch.png", dpi=150)
    svg = OUT_DIR / "launch.svg"
    fig.savefig(svg, metadata={"Date": None})
    svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
    plt.close(fig)


def summarize_catalog(report_gz: Path) -> dict:
    rep = json.load(gzip.open(report_gz))
    rng = random.Random(20261123)
    out = {"parent": rep["compiler_labels"]["parent"], "candidate": rep["compiler_labels"]["candidate"], "targets": {}}
    for target in ("wasm-direct", "native-c"):
        per_w = {}
        ratios = []
        w_samples = []
        for wl in rep["workloads"]:
            name = wl["name"]
            ps = [b["resource_usage"]["total_cpu_seconds"] for b in rep["builds"] if b["phase"] == "measurement" and b["compiler"] == "parent" and b["workload"] == name and b["target"] == target]
            cs = [b["resource_usage"]["total_cpu_seconds"] for b in rep["builds"] if b["phase"] == "measurement" and b["compiler"] == "candidate" and b["workload"] == name and b["target"] == target]
            pm, cm = statistics.median(ps), statistics.median(cs)
            r = cm / pm
            per_w[name] = {"parent_ms": pm * 1000, "candidate_ms": cm * 1000, "ratio": r, "pct_change": (r - 1.0) * 100}
            ratios.append(r)
            w_samples.append((ps, cs))
        gmean = math.exp(sum(math.log(r) for r in ratios) / len(ratios))
        boots = []
        for _ in range(2000):
            br = []
            for ps, cs in w_samples:
                bp = statistics.median(rng.choices(ps, k=len(ps)))
                bc = statistics.median(rng.choices(cs, k=len(cs)))
                br.append(bc / bp)
            boots.append(math.exp(sum(math.log(x) for x in br) / len(br)))
        boots.sort()
        out["targets"][target] = {
            "geomean_ratio": gmean,
            "geomean_pct_change": (gmean - 1.0) * 100,
            "ci95_pct_change": [(boots[50] - 1.0) * 100, (boots[1949] - 1.0) * 100],
            "faster_count": sum(1 for r in ratios if r < 1.0),
            "total_workloads": len(ratios),
            "workloads": per_w,
        }
    return out


def main() -> None:
    STAGE.mkdir(parents=True, exist_ok=True)

    # 1. Portable self-hosting (build 3 rounds + run 3 rounds on clean commit 949c5c0)
    print("\n=== [1/5] Portable self-hosting (selfhost_comparison.py) ===", flush=True)
    sh_stage = STAGE / "selfhost"
    if not (sh_stage / "measurements.json").is_file():
        if sh_stage.exists():
            shutil.rmtree(sh_stage)
        run([
            PY, "bench/selfhost_comparison.py", "build",
            "--emitter", CAND_GOOSE, "--commit", COMMIT,
            "--cc", "clang", "--rounds", "3", "--jobs", "4",
            "--build-cpus", "1,3,5,7", "--cpu", "4", str(sh_stage),
        ])
        run([
            PY, "bench/selfhost_comparison.py", "run",
            "--cpu", "4", "--rounds", "3", str(sh_stage),
        ])
    shutil.copyfile(sh_stage / "measurements.json", OUT_DIR / "selfhost.json")
    run([
        PY, "bench/selfhost_charts.py", str(OUT_DIR / "selfhost.json"),
        "--output-dir", str(CHARTS), "--receipt", str(OUT_DIR / "selfhost-chart.json"),
    ])

    # 2. Cold and cached launches (launch.py using selfhost stage + Batch 13 training.profile)
    print("\n=== [2/5] Cold and cached launches (launch.py) ===", flush=True)
    launch_stage = STAGE / "launch"
    if not (launch_stage / "results.json").is_file():
        if launch_stage.exists():
            shutil.rmtree(launch_stage)
        run([
            PY, "bench/results/2026-11-18/compiler-request-latency/launch.py",
            str(ROOT), str(sh_stage), str(launch_stage),
            "--cpu", "3", "--parallel-cpus", "0,1,2,3,4,5,6,7", "--rounds", "3",
            "--layout-profile", str(TRAIN_PROFILE), "--fixed-bundled32",
        ])
    shutil.copyfile(launch_stage / "results.json", OUT_DIR / "launch.json")
    plot_launch(OUT_DIR / "launch.json")

    # 3. Eleven-program compiler catalog (Batch 8 fb15dbf vs Batch 13 949c5c0, 31 samples, CPU 2)
    print("\n=== [3/5] Eleven-program compiler catalog (compare_compilers.py) ===", flush=True)
    cat_stage = STAGE / "catalog"
    if not (cat_stage / "report.json").is_file():
        parent_src = extract_commit_selfhost(PARENT_COMMIT, STAGE / "parent-src")
        cand_src = extract_commit_selfhost(COMMIT, STAGE / "cand-src")
        if cat_stage.exists():
            shutil.rmtree(cat_stage)
        run([
            PY, "bench/compare_compilers.py",
            "--parent", str(PARENT_GOOSE), "--parent-source", str(parent_src), "--parent-label", PARENT_COMMIT,
            "--candidate", str(CAND_GOOSE), "--candidate-source", str(cand_src), "--candidate-label", COMMIT[:7],
            "--stdlib", str(CAND_STDLIB), "--samples", "31", "--cpu", "2",
            "--output-dir", str(cat_stage),
        ])
        gzip_copy(cat_stage / "report.json", OUT_DIR / "compiler-comparison.json.gz")
    cat_sum = summarize_catalog(OUT_DIR / "compiler-comparison.json.gz")
    (OUT_DIR / "catalog-summary.json").write_text(json.dumps(cat_sum, indent=2) + "\n")
    run([
        PY, "bench/compiler_comparison_charts.py", str(OUT_DIR / "compiler-comparison.json.gz"),
        "--output-dir", str(CHARTS), "--receipt", str(OUT_DIR / "compiler-chart.json"),
    ])

    # 4. Ten example programs + native Wasmtime host (examples.py + wasmtime_host.py)
    print("\n=== [4/5] Ten example programs + Wasmtime host ===", flush=True)
    ex_stage = STAGE / "examples"
    if not (ex_stage / "report.json").is_file():
        run([
            "taskset", "-c", "3", PY, "bench/examples.py",
            "--goose", str(CAND_GOOSE), "--stdlib", str(CAND_STDLIB),
            "--cc", "gcc", "--compile-samples", "5", "--samples", "5",
            "--machine-label", "AMD Ryzen 7 3800X (shared Linux host, CPU 3)",
            "--output-dir", str(ex_stage),
        ])
    gzip_copy(ex_stage / "report.json", OUT_DIR / "examples.json.gz")
    ex_charts_tmp = STAGE / "ex-charts"
    run([PY, "bench/example_charts.py", str(OUT_DIR / "examples.json.gz"), "--output-dir", str(ex_charts_tmp)])
    shutil.copyfile(ex_charts_tmp / "examples-compilation.svg", CHARTS / "goose-examples-compilation.svg")

    host_stage = STAGE / "host"
    host_rep = host_stage / "bench/report.json"
    if not host_rep.is_file():
        host_rep = host_stage / "report.json"
    if not host_rep.is_file():
        run([
            "taskset", "-c", "7", PY, "bench/wasmtime_host.py",
            "--host", str(ROOT / "build/bin/goose-wasmtime"),
            "--aot-host", str(ROOT / "build/bin/goose-wasmtime-aot"),
            "--example-report", str(ex_stage / "report.json"),
            "--samples", "15", "--prepare-samples", "5",
            "--machine-label", "AMD Ryzen 7 3800X (shared Linux host, CPU 7)",
            "--output-dir", str(host_stage),
        ])
        host_rep = host_stage / "bench/report.json"
        if not host_rep.is_file():
            host_rep = host_stage / "report.json"
    gzip_copy(host_rep, OUT_DIR / "host.json.gz")
    host_charts_tmp = STAGE / "host-charts"
    run([PY, "bench/example_runtime_charts.py", str(OUT_DIR / "host.json.gz"), "--output-dir", str(host_charts_tmp)])
    shutil.copyfile(host_charts_tmp / "examples-runtime.svg", CHARTS / "goose-examples-runtime.svg")
    run([PY, "bench/wasmtime_host_charts.py", str(OUT_DIR / "host.json.gz"), "--output-dir", str(host_charts_tmp)])
    shutil.copyfile(host_charts_tmp / "wasmtime-host-preparation.svg", CHARTS / "goose-host-preparation.svg")

    # 5. Langbench Mandelbrot (cold builds + resident hot runs)
    print("\n=== [5/5] Langbench Mandelbrot (langbench.py + langbench_hot.py) ===", flush=True)
    lb_stage = STAGE / "langbench"
    if not (lb_stage / "report.json").is_file():
        run([
            PY, "bench/langbench.py",
            "--profiles", "small", "medium", "official",
            "--samples", "1", "--compile-samples", "5", "--cpu", "1",
            "--goose", str(CAND_GOOSE), "--stdlib", str(CAND_STDLIB),
            "--upstream-goose", str(UPSTREAM_GOOSE), "--upstream-stdlib", str(UPSTREAM_STDLIB),
            "--output-dir", str(lb_stage),
        ])
    shutil.copyfile(lb_stage / "report.json", OUT_DIR / "langbench-build.json")
    run([
        PY, "bench/langbench_charts.py", str(OUT_DIR / "langbench-build.json"),
        "--output-dir", str(CHARTS), "--receipt", str(OUT_DIR / "langbench-chart.json"),
    ])

    lb_hot_stage = STAGE / "langbench-hot"
    if not (lb_hot_stage / "report.json").is_file():
        run([
            PY, "bench/langbench_hot.py",
            "--reference-report", str(lb_stage / "report.json"),
            "--samples", "7", "--cpu", "1",
            "--output-dir", str(lb_hot_stage),
        ])
    gzip_copy(lb_hot_stage / "report.json", OUT_DIR / "langbench-hot.json.gz")
    run([
        PY, "bench/langbench_hot_charts.py", str(OUT_DIR / "langbench-hot.json.gz"),
        "--output-dir", str(CHARTS), "--receipt", str(OUT_DIR / "langbench-hot-chart.json"),
    ])

    print("\nALL 5 READER BENCHMARKS AND ALL CHARTS REFRESHED SUCCESSFULLY!", flush=True)


if __name__ == "__main__":
    main()
