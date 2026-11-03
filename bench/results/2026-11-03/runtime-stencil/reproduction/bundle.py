#!/usr/bin/env python3
"""Bounded incremental runtime-stencil evidence. Execute only after timing windows close."""
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
import sys
from dataclasses import asdict

from checks import SHA, digest, guest_identities, load, require, safe_member, validate_current, validate_lifecycle, validate_presentation

HERE=Path(__file__).resolve().parent
TEXT={'.py','.mjs','.js','.json','.jsonl','.c','.cpp','.h','.hpp','.inc','.cmake','.goose','.patch','.diff',
      '.md','.txt','.yml','.yaml','.out','.log','.stdout','.stderr','.wat','.csv','.lock','.pins','.png','.svg','.webp','.gdb','.toml'}
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
            if isinstance(expected,dict) and isinstance(expected.get('sha256'),str) and SHA.fullmatch(expected['sha256']) and '/' in original:
                yield original,expected['sha256']
        for path,sha in [('path','sha256'),('artifact','artifact_sha256'),('artifact','sha256'),
                         ('aot_path','aot_sha256'),('precompiled','precompiled_sha256'),
                         ('module','wasm_sha256'),('wasm','wasm_sha256'),('wasm','sha256'),('aot','aot_sha256'),('source','source_sha256'),
                         ('library','library_sha256'),('sdk_archive','sdk_archive_sha256'),
                         ('host','host_sha256'),('compiler','compiler_sha256'),('cache_config','cache_config_sha256')]:
            original=value.get(path);expected=value.get(sha)
            if isinstance(original,str) and isinstance(expected,str) and SHA.fullmatch(expected):
                if path=='compiler' and '/' not in original and not Path(original).suffix:
                    continue
                yield original,expected
        for item in value.values():yield from fingerprints(item)
    elif isinstance(value,list):
        for item in value:yield from fingerprints(item)


class Bundle:
    def __init__(self,root,spec):
        self.root=root.absolute();self.spec=spec;self.build=self.root/spec['build'];self.out=self.root/spec['output']
        self.out.mkdir(parents=True,exist_ok=True)
        require(not (self.out/'retention.json').exists(),'finished bundle already exists')
        self.objects={};self.reused={};self.prior_objects={};self.by_path={}
        self.index={'schema':'goose-runtime-stencil-objects-v1','archives':{},'aliases':{},
            'omitted':{},'documents':{},'source_stages':{},'public_bindings':{},'guests':{},
            'required_guests':{},'controls':{},'host_stages':{},'engine_cache_files':{},'policy':spec['policy']}

    def load_prior(self):
        reuse=self.spec['reuse'];path=self.root/reuse['index'];manifest=load(self.root/reuse['manifest'])
        expected=manifest['archives.json.gz'];require(digest(path)==expected,'immediate prior index changed')
        prior=load(path)
        require(prior['schema']==reuse['index_schema'],'prior index is not the declared calls bundle')
        require(set(prior['archives'])==set(reuse['archives']),'prior archive inventory differs')
        for name,record in sorted(prior['archives'].items()):
            location=reuse['archives'][name]
            parts=Path(location).parts
            require(len(parts)==3 and parts[0]=='..' and parts[1] in {'fresh-construction','functions-calls','functions-forwarding'},
                    'prior archive escapes bounded publications')
            safe_member(parts[2])
            for member,item in sorted(record['members'].items()):
                safe_member(member)
                self.prior_objects.setdefault(item['sha256'],{'archive':location,'member':member,**item,
                    'archive_sha256':record['sha256'],'archive_bytes':record['bytes']})
        self.index['reuse_source']={'index':reuse['index'],'sha256':expected,
            'scope':'Only archive/member byte identities were read; zero prior aliases or documents imported.'}

    def known_location(self,value):
        if value in self.objects:
            obj=self.objects[value]
            return {'object':value,'sha256':value,'bytes':obj['bytes'],'member':obj['member']}
        if value not in self.reused:
            item=self.prior_objects[value];name=item['archive']
            record=self.index['archives'].setdefault(name,{'external':True,'sha256':item['archive_sha256'],
                'bytes':item['archive_bytes'],'members':{}})
            record['members'][item['member']]={'sha256':value,'bytes':item['bytes']}
            self.reused[value]={'archive':name,'member':item['member'],'sha256':value,'bytes':item['bytes']}
        return dict(self.reused[value])

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
        if value not in self.objects and value not in self.prior_objects:
            self.objects[value]={'path':str(path),'sha256':value,'bytes':path.stat().st_size,
                                 'member':'objects/'+value+'/'+path.name}
        location=self.known_location(value)
        key=str(original)+'@'+value;self.index['omitted'].pop(key,None)
        self.index['aliases'][key]=location
        if path.suffix in GUEST:self.index['guests'][value]=True
        return location

    def omission(self,path):
        text=str(path)
        if path.name in {'goose','goose-wasmtime'}:
            return 'Pinned compiler or native host executable; source/build identities retained, not a measured guest.'
        if '/build/source/' in text or '/build/native/' in text or '/build/wasmtime-host/' in text or '/build/emsdk/' in text or '/build/em-cache/' in text:
            return 'Pinned upstream/SDK/build dependency; rebuild from retained revision, patches, tools and configuration.'
        if path.suffix in {'.a','.so','.xz','.zip','.exe','.dylib','.dll'} or '.so.' in path.name:
            return 'Pinned compiler/engine/SDK/tool binary; not a measured guest.'
        if path.name=='archives.json.gz':return 'Historical index identity only; no prior alias namespace or historical documents are imported.'
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
        if expected in self.objects or expected in self.prior_objects:
            self.index['aliases'][key]=self.known_location(expected);return
        if not path.is_file() and not Path(original).is_absolute():
            for base in (self.root/'build/source',self.root/'build/langarena-upstream'):
                candidate=(base/original).resolve()
                if candidate.is_relative_to(base.resolve()) and candidate.is_file() and digest(candidate)==expected:
                    self.add(candidate,expected,original);return
        require(path.is_file(),('required source/input unavailable',original,expected))
        self.add(path,expected,original)

    def document(self,path):
        path=self.absolute(path);value=load(path);self.index['documents'][str(path)]=self.add(path)
        for original,item in value.get('final_cache_file_manifest',{}).items():
            location=self.add(original,item['sha256'])
            self.index['engine_cache_files'][original]={'kind':item['kind'],**location}
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

    def copy_reports(self,complete=False):
        reports={name:load(self.build/origin) for name,origin in self.spec['reports'].items()}
        reference=self.root/self.spec['reference'];require(digest(reference)==self.spec['reference_sha256'],'reference changed')
        validate_current(reports,load(reference),self.spec['compiler_sha256'])
        validate_lifecycle(reports['lifecycle.json'],reports,self.spec['compiler_sha256'])
        for name,origin in self.spec['reports'].items():
            source=self.build/origin;target=self.out/name
            if target.exists():require(digest(target)==digest(source),('existing raw public report differs',name))
            else:shutil.copyfile(source,target)
        for name,origin in self.spec['extra_reports'].items():
            source=self.build/origin;target=self.out/name
            require(source.is_file(),('worker report not yet complete',origin))
            require(load(source)['status']=='passed',('worker report failed',origin))
            if target.exists():require(digest(source)==digest(target),('existing worker copy differs',name))
            else:shutil.copyfile(source,target)
        metadata=dict(self.spec['public_metadata'])
        metadata.update({name:origin for name,origin in self.spec['optional_public_metadata'].items()
                         if (self.build/origin).is_file()})
        for name,origin in metadata.items():
            source=self.build/origin;target=self.out/name
            if not source.is_file():
                require(not complete,('public evidence not yet complete',origin))
                continue
            if target.exists():require(digest(source)==digest(target),('existing public evidence copy differs',name))
            else:shutil.copyfile(source,target)
        target=self.out/'references.json'
        if target.exists():require(digest(target)==self.spec['reference_sha256'],'public reference differs')
        else:shutil.copyfile(reference,target)
        folder=self.root/self.spec['source_stages']['final']
        identity={'name':'private-snapshots-byte-stencils-and-runtime-reuse','root':str(folder),'compiler_sha256':self.spec['compiler_sha256'],
                  'source':load(folder/'source.json'),'toolchain':load(folder/'toolchain.json'),
                  'binary_retained':False,'rebuild':'Use the declared retained headers/patches, toolchain metadata and bootstrap helpers.'}
        target=self.out/'compiler-identity.json'
        if target.exists():require(load(target)==identity,'compiler identity changed')
        else:target.write_text(json.dumps(identity,indent=2)+'\n')

    def source_stage(self,label,origin):
        folder=self.root/origin;source=load(folder/'source.json');toolchain=load(folder/'toolchain.json')
        require(source['headers'] and source['patches'],('empty stage source inventory',label))
        require(source['headers']==toolchain['headers'] and source['patches']==toolchain['patches'],'stage source/toolchain mismatch')
        stage={'compiler_sha256':toolchain['compiler_sha256'],'source':self.add(folder/'source.json'),
               'toolchain':self.add(folder/'toolchain.json'),'headers':{},'patches':{}}
        for name,expected in source['headers'].items():
            candidates=[folder/'compiler'/name,folder/'headers'/name]
            candidate=next((path for path in candidates if path.is_file()),None)
            require(candidate is not None,('missing declared stage header',label,name))
            stage['headers'][name]=self.add(candidate,expected)
        for name,expected in source['patches'].items():
            candidate=folder/name
            if not candidate.is_file():candidate=self.root/name
            stage['patches'][name]=self.add(candidate,expected)
        if (folder/'O2.wasm').is_file():stage['module']=self.add(folder/'O2.wasm')
        binary=str(folder/'bin/goose');value=toolchain['compiler_sha256']
        self.index['omitted'][binary+'@'+value]={'original':binary,'sha256':value,'reason':'Compiler executable identity; source and build metadata retained.'}
        self.index['source_stages'][label]=stage

    def host_stage(self,label,item):
        for path in item['sources']:self.add(self.root/path)
        metadata=self.root/item['metadata'];value=load(metadata)
        self.document(metadata)
        sources={path:self.add(self.root/path) for path in item['sources']}
        for path,location in sources.items():
            expected={sha for original,sha in value['input_sha256'].items() if Path(original).name==Path(path).name}
            require(expected=={location['sha256']},('host snapshot differs from actual build input',label,path))
        self.index['host_stages'][label]={'metadata':self.add(metadata),'host_sha256':value['host_sha256'],
            'sources':sources}

    def worker_case_inputs(self):
        worker=load(self.build/'qualification/attempt-2/worker-replay/report.json')
        host=load(self.build/'qualification/attempt-2/host/report.json')
        source=self.root/'tests/run_differential.py'
        require(digest(source)==worker['input_sha256'][str(source)],'sealed case source changed')
        sys.path.insert(0,str(self.root/'tests'))
        from run_differential import cases
        values=[asdict(case) for case in cases()]
        canonical=(json.dumps(values,sort_keys=True,indent=2)+'\n').encode()
        require(hashlib.sha256(canonical).hexdigest()==host['case_inputs_sha256'],'derived case inputs differ from qualified host corpus')
        value={'status':'derived-from-sealed-source','source':str(source),'source_sha256':digest(source),
               'case_inputs_sha256':host['case_inputs_sha256'],'cases':json.loads(canonical)}
        target=self.build/'qualification/attempt-2/worker-case-inputs.json'
        if target.exists():require(load(target)==value,'derived worker case inputs changed')
        else:target.write_text(json.dumps(value,indent=2)+'\n')

    def presentation_revision(self):
        path=self.build/self.spec['presentation_followup'];value=load(path)
        before=self.absolute(value['before_snapshot']);after=self.absolute(value['source'])
        validate_presentation(value,before.read_bytes(),after.read_bytes())
        self.index['presentation_revision']={'record':self.add(path),
            'before':self.add(before,value['before_sha256'],value['source']),
            'after':self.add(after,value['after_sha256'],value['source'])}
        pins=load(self.build/self.spec['qualified_input_pins']);sources={};changed=[]
        for original,expected in pins.items():
            source=Path(original)
            if not source.is_relative_to(self.root):continue
            relative=source.relative_to(self.root)
            if relative.parts[0] not in {'compiler','host','scripts','tests','oracle','.github','bench'}:continue
            if relative.parts[:2] in {('bench','results'),('bench','charts')}:continue
            actual=digest(source)
            if actual!=expected:changed.append(original)
            sources[original]={'qualified_sha256':expected,'final_sha256':actual}
            self.add(source,actual)
        require(changed==[value['source']] and pins[value['source']]==value['before_sha256'],
                ('unexpected post-qualification source revision',changed))
        self.index['qualified_source_bindings']=sources

    def collect(self):
        self.load_prior()
        self.copy_reports(complete=True)
        self.worker_case_inputs()
        self.presentation_revision()
        for folder in self.spec['trees']:self.scan(self.build/folder)
        for folder in self.spec['optional_trees']:
            if (self.build/folder).is_dir():self.scan(self.build/folder)
        for path in sorted(self.build.iterdir()):
            if path.is_file() and path.suffix in TEXT:self.add(path)
        for qualification,names in self.spec['qualification_controls'].items():
            q=self.build/qualification
            for path in sorted(q.iterdir()):
                if path.is_file() and path.suffix in TEXT:self.add(path)
            for name in names:
                control=q/name;self.scan(control/'shadow')
                for path in sorted(control.iterdir()):
                    if path.is_file() and path.suffix in TEXT:self.add(path)
                for metadata in ['source.json','toolchain.json','control-toolchain-match.json']:self.add(control/'build'/metadata)
                self.scan(control/'build/compiler');self.add(control/'build/native/CMakeCache.txt')
                toolchain=load(control/'build/toolchain.json')
                self.index['controls'][qualification+'/'+name]={'qualification':qualification,
                    'compiler_sha256':toolchain['compiler_sha256'],
                    'toolchain':self.add(control/'build/toolchain.json'),
                    'match':self.add(control/'build/control-toolchain-match.json'),
                    'headers':{header:self.add(control/'build/compiler'/header,expected)
                               for header,expected in toolchain['headers'].items()}}
        for label,origin in self.spec['source_stages'].items():self.source_stage(label,origin)
        for label,item in self.spec['host_stages'].items():self.host_stage(label,item)
        for origin in self.spec['reports'].values():self.document(self.build/origin)
        for origin in self.spec['evidence_documents']:self.document(self.build/origin)
        for origin in self.spec['optional_evidence_documents']:
            if (self.build/origin).is_file():self.document(self.build/origin)
        for name,origin in self.spec['extra_reports'].items():self.add(self.out/name,digest(self.build/origin))
        metadata=dict(self.spec['public_metadata'])
        metadata.update({name:origin for name,origin in self.spec['optional_public_metadata'].items()
                         if (self.build/origin).is_file()})
        for name,origin in metadata.items():self.add(self.out/name,digest(self.build/origin))
        for name in self.spec['direct_files']:self.add(self.root/name)
        self.add(self.root/self.spec['reference'])
        tracked=subprocess.run(['git','ls-files','-z','scripts','tests','bench','oracle','host','.github','toolchain.json','requirements.txt','docs/capabilities.json'],
                               cwd=self.root,check=True,capture_output=True).stdout
        for raw in tracked.split(b'\0'):
            if not raw:continue
            name=os.fsdecode(raw);path=self.root/name
            if '/results/' in name or '/charts/' in name:continue
            if path.suffix in TEXT or path.name in RAW:self.add(path)
        # This newly added source may still be untracked before final staging.
        for name in ('test_private_snapshot_parameters.py','test_byte_stencil.py','test_runtime_session.py'):
            self.add(self.root/'tests'/name)
        for name in self.spec['required_public_files']:require((self.out/name).is_file(),('public derivation missing',name))
        for name in self.spec['public_files']:self.index['public_bindings'][name]=self.add(self.root/name)
        for path in HERE.iterdir():
            if path.is_file() and path.suffix in {'.py','.json','.md'}:self.add(path)
        if (HERE/'preparation-history').is_dir():self.scan(HERE/'preparation-history')
        self.index['opaque_failed_attempts']=[{'path':str(self.build/name),
            'disposition':'Opaque FAILED ATTEMPT bytes only; metadata is not a valid source/compiler stage.'}
            for name in self.spec['opaque_failed_attempts']]
        self.index['rejected_executions']=[{'path':str(self.build/name),'reason':self.spec['rejection_reason'],
            'disposition':'Immutable rejected performance evidence; not a final primary report.'}
            for name in self.spec['rejected_execution_roots']]

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
            self.index['archives'][name]={'external':False,'sha256':digest(target),'bytes':target.stat().st_size,'members':members}
        def locate(value):
            if isinstance(value,dict):
                if 'object' in value:value['archive']=self.objects[value.pop('object')]['archive']
                for item in value.values():locate(item)
            elif isinstance(value,list):
                for item in value:locate(item)
        locate(self.index)

    def storage_summary(self):
        suffixes={}
        for label,objects in [('new',self.objects),('reused',self.reused)]:
            rows={}
            for obj in objects.values():
                suffix=Path(obj['member']).suffix or '[no suffix]'
                item=rows.setdefault(suffix,{'objects':0,'bytes':0});item['objects']+=1;item['bytes']+=obj['bytes']
            suffixes[label]=rows
        return {'new_objects':len(self.objects),'new_raw_bytes':sum(row['bytes'] for row in self.objects.values()),
                'reused_objects':len(self.reused),'reused_raw_bytes':sum(row['bytes'] for row in self.reused.values()),
                'current_aliases':len(self.index['aliases']),
                'reused_archives':sum(bool(row.get('external')) for row in self.index['archives'].values()),
                'prior_aliases_imported':0,'prior_documents_opened':0,'by_suffix':suffixes,
                'largest_new_objects':[{key:row[key] for key in ('path','sha256','bytes','member')}
                    for row in sorted(self.objects.values(),key=lambda row:-row['bytes'])[:5]]}

    def seal(self):
        require((self.build/self.spec['final_review']).is_file(),'final public review must exist before archive capture')
        require(load(self.build/self.spec['final_review'])['status']=='passed','final public review did not pass')
        self.collect()
        helpers=self.out/'reproduction';helpers.mkdir(exist_ok=True)
        for name in ('bundle.py','verify.py','checks.py','spec.json'):
            source=HERE/name;target=helpers/name
            if target.exists():require(digest(source)==digest(target),('existing reproduction helper differs',name))
            else:shutil.copyfile(source,target)
            self.add(target)
        self.index['storage']=self.storage_summary()
        self.archive();compressed(self.out/'archives.json.gz',self.index)
        public={str(path.relative_to(self.out)):digest(path) for path in self.out.rglob('*') if path.is_file() and '__pycache__' not in path.parts}
        retention={'schema':'goose-runtime-stencil-retention-v1','specification':self.spec,'archive_index':'archives.json.gz',
                   'compiler_sha256':self.spec['compiler_sha256'],'public_file_sha256':public}
        (self.out/'retention.json').write_text(json.dumps(retention,indent=2)+'\n')
        public['retention.json']=digest(self.out/'retention.json');(self.out/'SHA256.json').write_text(json.dumps(public,indent=2)+'\n')


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('phase',choices=['copy-reports','inventory','package'])
    parser.add_argument('--root',type=Path,default=Path('/home/jacobt/src/goose-to-wasm'))
    parser.add_argument('--spec',type=Path,default=HERE/'spec.json');args=parser.parse_args();bundle=Bundle(args.root,load(args.spec))
    if args.phase=='copy-reports':bundle.copy_reports()
    elif args.phase=='inventory':
        bundle.collect();print(json.dumps(bundle.storage_summary(),indent=2))
    else:bundle.seal()


if __name__=='__main__':main()
