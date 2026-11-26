#!/usr/bin/env python3
"""Alternating paired A/B compiler benchmark on a pinned CPU core (or unpinned for multi-core)."""
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

from bench_harness import workload_specs


def run_once(compiler: Path, spec: dict, extra_args: list[str], pin_cpu: int | None) -> dict:
    with tempfile.TemporaryDirectory(prefix='goosew_ab_') as tmp:
        out_path = Path(tmp) / 'out.bin'
        stats_path = Path(tmp) / 'stats.json'
        err_path = Path(tmp) / 'stderr.txt'
        cmd = [str(compiler), spec['src'], *spec['args'], *extra_args,
               '-o', str(out_path), '--wasm-stats', str(stats_path)]
        if pin_cpu is not None:
            cmd = ['taskset', '-c', str(pin_cpu), *cmd]
        with err_path.open('wb') as ef:
            t0 = time.perf_counter_ns()
            proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=ef)
            _, status, rusage = os.wait4(proc.pid, 0)
            wall_ns = time.perf_counter_ns() - t0
            proc.returncode = os.waitstatus_to_exitcode(status)
        if proc.returncode != 0:
            raise RuntimeError(f'Command failed ({proc.returncode}): {cmd}\nstderr:\n{err_path.read_text(errors="replace")}')
        stats = json.loads(stats_path.read_text()) if stats_path.exists() else {}
        out_bytes = out_path.read_bytes()
        return {
            'wall_ns': wall_ns,
            'max_rss_kb': rusage.ru_maxrss,
            'out_sha256': hashlib.sha256(out_bytes).hexdigest(),
            'out_size': len(out_bytes),
            'stats': stats,
        }


def summarize(runs: list[dict], loc: int) -> dict:
    walls_ms = [r['wall_ns'] / 1e6 for r in runs]
    med_ms = statistics.median(walls_ms)
    stages = {}
    for k in ('parse_ns', 'typecheck_ns', 'lifetime_ns', 'optimize_ns', 'backend_ns'):
        stages[k.replace('_ns', '_ms')] = round(statistics.median(r['stats'].get(k, 0) / 1e6 for r in runs), 2)
    stages['typecheck_excl_life_ms'] = round(stages['typecheck_ms'] - stages['lifetime_ms'], 2)
    compile_ms = round(stages['parse_ms'] + stages['typecheck_ms'] + stages['optimize_ms'] + stages['backend_ms'], 2)
    stages['compile_ms'] = compile_ms
    stages['other_ms'] = round(max(0.0, med_ms - compile_ms), 2)
    rss_kb = [r['max_rss_kb'] for r in runs]
    return {
        'loc': loc,
        'median_wall_ms': round(med_ms, 2),
        'min_wall_ms': round(min(walls_ms), 2),
        'walls_ms': [round(x, 2) for x in walls_ms],
        'loc_per_sec': round(loc / (med_ms / 1000.0)),
        'compile_loc_per_sec': round(loc / (compile_ms / 1000.0)) if compile_ms > 0 else 0,
        'median_max_rss_kb': round(statistics.median(rss_kb)),
        'stages_ms': stages,
        'out_sha256': runs[0]['out_sha256'],
        'out_size': runs[0]['out_size'],
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--base', type=Path, required=True)
    ap.add_argument('--base-label', required=True)
    ap.add_argument('--cand', type=Path, required=True)
    ap.add_argument('--cand-label', required=True)
    ap.add_argument('--base-arg', action='append', default=[])
    ap.add_argument('--cand-arg', action='append', default=[])
    ap.add_argument('--workloads', nargs='+', required=True)
    ap.add_argument('--rounds', type=int, default=3)
    ap.add_argument('--pin-cpu', type=int, default=7)
    ap.add_argument('--no-pin', action='store_true')
    ap.add_argument('--out', type=Path, required=True)
    args = ap.parse_args()

    pin = None if args.no_pin else args.pin_cpu
    base = args.base.resolve()
    cand = args.cand.resolve()
    specs = workload_specs()
    report = {
        'timestamp': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
        'pin_cpu': pin,
        'rounds': args.rounds,
        'base': {'label': args.base_label, 'path': str(base), 'sha256': hashlib.sha256(base.read_bytes()).hexdigest(), 'args': args.base_arg},
        'cand': {'label': args.cand_label, 'path': str(cand), 'sha256': hashlib.sha256(cand.read_bytes()).hexdigest(), 'args': args.cand_arg},
        'workloads': {},
    }
    for name in args.workloads:
        spec = specs[name]
        # Warmup once each
        run_once(base, spec, args.base_arg, pin)
        run_once(cand, spec, args.cand_arg, pin)
        b_runs, c_runs = [], []
        for r in range(args.rounds):
            if r % 2 == 0:
                b_runs.append(run_once(base, spec, args.base_arg, pin))
                c_runs.append(run_once(cand, spec, args.cand_arg, pin))
            else:
                c_runs.append(run_once(cand, spec, args.cand_arg, pin))
                b_runs.append(run_once(base, spec, args.base_arg, pin))
        b_shas = {x['out_sha256'] for x in b_runs}
        c_shas = {x['out_sha256'] for x in c_runs}
        assert len(b_shas) == 1 and len(c_shas) == 1, f'Non-deterministic {name}: {b_shas} vs {c_shas}'
        bs = summarize(b_runs, spec['loc'])
        cs = summarize(c_runs, spec['loc'])
        speedup = round(bs['median_wall_ms'] / cs['median_wall_ms'], 3) if cs['median_wall_ms'] > 0 else 0.0
        same_bytes = bs['out_sha256'] == cs['out_sha256']
        report['workloads'][name] = {
            'base': bs,
            'cand': cs,
            'wall_speedup': speedup,
            'byte_identical': same_bytes,
        }
        print(f"{name:22s}  base={bs['median_wall_ms']:7.1f} ms  cand={cs['median_wall_ms']:7.1f} ms  "
              f"speedup={speedup:5.2f}x  life={bs['stages_ms']['lifetime_ms']:6.1f}->{cs['stages_ms']['lifetime_ms']:6.1f}  "
              f"opt={bs['stages_ms']['optimize_ms']:5.1f}->{cs['stages_ms']['optimize_ms']:5.1f}  "
              f"be={bs['stages_ms']['backend_ms']:5.1f}->{cs['stages_ms']['backend_ms']:5.1f}  same={same_bytes}")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
