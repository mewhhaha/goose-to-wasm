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

from bundle import fingerprints
from checks import digest, exact, guest_identities, load, require, safe_member, validate_current


def archive_path(out,spec,name,record):
    if record.get('external'):
        allowed=set(spec['reuse']['archives'].values())
        expected={f'../functions-calls/evidence-{n:03}.tar.gz' for n in range(4)}
        expected.update(f'../functions-forwarding/evidence-{n:03}.tar.gz' for n in range(8))
        require(allowed==expected and name in allowed,'archive is not one of twelve bounded prior files')
        directory=Path(name).parent
        path=(out/name).resolve()
        require(path.parent==(out/directory).resolve(),'prior archive escapes bounded directory')
        return path
    safe_member(name)
    require(Path(name).parent==Path('.'),'new archive must be local')
    return out/name


def validate_initialization(value,index,payloads,by_path,reports):
    require(value['schema']=='goose-initialization-screen-v1' and value['status']=='passed','initialization report failed')
    require(value['input_sha256']==value['input_sha256_after'],'initialization inputs changed')
    config=value['configuration']
    require(config['cpu']==2 and config['optimization']=='O2' and config['offline'] and
            config['initial_pages']==1 and config['maximum_pages']==1024,'initialization configuration differs')
    require(config['warmups_per_module_per_engine']==50 and config['paired_rounds']==9 and
            config['calls_per_block']==100,'initialization coverage differs')
    require(set(value['compiler_identities'])=={'baseline','final'},'initialization compiler inventory differs')
    for name,stage in [('baseline','baseline-353'),('final','final')]:
        require(value['compiler_identities'][name]['sha256']==index['source_stages'][stage]['compiler_sha256'],
                'initialization source/compiler differs')
    phases={row['compiler']:row for row in value['compile_phases']}
    require(len(value['compile_phases'])==2 and set(phases)=={'baseline','final'},'initialization compile coverage differs')
    for name,phase in phases.items():
        require(phase['status']=='passed' and phase['returncode']==0,'initialization fixture compile failed')
        require(phase['module_sha256'] in index['guests'] and
                set(by_path.get(phase['output'],{}))=={phase['module_sha256']},'initialization guest unavailable')
    require(len(value['commands'])==4,'initialization command coverage differs')
    for command in value['commands']:
        require(command['returncode']==0 and command['cpu_affinity']==[2],'initialization child failed or affinity differs')
        for kind in ('stdout','stderr'):
            require(set(by_path.get(command[kind+'_path'],{}))=={command[kind+'_sha256']},'initialization raw log unavailable')
    require(set(value['engine_runs'])=={'engine-v8','engine-wasmtime'},'initialization engines differ')
    pins=value['engine_versions_expected']
    require(pins['wasmtime_python']==reports['host-qualification.json']['python_engine']['version'],'initialization engine pin differs')
    for engine,run in value['engine_runs'].items():
        result=run['result']
        require(json.loads(payloads[run['stdout_sha256']])==result and payloads[run['stderr_sha256']]==b'',
                'initialization worker protocol differs')
        require(result['warmups']==50 and result['rounds']==9 and result['calls_per_round']==100,'worker coverage differs')
        require(len(result['warmup_order'])==50 and len(result['round_order'])==9 and
                all(sorted(order)==['baseline','final'] for order in result['warmup_order']+result['round_order']),
                'initialization paired ordering differs')
        if engine=='engine-wasmtime':
            require(result['engine']['version']==pins['wasmtime_python'] and
                    result['engine_config']=={'cranelift_opt_level':'speed'},'initialization Wasmtime differs')
        else:
            require(result['engine']['node'].removeprefix('v')==pins['node'] and result['engine']['v8']==pins['v8'],
                    'initialization V8 differs')
        require(set(result['modules'])=={'baseline','final'},'worker module inventory differs')
        for name,module in result['modules'].items():
            require(module['module_sha256']==phases[name]['module_sha256'] and
                    module['module_bytes']==phases[name]['module_bytes'],'worker guest differs')
            sizes=[module[key] for key in ('memory_bytes','memory_bytes_after_warmup','memory_bytes_after_measurement')]
            require(all(type(size) is int and 65536<=size<=1024*65536 and size%65536==0 for size in sizes) and
                    sizes[1]>=max(sizes[0],8388608) and sizes[1]==sizes[2],'initialization memory plateau differs')
        exact(result['observations'],('compiler','round'),
              {(name,round_) for name in ('baseline','final') for round_ in range(9)},'initialization observations')
        require([(row['round'],row['compiler']) for row in result['observations']]==
                [(round_,name) for round_,order in enumerate(result['round_order']) for name in order],
                'initialization recorded order differs')
        for row in result['observations']:
            require(row['calls']==100 and row['checksum'] in (0,'0') and type(row['elapsed_ns']) is int and
                    row['elapsed_ns']>0 and row['ns_per_call']==row['elapsed_ns']/100,'initialization timer/checksum differs')


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
    require(retention['schema']=='goose-fresh-construction-retention-v1','retention schema')
    for name,expected in manifest.items():
        safe_member(name);require(digest(out/name)==expected,('public manifest differs',name))
    for name,expected in retention['public_file_sha256'].items():
        require(manifest[name]==expected,('retention/public manifest mismatch',name))
    require(manifest['retention.json']==digest(out/'retention.json'),'retention digest differs')
    index=load(out/retention['archive_index']);require(index['schema']=='goose-fresh-construction-objects-v1','object index schema')
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
    for name in ('final-warmed.json','final-v8.json'):
        for row in reports[name]['observations']:
            path=str(Path(row['log_directory'])/'stdout.txt')
            require(path in by_path and len(by_path[path])==1,('authoritative stdout unavailable',path))
            wanted.update(by_path[path])
    for stage in index['source_stages'].values():
        wanted.add(stage['source']['sha256']);wanted.add(stage['toolchain']['sha256'])
    for control in index['controls'].values():
        wanted.add(control['toolchain']['sha256']);wanted.add(control['match']['sha256'])
    for name in spec['extra_reports']:
        extra=load(out/name)
        for command in extra['commands']:
            wanted.update((command['stdout_sha256'],command['stderr_sha256']))
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
            phases={'delivered-warmed':'final-warmed.json','delivered-v8':'final-v8.json','examples':'examples.json','host':'host.json','langarena':'cohort.json'}
            require(len(value['phases'])==5 and {row['name'] for row in value['phases']}==set(phases),'five delivery phases differ')
            for row in value['phases']:
                require(row['status']=='passed' and row['exit_status']==0,'delivery phase failed')
                require(row['report_sha256']==digest(out/phases[row['name']]),'delivery report edge differs')
                require(row['stdout_sha256'] in retained and row['stderr_sha256'] in retained,'delivery output missing')
        if any(origin.endswith('/'+name) for name in spec['extra_reports'].values()):
            validate_initialization(value,index,payloads,by_path,reports)
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
        require(len(stage['headers'])==32 and len(stage['patches'])==2,'source inventory differs')
        require(source['headers']==toolchain['headers']=={name:value['sha256'] for name,value in stage['headers'].items()},'stage headers differ')
        require(source['patches']==toolchain['patches']=={name:value['sha256'] for name,value in stage['patches'].items()},'stage patches differ')
        require(stage['compiler_sha256']==toolchain['compiler_sha256'],'stage compiler differs')
    require(index['source_stages']['final']['compiler_sha256']==spec['compiler_sha256'],'selected source/compiler differs')
    final_headers={name:row['sha256'] for name,row in index['source_stages']['final']['headers'].items()}
    final_controls=set()
    for name,control in index['controls'].items():
        toolchain=json.loads(payloads[control['toolchain']['sha256']]);match=json.loads(payloads[control['match']['sha256']])
        require(len(control['headers'])==32 and toolchain['headers']==
                {header:row['sha256'] for header,row in control['headers'].items()},'control source inventory differs')
        require(control['compiler_sha256']==toolchain['compiler_sha256']==match['control_compiler_sha256'],'control compiler differs')
        if control['qualification']==spec['qualification']:
            final_controls.add(name.split('/')[-1])
            changed={header for header,expected in final_headers.items() if toolchain['headers'][header]!=expected}
            expected_header={'resource-control':'direct_wasm_temps.h','named-control':'direct_wasm_funvals.h'}[name.split('/')[-1]]
            require(changed=={expected_header} and match['selected_compiler_sha256']==spec['compiler_sha256'],'final control changes unrelated source')
    require(final_controls==set(spec['qualification_controls'][spec['qualification']]),'final matched controls missing')
    require(set(index['source_stages'])==set(spec['source_stages']) and
            all('stale-rebuild' not in Path(origin).parts for origin in spec['source_stages'].values()),'failed attempt advertised as valid stage')
    require(len(index['opaque_failed_attempts'])==len(spec['opaque_failed_attempts']),'failed attempt classification differs')
    require({row['path'].split('/functions-init/')[-1] for row in index['rejected_executions']}==set(spec['rejected_execution_roots']) and
            all(row['reason'] and row['disposition'] for row in index['rejected_executions']),'rejected execution labels missing')
    storage=index['storage'];require(storage['prior_aliases_imported']==storage['prior_documents_opened']==0,'historical namespace or reports imported')
    for public,location in index['public_bindings'].items():
        if public.endswith('-latest.json') or public=='bench/results/latest.json':
            pointer=json.loads(payloads[location['sha256']])
            if public=='bench/results/runtime-targets-latest.json':
                require(pointer['sha256']==spec['reference_sha256'],'reference pointer differs')
                require(pointer['comparison']['report'].endswith('/fresh-construction/final-warmed.json') and
                        pointer['comparison']['sha256']==digest(out/'final-warmed.json'),'comparison pointer differs')
                require(pointer['chart_verification']['sha256']==digest(out/'target-chart-verification.json'),'target chart proof pointer differs')
            else:
                require(pointer['report'].startswith('2026-11-03/fresh-construction/') and
                        pointer['sha256']==digest(out/Path(pointer['report']).name),'latest report pointer differs')
    readme=load(out/'readme.json')
    for name,expected in readme['sources'].items():safe_member(name);require(digest(out/name)==expected,'derived chart source differs')
    for name in ('target-chart-verification.json','chart-verification.json','chart-visual-review.json'):
        require(load(out/name)['status']=='passed',('chart proof failed',name))
    validate_tables(out,index,payloads,reports)
    return {'status':'passed','compiler_sha256':spec['compiler_sha256'],'archives':verified,'aliases':len(aliases),
            'omissions':len(omitted),'required_guests':len(index['required_guests']),'retained_guest_objects':len(index['guests']),
            'qualification':{'focused':70,'cases':978,'observations':9573,'native_comparisons':7656,'host_observations':11484,
                             'unique_modules':reports['host-qualification.json']['unique_wasm']},
            'measurements':{'warmed':550,'v8':200,'paired_rounds':9,'examples':1600,'host':1440,'preparations':200,'cohort':315},
            'documentation_table_cells':46,
            'retention_sha256':digest(out/'retention.json'),'index_sha256':digest(out/retention['archive_index']),
            'storage':storage,
            'scope':'Verification needs the current publication and the bounded calls and forwarding archives named in its index. Reuse is byte storage only; execution rows remain fresh. No recursive report/index closure, source checkout scan, compiler, test or guest engine execution.'}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--package',type=Path,default=Path(__file__).resolve().parent.parent);parser.add_argument('--report',type=Path)
    args=parser.parse_args();result=verify(args.package.absolute())
    if args.report:
        require(not args.report.exists(),'verification report already exists');args.report.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))


if __name__=='__main__':main()
