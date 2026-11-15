#!/usr/bin/env python3
"""statcorpus.py COMPILER OUT.json [--jobs N]: run COMPILER --check over every
unique conformance source and collect its LIFESTAT line (frames, functions,
most frames of one function)."""
import argparse, json, subprocess, sys, tarfile, shutil
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT = Path(__file__).resolve().parents[2]
ap = argparse.ArgumentParser(); ap.add_argument('compiler'); ap.add_argument('out'); ap.add_argument('--jobs', type=int, default=4)
args = ap.parse_args()
manifest = json.loads((ROOT / 'tests/conformance/cases.json').read_text())
upstream = ROOT / 'build/tmp/corpus-upstream'
if not upstream.exists():
    with tarfile.open(ROOT / manifest['upstream']['archive']) as bundle:
        for member in bundle:
            if not member.isfile(): continue
            p = upstream / member.name; p.parent.mkdir(parents=True, exist_ok=True)
            with bundle.extractfile(member) as s, p.open('wb') as o: shutil.copyfileobj(s, o)
    shutil.copytree(ROOT / 'stdlib', upstream / 'stdlib')
sources = {}
for case in manifest['cases']:
    name = case['source']
    if name in sources: continue
    if name.startswith('upstream:'): sources[name] = (upstream / name[len('upstream:'):], upstream, upstream / 'stdlib')
    else: sources[name] = (ROOT / name, ROOT, ROOT / 'stdlib')
def run(name):
    path, cwd, lib = sources[name]
    r = subprocess.run([args.compiler, str(path), '--target', 'native', '--check', '--stdlib', str(lib)], cwd=cwd, capture_output=True, timeout=600)
    for line in r.stderr.decode(errors='replace').splitlines():
        if line.startswith('LIFESTAT'): return name, [int(x) for x in line.split()[1:]]
    return name, None
rows = {}
with ThreadPoolExecutor(args.jobs) as pool:
    for name, stat in pool.map(run, sorted(sources)): rows[name] = stat
Path(args.out).write_text(json.dumps(rows, indent=0))
have = [v for v in rows.values() if v]
print('sources', len(rows), 'with lifetime pass', len(have))
for i, label in enumerate(['frames', 'functions', 'most per function']):
    vals = sorted(v[i] for v in have)
    print(label, 'max', vals[-1], 'p99', vals[int(len(vals) * 0.99)], 'p90', vals[int(len(vals) * 0.9)], 'median', vals[len(vals) // 2])
for limit in [1, 2, 4, 8, 16, 32, 64]:
    print('programs with a function over', limit, 'frames:', sum(1 for v in have if v[2] > limit))
