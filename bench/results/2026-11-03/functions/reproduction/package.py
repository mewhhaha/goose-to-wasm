#!/usr/bin/env python3
"""Bounded Functions retention. Run only after all measurement windows close.

copy-reports copies eight raw reports for chart generation. package seals the
explicit campaign only; it never executes compilers, guests, tests or engines.
"""
from pathlib import Path
import argparse
import gzip
import hashlib
import io
import json
import math
import os
import shutil
import subprocess
import tarfile

from checks import digest, guest_identities, identities, load, require, safe_member, validate_current

HERE = Path(__file__).resolve().parent
TEXT = {'.py','.mjs','.js','.json','.jsonl','.c','.cpp','.h','.hpp','.inc','.cmake','.goose',
        '.patch','.diff','.md','.txt','.yml','.yaml','.out','.log','.stdout','.stderr','.wat','.csv','.lock','.pins',
        '.png','.svg','.webp'}
GUEST = {'.wasm','.cwasm','.bin'}
RAW = {'stdout','stderr','stdin','expected','pins','LICENSE','CMakeLists.txt','Cargo.lock.frozen','SHA256SUMS'}


def save(path, value):
    require(not path.exists(), ('refusing to overwrite', str(path)))
    path.write_text(json.dumps(value, indent=2)+'\n')


def save_gzip(path, value):
    require(not path.exists(), ('refusing to overwrite', str(path)))
    with path.open('wb') as raw:
        with gzip.GzipFile(filename='', fileobj=raw, mode='wb', mtime=0) as stream:
            stream.write(json.dumps(value, separators=(',',':'), sort_keys=True).encode())


class Package:
    def __init__(self, root, spec):
        self.root=root.absolute(); self.build=self.root/'build/functions-hill'; self.spec=spec
        self.output=self.root/spec['output']; self.output.mkdir(parents=True,exist_ok=True)
        require(not (self.output/'retention.json').exists(), 'finished package already exists')
        self.index={'schema':'goose-functions-archives-v1','archives':{},'aliases':{},'omitted':{},
                    'claims':{},'evidence_documents':{},'source_stages':{},'required_guests':{},
                    'public_bindings':{},'opaque_context':[],
                    'policy':spec['policy']}
        self.objects={}; self.prior={}; self.prior_by_sha={}

    def absolute(self, path):
        path=Path(path)
        if not path.is_absolute(): path=self.root/path
        return path.absolute()

    def reports(self):
        return {name:load(self.build/origin) for name,origin in self.spec['reports'].items()}

    def copy_reports(self):
        reports=self.reports(); reference=load(self.root/self.spec['reference'])
        validate_current(reports,reference,self.spec['compiler_sha256'])
        for name,origin in self.spec['reports'].items():
            source=self.build/origin; target=self.output/name
            if target.exists(): require(digest(target)==digest(source), ('existing report differs',name))
            else: shutil.copyfile(source,target)
        for name,origin in self.spec.get('extra_public_reports',{}).items():
            source=self.build/origin;target=self.output/name
            require(target.is_file() and digest(source)==digest(target), ('public extra report differs',name))
        reference_source=self.root/self.spec['reference']; reference_target=self.output/'references.json'
        require(digest(reference_source)==self.spec['reference_sha256'], 'official reference changed')
        if reference_target.exists(): require(digest(reference_target)==self.spec['reference_sha256'], 'public reference differs')
        else: shutil.copyfile(reference_source,reference_target)
        identity={'name':'compact-locals','root':str(self.build/'final'),'compiler_sha256':self.spec['compiler_sha256'],
                  'source':load(self.build/'final/source.json'),'toolchain':load(self.build/'final/toolchain.json'),
                  'binary_retained':False,'rebuild':'Use retained source, patches, toolchain and bootstrap scripts.'}
        require(identity['toolchain']['compiler_sha256']==self.spec['compiler_sha256'], 'public compiler identity differs')
        target=self.output/'compiler-identity.json'
        if target.exists(): require(load(target)==identity, 'existing compiler identity differs')
        else: save(target,identity)

    def load_prior(self):
        source=self.root/self.spec['prior_index']; pins=load(self.build/'qualification/prior-evidence.json')
        require(digest(source)==pins['reports'][str(source)], 'published prior index changed')
        self.prior=load(source)
        self.index['prior_index']={'path':str(source),'sha256':digest(source)}
        for location in self.prior['aliases'].values():
            self.prior_by_sha.setdefault(location['sha256'], location)

    def reuse(self, original, expected):
        location=self.prior_by_sha[expected]; old=self.prior['archives'][location['archive']]
        archive=(self.root/self.spec['prior_index']).parent/location['archive']
        archive=archive.resolve()
        name=os.path.relpath(archive,self.output)
        record=self.index['archives'].setdefault(name, {'sha256':old['sha256'], 'bytes':old['bytes'],
                                                       'historical':True,'members':{}})
        require(record['sha256']==old['sha256'], 'historical archive collision')
        item=old['members'][location['member']]
        record['members'][location['member']]=item
        result={'archive':name,'member':location['member'],**item}
        self.index['aliases'][original+'@'+expected]=result
        return result

    def add(self, path, expected=None, original=None):
        path=self.absolute(path)
        if original is None: original=str(path)
        actual=digest(path)
        require(expected is None or actual==expected, ('retained file differs',str(path),expected))
        key=original+'@'+actual
        if key in self.index['aliases']: return self.index['aliases'][key]
        if actual in self.prior_by_sha: return self.reuse(original,actual)
        if actual not in self.objects:
            self.objects[actual]={'path':str(path),'sha256':actual,'bytes':path.stat().st_size,
                                  'member':'objects/'+actual+'/'+path.name}
        obj=self.objects[actual]
        result={'object':actual,'member':obj['member'],'sha256':actual,'bytes':obj['bytes']}
        self.index['aliases'][key]=result
        return result

    def omission_reason(self, path):
        text=str(path)
        for component in ('/build/source/','/build/emsdk/','/build/em-cache/','/cargo-target/','/target/',
                          '/source-extraction/','/native/','/build/wasmtime-host/'):
            if component in text: return 'Pinned rebuildable SDK/upstream/build dependency; tree deliberately omitted.'
        if '/bench/results/' in text: return 'Separately published historical context; no recursive report closure.'
        if path.suffix in {'.a','.so','.xz','.zip','.exe'} or '.so.' in path.name:
            return 'Pinned engine, SDK, or tool binary; rebuild/install from retained identities.'
        if '/bin/' in text or '/.venv/' in text or '/usr/' in text or '/none-screen/host' in text or '/winch-screen/host' in text:
            return 'Pinned compiler, host, or tool executable; not a measured guest.'
        return None

    def resolve(self, original, expected, role='input'):
        path=self.absolute(original); original=str(original); key=original+'@'+expected
        if key in self.index['aliases']: return self.index['aliases'][key]
        if expected in self.prior_by_sha: return self.reuse(original,expected)
        reason=self.omission_reason(path)
        if role!='guest' and reason:
            self.index['omitted'][key]={'original':original,'sha256':expected,'reason':reason,'category':'dependency-or-tool'}
            return None
        if path.is_file() and digest(path)==expected: return self.add(path,expected,original)
        # Only minimal source-stage trees are eligible alternate versions.
        for folder in self.spec['source_stages'].values():
            for candidate in (self.build/folder/'compiler'/path.name,self.build/folder/path.name):
                if candidate.is_file() and digest(candidate)==expected: return self.add(candidate,expected,original)
        raise RuntimeError(('required identity unavailable',role,original,expected))

    def document(self, path, claim=False):
        value=load(path); location=self.add(path)
        if claim: self.index['claims'][str(self.absolute(path))]=location
        else: self.index['evidence_documents'][str(self.absolute(path))]=location
        guests=list(guest_identities(value))
        for original,expected in guests:
            if original is not None:
                self.resolve(original,expected,'guest')
            else:
                require(expected in self.objects or expected in self.prior_by_sha,
                        ('anonymous guest bytes unavailable',str(path),expected))
            self.index['required_guests'][expected]=True
        for original,expected in identities(value): self.resolve(original,expected)
        return value

    def scan(self, folder):
        require(folder.is_dir(), ('required bounded tree missing',str(folder)))
        # os.walk pruning prevents traversal of snapshots, SDKs, and native/Rust build trees.
        for directory, children, files in os.walk(folder):
            children[:]=sorted(name for name in children if name not in
                {'source','source-extraction','target','cargo-target','sdk-full','sdk-min','node_modules','.git','__pycache__'})
            for name in sorted(files):
                path=Path(directory)/name
                if path.is_symlink(): continue
                if path.suffix in TEXT|GUEST or name in RAW:
                    self.add(path)
                    if 'packag' in name and path.suffix=='.log': self.index['opaque_context'].append(str(path))
                else:
                    expected=digest(path)
                    self.index['omitted'][str(path)+'@'+expected]={'original':str(path),'sha256':expected,
                        'category':'unneeded-binary-output','reason':'Bounded scan output is not a measured .bin/.wasm/.cwasm guest or reproduction source.'}

    def source_stage(self, label, folder):
        folder=self.build/folder; manifest=load(folder/'source.json'); toolchain=load(folder/'toolchain.json')
        require(len(manifest['headers'])==32 and len(manifest['patches'])==2, ('minimal source inventory',label))
        require(manifest['headers']==toolchain['headers'] and manifest['patches']==toolchain['patches'], 'source/toolchain mismatch')
        stage={'compiler_sha256':toolchain['compiler_sha256'],'headers':{},'patches':{},
               'source':self.add(folder/'source.json'),'toolchain':self.add(folder/'toolchain.json')}
        for name,expected in manifest['headers'].items():
            original=folder/'compiler'/name
            stage['headers'][name]=self.resolve(original,expected,'source')
        for name,expected in manifest['patches'].items(): stage['patches'][name]=self.resolve(name,expected,'source')
        self.index['source_stages'][label]=stage

    def collect(self):
        self.load_prior(); self.copy_reports()
        catalog=load(self.build/'qualification/attempt-1/artifact-catalog.json')
        require(catalog['status']=='catalogued', 'qualification artifact catalog incomplete')
        # Resolve measured qualification guests first, before tool omission rules.
        for expected,row in catalog['objects'].items():
            for original in row['fresh_paths']: self.resolve(original,expected,'guest')
        for folder in self.spec['trees']+self.spec['screens']: self.scan(self.build/folder)
        for name in self.spec.get('extra_files',[]): self.add(self.build/name)
        for path in sorted(self.build.iterdir()):
            if path.is_file() and path.suffix in TEXT:
                self.add(path)
                if 'packag' in path.name and path.suffix=='.log': self.index['opaque_context'].append(str(path))
        for name,origin in self.spec['reports'].items(): self.document(self.build/origin,True)
        for folder in self.spec['screens']: self.document(self.build/folder/'report.json')
        for origin in self.spec.get('evidence_reports',[]): self.document(self.build/origin)
        self.document(self.build/'experiments.json')
        self.document(self.build/'qualification/attempt-1/selected.json')
        self.document(self.build/'qualification/attempt-1/input-pins.json')
        for label,folder in self.spec['source_stages'].items(): self.source_stage(label,folder)
        self.document(self.output/'compiler-identity.json')
        for name,origin in self.spec.get('extra_public_reports',{}).items(): self.add(self.output/name,digest(self.build/origin))
        reference=self.root/self.spec['reference']
        require(digest(reference)==self.spec['reference_sha256'], 'official reference changed')
        # Reference is an immutable leaf, not a request to recursively close its history.
        self.add(reference)
        tracked=subprocess.run(['git','ls-files','-z','scripts','tests','bench','oracle','host','.github','toolchain.json',
                                'requirements.txt','docs/capabilities.json'],cwd=self.root,check=True,capture_output=True).stdout
        for raw in tracked.split(b'\0'):
            if not raw: continue
            name=os.fsdecode(raw);path=self.root/name
            if '/results/' in name or '/charts/' in name: continue
            if path.suffix in TEXT or path.name in RAW: self.add(path)
        for name in self.spec['required_public_files']: require((self.output/name).is_file(), ('derived public file required',name))
        for name in self.spec['public_files']: self.index['public_bindings'][name]=self.add(self.root/name)
        for path in HERE.glob('*.py'): self.add(path)
        self.add(HERE/'spec.json')

    def archives(self):
        limit=self.spec['maximum_raw_archive_bytes']; groups=[]; group=[]; raw_size=10240
        for expected,obj in sorted(self.objects.items()):
            size=512+math.ceil(obj['bytes']/512)*512
            require(size+10240<=limit, ('single object exceeds raw archive bound',obj['path']))
            if raw_size+size>limit: groups.append(group);group=[];raw_size=10240
            group.append(expected);raw_size+=size
        if group: groups.append(group)
        for number,group in enumerate(groups):
            name=f'evidence-{number:03}.tar.gz'; target=self.output/name
            require(not target.exists(), ('refusing to overwrite archive',name))
            members={}
            with target.open('wb') as raw:
                with gzip.GzipFile(filename='',fileobj=raw,mode='wb',mtime=0,compresslevel=6) as compressed:
                    with tarfile.open(fileobj=compressed,mode='w|',format=tarfile.USTAR_FORMAT) as archive:
                        for expected in group:
                            obj=self.objects[expected];path=Path(obj['path'])
                            require(digest(path)==expected, ('source changed before archive',str(path)))
                            info=tarfile.TarInfo(obj['member']);info.size=obj['bytes'];info.mode=0o644
                            with path.open('rb') as stream: archive.addfile(info,stream)
                            members[obj['member']]={'sha256':expected,'bytes':obj['bytes']}
                            obj['archive']=name
            require(target.stat().st_size<100*1024*1024, ('Git file size cap',name))
            self.index['archives'][name]={'sha256':digest(target),'bytes':target.stat().st_size,
                                          'historical':False,'members':members}
        def patch(value):
            if isinstance(value,dict):
                if 'object' in value:
                    value['archive']=self.objects[value.pop('object')]['archive']
                for item in value.values(): patch(item)
            elif isinstance(value,list):
                for item in value: patch(item)
        patch(self.index)

    def seal(self):
        self.collect(); self.archives(); save_gzip(self.output/'archives.json.gz',self.index)
        public={}
        for path in sorted(self.output.iterdir()):
            if path.is_file(): public[path.name]=digest(path)
        save(self.output/'retention.json',{'schema':'goose-functions-retention-v1','compiler_sha256':self.spec['compiler_sha256'],
            'reference_sha256':self.spec['reference_sha256'],'reference':os.path.relpath(self.root/self.spec['reference'],self.output),
            'archive_index':'archives.json.gz','report_origins':self.spec['reports'],'public_file_sha256':public,
            'maximum_raw_archive_bytes':self.spec['maximum_raw_archive_bytes'],'specification':self.spec})
        public['retention.json']=digest(self.output/'retention.json')
        save(self.output/'SHA256.json',public)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase',choices=('copy-reports','package'))
    parser.add_argument('--root',type=Path,default=Path('/home/jacobt/src/goose-to-wasm'))
    parser.add_argument('--spec',type=Path,default=HERE/'spec.json')
    args=parser.parse_args(); package=Package(args.root,load(args.spec))
    if args.phase=='copy-reports': package.copy_reports()
    else: package.seal()


if __name__=='__main__': main()
