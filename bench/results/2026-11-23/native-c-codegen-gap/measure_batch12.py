"""Paired compiler & runtime benchmarks for Batch 12 (Native C codegen gap)."""
from __future__ import annotations

import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import resource
import shutil
import statistics
import subprocess
import sys
from time import perf_counter_ns

ROOT = Path(__file__).resolve().parents[4]
sys.path[:0] = [
    str(ROOT / "bench"),
    str(ROOT / "scripts"),
    str(ROOT / "bench/results/2026-11-18/selfhost-wasm-runtime/tools"),
]
from measure import measured

OUT_DIR = Path(__file__).resolve().parent
WORK_DIR = ROOT / "build/bench-batch12"
FROZEN = ROOT / "build/bench-batch2/frozen-9a6040a"
UPSTREAM_GOOSE = ROOT / "build/native/goose"
B11_NATIVE = ROOT / "build/qualify-batch11/bootstrap/bin/goose"
B11_STDLIB = ROOT / "build/qualify-batch11/bootstrap/bin/stdlib"
B12_NATIVE = ROOT / "build/qualify-batch12/bootstrap/bin/goose"
B12_STDLIB = ROOT / "build/qualify-batch12/bootstrap/bin/stdlib"
DRIVER = ROOT / "scripts/goose_wasm.py"

SELFBUILD_WASM_ARGS = [
    "selfhost/main.goose", "--stdlib", "stdlib", "--target", "wasm-direct", "-O2",
    "--wasm-memory64", "--wasm-max-pages", "262144",
]
SELFBUILD_C_ARGS = [
    "selfhost/main.goose", "--stdlib", "stdlib", "--target", "native", "-O2",
]

OWNER_KERNEL_SOURCE = """root struct Board {
    a: i64[>..],
    b: i64[>..],
    c: i64[>..],
}
fn insertion_owner(xs: i64[>..]&) {
    for i in 1..xs.len {
        let v = xs[i];
        var j = i;
        while j > 0 && xs[j - 1] > v {
            xs[j] = xs[j - 1];
            j--;
        }
        xs[j] = v;
    }
}
fn dot_board(st: Board&) -> i64 {
    var acc: i64 = 0;
    for rep in 0..800 {
        var i: i64 = 0;
        while i < st.a.len {
            let v = st.a[i] * st.b[i] + st.c[i];
            st.c[i] = v & 65535;
            acc += v;
            i++;
        }
    }
    return acc;
}
fn main() {
    var xs: i64[>..] = [];
    var s: u64 = 1;
    for i in 0..16000 {
        s = s * 6364136223846793005 + 1442695040888963407;
        xs.push(((s >> 33) & 1048575) as i64);
    }
    insertion_owner(xs);
    var st = Board { a: [], b: [], c: [] };
    for i in 0..16000 {
        st.a.push(xs[i] & 255);
        st.b.push((xs[15999 - i] & 255) + 1);
        st.c.push(i & 15);
    }
    let acc = dot_board(st);
    print(xs[0], " ", xs[8000], " ", xs[15999], " ", acc);
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


def file_info(path: Path) -> dict:
    data = path.read_bytes()
    return {
        "path": str(path),
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def tool_info(cmd: str) -> dict:
    resolved = Path(shutil.which(cmd)).resolve()
    version = subprocess.check_output([str(resolved), "--version"], text=True, stdin=subprocess.DEVNULL).splitlines()[0]
    return {"path": str(resolved), "version": version, "sha256": hashlib.sha256(resolved.read_bytes()).hexdigest()}


def paired_ratio_stats(num: list[float], den: list[float]) -> dict:
    ratios = sorted(a / b for a, b in zip(num, den))
    return {
        "median": statistics.median(ratios),
        "interval95": [ratios[0], ratios[-1]],
        "rounds_below_one": sum(1 for r in ratios if r < 1.0),
    }


def count_stack_canaries(binary: Path) -> int:
    out = subprocess.check_output(["objdump", "-d", str(binary)], text=True, stdin=subprocess.DEVNULL)
    return out.count("__stack_chk_fail")


def compile_c_single(cc: str, c_path: Path, out_bin: Path) -> float:
    t0 = perf_counter_ns()
    subprocess.run([cc, "-std=gnu11", "-O2", str(c_path), "-lm", "-ldl", "-pthread", "-o", str(out_bin)],
                   check=True, stdin=subprocess.DEVNULL)
    return (perf_counter_ns() - t0) / 1e9


def build_compiler_binaries() -> tuple[dict[str, Path], dict]:
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    b11_c = WORK_DIR / "b11-main.c"
    b12_c = WORK_DIR / "b12-main.c"
    up_c = WORK_DIR / "upstream-main.c"

    subprocess.run([str(B11_NATIVE), *SELFBUILD_C_ARGS, "-o", str(b11_c)], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)
    subprocess.run([str(B12_NATIVE), *SELFBUILD_C_ARGS, "-o", str(b12_c)], cwd=ROOT, stdin=subprocess.DEVNULL, check=True)
    subprocess.run([str(UPSTREAM_GOOSE), "selfhost/main.goose", "--stdlib", "stdlib", "--standalone", "-O2", "-o", str(up_c)],
                   cwd=ROOT, stdin=subprocess.DEVNULL, check=True)

    b11_clang = WORK_DIR / "goose-b11-clang"
    b11_gcc = WORK_DIR / "goose-b11-gcc"
    b12_clang = WORK_DIR / "goose-b12-clang"
    b12_gcc = WORK_DIR / "goose-b12-gcc"
    up_clang = WORK_DIR / "goose-upstream-clang"
    up_gcc = WORK_DIR / "goose-upstream-gcc"

    c_compile = {
        "b11-clang-single-s": compile_c_single("clang", b11_c, b11_clang),
        "b11-gcc-single-s": compile_c_single("gcc", b11_c, b11_gcc),
        "b12-clang-single-s": compile_c_single("clang", b12_c, b12_clang),
        "b12-gcc-single-s": compile_c_single("gcc", b12_c, b12_gcc),
        "upstream-clang-single-s": compile_c_single("clang", up_c, up_clang),
        "upstream-gcc-single-s": compile_c_single("gcc", up_c, up_gcc),
    }

    # Measure parallel 3-unit C builds via goose_wasm.py (uncached, fresh build dir)
    for label, compiler, stdlib in [("b11", B11_NATIVE, B11_STDLIB), ("b12", B12_NATIVE, B12_STDLIB)]:
        for cc in ("clang", "gcc"):
            bdir = WORK_DIR / f"units3-{label}-{cc}"
            if bdir.exists():
                shutil.rmtree(bdir)
            out_bin = WORK_DIR / f"goose-{label}-{cc}-j3"
            t0 = perf_counter_ns()
            subprocess.run([
                sys.executable, str(DRIVER), "build", "selfhost/main.goose",
                "--backend", "native", "--cc", cc, "--jobs", "3",
                "--goose", str(compiler), "--stdlib", str(stdlib), "-O2",
                "--no-cache", "--build-dir", str(bdir), "-o", str(out_bin),
            ], cwd=ROOT, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, check=True)
            c_compile[f"{label}-{cc}-jobs3-total-s"] = (perf_counter_ns() - t0) / 1e9

    emitted_c = {}
    for label, path in [("b11", b11_c), ("b12", b12_c), ("upstream", up_c)]:
        data = path.read_bytes()
        emitted_c[label] = {
            "bytes": len(data),
            "lines": data.count(b"\n"),
            "sha256": hashlib.sha256(data).hexdigest(),
        }

    bins = {
        "b11-clang": b11_clang,
        "b12-clang": b12_clang,
        "b11-gcc": b11_gcc,
        "b12-gcc": b12_gcc,
        "upstream-clang": up_clang,
        "upstream-gcc": up_gcc,
    }
    canaries = {k: count_stack_canaries(v) for k, v in bins.items()}
    print("Emitted C sizes:", {k: (v["bytes"], v["lines"]) for k, v in emitted_c.items()}, flush=True)
    print("C compile seconds:", {k: round(v, 2) for k, v in c_compile.items()}, flush=True)
    print("Stack canary functions:", canaries, flush=True)
    return bins, {"emitted_c": emitted_c, "c_compile_seconds": c_compile, "stack_canary_functions": canaries}


def run_paired_commands(
    workdir: Path,
    cwd: Path,
    cases: dict[str, list[str]],
    rounds: int,
    check_file: Path | None = None,
    stats_file: Path | None = None,
    expect_same_output: bool = True,
) -> dict:
    workdir.mkdir(parents=True, exist_ok=True)
    expected: dict[str, dict] = {}
    for name, cmd in cases.items():
        if check_file is not None:
            check_file.unlink(missing_ok=True)
        if stats_file is not None:
            stats_file.unlink(missing_ok=True)
        proc = subprocess.run(cmd, cwd=cwd, stdin=subprocess.DEVNULL, capture_output=True)
        if proc.returncode or proc.stderr:
            raise RuntimeError((name, proc.returncode, proc.stderr.decode(errors="replace")))
        if check_file is not None:
            expected[name] = {"bytes": check_file.stat().st_size, "sha256": hashlib.sha256(check_file.read_bytes()).hexdigest()}
        else:
            expected[name] = {"stdout_sha256": hashlib.sha256(proc.stdout).hexdigest(), "stdout": proc.stdout.decode(errors="replace")}

    if expect_same_output:
        uniq = {json.dumps(v, sort_keys=True) for v in expected.values()}
        if len(uniq) != 1:
            raise RuntimeError(f"Outputs differ across cases: {expected}")

    samples = []
    for r in range(rounds):
        order = list(cases)
        if r % 2:
            order.reverse()
        for name in order:
            if check_file is not None:
                check_file.unlink(missing_ok=True)
            if stats_file is not None:
                stats_file.unlink(missing_ok=True)
            before = resource.getrusage(resource.RUSAGE_CHILDREN)
            proc, wall_ns, counters = measured(
                lambda: subprocess.run(cases[name], cwd=cwd, stdin=subprocess.DEVNULL, capture_output=True),
                child=True,
            )
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
            if proc.returncode or proc.stderr:
                raise RuntimeError((name, proc.returncode, proc.stderr.decode(errors="replace")))
            if check_file is not None:
                actual = {"bytes": check_file.stat().st_size, "sha256": hashlib.sha256(check_file.read_bytes()).hexdigest()}
            else:
                actual = {"stdout_sha256": hashlib.sha256(proc.stdout).hexdigest(), "stdout": proc.stdout.decode(errors="replace")}
            if actual != expected[name]:
                raise ValueError((name, actual, expected[name]))
            phases = {}
            if stats_file is not None and stats_file.is_file():
                st = json.loads(stats_file.read_bytes())
                phases = {k: st.get(k, 0) for k in ("parse_ns", "typecheck_ns", "lifetime_ns", "optimize_ns", "backend_ns")}
            samples.append({
                "round": r + 1,
                "case": name,
                "wall_ns": wall_ns,
                "cpu_s": (after.ru_utime + after.ru_stime) - (before.ru_utime + before.ru_stime),
                "counters": counters,
                "phases": phases,
            })

    medians = {}
    for name in cases:
        rows = [s for s in samples if s["case"] == name]
        ins = statistics.median(r["counters"]["instructions"]["value"] for r in rows)
        cyc = statistics.median(r["counters"]["cycles"]["value"] for r in rows)
        br = statistics.median(r["counters"]["branches"]["value"] for r in rows)
        bm = statistics.median(r["counters"]["branch_misses"]["value"] for r in rows)
        medians[name] = {
            "wall_seconds": statistics.median(r["wall_ns"] for r in rows) / 1e9,
            "cpu_seconds": statistics.median(r["cpu_s"] for r in rows),
            "instructions": ins,
            "cycles": cyc,
            "branches": br,
            "branch_misses": bm,
            "ipc": ins / cyc if cyc else 0.0,
            "phases_seconds": {
                k[:-3]: statistics.median(r["phases"][k] for r in rows) / 1e9
                for k in ("parse_ns", "typecheck_ns", "lifetime_ns", "optimize_ns", "backend_ns")
                if rows and k in rows[0]["phases"]
            },
        }
    return {"expected": expected, "medians": medians, "samples": samples}


def compare_pair(run: dict, num_case: str, den_case: str) -> dict:
    num_rows = [s for s in run["samples"] if s["case"] == num_case]
    den_rows = [s for s in run["samples"] if s["case"] == den_case]
    return {
        "wall": paired_ratio_stats([r["wall_ns"] for r in num_rows], [r["wall_ns"] for r in den_rows]),
        "instructions": paired_ratio_stats(
            [r["counters"]["instructions"]["value"] for r in num_rows],
            [r["counters"]["instructions"]["value"] for r in den_rows],
        ),
        "cycles": paired_ratio_stats(
            [r["counters"]["cycles"]["value"] for r in num_rows],
            [r["counters"]["cycles"]["value"] for r in den_rows],
        ),
        "branches": paired_ratio_stats(
            [r["counters"]["branches"]["value"] for r in num_rows],
            [r["counters"]["branches"]["value"] for r in den_rows],
        ),
    }


def benchmark_kernels(rounds: int) -> dict:
    kdir = WORK_DIR / "kernels"
    kdir.mkdir(parents=True, exist_ok=True)
    owner_src = kdir / "owner_kernel.goose"
    owner_src.write_text(OWNER_KERNEL_SOURCE)
    sroa_src = kdir / "sroa_kernel.goose"
    sroa_src.write_text(SROA_KERNEL_SOURCE)

    specs = [
        ("sorting", ROOT / "examples/sorting.goose"),
        ("owner_kernel", owner_src),
        ("sroa_kernel", sroa_src),
    ]
    out = {}
    for kname, src in specs:
        cases = {}
        meta = {}
        for label, compiler, stdlib in [("b11", B11_NATIVE, B11_STDLIB), ("b12", B12_NATIVE, B12_STDLIB)]:
            c_out = kdir / f"{kname}-{label}.c"
            subprocess.run([str(compiler), str(src), "--stdlib", str(stdlib), "--target", "native", "-O2", "-o", str(c_out)],
                           cwd=ROOT, stdin=subprocess.DEVNULL, check=True)
            for cc in ("clang", "gcc"):
                bin_out = kdir / f"{kname}-{label}-{cc}"
                compile_c_single(cc, c_out, bin_out)
                cases[f"{label}-{cc}"] = [str(bin_out)]
                meta[f"{label}-{cc}"] = file_info(bin_out)
        run = run_paired_commands(kdir / kname, ROOT, cases, rounds=rounds, expect_same_output=True)
        run["binaries"] = meta
        run["paired"] = {
            "b12_vs_b11_clang": compare_pair(run, "b12-clang", "b11-clang"),
            "b12_vs_b11_gcc": compare_pair(run, "b12-gcc", "b11-gcc"),
        }
        out[kname] = run
        print(
            f"Kernel {kname}: "
            f"Clang {run['medians']['b11-clang']['wall_seconds']*1e3:.1f} -> {run['medians']['b12-clang']['wall_seconds']*1e3:.1f} ms "
            f"({run['paired']['b12_vs_b11_clang']['wall']['median']:.3f}x, {run['medians']['b11-clang']['instructions']/1e9:.2f} -> {run['medians']['b12-clang']['instructions']/1e9:.2f}B) | "
            f"GCC {run['medians']['b11-gcc']['wall_seconds']*1e3:.1f} -> {run['medians']['b12-gcc']['wall_seconds']*1e3:.1f} ms "
            f"({run['paired']['b12_vs_b11_gcc']['wall']['median']:.3f}x, {run['medians']['b11-gcc']['instructions']/1e9:.2f} -> {run['medians']['b12-gcc']['instructions']/1e9:.2f}B)",
            flush=True,
        )
    return out


def main() -> None:
    os.sched_setaffinity(0, {7})
    rounds = 7
    bins, build_meta = build_compiler_binaries()

    out_wasm = WORK_DIR / "out.wasm"
    stats_file = WORK_DIR / "stats.json"
    selfhost_wasm = run_paired_commands(
        WORK_DIR / "selfhost-wasm",
        ROOT,
        {k: [str(v), *SELFBUILD_WASM_ARGS, "--wasm-stats", str(stats_file), "-o", str(out_wasm)] for k, v in bins.items()},
        rounds=rounds,
        check_file=out_wasm,
        stats_file=stats_file,
        expect_same_output=True,
    )
    selfhost_wasm["paired"] = {
        "b12_vs_b11_clang": compare_pair(selfhost_wasm, "b12-clang", "b11-clang"),
        "b12_vs_b11_gcc": compare_pair(selfhost_wasm, "b12-gcc", "b11-gcc"),
        "b12_vs_upstream_clang": compare_pair(selfhost_wasm, "b12-clang", "upstream-clang"),
        "b12_vs_upstream_gcc": compare_pair(selfhost_wasm, "b12-gcc", "upstream-gcc"),
    }
    print("\nselfhost/main.goose -> Wasm -O2 (7 rounds, CPU 7):", flush=True)
    for k, m in selfhost_wasm["medians"].items():
        print(f"  {k:15s} {m['wall_seconds']:.3f} s  {m['instructions']/1e9:.3f} B insn  {m['cycles']/1e9:.3f} B cyc  {m['branches']/1e9:.3f} B br  IPC {m['ipc']:.2f}", flush=True)

    out_c = WORK_DIR / "out.c"
    c_cases = {k: [str(bins[k]), *SELFBUILD_C_ARGS, "-o", str(out_c)] for k in ("b11-clang", "b12-clang", "b11-gcc", "b12-gcc")}
    selfhost_c = run_paired_commands(
        WORK_DIR / "selfhost-c",
        ROOT,
        c_cases,
        rounds=rounds,
        check_file=out_c,
        expect_same_output=False,
    )
    selfhost_c["paired"] = {
        "b12_vs_b11_clang": compare_pair(selfhost_c, "b12-clang", "b11-clang"),
        "b12_vs_b11_gcc": compare_pair(selfhost_c, "b12-gcc", "b11-gcc"),
    }
    print("\nselfhost/main.goose -> C -O2 (7 rounds, CPU 7):", flush=True)
    for k, m in selfhost_c["medians"].items():
        print(f"  {k:15s} {m['wall_seconds']:.3f} s  {m['instructions']/1e9:.3f} B insn  {m['cycles']/1e9:.3f} B cyc  IPC {m['ipc']:.2f}", flush=True)

    frozen_wasm = run_paired_commands(
        WORK_DIR / "frozen-wasm",
        FROZEN,
        {k: [str(bins[k]), *SELFBUILD_WASM_ARGS, "--wasm-stats", str(stats_file), "-o", str(out_wasm)] for k in ("b11-clang", "b12-clang", "b11-gcc", "b12-gcc")},
        rounds=rounds,
        check_file=out_wasm,
        stats_file=stats_file,
        expect_same_output=True,
    )
    frozen_wasm["paired"] = {
        "b12_vs_b11_clang": compare_pair(frozen_wasm, "b12-clang", "b11-clang"),
        "b12_vs_b11_gcc": compare_pair(frozen_wasm, "b12-gcc", "b11-gcc"),
    }
    print("\nFrozen 9a6040a -> Wasm -O2 (7 rounds, CPU 7):", flush=True)
    for k, m in frozen_wasm["medians"].items():
        print(f"  {k:15s} {m['wall_seconds']:.3f} s  {m['instructions']/1e9:.3f} B insn  {m['cycles']/1e9:.3f} B cyc  IPC {m['ipc']:.2f}", flush=True)

    kernels = benchmark_kernels(rounds=rounds)

    all_samples = {
        "selfhost_wasm": selfhost_wasm.pop("samples"),
        "selfhost_c": selfhost_c.pop("samples"),
        "frozen_wasm": frozen_wasm.pop("samples"),
        "kernels": {k: v.pop("samples") for k, v in kernels.items()},
    }
    summary = {
        "cpu": 7,
        "rounds": rounds,
        "host": platform.uname()._asdict(),
        "tools": {
            "clang": tool_info("clang"),
            "gcc": tool_info("gcc"),
            "upstream_goose": file_info(UPSTREAM_GOOSE),
            "b11_bootstrap_goose": file_info(B11_NATIVE),
            "b12_bootstrap_goose": file_info(B12_NATIVE),
        },
        "compiler_binaries": {k: file_info(v) for k, v in bins.items()},
        "build_meta": build_meta,
        "selfhost_wasm": selfhost_wasm,
        "selfhost_c": selfhost_c,
        "frozen_wasm": frozen_wasm,
        "kernels": kernels,
    }
    (OUT_DIR / "results.json").write_text(json.dumps(summary, indent=2) + "\n")
    with gzip.open(OUT_DIR / "samples.json.gz", "wt") as fh:
        json.dump(all_samples, fh)
    print(f"\nWrote {OUT_DIR / 'results.json'} and samples.json.gz", flush=True)


if __name__ == "__main__":
    main()
