#!/usr/bin/env python3
"""Run two fingerprint-instrumented compilers with --check over every unique
conformance source and compare their LIFEFP state lines, stdout and other stderr.

usage: fpcompare.py BASE CAND OUTDIR [--jobs N] [--filter TEXT]
"""
import argparse, json, hashlib, subprocess, sys, tarfile, shutil
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parents[4]
ap = argparse.ArgumentParser()
ap.add_argument('base'); ap.add_argument('cand'); ap.add_argument('out')
ap.add_argument('--jobs', type=int, default=4)
ap.add_argument('--filter', default='')
args = ap.parse_args()
out = Path(args.out); out.mkdir(parents=True, exist_ok=True)
manifest = json.loads((ROOT / 'tests/conformance/cases.json').read_text())
upstream = out / 'upstream'
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
    if name in sources or args.filter not in name: continue
    if name.startswith('upstream:'):
        sources[name] = (upstream / name[len('upstream:'):], upstream, upstream / 'stdlib')
    else:
        sources[name] = (ROOT / name, ROOT, ROOT / 'stdlib')

def run(compiler, name):
    path, cwd, lib = sources[name]
    try:
        r = subprocess.run([compiler, str(path), '--target', 'native', '--check', '--stdlib', str(lib)], cwd=cwd, capture_output=True, timeout=600)
        code, so, se = r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        return ('timeout', [], '', '')
    lines = [l for l in se.decode(errors='replace').splitlines() if l.startswith('LIFEFP')]
    rest = [l for l in se.decode(errors='replace').splitlines() if not l.startswith('LIFEFP')]
    return (code, lines, hashlib.sha256(so).hexdigest(), hashlib.sha256('\n'.join(rest).encode()).hexdigest())

def compare(name):
    a = run(args.base, name); b = run(args.cand, name)
    return name, a == b, a, b

rows = []
with ThreadPoolExecutor(args.jobs) as pool:
    for i, (name, same, a, b) in enumerate(pool.map(compare, sorted(sources)), 1):
        rows.append({'source': name, 'same': same, 'fingerprints': len(a[1]), 'base': a if not same else None, 'cand': b if not same else None})
        if not same: print('DIFFERS', name, file=sys.stderr, flush=True)
        if i % 500 == 0: print(i, 'compared', flush=True)
diff = [r for r in rows if not r['same']]
with_fp = sum(1 for r in rows if r['fingerprints'] > 0)
summary = {'compared': len(rows), 'differing': len(diff), 'with_lifetime_fingerprints': with_fp,
           'fingerprint_lines': sum(r['fingerprints'] for r in rows)}
(out / 'report.json').write_text(json.dumps({'summary': summary, 'differing': diff}, indent=1))
print(json.dumps(summary))
