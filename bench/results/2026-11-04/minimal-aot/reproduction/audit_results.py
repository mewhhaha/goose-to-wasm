#!/usr/bin/env python3
"""Audit retained result semantics; no builds, engines, imports from the project, or writes."""
import sys
sys.dont_write_bytecode = True
import argparse
import collections
from datetime import datetime
import gzip
import hashlib
import itertools
import json
import math
from pathlib import Path
import random
import statistics
import tarfile

COMPILER = '8c09c1a6bcc782de5b86dda621a91ae234acba8fbe108d146582113eb6a110b6'
FULL = '9c387aac2f4057e007f50cf421a7c7895c4c9a02b9496ca2fb45cd1291b27bf8'
MINIMAL = 'b3460d7f5dbae2abe3177fddcce4cfbdffa428824e723c65d00bfa8bffd2498e'
NAMES = {'squares','tour','functions','errors','sieve','sorting','sudoku','maze','vm','life'}

def need(ok, message):
    if not ok: raise ValueError(message)

def sha(data): return hashlib.sha256(data).hexdigest()
def near(a,b): need(math.isfinite(a) and math.isclose(a,b,rel_tol=1e-12,abs_tol=1e-15),f'numeric mismatch: {a} != {b}')
def summary(record, values):
    need(record['n']==len(values),'summary count')
    need(all(math.isfinite(x) and x>0 for x in values),'invalid duration or ratio')
    median=statistics.median(values)
    near(record['median'],median)
    near(record['mad'],statistics.median(abs(x-median) for x in values))
    if 'samples' in record:
        need(len(record['samples'])==len(values),'sample vector length')
        for a,b in zip(record['samples'],values): near(a,b)

def exact(rows, keys, expected):
    found={tuple(r[k] for k in keys):r for r in rows}
    need(len(found)==len(rows) and set(found)==expected,'duplicate/missing/extra matrix rows: '+str(keys))
    return found

def audit(out):
    out=out.resolve()
    index=json.loads(gzip.decompress((out/'archives.json.gz').read_bytes()))
    reports={name:json.loads((out/name).read_bytes()) for name in index['reports']}
    for name,loc in index['reports'].items():need(sha((out/name).read_bytes())==loc['sha256'],'public report binding '+name)
    need(index['identity_only']=={},'this release promises zero omissions')
    q=reports['qualification.json'];p=reports['functions-paired.json'];s=reports['selection.json']
    h=reports['host.json'];e=reports['examples.json'];l=reports['lifecycle.json'];d=reports['delivery-execution.json']
    needed={loc['sha256'] for loc in index['documents'].values()}
    needed.update(loc['sha256'] for loc in index['public_bindings'].values())
    old=q['reused_compiler'];needed.add(old['report_sha256'])
    derivation_path=old['derived_reference_report']
    derived_locations=[v for k,v in index['inputs'].items() if k.rpartition('@')[0]==derivation_path]
    need(len(derived_locations)==1,'derived report identity ambiguous');needed.add(derived_locations[0]['sha256'])
    needed.add(q['unsupported_attempt']['report_sha256'])
    need(q['fresh_gates']['sha256'] in needed,'fresh gate report is not declared')
    by_sha={v['sha256']:v for v in index['inputs'].values()}
    needed.update(by_sha[x]['sha256'] for x in needed)
    payloads={};archive_requests=collections.defaultdict(dict)
    for identity in needed:
        loc=by_sha[identity];archive_requests[loc['archive']][loc['member']]=identity
    for name, requests in archive_requests.items():
        with tarfile.open(out/name,'r:gz') as archive:
            for member in archive:
                if member.name not in requests:continue
                need(member.isfile(),'nonregular semantic input')
                data=archive.extractfile(member).read();identity=requests[member.name]
                need(sha(data)==identity,'semantic payload identity '+member.name);payloads[identity]=data
    need(set(payloads)==needed,'semantic payload missing')
    def doc(identity):return json.loads(payloads[identity])
    def binding(path):return payloads[index['public_bindings'][path]['sha256']]
    def pin(path,identity):need(path+'@'+identity in index['inputs'],'unretained pin '+path)
    for r in reports.values():need(r.get('status') in {'pass','passed'},'nonpassing primary report')
    original=doc(old['report_sha256']);derived=doc(derived_locations[0]['sha256'])
    der=derived['reference_derivation'];oldpins=original['qualification_execution']['input_sha256']
    need(len(oldpins)==1487 and len(der['input_aliases'])==13,'prior input/alias count')
    expected={der['input_aliases'].get(k,k):v for k,v in oldpins.items()}
    need(len(expected)==1487 and derived['qualification_execution']['input_sha256']==expected,'alias mapping')
    restored=dict(derived);restored.pop('reference_derivation');restored['qualification_execution']={**derived['qualification_execution'],'input_sha256':oldpins}
    need(restored==original,'alias view changes historical rows')
    need(der['original_report_sha256']==old['report_sha256'] and old['compiler_sha256']==COMPILER,'prior reference identity')
    need(original['observations']==len(original['results'])==9573 and original['cases']==978 and original['failures']==0,'prior matrix counts')
    need(sum(r.get('kind')=='compile-refusal' for r in original['results'])==3,'prior refusals')
    need(all(r['status']=='pass' for r in original['results']),'prior row failure')
    # Prior rows are historical references. Verify their native bytes through
    # bounded physical member metadata, without importing any old alias map.
    prior_guests={r['sha256'] for r in original['results'] if 'sha256' in r}
    missing=prior_guests-set(by_sha)
    need(missing=={r['sha256'] for r in original['results'] if r.get('sha256') in missing and r['backend']=='native'},'unexpected missing historical Wasm')
    prior=out/'../leaf-and-loads';prior_raw=(prior/'archives.json.gz').read_bytes()
    need(sha(prior_raw)==index['reuse']['index_sha256'],'prior physical index identity')
    physical=json.loads(gzip.decompress(prior_raw))['archives']
    need(set(physical)==set(index['reuse']['archive_allowlist']),'prior physical allowlist')
    native_members=collections.defaultdict(dict)
    for archive,record in physical.items():
        for member,identity in record['members'].items():
            if identity['sha256'] in missing:native_members[archive][member]=identity
    checked=set()
    for archive,members in native_members.items():
        need('../leaf-and-loads/'+archive in index['archives'],'historical guest needs undeclared physical archive')
        with tarfile.open(prior/archive,'r:gz') as stream:
            for member in stream:
                if member.name not in members:continue
                member_identity=members[member.name]
                need(member.isfile() and member.size==member_identity['bytes'],'historical native member extent')
                with stream.extractfile(member) as data:identity=hashlib.file_digest(data,'sha256').hexdigest()
                need(identity==member_identity['sha256'],'historical native payload identity');checked.add(identity)
    need(checked==missing,'historical native payload coverage')
    for path,identity in expected.items():pin(path,identity)
    gate=doc(q['fresh_gates']['sha256']);need(gate['input_sha256']==gate['input_sha256_after'],'gate pins')
    gate_counts={'process':13,'native':12,'aot':16,'session':9,'langarena':16,'runtime-reference':12}
    need({r['name']:r['observed_tests'] for r in gate['commands']}==gate_counts,'fresh gate coverage')
    need(sum(gate_counts.values())==78 and all(r['exit_status']==0 and r['coverage_exact'] for r in gate['commands']),'fresh gates not passing')
    reference={(r['case'],r['optimization'],r['debug'],r['backend'],r['engine']):r for r in original['results'] if r.get('kind')!='compile-refusal'}
    for label,count,backends,modes in [('host',11484,{'direct','c-wasm'},{'wasm','wasm-no-parallel','precompiled-no-parallel'}),('minimal',1914,{'direct'},{'precompiled-minimal'})]:
        top=q[label];r=doc(top['report_sha256'])
        need(r['status']=='pass' and r['coverage_exact'] and top['observations']==count and len(r['results'])==count,'fresh replay count/status')
        need(r['input_sha256']==r['input_sha256_after'] and r['aot_sha256']==r['aot_sha256_after'],'replay input/artifact drift')
        expected={(a,b,c,backend,mode) for a,b,c,backend,engine in reference if backend in backends and engine=='wasmtime' for mode in modes}
        rows=exact(r['results'],['case','optimization','debug','backend','mode'],expected)
        for key,row in rows.items():
            prior=reference[key[:4]+('wasmtime',)]
            need(row['status']=='pass' and all(row['comparisons'].values()),'fresh replay failed comparison')
            need(row['stdout']==prior['stdout'] and row['exit_code']==prior['exit_code'],'fresh replay output differs')
        for path,identity in r['input_sha256'].items():pin(path,identity)
        need(r['compiler_sha256']==COMPILER and r['host_build']['host_sha256']==FULL,'replay compiler/full host')
        if label=='minimal':need(r['aot_host_build']['host_sha256']==MINIMAL,'minimal host identity')
    rejected=q['unsupported_attempt'];raw=doc(rejected['report_sha256'])
    need(rejected['status']=='not-qualified' and rejected['requested_units']==3828 and rejected['runtime_observations']==0 and rejected['producer_exit_status']==1,'EH attempt misclassified')
    need(len(raw['results'])==0 and raw.get('status')!='pass','incomplete attempt contains primary results')
    need(rejected['collected_refusals']==99 and rejected['collected_preparations_before_environment_abort']==600,'incomplete attempt recorded scope')
    goldens={}
    for row in e['observations']:
        need(row['status']=='passed','example row failed')
        if row['kind']=='execution':goldens.setdefault(row['name'],row['stdout_sha256']);need(goldens[row['name']]==row['stdout_sha256'],'example output drift')
    need(set(goldens)==NAMES,'example names')
    builds=[r for r in e['observations'] if r['kind']=='build'];runs=[r for r in e['observations'] if r['kind']=='execution']
    exact(builds,['name','backend','sample'],set(itertools.product(NAMES,['direct','c-wasm','native'],range(5))))
    ecells={(n,b,g) for n in NAMES for b in ['direct','c-wasm'] for g in ['v8','wasmtime']}|{(n,'native','native') for n in NAMES}
    expected={(*cell,phase,i) for cell in ecells for phase,count in [('warmup',1),('measure',15)] for i in range(count)}
    expected.update((*cell,'measure-engine',i) for cell in ecells if cell[1]!='native' for i in range(15))
    exact([r for r in runs if r['phase']!='qualification'],['name','backend','engine','phase','sample'],expected)
    exact([r for r in runs if r['phase']=='qualification'],['name','backend','engine'],ecells)
    for r in e['compile_summary']:summary(r['wall_seconds'],[x['wall_seconds'] for x in builds if (x['name'],x['backend'])==(r['name'],r['backend'])])
    for r in e['runtime_summary']:
        summary(r['process_wall_seconds'],[x['process_wall_seconds'] for x in runs if (x['name'],x['backend'],x['engine'])==(r['name'],r['backend'],r['engine']) and x['phase']=='measure'])
    cells={(n,b,m) for n in NAMES for b in ['direct','c-wasm'] for m in ['python','native','native-serial','precompiled','precompiled-minimal']}|{(n,'native','native-C') for n in NAMES}
    exact(h['observations'],['name','backend','mode','phase','sample'],{(*c,p,i) for c in cells for p,n in [('measure',15),('warmup',1)] for i in range(n)})
    need(len(h['runtime_summary'])==110 and len(h['preparation_summary'])==60,'host summary cells')
    for r in h['observations']:need(r['exit_code']==0 and r['stdout_sha256']==goldens[r['name']],'host golden/exit')
    for r in h['runtime_summary']:summary(r['wall_seconds'],[x['wall_seconds'] for x in h['observations'] if (x['name'],x['backend'],x['mode'])==(r['name'],r['backend'],r['mode']) and x['phase']=='measure'])
    exact(h['preparation'],['name','backend','configuration','sample'],set(itertools.product(NAMES,['direct','c-wasm'],['parallel','serial','minimal'],range(5))))
    for r in h['preparation_summary']:summary(r['wall_seconds'],[x['wall_seconds'] for x in h['preparation'] if (x['name'],x['backend'],x['configuration'])==(r['name'],r['backend'],r['configuration'])])
    need({(r['name'],r['backend'],r['configuration'],r['sha256']) for r in h['preparation']}=={(r['name'],r['backend'],r['configuration'],r['sha256']) for r in h['artifact_qualification']},'AOT qualification inventory')
    need(all(r['status']=='passed' for r in h['artifact_qualification']),'AOT qualification failed')
    need(h['host_build']['host_sha256']==FULL and h['aot_host_build']['host_sha256']==MINIMAL,'broad hosts')
    lc=collections.Counter((r['name'],r['mode'],r['phase']) for r in l['observations'])
    need(set(lc)==set(itertools.product(NAMES,['ordinary','cache-miss','cache-hit','precompiled','native-C','worker-hit'],['warmup','measure'])),'lifecycle matrix')
    for k,v in lc.items():need(v=={'warmup':1,'measure':15}[k[-1]],'lifecycle sample count')
    for r in l['observations']:need(r['returncode']==0 and r['stderr']=='' and sha(r['stdout'].encode())==goldens[r['name']],'lifecycle output')
    exact(p['observations'],['affinity','workload','variant','phase','sample'],{(a,w,v,phase,i) for a in ['pool','cpu2'] for w in ['functions','squares'] for v in ['default','default_aa','subset_full','subset_min','native'] for phase,n in [('warmup',2),('measure',61)] for i in range(n)})
    need(p['input_sha256']==p['input_sha256_after'],'paired pins')
    need(p['host_builds']['default']['host_sha256']==p['host_builds']['default_aa']['host_sha256']=='e303865d7661dc5d0dad1e1719753d1101bfe7f7e16d5b1eb2e174f416fbbf28','paired baseline/A-A host identity')
    need(p['host_builds']['subset_full']['host_sha256']==FULL and p['host_builds']['subset_min']['host_sha256']==MINIMAL,'paired product host identity')
    for workload,variants in p['cells'].items():
        artifacts=p['artifacts'][workload]
        for variant,command in variants.items():
            expected=p['input_sha256'][artifacts['native']]
            if variant!='native':expected=p['host_builds'][variant]['host_sha256']
            pin(command[0],expected)
            if variant!='native':
                artifact=artifacts['default_aot']
                if variant in {'subset_full','subset_min'}:artifact=artifacts['subset_aot']
                pin(command[-1],p['input_sha256'][artifact])
        matches={r['artifact_sha256'] for r in builds if r['name']==workload and r['backend']=='direct'}
        need(matches=={p['input_sha256'][artifacts['wasm']]},'paired/broad guest identity')
    for path,identity in p['input_sha256'].items():pin(path,identity)
    need(set(l['worker_lifecycle'])==NAMES,'resident worker inventory')
    for name,worker in l['worker_lifecycle'].items():
        need(worker['first_returncode']==0 and not worker['first_cache_hit'] and worker['resident_process_count']==1 and worker['first_stderr']=='' and sha(worker['first_stdout'].encode())==goldens[name],'fresh worker initialization')
    for path,record in l['final_cache_file_manifest'].items():
        pin(path,record['sha256'])
        need(index['inputs'][path+'@'+record['sha256']]['bytes']==record['bytes'],'cache byte extent')
    for r in p['observations']:need(r['returncode']==0 and r['stderr']=='' and sha(r['stdout'].encode())==goldens[r['workload']] and r['command']==p['cells'][r['workload']][r['variant']],'paired outputs/commands')
    rng=random.Random(20261104);intervals=0
    for key,g in p['summary'].items():
        a,w=key.split('/');values={v:[r['wall_ns'] for r in sorted(p['observations'],key=lambda x:x['sample']) if r['affinity']==a and r['workload']==w and r['variant']==v and r['phase']=='measure'] for v in p['cells'][w]}
        for v,ns in values.items():summary(g['wall_us'][v],[x/1000 for x in ns]);summary(s['summary'][key]['wall_us'][v],[x/1000 for x in ns])
        for name,item in g['paired_ratios'].items():
            x,y=name.split('_over_');summary(item,[u/v for u,v in zip(values[x],values[y])])
        for name in ['default_aa_over_default','subset_full_over_default','subset_min_over_default','subset_min_over_native','subset_min_over_subset_full']:
            x,y=name.split('_over_');ratios=[u/v for u,v in zip(values[x],values[y])];summary(s['summary'][key]['ratios'][name],ratios)
            boots=sorted(statistics.median(rng.choices(ratios,k=61)) for _ in range(10000))
            for actual,recorded in zip([boots[249],boots[9749]],s['summary'][key]['ratios'][name]['median_ci95']):near(actual,recorded)
            intervals+=1
    need(s['report_sha256']==sha((out/'functions-paired.json').read_bytes()),'selection report link')
    need(d['compiler_sha256']==COMPILER and d['input_sha256']==d['input_sha256_after'],'delivery pins')
    need([x['name'] for x in d['phases']]==['examples','host','lifecycle','paired'],'delivery phase inventory')
    previous=datetime.fromisoformat(d['started_utc'])
    mapping={'examples':'examples.json','host':'host.json','lifecycle':'lifecycle.json','paired':'functions-paired.json'}
    for r in d['phases']:
        start=datetime.fromisoformat(r['started_utc']);finish=datetime.fromisoformat(r['finished_utc'])
        need(previous<=start<=finish and r['exit_status']==0,'phase order/exit')
        need(r['report_sha256']==sha((out/mapping[r['name']]).read_bytes()),'phase report SHA')
        need(r['observations']==len(reports[mapping[r['name']]]['observations']),'phase row count');previous=finish
    need(previous<=datetime.fromisoformat(d['finished_utc']),'delivery finish order')
    for path,identity in d['input_sha256'].items():pin(path,identity)
    for name in ['bench/results/examples-latest.json','bench/results/wasmtime-host-latest.json','bench/results/runtime-lifecycle-latest.json']:
        pointer=json.loads(binding(name));need('minimal-aot' in json.dumps(pointer),'current pointer target')
    need('leaf-and-loads' in binding('bench/results/latest.json').decode(),'historical LangArena pointer scope')
    need('leaf-and-loads' in binding('bench/results/runtime-targets-latest.json').decode(),'historical kernel pointer scope')
    med={(r['name'],r['backend'],r['mode']):r['wall_seconds']['median']*1000 for r in h['runtime_summary']}
    table_rows=0
    for document in [binding('bench/wasmtime-host.md').decode(),(out/'README.md').read_text()]:
        for line in document.splitlines():
            cells=[x.strip() for x in line.strip().strip('|').split('|')]
            if len(cells)!=5 or cells[0].lower() not in NAMES:continue
            n=cells[0].lower();keys=[(n,'direct','native'),(n,'direct','precompiled'),(n,'direct','precompiled-minimal'),(n,'native','native-C')]
            need(cells[1:]==[f'{med[k]:.3f}' for k in keys],'rounded published table '+n);table_rows+=1
    need(table_rows==14,'published table coverage')
    return {'status':'passed','compiler_sha256':COMPILER,'full_host_sha256':FULL,'minimal_host_sha256':MINIMAL,'prior_compiler_observations':9573,'historical_native_payloads_verified':len(checked),'prior_input_pins':1487,'prior_input_aliases':13,'fresh_unit_checks':78,'fresh_full_host_observations':11484,'fresh_minimal_direct_observations':1914,'unqualified_all_backend_attempt_primary_rows':0,'examples_rows':1600,'host_rows':1760,'host_preparation_rows':300,'host_runtime_cells':110,'host_preparation_cells':60,'lifecycle_rows':960,'paired_rows':1260,'paired_rounds_per_cell':61,'bootstrap_intervals_recomputed':intervals,'rounded_table_rows':table_rows,'delivery_phases':4,'semantic_payload_objects':len(payloads),'retained_lifecycle_cache_files':len(l['final_cache_file_manifest']),'identity_only':0,'limits':['Compiler/native/V8/Python differential rows are verified historical evidence, not rerun.','Minimal full-corpus support is direct only; the selected ten C-to-Wasm examples are independently qualified.','61-round paired and 15-sample broad cohorts remain separate.','Byte inventory, all archive members, nested raw logs and other retained artifacts are checked by verify.py.','Chart layout is reviewed visually outside this arithmetic checker.']}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('publication',type=Path,nargs='?',default=Path(__file__).resolve().parent.parent)
    args=parser.parse_args()
    print(json.dumps(audit(args.publication),indent=2,sort_keys=True))
