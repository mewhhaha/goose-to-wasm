#!/usr/bin/env python3
"""Offline verification of only the new Functions campaign and byte objects.

No compiler, engine or guest runs. Hashing/decompression still needs an explicit
quiet window. Published dependencies are checked by archive and member SHA.
"""
from pathlib import Path
import argparse
import gzip
import hashlib
import json
import math
import tarfile

from checks import digest, guest_identities, identities, load, reference_root, require, safe_member, validate_current


def verify(output):
    retention=load(output/'retention.json');spec=retention['specification']
    require(retention['schema']=='goose-functions-retention-v1', 'retention schema')
    require(retention['compiler_sha256']==spec['compiler_sha256'], 'compiler identity')
    manifest=load(output/'SHA256.json')
    require(manifest['retention.json']==digest(output/'retention.json'), 'retention manifest differs')
    for name,expected in manifest.items():
        safe_member(name);require(digest(output/name)==expected, ('public SHA manifest differs',name))
    for name,expected in retention['public_file_sha256'].items():
        safe_member(name);require(digest(output/name)==expected, ('public file differs',name))
    index=load(output/retention['archive_index'])
    require(index['schema']=='goose-functions-archives-v1', 'archive index schema')
    archives=index['archives'];aliases=index['aliases'];omitted=index['omitted']
    require(not set(aliases)&set(omitted), 'identity both retained and omitted')
    wanted=set();path_locations={}
    for original,location in aliases.items():
        path,separator,expected=original.rpartition('@')
        require(separator and location['sha256']==expected, ('alias identity',original))
        record=archives[location['archive']]['members'][location['member']]
        require(record=={key:location[key] for key in ('sha256','bytes')}, 'member location differs')
        path_locations.setdefault(path,{})[expected]=location
    for key,row in omitted.items():
        require(key==row['original']+'@'+row['sha256'] and row['reason'] and row['category'], 'invalid explicit omission')
    reports={name:load(output/name) for name in spec['reports']}
    reference_path=(output/retention['reference']).resolve()
    require(digest(reference_path)==retention['reference_sha256'], 'official reference changed')
    reference=load(reference_path)
    validate_current(reports,reference,retention['compiler_sha256'])
    require(len(index['source_stages'])==3 and set(index['source_stages'])=={'tee','dead','final'}, 'source stages missing')
    for stage in index['source_stages'].values():
        require(len(stage['headers'])==32 and len(stage['patches'])==2, 'minimal source inventory incomplete')
        require(all(stage['headers'].values()) and all(stage['patches'].values()), 'source identity was omitted')
    require(index['source_stages']['final']['compiler_sha256']==retention['compiler_sha256'], 'final source compiler differs')
    expected_guests=set(index['required_guests'])
    retained_shas={location['sha256'] for location in aliases.values()}
    require(expected_guests<=retained_shas, 'required guest bytes missing')
    # Only declared current claim reports get fingerprint closure. Archived JSON
    # logs, rejected attempts and historical packaging context remain byte leaves.
    def check_claim(value, label):
        for original,expected in identities(value):
            require(original+'@'+expected in aliases or original+'@'+expected in omitted,
                    ('current input identity unresolved',label,original,expected))
        for original,expected in guest_identities(value):
            require(expected in retained_shas, ('measured guest missing',label,original,expected))
            if original is not None:
                require(original+'@'+expected in aliases, ('measured guest classified as tool',label,original))
    for name,report in reports.items(): check_claim(report,name)
    for name,origin in retention['report_origins'].items():
        expected_report=digest(output/name)
        matches=[location for original,location in aliases.items()
                 if original.endswith('/build/functions-hill/'+origin+'@'+expected_report)]
        require(matches, ('raw report original unavailable',name))
    host=reports['host.json'];example_path=host['configuration']['example_report']
    require(host['input_sha256'][example_path]==digest(output/'examples.json'), 'host/example report edge differs')
    for name in ('final-warmed.json','final-v8.json'):
        for row in reports[name]['observations']:
            path=str(Path(row['log_directory'])/'stdout.txt')
            require(path in path_locations and len(path_locations[path])==1, ('raw kernel stdout missing',path))
            wanted.update(path_locations[path])
    # Source metadata and archived claim bytes are checked against their aliases.
    for stage in index['source_stages'].values():
        wanted.add(stage['source']['sha256']);wanted.add(stage['toolchain']['sha256'])
    wanted.update(location['sha256'] for location in index['evidence_documents'].values())
    wanted.update(location['sha256'] for location in index['public_bindings'].values())
    payloads={};verified={}
    for name,record in archives.items():
        path=(output/name).resolve()
        if not record['historical']:
            safe_member(name);require(path.parent==output.resolve(), 'new archive escapes package')
        require(path.stat().st_size==record['bytes'] and digest(path)==record['sha256'], ('archive differs',name))
        found={};total_raw=10240
        with tarfile.open(path,'r:gz') as archive:
            for member in archive:
                safe_member(member.name)
                require(member.isfile(), ('nonregular archive member',name,member.name))
                total_raw+=512+math.ceil(member.size/512)*512
                if member.name not in record['members']:
                    require(record['historical'], ('unindexed new member',name,member.name));continue
                require(member.name not in found, ('duplicate archive member',name,member.name))
                retained=record['members'][member.name]['sha256'] in wanted
                with archive.extractfile(member) as stream:
                    if retained:
                        payload=stream.read();expected=hashlib.sha256(payload).hexdigest()
                        payloads[expected]=payload
                    else: expected=hashlib.file_digest(stream,'sha256').hexdigest()
                found[member.name]={'sha256':expected,'bytes':member.size}
        require(found==record['members'], ('member SHA/coverage differs',name))
        if not record['historical']:
            require(total_raw<=retention['maximum_raw_archive_bytes'], ('raw archive partition bound',name))
            require(record['bytes']<100*1024*1024, ('Git archive size cap',name))
        verified[name]=len(found)
        print('verified',name,len(found),'members',flush=True)
    require(wanted<=payloads.keys(), 'required raw payload missing')
    for name in ('final-warmed.json','final-v8.json'):
        for row in reports[name]['observations']:
            path=str(Path(row['log_directory'])/'stdout.txt');expected=next(iter(path_locations[path]))
            lines=payloads[expected].decode().splitlines()
            require(len(lines)==2 and all(line.isdecimal() for line in lines), ('raw timer protocol',path))
            checksum,nanoseconds=map(int,lines)
            require(checksum==row['checksum'] and nanoseconds>0 and nanoseconds/1e9==row['timed_region_seconds'],
                    ('authoritative timer/checksum differs',name,path))
    for name,stage in index['source_stages'].items():
        source=json.loads(payloads[stage['source']['sha256']]);toolchain=json.loads(payloads[stage['toolchain']['sha256']])
        require(source['headers']==toolchain['headers'] and source['patches']==toolchain['patches'], ('source metadata differs',name))
        require(toolchain['compiler_sha256']==stage['compiler_sha256'], ('source compiler differs',name))
        require(source['headers']=={key:value['sha256'] for key,value in stage['headers'].items()}, ('retained headers differ',name))
        require(source['patches']=={key:value['sha256'] for key,value in stage['patches'].items()}, ('retained patches differ',name))
    repo=reference_root(reference)
    qualified=reports['differential.json']['qualification_execution']['input_sha256']
    for name,location in index['source_stages']['final']['headers'].items():
        require(qualified[str(repo/'compiler'/name)]==location['sha256'], ('qualified final header differs',name))
    for origin,location in index['evidence_documents'].items():
        evidence=json.loads(payloads[location['sha256']]);check_claim(evidence,origin)
        if origin.endswith('/delivery-execution/report.json'):
            require(evidence['status']=='passed' and evidence['compiler_sha256']==retention['compiler_sha256'], 'delivery execution failed')
            require(evidence['input_sha256']==evidence['input_sha256_after'], 'delivery execution pins changed')
            phases={'delivered-warmed':'final-warmed.json','delivered-v8':'final-v8.json',
                    'examples':'examples.json','host':'host.json','langarena':'cohort.json'}
            require(len(evidence['phases'])==5 and {row['name'] for row in evidence['phases']}==set(phases), 'delivery phases differ')
            for row in evidence['phases']:
                require(row['status']=='passed' and row['exit_status']==0, 'delivery phase failed')
                require(row['report_sha256']==digest(output/phases[row['name']]), 'delivery phase report differs')
                require(row['stdout_sha256'] in retained_shas and row['stderr_sha256'] in retained_shas, 'delivery phase output missing')
        if any(origin.endswith('/'+screen+'/report.json') for screen in spec['screens']):
            require(evidence['status']=='passed', ('screen status differs',origin))
    for name,location in index['public_bindings'].items():
        if name.endswith('-latest.json') or name=='bench/results/latest.json':
            pointer=json.loads(payloads[location['sha256']])
            target=Path(pointer['report']).name
            if name=='bench/results/runtime-targets-latest.json':
                require(pointer['sha256']==retention['reference_sha256'], 'reference pointer differs')
                comparison=pointer['comparison']
                require(comparison['report'].endswith('/functions/final-warmed.json') and
                        comparison['sha256']==digest(output/'final-warmed.json'), 'runtime comparison pointer differs')
                proof=pointer['chart_verification']
                require(proof['report'].endswith('/functions/target-chart-verification.json') and
                        proof['sha256']==digest(output/'target-chart-verification.json'), 'target chart verification pointer differs')
            else:
                require(pointer['report'].startswith('2026-11-03/functions/') and
                        pointer['sha256']==digest(output/target), ('latest pointer differs',name))
    derived=load(output/'readme.json')
    require(derived.get('sources'), 'derived chart source manifest required')
    for name,expected in derived['sources'].items():
        safe_member(name);require(digest(output/name)==expected, ('chart input identity differs',name))
    chart_proof=load(output/'target-chart-verification.json')
    require(chart_proof['status']=='passed', 'target chart verification failed')
    campaign=load(output/'campaign.json')
    require(campaign.get('status')=='measured-and-qualified', 'campaign publication incomplete')
    require(campaign['selected_compiler_sha256']==retention['compiler_sha256'], 'campaign compiler differs')
    return {'status':'passed','compiler_sha256':retention['compiler_sha256'],'archives':verified,
            'aliases':len(aliases),'explicit_omissions':len(omitted),'measured_guest_identities':len(expected_guests),
            'qualification':{'focused':66,'differential':9573,'native_comparisons':7656,'cases':978,
                             'host':11484,'unique_modules':reports['host-qualification.json']['unique_wasm']},
            'measurements':{'warmed':550,'v8':200,'pairs':9,'examples':1600,'host':1440,'preparations':200,'cohort':315},
            'retention_sha256':digest(output/'retention.json'),'index_sha256':digest(output/retention['archive_index'])}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,required=True)
    parser.add_argument('--report',type=Path)
    args=parser.parse_args();result=verify(args.package.absolute())
    if args.report:
        require(not args.report.exists(), 'refusing to overwrite verification record')
        args.report.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))


if __name__=='__main__': main()
