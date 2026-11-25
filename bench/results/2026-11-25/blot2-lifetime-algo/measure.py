#!/usr/bin/env python3
"""Pinned CPU-7 alternating benchmarks: qualified blot2-algo vs v2026.4-2."""
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
WORK = ROOT / "build/bench-blot2-algo"

GOOSE_V2 = ROOT / "build/qualify-v2026.4-2/bootstrap/bin/goose"
GOOSE_NEW = ROOT / "build/qualify-blot2-algo/bootstrap/bin/goose"
STDLIB = ROOT / "stdlib"
BLOT_STDLIB = ROOT / "build/blot-stdlib"
PIN_CPU = 7


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_measured(cmd: list[str], *, cwd: Path, timeout_s: int = 300) -> dict:
    """Run in a fresh child via os.wait4 pinned to CPU 7 for exact wall, CPU, and max RSS."""
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
        "    out_txt = out.read().decode('utf-8', 'replace')\n"
        "    err_txt = err.read().decode('utf-8', 'replace')\n"
        "    lines = (err_txt or out_txt).strip().splitlines()\n"
        "    print(json.dumps({'rc': os.waitstatus_to_exitcode(st), 'timed_out': to, 'wall_s': wall,\n"
        "        'cpu_s': ru.ru_utime + ru.ru_stime, 'max_rss_kib': ru.ru_maxrss,\n"
        "        'error_count': sum(1 for l in lines if ': error:' in l),\n"
        "        'first_line': lines[0] if lines else ''}))\n"
    )
    r = subprocess.run(
        [sys.executable, "-c", helper, str(cwd), str(timeout_s), str(PIN_CPU), json.dumps(cmd)],
        stdin=subprocess.DEVNULL, capture_output=True, text=True, check=True,
    )
    return json.loads(r.stdout)


def summarize(rows: list[dict]) -> dict:
    walls = [x["wall_s"] for x in rows]
    cpus = [x["cpu_s"] for x in rows]
    rss = [x["max_rss_kib"] for x in rows]
    return {
        "median_wall_s": round(statistics.median(walls), 4),
        "median_cpu_s": round(statistics.median(cpus), 4),
        "median_rss_gib": round(statistics.median(rss) / 1048576.0, 4),
        "walls_s": [round(v, 4) for v in walls],
        "cpus_s": [round(v, 4) for v in cpus],
        "max_rss_kib": rss,
        "rc": rows[-1]["rc"],
        "error_count": rows[-1]["error_count"],
        "first_line": rows[-1]["first_line"],
    }


def main() -> None:
    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True)

    clang_ver = subprocess.run(["clang", "--version"], capture_output=True, text=True, check=True).stdout.splitlines()[0]
    head_sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()
    qual_summary = json.loads((ROOT / "build/qualify-blot2-algo/summary.json").read_text())

    results: dict = {
        "date": "2026-11-25",
        "pin_cpu": PIN_CPU,
        "host": platform.platform(),
        "uname": " ".join(platform.uname()),
        "clang": clang_ver,
        "base_head": head_sha,
        "compilers": {
            "v2026.4-2": {"path": str(GOOSE_V2.relative_to(ROOT)), "sha256": sha256_file(GOOSE_V2)},
            "blot2-algo": {
                "path": str(GOOSE_NEW.relative_to(ROOT)),
                "sha256": sha256_file(GOOSE_NEW),
                "fixed_point_c_sha256": qual_summary["bootstrap"]["next_generation_c_sha256"],
            },
        },
        "selfhost": {},
        "blot2": {},
    }

    # Suite 1: selfhost/main.goose (5 alternating rounds, CPU 7)
    print("=== Suite 1: selfhost/main.goose (5 alternating rounds, CPU 7) ===", flush=True)
    for mode, label, build_args in [
        ("check", "--check", ["--check", "--stdlib", "stdlib", "selfhost/main.goose"]),
        ("emit_c", "--target c -O2", ["--target", "c", "-O2", "--stdlib", "stdlib", "-o", "{out}", "selfhost/main.goose"]),
        ("emit_wasm64", "--target wasm-direct --wasm-memory64 -O2", ["--target", "wasm-direct", "--wasm-memory64", "--wasm-max-pages", "4194304", "-O2", "--stdlib", "stdlib", "-o", "{out}", "selfhost/main.goose"]),
    ]:
        rows_v2, rows_new = [], []
        hashes = {}
        for r in range(5):
            pair = [("v2", GOOSE_V2, rows_v2), ("new", GOOSE_NEW, rows_new)]
            if r % 2 == 1:
                pair.reverse()
            for tag, binp, dest in pair:
                out_f = WORK / f"selfhost_{mode}_{tag}.out"
                cmd = [str(binp)] + [str(out_f) if a == "{out}" else a for a in build_args]
                res = run_measured(cmd, cwd=ROOT)
                assert res["rc"] == 0, f"{mode} {tag} failed: {res}"
                dest.append(res)
                if "{out}" in build_args and r == 0:
                    hashes[tag] = {"bytes": out_f.stat().st_size, "sha256": sha256_file(out_f)}
        s_v2 = summarize(rows_v2)
        s_new = summarize(rows_new)
        results["selfhost"][mode] = {
            "label": label,
            "v2026.4-2": s_v2,
            "blot2-algo": s_new,
            "speedup_wall": round(s_v2["median_wall_s"] / s_new["median_wall_s"], 3),
            "outputs": hashes,
        }
        if hashes:
            assert hashes["v2"] == hashes["new"], f"output mismatch for {mode}: {hashes}"
        print(f"  {mode:12s}: v2={s_v2['median_wall_s']:.3f}s  new={s_new['median_wall_s']:.3f}s  ({s_v2['median_wall_s']/s_new['median_wall_s']:.2f}x)", flush=True)

    # Suite 2: Frozen Blot2 snapshots (3 alternating paired rounds each, CPU 7)
    print("\n=== Suite 2: Frozen Blot2 checks (3 alternating paired rounds each, CPU 7) ===", flush=True)
    for snap, cwd, stdlib, expected_err in [
        ("cb1e9e15", ROOT / "build/blot2-cb1e9e15/compiler-goose/src", BLOT_STDLIB, "check/check.goose:3422:86:"),
        ("6ad5fbb", ROOT / "build/blot2-6ad5fbb/compiler-goose/src", STDLIB, "check/check.goose:3179:86:"),
    ]:
        rows_v2, rows_new = [], []
        for r in range(3):
            pair = [("v2", GOOSE_V2, rows_v2), ("new", GOOSE_NEW, rows_new)]
            if r % 2 == 1:
                pair.reverse()
            for tag, binp, dest in pair:
                cmd = [str(binp), "main.goose", "--stdlib", str(stdlib), "--reachable-program", "--expansion-node-limit", "1000000", "--check"]
                res = run_measured(cmd, cwd=cwd, timeout_s=240)
                assert res["rc"] == 1 and res["error_count"] == 1 and expected_err in res["first_line"], f"{snap} {tag}: {res}"
                dest.append(res)
                print(f"  {snap} r{r+1} {tag:3s}: wall={res['wall_s']:.2f}s  cpu={res['cpu_s']:.2f}s  rss={res['max_rss_kib']/1048576:.2f}GiB", flush=True)
        s_v2 = summarize(rows_v2)
        s_new = summarize(rows_new)
        results["blot2"][snap] = {
            "v2026.4-2": s_v2,
            "blot2-algo": s_new,
            "speedup_wall": round(s_v2["median_wall_s"] / s_new["median_wall_s"], 3),
            "speedup_cpu": round(s_v2["median_cpu_s"] / s_new["median_cpu_s"], 3),
            "rss_delta_mib": round((s_new["median_rss_gib"] - s_v2["median_rss_gib"]) * 1024.0, 1),
        }
        print(f"  => {snap} MEDIAN: v2={s_v2['median_wall_s']:.2f}s ({s_v2['median_rss_gib']:.2f}GiB) -> new={s_new['median_wall_s']:.2f}s ({s_new['median_rss_gib']:.2f}GiB) | {s_v2['median_wall_s']/s_new['median_wall_s']:.2f}x wall, {s_v2['median_cpu_s']/s_new['median_cpu_s']:.2f}x cpu", flush=True)

    (OUT_DIR / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    print(f"\nWrote {OUT_DIR / 'results.json'}", flush=True)


if __name__ == "__main__":
    main()
