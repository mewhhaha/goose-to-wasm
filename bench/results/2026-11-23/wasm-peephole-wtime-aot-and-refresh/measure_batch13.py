"""Paired CPU 7 compiler, runtime, and wtime-aot benchmarks for Batch 13
(Wasm peephole folding, dead region/scratch mark elimination, cold abort outlining).
"""
from __future__ import annotations

import gzip
import hashlib
import json
import os
from pathlib import Path
import random
import resource
import shutil
import statistics
import subprocess
import sys
import time
from time import perf_counter_ns

ROOT = Path(__file__).resolve().parents[4]
sys.path[:0] = [
    str(ROOT / "bench"),
    str(ROOT / "scripts"),
    str(ROOT / "bench/results/2026-11-18/selfhost-wasm-runtime/tools"),
]
from measure import measured

OUT_DIR = Path(__file__).resolve().parent
WORK_DIR = ROOT / "build/bench-batch13"
HOST = ROOT / "host/rust/target/release/goose-wasmtime"
WTIME_REPO = ROOT.parent / "wtime"
WTIME_AOT = ROOT / "build/wtime-aot-target/release/wtime-aot"
WTIME_CACHE = ROOT / "build/wtime-aot-cache"
WTIME_TOOLCHAIN = "1.97.1"
FROZEN = ROOT / "build/bench-batch2/frozen-9a6040a"

PREV_NATIVE = ROOT / "build/qualify-batch11/bootstrap/bin/goose"
PREV_BALANCED = ROOT / "build/bench-batch11/balanced.wasm"
PREV_DIRECT = ROOT / "build/bench-batch11/direct.wasm"
B12_NATIVE = ROOT / "build/qualify-batch12/bootstrap/bin/goose"
CAND_NATIVE = ROOT / "build/qualify-batch13/bootstrap/bin/goose"
CAND_STDLIB = ROOT / "build/qualify-batch13/bootstrap/bin/stdlib"
UPSTREAM_CPP = ROOT / "build/native/goose"

SELFBUILD_WASM = [
    "selfhost/main.goose", "--stdlib", "stdlib", "--target", "wasm-direct", "-O2",
    "--wasm-memory64", "--wasm-max-pages", "262144",
]
SELFBUILD_C = [
    "selfhost/main.goose", "--stdlib", "stdlib", "--target", "native", "-O2", "--standalone",
]

OWNER_KERNEL_SOURCE = """struct Holder {
    vals: i64[>..]&,
    weights: i64[>..]&,
}

fn owner_sum(h: Holder&, rounds: i64) -> i64 {
    var acc: i64 = 0;
    var r: i64 = 0;
    while r < rounds {
        var i: i64 = 0;
        while i < h.vals.len {
            let v = h.vals[i];
            let w = h.weights[i];
            acc += (v * w) ^ (i + r);
            i++;
        }
        r++;
    }
    return acc;
}

fn main() {
    var a: i64[>..] = [];
    var b: i64[>..] = [];
    for i in 0..4096 {
        a.push((i * 131 + 17) & 1023);
        b.push((i * 37 + 5) & 255);
    }
    var h = Holder { vals: a, weights: b };
    print(owner_sum(h, 4000));
}
"""

SROA_KERNEL_SOURCE = """struct Vec3 { x: f64, y: f64, z: f64 }
struct Ev { a: i32, b: i32, tag: u8 }

fn step_vec3(p: const Vec3&, v: const Vec3&, dt: f64, n: i64) -> Vec3 {
    var cur = Vec3 { x: p.x, y: p.y, z: p.z };
    var vel = Vec3 { x: v.x, y: v.y, z: v.z };
    var i: i64 = 0;
    while i < n {
        let ax = -cur.x * 0.015625 + cur.y * 0.0078125;
        let ay = -cur.y * 0.015625 + cur.z * 0.0078125;
        let az = -cur.z * 0.015625 + cur.x * 0.0078125;
        vel = Vec3 { x: vel.x + ax * dt, y: vel.y + ay * dt, z: vel.z + az * dt };
        cur = Vec3 { x: cur.x + vel.x * dt, y: cur.y + vel.y * dt, z: cur.z + vel.z * dt };
        i++;
    }
    return cur;
}

fn vec3_bench(rounds: i64) -> i64 {
    var pos = Vec3 { x: 1.0, y: 0.5, z: -0.25 };
    var vel = Vec3 { x: 0.125, y: -0.0625, z: 0.03125 };
    var acc: f64 = 0.0;
    for r in 0..rounds {
        let next = step_vec3(pos, vel, 0.0625, 16);
        vel = Vec3 { x: (next.x - pos.x) * 0.5, y: (next.y - pos.y) * 0.5, z: (next.z - pos.z) * 0.5 };
        pos = Vec3 { x: next.x * 0.999 + 0.001, y: next.y * 0.999 - 0.0005, z: next.z * 0.999 + 0.00025 };
        acc += pos.x + pos.y + pos.z;
    }
    return (acc * 1000.0) as i64;
}

fn event_bench(n: i64) -> i64 {
    var evs: Ev[>..] = [];
    for rep in 0..40 {
        evs.clear();
        var s: i32 = (rep * 131 + 7) as i32;
        for i in 0..n {
            s = s * 1103515245 + 12345;
            evs.push(Ev { a: s & 4095, b: (s >> 12) & 4095, tag: (i & 7) as u8 });
        }
        var sum: i64 = 0;
        for e in evs {
            sum += (e.a as i64) * 3 - (e.b as i64) + (e.tag as i64);
        }
        if rep == 39 { return sum; }
    }
    return 0;
}

fn main() {
    let v = vec3_bench(300000);
    let e = event_bench(200000);
    print(v, " ", e);
}
"""


def ctr_val(v) -> int:
    return int(v["value"] if isinstance(v, dict) else v)


def file_info(path: Path) -> dict:
    data = path.read_bytes()
    return {
        "path": str(path),
        "bytes": len(data),
        "gzip_bytes": len(gzip.compress(data, compresslevel=9, mtime=0)),
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def paired_ratio_stats(num: list[float], den: list[float]) -> dict:
    ratios = sorted(a / b for a, b in zip(num, den))
    return {
        "median": statistics.median(ratios),
        "interval95": [ratios[0], ratios[-1]],
        "rounds_below_one": sum(1 for r in ratios if r < 1.0),
    }


def assert_wtime_clean() -> str:
    return subprocess.check_output(["git", "-C", str(WTIME_REPO), "rev-parse", "HEAD"], text=True).strip()


def wtime_aot_build(wasm: Path, label: str, target_cpu: str = "native") -> tuple[Path, dict]:
    WTIME_CACHE.mkdir(parents=True, exist_ok=True)
    t0 = perf_counter_ns()
    proc = subprocess.run(
        [
            str(WTIME_AOT), "build", str(wasm),
            "--cache", str(WTIME_CACHE),
            "--toolchain", WTIME_TOOLCHAIN,
            "--target-cpu", target_cpu,
            "--jobs", "8",
        ],
        cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True, text=True,
    )
    elapsed_s = (perf_counter_ns() - t0) / 1e9
    if proc.returncode != 0:
        raise RuntimeError(f"wtime-aot build failed for {label}: {proc.stderr}\n{proc.stdout}")
    bin_path = Path(proc.stdout.strip().splitlines()[-1])
    if not bin_path.is_file():
        raise RuntimeError(f"wtime-aot output missing: {bin_path}")
    info = file_info(bin_path)
    info["build_seconds"] = elapsed_s
    info["target_cpu"] = target_cpu
    info["toolchain"] = WTIME_TOOLCHAIN
    print(f"  wtime-aot {label:18s}: {bin_path.stat().st_size:,} B (build {elapsed_s:.2f} s)", flush=True)
    return bin_path, info


def build_all_artifacts() -> dict:
    """Build all Wasm releases, native Clang/GCC compilers, wtime-aot binaries, and kernels on all CPUs."""
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    art: dict = {}

    # 1. Train Batch 13 region profile
    stats_wasm = WORK_DIR / "stats.wasm"
    subprocess.run([
        CAND_NATIVE, "selfhost/main.goose", "--stdlib", CAND_STDLIB,
        "--target", "wasm-direct", "-O2", "--wasm-memory64", "--wasm-max-pages", "262144",
        "--wasm-region-stats", "-o", stats_wasm,
    ], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)

    profiles = []
    for name, cwd, args in [
        ("self", FROZEN, SELFBUILD_WASM),
        ("squares", ROOT, ["examples/squares.goose", "--stdlib", str(CAND_STDLIB), "--target", "wasm-direct", "-O2"]),
        ("sorting", ROOT, ["examples/sorting.goose", "--stdlib", str(CAND_STDLIB), "--target", "wasm-direct", "-O2"]),
        ("tour", ROOT, ["examples/tour.goose", "--stdlib", str(CAND_STDLIB), "--target", "wasm-direct", "-O2"]),
    ]:
        prof = WORK_DIR / f"train_{name}.prof"
        out = WORK_DIR / f"train_{name}.wasm"
        env = dict(os.environ, GOOSE_REGION_PROFILE=str(prof))
        subprocess.run([
            str(ROOT / ".venv/bin/python"), str(ROOT / "scripts/run_wasmtime.py"),
            str(stats_wasm), "--", *args, "-o", str(out),
        ], cwd=cwd, env=env, stdin=subprocess.DEVNULL, check=True)
        profiles.append(prof)

    merged: dict[int, int] = {}
    for p in profiles:
        for line in p.read_text().splitlines():
            if not line.strip():
                continue
            k, v = map(int, line.split())
            if v > merged.get(k, 0):
                merged[k] = v
    train_prof = WORK_DIR / "training.profile"
    train_prof.write_text("".join(f"{k} {v}\n" for k, v in sorted(merged.items())))
    shutil.copyfile(train_prof, OUT_DIR / "training.profile")
    art["training_profile"] = train_prof

    # 2. Build Batch 13 direct, balanced, size, and portable memory64 compiler Wasm
    direct = WORK_DIR / "direct.wasm"
    direct_args = [
        "selfhost/main.goose", "--stdlib", str(CAND_STDLIB),
        "--target", "wasm-direct", "-O2", "--wasm-bundled-host",
        "--wasm-initial-pages", "65535", "--wasm-max-pages", "65535",
        "--wasm-region-profile", str(train_prof),
    ]
    subprocess.run([CAND_NATIVE, *direct_args, "-o", direct], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)

    balanced = WORK_DIR / "balanced.wasm"
    size = WORK_DIR / "size.wasm"
    for prof_name, dest in [("balanced", balanced), ("size", size)]:
        if not dest.is_file():
            subprocess.run([
                str(ROOT / ".venv/bin/python"), str(ROOT / "scripts/goose_wasm.py"),
                "compact", "--profile", prof_name, str(direct), "-o", str(dest),
            ], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)

    compiler64 = WORK_DIR / "compiler64.wasm"
    subprocess.run([
        CAND_NATIVE, "selfhost/main.goose", "--stdlib", str(CAND_STDLIB),
        "--target", "wasm-direct", "-O2", "--wasm-memory64", "--wasm-max-pages", "262144",
        "-o", compiler64,
    ], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)

    # Verify byte-identical direct.wasm emitted by native vs balanced Wasm
    bal_cache = WORK_DIR / "balanced.cwasm"
    subprocess.run([HOST, balanced, "--cache", bal_cache, "--", "--version"], cwd=ROOT, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, check=True)
    direct_from_wasm = WORK_DIR / "direct-from-wasm.wasm"
    subprocess.run([HOST, balanced, "--cache", bal_cache, "--", *direct_args, "-o", direct_from_wasm], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)
    assert hashlib.sha256(direct.read_bytes()).hexdigest() == hashlib.sha256(direct_from_wasm.read_bytes()).hexdigest()
    print(f"Verified byte-identical direct.wasm: {direct.stat().st_size:,} B", flush=True)
    print(f"  balanced.wasm:   {balanced.stat().st_size:,} B", flush=True)
    print(f"  size.wasm:       {size.stat().st_size:,} B", flush=True)
    print(f"  compiler64.wasm: {compiler64.stat().st_size:,} B", flush=True)
    art.update(direct=direct, balanced=balanced, size=size, compiler64=compiler64)

    # 3. Build Batch 13 native Clang and GCC compilers (multi-core --jobs 4)
    native_clang = WORK_DIR / "goose-b13-clang"
    native_gcc = WORK_DIR / "goose-b13-gcc"
    for cc, dest in [("clang", native_clang), ("gcc", native_gcc)]:
        if not dest.is_file():
            subprocess.run([
                str(ROOT / ".venv/bin/python"), str(ROOT / "scripts/goose_wasm.py"), "build",
                "--backend", "native", "--cc", cc, "--jobs", "4",
                "--goose", str(CAND_NATIVE), "--stdlib", str(CAND_STDLIB), "-O2",
                "--build-dir", str(WORK_DIR / f"nat-{cc}"), "-o", str(dest), "selfhost/main.goose",
            ], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)
    art["native_clang"] = native_clang
    art["native_gcc"] = native_gcc

    # 4. Build wtime-aot compilers (32-bit direct, 32-bit balanced, 64-bit memory64)
    print(f"Building wtime-aot compilers (safe Rust, rustc {WTIME_TOOLCHAIN}, target-cpu=native)...", flush=True)
    art["wtime_aot_32"], art["wtime_aot_32_info"] = wtime_aot_build(direct, "compiler32-direct")
    art["wtime_aot_32_bal"], art["wtime_aot_32_bal_info"] = wtime_aot_build(balanced, "compiler32-bal")
    art["wtime_aot_64"], art["wtime_aot_64_info"] = wtime_aot_build(compiler64, "compiler64")

    # 5. Build runtime kernels (sorting, owner_kernel, sroa_kernel) across Prev Wasm, Cand Wasm, wtime-aot, Clang, GCC
    kdir = WORK_DIR / "kernels"
    kdir.mkdir(parents=True, exist_ok=True)
    owner_src = kdir / "owner_kernel.goose"
    owner_src.write_text(OWNER_KERNEL_SOURCE)
    sroa_src = kdir / "sroa_kernel.goose"
    sroa_src.write_text(SROA_KERNEL_SOURCE)
    kernel_srcs = {
        "sorting": ROOT / "examples/sorting.goose",
        "owner_kernel": owner_src,
        "sroa_kernel": sroa_src,
    }
    art["kernels"] = {}
    for kname, src in kernel_srcs.items():
        kd = kdir / kname
        kd.mkdir(parents=True, exist_ok=True)
        w_prev = kd / "prev.wasm"
        w_cand = kd / "cand.wasm"
        w_cand_bal = kd / "cand_bal.wasm"
        subprocess.run([PREV_NATIVE, str(src), "--stdlib", str(PREV_NATIVE.parent / "stdlib"), "--target", "wasm-direct", "-O2", "--wasm-bundled-host", "-o", str(w_prev)], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)
        subprocess.run([CAND_NATIVE, str(src), "--stdlib", str(CAND_STDLIB), "--target", "wasm-direct", "-O2", "--wasm-bundled-host", "-o", str(w_cand)], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)
        subprocess.run([str(ROOT / ".venv/bin/python"), str(ROOT / "scripts/goose_wasm.py"), "compact", "--profile", "balanced", str(w_cand), "-o", str(w_cand_bal)], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)
        aot_bin, aot_info = wtime_aot_build(w_cand, f"kernel-{kname}")
        nat_bins = {}
        for cc in ("clang", "gcc"):
            nb = kd / f"nat_{cc}"
            subprocess.run([
                str(ROOT / ".venv/bin/python"), str(ROOT / "scripts/goose_wasm.py"), "build",
                "--backend", "native", "--cc", cc, "--jobs", "1",
                "--goose", str(CAND_NATIVE), "--stdlib", str(CAND_STDLIB), "-O2",
                "--build-dir", str(kd / f"build_{cc}"), "-o", str(nb), str(src),
            ], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)
            nat_bins[cc] = nb
        art["kernels"][kname] = {
            "source": str(src),
            "wasm_prev": w_prev,
            "wasm_cand": w_cand,
            "wasm_cand_bal": w_cand_bal,
            "wtime_aot": aot_bin,
            "wtime_aot_info": aot_info,
            "native_clang": nat_bins["clang"],
            "native_gcc": nat_bins["gcc"],
        }
    return art


def run_cold_cached(workdir: Path, direct: Path, balanced: Path, size: Path, rounds: int = 5) -> dict:
    workdir.mkdir(parents=True, exist_ok=True)
    modules = {
        "previous": PREV_BALANCED,
        "direct": direct,
        "balanced": balanced,
        "size": size,
    }
    rng = random.Random(134713)
    out_wasm = workdir / "cold_out.wasm"
    stats = workdir / "cold_engine.json"
    rows = []
    mod_meta = {k: file_info(p) for k, p in modules.items()}

    def invoke(key: str, cached: bool) -> dict:
        cache_args = ["--cache", workdir / f"rel_{key}.cwasm"] if cached else ["--no-cache"]
        out_wasm.unlink(missing_ok=True)
        stats.unlink(missing_ok=True)
        cmd = [HOST, modules[key], *cache_args, "--timing-json", stats, "--", *SELFBUILD_WASM, "-o", out_wasm]
        t0 = perf_counter_ns()
        proc = subprocess.run(cmd, cwd=FROZEN, stdin=subprocess.DEVNULL, capture_output=True, timeout=180, check=True)
        elapsed = perf_counter_ns() - t0
        if proc.stdout or proc.stderr:
            raise RuntimeError((key, proc.stderr.decode(errors="replace")))
        return {
            "profile": key,
            "cached": cached,
            "wall_ns": elapsed,
            "output_bytes": out_wasm.stat().st_size,
            "output_sha256": hashlib.sha256(out_wasm.read_bytes()).hexdigest(),
            "engine": json.loads(stats.read_bytes()),
        }

    for k in modules:
        invoke(k, True)
    for r in range(rounds):
        for cached in (False, True):
            order = list(modules)
            rng.shuffle(order)
            for k in order:
                row = invoke(k, cached)
                row["round"] = r + 1
                rows.append(row)
                mode = "cached" if cached else "cold"
                print(f"  [release r{r+1}/{rounds}] {k:10s} {mode:6s} wall={row['wall_ns']/1e9:.3f}s", flush=True)

    profiles_out = {}
    for k in modules:
        cold_rows = [x for x in rows if x["profile"] == k and not x["cached"]]
        cached_rows = [x for x in rows if x["profile"] == k and x["cached"]]
        cwasm = workdir / f"rel_{k}.cwasm"
        profiles_out[k] = {
            **mod_meta[k],
            "cwasm_bytes": cwasm.stat().st_size if cwasm.is_file() else 0,
            "cold": {
                "wall_seconds": statistics.median(x["wall_ns"] for x in cold_rows) / 1e9,
                "prepare_seconds": statistics.median(x["engine"]["compile_instantiate_ns"] for x in cold_rows) / 1e9,
                "run_seconds": statistics.median(x["engine"]["start_function_ns"] for x in cold_rows) / 1e9,
            },
            "cached": {
                "wall_seconds": statistics.median(x["wall_ns"] for x in cached_rows) / 1e9,
                "prepare_seconds": statistics.median(x["engine"]["compile_instantiate_ns"] for x in cached_rows) / 1e9,
                "run_seconds": statistics.median(x["engine"]["start_function_ns"] for x in cached_rows) / 1e9,
            },
        }
    return {"profiles": profiles_out, "samples": rows}


def run_paired_series(workdir: Path, cwd: Path, specs: dict[str, dict], rounds: int) -> dict:
    workdir.mkdir(parents=True, exist_ok=True)
    expected: dict[str, dict | None] = {}
    for name, sp in specs.items():
        out_path: Path | None = sp.get("out")
        stats_path: Path | None = sp.get("stats")
        if out_path is not None:
            out_path.unlink(missing_ok=True)
        if stats_path is not None:
            stats_path.unlink(missing_ok=True)
        p = subprocess.run(sp["cmd"], cwd=cwd, stdin=subprocess.DEVNULL, capture_output=True)
        if p.returncode != 0:
            raise RuntimeError((name, p.returncode, p.stderr.decode(errors="replace")[:500]))
        if out_path is not None:
            expected[name] = {"bytes": out_path.stat().st_size, "sha256": hashlib.sha256(out_path.read_bytes()).hexdigest()}
        else:
            expected[name] = {"stdout_sha256": hashlib.sha256(p.stdout).hexdigest(), "stdout_len": len(p.stdout)}

    samples = []
    for r in range(rounds):
        order = list(specs)
        if r % 2:
            order.reverse()
        for name in order:
            sp = specs[name]
            out_path = sp.get("out")
            stats_path = sp.get("stats")
            timer_path = sp.get("timer")
            for fp in (out_path, stats_path, timer_path):
                if fp is not None:
                    fp.unlink(missing_ok=True)
            before = resource.getrusage(resource.RUSAGE_CHILDREN)
            p, wall_ns, ctrs = measured(
                lambda: subprocess.run(sp["cmd"], cwd=cwd, stdin=subprocess.DEVNULL, capture_output=True),
                child=True,
            )
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            if p.returncode != 0:
                raise RuntimeError((name, p.returncode, p.stderr.decode(errors="replace")[:500]))
            if out_path is not None:
                actual = {"bytes": out_path.stat().st_size, "sha256": hashlib.sha256(out_path.read_bytes()).hexdigest()}
            else:
                actual = {"stdout_sha256": hashlib.sha256(p.stdout).hexdigest(), "stdout_len": len(p.stdout)}
            if actual != expected[name]:
                raise ValueError((name, actual, expected[name]))
            phases = {}
            if stats_path is not None and stats_path.is_file():
                st = json.loads(stats_path.read_bytes())
                phases = {k: st.get(k, 0) for k in ("parse_ns", "typecheck_ns", "lifetime_ns", "optimize_ns", "backend_ns")}
            row = {
                "round": r + 1,
                "case": name,
                "wall_ns": wall_ns,
                "cpu_s": (after.ru_utime + after.ru_stime) - (before.ru_utime + before.ru_stime),
                "counters": {k: ctr_val(v) for k, v in ctrs.items()},
                "phases": phases,
                "output": actual,
            }
            if timer_path is not None and timer_path.is_file():
                row["engine"] = json.loads(timer_path.read_bytes())
            samples.append(row)
            ipc = row["counters"]["instructions"] / max(1, row["counters"]["cycles"])
            print(
                f"  r{r+1}/{rounds} {name:18s} wall={wall_ns/1e6:7.1f}ms "
                f"instr={row['counters']['instructions']/1e9:6.3f}B "
                f"cyc={row['counters']['cycles']/1e9:6.3f}B IPC={ipc:.3f} "
                f"br={row['counters']['branches']/1e9:5.3f}B",
                flush=True,
            )

    medians = {}
    for name in specs:
        rows = [s for s in samples if s["case"] == name]
        ins = statistics.median(s["counters"]["instructions"] for s in rows)
        cyc = statistics.median(s["counters"]["cycles"] for s in rows)
        med = {
            "wall_seconds": statistics.median(s["wall_ns"] for s in rows) / 1e9,
            "cpu_seconds": statistics.median(s["cpu_s"] for s in rows),
            "instructions": int(ins),
            "cycles": int(cyc),
            "branches": int(statistics.median(s["counters"]["branches"] for s in rows)),
            "ipc": ins / max(1.0, cyc),
            "output": expected[name],
        }
        if rows[0]["phases"]:
            for k in ("parse_ns", "typecheck_ns", "lifetime_ns", "optimize_ns", "backend_ns"):
                med[k.replace("_ns", "_seconds")] = statistics.median(s["phases"][k] for s in rows) / 1e9
        medians[name] = med
    return {"rounds": rounds, "medians": medians, "samples": samples}


def make_compiler_specs(workdir: Path, art: dict, include_prev: bool = True) -> dict[str, dict]:
    workdir.mkdir(parents=True, exist_ok=True)
    out_wasm = workdir / "out.wasm"
    stats_f = workdir / "stats.json"
    timer_f = workdir / "timer.json"
    specs: dict[str, dict] = {}

    def add_wasm(name: str, mod: Path):
        cw = workdir / f"{name}.cwasm"
        subprocess.run([HOST, mod, "--cache", cw, "--", "--version"], cwd=ROOT, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, check=True)
        specs[name] = {
            "cmd": [HOST, mod, "--cache", cw, "--timing-json", timer_f, "--", *SELFBUILD_WASM, "--wasm-stats", stats_f, "-o", out_wasm],
            "out": out_wasm, "stats": stats_f, "timer": timer_f,
        }

    if include_prev:
        add_wasm("wasm_prev_bal", PREV_BALANCED)
    add_wasm("wasm_cand_direct", art["direct"])
    add_wasm("wasm_cand_bal", art["balanced"])
    add_wasm("wasm_cand_size", art["size"])
    for name, bin_path in [
        ("wtime_aot_32", art["wtime_aot_32"]),
        ("wtime_aot_32_bal", art["wtime_aot_32_bal"]),
        ("wtime_aot_64", art["wtime_aot_64"]),
    ]:
        specs[name] = {
            "cmd": [bin_path, "--allow-files", "/", "--allow-env", "*", "--timing-json", timer_f, "--", *SELFBUILD_WASM, "--wasm-stats", stats_f, "-o", out_wasm],
            "out": out_wasm, "stats": stats_f, "timer": timer_f,
        }
    specs["native_clang"] = {
        "cmd": [art["native_clang"], *SELFBUILD_WASM, "--wasm-stats", stats_f, "-o", out_wasm],
        "out": out_wasm, "stats": stats_f,
    }
    specs["native_gcc"] = {
        "cmd": [art["native_gcc"], *SELFBUILD_WASM, "--wasm-stats", stats_f, "-o", out_wasm],
        "out": out_wasm, "stats": stats_f,
    }
    return specs


def paired_table(series: dict, pairs: list[tuple[str, str, str]]) -> dict:
    out = {}
    for label, num_case, den_case in pairs:
        nr = [s for s in series["samples"] if s["case"] == num_case]
        dr = [s for s in series["samples"] if s["case"] == den_case]
        out[label] = {
            "wall": paired_ratio_stats([x["wall_ns"] for x in nr], [x["wall_ns"] for x in dr]),
            "instructions": paired_ratio_stats([x["counters"]["instructions"] for x in nr], [x["counters"]["instructions"] for x in dr]),
            "cycles": paired_ratio_stats([x["counters"]["cycles"] for x in nr], [x["counters"]["cycles"] for x in dr]),
        }
    return out


def main() -> None:
    wtime_sha = assert_wtime_clean()
    full_affinity = os.sched_getaffinity(0)

    # Phase 1: Build everything with full multi-core affinity
    art = build_all_artifacts()
    assert_wtime_clean()

    # Phase 2: Pin CPU 7 for ALL timed single-core benchmarks
    os.sched_setaffinity(0, {7})
    resource.setrlimit(resource.RLIMIT_STACK, (256 << 20, resource.getrlimit(resource.RLIMIT_STACK)[1]))

    print("\n=== Cold & cached release profiles (5 rounds, frozen 9a6040a) ===", flush=True)
    release = run_cold_cached(WORK_DIR / "release", art["direct"], art["balanced"], art["size"], rounds=5)

    print("\n=== Frozen 9a6040a paired self-builds (7 rounds, CPU 7) ===", flush=True)
    frozen_specs = make_compiler_specs(WORK_DIR / "frozen", art, include_prev=True)
    frozen_series = run_paired_series(WORK_DIR / "frozen", FROZEN, frozen_specs, rounds=7)
    # Verify byte-identical output across all 7 Batch 13 engines!
    b13_frozen_hashes = {frozen_series["medians"][k]["output"]["sha256"] for k in frozen_specs if k != "wasm_prev_bal"}
    assert len(b13_frozen_hashes) == 1, f"Frozen output mismatch across Batch 13 engines: {b13_frozen_hashes}"

    print("\n=== Own-source selfhost/main.goose paired self-builds (7 rounds, CPU 7) ===", flush=True)
    own_specs = make_compiler_specs(WORK_DIR / "own", art, include_prev=True)
    own_series = run_paired_series(WORK_DIR / "own", ROOT, own_specs, rounds=7)
    b13_own_hashes = {own_series["medians"][k]["output"]["sha256"] for k in own_specs if k != "wasm_prev_bal"}
    assert len(b13_own_hashes) == 1, f"Own-source output mismatch across Batch 13 engines: {b13_own_hashes}"

    print("\n=== Head-to-head vs upstream C++ Goose (5 rounds, CPU 7) ===", flush=True)
    up_dir = WORK_DIR / "upstream"
    up_dir.mkdir(parents=True, exist_ok=True)
    up_c_out = up_dir / "out.c"
    up_bal_cw = WORK_DIR / "own/wasm_cand_bal.cwasm"
    up_specs = {
        "upstream_cpp_check": {"cmd": [UPSTREAM_CPP, "check", "selfhost/main.goose", "--stdlib", "stdlib"]},
        "upstream_cpp_c": {"cmd": [UPSTREAM_CPP, "selfhost/main.goose", "--stdlib", "stdlib", "--standalone", "-O2", "-o", up_c_out], "out": up_c_out},
        "wasm_cand_bal_c": {"cmd": [HOST, art["balanced"], "--cache", up_bal_cw, "--", *SELFBUILD_C, "-o", up_c_out], "out": up_c_out},
        "wtime_aot_32_c": {"cmd": [art["wtime_aot_32"], "--allow-files", "/", "--allow-env", "*", "--", *SELFBUILD_C, "-o", up_c_out], "out": up_c_out},
        "native_clang_c": {"cmd": [art["native_clang"], *SELFBUILD_C, "-o", up_c_out], "out": up_c_out},
        "native_gcc_c": {"cmd": [art["native_gcc"], *SELFBUILD_C, "-o", up_c_out], "out": up_c_out},
    }
    upstream_series = run_paired_series(up_dir, ROOT, up_specs, rounds=5)
    c_hashes = {upstream_series["medians"][k]["output"]["sha256"] for k in ("wasm_cand_bal_c", "wtime_aot_32_c", "native_clang_c", "native_gcc_c")}
    assert len(c_hashes) == 1, f"Emitted C mismatch across Batch 13 engines: {c_hashes}"

    print("\n=== Runtime kernels (7 rounds, CPU 7) ===", flush=True)
    kernel_results = {}
    kernel_samples = {}
    for kname, kinfo in art["kernels"].items():
        print(f"-- Kernel: {kname} --", flush=True)
        kw = WORK_DIR / f"krun-{kname}"
        kw.mkdir(parents=True, exist_ok=True)
        kspecs: dict[str, dict] = {}
        for label, mod in [("wasm_prev", kinfo["wasm_prev"]), ("wasm_cand", kinfo["wasm_cand"]), ("wasm_cand_bal", kinfo["wasm_cand_bal"])]:
            cw = kw / f"{label}.cwasm"
            subprocess.run([HOST, mod, "--cache", cw, "--", "--version"], cwd=ROOT, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, check=False)
            # Prime cache cleanly via actual run
            subprocess.run([HOST, mod, "--cache", cw], cwd=ROOT, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, check=True)
            kspecs[label] = {"cmd": [HOST, mod, "--cache", cw]}
        kspecs["wtime_aot"] = {"cmd": [kinfo["wtime_aot"]]}
        kspecs["native_clang"] = {"cmd": [kinfo["native_clang"]]}
        kspecs["native_gcc"] = {"cmd": [kinfo["native_gcc"]]}
        kser = run_paired_series(kw, ROOT, kspecs, rounds=7)
        # Verify byte-identical stdout across ALL 6 engines!
        std_hashes = {kser["medians"][k]["output"]["stdout_sha256"] for k in kspecs}
        assert len(std_hashes) == 1, f"Kernel {kname} stdout mismatch: {std_hashes}"
        kernel_results[kname] = {
            "medians": kser["medians"],
            "wtime_aot_build": kinfo["wtime_aot_info"],
            "wasm_sizes": {
                "prev": kinfo["wasm_prev"].stat().st_size,
                "cand": kinfo["wasm_cand"].stat().st_size,
                "cand_bal": kinfo["wasm_cand_bal"].stat().st_size,
            },
            "paired": paired_table(kser, [
                ("wasm_cand_vs_prev", "wasm_cand", "wasm_prev"),
                ("wtime_aot_vs_wasmtime", "wtime_aot", "wasm_cand"),
                ("wtime_aot_vs_clang", "wtime_aot", "native_clang"),
                ("wtime_aot_vs_gcc", "wtime_aot", "native_gcc"),
                ("wasmtime_vs_clang", "wasm_cand", "native_clang"),
            ]),
        }
        kernel_samples[kname] = kser["samples"]

    os.sched_setaffinity(0, full_affinity)
    assert_wtime_clean()

    # Save profiles.json, rebuilds.json, results.json, samples.json.gz
    (OUT_DIR / "profiles.json").write_text(json.dumps(release["profiles"], indent=2) + "\n")

    frozen_pairs = paired_table(frozen_series, [
        ("bal_vs_prev", "wasm_cand_bal", "wasm_prev_bal"),
        ("size_vs_prev", "wasm_cand_size", "wasm_prev_bal"),
        ("direct_vs_prev", "wasm_cand_direct", "wasm_prev_bal"),
        ("wtime32_vs_wasmtime_bal", "wtime_aot_32", "wasm_cand_bal"),
        ("wtime32_vs_clang", "wtime_aot_32", "native_clang"),
        ("wtime32_vs_gcc", "wtime_aot_32", "native_gcc"),
        ("wtime64_vs_wasmtime_bal", "wtime_aot_64", "wasm_cand_bal"),
        ("wtime64_vs_clang", "wtime_aot_64", "native_clang"),
        ("wasmtime_bal_vs_clang", "wasm_cand_bal", "native_clang"),
    ])
    own_pairs = paired_table(own_series, [
        ("bal_vs_prev", "wasm_cand_bal", "wasm_prev_bal"),
        ("size_vs_prev", "wasm_cand_size", "wasm_prev_bal"),
        ("direct_vs_prev", "wasm_cand_direct", "wasm_prev_bal"),
        ("wtime32_vs_wasmtime_bal", "wtime_aot_32", "wasm_cand_bal"),
        ("wtime32_vs_clang", "wtime_aot_32", "native_clang"),
        ("wtime32_vs_gcc", "wtime_aot_32", "native_gcc"),
        ("wtime64_vs_wasmtime_bal", "wtime_aot_64", "wasm_cand_bal"),
        ("wtime64_vs_clang", "wtime_aot_64", "native_clang"),
        ("wasmtime_bal_vs_clang", "wasm_cand_bal", "native_clang"),
    ])
    up_pairs = paired_table(upstream_series, [
        ("wasm_c_vs_upstream_c", "wasm_cand_bal_c", "upstream_cpp_c"),
        ("wtime32_c_vs_upstream_c", "wtime_aot_32_c", "upstream_cpp_c"),
        ("clang_c_vs_upstream_c", "native_clang_c", "upstream_cpp_c"),
        ("gcc_c_vs_upstream_c", "native_gcc_c", "upstream_cpp_c"),
    ])

    summary = {
        "schema": "batch13-results-v1",
        "cpu": 7,
        "wtime_repo_commit": wtime_sha,
        "wtime_aot_toolchain": WTIME_TOOLCHAIN,
        "wtime_aot_target_cpu": "native",
        "host": file_info(HOST),
        "artifacts": {
            "direct": file_info(art["direct"]),
            "balanced": file_info(art["balanced"]),
            "size": file_info(art["size"]),
            "compiler64": file_info(art["compiler64"]),
            "prev_direct": file_info(PREV_DIRECT),
            "prev_balanced": file_info(PREV_BALANCED),
            "wtime_aot_32": art["wtime_aot_32_info"],
            "wtime_aot_32_bal": art["wtime_aot_32_bal_info"],
            "wtime_aot_64": art["wtime_aot_64_info"],
        },
        "profiles": release["profiles"],
        "frozen": {"medians": frozen_series["medians"], "paired": frozen_pairs},
        "own": {"medians": own_series["medians"], "paired": own_pairs},
        "upstream": {"medians": upstream_series["medians"], "paired": up_pairs},
        "kernels": kernel_results,
    }
    (OUT_DIR / "results.json").write_text(json.dumps(summary, indent=2) + "\n")
    (OUT_DIR / "rebuilds.json").write_text(json.dumps({
        "frozen": summary["frozen"],
        "own": summary["own"],
    }, indent=2) + "\n")
    with gzip.open(OUT_DIR / "samples.json.gz", "wt") as gz:
        json.dump({
            "release": release["samples"],
            "frozen": frozen_series["samples"],
            "own": own_series["samples"],
            "upstream": upstream_series["samples"],
            "kernels": kernel_samples,
        }, gz)
    print("\nSaved profiles.json, rebuilds.json, results.json, samples.json.gz!", flush=True)


if __name__ == "__main__":
    main()
