#!/usr/bin/env python3
"""xcorpus.py COMPILER OUTDIR [--jobs N]: run a cross-check build (xcheck.py)
with --check over every unique conformance source; count LIFEXCHECK lines."""
import argparse, json, subprocess, sys, tarfile, shutil, collections
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT = Path(__file__).resolve().parents[2]
ap = argparse.ArgumentParser(); ap.add_argument('compiler'); ap.add_argument('out'); ap.add_argument('--jobs', type=int, default=4)
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
    if name in sources: continue
    sources[name] = (upstream / name[len('upstream:'):], upstream, upstream / 'stdlib') if name.startswith('upstream:') else (ROOT / name, ROOT, ROOT / 'stdlib')
def run(name):
    path, cwd, lib = sources[name]
    r = subprocess.run([args.compiler, str(path), '--target', 'native', '--check', '--stdlib', str(lib)], cwd=cwd, capture_output=True, timeout=600)
    lines = [l for l in r.stderr.decode(errors='replace').splitlines() if l.startswith("LIFEPATHS")]
    return name, lines
names = ['mixed_kinds_lookups','deep_cells','frame0_reach_calls','lexical_is_target','settled_walks','settled_validation_walks','replay_skips','offers_with_recursive_place','readback_hits','contents_hits','load_hits','byte_view_holders']; totals = [0]*12; used = [0]*12; differ = []; reached = 0
with ThreadPoolExecutor(args.jobs) as pool:
    for name, lines in pool.map(run, sorted(sources)):
        for l in lines:
            if 'differ' in l: differ.append((name, l))
            elif l.startswith('LIFEPATHS'):
                reached += 1
                for i, v in enumerate(l.split()[1:13]):
                    totals[i] += int(v); used[i] += int(v) > 0
summary = {'sources': len(sources), 'reached_the_pass': reached, 'paths': {n: {'events': totals[i], 'sources': used[i]} for i, n in enumerate(names)}}
(out / 'paths.json').write_text(json.dumps({'summary': summary, 'differing': differ}, indent=1))
print(json.dumps(summary))
