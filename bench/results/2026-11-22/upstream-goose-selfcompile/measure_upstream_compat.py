"""Pinned CPU 7 measurements for upstream C++ Goose compatibility and head-to-head self-compilation."""
from __future__ import annotations

import gzip
import hashlib
import json
import os
from pathlib import Path
import resource
import shutil
import statistics
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[4]
sys.path[:0] = [
    str(ROOT / "bench"),
    str(ROOT / "scripts"),
    str(ROOT / "bench/results/2026-11-18/selfhost-wasm-runtime/tools"),
]
from measure import measured

OUT_DIR = Path(__file__).resolve().parent
WORK_DIR = ROOT / "build/bench-upstream-compat"
HOST = ROOT / "host/rust/target/release/goose-wasmtime"
FROZEN = ROOT / "build/bench-batch2/frozen-9a6040a"
BASE_NATIVE = ROOT / "build/qualify-batch8/bootstrap/bin/goose"
BASE_BALANCED = ROOT / "build/bench-batch8/balanced.wasm"
CAND_NATIVE = ROOT / "build/qualify-upstream-compat/bootstrap/bin/goose"
CAND_STDLIB = ROOT / "build/qualify-upstream-compat/bootstrap/bin/stdlib"
UPSTREAM_CPP = ROOT / "build/native/goose"

SELFBUILD_WASM = [
    "selfhost/main.goose", "--stdlib", "stdlib", "--target", "wasm-direct", "-O2",
    "--wasm-memory64", "--wasm-max-pages", "262144",
]
SELFBUILD_C = [
    "selfhost/main.goose", "--stdlib", "stdlib", "--target", "native", "-O2", "--standalone",
]


def file_info(path: Path) -> dict:
    data = path.read_bytes()
    return {
        "path": str(path),
        "bytes": len(data),
        "gzip_bytes": len(gzip.compress(data, compresslevel=9, mtime=0)),
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def paired_ratio(num: list[float], den: list[float]) -> dict:
    ratios = sorted(a / b for a, b in zip(num, den))
    return {
        "median": statistics.median(ratios),
        "interval95": [ratios[0], ratios[-1]],
        "rounds_below_one": sum(1 for r in ratios if r < 1.0),
    }


def build_artifacts() -> tuple[Path, Path, Path]:
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    train_prof = ROOT / "build/bench-batch8/training.profile"
    direct = WORK_DIR / "direct.wasm"
    direct_args = [
        "selfhost/main.goose", "--stdlib", str(CAND_STDLIB),
        "--target", "wasm-direct", "-O2", "--wasm-bundled-host",
        "--wasm-initial-pages", "65535", "--wasm-max-pages", "65535",
        "--wasm-region-profile", str(train_prof),
    ]
    subprocess.run([CAND_NATIVE, *direct_args, "-o", direct], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)
    balanced = WORK_DIR / "balanced.wasm"
    subprocess.run([
        str(ROOT / ".venv/bin/python"), str(ROOT / "scripts/goose_wasm.py"),
        "compact", "--profile", "balanced", str(direct), "-o", str(balanced),
    ], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)

    bal_cache = WORK_DIR / "balanced.cwasm"
    subprocess.run([HOST, balanced, "--cache", bal_cache, "--", "--version"], cwd=ROOT, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, check=True)
    direct_from_wasm = WORK_DIR / "direct-from-wasm.wasm"
    subprocess.run([HOST, balanced, "--cache", bal_cache, "--", *direct_args, "-o", direct_from_wasm], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)
    assert hashlib.sha256(direct.read_bytes()).hexdigest() == hashlib.sha256(direct_from_wasm.read_bytes()).hexdigest()

    cpp_built = WORK_DIR / "goose-from-cpp"
    if not cpp_built.is_file():
        subprocess.run([
            UPSTREAM_CPP, "build", "selfhost/main.goose", "--stdlib", "stdlib",
            "-O2", "--cc", "gcc", "-o", cpp_built,
        ], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)
    return direct, balanced, cpp_built


def run_series(workdir: Path, cwd: Path, specs: dict[str, tuple[list[str], Path | None]], rounds: int) -> dict:
    workdir.mkdir(parents=True, exist_ok=True)
    expected: dict[str, dict | None] = {}
    for name, (cmd, out_path) in specs.items():
        if out_path is not None:
            out_path.unlink(missing_ok=True)
        p = subprocess.run(cmd, cwd=cwd, stdin=subprocess.DEVNULL, capture_output=True)
        if p.returncode != 0:
            raise RuntimeError((name, p.returncode, p.stderr.decode(errors="replace")[:500]))
        expected[name] = (
            {"bytes": out_path.stat().st_size, "sha256": hashlib.sha256(out_path.read_bytes()).hexdigest()}
            if out_path is not None else None
        )

    samples = []
    for r in range(rounds):
        order = list(specs)
        if r % 2:
            order.reverse()
        for name in order:
            cmd, out_path = specs[name]
            if out_path is not None:
                out_path.unlink(missing_ok=True)
            before = resource.getrusage(resource.RUSAGE_CHILDREN)
            p, wall_ns, ctrs = measured(
                lambda: subprocess.run(cmd, cwd=cwd, stdin=subprocess.DEVNULL, capture_output=True),
                child=True,
            )
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            if p.returncode != 0:
                raise RuntimeError((name, p.returncode, p.stderr.decode(errors="replace")[:500]))
            actual = (
                {"bytes": out_path.stat().st_size, "sha256": hashlib.sha256(out_path.read_bytes()).hexdigest()}
                if out_path is not None else None
            )
            if actual != expected[name]:
                raise ValueError((name, actual, expected[name]))
            samples.append({
                "round": r + 1,
                "case": name,
                "wall_ns": wall_ns,
                "cpu_s": (after.ru_utime + after.ru_stime) - (before.ru_utime + before.ru_stime),
                "counters": ctrs,
                "output": actual,
            })
            print(
                f"  r{r+1}/{rounds} {name:28s} wall={wall_ns/1e6:7.1f}ms "
                f"instr={ctrs['instructions']['value']/1e9:6.3f}B cyc={ctrs['cycles']['value']/1e9:6.3f}B",
                flush=True,
            )

    medians = {}
    for name in specs:
        rows = [s for s in samples if s["case"] == name]
        medians[name] = {
            "wall_seconds": statistics.median(s["wall_ns"] for s in rows) / 1e9,
            "cpu_seconds": statistics.median(s["cpu_s"] for s in rows),
            "instructions": int(statistics.median(s["counters"]["instructions"]["value"] for s in rows)),
            "cycles": int(statistics.median(s["counters"]["cycles"]["value"] for s in rows)),
            "output": expected[name],
        }
    return {"rounds": rounds, "medians": medians, "samples": samples}


def main():
    resource.setrlimit(resource.RLIMIT_STACK, (256 << 20, resource.getrlimit(resource.RLIMIT_STACK)[1]))
    os.sched_setaffinity(0, {7})
    direct, balanced, cpp_built = build_artifacts()

    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        base_cache = work / "base.cwasm"
        cand_cache = work / "cand.cwasm"
        subprocess.run([HOST, BASE_BALANCED, "--cache", base_cache, "--", "--version"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, check=True)
        subprocess.run([HOST, balanced, "--cache", cand_cache, "--", "--version"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, check=True)

        print("1) Frozen 9a6040a regression check (5 alternating rounds, CPU 7)...", flush=True)
        f_out = work / "frozen.wasm"
        frozen = run_series(work / "frozen", FROZEN, {
            "native-before": ([str(BASE_NATIVE), *SELFBUILD_WASM, "-o", str(f_out)], f_out),
            "native-after": ([str(CAND_NATIVE), *SELFBUILD_WASM, "-o", str(f_out)], f_out),
            "wasm-before": ([str(HOST), str(BASE_BALANCED), "--cache", str(base_cache), "--", *SELFBUILD_WASM, "-o", str(f_out)], f_out),
            "wasm-after": ([str(HOST), str(balanced), "--cache", str(cand_cache), "--", *SELFBUILD_WASM, "-o", str(f_out)], f_out),
        }, rounds=5)
        for k in ("native-before", "native-after", "wasm-before", "wasm-after"):
            assert frozen["medians"][k]["output"]["sha256"] == "df47e5c4ad0b37d48c4c8df2baf1db2f538faf7dbf1b13665913c73fbf424afe"

        print("2) Head-to-head self-compilation of selfhost/main.goose (5 alternating rounds, CPU 7)...", flush=True)
        w_out = work / "own.wasm"
        c_out = work / "own.c"
        h2h = run_series(work / "h2h", ROOT, {
            "upstream-cpp-check": ([str(UPSTREAM_CPP), "check", "selfhost/main.goose", "--stdlib", "stdlib"], None),
            "upstream-cpp-emit-c": ([str(UPSTREAM_CPP), "selfhost/main.goose", "--stdlib", "stdlib", "-O2", "-o", str(c_out)], c_out),
            "wasmtime-balanced-emit-c": ([str(HOST), str(balanced), "--cache", str(cand_cache), "--", *SELFBUILD_C, "-o", str(c_out)], c_out),
            "selfhost-native-emit-c": ([str(CAND_NATIVE), *SELFBUILD_C, "-o", str(c_out)], c_out),
            "wasmtime-balanced-emit-wasm": ([str(HOST), str(balanced), "--cache", str(cand_cache), "--", *SELFBUILD_WASM, "-o", str(w_out)], w_out),
            "selfhost-native-emit-wasm": ([str(CAND_NATIVE), *SELFBUILD_WASM, "-o", str(w_out)], w_out),
            "cppbuilt-native-emit-wasm": ([str(cpp_built), *SELFBUILD_WASM, "-o", str(w_out)], w_out),
        }, rounds=5)
        wasm_hashes = {h2h["medians"][k]["output"]["sha256"] for k in ("wasmtime-balanced-emit-wasm", "selfhost-native-emit-wasm", "cppbuilt-native-emit-wasm")}
        assert len(wasm_hashes) == 1, f"Wasm outputs differed: {wasm_hashes}"

    def ratio(data, a, b):
        ra = [s for s in data["samples"] if s["case"] == a]
        rb = [s for s in data["samples"] if s["case"] == b]
        return {
            "wall": paired_ratio([s["wall_ns"] for s in ra], [s["wall_ns"] for s in rb]),
            "instructions": paired_ratio([s["counters"]["instructions"]["value"] for s in ra], [s["counters"]["instructions"]["value"] for s in rb]),
        }

    result = {
        "cpu": 7,
        "upstream_version": subprocess.check_output([str(UPSTREAM_CPP), "version"], text=True).strip(),
        "host": file_info(HOST),
        "upstream_cpp": file_info(UPSTREAM_CPP),
        "direct_wasm": file_info(direct),
        "balanced_wasm": file_info(balanced),
        "candidate_native": file_info(CAND_NATIVE),
        "cppbuilt_native": file_info(cpp_built),
        "frozen": {
            "rounds": frozen["rounds"],
            "medians": frozen["medians"],
            "paired": {
                "wasm-after / wasm-before": ratio(frozen, "wasm-after", "wasm-before"),
                "native-after / native-before": ratio(frozen, "native-after", "native-before"),
            },
        },
        "head_to_head": {
            "rounds": h2h["rounds"],
            "medians": h2h["medians"],
            "paired": {
                "wasmtime-emit-wasm / upstream-cpp-emit-c": ratio(h2h, "wasmtime-balanced-emit-wasm", "upstream-cpp-emit-c"),
                "wasmtime-emit-wasm / upstream-cpp-check": ratio(h2h, "wasmtime-balanced-emit-wasm", "upstream-cpp-check"),
                "wasmtime-emit-c / upstream-cpp-emit-c": ratio(h2h, "wasmtime-balanced-emit-c", "upstream-cpp-emit-c"),
                "selfhost-native-emit-wasm / upstream-cpp-emit-c": ratio(h2h, "selfhost-native-emit-wasm", "upstream-cpp-emit-c"),
                "selfhost-native-emit-c / upstream-cpp-emit-c": ratio(h2h, "selfhost-native-emit-c", "upstream-cpp-emit-c"),
                "cppbuilt-native-emit-wasm / upstream-cpp-emit-c": ratio(h2h, "cppbuilt-native-emit-wasm", "upstream-cpp-emit-c"),
            },
        },
    }
    (OUT_DIR / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    with gzip.open(OUT_DIR / "samples.json.gz", "wt", encoding="utf-8") as gz:
        json.dump({"frozen": frozen, "head_to_head": h2h}, gz, indent=1)
    print("Wrote results.json and samples.json.gz", flush=True)


if __name__ == "__main__":
    main()
