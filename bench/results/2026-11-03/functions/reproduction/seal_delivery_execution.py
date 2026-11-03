"""Add the finite orchestration evidence and exactly recovered prototype test."""
from pathlib import Path
import gzip
import hashlib
import json
import math
import shutil
import tarfile

ROOT=Path.cwd();BASE=ROOT/'build/functions-hill';OUT=ROOT/'bench/results/2026-11-03/functions'

def sha(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def compressed(path,value):
    with path.open('wb') as raw:
        with gzip.GzipFile(filename='',fileobj=raw,mode='wb',mtime=0) as stream:
            stream.write(json.dumps(value,separators=(',',':'),sort_keys=True).encode())

with gzip.open(OUT/'archives.json.gz','rt') as stream:index=json.load(stream)
by_sha={row['sha256']:row for row in index['aliases'].values()}
omitted={row['sha256']:row for row in index['omitted'].values()};objects={}

def add(path,original=None):
    path=path.absolute()
    if original is None:original=str(path)
    expected=sha(path);key=original+'@'+expected
    if expected in by_sha:location=dict(by_sha[expected])
    else:
        location={'archive':'evidence-delivery-execution.tar.gz','member':f'objects/{expected}/{path.name}',
                  'sha256':expected,'bytes':path.stat().st_size}
        objects[expected]=(path,location)
        by_sha[expected]=location
    index['aliases'][key]=location
    return location

paths=sorted(path for path in (BASE/'delivery-execution').rglob('*') if path.is_file())
paths += [BASE/'dead/tests/test_local_tee.py',BASE/'dead/tests/recovery.json',
          BASE/'delivery-package/verify_package.py',Path(__file__).absolute()]
for path in paths:add(path)
old_test=BASE/'dead/tests/test_local_tee.py'
assert sha(old_test)=='10eed059c232e25fcfce5b7ac542502e712d59606c167a9c7de4dc215c042c05'
add(old_test,str(ROOT/'tests/test_local_tee.py'))
report=BASE/'delivery-execution/report.json';value=json.loads(report.read_bytes())
assert sha(report)=='7a14899e201a8fcd6345cf9a5638ac748623153ddf31b561c4af70c05f4eb808'
assert value['input_sha256']==value['input_sha256_after'] and value['status']=='passed'
for original,expected in value['input_sha256'].items():
    key=original+'@'+expected
    if key in index['aliases'] or key in index['omitted']:continue
    if expected in by_sha:index['aliases'][key]=dict(by_sha[expected])
    elif expected in omitted:
        row=dict(omitted[expected]);row['original']=original;index['omitted'][key]=row
    else:raise RuntimeError(('unresolved bounded orchestration input',original,expected))
index['evidence_documents'][str(report)]=add(report)
name='evidence-delivery-execution.tar.gz';target=OUT/name;assert not target.exists()
raw_size=10240+sum(512+math.ceil(row['bytes']/512)*512 for _,row in objects.values())
assert raw_size<=67108864
members={}
with target.open('wb') as raw:
    with gzip.GzipFile(filename='',fileobj=raw,mode='wb',mtime=0) as stream:
        with tarfile.open(fileobj=stream,mode='w|',format=tarfile.USTAR_FORMAT) as archive:
            for expected,(path,row) in sorted(objects.items()):
                info=tarfile.TarInfo(row['member']);info.size=row['bytes'];info.mode=0o644
                with path.open('rb') as source:archive.addfile(info,source)
                members[row['member']]={'sha256':expected,'bytes':info.size}
index['archives'][name]={'sha256':sha(target),'bytes':target.stat().st_size,'historical':False,'members':members}
compressed(OUT/'archives.json.gz',index)
for source in [BASE/'delivery-package/verify_package.py',Path(__file__).absolute()]:
    shutil.copyfile(source,OUT/'reproduction'/source.name)
p=OUT/'retention.json';retention=json.loads(p.read_bytes())
for path in [target,OUT/'archives.json.gz',OUT/'reproduction/verify_package.py',OUT/'reproduction/seal_delivery_execution.py']:
    retention['public_file_sha256'][str(path.relative_to(OUT))]=sha(path)
p.write_text(json.dumps(retention,indent=2)+'\n')
p=OUT/'SHA256.json';manifest=json.loads(p.read_bytes());manifest.update(retention['public_file_sha256'])
manifest['retention.json']=sha(OUT/'retention.json');p.write_text(json.dumps(manifest,indent=2)+'\n')
print('delivery evidence sealed',len(paths),'paths',len(objects),'new byte objects',target.stat().st_size,'compressed bytes')
