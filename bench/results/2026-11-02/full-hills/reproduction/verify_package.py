#!/usr/bin/env python3
"""Verify campaign archives and primary claims without executing any guest.

Run only outside performance sampling: reading/hashing/decompressing archives
uses CPU and IO. Historical sibling archives remain explicit dependencies.
"""
from pathlib import Path
import argparse
import gzip
import hashlib
import json
import math
import tarfile
from package import OUT, REPORTS, REFERENCE_SHA, digest, guest_identities, identities, load, require, safe_member, validate_claims


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    default=OUT
    if Path(__file__).resolve().parent.name=='reproduction': default=Path(__file__).resolve().parent.parent
    parser.add_argument('--package',type=Path,default=default)
    parser.add_argument('--report',type=Path,help='optional verification record; existing files are never overwritten')
    args=parser.parse_args()
    output=args.package.resolve(); retention=load(output/'retention.json')
    require(retention['schema']=='goose-full-hills-retention-v1','unknown retention schema')
    require(retention['reference_sha256']==REFERENCE_SHA,'reference identity differs')
    for name,expected in retention['public_file_sha256'].items():
        safe_member(name)
        require(digest(output/name)==expected,('public file differs',name))
    readme=load(output/'readme.json')
    for name,expected in readme['sources'].items():
        safe_member(name)
        require(digest(output/name)==expected,('derived chart source differs',name))
    index=load(output/retention['archive_index'])
    require(index['schema']=='goose-full-hills-archives-v1','unknown archive index schema')
    archives=index['archives']; aliases=index['aliases']; omitted=index['omitted']
    def location_exists(location):
        archive=location['archive']; member=location['member']
        require(archive in archives and member in archives[archive]['members'],'unavailable archive member')
        require(archives[archive]['members'][member]=={name:location[name] for name in ('sha256','bytes')},'member identity differs')
    for original,location in aliases.items():
        _,separator,expected=original.rpartition('@')
        require(separator and expected==location['sha256'],'alias SHA differs')
        location_exists(location)
        require(original not in omitted,'input advertised both retained and omitted')
    for original,location in index['opaque_historical_context'].items():
        require('/source/bench/results/' in original,'unexpected opaque context')
        location_exists(location)
        require(aliases[original+'@'+location['sha256']]==location and original not in index['documents'],
                'opaque context must be retained without recursive claim validation')
    for original,row in omitted.items():
        require(original==row['original']+'@'+row['sha256'] and row['reason'],'invalid omission')
        require(row['category'] in {'tool-binary-or-external-input','rebuildable-dependency'},'unrecognized omission')
        if row.get('dependency_manifest'):
            manifest=row['dependency_manifest']
            require(manifest.endswith('/hosts/h01-runtime/source-files.json') and manifest in index['documents'],
                    'unrecognized dependency source manifest')
    retained_sha={location['sha256'] for location in aliases.values()}
    for sha in index['anonymous_guests']:
        require(sha in retained_sha,('anonymous guest unavailable',sha))
    reports={name:load(output/name) for name in REPORTS}
    reference=load(output/'references.json'); compiler=load(output/'compiler-identity.json')
    require(digest(output/'references.json')==REFERENCE_SHA,'raw reference differs')
    require(compiler['compiler_sha256']==retention['compiler_sha256'],'final compiler identity differs')
    validate_claims(reports,reference,retention['compiler_sha256'],retention['expected_counts'],load(output/'campaign.json'))
    for name in ('ci-followup.json','optimizer-followup.json'):
        for original,row in reports[name]['source_changes'].items():
            for path,sha in [(original,row['before_sha256']),(row['preserved_before'],row['before_sha256']),
                             (original,row['after_sha256'])]:
                require(path+'@'+sha in aliases,('follow-up source version unavailable',name,path,sha))
    campaign=load(output/'campaign.json')
    require(set(index['hill_evidence'])=={item['id'] for item in campaign['items']},'hill evidence inventory differs')
    for item in campaign['items']:
        evidence=index['hill_evidence'][item['id']]
        require([row['requested'] for row in evidence]==item['evidence'],'hill evidence paths differ')
        for row in evidence:
            location_exists(row['location'])
            require(aliases[row['original']+'@'+row['location']['sha256']]==row['location'],'hill evidence alias differs')
    # Qualification reports may be internally consistent while linked to a
    # different examples cohort. Verify this retained report-to-report edge.
    host=reports['host.json']; example_path=host['configuration']['example_report']
    require(host['input_sha256'][example_path]==retention['public_file_sha256']['examples.json'],'host/examples report link differs')
    for name,origin in retention['report_origins'].items():
        expected=retention['public_file_sha256'][name]
        candidates=[location for original,location in aliases.items()
                    if original.endswith('/build/full-hills/'+origin+'@'+expected)]
        require(candidates,('raw report origin unavailable',name))
    path_locations={}
    for original,location in aliases.items():
        path=original.rpartition('@')[0]
        path_locations.setdefault(path,{})[location['sha256']]=location
    payloads={}; wanted=set()
    for name in ('final-warmed.json','final-v8.json'):
        for row in reports[name]['observations']:
            path=str(Path(row['log_directory'])/'stdout.txt')
            require(path in path_locations and len(path_locations[path])==1,('runtime stdout unavailable/ambiguous',path))
            wanted.update(path_locations[path])
    documents_by_sha={}
    for original,location in index['documents'].items():
        location_exists(location)
        documents_by_sha.setdefault(location['sha256'],[]).append(original)
    inspected_documents=set(); guests_checked=0
    def check_document(value,origin):
        nonlocal guests_checked
        for original,sha in identities(value):
            require(original+'@'+sha in aliases or original+'@'+sha in omitted,
                    ('document fingerprint unresolved',origin,original,sha))
        for original,sha in guest_identities(value):
            guests_checked+=1
            if original is None:
                require(sha in retained_sha,('document guest unavailable',origin,sha))
            else:
                require(original+'@'+sha in aliases,('document guest bytes omitted',origin,original,sha))
    verified={}
    for name,record in archives.items():
        path=(output/name).resolve()
        if record['historical']:
            require(path.parent in {output.parent/'runtime-targets',output.parent/'resource-free-calls'},'unexpected historical dependency')
        else:
            safe_member(name)
            require(path.parent==output,'archive escapes package')
        require(digest(path)==record['sha256'] and path.stat().st_size==record['bytes'],('archive differs',name))
        members={}
        with tarfile.open(path,'r:gz') as archive:
            for member in archive:
                safe_member(member.name)
                require(member.isfile() and member.name not in members,('nonregular/duplicate member',name,member.name))
                with archive.extractfile(member) as data:
                    sha=hashlib.file_digest(data,'sha256').hexdigest()
                members[member.name]={'sha256':sha,'bytes':member.size}
                if sha in wanted or sha in documents_by_sha and sha not in inspected_documents:
                    with archive.extractfile(member) as data: payload=data.read()
                    if sha in wanted: payloads[sha]=payload
                    if sha in documents_by_sha and sha not in inspected_documents:
                        origin=documents_by_sha[sha][0]
                        if origin.endswith('.gz'): payload=gzip.decompress(payload)
                        check_document(json.loads(payload),origin)
                        inspected_documents.add(sha)
        require(members==record['members'],('archive member index differs',name))
        verified[name]=len(members)
    require(inspected_documents==set(documents_by_sha),'some retained JSON documents were not checked')
    for name in ('final-warmed.json','final-v8.json'):
        for row in reports[name]['observations']:
            path=str(Path(row['log_directory'])/'stdout.txt')
            sha=next(iter(path_locations[path]))
            lines=payloads[sha].decode().splitlines()
            require(len(lines)==2 and all(line.isdecimal() for line in lines),'invalid raw warmed protocol')
            checksum,nanoseconds=map(int,lines)
            require(checksum==row['checksum'] and nanoseconds>0 and nanoseconds/1e9==row['timed_region_seconds'],
                    ('authoritative raw timer differs',name,path))
    for report in reports.values(): check_document(report,'primary report')
    result={'status':'passed','archives':verified,'alias_count':len(aliases),'omitted_inputs':len(omitted),
            'opaque_historical_context_files':len(index['opaque_historical_context']),
            'retained_json_documents':len(index['documents']),'guest_identities_checked':guests_checked,
            'compiler_sha256':retention['compiler_sha256'],'reference_sha256':REFERENCE_SHA,
            'original_focused_commands':retention['expected_counts']['focused_commands'],
            'followup_commands':len(reports['ci-followup.json']['commands']),
            'optimizer_followup_commands':len(reports['optimizer-followup.json']['commands']),
            'retention_sha256':digest(output/'retention.json'),'index_sha256':digest(output/retention['archive_index']),
            'claims':'Exact primary matrices, raw warmed protocol/timers, final compiler and frozen source/engine choices verified. Failed experiments remain unmodified evidence, not passing claims.'}
    if args.report:
        require(not args.report.exists(),'refusing to overwrite verification output')
        args.report.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))


if __name__=='__main__': main()
