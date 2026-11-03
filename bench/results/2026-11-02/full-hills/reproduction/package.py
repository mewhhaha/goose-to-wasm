#!/usr/bin/env python3
"""Retain the full 24-hill campaign. Run only outside all measurement windows.

Reports are copied byte for byte. archives.json.gz holds the member index,
original@SHA aliases, historical archive dependencies and explicit exclusions.
No compiler, guest, build tool, daemon or benchmark is executed.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import gzip
import hashlib
import json
import math
import os
import re
import shutil
import tarfile

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT/'build/full-hills'
OUT = ROOT/'bench/results/2026-11-02/full-hills'
REFERENCE = ROOT/'build/runtime-reference/production/report.json'
REFERENCE_SHA = '06c1f5b883af43d5f5563416fec01d5a1ff5ec309a5005e3abb5293654e59350'
REPORTS = {'cohort.json':'current/langarena/report.json', 'examples.json':'current/examples/report.json',
           'host.json':'current/host/report.json', 'final-warmed.json':'delivered-warmed/report.json',
           'final-v8.json':'delivered-v8/report.json', 'qualification.json':'final-qualification/report.json',
           'differential.json':'differential/report.json', 'host-qualification.json':'host-qualification/report.json',
           'ci-followup.json':'ci-followup/qualification.json',
           'optimizer-followup.json':'optimizer-followup/qualification.json'}
TEXT = {'.py','.mjs','.js','.json','.jsonl','.c','.cc','.cpp','.h','.hpp','.inc','.in','.cmake','.goose',
        '.patch','.diff','.md','.txt','.yml','.yaml','.out','.log','.stdout','.stderr','.wat','.s','.asm','.disasm','.map','.ll','.csv','.tsv','.lock','.pins'}
GUEST = {'.wasm','.cwasm','.bin'}
ASSETS = {'.svg','.png','.webp','.jpg','.jpeg','.pdf'}
RAW_NAMES = {'stdout','stderr','stdin','expected','pins','LICENSE','CMakeLists.txt','Cargo.lock.frozen','SHA256SUMS'}
SHA = re.compile(r'^[0-9a-f]{64}$')
EXCLUDED = ['hosts/h01-runtime/cargo-target','hosts/h01-runtime/source-extraction','hosts/h01-runtime/source',
            'hosts/sdk-full','hosts/sdk-min','hosts/min/source','hosts/min/target']
ROOT_DEPENDENCIES = ['build/emsdk','build/em-cache','.venv','build/wasmtime-host','build/source']


def require(condition, message):
    if not condition:
        raise RuntimeError(str(message))


def digest(path):
    with Path(path).open('rb') as data:
        return hashlib.file_digest(data,'sha256').hexdigest()


def load(path):
    if str(path).endswith('.gz'):
        with gzip.open(path,'rt') as source:
            return json.load(source)
    return json.loads(Path(path).read_bytes())


def absolute(path):
    path = Path(path)
    if not path.is_absolute():
        path = ROOT/path
    return path.absolute()


def safe_member(name):
    path = Path(name)
    require(name and '\\' not in name and not path.is_absolute() and '..' not in path.parts, ('unsafe member',name))


def identities(value):
    """Path-keyed fingerprints, including nested source/compiler manifests."""
    if isinstance(value,dict):
        for name,item in value.items():
            if isinstance(item,str) and SHA.fullmatch(item) and ('/' in name or Path(name).suffix):
                yield name,item
            yield from identities(item)
    elif isinstance(value,list):
        for item in value:
            yield from identities(item)


def guest_identities(value):
    if isinstance(value,dict):
        pairs = [('artifact','artifact_sha256'),('artifact','sha256'),('aot_path','aot_sha256'),
                 ('precompiled','precompiled_sha256'),('module','wasm_sha256'),('wasm','wasm_sha256'),
                 ('baseline_artifact','baseline_sha256'),('candidate_artifact','candidate_sha256')]
        if 'wasm_sha256' not in value:
            pairs.append(('module','sha256'))
        if isinstance(value.get('path'),str) and (Path(value['path']).suffix in GUEST or value.get('family')=='native'):
            pairs.append(('path','sha256'))
        bound = set()
        for path,sha in pairs:
            if isinstance(value.get(path),str) and isinstance(value.get(sha),str) and SHA.fullmatch(value[sha]):
                yield value[path],value[sha]
                bound.add(sha)
        fields = {'artifact_sha256','module_sha256','wasm_sha256','aot_sha256','precompiled_sha256'}
        if 'module_bytes' in value:
            fields.add('sha256')
        for field in fields-bound:
            if isinstance(value.get(field),str) and SHA.fullmatch(value[field]):
                yield None,value[field]
        for item in value.values():
            yield from guest_identities(item)
    elif isinstance(value,list):
        for item in value:
            yield from guest_identities(item)


def exact(rows,fields,expected,label):
    actual = [tuple(row[field] for field in fields) for row in rows]
    require(len(actual)==len(set(actual)) and set(actual)==expected, label+' coverage differs')


def normalized_fingerprints(pins,repo_root):
    """Compare mixed historical relative and absolute names without rewriting."""
    result={}
    for original,sha in pins.items():
        path=Path(original)
        if not path.is_absolute(): path=repo_root/path
        name=os.path.normpath(str(path))
        require(name not in result or result[name]==sha,('conflicting fingerprint aliases',original))
        result[name]=sha
    return result


def reference_root(reference):
    # Derive the recorded repository root, not the verifier's current checkout.
    roots={Path(case['source']).parents[3] for case in reference['workloads']
           if Path(case['source']).parts[-4:-1]==('bench','langarena','ports')}
    require(len(roots)==1,'ambiguous frozen source root')
    return next(iter(roots))


def validate_named(report,reference,compiler_sha,v8=False):
    require(report['status']=='passed' and not report['failures'] and report['coverage_exact'],'kernel report failed')
    config = report['configuration']; samples = config['samples']
    require(type(samples) is int and samples>=9 and config['cpu']==2,'kernel sampling configuration')
    require(report['workloads']==reference['workloads'] and len(report['workloads'])==10,'kernel workload drift')
    require(report['selection']==reference['selection'],'frozen selection drift')
    require(report['compilers']['final']['sha256']==compiler_sha,'final named compiler differs')
    require(report['input_sha256']==report['input_sha256_after'],'kernel pins changed')
    require(report['input_sha256'][config['reference']]==REFERENCE_SHA,'kernel reference differs')
    require(report['host_build']==reference['host_build'],'frozen Wasmtime host differs')
    require(report['input_sha256'][config['host']]==reference['host_build']['host_sha256'],'kernel host hash differs')
    require(config['references'] != v8,'kernel reference mode differs')
    if v8:
        require(report['runtime_engine']=='v8-default' and config['runtime_flags']==[],'V8 flags differ')
    expected = set()
    cases = {case['name']:case for case in report['workloads']}
    commands={row['log_directory']:row for row in report['commands'] if 'log_directory' in row}
    for task,case in cases.items():
        artifacts = report['artifacts'][task]
        variants = set(config['compilers'])
        if not v8:
            selected = reference['selection'][task]
            choices = {'original_direct':'direct-O2','gcc_O2_anchor':'native-gcc-O2-generic',
                       'selected_native':selected['native']['variant'],'selected_wasm':selected['wasm']['wasmtime']['variant']}
            roles = {role:'ref--'+name for role,name in choices.items()}
            require(report['reference_roles'][task]==roles,'reference roles differ')
            variants.update(roles.values())
            for variant in choices.values():
                original = reference['artifacts'][case['id']+'/'+variant]
                actual = artifacts['ref--'+variant]
                for field in ('family','sha256','aot_sha256'):
                    require(actual.get(field)==original.get(field),'selected reference artifact differs')
        require(set(artifacts)==variants,'kernel variants differ')
        for name in config['compilers']:
            require(artifacts[name]['compiler_sha256']==report['compilers'][name]['sha256'],'kernel compiler/artifact mismatch')
        expected.update((task,name,'qualify',0) for name in variants)
        expected.update((task,name,'measure',i) for name in variants for i in range(samples))
    exact(report['observations'],('task','variant','phase','round'),expected,'kernels')
    require(report['observations_expected']==len(expected),'kernel expected count differs')
    for row in report['observations']:
        case = cases[row['task']]; artifact = report['artifacts'][row['task']][row['variant']]
        profile = 'run'
        if row['phase']=='qualify': profile='test'
        require(row['profile']==profile and row['runtime_affinity']==[2],'kernel profile/affinity differs')
        require(row['checksum']==row['expected_checksum']==case[profile]['checksum'] and row['revision_exit']==0,'kernel checksum differs')
        elapsed,wall = row['timed_region_seconds'],row['process_wall_seconds']
        require(math.isfinite(elapsed) and math.isfinite(wall) and 0<elapsed<=wall,'invalid kernel interval')
        require(row['artifact_sha256']==artifact['sha256'],'kernel guest identity differs')
        command=commands[row['log_directory']]
        require(command['returncode']==0 and not command['error'],'kernel runtime command failed')
        command=command['command']
        require(command[:3]==[reference['tools']['taskset'],'-c','2'],'kernel runtime affinity command differs')
        engine = 'wasmtime'
        if artifact['family']=='native':
            engine='native'
            require(command[3:]==[artifact['path']],'native runtime command differs')
        elif v8:
            engine='v8'
            require(len(command)==6 and command[5]==artifact['path'] and command[4].endswith('/scripts/run_wasm.mjs'),'V8 runtime command differs')
            require(report['input_sha256'][command[3]]==reference['inputs'][reference['tools']['node']],'V8 engine bytes differ')
        else:
            require(command[3:]==[config['host'],'--precompiled',artifact['aot_path']],'Wasmtime runtime command differs')
        require(row['engine']==engine,'kernel engine differs')


def validate_claims(reports,reference,compiler_sha,counts,campaign):
    """Pure report validation shared by the packager and offline verifier."""
    items = campaign['items']
    require({row['id'] for row in items}=={f'H{i:02}' for i in range(1,25)} and len(items)==24,'need all24 hills')
    for item in items:
        require(item['status'] in {'kept','rejected','proof-limited','reference-only'},'unfinished hill '+item['id'])
        require(item.get('reason') or item.get('conclusion'),'missing hill reason '+item['id'])
        require(item['evidence'],'missing hill evidence '+item['id'])
    require(reference['status']=='passed' and not reference['failures'],'reference failed')
    for name,report in reports.items():
        if name!='differential.json':
            require(report['status'] in {'passed','pass'},('primary report failed',name))
        require(not report.get('failures'),('primary report failures',name))
    for name in ('cohort.json','examples.json','host.json'):
        require(reports[name]['environment']['compiler_sha256']==compiler_sha,('compiler differs',name))
        require(reports[name]['environment']['wasmtime']==reference['host_build']['version'],('Wasmtime version differs',name))
    for name in ('qualification.json','differential.json','host-qualification.json'):
        require(reports[name]['compiler_sha256']==compiler_sha,('qualification compiler differs',name))
    followup=reports['ci-followup.json']; repo=reference_root(reference)
    require(followup['compiler_sha256_before']==followup['compiler_sha256_after']==compiler_sha,'CI follow-up compiler differs')
    require(followup['tool_sha256_before']==followup['tool_sha256_after'],'CI follow-up tool identities differ')
    require(followup['tool_sha256_before'][str(repo/'build/bin/goose')]==compiler_sha,'CI follow-up compiler tool pin differs')
    require(all(row['exit_status']==0 for row in followup['commands']),'CI follow-up failed')
    require({'lane-default','lane-wrapper','lane-discovery','resource-free-ci-default','ci-invocations'}<=
            {row['name'] for row in followup['commands']},'CI follow-up commands incomplete')
    allowed={str(repo/name) for name in ('tests/test_lane_writeback.py','tests/test_simd_only_writeback.py','.github/workflows/ci.yml')}
    require(set(followup['source_changes'])==allowed,'CI correction source scope differs')
    qualified=reports['differential.json']['qualification_execution']['input_sha256']
    for original,row in followup['source_changes'].items():
        require(followup['input_sha256_before'][original]==row['before_sha256'] and
                followup['input_sha256_after'][original]==row['after_sha256'],'CI correction fingerprint linkage differs')
        if original in qualified: require(qualified[original]==row['before_sha256'],'CI original differs from65-gate source')
    optimizer=reports['optimizer-followup.json']
    require(optimizer['compiler_sha256_before']==optimizer['compiler_sha256_after']==compiler_sha,'optimizer follow-up compiler differs')
    require(optimizer['tool_sha256_before']==optimizer['tool_sha256_after'],'optimizer follow-up tools differ')
    require(optimizer['tool_sha256_before'][str(repo/'build/bin/goose')]==compiler_sha,'optimizer follow-up compiler tool differs')
    allowed={str(repo/name) for name in ('bench/runtime_reference.py','tests/test_runtime_reference.py')}
    require(set(optimizer['source_changes'])==allowed,'optimizer correction source scope differs')
    for original,row in optimizer['source_changes'].items():
        require(optimizer['input_sha256_before'][original]==row['before_sha256'] and
                optimizer['input_sha256_after'][original]==row['after_sha256'],'optimizer correction linkage differs')
        require(qualified[original]==row['before_sha256'],'optimizer original differs from65-gate source')
    commands={row['name']:row for row in optimizer['commands']}
    require(len(commands)==len(optimizer['commands']) and set(commands)=={'old-flags-reproduction','runtime-reference-unit',
            'new-flags-optimization','v8-smoke','wasmtime-smoke'},'optimizer follow-up coverage differs')
    require(commands['old-flags-reproduction']['exit_status']!=0,'missing original optimizer rejection')
    require(all(row['exit_status']==0 for name,row in commands.items() if name!='old-flags-reproduction'),'optimizer correction failed')
    old=commands['old-flags-reproduction']['command']; new=commands['new-flags-optimization']['command']
    require('--enable-simd' not in old and new==[*old[:-2],'--enable-simd','-o',optimizer['optimized_guest']['path']],
            'optimizer command changed beyond standard SIMD feature/output path')
    require({row['engine'] for row in optimizer['smoke_results']}=={'v8','wasmtime'} and len(optimizer['smoke_results'])==2,'optimizer engines incomplete')
    for row in optimizer['smoke_results']:
        require(row['status']=='passed' and row['checksum']==row['expected_checksum']==optimizer['case']['test']['checksum'],
                'optimized guest checksum differs')
    require(optimizer['guest']['sha256']==reports['final-warmed.json']['artifacts'][optimizer['case']['name']]['final']['sha256'],
            'optimizer smoke is not based on the delivered compiler guest')
    focused = reports['qualification.json']['commands']
    require(len(focused)==counts['focused_commands'] and all(row['exit_status']==0 for row in focused),'focused gates differ')
    diff = reports['differential.json']; rows = diff['results']
    require(diff['observations']==len(rows)==counts['differential_observations'] and diff['cases']==counts['cases'],'differential counts differ')
    require(all(row['status']=='pass' for row in rows),'differential failures')
    runtime = [row for row in rows if row.get('kind')!='compile-refusal']
    native = {(row['case'],row['optimization'],row['debug']):row for row in runtime if row['backend']=='native'}
    require(len(native)==sum(row['backend']=='native' for row in runtime),'duplicate native rows')
    expected = {(*key,backend,engine) for key in native for backend,engine in
                [('native','native'),('direct','v8'),('direct','wasmtime'),('c-wasm','v8'),('c-wasm','wasmtime')]}
    exact(runtime,('case','optimization','debug','backend','engine'),expected,'differential')
    require(len(runtime)-len(native)==counts['native_comparisons'],'native comparison count differs')
    require(len({row['case'] for row in runtime})==counts['cases'],'differential case inventory differs')
    refusals = [row for row in rows if row.get('kind')=='compile-refusal']
    require({row['case'] for row in refusals}=={'unsupported_varint_array','unsupported_pointer_extern','invalid_source'} and len(refusals)==3,'refusals differ')
    for row in runtime:
        original = native[row['case'],row['optimization'],row['debug']]
        require(row['stdout']==original['stdout'] and row['exit_code']==original['exit_code'],'native comparison differs')
    replay = reports['host-qualification.json']
    require(replay['coverage_exact'] and replay['observations']==len(replay['results'])==counts['host_observations'],'host coverage differs')
    require(replay['unique_wasm']==len(replay['preparations'])==counts['host_modules'],'host module count differs')
    require(all(row['status']=='pass' for row in replay['results']+replay['preparations']),'host replay failed')
    modes = ('wasm','wasm-no-parallel','precompiled-no-parallel')
    expected = {(*key,backend,mode) for key in native for backend in ('direct','c-wasm') for mode in modes}
    exact(replay['results'],('case','optimization','debug','backend','mode'),expected,'host replay')
    require(replay['input_sha256']==replay['input_sha256_after'] and replay['aot_sha256']==replay['aot_sha256_after'],'host replay pins changed')
    examples = reports['examples.json']; config=examples['configuration']
    names = {row['name'] for row in examples['examples']}
    require(len(names)==10 and not config['smoke'] and config['compile_samples']==5 and config['samples']==15 and config['warmups']==1,'example configuration differs')
    builds = [row for row in examples['observations'] if row['kind']=='build']
    exact(builds,('name','backend','sample'),{(name,backend,i) for name in names for backend in ('direct','c-wasm','native') for i in range(5)},'example builds')
    runs = [row for row in examples['observations'] if row['kind']=='execution']
    cells = [(backend,engine) for backend,engine in [('native','native'),('direct','v8'),('direct','wasmtime'),('c-wasm','v8'),('c-wasm','wasmtime')]]
    expected = {(name,backend,engine,phase,i) for name in names for backend,engine in cells for phase,n in [('warmup',1),('measure',15)] for i in range(n)}
    unique_builds=list(dict.fromkeys((row['name'],row['backend'],row['artifact_sha256']) for row in builds))
    require(len(unique_builds)==30,'example build artifact identities differ across repeated builds')
    for sample,(name,backend,_) in enumerate(unique_builds):
        engines=('v8','wasmtime')
        if backend=='native': engines=('native',)
        expected.update((name,backend,engine,'qualification',sample) for engine in engines)
    expected.update((name,backend,engine,'measure-engine',i) for name in names for backend,engine in cells if backend!='native' for i in range(15))
    exact(runs,('name','backend','engine','phase','sample'),expected,'example execution')
    require(len(examples['observations'])==1600 and all(row['status']=='passed' for row in examples['observations']),'example observations differ')
    host = reports['host.json']; host_config=host['configuration']
    require(host_config['samples']==15 and host_config['prepare_samples']==5 and host_config['warmups']==1 and not host_config['smoke'],'host benchmark configuration differs')
    expected = {(name,backend,mode,phase,i) for name in names for backend in ('direct','c-wasm') for mode in ('python','native','native-serial','precompiled') for phase,n in [('warmup',1),('measure',15)] for i in range(n)}
    expected.update((name,'native','native-C',phase,i) for name in names for phase,n in [('warmup',1),('measure',15)] for i in range(n))
    exact(host['observations'],('name','backend','mode','phase','sample'),expected,'host launch benchmark')
    exact(host['preparation'],('name','backend','configuration','sample'),{(name,backend,mode,i) for name in names for backend in ('direct','c-wasm') for mode in ('parallel','serial') for i in range(5)},'host preparation')
    require(len(host['observations'])==1440 and len(host['preparation'])==200,'host benchmark counts differ')
    require(host['host_build']==replay['host_build'],'production benchmark/replay host identities differ')
    require(host['host_build']['version']==host['python_engine']['version']==reference['host_build']['version'],'Python/native versions differ')
    python_engine=host['python_engine']
    # Examples have always captured this absolute library input. The new
    # LangArena field is required only for the freshly collected final cohort.
    require(reports['examples.json']['environment']['input_sha256'][python_engine['library']]==python_engine['library_sha256'],
            'example Python library identity differs')
    cohort_environment=reports['cohort.json']['environment']
    require(cohort_environment.get('python_engine')==python_engine,
            'fresh LangArena Python engine identity missing/different; do not invent a historical pin')
    cohort_pins=normalized_fingerprints(cohort_environment['input_sha256'],reference_root(reference))
    require(cohort_pins[os.path.normpath(python_engine['library'])]==python_engine['library_sha256'],
            'LangArena Python library fingerprint differs')
    golden={}
    for example in examples['examples']:
        suffix='/examples/'+example['expected']
        matches={sha for path,sha in examples['environment']['input_sha256'].items() if path.endswith(suffix)}
        require(len(matches)==1,'missing example golden identity')
        golden[example['name']]=next(iter(matches))
    for row in examples['observations']:
        if row['kind']=='execution': require(row['stdout_sha256']==golden[row['name']],'example golden differs')
    for row in host['observations']:
        require(row['exit_code']==0 and row['stdout_sha256']==golden[row['name']],'host golden differs')
    for row in host['preparation']:
        hashes={item['artifact_sha256'] for item in builds if item['name']==row['name'] and item['backend']==row['backend']}
        require(hashes=={row['wasm_sha256']},'host/example guest identity differs')
    cohort = reports['cohort.json']; config=cohort['configuration']
    require(config['tracks']==['adapted'] and config['profiles']==['test','run'] and config['compile_samples']==config['runtime_samples']==5 and config['skip_edits'],'cohort configuration differs')
    builds=[row for row in cohort['observations'] if row['kind']=='build']; tasks={row['task'] for row in builds}
    require(tasks=={case['name'] for case in reference['workloads'] if case['name'].startswith(('Etc::','Sort::','Hash::','CLBG::'))} and len(tasks)==7,'port inventory differs')
    exact(builds,('task','backend','phase','sample'),{(task,backend,'cold',i) for task in tasks for backend in ('native','direct','c-wasm') for i in range(5)},'port builds')
    runs=[row for row in cohort['observations'] if row['kind']=='execution']
    exact(runs,('task','backend','engine','profile','sample'),{(task,backend,engine,profile,i) for task in tasks for backend,engine in cells for profile,n in [('test',1),('run',5)] for i in range(n)},'port execution')
    require(len(cohort['observations'])==315 and all(row['status']=='passed' for row in cohort['observations']),'port observations differ')
    for row in runs:
        elapsed=row['timed_region_seconds']
        case=next(case for case in reference['workloads'] if case['name']==row['task'])
        require(row['checksum']==row['expected_checksum']==case[row['profile']]['checksum'] and row['stdin']==case[row['profile']]['stdin'],
                'port input/checksum differs')
        require(math.isfinite(elapsed) and 0<elapsed<=row['wall_seconds'],'port interval differs')
        lines=row['stdout'].splitlines()
        require(len(lines)==2 and all(line.isdecimal() for line in lines) and int(lines[0])==row['checksum'] and int(lines[1])/1e9==elapsed,
                'port authoritative timer differs')
    validate_named(reports['final-warmed.json'],reference,compiler_sha)
    validate_named(reports['final-v8.json'],reference,compiler_sha,v8=True)
    for task in reports['final-warmed.json']['artifacts']:
        require(reports['final-warmed.json']['artifacts'][task]['final']['sha256']==reports['final-v8.json']['artifacts'][task]['final']['sha256'],
                'V8/Wasmtime final guest bytes differ')


class Package:
    def __init__(self,args):
        self.args=args; self.out=args.output.absolute(); self.out.mkdir(parents=True,exist_ok=True)
        require(self.out.parent.resolve()==OUT.parent.resolve(),'package must remain beside its dated historical dependencies')
        require(not (self.out/'retention.json').exists(),'refusing to replace a finished package')
        self.index={'schema':'goose-full-hills-archives-v1','archives':{},'aliases':{},'omitted':{},'documents':{},'anonymous_guests':[],
                    'hill_evidence':{},'opaque_historical_context':{},'excluded_trees':EXCLUDED,'root_dependency_trees':ROOT_DEPENDENCIES,
                    'dependency_policy':'Rust checkout/targets/caches and tool binaries are omitted; exact dependency manifests, archive URLs/hashes, lockfiles, generated config, commands and modified source are retained.'}
        self.objects={}; self.external={}; self.external_by_sha={}; self.documents={}; self.source_pins={}

    def key(self,path):
        return str(Path(path).absolute())

    def excluded(self,path):
        path=Path(path).absolute()
        return any(path.is_relative_to(BUILD/name) for name in EXCLUDED)

    def dependency(self,path):
        path=absolute(path)
        return self.excluded(path) or any(path.is_relative_to(ROOT/name) for name in ROOT_DEPENDENCIES)

    def walk(self,folder):
        for directory,dirs,names in os.walk(folder,followlinks=False):
            directory=Path(directory)
            dirs[:]=sorted(name for name in dirs if name not in {'.git','__pycache__','node_modules','cargo-target','target','.cache'}
                           and not (directory==ROOT/'bench' and name=='results')
                           and not self.excluded(directory/name) and not (directory/name).is_symlink())
            for name in sorted(names):
                path=directory/name
                if path.is_file() and not path.is_symlink(): yield path

    def add(self,path,group='experiments'):
        path=Path(path).absolute(); sha=digest(path); size=path.stat().st_size
        self.source_pins[str(path)]=sha
        if sha not in self.objects:
            self.objects[sha]={'path':path,'group':group,'member':'objects/'+sha,'sha256':sha,'bytes':size}
        location={name:self.objects[sha][name] for name in ('member','sha256','bytes')}
        location['archive']=self.objects[sha]['group']+'.tar.gz'
        self.index['aliases'][str(path)+'@'+sha]=location
        self.index['omitted'].pop(str(path)+'@'+sha,None)
        return location

    def historical_catalog(self):
        for name in ('resource-free-calls','runtime-targets'):
            folder=OUT.parent/name
            hashes={}
            sha_file=folder/'SHA256.json'
            if sha_file.exists(): hashes.update(load(sha_file))
            retention=folder/'retention.json'
            if retention.exists(): hashes.update(load(retention).get('public_file_sha256',{}))
            indexed=folder/'archives.json.gz'
            if indexed.exists():
                require(digest(indexed)==hashes['archives.json.gz'],'historical index differs')
                for archive,record in load(indexed).items():
                    if '/' in archive: continue
                    hashes[archive]=record['sha256']
                    archive_path=folder/archive
                    for member,item in record['members'].items():
                        self.external_by_sha.setdefault(item['sha256'],(archive_path,record['sha256'],member,item['sha256']))
            for map_name,default_archive in [('artifact-map.json','guest-artifacts.tar.gz'),('source-map.json','inputs.tar.gz')]:
                path=folder/map_name
                if not path.exists(): continue
                require(digest(path)==hashes[map_name],'historical map differs: '+str(path))
                for item in load(path).values():
                    archive=item.get('archive',default_archive)
                    archive_path=(folder/archive).resolve()
                    expected=item.get('archive_sha256')
                    if expected is None: expected=hashes[archive]
                    self.external_by_sha.setdefault(item['sha256'],(archive_path,expected,item['archive_path'],item['sha256']))

    def external_location(self,sha):
        if sha not in self.external_by_sha: return None
        path,expected,member,_=self.external_by_sha[sha]
        key=os.path.relpath(path,self.out)
        require(path.parent in {OUT.parent/'runtime-targets',OUT.parent/'resource-free-calls'},'unexpected historical archive')
        if key not in self.index['archives']:
            require(digest(path)==expected,'historical archive SHA differs')
            members={}
            with tarfile.open(path,'r:gz') as archive:
                for entry in archive:
                    safe_member(entry.name)
                    require(entry.isfile() and entry.name not in members,'invalid historical archive member')
                    with archive.extractfile(entry) as data:
                        value=hashlib.file_digest(data,'sha256').hexdigest()
                    members[entry.name]={'sha256':value,'bytes':entry.size}
            self.index['archives'][key]={'sha256':expected,'bytes':path.stat().st_size,'members':members,'historical':True}
        item=self.index['archives'][key]['members'][member]
        require(item['sha256']==sha,'historical member hash differs')
        return {'archive':key,'member':member,**item}

    def resolve(self,original,sha,guest=False,dependency_manifest=None):
        require(SHA.fullmatch(sha),'invalid expected SHA')
        alias=str(original)+'@'+sha
        if alias in self.index['aliases']: return self.index['aliases'][alias]
        if sha in self.objects:
            obj=self.objects[sha]; location={'archive':obj['group']+'.tar.gz',**{k:obj[k] for k in ('member','sha256','bytes')}}
        else:
            location=self.external_location(sha)
        path=absolute(original)
        if location is None and not self.dependency(path) and path.is_file() and digest(path)==sha:
            if guest or path.suffix in TEXT or path.name in RAW_NAMES or SHA.fullmatch(path.name):
                location=self.add(path,'sources')
        if location is not None:
            self.index['aliases'][alias]=location
            self.index['omitted'].pop(alias,None)
            return location
        require(not guest and (path.suffix not in GUEST or dependency_manifest is not None),('guest bytes unavailable',original,sha))
        local_text=path.is_relative_to(ROOT) and (path.suffix in TEXT or path.name in RAW_NAMES)
        require(not local_text or self.dependency(path) or dependency_manifest is not None,('historical local source unavailable',original,sha))
        category='tool-binary-or-external-input'
        if self.dependency(path) or dependency_manifest is not None: category='rebuildable-dependency'
        self.index['omitted'][alias]={'original':str(original),'sha256':sha,'category':category,
                                    'reason':'Not advertised as retained bytes; rebuild using retained dependency identities and commands.'}
        if dependency_manifest is not None:
            self.index['omitted'][alias]['dependency_manifest']=dependency_manifest
        return None

    def collect(self):
        for path in self.walk(BUILD):
            relative=path.relative_to(BUILD)
            if path==Path(__file__).resolve() or path.name=='verify_package.py': group='sources'
            elif path.suffix in GUEST: group='guests'
            elif path.suffix in ASSETS: group='assets'
            elif 'source' in relative.parts or 'compiler' in relative.parts or 'frozen-inputs' in relative.parts: group='sources'
            elif relative.parts[0] in {'final-qualification','differential','host-qualification'}: group='qualification'
            else: group='experiments'
            is_json=path.suffix=='.json' or path.name.endswith('.json.gz')
            if path.suffix not in TEXT|GUEST|ASSETS and path.name not in RAW_NAMES and not SHA.fullmatch(path.name) and not is_json: continue
            self.add(path,group)
            opaque=any(relative.parts[i:i+3]==('source','bench','results') for i in range(len(relative.parts)-2))
            if opaque:
                self.index['opaque_historical_context'][str(path)]=self.index['aliases'][str(path)+'@'+digest(path)]
            elif is_json:
                try: self.documents[str(path)]=load(path)
                except (ValueError,UnicodeError): pass
        for name in ('compiler','scripts','oracle','tests','examples','docs','host','patches','bench'):
            for path in self.walk(ROOT/name):
                if 'results' in path.relative_to(ROOT/name).parts: continue
                if path.suffix in TEXT|ASSETS or path.name in RAW_NAMES: self.add(path,'sources')
        for name in ('README.md','AGENTS.md','LICENSE','toolchain.json','requirements.txt','.github/workflows/ci.yml'):
            self.add(ROOT/name,'sources')
        for path in (ROOT/'bench/results').glob('*latest.json'):
            self.add(path,'sources')
        # Prepublished chart inputs and reviews can be named by earlier assembly
        # manifests. Retain their exact bytes before resolving those manifests.
        # Reproduction scripts are copied from the current originals later.
        for path in self.out.rglob('*'):
            if path.is_file() and 'reproduction' not in path.relative_to(self.out).parts:
                if path.suffix in {'.json','.md'}|ASSETS: self.add(path,'assets')
        # Do not walk the Rust checkout. Retain only the exact upstream build inputs
        # needed to reproduce its separate dependency, plus all outside proofs/logs.
        rust=BUILD/'hosts/h01-runtime/source'
        for name in ('Cargo.lock','Cargo.toml','crates/c-api/Cargo.toml','crates/c-api/CMakeLists.txt'):
            path=rust/name
            if path.is_file(): self.add(path,'sources')
        self.add(REFERENCE,'sources'); self.documents[str(REFERENCE)]=load(REFERENCE)
        unresolved=[]
        for origin,document in list(self.documents.items()):
            self.index['documents'][origin]=self.index['aliases'][origin+'@'+digest(origin)]
            dependency_manifest=None
            if origin.endswith('/hosts/h01-runtime/source-files.json'):
                dependency_manifest=origin
            for original,sha in identities(document):
                try: self.resolve(original,sha,dependency_manifest=dependency_manifest)
                except RuntimeError as error: unresolved.append((origin,str(error)))
            for original,sha in guest_identities(document):
                try:
                    if original is not None: self.resolve(original,sha,guest=True)
                    else:
                        self.resolve('sha256:'+sha,sha,guest=True)
                        self.index['anonymous_guests'].append(sha)
                except RuntimeError as error: unresolved.append((origin,str(error)))
        require(not unresolved,('unresolved retained identities',sorted(set(unresolved))))

    def write_archives(self):
        # Bound raw payload per partition so even incompressible guests fit GitHub.
        limit=64*1024*1024
        original_groups={sha:obj['group'] for sha,obj in self.objects.items()}
        for group in sorted(set(original_groups.values())):
            objects=[obj for sha,obj in sorted(self.objects.items()) if original_groups[sha]==group]
            if sum(obj['bytes'] for obj in objects)<=limit: continue
            part=1; size=0
            for obj in objects:
                require(obj['bytes']<=limit,('single retained object exceeds archive partition limit',obj['path']))
                if size+obj['bytes']>limit:
                    part+=1; size=0
                obj['group']=group+'-'+str(part).zfill(3)
                size+=obj['bytes']
        def remap(value):
            if isinstance(value,dict):
                sha=value.get('sha256')
                if sha in self.objects and value.get('archive')==original_groups[sha]+'.tar.gz':
                    value['archive']=self.objects[sha]['group']+'.tar.gz'
                for item in value.values(): remap(item)
            elif isinstance(value,list):
                for item in value: remap(item)
        remap(self.index)
        for group in sorted({obj['group'] for obj in self.objects.values()}):
            name=group+'.tar.gz'; members={}
            with (self.out/name).open('wb') as raw:
                with gzip.GzipFile(fileobj=raw,filename='',mtime=0,mode='wb',compresslevel=3) as compressed:
                    with tarfile.open(fileobj=compressed,mode='w|') as archive:
                        for sha,obj in sorted(self.objects.items()):
                            if obj['group']!=group: continue
                            path=obj['path']; require(digest(path)==sha,('input changed',path))
                            info=tarfile.TarInfo(obj['member']); info.size=obj['bytes']; info.mode=0o644
                            with path.open('rb') as data: archive.addfile(info,data)
                            members[obj['member']]={'sha256':sha,'bytes':obj['bytes']}
            self.index['archives'][name]={'sha256':digest(self.out/name),'bytes':(self.out/name).stat().st_size,'members':members,'historical':False}

    def main(self):
        args=self.args
        folder=args.compiler_root
        if folder is None:
            folder=BUILD/'compiler-experiments'/args.compiler
        folder=folder.absolute()
        metadata=load(folder/'toolchain.json'); source=load(folder/'source.json'); compiler_sha=metadata['compiler_sha256']
        require(digest(folder/'bin/goose')==compiler_sha,'final frozen compiler mismatch')
        self.source_pins[str(folder/'bin/goose')]=compiler_sha
        require(source['headers']==metadata['headers'] and source['patches']==metadata['patches'],'compiler metadata mismatch')
        for name,expected in source['headers'].items():
            path=folder/'compiler'/name
            require(path.is_file() and digest(path)==expected,('final frozen header differs',name))
        require(digest(REFERENCE)==REFERENCE_SHA,'frozen reference changed')
        reports={name:load(BUILD/origin) for name,origin in REPORTS.items()}
        campaign=load(args.campaign)
        counts={'focused_commands':args.focused_commands,'differential_observations':9573,'native_comparisons':7656,'cases':978,
                'host_observations':11484,'host_modules':args.host_modules}
        validate_claims(reports,load(REFERENCE),compiler_sha,counts,campaign)
        self.add(args.campaign,'experiments'); self.documents[str(args.campaign.absolute())]=campaign
        for item in campaign['items']:
            self.index['hill_evidence'][item['id']]=[]
            for name in item['evidence']:
                path=Path(name)
                if not path.is_absolute():
                    candidates=[BUILD/path,ROOT/path]
                    path=next((candidate for candidate in candidates if candidate.is_file()),BUILD/path)
                require(path.is_file(),('missing hill evidence',item['id'],str(path)))
                require(path.resolve().is_relative_to(ROOT.resolve()),'hill evidence escapes repository')
                location=self.add(path,'experiments')
                self.index['hill_evidence'][item['id']].append({'requested':name,'original':str(path.absolute()),'location':location})
                if path.suffix=='.json': self.documents[str(path.absolute())]=load(path)
        self.historical_catalog(); self.collect()
        identity={'name':args.compiler,'root':str(folder),'compiler_sha256':compiler_sha,'source':source,'toolchain':metadata,
                  'binary_retained':False,'rebuild':'Use retained source, patches, toolchain and bootstrap scripts.'}
        for path in (folder/'source.json',folder/'toolchain.json'): self.add(path,'sources')
        for name,sha in source['headers'].items(): self.resolve(str(folder/'compiler'/name),sha)
        for name,origin in REPORTS.items():
            shutil.copyfile(BUILD/origin,self.out/name)
            self.resolve(str(BUILD/origin),digest(self.out/name))
        shutil.copyfile(args.campaign,self.out/'campaign.json')
        shutil.copyfile(REFERENCE,self.out/'references.json')
        identity_path=self.out/'compiler-identity.json'
        identity_bytes=(json.dumps(identity,indent=2)+'\n').encode()
        if identity_path.exists():
            require(identity_path.read_bytes()==identity_bytes,'published compiler identity would change')
        else: identity_path.write_bytes(identity_bytes)
        (self.out/'reproduction').mkdir(exist_ok=True)
        for name in ('package.py','verify_package.py'):
            shutil.copyfile(BUILD/name,self.out/'reproduction'/name)
        for path in self.out.rglob('*'):
            if path.is_file() and (path.suffix in ASSETS or path.suffix=='.md'):
                self.add(path,'assets')
        self.write_archives()
        self.index['anonymous_guests']=sorted(set(self.index['anonymous_guests']))
        with (self.out/'archives.json.gz').open('wb') as raw:
            with gzip.GzipFile(fileobj=raw,filename='',mtime=0,mode='wb',compresslevel=3) as data:
                data.write(json.dumps(self.index,separators=(',',':')).encode()+b'\n')
        require(all(digest(path)==sha for path,sha in self.source_pins.items()),'inputs changed during packaging')
        public_paths=[path for path in self.out.rglob('*') if path.is_file() and path.name!='retention.json'
                      and (path.suffix in {'.json','.md','.py'}|ASSETS or path.name.endswith('.json.gz'))]
        public={str(path.relative_to(self.out)):digest(path) for path in sorted(public_paths)}
        retention={'schema':'goose-full-hills-retention-v1','recorded_utc':datetime.now(timezone.utc).isoformat(),
            'compiler_sha256':compiler_sha,'reference_sha256':REFERENCE_SHA,'report_origins':REPORTS,
            'public_file_sha256':public,'expected_counts':counts,'archive_index':'archives.json.gz',
            'reference_alias':str(REFERENCE)+'@'+REFERENCE_SHA,'notes':[
                'Reports are immutable copies. All campaign reports, failed attempts, proofs and available guest bytes are retained.',
                'Only compressed archives.json.gz stores the expanded machine index; aliases identify original path AND SHA.',
                'Historical archive references include archive and member digests and remain separately collected evidence.',
                'Older bench/results copied inside frozen source snapshots are retained and hashed as opaque historical context; their unrelated old claims/dependencies are not recursively validated.',
                'Tool/compiler/host/library binaries and the Rust source/target/cache trees are omitted, never described as retained bytes.',
                'Rust source archive identity, lockfile, CMake/generated configuration, build commands, feature proofs and tools are retained.',
                'Packaging, hashing, compression and verification are correctness work and must not overlap performance sampling.']}
        (self.out/'retention.json').write_text(json.dumps(retention,indent=2)+'\n')
        print('Packaged',len(self.objects),'unique objects;',len(self.index['aliases']),'aliases;',len(self.documents),'JSON documents')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler',default='final',help='frozen compiler-experiments directory name')
    parser.add_argument('--compiler-root',type=Path,help='explicit frozen compiler installation root')
    parser.add_argument('--campaign',type=Path,default=BUILD/'campaign.json')
    parser.add_argument('--output',type=Path,default=OUT)
    parser.add_argument('--focused-commands',type=int,default=65)
    parser.add_argument('--host-modules',type=int,default=1574)
    args=parser.parse_args()
    Package(args).main()


if __name__=='__main__': main()
