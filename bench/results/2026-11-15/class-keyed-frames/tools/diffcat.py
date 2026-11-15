#!/usr/bin/env python3
"""diffcat.py REPORT_DIR BASE CAND: for the sources fpcompare found differing,
rerun both compilers and group by how the diagnostics differ."""
import json, subprocess, sys, collections
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
out, base, cand = sys.argv[1], sys.argv[2], sys.argv[3]
report = json.load(open(out + '/report.json'))
upstream = Path(out) / 'upstream'
def run(compiler, name):
    if name.startswith('upstream:'): path, cwd, lib = upstream / name[9:], upstream, upstream / 'stdlib'
    else: path, cwd, lib = ROOT / name, ROOT, ROOT / 'stdlib'
    r = subprocess.run([compiler, str(path), '--target', 'native', '--check', '--stdlib', str(lib)], cwd=cwd, capture_output=True, timeout=600)
    return r.returncode, [l for l in r.stderr.decode(errors='replace').splitlines() if 'error' in l]
groups = collections.defaultdict(list)
for row in report['differing']:
    name = row['source']; b = run(base, name); c = run(cand, name)
    if b[0] == 0 and c[0] != 0: kind = 'accept->reject'
    elif b[0] != 0 and c[0] == 0: kind = 'reject->accept'
    elif b[0] != 0 and c[0] != 0:
        bm = sorted(set(l.split('error: ')[-1] for l in b[1])); cm = sorted(set(l.split('error: ')[-1] for l in c[1]))
        kind = 'same messages, other places' if bm == cm else 'other messages'
    else: kind = 'both accept, other output'
    groups[kind].append((name, b[1], c[1]))
json.dump({k: v for k, v in groups.items()}, open(out + '/categories.json', 'w'), indent=1)
for k, v in groups.items(): print(k, len(v))
