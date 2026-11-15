#!/usr/bin/env python3
"""geomean.py REPORT.json...: candidate/parent median compile wall time per cell and geometric means."""
import json, math, sys
def g(xs): return math.exp(sum(math.log(x) for x in xs) / len(xs))
for path in sys.argv[1:]:
    d = json.load(open(path))
    med = {(r['compiler'], r['workload'], r['target']): r['compile_wall_seconds']['median'] for r in d['summary']}
    ratios = {(w, t): m / med[('parent', w, t)] for (c, w, t), m in med.items() if c == 'candidate'}
    print(path, 'wasm %.4f' % g([v for (w, t), v in ratios.items() if t == 'wasm-direct']),
          'c %.4f' % g([v for (w, t), v in ratios.items() if t == 'native-c']), 'all %.4f' % g(list(ratios.values())), len(ratios),
          'min %s %.3f' % min(((k, v) for k, v in ratios.items()), key=lambda x: x[1]),
          'max %s %.3f' % max(((k, v) for k, v in ratios.items()), key=lambda x: x[1]))
