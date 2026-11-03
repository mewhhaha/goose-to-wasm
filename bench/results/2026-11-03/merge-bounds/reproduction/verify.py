#!/usr/bin/env python3
"""Verify current evidence and bounded immediate-prior byte objects; run no guests."""
from pathlib import Path
import argparse
import gzip
import hashlib
import json
import math
import statistics
import tarfile
import struct
import tomllib
import sys

sys.dont_write_bytecode=True

from bundle import fingerprints
from checks import digest, exact, guest_identities, load, require, safe_member, validate_current, validate_lifecycle


def archive_path(out,spec,name,record):
    if record.get('external'):
        allowed=set(spec['reuse']['archives'].values())
        expected={f'../runtime-stencil/evidence-{n:03}.tar.gz' for n in range(2)}
        expected.update(f'../fresh-construction/evidence-{n:03}.tar.gz' for n in range(2))
        expected.update(f'../functions-calls/evidence-{n:03}.tar.gz' for n in range(4))
        expected.update(f'../functions-forwarding/evidence-{n:03}.tar.gz' for n in range(8))
        require(allowed==expected and name in allowed,'archive is not one of sixteen bounded prior files')
        directory=Path(name).parent
        path=(out/name).resolve()
        require(path.parent==(out/directory).resolve(),'prior archive escapes bounded directory')
        return path
    safe_member(name)
    require(Path(name).parent==Path('.'),'new archive must be local')
    return out/name


def validate_worker(value,index,payloads,by_path,reports):
    require(value['schema']=='goose-fresh-store-worker-replay-v1' and value['status']=='passed' and
            value['coverage_exact'] and value['failures']==0,'worker replay failed')
    require(value['observations']==len(value['results'])==value['derived_effective_cases'] and value['underlying_aliases']==3828,'worker replay counts differ')
    require(value['input_sha256']==value['input_sha256_after'],'worker input pins changed')
    require(value['host_build']==reports['host-qualification.json']['host_build'] and
            value['compiler_sha256']==reports['differential.json']['compiler_sha256'],'worker identities differ')
    require(value['configuration']['processes']==1 and not value['configuration']['disk_compilation_cache'] and
            value['configuration']['fresh_store_and_instance_per_request'],'worker isolation configuration differs')
    require(value['worker_command'][-2:]==['--serve','--no-cache'] and
            payloads[value['handshake_sha256']]==b'GWRT\1\0\0\0','worker protocol/command differs')
    case_docs=[location for origin,location in index['documents'].items() if origin.endswith('/worker-case-inputs.json')]
    require(len(case_docs)==1,'worker case-input derivation missing')
    source=json.loads(payloads[case_docs[0]['sha256']]);cases={case['name']:case for case in source['cases']}
    canonical=(json.dumps(source['cases'],sort_keys=True,indent=2)+'\n').encode()
    require(hashlib.sha256(canonical).hexdigest()==source['case_inputs_sha256']==
            reports['host-qualification.json']['case_inputs_sha256'],'worker case-input corpus differs')
    diff=[row for row in reports['differential.json']['results'] if row.get('kind')!='compile-refusal']
    native={(row['case'],row['optimization'],row['debug']):row for row in diff if row['backend']=='native'}
    python={(row['case'],row['optimization'],row['debug'],row['backend']):row for row in diff
            if row['backend'] in {'direct','c-wasm'} and row['engine']=='wasmtime'}
    expected={(row['sha256'],hashlib.sha256(cases[row['case']]['stdin'].encode()).hexdigest()) for row in python.values()}
    aliases=set();actual=set();seen=set()
    header=struct.Struct('<IIQQQQ')
    for row in value['results']:
        require(row['status']=='pass' and all(row['comparisons'].values()),'worker comparison failed')
        key=(row['wasm_sha256'],row['stdin_sha256']);require(key not in actual,'duplicate effective worker input');actual.add(key)
        request=payloads[row['request_sha256']];response=payloads[row['response_sha256']]
        require(len(request)>=8 and len(response)>=header.size,'truncated worker wire evidence')
        path_size,input_size=struct.unpack_from('<II',request)
        require(len(request)==8+path_size+input_size and request[8:8+path_size]==row['module'].encode(),'worker request framing differs')
        stdin=request[8+path_size:];require(hashlib.sha256(stdin).hexdigest()==row['stdin_sha256'],'worker request stdin differs')
        flags,code,out_size,err_size,prepare,start=header.unpack_from(response)
        require(flags in (0,1) and len(response)==header.size+out_size+err_size,'worker response framing differs')
        stdout=response[header.size:header.size+out_size];stderr=response[header.size+out_size:]
        require(stdout==payloads[row['stdout_sha256']] and stderr==payloads[row['stderr_sha256']] and code==row['exit_code'] and
                prepare==row['prepare_ns'] and start==row['start_ns'],'worker raw result differs')
        require(bool(flags)==row['module_cache_hit']==(row['wasm_sha256'] in seen),'worker module reuse progression differs')
        seen.add(row['wasm_sha256'])
        for alias in row['aliases']:
            alias_key=(alias['case'],alias['optimization'],alias['debug'],alias['backend'])
            require(alias_key not in aliases and alias_key in python,'worker alias missing/duplicate');aliases.add(alias_key)
            reference=python[alias_key];oracle=native[alias_key[:3]];case=cases[alias['case']]
            require(reference['sha256']==row['wasm_sha256'] and stdin==case['stdin'].encode(),'worker alias guest/input differs')
            require(code==reference['exit_code']==oracle['exit_code'] and stdout==reference['stdout'].encode()==oracle['stdout'].encode(),
                    'worker/native/Python output differs')
            if not reference['stderr']:require(not stderr,'unexpected worker stderr')
            if case['stdout'] is not None:require(stdout==case['stdout'].encode(),'worker golden differs')
            if case['diagnostic']:require(case['diagnostic'].lower() in stderr.decode(errors='replace').lower(),'worker diagnostic differs')
        for name,expected_sha in [('request.log',row['request_sha256']),('response.log',row['response_sha256']),
                                 ('stdout',row['stdout_sha256']),('stderr',row['stderr_sha256']),('stdin',row['stdin_sha256'])]:
            require(expected_sha in by_path.get(str(Path(row['logs'])/name),{}),'worker raw log edge missing')
    require(actual==expected and aliases==set(python) and len(actual)==value['derived_effective_cases'] and len(aliases)==3828,'worker exact corpus coverage differs')


def validate_tables(out,index,payloads,reports):
    proof=load(out/'table-verification.json');checks=[]
    require(proof['status']=='passed' and proof['cells_checked']==46,'documentation table proof failed')
    def table(document):
        text=payloads[index['public_bindings'][document]['sha256']].decode()
        return {cells[0]:cells[1:] for line in text.splitlines() if line.startswith('|')
                for cells in [[cell.strip() for cell in line.split('|')[1:-1]]]}
    document='docs/RUNTIME_TARGETS.md';rows=table(document)
    warmed={row['task']:row for row in reports['final-warmed.json']['summary']}
    labels={'Fannkuch':'CLBG::Fannkuchredux','Mandelbrot':'CLBG::Mandelbrot','Sieve':'Etc::Sieve',
            'CRC32':'Hash::CRC32','Custom hash':'Hash::SHA256','Merge sort':'Sort::Merge','Quicksort':'Sort::Quick',
            'Life adapter':'Example::Life','Insertion-sort adapter':'Example::Sorting','Sudoku adapter':'Example::Sudoku'}
    for label,task in labels.items():
        row=warmed[task];variants=['final',row['reference_roles']['selected_wasm'],row['reference_roles']['selected_native']]
        expected=[f"{row['times'][variant]['median']*1000:,.0f}" for variant in variants]
        require(rows[label]==expected,('runtime target table differs',task))
        checks.append({'document':document,'task':task,'cells':expected})
    document='bench/wasmtime-host.md';rows=table(document)
    host={(row['name'],row['backend'],row['mode']):row for row in reports['host.json']['runtime_summary']}
    for label,task in [('Functions','functions'),('Sorting','sorting'),('Sudoku','sudoku'),('Life','life')]:
        modes=[('direct','python'),('direct','native'),('direct','precompiled'),('native','native-C')]
        expected=[f"{host[task,backend,mode]['wall_seconds']['median']*1000:.3f} ms" for backend,mode in modes]
        require(rows[label]==expected,('host table differs',task))
        checks.append({'document':document,'task':task,'cells':expected})
    require(proof['checks']==checks,'documentation proof does not match task identities/cells')
    for name,expected in proof['inputs'].items():
        if name in index['public_bindings']:
            require(index['public_bindings'][name]['sha256']==expected,'documentation proof source differs')
        else:
            require(digest(out/Path(name).name)==expected,'documentation proof report differs')


def verify(out):
    manifest=load(out/'SHA256.json');retention=load(out/'retention.json');spec=retention['specification']
    require(retention['schema']=='goose-merge-bounds-retention-v1','retention schema')
    for name,expected in manifest.items():
        safe_member(name);require(digest(out/name)==expected,('public manifest differs',name))
    for name,expected in retention['public_file_sha256'].items():
        require(manifest[name]==expected,('retention/public manifest mismatch',name))
    require(manifest['retention.json']==digest(out/'retention.json'),'retention digest differs')
    index=load(out/retention['archive_index']);require(index['schema']=='goose-merge-bounds-objects-v1','object index schema')
    aliases=index['aliases'];omitted=index['omitted'];archives=index['archives']
    require(not set(aliases)&set(omitted),'identity both retained and omitted')
    by_path={};retained={location['sha256'] for location in aliases.values()}
    wanted={location['sha256'] for location in index['documents'].values()}
    wanted.update(location['sha256'] for location in index['public_bindings'].values())
    for original,location in aliases.items():
        path,separator,expected=original.rpartition('@');require(separator and expected==location['sha256'],'alias SHA differs')
        archive_path(out,spec,location['archive'],archives[location['archive']]);safe_member(location['member'])
        require(archives[location['archive']]['members'][location['member']]==
                {key:location[key] for key in ('sha256','bytes')},'member location differs')
        by_path.setdefault(path,{})[expected]=location
    for key,row in omitted.items():
        require(key==row['original']+'@'+row['sha256'] and row['reason'],'invalid omission')
        require(Path(row['original']).suffix not in {'.wasm','.cwasm','.bin'},'guest omitted as tool')
    require(set(index['guests'])<=retained and set(index['required_guests'])<=retained,'guest bytes unavailable')
    reports={name:load(out/name) for name in spec['reports']};reference=load(out/'references.json')
    require(digest(out/'references.json')==spec['reference_sha256'],'official reference differs')
    validate_current(reports,reference,spec['compiler_sha256'])
    validate_lifecycle(reports['lifecycle.json'],reports,spec['compiler_sha256'])
    for name in ('final-warmed.json','final-v8.json'):
        for row in reports[name]['observations']:
            path=str(Path(row['log_directory'])/'stdout.txt')
            require(path in by_path and len(by_path[path])==1,('authoritative stdout unavailable',path))
            wanted.update(by_path[path])
    for stage in index['source_stages'].values():
        wanted.add(stage['source']['sha256']);wanted.add(stage['toolchain']['sha256'])
    for control in index['controls'].values():
        wanted.add(control['toolchain']['sha256']);wanted.add(control['match']['sha256'])
    worker=load(out/'worker-qualification.json')
    wanted.add(worker['handshake_sha256'])
    for row in worker['results']:
        wanted.update(row[key] for key in ('stdout_sha256','stderr_sha256','request_sha256','response_sha256'))
    for stage in index['host_stages'].values():wanted.add(stage['metadata']['sha256'])
    wanted.update(item['sha256'] for item in index['engine_cache_files'].values() if item['kind']=='config')
    payloads={};verified={}
    for name,record in archives.items():
        path=archive_path(out,spec,name,record)
        require(path.stat().st_size==record['bytes'] and digest(path)==record['sha256'],('archive SHA differs',name))
        members={};seen=set();raw_size=10240
        with tarfile.open(path,'r:gz') as archive:
            for member in archive:
                safe_member(member.name)
                require(member.isfile() and member.name not in seen,'unsafe/duplicate archive member')
                seen.add(member.name)
                raw_size+=512+math.ceil(member.size/512)*512
                if member.name not in record['members']:
                    require(record.get('external'),'unindexed new archive member')
                    continue
                expected=record['members'][member.name]['sha256']
                with archive.extractfile(member) as stream:
                    if expected in wanted:
                        data=stream.read();actual=hashlib.sha256(data).hexdigest();payloads[actual]=data
                    else:actual=hashlib.file_digest(stream,'sha256').hexdigest()
                members[member.name]={'sha256':actual,'bytes':member.size}
        require(members==record['members'],('archive member coverage differs',name))
        require(raw_size<=spec['max_raw_archive_bytes'] and record['bytes']<100*1024*1024,'archive size bound')
        verified[name]=len(members);print('verified',name,len(members),'members',flush=True)
    require(wanted<=payloads.keys(),'required retained payload absent')
    pin_locations=[item for path,item in index['documents'].items() if path.endswith('/'+spec['build']+'/'+spec['qualified_input_pins'])]
    require(len(pin_locations)==1,'qualified input seal missing')
    pins=json.loads(payloads[pin_locations[0]['sha256']]);repo_root=Path(index['repository_root']);expected_sources={}
    for path,sha in pins.items():
        source=Path(path)
        if not source.is_relative_to(repo_root):continue
        relative=source.relative_to(repo_root)
        if relative.parts[0] not in {'compiler','host','scripts','tests','oracle','.github','bench'}:continue
        if relative.parts[:2] in {('bench','results'),('bench','charts')}:continue
        expected_sources[path]=sha
    require(index['qualified_source_bindings']==expected_sources,'qualified/final source inventory differs')
    require(all(path+'@'+sha in aliases for path,sha in expected_sources.items()),'unchanged qualified source identity missing')
    for path,item in index['engine_cache_files'].items():
        if item['kind']=='config':
            config=tomllib.loads(payloads[item['sha256']].decode())
            require(config=={'cache':{'directory':str(Path(path).parent/'entries')}},
                    'lifecycle config shares or redirects its cache directory')
    for origin,location in index['documents'].items():
        value=json.loads(payloads[location['sha256']])
        for original,expected in fingerprints(value):
            require(str(original)+'@'+expected in aliases or str(original)+'@'+expected in omitted,
                    ('current document input unresolved',origin,original,expected))
        for original,expected in guest_identities(value):
            require(expected in retained,('current measured guest missing',origin,original,expected))
            if original is not None:require(str(original)+'@'+expected in aliases,'guest path omitted')
        if origin.endswith('/'+spec['delivery_execution']):
            require(value['status']=='passed' and value['compiler_sha256']==spec['compiler_sha256'],'delivery execution failed')
            require(value['input_sha256']==value['input_sha256_after'],'delivery source pins changed')
            phases={'delivered-warmed':'final-warmed.json','delivered-v8':'final-v8.json','examples':'examples.json','host':'host.json','langarena':'cohort.json','lifecycle':'lifecycle.json'}
            require(len(value['phases'])==6 and {row['name'] for row in value['phases']}==set(phases),'six delivery phases differ')
            for row in value['phases']:
                require(row['status']=='passed' and row['exit_status']==0,'delivery phase failed')
                require(row['report_sha256']==digest(out/phases[row['name']]),'delivery report edge differs')
                require(row['stdout_sha256'] in retained and row['stderr_sha256'] in retained,'delivery output missing')
        if any(origin.endswith('/'+name) for name in spec['extra_reports'].values()):
            validate_worker(value,index,payloads,by_path,reports)
        if origin.endswith('/lifecycle-smoke-3/report.json'):
            validate_lifecycle(value,reports,spec['compiler_sha256'],smoke=True)
        if origin.endswith('/guide-validation/report.json'):
            require(value['status']=='passed' and len(value['checks'])==15 and
                    all(row['returncode']==0 for row in value['checks']),'GUIDE smoke checks failed')
            require(value['guide_sha256']==index['public_bindings']['docs/GUIDE.md']['sha256'] and
                    value['compiler_sha256']==spec['compiler_sha256'] and
                    value['host_sha256']==reports['host-qualification.json']['host_build']['host_sha256'],
                    'GUIDE source/compiler/host identity differs')
            require(value['module_sha256'] in index['guests'] and value['artifact_sha256'] in index['guests'],
                    'GUIDE Wasm/AOT guest evidence absent')
        for path,item in value.get('final_cache_file_manifest',{}).items():
            require(path in index['engine_cache_files'] and index['engine_cache_files'][path]['sha256']==item['sha256'] and
                    index['engine_cache_files'][path]['bytes']==item['bytes'] and item['sha256'] in retained,
                    'measured cache payload/counter file missing')
    for name,origin in {**spec['reports'],**spec['extra_reports']}.items():
        expected=digest(out/name)
        require(any(path.endswith('/'+spec['build']+'/'+origin) and location['sha256']==expected
                    for path,location in index['documents'].items()),('plain raw report copy differs',name))
    metadata=dict(spec['public_metadata'])
    metadata.update({name:origin for name,origin in spec['optional_public_metadata'].items() if name in manifest})
    for name,origin in metadata.items():
        expected=digest(out/name)
        require(any(path.endswith('/'+spec['build']+'/'+origin+'@'+expected) for path in aliases),
                ('public metadata/rejection copy differs',name))
    for name in ('final-warmed.json','final-v8.json'):
        for row in reports[name]['observations']:
            path=str(Path(row['log_directory'])/'stdout.txt');expected=next(iter(by_path[path]))
            lines=payloads[expected].decode().splitlines()
            require(len(lines)==2 and all(line.isdecimal() for line in lines),'raw warmed protocol differs')
            checksum,ns=map(int,lines)
            require(checksum==row['checksum'] and ns>0 and ns/1e9==row['timed_region_seconds'],'raw authoritative timer/checksum differs')
    for label,stage in index['source_stages'].items():
        source=json.loads(payloads[stage['source']['sha256']]);toolchain=json.loads(payloads[stage['toolchain']['sha256']])
        require(set(stage['headers'])==set(source['headers']) and set(stage['patches'])==set(source['patches']),'declared source inventory differs')
        require(source['headers']==toolchain['headers']=={name:value['sha256'] for name,value in stage['headers'].items()},'stage headers differ')
        require(source['patches']==toolchain['patches']=={name:value['sha256'] for name,value in stage['patches'].items()},'stage patches differ')
        require(stage['compiler_sha256']==toolchain['compiler_sha256'],'stage compiler differs')
    require(index['source_stages']['final']['compiler_sha256']==spec['compiler_sha256'],'selected source/compiler differs')
    for label,stage in index['host_stages'].items():
        host=json.loads(payloads[stage['metadata']['sha256']])
        require(host['host_sha256']==stage['host_sha256'],'host stage identity differs')
        for path,location in stage['sources'].items():
            require(location['sha256'] in retained,'host source snapshot missing')
            expected={sha for original,sha in host['input_sha256'].items() if Path(original).name==Path(path).name}
            require(expected=={location['sha256']},('host source differs from stage build input',label,path))
        if label=='final':require(host==reports['host-qualification.json']['host_build'],'final host stage differs from replay')
    final_headers={name:row['sha256'] for name,row in index['source_stages']['final']['headers'].items()}
    final_controls=set()
    for name,control in index['controls'].items():
        toolchain=json.loads(payloads[control['toolchain']['sha256']]);match=json.loads(payloads[control['match']['sha256']])
        require(set(control['headers'])==set(toolchain['headers']) and toolchain['headers']==
                {header:row['sha256'] for header,row in control['headers'].items()},'control source inventory differs')
        require(control['compiler_sha256']==toolchain['compiler_sha256']==match['control_compiler_sha256'],'control compiler differs')
        if control['qualification']==spec['qualification']:
            final_controls.add(name.split('/')[-1])
            changed={header for header,expected in final_headers.items() if toolchain['headers'][header]!=expected}
            expected_header={'merge-control':'direct_wasm_merge.h','resource-control':'direct_wasm_temps.h','named-control':'direct_wasm_funvals.h','private-control':'direct_wasm_emit.h','stencil-control':'direct_wasm_stencil.h'}[name.split('/')[-1]]
            require(changed=={expected_header} and match['selected_compiler_sha256']==spec['compiler_sha256'],'final control changes unrelated source')
    require(final_controls==set(spec['qualification_controls'][spec['qualification']]),'final matched controls missing')
    require(set(index['source_stages'])==set(spec['source_stages']) and
            all('stale-rebuild' not in Path(origin).parts for origin in spec['source_stages'].values()),'failed attempt advertised as valid stage')
    require(len(index['opaque_failed_attempts'])==len(spec['opaque_failed_attempts']),'failed attempt classification differs')
    require({row['path'].split('/next-hills/')[-1] for row in index['rejected_executions']}==set(spec['rejected_execution_roots']) and
            all(row['reason'] and row['disposition'] for row in index['rejected_executions']),'rejected execution labels missing')
    storage=index['storage'];require(storage['prior_aliases_imported']==storage['prior_documents_opened']==0,'historical namespace or reports imported')
    for public,location in index['public_bindings'].items():
        if public.endswith('-latest.json') or public=='bench/results/latest.json':
            pointer=json.loads(payloads[location['sha256']])
            if public=='bench/results/runtime-targets-latest.json':
                require(pointer['sha256']==spec['reference_sha256'],'reference pointer differs')
                require(pointer['comparison']['report'].endswith('/merge-bounds/final-warmed.json') and
                        pointer['comparison']['sha256']==digest(out/'final-warmed.json'),'comparison pointer differs')
                require(pointer['chart_verification']['sha256']==digest(out/'target-chart-verification.json'),'target chart proof pointer differs')
            else:
                require(pointer['report'].startswith('2026-11-03/merge-bounds/') and
                        pointer['sha256']==digest(out/Path(pointer['report']).name),'latest report pointer differs')
    readme=load(out/'readme.json')
    for name,expected in readme['sources'].items():safe_member(name);require(digest(out/name)==expected,'derived chart source differs')
    for name in ('target-chart-verification.json','chart-verification.json','chart-visual-review.json'):
        require(load(out/name)['status']=='passed',('chart proof failed',name))
    validate_tables(out,index,payloads,reports)
    return {'status':'passed','compiler_sha256':spec['compiler_sha256'],'archives':verified,'aliases':len(aliases),
            'omissions':len(omitted),'required_guests':len(index['required_guests']),'retained_guest_objects':len(index['guests']),
            'qualification':{'focused':74,'cases':978,'observations':9573,'native_comparisons':7656,'host_observations':11484,
                             'unique_modules':reports['host-qualification.json']['unique_wasm']},
            'measurements':{'warmed':550,'v8':200,'paired_rounds':9,'examples':1600,'host':1440,'preparations':200,'cohort':315,'lifecycle':960,'worker_effective':worker['derived_effective_cases'],'worker_aliases':3828},
            'documentation_table_cells':46,
            'retention_sha256':digest(out/'retention.json'),'index_sha256':digest(out/retention['archive_index']),
            'storage':storage,
            'scope':'Verification needs the current publication and the bounded runtime-stencil, fresh-construction, calls and forwarding archives named in its index. Reuse is byte storage only; execution rows remain fresh. No recursive report/index closure, source checkout scan, compiler, test or guest engine execution.'}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--package',type=Path,default=Path(__file__).resolve().parent.parent);parser.add_argument('--report',type=Path)
    args=parser.parse_args();result=verify(args.package.absolute())
    if args.report:
        require(not args.report.exists(),'verification report already exists');args.report.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))


if __name__=='__main__':main()
