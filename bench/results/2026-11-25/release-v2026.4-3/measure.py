#!/usr/bin/env python3
"""Pinned head-to-head consumer benchmark suite: goose-to-wasm v2026.4-3 vs v2026.4-2 vs upstream C++ Goose."""
from __future__ import annotations

import hashlib
import json
import os
import platform
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
OUT_DIR = Path(__file__).resolve().parent
WORK = ROOT / "build/bench-v2026.4-3"
sys.path.insert(0, str(ROOT / "scripts"))
import run_wasmtime  # noqa: E402

GOOSE_V2 = ROOT / "build/qualify-v2026.4-2/bootstrap/bin/goose"
GOOSE_V3 = ROOT / "build/qualify-v2026.4-3/bootstrap/bin/goose"
UPSTREAM = ROOT / "build/native/goose"
STDLIB = ROOT / "stdlib"
BLOT_STDLIB = ROOT / "build/blot-stdlib"
PIN_CPU = 7


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_cmd(cmd: list[str], *, cwd: Path = ROOT, env: dict[str, str] | None = None,
            stdin_bytes: bytes = b"", pin_cpu: int | None = PIN_CPU,
            timeout_s: int = 240) -> dict:
    full_cmd = (["taskset", "-c", str(pin_cpu)] + cmd) if pin_cpu is not None else cmd
    t0 = time.perf_counter()
    try:
        r = subprocess.run(
            full_cmd, cwd=str(cwd), env=env,
            input=stdin_bytes if stdin_bytes else None,
            stdin=None if stdin_bytes else subprocess.DEVNULL,
            capture_output=True, timeout=timeout_s,
        )
        wall = time.perf_counter() - t0
        return {
            "rc": r.returncode,
            "timed_out": False,
            "wall_s": wall,
            "stdout": r.stdout.decode("utf-8", errors="replace"),
            "stderr": r.stderr.decode("utf-8", errors="replace"),
        }
    except subprocess.TimeoutExpired as exc:
        wall = time.perf_counter() - t0
        return {
            "rc": -9,
            "timed_out": True,
            "wall_s": wall,
            "stdout": (exc.stdout or b"").decode("utf-8", errors="replace"),
            "stderr": (exc.stderr or b"").decode("utf-8", errors="replace"),
        }


def run_measured_rusage(cmd: list[str], *, cwd: Path, env: dict[str, str], timeout_s: int = 240) -> dict:
    """Run in a fresh single-threaded Python helper so os.wait4 returns exact child CPU & RSS."""
    helper = (
        "import json, os, signal, sys, tempfile, time\n"
        "cwd, timeout_s, pin_cpu, cmd = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), json.loads(sys.argv[4])\n"
        "with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:\n"
        "    t0 = time.perf_counter()\n"
        "    pid = os.fork()\n"
        "    if pid == 0:\n"
        "        os.sched_setaffinity(0, {pin_cpu})\n"
        "        os.chdir(cwd)\n"
        "        dn = os.open(os.devnull, os.O_RDONLY); os.dup2(dn, 0); os.close(dn)\n"
        "        os.dup2(out.fileno(), 1); os.dup2(err.fileno(), 2)\n"
        "        os.execv(cmd[0], cmd)\n"
        "    to = False\n"
        "    def ah(s, f):\n"
        "        global to; to = True\n"
        "        try: os.kill(pid, signal.SIGKILL)\n"
        "        except ProcessLookupError: pass\n"
        "    signal.signal(signal.SIGALRM, ah); signal.alarm(timeout_s)\n"
        "    _, st, ru = os.wait4(pid, 0); signal.alarm(0)\n"
        "    wall = time.perf_counter() - t0\n"
        "    out.seek(0); err.seek(0)\n"
        "    lines = err.read().decode('utf-8', 'replace').strip().splitlines()\n"
        "    print(json.dumps({'rc': os.waitstatus_to_exitcode(st), 'timed_out': to, 'wall_s': wall,\n"
        "        'cpu_s': ru.ru_utime + ru.ru_stime, 'max_rss_kib': ru.ru_maxrss,\n"
        "        'error_count': sum(1 for l in lines if ': error:' in l),\n"
        "        'stderr': lines[:12]}))\n"
    )
    r = subprocess.run(
        [sys.executable, "-c", helper, str(cwd), str(timeout_s), str(PIN_CPU), json.dumps(cmd)],
        env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True, check=True,
    )
    return json.loads(r.stdout)


def alternating(specs: list[tuple[str, callable]], rounds: int = 5) -> dict:
    raw = {name: [] for name, _ in specs}
    for r in range(rounds):
        order = specs if r % 2 == 0 else list(reversed(specs))
        for name, fn in order:
            raw[name].append(fn())
    out = {}
    for name, rows in raw.items():
        walls = [x["wall_s"] for x in rows]
        out[name] = {
            "median_wall_s": statistics.median(walls),
            "walls_s": [round(v, 5) for v in walls],
        }
        if "extra" in rows[-1]:
            out[name]["extra"] = rows[-1]["extra"]
    return out


def main() -> None:
    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True)

    base_env = dict(os.environ)
    up_home = WORK / "upstream-home"
    up_home.mkdir()
    up_env = dict(base_env, GOOSE_HOME=str(up_home), GOOSE_CC="clang")

    print("Warming native runtime caches...", flush=True)
    w1 = run_cmd([str(UPSTREAM), "build", str(ROOT / "examples/squares.goose"), "--stdlib", str(STDLIB), "-O2", "-o", str(WORK / "warm-up")], env=up_env)
    assert w1["rc"] == 0, f"upstream warm failed: {w1['stderr']}"
    w2 = run_cmd([sys.executable, str(ROOT / "scripts/goose_wasm.py"), "build", str(ROOT / "examples/squares.goose"), "--goose", str(GOOSE_V3), "--stdlib", str(STDLIB), "--backend", "native", "--cc", "clang", "-O2", "-o", str(WORK / "warm-g2w")], env=base_env)
    assert w2["rc"] == 0, f"g2w warm failed: {w2['stderr']}"

    print("Building v2026.4-3 portable memory64 Wasm compiler...", flush=True)
    comp64 = WORK / "compiler-64.wasm"
    comp64_cw = WORK / "compiler-64.cwasm"
    r64 = run_cmd([str(GOOSE_V3), "--target", "wasm-direct", "--wasm-memory64", "--wasm-max-pages", "4194304", "-O2", "--stdlib", str(STDLIB), "-o", str(comp64), str(ROOT / "selfhost/main.goose")])
    assert r64["rc"] == 0, r64["stderr"]
    comp64_bytes = comp64.read_bytes()
    rw_warm = run_cmd([sys.executable, str(ROOT / "scripts/run_wasmtime.py"), "--cache", str(comp64_cw), str(comp64), "--", "--version"], env=base_env)
    assert rw_warm["rc"] == 0, rw_warm["stderr"]
    print(f"  compiler-64.wasm: {len(comp64_bytes):,} B ({rw_warm['stdout'].strip()}, cached .cwasm ready)", flush=True)

    # =========================================================================
    # Suite 1: Large-project compiler turnaround (selfhost/main.goose, ~30k LOC)
    # =========================================================================
    print("\n=== Suite 1: Self-compilation & check (selfhost/main.goose, 5 alternating rounds, CPU 7) ===", flush=True)
    s1_dir = WORK / "suite1"
    s1_dir.mkdir()

    def s1_up_check():
        r = run_cmd([str(UPSTREAM), "check", "selfhost/main.goose", "--stdlib", "stdlib"], env=up_env)
        assert r["rc"] == 0, r["stderr"]
        return r

    def s1_up_c():
        out = s1_dir / "up.c"
        r = run_cmd([str(UPSTREAM), "selfhost/main.goose", "--stdlib", "stdlib", "--standalone", "-O2", "-o", str(out)], env=up_env)
        assert r["rc"] == 0, r["stderr"]
        r["extra"] = {"bytes": out.stat().st_size}
        return r

    def s1_v2_check():
        r = run_cmd([str(GOOSE_V2), "--check", "--stdlib", "stdlib", "selfhost/main.goose"], env=base_env)
        assert r["rc"] == 0, r["stderr"]
        return r

    def s1_v2_wasm64():
        out = s1_dir / "v2_64.wasm"
        r = run_cmd([str(GOOSE_V2), "--target", "wasm-direct", "--wasm-memory64", "--wasm-max-pages", "4194304", "-O2", "--stdlib", "stdlib", "-o", str(out), "selfhost/main.goose"], env=base_env)
        assert r["rc"] == 0, r["stderr"]
        r["extra"] = {"bytes": out.stat().st_size, "sha256": sha256_file(out)[:16]}
        return r

    def s1_v2_c():
        out = s1_dir / "v2.c"
        r = run_cmd([str(GOOSE_V2), "--target", "c", "-O2", "--stdlib", "stdlib", "-o", str(out), "selfhost/main.goose"], env=base_env)
        assert r["rc"] == 0, r["stderr"]
        r["extra"] = {"bytes": out.stat().st_size, "sha256": sha256_file(out)[:16]}
        return r

    def s1_v3_check():
        r = run_cmd([str(GOOSE_V3), "--check", "--stdlib", "stdlib", "selfhost/main.goose"], env=base_env)
        assert r["rc"] == 0, r["stderr"]
        return r

    def s1_v3_wasm64():
        out = s1_dir / "v3_64.wasm"
        r = run_cmd([str(GOOSE_V3), "--target", "wasm-direct", "--wasm-memory64", "--wasm-max-pages", "4194304", "-O2", "--stdlib", "stdlib", "-o", str(out), "selfhost/main.goose"], env=base_env)
        assert r["rc"] == 0, r["stderr"]
        r["extra"] = {"bytes": out.stat().st_size, "sha256": sha256_file(out)[:16]}
        return r

    def s1_v3_c():
        out = s1_dir / "v3.c"
        r = run_cmd([str(GOOSE_V3), "--target", "c", "-O2", "--stdlib", "stdlib", "-o", str(out), "selfhost/main.goose"], env=base_env)
        assert r["rc"] == 0, r["stderr"]
        r["extra"] = {"bytes": out.stat().st_size, "sha256": sha256_file(out)[:16]}
        return r

    def s1_wasmtime_check():
        r = run_cmd([sys.executable, str(ROOT / "scripts/run_wasmtime.py"), "--cache", str(comp64_cw), str(comp64), "--", "--check", "--stdlib", "stdlib", "selfhost/main.goose"], env=base_env)
        assert r["rc"] == 0, r["stderr"]
        return r

    def s1_wasmtime_wasm64():
        out = s1_dir / "wt64.wasm"
        r = run_cmd([sys.executable, str(ROOT / "scripts/run_wasmtime.py"), "--cache", str(comp64_cw), str(comp64), "--", "--target", "wasm-direct", "--wasm-memory64", "--wasm-max-pages", "4194304", "-O2", "--stdlib", "stdlib", "-o", str(out), "selfhost/main.goose"], env=base_env)
        assert r["rc"] == 0, r["stderr"]
        r["extra"] = {"bytes": out.stat().st_size, "sha256": sha256_file(out)[:16]}
        return r

    suite1 = alternating([
        ("upstream_check", s1_up_check),
        ("upstream_emit_c", s1_up_c),
        ("v2_check", s1_v2_check),
        ("v2_wasm64", s1_v2_wasm64),
        ("v2_emit_c", s1_v2_c),
        ("g2w_check", s1_v3_check),
        ("g2w_wasm64", s1_v3_wasm64),
        ("g2w_emit_c", s1_v3_c),
        ("g2w_wasmtime_check", s1_wasmtime_check),
        ("g2w_wasmtime_emit_wasm64", s1_wasmtime_wasm64),
    ], rounds=5)
    assert suite1["g2w_wasm64"]["extra"]["sha256"] == suite1["g2w_wasmtime_emit_wasm64"]["extra"]["sha256"], (
        f"native vs wasmtime Wasm64 mismatch: {suite1['g2w_wasm64']['extra']} vs {suite1['g2w_wasmtime_emit_wasm64']['extra']}"
    )
    for k, v in suite1.items():
        print(f"  {k:26s} wall={v['median_wall_s']:.3f}s {v['walls_s']}", flush=True)

    # Record phase stats breakdown v2 vs v3 on selfhost C and Wasm
    phase_stats = {}
    for label, binp in [("v2", GOOSE_V2), ("v3", GOOSE_V3)]:
        for target, ext in [("c", "c"), ("wasm-direct", "wasm")]:
            st_path = s1_dir / f"stats_{label}_{ext}.json"
            out_path = s1_dir / f"stats_{label}.{ext}"
            r = run_cmd([str(binp), "--target", target, "-O2", "--stdlib", "stdlib", "--wasm-stats", str(st_path), "-o", str(out_path), "selfhost/main.goose"], env=base_env)
            assert r["rc"] == 0, r["stderr"]
            phase_stats[f"{label}_{ext}"] = json.loads(st_path.read_text())

    # =========================================================================
    # Suite 2: Everyday dev build & edit-run turnaround across 8 examples
    # =========================================================================
    print("\n=== Suite 2: Everyday build & edit-run turnaround (8 examples, 5 rounds, CPU 7) ===", flush=True)
    examples = ["squares", "sieve", "sorting", "sudoku", "maze", "vm", "life", "tour"]
    s2_dir = WORK / "suite2"
    s2_dir.mkdir()
    node_bin = shutil.which("node")
    assert node_bin, "node not found"
    suite2 = {}
    for ex in examples:
        src = ROOT / "examples" / f"{ex}.goose"
        exp = (ROOT / "examples/expected" / f"{ex}.out").read_text()

        def mk_up_check(s=src):
            def f():
                r = run_cmd([str(UPSTREAM), "check", str(s), "--stdlib", str(STDLIB)], env=up_env)
                assert r["rc"] == 0, r["stderr"]
                return r
            return f

        def mk_g2w_check(s=src):
            def f():
                r = run_cmd([str(GOOSE_V3), "--check", "--stdlib", str(STDLIB), str(s)], env=base_env)
                assert r["rc"] == 0, r["stderr"]
                return r
            return f

        def mk_g2w_wasm(s=src, name=ex):
            out = s2_dir / f"{name}.wasm"
            def f():
                r = run_cmd([str(GOOSE_V3), "--target", "wasm-direct", "-O2", "--stdlib", str(STDLIB), "-o", str(out), str(s)], env=base_env)
                assert r["rc"] == 0, r["stderr"]
                r["extra"] = {"bytes": out.stat().st_size}
                return r
            return f

        def mk_g2w_native(s=src, name=ex):
            out = s2_dir / f"{name}-g2w"
            def f():
                r = run_cmd([sys.executable, str(ROOT / "scripts/goose_wasm.py"), "build", str(s), "--goose", str(GOOSE_V3), "--stdlib", str(STDLIB), "--backend", "native", "--cc", "clang", "-O2", "-o", str(out)], env=base_env)
                assert r["rc"] == 0, r["stderr"]
                return r
            return f

        def mk_up_build(s=src, name=ex):
            out = s2_dir / f"{name}-up"
            def f():
                r = run_cmd([str(UPSTREAM), "build", str(s), "--stdlib", str(STDLIB), "-O2", "-o", str(out)], env=up_env)
                assert r["rc"] == 0, r["stderr"]
                return r
            return f

        def mk_up_run_o0(s=src, expected=exp):
            def f():
                r = run_cmd([str(UPSTREAM), "run", str(s), "--stdlib", str(STDLIB), "-O0"], env=up_env)
                assert r["rc"] == 0 and r["stdout"] == expected
                return r
            return f

        def mk_g2w_wasm_node_cycle(s=src, name=ex, expected=exp):
            out = s2_dir / f"{name}-cycle.wasm"
            def f():
                t0 = time.perf_counter()
                r1 = run_cmd([str(GOOSE_V3), "--target", "wasm-direct", "-O2", "--stdlib", str(STDLIB), "-o", str(out), str(s)], env=base_env)
                assert r1["rc"] == 0, r1["stderr"]
                r2 = run_cmd([node_bin, str(ROOT / "scripts/run_wasm.mjs"), str(out)], env=base_env)
                wall = time.perf_counter() - t0
                assert r2["rc"] == 0 and r2["stdout"] == expected
                return {"rc": 0, "wall_s": wall}
            return f

        res = alternating([
            ("upstream_check", mk_up_check()),
            ("g2w_check", mk_g2w_check()),
            ("g2w_wasm_o2", mk_g2w_wasm()),
            ("g2w_native_o2", mk_g2w_native()),
            ("upstream_build_o2", mk_up_build()),
            ("upstream_run_o0", mk_up_run_o0()),
            ("g2w_wasm_plus_node", mk_g2w_wasm_node_cycle()),
        ], rounds=5)
        suite2[ex] = res
        print(
            f"  {ex:10s} chk={res['g2w_check']['median_wall_s']*1000:4.1f}ms vs {res['upstream_check']['median_wall_s']*1000:5.1f}ms | "
            f"wasm={res['g2w_wasm_o2']['median_wall_s']*1000:4.1f}ms | "
            f"up-bld={res['upstream_build_o2']['median_wall_s']*1000:5.1f}ms",
            flush=True,
        )

    # =========================================================================
    # Suite 3: Runtime performance vs upstream C++ Goose (5 alternating rounds)
    # =========================================================================
    print("\n=== Suite 3: Compiled runtime performance vs upstream C++ Goose (CPU 7, 5 rounds) ===", flush=True)
    s3_dir = WORK / "suite3"
    s3_dir.mkdir()
    suite3 = {}
    rt_examples = ["sorting", "sudoku", "sieve", "maze", "life"]
    for ex in rt_examples:
        exp = (ROOT / "examples/expected" / f"{ex}.out").read_text()
        bin_up = s2_dir / f"{ex}-up"
        bin_g2w = s2_dir / f"{ex}-g2w"
        wasm_g2w = s2_dir / f"{ex}.wasm"
        wbytes = wasm_g2w.read_bytes()
        prep = run_wasmtime.prepare_module(wbytes, s3_dir / f"{ex}.cwasm")

        def run_up(b=bin_up, expected=exp):
            r = run_cmd([str(b)], env=base_env)
            assert r["rc"] == 0 and r["stdout"] == expected
            return r

        def run_g2w_nat(b=bin_g2w, expected=exp):
            r = run_cmd([str(b)], env=base_env)
            assert r["rc"] == 0 and r["stdout"] == expected
            return r

        def run_wt(wb=wbytes, pr=prep, expected=exp):
            os.sched_setaffinity(0, {PIN_CPU})
            t0 = time.perf_counter()
            res = run_wasmtime.run_module(wb, b"", prepared=pr)
            wall = time.perf_counter() - t0
            assert res["exit_code"] == 0 and res["stdout"].decode("utf-8") == expected
            return {"rc": 0, "wall_s": wall}

        def run_node(w=wasm_g2w, expected=exp):
            r = run_cmd([node_bin, str(ROOT / "scripts/run_wasm.mjs"), str(w)], env=base_env)
            assert r["rc"] == 0 and r["stdout"] == expected
            return r

        res = alternating([
            ("upstream_native_o2", run_up),
            ("g2w_native_o2", run_g2w_nat),
            ("g2w_wasm_wasmtime", run_wt),
            ("g2w_wasm_node", run_node),
        ], rounds=5)
        suite3[ex] = res
        print(
            f"  {ex:10s} up-nat={res['upstream_native_o2']['median_wall_s']*1000:6.2f}ms | "
            f"g2w-nat={res['g2w_native_o2']['median_wall_s']*1000:6.2f}ms | "
            f"wasmtime={res['g2w_wasm_wasmtime']['median_wall_s']*1000:6.2f}ms | "
            f"node={res['g2w_wasm_node']['median_wall_s']*1000:6.2f}ms",
            flush=True,
        )

    mb_src = ROOT / "bench/langbench/mandelbrot.goose"
    mb_host = ROOT / "bench/host_input.c"
    mb_in = b"2048 1000 1\n"
    mb_up_c = s3_dir / "mb_up.c"
    mb_up_bin = s3_dir / "mb_up"
    mb_g2w_c = s3_dir / "mb_g2w.c"
    mb_g2w_bin = s3_dir / "mb_g2w"
    mb_wasm = s3_dir / "mb.wasm"
    assert run_cmd([str(UPSTREAM), str(mb_src), "--stdlib", str(STDLIB), "--standalone", "-O2", "-o", str(mb_up_c)], env=up_env)["rc"] == 0
    assert run_cmd(["clang", "-O2", str(mb_up_c), str(mb_host), "-lm", "-lpthread", "-o", str(mb_up_bin)])["rc"] == 0
    assert run_cmd([str(GOOSE_V3), "--target", "c", "-O2", "--stdlib", str(STDLIB), "-o", str(mb_g2w_c), str(mb_src)])["rc"] == 0
    assert run_cmd(["clang", "-O2", str(mb_g2w_c), str(mb_host), "-lm", "-lpthread", "-o", str(mb_g2w_bin)])["rc"] == 0
    assert run_cmd([str(GOOSE_V3), "--target", "wasm-direct", "-O2", "--stdlib", str(STDLIB), "-o", str(mb_wasm), str(mb_src)])["rc"] == 0
    mb_wbytes = mb_wasm.read_bytes()
    mb_prep = run_wasmtime.prepare_module(mb_wbytes, s3_dir / "mb.cwasm")

    def mb_parse(stdout: str) -> float:
        lines = stdout.strip().splitlines()
        assert lines[0].strip() == "1038538536", f"bad mandelbrot checksum: {lines}"
        return int(lines[1].strip()) / 1e9

    def mb_up_run():
        r = run_cmd([str(mb_up_bin)], stdin_bytes=mb_in)
        assert r["rc"] == 0
        r["wall_s"] = mb_parse(r["stdout"])
        return r

    def mb_g2w_nat_run():
        r = run_cmd([str(mb_g2w_bin)], stdin_bytes=mb_in)
        assert r["rc"] == 0
        r["wall_s"] = mb_parse(r["stdout"])
        return r

    def mb_wt_run():
        os.sched_setaffinity(0, {PIN_CPU})
        res = run_wasmtime.run_module(mb_wbytes, mb_in, prepared=mb_prep)
        assert res["exit_code"] == 0
        sec = mb_parse(res["stdout"].decode("utf-8"))
        return {"rc": 0, "wall_s": sec}

    def mb_node_run():
        r = run_cmd([node_bin, str(ROOT / "scripts/run_wasm.mjs"), str(mb_wasm)], stdin_bytes=mb_in)
        assert r["rc"] == 0
        r["wall_s"] = mb_parse(r["stdout"])
        return r

    suite3["mandelbrot"] = alternating([
        ("upstream_native_o2", mb_up_run),
        ("g2w_native_o2", mb_g2w_nat_run),
        ("g2w_wasm_wasmtime", mb_wt_run),
        ("g2w_wasm_node", mb_node_run),
    ], rounds=5)
    m = suite3["mandelbrot"]
    print(
        f"  {'mandelbrot':10s} up-nat={m['upstream_native_o2']['median_wall_s']:.3f}s | "
        f"g2w-nat={m['g2w_native_o2']['median_wall_s']:.3f}s | "
        f"wasmtime={m['g2w_wasm_wasmtime']['median_wall_s']:.3f}s | "
        f"node={m['g2w_wasm_node']['median_wall_s']:.3f}s (kernel clock)",
        flush=True,
    )

    # =========================================================================
    # Suite 4: Giant real-world compiler check (Blot2 cb1e9e15 & 6ad5fbb, v2 vs v3)
    # =========================================================================
    print("\n=== Suite 4: Frozen Blot2 checks (default 2 GiB, CPU 7, paired v2 vs v3) ===", flush=True)
    suite4 = {}
    for snap, cwd, stdlib, rounds in [
        ("cb1e9e15", ROOT / "build/blot2-cb1e9e15/compiler-goose/src", BLOT_STDLIB, 3),
        ("6ad5fbb", ROOT / "build/blot2-6ad5fbb/compiler-goose/src", STDLIB, 3),
    ]:
        v2_runs, v3_runs = [], []
        for r in range(rounds):
            order = [("v2", GOOSE_V2, v2_runs), ("v3", GOOSE_V3, v3_runs)] if r % 2 == 0 else [("v3", GOOSE_V3, v3_runs), ("v2", GOOSE_V2, v2_runs)]
            for tag, binp, dest in order:
                row = run_measured_rusage(
                    [str(binp), "--check", "--stdlib", str(stdlib), "--reachable-program", "--expansion-node-limit", "1000000", "main.goose"],
                    cwd=cwd, env=base_env, timeout_s=240,
                )
                assert row["rc"] == 1 and row["error_count"] == 1, f"{snap} {tag} unexpected: {row}"
                dest.append(row)
                print(f"  [{snap}] {tag} r{r+1}: wall={row['wall_s']:.2f}s cpu={row['cpu_s']:.2f}s rss={row['max_rss_kib']/1048576:.2f}GiB errors={row['error_count']}", flush=True)
        suite4[snap] = {
            "g2w_v2": {
                "median_wall_s": statistics.median(x["wall_s"] for x in v2_runs),
                "median_cpu_s": statistics.median(x["cpu_s"] for x in v2_runs),
                "median_rss_kib": statistics.median(x["max_rss_kib"] for x in v2_runs),
                "runs": v2_runs,
            },
            "g2w_v3": {
                "median_wall_s": statistics.median(x["wall_s"] for x in v3_runs),
                "median_cpu_s": statistics.median(x["cpu_s"] for x in v3_runs),
                "median_rss_kib": statistics.median(x["max_rss_kib"] for x in v3_runs),
                "runs": v3_runs,
            },
        }

    out_data = {
        "schema": "goose-to-wasm-release-bench-v3",
        "release": "v2026.4-3",
        "cpu": PIN_CPU,
        "host": platform.platform(),
        "clang": subprocess.check_output(["clang", "--version"], text=True).splitlines()[0],
        "node": subprocess.check_output([node_bin, "--version"], text=True).strip(),
        "v2_version": subprocess.check_output([str(GOOSE_V2), "--version"], text=True).strip(),
        "v2_sha256": sha256_file(GOOSE_V2),
        "g2w_version": subprocess.check_output([str(GOOSE_V3), "--version"], text=True).strip(),
        "g2w_sha256": sha256_file(GOOSE_V3),
        "upstream_sha256": sha256_file(UPSTREAM),
        "compiler_wasm_bytes": {"wasm64": len(comp64_bytes)},
        "suite1_selfcompile": suite1,
        "suite1_phase_stats": phase_stats,
        "suite2_examples_build": suite2,
        "suite3_runtime": suite3,
        "suite4_blot2": suite4,
    }
    res_path = OUT_DIR / "results.json"
    res_path.write_text(json.dumps(out_data, indent=2) + "\n")
    print(f"\nSaved pinned results to {res_path}", flush=True)


if __name__ == "__main__":
    main()
