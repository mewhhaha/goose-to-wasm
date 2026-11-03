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
        directory=Path(spec['reuse']['relative_directory'])
        require(directory.parts==('..','functions-forwarding'),'unexpected prior archive directory')
        require(Path(name).parent==directory and Path(name).name in spec['reuse']['archives'],'archive is not from the immediate prior bundle')
        path=(out/name).resolve()
        require(path.parent==(out/directory).resolve(),'prior archive escapes bounded directory')
        return path
    safe_member(name)
    require(Path(name).parent==Path('.'),'new archive must be local')
    return out/name


def verify(out):
    manifest=load(out/'SHA256.json');retention=load(out/'retention.json');spec=retention['specification']
    require(retention['schema']=='goose-calls-retention-v1','retention schema')
    for name,expected in manifest.items():
        safe_member(name);require(digest(out/name)==expected,('public manifest differs',name))
    for name,expected in retention['public_file_sha256'].items():
        require(manifest[name]==expected,('retention/public manifest mismatch',name))
    require(manifest['retention.json']==digest(out/'retention.json'),'retention digest differs')
    index=load(out/retention['archive_index']);require(index['schema']=='goose-calls-objects-v1','object index schema')
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
            require(value['status']=='passed','holdout failed')
            variants=set(value['variants']);require(len(variants)==2 and 'baseline-O2' in variants,'holdout variants differ')
            selected=next(iter(variants-{'baseline-O2'}))
            require(value['variants'][selected]['sha256']==index['source_stages']['final']['module']['sha256'],'holdout selected module differs')
            require(value['variants']['baseline-O2']['sha256']==index['source_stages']['baseline-19d']['module']['sha256'],'holdout baseline module differs')
            cells={'native-C'}|{variant+'/'+mode for variant in variants for mode in ('ordinary','aot','v8')}
            expected={(phase,sample,cell) for phase,count in [('warmup',2),('measure',61)] for sample in range(count) for cell in cells}
            exact(value['observations'],('phase','sample','cell'),expected,'holdout observations')
            exact(value['phase_probes'],('sample','variant','engine'),
                  {(i,variant,engine) for i in range(31) for variant in variants for engine in ('native-host','v8')},'holdout phase probes')
            measured={(row['sample'],row['cell']):row['seconds'] for row in value['observations'] if row['phase']=='measure'}
            for cell in cells:
                samples=[measured[i,cell] for i in range(61)];median=statistics.median(samples)
                require(all(math.isfinite(sample) and sample>0 for sample in samples),'invalid holdout time')
                require(value['summary'][cell]['n']==61 and value['summary'][cell]['median']==median and
                        value['summary'][cell]['mad']==statistics.median(abs(sample-median) for sample in samples),'holdout median/MAD differs')
            for mode in ('ordinary','aot','v8'):
                ratios=[measured[i,'baseline-O2/'+mode]/measured[i,selected+'/'+mode] for i in range(61)]
                median=statistics.median(ratios)
                require(value['paired_speedups'][mode]['n']==61 and value['paired_speedups'][mode]['median']==median and
                        value['paired_speedups'][mode]['mad']==statistics.median(abs(ratio-median) for ratio in ratios),'holdout paired summary differs')
            golden={expected for path,expected in value['input_sha256'].items() if path.endswith('/examples/expected/functions.out')}
            require(len(golden)==1,'holdout golden identity missing')
            folder=Path(origin).parent;empty=hashlib.sha256(b'').hexdigest()
            log_paths=[folder/'logs'/row['phase']/str(row['sample'])/row['cell'] for row in value['observations']]
            log_paths += [folder/'logs/phases'/str(row['sample'])/row['variant']/row['engine'] for row in value['phase_probes']]
            for log in log_paths:
                require(set(by_path.get(str(log/'stdout'),{}))==golden and set(by_path.get(str(log/'stderr'),{}))=={empty},'holdout raw output/golden differs')
    for name,origin in {**spec['reports'],**spec['extra_reports']}.items():
        expected=digest(out/name)
        require(any(path.endswith('/'+spec['build']+'/'+origin) and location['sha256']==expected
                    for path,location in index['documents'].items()),('plain raw report copy differs',name))
    for name,origin in spec['public_metadata'].items():
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
    require(index['opaque_failed_attempts'],'failed attempt classification missing')
    require({row['path'].split('/functions-grow/')[-1] for row in index['rejected_executions']}==set(spec['rejected_execution_roots']) and
            all(row['reason'] and row['disposition'] for row in index['rejected_executions']),'rejected execution labels missing')
    storage=index['storage'];require(storage['prior_aliases_imported']==storage['prior_documents_opened']==0,'historical namespace or reports imported')
    for public,location in index['public_bindings'].items():
        if public.endswith('-latest.json') or public=='bench/results/latest.json':
            pointer=json.loads(payloads[location['sha256']])
            if public=='bench/results/runtime-targets-latest.json':
                require(pointer['sha256']==spec['reference_sha256'],'reference pointer differs')
                require(pointer['comparison']['report'].endswith('/functions-calls/final-warmed.json') and
                        pointer['comparison']['sha256']==digest(out/'final-warmed.json'),'comparison pointer differs')
                require(pointer['chart_verification']['sha256']==digest(out/'target-chart-verification.json'),'target chart proof pointer differs')
            else:
                require(pointer['report'].startswith('2026-11-03/functions-calls/') and
                        pointer['sha256']==digest(out/Path(pointer['report']).name),'latest report pointer differs')
    readme=load(out/'readme.json')
    for name,expected in readme['sources'].items():safe_member(name);require(digest(out/name)==expected,'derived chart source differs')
    for name in ('target-chart-verification.json','chart-verification.json','chart-visual-review.json'):
        require(load(out/name)['status']=='passed',('chart proof failed',name))
    return {'status':'passed','compiler_sha256':spec['compiler_sha256'],'archives':verified,'aliases':len(aliases),
            'omissions':len(omitted),'required_guests':len(index['required_guests']),'retained_guest_objects':len(index['guests']),
            'qualification':{'focused':69,'cases':978,'observations':9573,'native_comparisons':7656,'host_observations':11484,
                             'unique_modules':reports['host-qualification.json']['unique_wasm']},
            'measurements':{'warmed':550,'v8':200,'paired_rounds':9,'examples':1600,'host':1440,'preparations':200,'cohort':315},
            'retention_sha256':digest(out/'retention.json'),'index_sha256':digest(out/retention['archive_index']),
            'storage':storage,
            'scope':'Verification needs the current publication and immediate functions-forwarding archives named in its index. Reuse is byte storage only; execution rows remain fresh. No recursive report/index closure, source checkout scan, compiler, test or guest engine execution.'}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--package',type=Path,required=True);parser.add_argument('--report',type=Path)
    args=parser.parse_args();result=verify(args.package.absolute())
    if args.report:
        require(not args.report.exists(),'verification report already exists');args.report.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))


if __name__=='__main__':main()
