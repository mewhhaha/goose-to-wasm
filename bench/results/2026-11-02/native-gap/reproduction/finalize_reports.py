"""Connect the retained final cohort, source identities and README charts."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'bench/results/2026-11-02/native-gap'
BUILD = ROOT / 'build/native-gap'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write(path, data):
    path.write_text(json.dumps(data, indent=2) + '\n')

candidate = BUILD / 'dispatch'
pin = digest(candidate / 'bin/goose')
source_identity = json.loads((candidate / 'source.json').read_text())
examples = json.loads((BUILD / 'example-benchmarks/report.json').read_text())
paired = json.loads((BUILD / 'dispatch-pairs/report.json').read_text())
modes = json.loads((BUILD / 'dispatch-modes/report.json').read_text())
qualification = json.loads((BUILD / 'qualification/report.json').read_text())
differential = json.loads((BUILD / 'differential/report.json').read_text())
cohort = json.loads((OUT / 'cohort.json').read_text())
assert {pin} == {examples['environment']['compiler_sha256'], cohort['environment']['compiler_sha256'],
                  modes['compiler_sha256']['candidate'], qualification['compiler_sha256'],
                  differential['compiler_sha256'], paired['input_sha256'][str((candidate/'bin/goose').resolve())]}
assert examples['environment']['compiler_source_identity'] == paired['compiler_sources']['candidate'] == source_identity
assert examples['status'] == cohort['status'] == paired['status'] == modes['status'] == qualification['status'] == 'passed'
assert not examples['failures'] and not cohort['failures'] and differential['failures'] == 0
assert differential['observations'] == len(differential['results']) == 9453
assert differential['qualification_execution']['native_stdout_comparisons'] == 7560
assert len(examples['observations']) == 1600 and len(cohort['observations']) == 315
assert len(qualification['commands']) == 44 and all(row['exit_status'] == 0 for row in qualification['commands'])
previous = json.loads((ROOT / 'bench/results/2026-11-02/prefix-resolution/cohort.json').read_text())
assert cohort['status'] == 'passed'
identities = {}
for name in ['baseline','block','outline','images','hybrid','dispatch']:
    directory = BUILD / name
    identities[name] = {'compiler_sha256': digest(directory / 'bin/goose'),
                        'source': json.loads((directory / 'source.json').read_text()),
                        'toolchain': json.loads((directory / 'toolchain.json').read_text())}
write(OUT / 'compiler-identities.json', identities)
cache = (ROOT / 'build/native/CMakeCache.txt').read_text().splitlines()
write(OUT / 'compiler-build.json', {
    'base_revision':'fe884fa9c2e92b3b0eb5d07701ef432bbcaa590e',
    'patch_sha256':digest(OUT / 'compiler-changes.patch'),
    'compiler_sha256':identities['dispatch']['compiler_sha256'],
    'cxx_version':subprocess.check_output(['/usr/bin/clang++','--version'],text=True),
    'cmake_configuration':[line for line in cache if line.startswith(('CMAKE_CXX_','CMAKE_BUILD_TYPE:','CMAKE_GENERATOR:'))]})

def artifacts(report):
    result = {}
    for row in report['observations']:
        if row['kind'] == 'build' and row['backend'] == 'direct':
            result.setdefault(row['task'], set()).add(row['artifact_sha256'])
    assert len(result) == 7
    assert all(len(values) == 1 for values in result.values())
    return {task: next(iter(values)) for task, values in result.items()}

old, new = artifacts(previous), artifacts(cohort)
comparison = [{'task': task, 'old_sha256': old[task], 'candidate_sha256': new[task],
               'identical': old[task] == new[task]} for task in sorted(new)]
assert all(row['identical'] for row in comparison)
write(OUT / 'artifact-comparison.json', {'status':'passed','comparison':comparison})
references = ['cohort.json','paired.json','compiler-identities.json','artifact-comparison.json']
write(OUT / 'readme.json', {
    'schema':'goose-readme-benchmarks-v1', 'status':'passed',
    'chart':{'date':'2026-11-02','host':'AMD Ryzen 7 3800X','samples':5,
             'compilation_note':'All backends measured in the same cohort.',
             'runtime_note':'Preparation, warmups and startup excluded. Native reference repeated in both panels.'},
    'method':'One fresh same-host cohort measures all three backends with the same current compiler and adapted sources. '
             'Backends are not interleaved pairs. Direct Wasm is memory32; C-to-Wasm is memory64. '
             'Native reference is repeated in both engine panels. The seven direct modules are byte-identical '
             'to the previous cohort; no kernel speedup is attributed to array-image dispatch.',
    'sources':{name:digest(OUT/name) for name in references},
    'compile_summary':cohort['compile_summary'], 'runtime_summary':cohort['runtime_summary']})
write(ROOT/'bench/results/latest.json', {'schema':'goose-readme-latest-v1','report':'2026-11-02/native-gap/readme.json'})
example_report = ROOT/'bench/results/2026-11-02/compact-examples/report.json'
write(ROOT/'bench/results/examples-latest.json', {'schema':'goose-example-benchmarks-latest-v1',
      'report':'2026-11-02/compact-examples/report.json','sha256':digest(example_report)})
print('Final cohorts and chart pointers connected')
