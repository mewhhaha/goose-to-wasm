#!/usr/bin/env python3
"""diagcompare.py A B OUTDIR: run two (fingerprinting) compilers with --check over every conformance source and
compare exit status, stdout and stderr without the state lines. Prints the sources that differ."""
import json, hashlib, subprocess, sys, tarfile, shutil
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
def _root():
    here = Path(__file__).resolve()
    for up in here.parents:
        if (up / 'tests/conformance/cases.json').exists(): return up
    raise SystemExit('run from inside the repository')
ROOT = _root()
a, b, out = str(Path(sys.argv[1]).resolve()), str(Path(sys.argv[2]).resolve()), Path(sys.argv[3]).resolve()
manifest = json.loads((ROOT / 'tests/conformance/cases.json').read_text()); up = out / 'upstream'
assert up.exists(), 'run fpcompare.py with this OUTDIR first (it unpacks the upstream sources)'
names = sorted({c['source'] for c in manifest['cases']})
def run(exe, name):
    if name.startswith('upstream:'): path, cwd, lib = up / name[9:], up, up / 'stdlib'
    else: path, cwd, lib = ROOT / name, ROOT, ROOT / 'stdlib'
    r = subprocess.run([exe, str(path), '--target', 'native', '--check', '--stdlib', str(lib)], cwd=cwd, capture_output=True, timeout=600)
    rest = '\n'.join(l for l in r.stderr.decode(errors='replace').splitlines() if not l.startswith('LIFEFP'))
    return r.returncode, r.stdout.decode(errors='replace'), rest
def one(name): return name, run(a, name), run(b, name)
diff = []
with ThreadPoolExecutor(int(sys.argv[4]) if len(sys.argv) > 4 else 2) as pool:
    for name, x, y in pool.map(one, names):
        if x != y: diff.append({'source': name, 'a': x, 'b': y}); print('DIFFERS', name, x[0], y[0], flush=True)
print(json.dumps({'compared': len(names), 'differing': len(diff)}))
(out / 'diag-report.json').write_text(json.dumps(diff, indent=1))
