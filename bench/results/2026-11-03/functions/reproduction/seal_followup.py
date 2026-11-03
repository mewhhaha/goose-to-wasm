"""Retain only the finite post-capture verifier corrections and their logs."""
from pathlib import Path
import gzip
import hashlib
import json
import shutil
import tarfile

ROOT=Path.cwd();BASE=ROOT/'build/functions-hill';OUT=ROOT/'bench/results/2026-11-03/functions'

def sha(path):
    with path.open('rb') as stream: return hashlib.file_digest(stream,'sha256').hexdigest()

def compressed(path,value):
    with path.open('wb') as raw:
        with gzip.GzipFile(filename='',fileobj=raw,mode='wb',mtime=0) as stream:
            stream.write(json.dumps(value,separators=(',',':'),sort_keys=True).encode())

attempt=BASE/'packaging-attempts/attempt-02'
paths=[attempt/name for name in ['verify-before-linear-fix.py','verify-before-linear-fix.log',
    'verify-before-campaign-schema-fix.py','verify-campaign-schema-mismatch.log']]
paths += [BASE/'delivery-package/verify_package.py',Path(__file__).absolute()]
shutil.copyfile(Path(__file__),OUT/'reproduction/seal_followup.py')
with gzip.open(OUT/'archives.json.gz','rt') as stream: index=json.load(stream)
name='evidence-packaging-followup.tar.gz';target=OUT/name
assert not target.exists()
members={}
with target.open('wb') as raw:
    with gzip.GzipFile(filename='',fileobj=raw,mode='wb',mtime=0) as compressed_stream:
        with tarfile.open(fileobj=compressed_stream,mode='w|',format=tarfile.USTAR_FORMAT) as archive:
            for number,path in enumerate(paths):
                expected=sha(path);member=f'followup/{number:03}-{path.name}'
                info=tarfile.TarInfo(member);info.size=path.stat().st_size;info.mode=0o644
                with path.open('rb') as stream: archive.addfile(info,stream)
                item={'sha256':expected,'bytes':info.size};members[member]=item
                index['aliases'][str(path)+'@'+expected]={'archive':name,'member':member,**item}
                if path.suffix=='.log': index['opaque_context'].append(str(path))
index['archives'][name]={'sha256':sha(target),'bytes':target.stat().st_size,'historical':False,'members':members}
compressed(OUT/'archives.json.gz',index)
p=OUT/'retention.json';retention=json.loads(p.read_text())
retention['current_reproduction']['reason']='Standalone verifier hashes each report once, reads each gzip member once, and validates the actual measured-and-qualified campaign schema. Earlier sources/failure logs remain archived; raw evidence was not rewritten.'
retention['public_file_sha256'].update({name:sha(target),'archives.json.gz':sha(OUT/'archives.json.gz'),
    'reproduction/seal_followup.py':sha(OUT/'reproduction/seal_followup.py')})
p.write_text(json.dumps(retention,indent=2)+'\n')
p=OUT/'SHA256.json';manifest=json.loads(p.read_text())
manifest.update(retention['public_file_sha256']);manifest['retention.json']=sha(OUT/'retention.json')
p.write_text(json.dumps(manifest,indent=2)+'\n')
print('follow-up sealed',len(paths),'files',target.stat().st_size,'bytes')
