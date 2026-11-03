"""Pure report checks reused from the published full-hills verifier; no collection."""
from pathlib import Path
import gzip
import hashlib
import json
import math
import os
import re
import statistics
import itertools
REFERENCE_SHA = '06c1f5b883af43d5f5563416fec01d5a1ff5ec309a5005e3abb5293654e59350'
BASELINE_SHA = '1b1ec504894d387ae0bbed287d2d3214e250e6dc9bbff2ffd2893a69c06a8874'
GUEST = {'.wasm', '.cwasm', '.bin'}
SHA = re.compile(r'^[0-9a-f]{64}$')

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

def measured_summary(actual,values,label):
    ordered=sorted(values);median=statistics.median(values)
    def percentile(fraction):
        position=fraction*(len(ordered)-1);lo=int(position);hi=min(lo+1,len(ordered)-1)
        return ordered[lo]+(ordered[hi]-ordered[lo])*(position-lo)
    expected={'n':len(values),'median':median,'mad':statistics.median(abs(value-median) for value in values),
              'min':min(values),'max':max(values),'p25':percentile(.25),'p75':percentile(.75),'samples':values}
    require(set(actual)==set(expected) and actual['n']==len(values),label+' summary fields/count differ')
    for key,value in expected.items():
        if key in {'n','samples'}:continue
        require(math.isclose(actual[key],value,rel_tol=1e-12,abs_tol=0),label+' '+key+' differs')
    require(len(actual['samples'])==len(values) and all(math.isclose(left,right,rel_tol=1e-12,abs_tol=0)
            for left,right in zip(actual['samples'],values)),label+' samples differ')

def measured_ratios(actual,values,label):
    require(len(actual['per_round'])==len(values),label+' paired rounds differ')
    for i,(row,value) in enumerate(zip(actual['per_round'],values)):
        require(row['round']==i and math.isclose(row['ratio'],value,rel_tol=1e-12,abs_tol=0),label+' paired ratio differs')
    measured_summary(actual['ratio'],values,label)

def validate_named_arithmetic(report):
    rounds=range(report['configuration']['samples']);tasks=[case['name'] for case in report['workloads']]
    indexed={(row['task'],row['variant'],row['round']):row['timed_region_seconds']
             for row in report['observations'] if row['phase']=='measure'}
    require(len(report['summary'])==len(tasks) and [row['task'] for row in report['summary']]==tasks,
            'warmed summary task inventory differs')
    for summary in report['summary']:
        task=summary['task'];variants=list(report['artifacts'][task])
        require(set(summary['times'])==set(variants) and summary['reference_roles']==report['reference_roles'][task],
                'warmed summary variant/role inventory differs')
        for variant in variants:
            measured_summary(summary['times'][variant],[indexed[task,variant,i] for i in rounds],'warmed '+task+'/'+variant)
        pairs=list(itertools.combinations(variants,2))
        require([(row['numerator'],row['denominator']) for row in summary['paired_ratios']]==pairs,
                'warmed artifact-pair inventory differs')
        for row,(numerator,denominator) in zip(summary['paired_ratios'],pairs):
            measured_ratios(row,[indexed[task,numerator,i]/indexed[task,denominator,i] for i in rounds],
                            'warmed '+task+'/'+numerator+'/'+denominator)
    comparisons=[(left,right,'compiler') for left,right in itertools.combinations(report['compilers'],2)]
    if report['configuration']['references']:
        comparisons.extend((name,role,'reference_role') for name in report['compilers']
                           for role in ['original_direct','gcc_O2_anchor','selected_native','selected_wasm'])
    require([(row['numerator'],row['denominator'],row['kind']) for row in report['geometric_ratios']]==comparisons,
            'warmed geometric comparison inventory differs')
    for row,(numerator,denominator,kind) in zip(report['geometric_ratios'],comparisons):
        require(row['tasks']==tasks,'warmed geometric task inventory differs');values=[]
        for i in rounds:
            ratios=[]
            for task in tasks:
                target=denominator
                if kind=='reference_role':target=report['reference_roles'][task][denominator]
                ratios.append(indexed[task,numerator,i]/indexed[task,target,i])
            values.append(math.exp(sum(math.log(value) for value in ratios)/len(ratios)))
        measured_ratios(row,values,'warmed geometric '+numerator+'/'+denominator)

def validate_named(report,reference,compiler_sha,v8=False):
    require(report['status']=='passed' and not report['failures'] and report['coverage_exact'],'kernel report failed')
    config = report['configuration']; samples = config['samples']
    require(type(samples) is int and samples>=9 and config['cpu']==2,'kernel sampling configuration')
    require(report['workloads']==reference['workloads'] and len(report['workloads'])==10,'kernel workload drift')
    require(report['selection']==reference['selection'],'frozen selection drift')
    require(set(report['compilers'])==set(config['compilers'])=={'baseline','final'},'named compiler comparison inventory differs')
    require(report['compilers']['baseline']['sha256']==BASELINE_SHA and
            report['compilers']['final']['sha256']==compiler_sha,'named baseline/final compiler differs')
    for name,compiler in report['compilers'].items():
        require(compiler['binary']==config['compilers'][name] and report['input_sha256'][compiler['binary']]==compiler['sha256'],
                'named compiler command/input identity differs')
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
    validate_named_arithmetic(report)

def validate_current(reports, reference, compiler_sha):
    require(reference['status']=='passed' and not reference['failures'], 'reference failed')
    for name, report in reports.items():
        if name != 'differential.json': require(report['status'] in {'passed','pass'}, ('report failed', name))
        require(not report.get('failures'), ('report failures', name))
    for name in ('qualification.json','differential.json','host-qualification.json'):
        require(reports[name]['compiler_sha256']==compiler_sha, ('qualification compiler differs', name))
    for name in ('cohort.json','examples.json','host.json'):
        require(reports[name]['environment']['compiler_sha256']==compiler_sha, ('measurement compiler differs', name))
        require(reports[name]['environment']['wasmtime']==reference['host_build']['version'], ('engine differs', name))
    require(reports['final-warmed.json']['configuration']['samples']==9, 'require nine fresh Wasmtime pairs')
    require(reports['final-v8.json']['configuration']['samples']==9, 'require nine fresh V8 pairs')
    require(len(reports['final-warmed.json']['observations'])==550, 'Wasmtime named coverage differs')
    require(len(reports['final-v8.json']['observations'])==200, 'V8 named coverage differs')
    replay=reports['host-qualification.json']
    require(replay['unique_wasm']==len({row['wasm_sha256'] for row in replay['preparations']}), 'current unique modules differ')
    counts={'focused_commands':74,'differential_observations':9573,'native_comparisons':7656,'cases':978,
            'host_observations':11484,'host_modules':replay['unique_wasm']}
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
        if row['mode'] in {'native','native-serial'}:
            command=row['command']
            prefix=[host_config['host'],'--no-cache']
            if row['mode']=='native-serial':prefix.append('--no-parallel-compilation')
            require(command[:-1]==prefix and not any(arg=='--cache' or arg.startswith('--cache-config') for arg in command),
                    'ordinary host launch cache policy differs')
    for row in host['preparation']:
        hashes={item['artifact_sha256'] for item in builds if item['name']==row['name'] and item['backend']==row['backend']}
        require(hashes=={row['wasm_sha256']},'host/example guest identity differs')
        prefix=[host_config['host'],'--no-cache']
        if row['configuration']=='serial':prefix.append('--no-parallel-compilation')
        require(row['command'][:-2]==prefix+['--compile'] and row['command'][-1]==row['artifact'] and
                not any(arg=='--cache' or arg.startswith('--cache-config') for arg in row['command']),
                'host preparation cache policy differs')
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


def validate_lifecycle(report,reports,compiler_sha,smoke=False):
    require(report['schema']=='goose-runtime-lifecycle-v1','lifecycle schema differs')
    expected_status='passed'
    if smoke:expected_status='passed-smoke'
    require(report['status']==expected_status and not report['failures'],'lifecycle report failed')
    config=report['configuration'];samples=config['samples'];warmups=config['warmups']
    modes={'ordinary','cache-miss','cache-hit','precompiled','native-C','worker-hit'}
    names=set(config['example_names']);known={row['name']:row for row in reports['examples.json']['examples']}
    require(set(config['modes'])==modes and names<=known.keys(),'lifecycle workload/mode inventory differs')
    require(config['smoke']==smoke and type(samples) is int and samples>0 and type(warmups) is int and warmups>=0,'lifecycle sample configuration differs')
    if not smoke:require(len(names)==10 and samples==15 and warmups==1,'full lifecycle coverage differs')
    environment=report['environment']
    require(environment['compiler']['sha256']==compiler_sha,'lifecycle compiler differs')
    require(environment['host_build']==reports['host-qualification.json']['host_build'],'lifecycle actual host metadata differs')
    require(environment['native_host']['sha256']==environment['host_build']['host_sha256'],'lifecycle host identity differs')
    require(report['artifact_sha256_still_match'] and report['precompiled_sha256_still_match'],'lifecycle artifacts changed')
    expected={(name,mode,phase,round_) for name in names for mode in modes
              for phase,start,count in [('warmup',0,warmups),('measure',warmups,samples)]
              for round_ in range(start,start+count)}
    exact(report['observations'],('name','mode','phase','round'),expected,'lifecycle')
    golden={}
    summaries={row['name']:row for row in report['examples']}
    require(len(report['examples'])==len(names) and set(summaries)==names,'lifecycle summary inventory differs')
    require(set(report['preparation'])==names and set(report['worker_lifecycle'])==names,'lifecycle preparation inventory differs')
    host=environment['native_host']['path'];miss_configs=set()
    for name in names:
        suffix='/examples/'+known[name]['expected']
        matches={value for path,value in reports['examples.json']['environment']['input_sha256'].items() if path.endswith(suffix)}
        require(len(matches)==1,'lifecycle golden identity missing');golden[name]=next(iter(matches))
        artifacts=summaries[name]['artifacts'];prep=report['preparation'][name]
        require(prep['cache_warm']['command']==[host,'--cache-config',prep['cache_config'],artifacts['direct']['path']] and
                prep['precompile']['command']==[host,'--no-cache','--compile',artifacts['direct']['path'],prep['precompiled']],
                'lifecycle preparation command/artifact edge differs')
        require(prep['cache_warm']['returncode']==prep['precompile']['returncode']==0 and
                not prep['cache_warm']['stderr'] and not prep['precompile']['stderr'] and
                hashlib.sha256(prep['cache_warm']['stdout'].encode()).hexdigest()==golden[name],
                'lifecycle preparation output differs')
        require(prep['cache_config'] in report['final_cache_file_manifest'] and
                report['final_cache_file_manifest'][prep['cache_config']]['sha256']==prep['cache_config_sha256'] and
                prep['cache_directory']==str(Path(prep['cache_config']).parent/'entries'),
                'lifecycle prepared cache identity differs')
    for row in report['observations']:
        artifacts=summaries[row['name']]['artifacts'];prep=report['preparation'][row['name']]
        require(row['returncode']==0 and not row['stderr'] and hashlib.sha256(row['stdout'].encode()).hexdigest()==golden[row['name']],
                'lifecycle output/golden differs')
        require(type(row['wall_ns']) is int and row['wall_ns']>0 and row['wall_seconds']==row['wall_ns']/1e9,'lifecycle timer differs')
        if row['phase']=='measure':require(row['sample']==row['round']-warmups,'lifecycle sample index differs')
        if row['mode']=='worker-hit':
            require(row['cache_hit'] is True and row['process_command']==[host,'--serve','--no-cache'] and
                    row['request_module']==artifacts['direct']['path'],'worker lifecycle configuration/artifact differs')
        elif row['mode'] in ('ordinary','precompiled'):
            command=[host,'--no-cache',artifacts['direct']['path']]
            if row['mode']=='precompiled':command=[host,'--no-cache','--precompiled',prep['precompiled']]
            require(row['command']==command,'cold lifecycle command/artifact differs')
        elif row['mode']=='native-C':
            require(row['command']==[artifacts['native']['path']],'native lifecycle command/artifact differs')
        elif row['mode'] in ('cache-miss','cache-hit'):
            config_path=row['cache_config']['path']
            require(row['command']==[host,'--cache-config',config_path,artifacts['direct']['path']],
                    'cache lifecycle command/artifact differs')
            require(row['cache_config']['path'] in report['final_cache_file_manifest'] and
                    report['final_cache_file_manifest'][row['cache_config']['path']]['sha256']==row['cache_config']['sha256'],
                    'lifecycle cache config is not retained in the exact manifest')
            if row['mode']=='cache-hit':
                require(config_path==prep['cache_config'] and row['cache_state_expected']=='hit','lifecycle hit cache is not prepared cache')
            else:
                require(config_path not in miss_configs and config_path not in {item['cache_config'] for item in report['preparation'].values()} and
                        row['cache_state_expected']=='miss','lifecycle miss cache is not fresh per row')
                miss_configs.add(config_path)
    for name in names:
        lifecycle=report['worker_lifecycle'][name]
        require(lifecycle['first_returncode']==0 and not lifecycle['first_stderr'] and lifecycle['first_cache_hit'] is False and
                hashlib.sha256(lifecycle['first_stdout'].encode()).hexdigest()==golden[name],'worker initial request differs')
        require(lifecycle['resident_process_count']==1 and lifecycle['session_command']==[host,'--serve','--no-cache'],
                'worker startup policy differs')
        for mode in modes:
            values=[row['wall_seconds'] for row in report['observations'] if row['name']==name and row['mode']==mode and row['phase']=='measure']
            median=statistics.median(values);summary=summaries[name]['modes'][mode]
            require(summary=={'n':samples,'median_seconds':median,'mad_seconds':statistics.median(abs(value-median) for value in values),
                              'samples_seconds':values},'lifecycle median/MAD differs')
        direct={row['artifact_sha256'] for row in reports['examples.json']['observations'] if row['kind']=='build' and row['name']==name and row['backend']=='direct'}
        native={row['artifact_sha256'] for row in reports['examples.json']['observations'] if row['kind']=='build' and row['name']==name and row['backend']=='native'}
        if not smoke:
            require(direct=={summaries[name]['artifacts']['direct']['sha256']} and native=={summaries[name]['artifacts']['native']['sha256']},
                    'lifecycle/example guest identity differs')
    require(report['final_cache_file_manifest'] and all(item['kind'] in {'config','cache-entry-or-stat'} and item['bytes']>=0
            for item in report['final_cache_file_manifest'].values()),'lifecycle cache payload/counter inventory missing')
