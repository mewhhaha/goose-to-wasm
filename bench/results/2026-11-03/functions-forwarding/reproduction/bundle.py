#!/usr/bin/env python3
"""Fresh bounded forwarding evidence. Execute only after timing windows close."""
from pathlib import Path
import argparse
import gzip
import hashlib
import json
import math
import os
import shutil
import subprocess
import tarfile

from checks import SHA, digest, guest_identities, load, require, safe_member, validate_current

HERE=Path(__file__).resolve().parent
TEXT={'.py','.mjs','.js','.json','.jsonl','.c','.cpp','.h','.hpp','.inc','.cmake','.goose','.patch','.diff',
      '.md','.txt','.yml','.yaml','.out','.log','.stdout','.stderr','.wat','.csv','.lock','.pins','.png','.svg','.webp'}
GUEST={'.wasm','.cwasm','.bin'}
RAW={'stdout','stderr','stdin','expected','pins','LICENSE','CMakeLists.txt','Cargo.lock.frozen','SHA256SUMS'}


def compressed(path,value):
    with path.open('wb') as raw:
        with gzip.GzipFile(filename='',fileobj=raw,mode='wb',mtime=0) as stream:
            stream.write(json.dumps(value,sort_keys=True,separators=(',',':')).encode())


def fingerprints(value):
    """Only explicit current-document path/SHA pairs; never follow a document."""
    if isinstance(value,dict):
        for original,expected in value.items():
            if isinstance(expected,str) and SHA.fullmatch(expected) and ('/' in original or Path(original).suffix):
                yield original,expected
        for path,sha in [('path','sha256'),('artifact','artifact_sha256'),('artifact','sha256'),
                         ('aot_path','aot_sha256'),('precompiled','precompiled_sha256'),
                         ('module','wasm_sha256'),('wasm','wasm_sha256'),('wasm','sha256'),('aot','aot_sha256'),('source','source_sha256'),
                         ('library','library_sha256'),('sdk_archive','sdk_archive_sha256'),
                         ('host','host_sha256'),('compiler','compiler_sha256')]:
            original=value.get(path);expected=value.get(sha)
            if isinstance(original,str) and isinstance(expected,str) and SHA.fullmatch(expected):
                yield original,expected
        for item in value.values():yield from fingerprints(item)
    elif isinstance(value,list):
        for item in value:yield from fingerprints(item)


class Bundle:
    def __init__(self,root,spec):
        self.root=root.absolute();self.spec=spec;self.build=self.root/spec['build'];self.out=self.root/spec['output']
        self.out.mkdir(parents=True,exist_ok=True)
        require(not (self.out/'retention.json').exists(),'finished bundle already exists')
        self.objects={};self.by_path={};self.index={'schema':'goose-forwarding-objects-v1','archives':{},'aliases':{},
            'omitted':{},'documents':{},'source_stages':{},'public_bindings':{},'guests':{},
            'required_guests':{},'policy':spec['policy']}

    def absolute(self,path):
        path=Path(path)
        if not path.is_absolute():path=self.root/path
        return path.absolute()

    def add(self,path,expected=None,original=None):
        path=self.absolute(path)
        if original is None:original=str(path)
        value=self.by_path.get(str(path))
        if value is None:value=digest(path);self.by_path[str(path)]=value
        require(expected is None or value==expected,('file identity differs',str(path),expected))
        if value not in self.objects:
            self.objects[value]={'path':str(path),'sha256':value,'bytes':path.stat().st_size,
                                 'member':'objects/'+value+'/'+path.name}
        obj=self.objects[value];location={'object':value,'sha256':value,'bytes':obj['bytes'],'member':obj['member']}
        key=str(original)+'@'+value;self.index['omitted'].pop(key,None)
        self.index['aliases'][key]=location
        if path.suffix in GUEST:self.index['guests'][value]=True
        return location

    def omission(self,path):
        text=str(path)
        if '/build/source/' in text or '/build/native/' in text or '/build/wasmtime-host/' in text or '/build/emsdk/' in text or '/build/em-cache/' in text:
            return 'Pinned upstream/SDK/build dependency; rebuild from retained revision, patches, tools and configuration.'
        if path.suffix in {'.a','.so','.xz','.zip','.exe','.dylib','.dll'} or '.so.' in path.name:
            return 'Pinned compiler/engine/SDK/tool binary; not a measured guest.'
        if path.name=='archives.json.gz':return 'Historical machine index identity only; no prior aliases or archives are imported.'
        if path.suffix not in TEXT and ('/bin/' in text or '/usr/' in text or '/.venv/' in text):
            return 'Pinned compiler, host or tool executable; not a measured guest.'
        return None

    def resolve(self,original,expected):
        original=str(original);key=original+'@'+expected;path=self.absolute(original)
        if key in self.index['aliases'] or key in self.index['omitted']:return
        if path.suffix in GUEST:
            require(path.is_file(),('required guest unavailable',original,expected));self.add(path,expected,original);return
        reason=self.omission(path)
        if reason:
            self.index['omitted'][key]={'original':original,'sha256':expected,'reason':reason};return
        if expected in self.objects:
            obj=self.objects[expected]
            self.index['aliases'][key]={'object':expected,'sha256':expected,'bytes':obj['bytes'],'member':obj['member']};return
        if not path.is_file() and not Path(original).is_absolute():
            for base in (self.root/'build/source',self.root/'build/langarena-upstream'):
                candidate=(base/original).resolve()
                if candidate.is_relative_to(base.resolve()) and candidate.is_file() and digest(candidate)==expected:
                    self.add(candidate,expected,original);return
        require(path.is_file(),('required source/input unavailable',original,expected))
        self.add(path,expected,original)

    def document(self,path):
        path=self.absolute(path);value=load(path);self.index['documents'][str(path)]=self.add(path)
        for original,expected in guest_identities(value):
            self.index['required_guests'][expected]=True
            if original is not None:
                candidate=self.absolute(original)
                require(candidate.is_file(),('required measured guest unavailable',original,expected))
                self.add(candidate,expected,original);self.index['guests'][expected]=True
        # The document is a declared current report/review, so only its explicit
        # identity pairs are resolved. Resolved JSON files remain opaque leaves.
        for original,expected in fingerprints(value):self.resolve(original,expected)

    def scan(self,folder):
        require(folder.is_dir(),('bounded campaign tree missing',str(folder)))
        for directory,children,files in os.walk(folder):
            children[:]=sorted(name for name in children if name not in
                {'source','source-extraction','target','cargo-target','sdk-full','sdk-min','bin','node_modules','.git','__pycache__'})
            for name in sorted(files):
                path=Path(directory)/name
                if path.is_symlink():continue
                if path.suffix in TEXT|GUEST or name in RAW:self.add(path)

    def copy_reports(self):
        reports={name:load(self.build/origin) for name,origin in self.spec['reports'].items()}
        reference=self.root/self.spec['reference'];require(digest(reference)==self.spec['reference_sha256'],'reference changed')
        validate_current(reports,load(reference),self.spec['compiler_sha256'])
        for name,origin in self.spec['reports'].items():
            source=self.build/origin;target=self.out/name
            if target.exists():require(digest(target)==digest(source),('existing raw public report differs',name))
            else:shutil.copyfile(source,target)
        for name,origin in self.spec['extra_reports'].items():
            source=self.build/origin;target=self.out/name
            require(source.is_file(),('holdout report not yet complete',origin))
            require(load(source)['status']=='passed',('holdout report failed',origin))
            if target.exists():require(digest(source)==digest(target),('existing holdout copy differs',name))
            else:shutil.copyfile(source,target)
        target=self.out/'references.json'
        if target.exists():require(digest(target)==self.spec['reference_sha256'],'public reference differs')
        else:shutil.copyfile(reference,target)
        folder=self.root/self.spec['source_stages']['final']
        identity={'name':'function-value-forwarding','root':str(folder),'compiler_sha256':self.spec['compiler_sha256'],
                  'source':load(folder/'source.json'),'toolchain':load(folder/'toolchain.json'),
                  'binary_retained':False,'rebuild':'Use retained32headers,2patches,toolchain metadata and bootstrap helpers.'}
        target=self.out/'compiler-identity.json'
        if target.exists():require(load(target)==identity,'compiler identity changed')
        else:target.write_text(json.dumps(identity,indent=2)+'\n')

    def source_stage(self,label,origin):
        folder=self.root/origin;source=load(folder/'source.json');toolchain=load(folder/'toolchain.json')
        require(len(source['headers'])==32 and len(source['patches'])==2,('stage source inventory',label))
        require(source['headers']==toolchain['headers'] and source['patches']==toolchain['patches'],'stage source/toolchain mismatch')
        stage={'compiler_sha256':toolchain['compiler_sha256'],'source':self.add(folder/'source.json'),
               'toolchain':self.add(folder/'toolchain.json'),'headers':{},'patches':{}}
        for name,expected in source['headers'].items():stage['headers'][name]=self.add(folder/'compiler'/name,expected)
        for name,expected in source['patches'].items():
            candidate=folder/name
            if not candidate.is_file():candidate=self.root/name
            stage['patches'][name]=self.add(candidate,expected)
        binary=str(folder/'bin/goose');value=toolchain['compiler_sha256']
        self.index['omitted'][binary+'@'+value]={'original':binary,'sha256':value,'reason':'Compiler executable identity; source and build metadata retained.'}
        self.index['source_stages'][label]=stage

    def collect(self):
        self.copy_reports()
        for folder in self.spec['trees']:self.scan(self.build/folder)
        for folder in self.spec['optional_trees']:
            if (self.build/folder).is_dir():self.scan(self.build/folder)
        for path in sorted(self.build.iterdir()):
            if path.is_file() and path.suffix in TEXT:self.add(path)
        q=self.build/'qualification'
        for path in sorted(q.iterdir()):
            if path.is_file() and path.suffix in TEXT:self.add(path)
        control=q/'resource-control';self.scan(control/'shadow')
        for path in sorted(control.iterdir()):
            if path.is_file() and path.suffix in TEXT:self.add(path)
        for name in ['source.json','toolchain.json','control-toolchain-match.json']:self.add(control/'build'/name)
        self.scan(control/'build/compiler')
        self.add(control/'build/native/CMakeCache.txt')
        for label,origin in self.spec['source_stages'].items():self.source_stage(label,origin)
        for origin in self.spec['reports'].values():self.document(self.build/origin)
        for origin in self.spec['evidence_documents']:self.document(self.build/origin)
        for origin in self.spec['optional_evidence_documents']:
            if (self.build/origin).is_file():self.document(self.build/origin)
        for name,origin in self.spec['extra_reports'].items():self.add(self.out/name,digest(self.build/origin))
        for name in self.spec['direct_files']:self.add(self.root/name)
        self.add(self.root/self.spec['reference'])
        tracked=subprocess.run(['git','ls-files','-z','scripts','tests','bench','oracle','host','.github','toolchain.json','requirements.txt','docs/capabilities.json'],
                               cwd=self.root,check=True,capture_output=True).stdout
        for raw in tracked.split(b'\0'):
            if not raw:continue
            name=os.fsdecode(raw);path=self.root/name
            if '/results/' in name or '/charts/' in name:continue
            if path.suffix in TEXT or path.name in RAW:self.add(path)
        for name in self.spec['required_public_files']:require((self.out/name).is_file(),('public derivation missing',name))
        for name in self.spec['public_files']:self.index['public_bindings'][name]=self.add(self.root/name)
        for path in HERE.iterdir():
            if path.is_file() and path.suffix in {'.py','.json'}:self.add(path)

    def archive(self):
        groups=[];group=[];size=10240;limit=self.spec['max_raw_archive_bytes']
        for value,obj in sorted(self.objects.items()):
            added=512+math.ceil(obj['bytes']/512)*512;require(added+10240<=limit,('object exceeds archive bound',obj['path']))
            if size+added>limit:groups.append(group);group=[];size=10240
            group.append(value);size+=added
        if group:groups.append(group)
        for number,group in enumerate(groups):
            name=f'evidence-{number:03}.tar.gz';target=self.out/name;require(not target.exists(),('archive exists',name));members={}
            with target.open('wb') as raw:
                with gzip.GzipFile(filename='',fileobj=raw,mode='wb',mtime=0,compresslevel=6) as stream:
                    with tarfile.open(fileobj=stream,mode='w|',format=tarfile.USTAR_FORMAT) as archive:
                        for value in group:
                            obj=self.objects[value];path=Path(obj['path']);require(digest(path)==value,('input changed during capture',str(path)))
                            info=tarfile.TarInfo(obj['member']);info.size=obj['bytes'];info.mode=0o644
                            with path.open('rb') as source:archive.addfile(info,source)
                            members[obj['member']]={'sha256':value,'bytes':obj['bytes']};obj['archive']=name
            require(target.stat().st_size<100*1024*1024,('Git file cap',name))
            self.index['archives'][name]={'sha256':digest(target),'bytes':target.stat().st_size,'members':members}
        def locate(value):
            if isinstance(value,dict):
                if 'object' in value:value['archive']=self.objects[value.pop('object')]['archive']
                for item in value.values():locate(item)
            elif isinstance(value,list):
                for item in value:locate(item)
        locate(self.index)

    def seal(self):
        self.collect()
        helpers=self.out/'reproduction';helpers.mkdir(exist_ok=True)
        for name in ('bundle.py','verify.py','checks.py','spec.json'):
            source=HERE/name;target=helpers/name
            if target.exists():require(digest(source)==digest(target),('existing reproduction helper differs',name))
            else:shutil.copyfile(source,target)
            self.add(target)
        self.archive();compressed(self.out/'archives.json.gz',self.index)
        public={str(path.relative_to(self.out)):digest(path) for path in self.out.rglob('*') if path.is_file() and '__pycache__' not in path.parts}
        retention={'schema':'goose-forwarding-retention-v1','specification':self.spec,'archive_index':'archives.json.gz',
                   'compiler_sha256':self.spec['compiler_sha256'],'public_file_sha256':public}
        (self.out/'retention.json').write_text(json.dumps(retention,indent=2)+'\n')
        public['retention.json']=digest(self.out/'retention.json');(self.out/'SHA256.json').write_text(json.dumps(public,indent=2)+'\n')


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('phase',choices=['copy-reports','package'])
    parser.add_argument('--root',type=Path,default=Path('/home/jacobt/src/goose-to-wasm'))
    parser.add_argument('--spec',type=Path,default=HERE/'spec.json');args=parser.parse_args();bundle=Bundle(args.root,load(args.spec))
    if args.phase=='copy-reports':bundle.copy_reports()
    else:bundle.seal()


if __name__=='__main__':main()
