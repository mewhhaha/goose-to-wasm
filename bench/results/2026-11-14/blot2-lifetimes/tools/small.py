#!/usr/bin/env python3
"""small.py OUT.json LABEL=COMPILER... [--rounds N]
Times an empty program (--check), examples/sorting.goose (--check) and
sorting at -O2 --target native, interleaving compilers, pinned to CPU 7.
Reports median wall, user and minor faults per (compiler, workload)."""
import json, os, resource, statistics, subprocess, sys, time
W = '/home/jacobt/src/goose-to-wasm/.claude/worktrees/agent-a17bf72e44110d4f2'
args = sys.argv[1:]
rounds = 15
if '--rounds' in args:
    i = args.index('--rounds'); rounds = int(args[i + 1]); del args[i:i + 2]
out_path = args[0]
compilers = [a.split('=', 1) for a in args[1:]]
os.makedirs(W + '/build/tmp/small', exist_ok=True)
empty = W + '/build/tmp/small/empty.goose'
open(empty, 'w').write('fn main() {}\n')
work = {
    'empty-check': [empty, '--check'],
    'sorting-check': [W + '/examples/sorting.goose', '--check'],
    'sorting-native-O2': [W + '/examples/sorting.goose', '-O2', '--target', 'native', '-o', W + '/build/tmp/small/sorting.c'],
}
def once(compiler, argv):
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    t0 = time.perf_counter()
    r = subprocess.run(['taskset', '-c', '7', compiler, *argv, '--stdlib', W + '/stdlib'], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    wall = time.perf_counter() - t0
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    assert r.returncode == 0, (compiler, argv, r.stderr[-500:])
    return wall, after.ru_utime - before.ru_utime, after.ru_minflt - before.ru_minflt
rows = {}
for name, argv in work.items():
    for label, compiler in compilers: once(compiler, argv)
for k in range(rounds):
    for name, argv in work.items():
        for label, compiler in (compilers if k % 2 == 0 else compilers[::-1]):
            rows.setdefault((label, name), []).append(once(compiler, argv))
report = []
for (label, name), samples in sorted(rows.items(), key=lambda x: (x[0][1], x[0][0])):
    report.append({'compiler': label, 'workload': name, 'samples': len(samples),
                   'wall_ms': round(1000 * statistics.median(s[0] for s in samples), 2),
                   'user_ms': round(1000 * statistics.median(s[1] for s in samples), 2),
                   'minflt': int(statistics.median(s[2] for s in samples))})
for r in report: print('%-20s %-14s wall %8.2f ms  user %8.2f ms  minflt %7d' % (r['workload'], r['compiler'], r['wall_ms'], r['user_ms'], r['minflt']))
json.dump({'compilers': dict(compilers), 'rounds': rounds, 'rows': report}, open(out_path, 'w'), indent=1)
