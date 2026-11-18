"""Run the native counts.patch probe over each distinct conformance source."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess
import resource

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('repo',type=Path); p.add_argument('probe',type=Path); p.add_argument('upstream',type=Path)
p.add_argument('stdlib',type=Path); p.add_argument('output',type=Path); p.add_argument('--workers',type=int,default=2)
a=p.parse_args()
soft,hard=resource.getrlimit(resource.RLIMIT_STACK)
resource.setrlimit(resource.RLIMIT_STACK,(256 << 20,hard))
repo=a.repo.resolve(); probe=a.probe.resolve(); stdlib=a.stdlib.resolve(); upstream=a.upstream.resolve()
def sha(path):
    with path.open('rb') as stream: return hashlib.file_digest(stream,'sha256').hexdigest()
manifest=repo/'tests/conformance/cases.json'
suite=json.loads(manifest.read_text())
assert sha(repo/suite['upstream']['archive'])==suite['upstream']['sha256']
names=sorted(set(v['source'] for v in suite['cases']))
def inspect(name):
    if name.startswith('upstream:'): path=upstream/name.removeprefix('upstream:'); cwd=upstream; lib=upstream/'stdlib'
    else: path=repo/name; cwd=repo; lib=stdlib
    run=subprocess.run([probe,path,'--target','native','--check','--stdlib',lib],cwd=cwd,capture_output=True,timeout=300)
    if b"native call stack overflow" in run.stderr: raise RuntimeError(name)
    if run.returncode not in (0,1): raise ValueError((name,run.returncode,run.stderr))
    observed=[json.loads(line.removeprefix(b'REPLAY ')) for line in run.stdout.splitlines() if line.startswith(b'REPLAY ')]
    assert len(observed)<=1
    sums=[0]*7
    if observed:
        v=observed[0]
        sums=[v[0],v[4],v[6],v[46],v[7]-v[10],v[8],v[47]]
    return dict(name=name,status=run.returncode,has_counts=bool(observed),source_sha256=sha(path),values=sums)
with ThreadPoolExecutor(a.workers) as pool:
    rows=list(pool.map(inspect,names))
counts=['calls','compact_entries','already_stamped','repeated_leaf','direct_place_offers','adjacent_equal_places','places_seen_in_same_replay']
summary=dict(distinct_sources=len(rows),with_final_counts=sum(r['has_counts'] for r in rows),with_compact_entries=sum(r['values'][1]>0 for r in rows),with_direct_offers=sum(r['values'][4]>0 for r in rows),status_ok=sum(r['status']==0 for r in rows),probe_sha256=sha(probe),manifest_sha256=sha(manifest),upstream_archive_sha256=suite['upstream']['sha256'],counts=dict(zip(counts,map(sum,zip(*(r['values'] for r in rows))))))
print(json.dumps(summary),flush=True)
output=dict(summary=summary,fields=counts,rows=rows)
a.output.write_text(json.dumps(output,separators=(',',':'))+'\n')
