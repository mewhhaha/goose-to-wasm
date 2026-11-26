#!/usr/bin/env python3
"""Benchmark harness for frozen compiler-throughput workloads.

Measures wall time (median of N rounds) and `--wasm-stats` stage breakdowns
for both pinned single-core (`taskset -c 7`) and unpinned multi-core runs,
plus optional SHA-256 bit-identity verification across thread counts.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[4]
WORKLOADS = ROOT / 'build/bench-workloads/2026-11-26'
BLOT2_SRC = ROOT / 'build/blot2-head-probe/compiler-goose/src/main.goose'
BLOT2_STDLIB = (ROOT / '../blot2/build/goose-port/upstream-d5ae5bb/source-precision/stdlib').resolve()


def workload_specs() -> dict[str, dict]:
    manifest = json.loads((WORKLOADS / 'manifest.json').read_text())
    return {
        'flat_multi_100k_o0': {
            'loc': manifest['flat_multi_100k']['total_lines'],
            'src': str(WORKLOADS / 'flat_multi_100k/main.goose'),
            'args': ['--stdlib', str(WORKLOADS / 'selfhost_f746c6e/stdlib'), '--target', 'wasm-direct', '-O0'],
        },
        'flat_multi_100k_o2': {
            'loc': manifest['flat_multi_100k']['total_lines'],
            'src': str(WORKLOADS / 'flat_multi_100k/main.goose'),
            'args': ['--stdlib', str(WORKLOADS / 'selfhost_f746c6e/stdlib'), '--target', 'wasm-direct', '-O2'],
        },
        'flat_single_100k_o0': {
            'loc': manifest['flat_single_100k']['total_lines'],
            'src': str(WORKLOADS / 'flat_single_100k/main.goose'),
            'args': ['--stdlib', str(WORKLOADS / 'selfhost_f746c6e/stdlib'), '--target', 'wasm-direct', '-O0'],
        },
        'flat_single_100k_o2': {
            'loc': manifest['flat_single_100k']['total_lines'],
            'src': str(WORKLOADS / 'flat_single_100k/main.goose'),
            'args': ['--stdlib', str(WORKLOADS / 'selfhost_f746c6e/stdlib'), '--target', 'wasm-direct', '-O2'],
        },
        'selfhost_o0_wasm64': {
            'loc': manifest['selfhost_f746c6e']['selfhost_lines'],
            'src': str(WORKLOADS / 'selfhost_f746c6e/selfhost/main.goose'),
            'args': ['--stdlib', str(WORKLOADS / 'selfhost_f746c6e/stdlib'), '--target', 'wasm-direct', '--wasm-memory64', '-O0'],
        },
        'selfhost_o2_wasm64': {
            'loc': manifest['selfhost_f746c6e']['selfhost_lines'],
            'src': str(WORKLOADS / 'selfhost_f746c6e/selfhost/main.goose'),
            'args': ['--stdlib', str(WORKLOADS / 'selfhost_f746c6e/stdlib'), '--target', 'wasm-direct', '--wasm-memory64', '-O2'],
        },
        'selfhost_o0_c': {
            'loc': manifest['selfhost_f746c6e']['selfhost_lines'],
            'src': str(WORKLOADS / 'selfhost_f746c6e/selfhost/main.goose'),
            'args': ['--stdlib', str(WORKLOADS / 'selfhost_f746c6e/stdlib'), '--target', 'c', '-O0'],
        },
        'selfhost_o2_c': {
            'loc': manifest['selfhost_f746c6e']['selfhost_lines'],
            'src': str(WORKLOADS / 'selfhost_f746c6e/selfhost/main.goose'),
            'args': ['--stdlib', str(WORKLOADS / 'selfhost_f746c6e/stdlib'), '--target', 'c', '-O2'],
        },
        'flat_multi_250k_o0': {
            'loc': 246765,
            'src': str(WORKLOADS / 'flat_multi_250k/main.goose'),
            'args': ['--stdlib', str(WORKLOADS / 'selfhost_f746c6e/stdlib'), '--target', 'wasm-direct', '-O0'],
        },
        'flat_multi_100k_o0_c': {
            'loc': manifest['flat_multi_100k']['total_lines'],
            'src': str(WORKLOADS / 'flat_multi_100k/main.goose'),
            'args': ['--stdlib', str(WORKLOADS / 'selfhost_f746c6e/stdlib'), '--target', 'c', '-O0'],
        },
        'flat_multi_250k_o0_c': {
            'loc': 246765,
            'src': str(WORKLOADS / 'flat_multi_250k/main.goose'),
            'args': ['--stdlib', str(WORKLOADS / 'selfhost_f746c6e/stdlib'), '--target', 'c', '-O0'],
        },
        'blot2_o0_wasm64': {
            'loc': 78954,
            'src': str(BLOT2_SRC),
            'args': ['--stdlib', str(BLOT2_STDLIB), '--library', '--reachable-program',
                     '--expansion-node-limit', '1000000', '--target', 'wasm-direct',
                     '--wasm-memory64', '--wasm-max-pages', '65536', '-O0'],
        },
        'blot2_o2_wasm64': {
            'loc': 78954,
            'src': str(BLOT2_SRC),
            'args': ['--stdlib', str(BLOT2_STDLIB), '--library', '--reachable-program',
                     '--expansion-node-limit', '1000000', '--target', 'wasm-direct',
                     '--wasm-memory64', '--wasm-max-pages', '65536', '-O2'],
        },
        'blot2_o0_c': {
            'loc': 78954,
            'src': str(BLOT2_SRC),
            'args': ['--stdlib', str(BLOT2_STDLIB), '--library', '--reachable-program',
                     '--expansion-node-limit', '1000000', '--target', 'c', '-O0'],
        },
    }


def run_once(compiler: Path, spec: dict, extra_args: list[str], pin_cpu: int | None) -> dict:
    with tempfile.TemporaryDirectory(prefix='goosew_bench_') as tmp:
        out_path = Path(tmp) / 'out.bin'
        stats_path = Path(tmp) / 'stats.json'
        cmd = [str(compiler), spec['src'], *spec['args'], *extra_args,
               '-o', str(out_path), '--wasm-stats', str(stats_path)]
        if pin_cpu is not None:
            cmd = ['taskset', '-c', str(pin_cpu), *cmd]
        t0 = time.perf_counter_ns()
        res = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True)
        wall_ns = time.perf_counter_ns() - t0
        if res.returncode != 0:
            raise RuntimeError(f'Command failed ({res.returncode}): {cmd}\nstderr:\n{res.stderr}\nstdout:\n{res.stdout}')
        stats = json.loads(stats_path.read_text()) if stats_path.exists() else {}
        out_bytes = out_path.read_bytes()
        return {
            'wall_ns': wall_ns,
            'out_sha256': hashlib.sha256(out_bytes).hexdigest(),
            'out_size': len(out_bytes),
            'stats': stats,
        }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--compiler', type=Path, required=True)
    ap.add_argument('--label', required=True)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--workloads', nargs='+', default=['flat_multi_100k_o0', 'flat_multi_100k_o2',
                                                       'flat_single_100k_o0', 'selfhost_o0_wasm64',
                                                       'selfhost_o2_wasm64', 'blot2_o0_wasm64'])
    ap.add_argument('--rounds', type=int, default=3)
    ap.add_argument('--warmup', type=int, default=1)
    ap.add_argument('--pin-cpu', type=int, default=None)
    ap.add_argument('--extra-arg', action='append', default=[])
    args = ap.parse_args()

    compiler = args.compiler.resolve()
    compiler_sha = hashlib.sha256(compiler.read_bytes()).hexdigest()
    specs = workload_specs()
    results = {
        'label': args.label,
        'compiler': str(compiler),
        'compiler_sha256': compiler_sha,
        'pin_cpu': args.pin_cpu,
        'extra_args': args.extra_arg,
        'rounds': args.rounds,
        'warmup': args.warmup,
        'timestamp': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
        'workloads': {},
    }
    for name in args.workloads:
        spec = specs[name]
        for _ in range(args.warmup):
            run_once(compiler, spec, args.extra_arg, args.pin_cpu)
        runs = [run_once(compiler, spec, args.extra_arg, args.pin_cpu) for _ in range(args.rounds)]
        shas = {r['out_sha256'] for r in runs}
        if len(shas) != 1:
            raise RuntimeError(f'Non-deterministic output on {name}: {shas}')
        walls_ms = [r['wall_ns'] / 1e6 for r in runs]
        med_ms = statistics.median(walls_ms)
        loc_per_s = spec['loc'] / (med_ms / 1000.0)
        stage_keys = ['parse_ns', 'typecheck_ns', 'lifetime_ns', 'optimize_ns', 'backend_ns']
        med_stages_ms = {}
        for k in stage_keys:
            vals = [r['stats'].get(k, 0) / 1e6 for r in runs]
            med_stages_ms[k.replace('_ns', '_ms')] = round(statistics.median(vals), 2)
        tc_excl = round(med_stages_ms['typecheck_ms'] - med_stages_ms['lifetime_ms'], 2)
        med_stages_ms['typecheck_excl_life_ms'] = tc_excl
        results['workloads'][name] = {
            'loc': spec['loc'],
            'median_wall_ms': round(med_ms, 2),
            'min_wall_ms': round(min(walls_ms), 2),
            'walls_ms': [round(x, 2) for x in walls_ms],
            'loc_per_sec': round(loc_per_s),
            'stages_ms': med_stages_ms,
            'out_sha256': next(iter(shas)),
            'out_size': runs[0]['out_size'],
            'counts': {k: runs[0]['stats'].get(k) for k in ('nodes', 'types', 'symbols', 'functions') if k in runs[0]['stats']},
        }
        print(f"{name:22s}  wall={med_ms:7.1f} ms ({loc_per_s:9,.0f} LOC/s)  "
              f"parse={med_stages_ms['parse_ms']:5.1f}  tc={tc_excl:5.1f}  life={med_stages_ms['lifetime_ms']:6.1f}  "
              f"opt={med_stages_ms['optimize_ms']:5.1f}  be={med_stages_ms['backend_ms']:5.1f}  sha={next(iter(shas))[:10]}")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    main()
