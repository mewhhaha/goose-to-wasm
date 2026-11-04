#!/usr/bin/env python3
"""Compare fresh Wasmtime hosts and explicit precompilation on unchanged examples."""
import argparse
import ctypes
from datetime import datetime,timezone
import itertools
import importlib.metadata
import json
import mmap
import os
from pathlib import Path
import random
import sys
import time

import benchmark as common
import process

ROOT=Path(__file__).resolve().parents[1]
BACKENDS=('direct',)
MODES=('python','native','native-serial','precompiled')


def residency(descriptor,size):
    if sys.platform!='linux' or not size:return None
    pages=(size+mmap.PAGESIZE-1)//mmap.PAGESIZE
    with mmap.mmap(descriptor,size,access=mmap.ACCESS_COPY) as mapping:
        address=ctypes.c_char.from_buffer(mapping);bits=(ctypes.c_ubyte*pages)()
        result=ctypes.CDLL(None,use_errno=True).mincore(
            ctypes.c_void_p(ctypes.addressof(address)),ctypes.c_size_t(size),bits)
        error=ctypes.get_errno();del address
    if result:return {'error':os.strerror(error)}
    return {'pages':pages,'resident_pages':sum(value&1 for value in bits)}


def warm_files(paths):
    rows=[];seen=set()
    for path in sorted({Path(path).resolve()for path in paths}):
        with path.open('rb') as source:
            stat=os.fstat(source.fileno());identity=(stat.st_dev,stat.st_ino)
            if identity in seen:continue
            seen.add(identity)
            row={'path':str(path),'device':stat.st_dev,'inode':stat.st_ino,'bytes':stat.st_size,
                 'before':residency(source.fileno(),stat.st_size)}
            os.fsync(source.fileno());row['fadvise_dontneed']=False
            if hasattr(os,'posix_fadvise') and hasattr(os,'POSIX_FADV_DONTNEED'):
                os.posix_fadvise(source.fileno(),0,0,os.POSIX_FADV_DONTNEED)
                row['fadvise_dontneed']=True
            row['after_eviction']=residency(source.fileno(),stat.st_size)
            read=0
            for block in iter(lambda:source.read(1024*1024),b''):read+=len(block)
            assert read==stat.st_size,path
            row['warmed_bytes']=read;row['after_warming']=residency(source.fileno(),stat.st_size)
            rows.append(row)
    return rows


def run(command, *, directory, name):
    directory.mkdir(parents=True,exist_ok=True)
    command=list(map(str,command))
    started=time.perf_counter_ns()
    result=process.run(command,input=b'',capture_output=True,timeout=180,cwd=ROOT)
    seconds=(time.perf_counter_ns()-started)/1e9
    (directory/(name+'.command.json')).write_text(json.dumps(command,indent=2)+'\n')
    (directory/(name+'.stdout')).write_bytes(result.stdout)
    (directory/(name+'.stderr')).write_bytes(result.stderr)
    if result.returncode:
        raise RuntimeError(f'{name} exited {result.returncode}: {result.stderr[-2000:]!r}')
    return result,seconds


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('examples',nargs='*')
    parser.add_argument('--host',type=Path,default=ROOT/'build/bin/goose-wasmtime')
    parser.add_argument('--aot-host',type=Path,help='optional minimal-profile trusted-AOT companion')
    parser.add_argument('--example-report',type=Path)
    parser.add_argument('--output-dir',type=Path,default=ROOT/'build/wasmtime-host/bench')
    parser.add_argument('--samples',type=int,default=15)
    parser.add_argument('--prepare-samples',type=int,default=5)
    parser.add_argument('--warmups',type=int,default=1)
    parser.add_argument('--smoke',action='store_true',help='reduced correctness-only sampling')
    parser.add_argument('--machine-label',default='')
    args=parser.parse_args()
    if not __debug__:parser.error('benchmark validation requires Python without -O')
    if args.samples<1 or args.prepare_samples<1 or args.warmups<0:parser.error('invalid sample counts')
    if args.example_report is None:
        pointer=json.loads((ROOT/'bench/results/examples-latest.json').read_text())
        args.example_report=ROOT/'bench/results'/pointer['report']
    if not args.smoke and min(args.samples,args.prepare_samples)<5:parser.error('performance evidence requires five samples; use --smoke for correctness checks')
    baseline=json.loads(args.example_report.read_text())
    assert baseline['status']in ['passed','passed-smoke'] and not baseline['failures']
    catalog=json.loads((ROOT/'examples/manifest.json').read_text())
    examples=[e for e in catalog['examples'] if not args.examples or e['name']in args.examples]
    assert examples and (not args.examples or {e['name']for e in examples}==set(args.examples))
    host=args.host.resolve();host_metadata=json.loads(host.with_suffix('.json').read_text())
    assert host_metadata['host_sha256']==common.digest(host)
    assert not host_metadata.get('runtime_only',False)
    aot_host=None;aot_metadata=None
    configurations={backend:['parallel','serial']for backend in BACKENDS};modes=list(MODES)
    if args.aot_host is not None:
        aot_host=args.aot_host.resolve();aot_metadata=json.loads(aot_host.with_suffix('.json').read_text())
        assert aot_metadata['host_sha256']==common.digest(aot_host)
        assert aot_metadata['runtime_only'] and aot_metadata['aot_profiles']==['minimal']
        assert aot_metadata['supported_modes']==['precompiled']
        assert 'minimal'in host_metadata['aot_profiles']
        assert aot_metadata['version']==host_metadata['version']
        for backend in BACKENDS:configurations[backend].append('minimal')
        modes.append('precompiled-minimal')
    import wasmtime._ffi as ffi
    active_library=Path(ffi.dll._name).resolve()
    native_library=Path(host_metadata['library']).resolve()
    assert common.digest(native_library)==host_metadata['library_sha256']
    python_library_sha256=common.digest(active_library)
    assert baseline['environment']['input_sha256'][str(active_library)]==python_library_sha256
    if host_metadata.get('linkage','python-shared')=='python-shared':
        assert active_library==native_library and python_library_sha256==host_metadata['library_sha256']
    assert importlib.metadata.version('wasmtime')==host_metadata['version']==baseline['environment']['wasmtime']
    assert common.digest(Path(baseline['configuration']['goose']))==baseline['environment']['compiler_sha256']
    out=args.output_dir.resolve();out.mkdir(parents=True,exist_ok=True)
    paths=[Path(__file__).resolve(),args.example_report.resolve(),host,host.with_suffix('.json'),
           ROOT/'examples/manifest.json',ROOT/'bench/benchmark.py',Path(process.__file__),ROOT/'scripts/run_wasmtime.py',
           Path(sys.executable).resolve(),active_library,native_library]
    paths += [Path(p)for p in host_metadata['input_sha256']]
    if aot_metadata is not None:
        aot_library=Path(aot_metadata['library']).resolve()
        assert common.digest(aot_library)==aot_metadata['library_sha256']
        paths += [aot_host,aot_host.with_suffix('.json'),aot_library]
        paths += [Path(p)for p in aot_metadata['input_sha256']]
        for path,expected in aot_metadata['input_sha256'].items():assert common.digest(Path(path))==expected,path
    paths += [Path(p)for p in baseline['environment']['input_sha256']]
    for path,expected in host_metadata['input_sha256'].items():assert common.digest(Path(path))==expected,path
    for path,expected in baseline['environment']['input_sha256'].items():assert common.digest(Path(path))==expected,path
    artifacts={};native={}
    for example in examples:
        for backend in (*BACKENDS,'native'):
            builds=[r for r in baseline['observations']if r['kind']=='build'and r['name']==example['name']and r['backend']==backend]
            assert builds and len({r['artifact_sha256']for r in builds})==1
            artifact=Path(builds[0]['artifact']);assert common.digest(artifact)==builds[0]['artifact_sha256']
            paths.append(artifact)
            if backend=='native':native[example['name']]=artifact
            else:artifacts[example['name'],backend]=artifact
    fingerprints={str(p.resolve()):common.digest(p)for p in set(paths)}
    args.goose=Path(baseline['configuration']['goose']);args.node='node';args.cc='gcc';args.emcc='emcc'
    report={'schema':'goose-wasmtime-host-benchmarks-v1','status':'running',
            'started_utc':datetime.now(timezone.utc).isoformat(),'configuration':vars(args),
            'environment':common.metadata(args),'host_build':host_metadata,
            'python_engine':{'version':importlib.metadata.version('wasmtime'),'library':str(active_library),
                             'library_sha256':python_library_sha256},'input_sha256':fingerprints,
            'examples':examples,'seed':352471,'preparation':[],'observations':[],
            'preparation_summary':[],'runtime_summary':[],'amortization':[],'artifact_qualification':[],
            'method':'Fresh ordinary launch-to-exit samples with checked golden bytes. Python and native Wasmtime share the pinned version; '
                     'their library bytes and build/linkage identities are recorded separately and may differ. '
                     'Native serial changes only compiler parallelism, not Wasm threads. Precompiled uses the native default configuration and an explicitly prepared, trusted local artifact. '
                     'When supplied, the minimal companion runs artifacts from both backends prepared by the full host with --aot-profile minimal and default compiler parallelism. '
                     'The minimal profile excludes exception handling and GC; every selected artifact must compile and qualify under that profile. '
                     'Preparation includes fresh host launch, Wasm compilation, serialization and file writing. Guest source, Wasm and native-C artifact bytes are unchanged. '
                     'After input hashes and artifact qualification, selected executable, Wasm and AOT inodes are fsynced, advised DONTNEED where supported, then sequentially read in 1 MiB blocks before warmups. Dependencies and shared libraries are outside this primary-file normalization. '
                     'Phases run sequentially; runtime modes are shuffled within each example/round block. Separate preparation commands never overlap runtime sampling. No headline runner writes a timing file.'}
    if aot_metadata is not None:report['aot_host_build']=aot_metadata
    report['environment']['host_controls']={key:os.environ.get(key)for key in ['RAYON_NUM_THREADS','WASMTIME_BACKTRACE_DETAILS','LD_PRELOAD','LD_LIBRARY_PATH','OMP_NUM_THREADS']}
    report['environment']['cpu_affinity']=sorted(os.sched_getaffinity(0))
    cpu_info=Path('/proc/cpuinfo')
    if cpu_info.is_file():
        report['environment']['cpu_flags']=next((line.split(':',1)[1].strip()for line in cpu_info.read_text().splitlines()if line.startswith('flags')), '')
    report_path=out/'report.json'
    def checkpoint():report_path.write_text(json.dumps(report,indent=2,default=str)+'\n')
    checkpoint();rng=random.Random(report['seed']);compiled={}
    jobs=[(sample,example,backend,configuration)for sample in range(args.prepare_samples)
          for example in examples for backend in BACKENDS for configuration in configurations[backend]]
    rng.shuffle(jobs)
    for sample,example,backend,configuration in jobs:
        name=example['name'];directory=out/'preparation'/name/backend/configuration/str(sample);directory.mkdir(parents=True,exist_ok=True)
        target=directory/'program.cwasm';command=[host,'--no-cache']
        if configuration=='serial':command.append('--no-parallel-compilation')
        if configuration=='minimal':command+=['--aot-profile','minimal']
        command += ['--compile',artifacts[name,backend],target]
        result,seconds=run(command,directory=directory,name='prepare')
        assert result.returncode==0 and result.stdout==result.stderr==b''
        row={'name':name,'backend':backend,'configuration':configuration,'sample':sample,
             'command':list(map(str,command)),'wall_seconds':seconds,'artifact':str(target),
             'sha256':common.digest(target),'wasm_sha256':common.digest(artifacts[name,backend])}
        report['preparation'].append(row)
        if configuration in ('parallel','minimal'):compiled[name,backend,configuration]=row
        checkpoint();print('PASS prepare',name,backend,configuration,sample,flush=True)
    qualified=set()
    for row in report['preparation']:
        key=(row['name'],row['backend'],row['configuration'],row['sha256'])
        if key in qualified:continue
        command=[host]
        if row['configuration']=='minimal':command=[aot_host]
        if row['configuration']=='serial':command.append('--no-parallel-compilation')
        command += ['--precompiled',row['artifact']]
        directory=out/'qualification'/row['name']/row['backend']/row['configuration']/row['sha256']
        result,_=run(command,directory=directory,name='qualify')
        golden=next(e['expected']for e in examples if e['name']==row['name'])
        assert result.stdout==(ROOT/'examples'/golden).read_bytes() and result.stderr==b''
        report['artifact_qualification'].append({'name':row['name'],'backend':row['backend'],
             'configuration':row['configuration'],'sha256':row['sha256'],'status':'passed'})
        qualified.add(key)
    checkpoint()
    cache_paths=[host,Path(sys.executable).resolve(),*native.values(),*artifacts.values()]
    if aot_host is not None:cache_paths.append(aot_host)
    cache_paths += [row['artifact']for row in compiled.values()]
    report['cache_preparation']={'method':'fsync, optional POSIX_FADV_DONTNEED, sequential 1 MiB read; Linux mincore residency is observational',
                                 'files':warm_files(cache_paths)}
    checkpoint()
    cells=[(e['name'],b,m)for e in examples for b in BACKENDS for m in MODES]
    if aot_host is not None:cells += [(e['name'],b,'precompiled-minimal')for e in examples for b in BACKENDS]
    cells += [(e['name'],'native','native-C')for e in examples]
    for phase,n in [('warmup',args.warmups),('measure',args.samples)]:
        jobs=[]
        for sample in range(n):
            shuffled=list(examples);rng.shuffle(shuffled)
            for example in shuffled:
                block=[cell for cell in cells if cell[0]==example['name']]
                rng.shuffle(block)
                jobs.extend((sample,cell)for cell in block)
        for sample,(name,backend,mode)in jobs:
            artifact=native.get(name)
            if backend!='native':artifact=artifacts[name,backend]
            if mode=='native-C':command=[artifact]
            elif mode=='python':command=[sys.executable,ROOT/'scripts/run_wasmtime.py',artifact]
            elif mode=='native':command=[host,'--no-cache',artifact]
            elif mode=='native-serial':command=[host,'--no-cache','--no-parallel-compilation',artifact]
            elif mode=='precompiled-minimal':command=[aot_host,'--precompiled',compiled[name,backend,'minimal']['artifact']]
            else:command=[host,'--precompiled',compiled[name,backend,'parallel']['artifact']]
            directory=out/'runtime'/phase/name/backend/mode/str(sample)
            result,seconds=run(command,directory=directory,name='run')
            golden=next(e['expected']for e in examples if e['name']==name)
            assert result.returncode==0 and result.stdout==(ROOT/'examples'/golden).read_bytes() and result.stderr==b'',(name,backend,mode,result)
            report['observations'].append({'name':name,'backend':backend,'mode':mode,'phase':phase,'sample':sample,
                'command':list(map(str,command)),'wall_seconds':seconds,'exit_code':result.returncode,
                'stdout_sha256':common.digest(ROOT/'examples'/golden)})
            checkpoint();print('PASS',phase,name,backend,mode,sample,flush=True)
    for example,backend,configuration in [(e,b,c)for e in examples for b in BACKENDS for c in configurations[b]]:
        values=[r['wall_seconds']for r in report['preparation']if r['name']==example['name']and r['backend']==backend and r['configuration']==configuration]
        assert len(values)==args.prepare_samples
        report['preparation_summary'].append({'name':example['name'],'backend':backend,'configuration':configuration,'wall_seconds':common.summary(values)})
    for name,backend,mode in cells:
        values=[r['wall_seconds']for r in report['observations']if r['name']==name and r['backend']==backend and r['mode']==mode and r['phase']=='measure']
        assert len(values)==args.samples
        report['runtime_summary'].append({'name':name,'backend':backend,'mode':mode,'wall_seconds':common.summary(values)})
    for example,backend in itertools.product(examples,BACKENDS):
        name=example['name']
        prep=next(r['wall_seconds']['median']for r in report['preparation_summary']if r['name']==name and r['backend']==backend and r['configuration']=='parallel')
        values={r['mode']:r['wall_seconds']['median']for r in report['runtime_summary']if r['name']==name and r['backend']==backend}
        estimate=None
        if values['native']>values['precompiled']:estimate=prep/(values['native']-values['precompiled'])
        report['amortization'].append({'name':name,'backend':backend,'preparation_plus_one_run_seconds':prep+values['precompiled'],
                                      'estimated_break_even_runs':estimate,'method':'Ratio of same-cohort medians; estimate excludes preparation from repeated launch cost only.'})
    report['paired_speedup']=[]
    for example,backend in itertools.product(examples,BACKENDS):
        name=example['name']
        values={(row['sample'],row['mode']):row['wall_seconds']for row in report['observations']
                if row['phase']=='measure'and row['name']==name and row['backend']==backend}
        for mode in modes:
            if mode=='python':continue
            ratios=[values[sample,'python']/values[sample,mode]for sample in range(args.samples)]
            report['paired_speedup'].append({'name':name,'backend':backend,'reference':'python','mode':mode,'speedup':common.summary(ratios)})
    assert len(report['observations'])==len(cells)*(args.samples+args.warmups)
    assert fingerprints=={str(p.resolve()):common.digest(p)for p in set(paths)}
    assert all(common.digest(Path(r['artifact']))==r['sha256']for r in report['preparation'])
    report['status']='passed'
    if args.smoke:report['status']='passed-smoke'
    report['finished_utc']=datetime.now(timezone.utc).isoformat();checkpoint()
    print('PASS',len(report['observations']),'runtime observations;',report_path)


if __name__=='__main__':main()
