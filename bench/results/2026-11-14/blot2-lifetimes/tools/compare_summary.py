import json, math
W = '/home/jacobt/src/goose-to-wasm/.claude/worktrees/agent-a17bf72e44110d4f2/'
def g(xs): return math.exp(sum(math.log(x) for x in xs) / len(xs))
out = {'method': 'bench/compare_compilers.py, 31 samples per cell after one warmup, shuffled balanced rounds; '
                  'ratio = candidate median compile wall / parent median', 'runs': []}
for name, path in [('final, CPU 7, seed 900614', 'build/compare-final/report.json'),
                   ('final, CPU 5, seed 900615', 'build/compare-final-rep/report.json'),
                   ('null: two copies of the 9806f0e binary, CPU 7, seed 900616', 'build/compare-null/report.json')]:
    d = json.load(open(W + path))
    med = {(r['compiler'], r['workload'], r['target']): r['compile_wall_seconds'] for r in d['summary']}
    cells = []
    for (c, w, t), m in sorted(med.items()):
        if c != 'candidate': continue
        p = med[('parent', w, t)]
        cells.append({'workload': w, 'target': t, 'parent_median_s': p['median'], 'parent_mad_s': p['mad'],
                      'candidate_median_s': m['median'], 'candidate_mad_s': m['mad'], 'ratio': m['median'] / p['median']})
    out['runs'].append({'run': name, 'status': d['status'], 'configuration': d['configuration'],
                        'compilers': d['compilers'],
                        'geomean': {'wasm-direct': g([c['ratio'] for c in cells if c['target'] == 'wasm-direct']),
                                    'native-c': g([c['ratio'] for c in cells if c['target'] == 'native-c']),
                                    'all': g([c['ratio'] for c in cells])},
                        'cells': cells})
json.dump(out, open(W + 'bench/results/2026-11-14/blot2-lifetimes/compiler-comparison.json', 'w'), indent=1)
print([(r['run'], round(r['geomean']['all'], 4)) for r in out['runs']])
