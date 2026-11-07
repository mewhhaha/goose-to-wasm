from pathlib import Path
import hashlib,json,subprocess
root=Path('/home/jacobt/src/goose-to-wasm');w=root/'build/completion-runs'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text())
assert not subprocess.check_output(['git','diff','--cached','--name-only'],cwd=root).strip()
proof=read(w/'c-only-bootstrap-47/report.json');summary=read(root/'selfhost/results/2026-11-07/pending-elements-and-payloads/summary.json')
assert summary['existing_contract_regressions']==summary['new_contract_failures']==0
plan={}
for row in read(w/'delivery-47.json').get('documentation', []):
 p=root/row['path'];assert sha(p)==row['sha256'];plan[row['path']]=p
for name,value in proof['source_sha256'].items():
 p=w/'snapshot-47/selfhost'/name;assert sha(p)==value;plan['selfhost/'+name]=p
for name,value in proof['asset_sha256'].items():
 p=w/'snapshot-47'/name;assert sha(p)==value;plan[name]=p
for name in ('native/tests/check.py', 'native/tests/var_relative.c', 'native/tests/bounded_cells.c'): plan[name]=w/'snapshot-47'/name
for name in ('proof.json','seed.c.gz','seed.json','sources.tar.gz'):plan['bootstrap/'+name]=w/'verified-seed-47'/name
for name in ('README.md','selfhost/README.md','bench/README.md','tests/conformance/cases.json','bench/results/examples-latest.json','bench/results/wasmtime-host-latest.json','bench/charts/goose-examples-compilation.svg','bench/charts/goose-examples-runtime.svg','bench/charts/goose-host-preparation.svg'):plan[name]=root/name
for name,value in read(w/'new-controls-47.json')['sources'].items():
 p=root/name;assert sha(p)==value;plan[name]=p
for folder in ('bench/results/2026-11-07/pending-elements-and-payloads','selfhost/results/2026-11-07/pending-elements-and-payloads'):
 for p in (root/folder).rglob('*'):
  if p.is_file():plan[p.relative_to(root).as_posix()]=p
backup=w/'live-before-47';backup.mkdir(exist_ok=True);changes=[];rows=[]
for name,source in sorted(plan.items()):
 data=source.read_bytes();live=root/name
 if name.startswith(('selfhost/','native/','bootstrap/')) and not live.exists():
  changes.append(dict(path=name,sha256=None))
 if name.startswith(('selfhost/','native/','bootstrap/')) and live.is_file() and live.read_bytes()!=data:
  dst=backup/name;dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes(live.read_bytes());changes.append(dict(path=name,sha256=sha(live)))
 blob=subprocess.check_output(['git','hash-object','-w','--stdin'],cwd=root,input=data).decode().strip()
 subprocess.run(['git','update-index','--add','--cacheinfo','100644,'+blob+','+name],cwd=root,check=True)
 staged=subprocess.check_output(['git','show',':'+name],cwd=root);assert staged==data,name
 rows.append(dict(path=name,source=str(source),git_blob=blob,sha256=hashlib.sha256(data).hexdigest()))
for name,key in [('examples-latest.json','examples.json'),('wasmtime-host-latest.json','host.json')]:
 p=read(root/'bench/results'/name);assert p['sha256']==sha(root/'bench/results'/p['report'])
# Preserve exact qualified contract bytes; this input contains a whitespace-only line.
subprocess.run(['git','diff','--cached','--check','--','.',':(exclude)tests/fixtures/contracts/pending-and-call-contracts/pending_owned_wrappers.goose'],cwd=root,check=True)
(w/'stage-plan-47.json').write_text(json.dumps(dict(status='passed',files=rows,live_before=changes),indent=2)+'\n')
print('stagedandverified',len(rows),'plannedpaths; livebackups',len(changes))
