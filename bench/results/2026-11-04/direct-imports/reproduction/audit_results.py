#!/usr/bin/env python3
"""Read-only semantic audit of the direct-imports campaign; no guest execution."""
import sys
sys.dont_write_bytecode = True
import argparse
import collections
from datetime import datetime
import gzip
import hashlib
import itertools
import json
import math
from pathlib import Path
import random
import re
import statistics
import tarfile

COMPILER = '8c09c1a6bcc782de5b86dda621a91ae234acba8fbe108d146582113eb6a110b6'
NAMES = {'squares', 'tour', 'functions', 'errors', 'sieve', 'sorting', 'sudoku', 'maze', 'vm', 'life'}


def need(ok, message):
    if not ok:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def near(a, b):
    need(math.isfinite(a) and math.isclose(a, b, rel_tol=1e-12, abs_tol=1e-15),
         f'numeric mismatch: {a} != {b}')


def summary(record, values):
    need(record['n'] == len(values) and all(math.isfinite(x) and x > 0 for x in values), 'invalid sample vector')
    median = statistics.median(values)
    near(record['median'], median)
    near(record['mad'], statistics.median(abs(x - median) for x in values))
    if 'samples' in record:
        need(len(record['samples']) == len(values), 'sample vector length')
        for actual, expected in zip(record['samples'], values):
            near(actual, expected)


def exact(rows, keys, expected):
    found = {tuple(row[key] for key in keys): row for row in rows}
    need(len(found) == len(rows) and set(found) == expected, 'duplicate/missing/extra rows: ' + str(keys))
    return found


class Evidence:
    def __init__(self, out, prior_root=None):
        self.out = out.resolve()
        self.prior_root = prior_root
        self.index = json.loads(gzip.decompress((self.out / 'archives.json.gz').read_bytes()))
        self.spec = json.loads((self.out / 'retention.json').read_text())['specification']
        self.by_sha = {row['sha256']: row for row in self.index['inputs'].values()}
        self.payloads = {}
        self.reports = {}
        for name, location in self.index['reports'].items():
            data = (self.out / name).read_bytes()
            need(sha(data) == location['sha256'], 'public report binding: ' + name)
            self.reports[name] = json.loads(data)
        need(self.index['identity_only'] == {}, 'release promises zero identity-only omissions')

    def read_many(self, identities):
        requested = collections.defaultdict(dict)
        for identity in set(identities) - self.payloads.keys():
            need(identity in self.by_sha, 'semantic input missing from retained byte namespace')
            location = self.by_sha[identity]
            requested[location['archive']][location['member']] = identity
        for name, members in requested.items():
            path = self.out / name
            if self.prior_root is not None and name.startswith('../minimal-aot/'):
                path = self.prior_root / name[len('../minimal-aot/'):]
            with tarfile.open(path, 'r:gz') as archive:
                for member in archive:
                    if member.name not in members:
                        continue
                    need(member.isfile(), 'nonregular semantic input')
                    data = archive.extractfile(member).read()
                    identity = members[member.name]
                    need(sha(data) == identity, 'semantic payload digest')
                    self.payloads[identity] = data
        need(set(identities) <= self.payloads.keys(), 'semantic payload unavailable')

    def doc(self, identity):
        self.read_many([identity])
        return json.loads(self.payloads[identity])

    def pin(self, path, identity):
        need(path + '@' + identity in self.index['inputs'], 'unretained input: ' + path)


    def document(self, relative):
        suffix = '/' + relative
        locations = [row for path, row in self.index['documents'].items() if path.endswith(suffix)]
        need(len(locations) == 1, 'semantic document binding: ' + relative)
        return self.doc(locations[0]['sha256'])


def compiler_reference(evidence):
    spec = evidence.spec['semantic']
    original = evidence.doc(spec['original_compiler_report_sha256'])
    derived = evidence.document(spec['baseline_report'])
    derivation = evidence.document(spec['baseline_aliases'])
    pins = original['qualification_execution']['input_sha256']
    need(len(pins) == spec['compiler_reference_pins'] and
         len(derivation['input_aliases']) == spec['compiler_reference_aliases'], 'strict compiler alias counts')
    expected = {derivation['input_aliases'].get(path, path): identity for path, identity in pins.items()}
    need(len(expected) == len(pins) and derived['qualification_execution']['input_sha256'] == expected,
         'compiler alias pin mapping')
    restored = dict(derived)
    need(restored.pop('reference_derivation') == derivation, 'derivation metadata mismatch')
    restored['qualification_execution'] = {**restored['qualification_execution'], 'input_sha256': pins}
    need(restored == original, 'alias view modifies historical evidence')
    need(derivation['original_report_sha256'] == spec['original_compiler_report_sha256'], 'original compiler report binding')
    need(original['compiler_sha256'] == COMPILER and original['observations'] == len(original['results']) == 9573 and
         original['cases'] == 978 and original['failures'] == 0, 'compiler reference identity/counts')
    need(sum(row.get('kind') == 'compile-refusal' for row in original['results']) == 3 and
         all(row['status'] == 'pass' for row in original['results']), 'compiler reference outcomes')
    for path, identity in expected.items():
        evidence.pin(path, identity)
    guests = {row['sha256'] for row in original['results'] if 'sha256' in row}
    need(guests <= evidence.by_sha.keys(), 'compiler reference guest bytes omitted')
    return {(row['case'], row['optimization'], row['debug'], row['backend'], row['engine']): row
            for row in original['results'] if row.get('kind') != 'compile-refusal'}


def audit_paired(report):
    need(report['schema'] == 'goose-remaining-hills-paired-v1' and report['status'] == 'passed', 'paired report failed')
    need(report['input_sha256'] == report['input_sha256_after'], 'paired input drift')
    config = report['configuration']
    cells = config['cells']
    affinities = config.get('affinities', ['pool', 'cpu2'])
    phases = [('warmup', config.get('warmups', 2)), ('measure', config.get('samples', 61))]
    expected = {(a, cell, phase, i) for a in affinities for cell in cells for phase, count in phases for i in range(count)}
    rows = exact(report['observations'], ['affinity', 'cell', 'phase', 'sample'], expected)
    for row in rows.values():
        need(row['exit_code'] == 0 and row['stderr'] == '', 'paired output status')
    for affinity in affinities:
        group = report['summary'][affinity]
        values = {cell: [rows[affinity, cell, 'measure', i]['wall_ns'] for i in range(config.get('samples', 61))] for cell in cells}
        for cell, vector in values.items():
            summary(group['wall_us'][cell], [x / 1000 for x in vector])
        for numerator, denominator in config['comparisons']:
            ratios = [x / y for x, y in zip(values[numerator], values[denominator])]
            record = group['paired_ratios'][numerator + '/' + denominator]
            summary(record, ratios)
            need(len(record['bootstrap_95_ci']) == 2, 'paired confidence interval cardinality')
            rng = random.Random(config.get('seed', 2026110412))
            boots = sorted(statistics.median(rng.choices(ratios, k=len(ratios))) for _ in range(10000))
            for actual, expected in zip(record['bootstrap_95_ci'], [boots[249], boots[9749]]):
                near(actual, expected)
    return len(rows)


def paired_campaign(evidence, name, report):
    all_names = sorted(NAMES)
    definitions = {
        'startup-paired.json': (['empty', 'print-only', 'functions', 'large-data'], ['baseline', 'aa_clone', 'direct', 'no_cow'], '_', 61, 2026110427),
        'startup-confirmation.json': (['functions', 'empty'], ['baseline', 'aa', 'direct', 'native'], '_', 201, 2026110433),
        'startup-regression.json': (all_names, ['baseline', 'aa', 'direct', 'native'], '_', 31, 2026110431),
        'raw-paired.json': (['empty', 'print-only', 'functions'], ['original', 'aa_clone', 'direct', 'raw', 'native'], '-', 201, 2026110419),
        'final-functions.json': (['functions'], ['baseline', 'aa', 'direct', 'final', 'native'], '_', 201, 2026110459),
        'final-regression.json': (all_names, ['baseline', 'aa', 'direct', 'final', 'native'], '_', 31, 2026110461),
        'vm-confirmation.json': (['vm'], ['baseline', 'aa', 'direct', 'final', 'native'], '_', 201, 2026110469),
    }
    workloads, variants, separator, samples, seed = definitions[name]
    expected = {workload + separator + variant for workload in workloads for variant in variants}
    config = report['configuration']
    need(set(config['cells']) == expected and config['samples'] == samples and config['warmups'] == 2 and
         config['affinities'] == ['pool', 'cpu2'] and config['seed'] == seed, 'paired campaign scope: ' + name)
    comparison_variants = [('direct', 'baseline'), ('aa', 'baseline'), ('direct', 'native')]
    if name == 'startup-paired.json':
        comparison_variants = [('aa_clone', 'baseline'), ('direct', 'baseline'), ('no_cow', 'baseline')]
    elif name == 'raw-paired.json':
        comparison_variants = [('raw', 'direct'), ('raw', 'original'), ('raw', 'aa_clone'), ('direct', 'original'),
                               ('aa_clone', 'original'), ('raw', 'native')]
    elif name in {'final-functions.json', 'final-regression.json', 'vm-confirmation.json'}:
        comparison_variants = [('final', 'baseline'), ('aa', 'baseline'), ('final', 'native'), ('final', 'direct')]
    expected_comparisons = {(workload + separator + left, workload + separator + right)
                            for workload in workloads for left, right in comparison_variants}
    need(len(config['comparisons']) == len(expected_comparisons) and
         {tuple(row) for row in config['comparisons']} == expected_comparisons, 'paired comparison inventory')
    for group in report['summary'].values():
        need(set(group['wall_us']) == expected and
             set(group['paired_ratios']) == {left + '/' + right for left, right in expected_comparisons}, 'paired summary inventory')
    needed = []
    for cell in config['cells'].values():
        expected_path = cell['expected']
        need(expected_path in report['input_sha256'], 'paired golden input pin')
        needed.append(report['input_sha256'][expected_path])
    evidence.read_many(needed)
    for key, cell in config['cells'].items():
        workload, variant = key.rsplit(separator, 1)
        if separator == '-' and key.endswith('-aa_clone'):
            workload, variant = key[:-9], 'aa_clone'
        expected_stdout = evidence.payloads[report['input_sha256'][cell['expected']]].decode()
        for row in report['observations']:
            if row['cell'] == key:
                need(row['stdout'] == expected_stdout, 'paired golden stdout: ' + key)
        executable = cell['executable']
        need(executable in report['input_sha256'], 'paired executable pin')
        command = cell['command']
        evidence.pin(command[0], report['input_sha256'][executable])
        if 'aot' in cell:
            need(len(command) == 3 and command[1] == '--precompiled', 'paired AOT command shape')
            evidence.pin(command[2], report['input_sha256'][cell['aot']])
        else:
            need(len(command) == 1, 'paired native command shape')
        if name.startswith('final-') and variant == 'final':
            need(report['input_sha256'][executable] == evidence.spec['semantic']['minimal_host_sha256'], 'final paired product identity')
        for path, identity in report['input_sha256'].items():
            evidence.pin(path, identity)
    return audit_paired(report)


def audit_delivery(evidence):
    reports = evidence.reports
    parent = reports['delivery-execution.json']
    need(parent['compiler_sha256'] == COMPILER and parent['input_sha256'] == parent['input_sha256_after'], 'delivery identity drift')
    phases = exact(parent['phases'], ['name'], {('examples',), ('host',), ('lifecycle',)})
    need([row['name'] for row in parent['phases']] == ['examples', 'host', 'lifecycle'], 'delivery phase order')
    previous = datetime.fromisoformat(parent['started_utc'])
    for name, count in [('examples', 1600), ('host', 1760), ('lifecycle', 960)]:
        row = phases[name,]
        child = reports[name + '.json']
        location = evidence.index['reports'][name + '.json']
        need(row['exit_status'] == 0 and row['report_sha256'] == location['sha256'] and
             row['observations'] == len(child['observations']) == count, 'delivery phase link: ' + name)
        evidence.pin(row['report'], row['report_sha256'])
        started = datetime.fromisoformat(row['started_utc'])
        finished = datetime.fromisoformat(row['finished_utc'])
        need(previous <= started <= finished, 'delivery phase interval')
        previous = finished
    need(previous <= datetime.fromisoformat(parent['finished_utc']), 'delivery completion interval')
    need(all(value is None for value in parent['environment']['controls'].values()), 'delivery runtime controls')
    need(parent['schema'] == 'goose-direct-imports-delivery-execution-v2', 'delivery resumption schema')
    resumed = parent['resumption']
    failed = evidence.doc(resumed['failed_checkpoint_sha256'])
    need(failed['status'] == 'failed' and 'No space left' in failed['error'] and
         failed['phases'] == [parent['phases'][0]], 'failed checkpoint/completed example resumption')
    need(failed['environment'] == parent['environment'] and failed['compiler_sha256'] == parent['compiler_sha256'] and
         failed['started_utc'] == parent['started_utc'] and
         datetime.fromisoformat(failed['finished_utc']) <= datetime.fromisoformat(parent['resumed_utc']) <=
         datetime.fromisoformat(phases['host',]['started_utc']), 'delivery resumption identity/interval')
    need(all(parent['input_sha256'].get(path) == identity for path, identity in failed['input_sha256'].items()),
         'resumption changes original cohort inputs')
    evidence.pin(resumed['failed_checkpoint'], resumed['failed_checkpoint_sha256'])
    evidence.pin(resumed['driver_log'], resumed['driver_log_sha256'])
    completion = evidence.document('build/remaining-hills/delivery-execution-final/completion.json')
    need(completion['status'] == 'passed' and completion['report_sha256'] ==
         evidence.index['reports']['delivery-execution.json']['sha256'], 'delivery final completion record')
    for path, identity in parent['input_sha256'].items():
        evidence.pin(path, identity)


def audit_final_preparation(evidence, goldens):
    preparation = evidence.document('build/remaining-hills/final-pairs/preparation.json')
    need(preparation['status'] == 'passed', 'final paired preparation status')
    artifacts = exact(preparation['artifacts'], ['name'], {(name,) for name in NAMES})
    regression = evidence.reports['final-regression.json']
    cells = regression['configuration']['cells']
    expected_checks = set()
    for name in NAMES:
        artifact = artifacts[name,]
        need(regression['input_sha256'][artifact['wasm']] == regression['input_sha256'][artifact['previous']] ==
             artifact['sha256'], 'unchanged final direct Wasm identity')
        evidence.pin(artifact['wasm'], artifact['sha256'])
        evidence.pin(artifact['previous'], artifact['sha256'])
        evidence.pin(artifact['aot'], artifact['aot_sha256'])
        evidence.pin(artifact['prepared_aot'], artifact['aot_sha256'])
        for variant in ['baseline', 'aa', 'direct', 'final']:
            cell = cells[name + '_' + variant]
            need(cell['aot'] == artifact['aot'] and regression['input_sha256'][cell['aot']] == artifact['aot_sha256'],
                 'final paired common AOT link')
            expected_checks.add((cell['executable'], '--precompiled', artifact['aot']))
    checks = {tuple(row['command']): row for row in preparation['checks']}
    need(len(checks) == len(preparation['checks']) == 40 and set(checks) == expected_checks, 'final paired preflight checks')
    names_by_aot = {row['aot']: row['name'] for row in preparation['artifacts']}
    for command, row in checks.items():
        need(row['exit_code'] == 0 and row['stderr'] == '' and row['stdout_sha256'] == goldens[names_by_aot[command[-1]]],
             'final paired preflight output')
    for report_name in ['final-functions.json', 'vm-confirmation.json']:
        report = evidence.reports[report_name]
        for key, cell in report['configuration']['cells'].items():
            need(cell == cells[key] or all(cell.get(field) == cells[key].get(field) for field in ['executable', 'aot', 'expected']),
                 'final confirmation/regression input identity')
            for path, identity in report['input_sha256'].items():
                if path in regression['input_sha256']:
                    need(regression['input_sha256'][path] == identity, 'final paired campaign shared input identity')


def audit_public_bindings(evidence):
    bindings = evidence.index['public_bindings']
    if not bindings:
        return 0
    names = ['bench/results/examples-latest.json', 'bench/results/wasmtime-host-latest.json',
             'bench/results/runtime-lifecycle-latest.json', 'bench/results/latest.json',
             'bench/results/runtime-targets-latest.json', 'bench/wasmtime-host.md']
    evidence.read_many([bindings[name]['sha256'] for name in names])
    for path, report in zip(names[:3], ['examples.json', 'host.json', 'lifecycle.json']):
        pointer = json.loads(evidence.payloads[bindings[path]['sha256']])
        need(pointer['report'] == '2026-11-04/direct-imports/' + report and
             pointer['sha256'] == evidence.index['reports'][report]['sha256'], 'current report pointer binding')
    for path in names[3:5]:
        need('leaf-and-loads' in evidence.payloads[bindings[path]['sha256']].decode(), 'separately collected reference pointer')
    medians = {(row['name'], row['backend'], row['mode']): row['wall_seconds']['median'] * 1000
               for row in evidence.reports['host.json']['runtime_summary']}
    found = set()
    document = evidence.payloads[bindings['bench/wasmtime-host.md']['sha256']].decode()
    for line in document.splitlines():
        cells = [cell.strip() for cell in line.strip().strip('|').split('|')]
        if len(cells) != 5 or cells[0].lower() not in NAMES:
            continue
        name = cells[0].lower()
        keys = [(name, 'direct', 'native'), (name, 'direct', 'precompiled'),
                (name, 'direct', 'precompiled-minimal'), (name, 'native', 'native-C')]
        need(cells[1:] == [f'{medians[key]:.3f}' for key in keys], 'rounded published host table: ' + name)
        need(name not in found, 'duplicate rounded host table row')
        found.add(name)
    need(found == {'functions', 'sorting', 'sudoku', 'life'}, 'rounded host table coverage')
    return len(found)


def audit(out, prior_root=None):
    evidence = Evidence(out, prior_root)
    reports = evidence.reports
    need(all(report.get('status') in {'pass', 'passed'} for report in reports.values()), 'nonpassing primary report')
    e = reports['examples.json']
    h = reports['host.json']
    lifecycle = reports['lifecycle.json']
    identities = evidence.spec['semantic']
    need(h['host_build']['host_sha256'] == identities['full_host_sha256'] and
         h['aot_host_build']['host_sha256'] == identities['minimal_host_sha256'], 'current host identities')
    goldens = {}
    runs = [row for row in e['observations'] if row['kind'] == 'execution']
    builds = [row for row in e['observations'] if row['kind'] == 'build']
    for row in runs:
        need(row['status'] == 'passed', 'example run failed')
        goldens.setdefault(row['name'], row['stdout_sha256'])
        need(goldens[row['name']] == row['stdout_sha256'], 'example output drift')
    need(set(goldens) == NAMES, 'ten-example golden coverage')
    exact(builds, ['name', 'backend', 'sample'], set(itertools.product(NAMES, ['direct', 'c-wasm', 'native'], range(5))))
    exact(e['compile_summary'], ['name', 'backend'], set(itertools.product(NAMES, ['direct', 'c-wasm', 'native'])))
    ecells = {(n, b, g) for n in NAMES for b in ['direct', 'c-wasm'] for g in ['v8', 'wasmtime']} | {(n, 'native', 'native') for n in NAMES}
    expected = {(*cell, phase, i) for cell in ecells for phase, count in [('warmup', 1), ('measure', 15)] for i in range(count)}
    expected.update((*cell, 'measure-engine', i) for cell in ecells if cell[1] != 'native' for i in range(15))
    exact([row for row in runs if row['phase'] != 'qualification'], ['name', 'backend', 'engine', 'phase', 'sample'], expected)
    exact([row for row in runs if row['phase'] == 'qualification'], ['name', 'backend', 'engine'], ecells)
    exact(e['runtime_summary'], ['name', 'backend', 'engine'], ecells)
    for row in e['compile_summary']:
        summary(row['wall_seconds'], [x['wall_seconds'] for x in builds if (x['name'], x['backend']) == (row['name'], row['backend'])])
    for row in e['runtime_summary']:
        summary(row['process_wall_seconds'], [x['process_wall_seconds'] for x in runs if (x['name'], x['backend'], x['engine']) == (row['name'], row['backend'], row['engine']) and x['phase'] == 'measure'])
    cells = {(n, b, m) for n in NAMES for b in ['direct', 'c-wasm'] for m in ['python', 'native', 'native-serial', 'precompiled', 'precompiled-minimal']} | {(n, 'native', 'native-C') for n in NAMES}
    exact(h['observations'], ['name', 'backend', 'mode', 'phase', 'sample'], {(*c, p, i) for c in cells for p, n in [('measure', 15), ('warmup', 1)] for i in range(n)})
    exact(h['runtime_summary'], ['name', 'backend', 'mode'], cells)
    for row in h['observations']:
        need(row['exit_code'] == 0 and row['stdout_sha256'] == goldens[row['name']], 'host output')
    for row in h['runtime_summary']:
        summary(row['wall_seconds'], [x['wall_seconds'] for x in h['observations'] if (x['name'], x['backend'], x['mode']) == (row['name'], row['backend'], row['mode']) and x['phase'] == 'measure'])
    exact(h['preparation'], ['name', 'backend', 'configuration', 'sample'], set(itertools.product(NAMES, ['direct', 'c-wasm'], ['parallel', 'serial', 'minimal'], range(5))))
    exact(h['preparation_summary'], ['name', 'backend', 'configuration'], set(itertools.product(NAMES, ['direct', 'c-wasm'], ['parallel', 'serial', 'minimal'])))
    for row in h['preparation_summary']:
        summary(row['wall_seconds'], [x['wall_seconds'] for x in h['preparation'] if (x['name'], x['backend'], x['configuration']) == (row['name'], row['backend'], row['configuration'])])
    need({(r['name'], r['backend'], r['configuration'], r['sha256']) for r in h['preparation']} ==
         {(r['name'], r['backend'], r['configuration'], r['sha256']) for r in h['artifact_qualification']} and
         all(row['status'] == 'passed' for row in h['artifact_qualification']), 'current AOT artifact qualification')
    lifecycle_modes = ['ordinary', 'cache-miss', 'cache-hit', 'precompiled', 'native-C', 'worker-hit']
    normalized = [{**row, 'sample': row.get('sample', row['round'])} for row in lifecycle['observations']]
    exact(normalized, ['name', 'mode', 'phase', 'sample'],
          {(name, mode, phase, sample) for name in NAMES for mode in lifecycle_modes
           for phase, count in [('warmup', 1), ('measure', 15)] for sample in range(count)})
    exact(lifecycle['examples'], ['name'], {(name,) for name in NAMES})
    lifecycle_examples = {row['name']: row for row in lifecycle['examples']}
    host = lifecycle['environment']['native_host']['path']
    need(lifecycle['environment']['native_host']['sha256'] == identities['full_host_sha256'] and
         lifecycle['environment']['host_build']['host_sha256'] == identities['full_host_sha256'], 'lifecycle product host identity')
    miss_paths = set()
    for example in lifecycle['examples']:
        need(set(example['modes']) == set(lifecycle_modes), 'lifecycle summary inventory')
        for mode, record in example['modes'].items():
            values = [row['wall_seconds'] for row in lifecycle['observations']
                      if row['name'] == example['name'] and row['mode'] == mode and row['phase'] == 'measure']
            summary({'n': record['n'], 'median': record['median_seconds'], 'mad': record['mad_seconds'],
                     'samples': record['samples_seconds']}, values)
    for row in lifecycle['observations']:
        need(row['returncode'] == 0 and row['stderr'] == '' and sha(row['stdout'].encode()) == goldens[row['name']], 'lifecycle output')
        near(row['wall_seconds'], row['wall_ns'] / 1e9)
        name, mode = row['name'], row['mode']
        artifacts = lifecycle_examples[name]['artifacts']
        if mode == 'worker-hit':
            need(row['process_command'] == [host, '--serve', '--no-cache'] and row['cache_hit'] is True and
                 row['request_module'] == artifacts['direct']['path'], 'resident worker request command/state')
        else:
            command = row['command']
            expected_command = [host]
            if mode == 'native-C':
                expected_command = [artifacts['native']['path']]
            elif mode in {'ordinary', 'precompiled'}:
                expected_command.append('--no-cache')
                if mode == 'precompiled':
                    expected_command += ['--precompiled', lifecycle['preparation'][name]['precompiled']]
                else:
                    expected_command.append(artifacts['direct']['path'])
            else:
                cfg = row['cache_config']
                expected_command += ['--cache-config', cfg['path'], artifacts['direct']['path']]
                evidence.pin(cfg['path'], cfg['sha256'])
                need(row['cache_state_expected'] == {'cache-miss': 'miss', 'cache-hit': 'hit'}[mode], 'lifecycle cache policy')
                if mode == 'cache-miss':
                    need(cfg['path'] not in miss_paths, 'cache-miss directory reused')
                    miss_paths.add(cfg['path'])
                else:
                    need(cfg['path'] == lifecycle['preparation'][name]['cache_config'], 'cache-hit preparation link')
            need(command == expected_command, 'lifecycle command identity: ' + mode)
    need(set(lifecycle['worker_lifecycle']) == NAMES, 'resident worker inventory')
    for name, worker in lifecycle['worker_lifecycle'].items():
        need(worker['first_returncode'] == 0 and not worker['first_cache_hit'] and worker['resident_process_count'] == 1 and
             worker['first_stderr'] == '' and sha(worker['first_stdout'].encode()) == goldens[name], 'fresh worker initialization')
        need(worker['session_command'] == [host, '--serve', '--no-cache'], 'worker process launch command')
    for path, record in lifecycle['final_cache_file_manifest'].items():
        evidence.pin(path, record['sha256'])
        need(evidence.index['inputs'][path + '@' + record['sha256']]['bytes'] == record['bytes'], 'cache byte extent')
    paired = {name: paired_campaign(evidence, name, report) for name, report in reports.items() if report.get('schema') == 'goose-remaining-hills-paired-v1'}
    need(set(paired) == {'startup-paired.json', 'startup-confirmation.json', 'startup-regression.json', 'raw-paired.json',
                         'final-functions.json', 'final-regression.json', 'vm-confirmation.json'}, 'startup campaign inventory')
    audit_final_preparation(evidence, goldens)
    audit_delivery(evidence)
    q = reports['qualification.json']
    need(q['compiler_sha256'] == COMPILER and q['input_sha256'] == q['input_sha256_after'] and
         q['coverage_exact'] and q['complete'] and q['active'] is None, 'qualification completion/identity')
    gate_counts = {'process': 13, 'native': 14, 'aot': 18, 'session': 9, 'compact-logs': 9,
                   'langarena': 16, 'runtime-reference': 12}
    gates = exact(q['commands'], ['name'], {(name,) for name in [*gate_counts, 'host-replay', 'minimal-replay']})
    need(q['fresh_gate_tests'] == sum(gate_counts.values()) == 91, 'fresh unit gate count')
    evidence.read_many([gates[name,]['log_sha256'] for name in gate_counts])
    for name, count in gate_counts.items():
        row = gates[name,]
        need(row['exit_status'] == 0 and row['expected_tests'] == row['observed_tests'] == count and
             row['coverage_exact'], 'fresh unit gate: ' + name)
        log = evidence.payloads[row['log_sha256']].decode()
        observed = re.findall(r'Ran (\d+) tests?', log)
        need(observed and int(observed[-1]) == count and re.search(r'^OK\s*$', log, re.MULTILINE), 'fresh unit gate log: ' + name)
    need(all(row['exit_status'] == 0 for row in q['commands']), 'qualification command exit')
    reference = compiler_reference(evidence)
    case_inputs = evidence.document(identities['case_inputs'])
    case_map = {(case['name'], case['debug']): case for case in case_inputs}
    need(len(case_inputs) == len(case_map) == 978, 'case-input manifest inventory')
    case_bytes = (json.dumps(case_inputs, sort_keys=True, indent=2) + '\n').encode()
    evidence.read_many([q[label]['report_sha256'] for label in ['host', 'minimal']])
    for label, count, backends, modes in [('host', 11484, {'direct', 'c-wasm'}, {'wasm', 'wasm-no-parallel', 'precompiled-no-parallel'}),
                                          ('minimal', 1914, {'direct'}, {'precompiled-minimal'})]:
        report = evidence.doc(q[label]['report_sha256'])
        need(report['status'] == 'pass' and report['coverage_exact'] and len(report['results']) == count and
             report['observations'] == report['expected_observations'] == count and report['failures'] == 0,
             'fresh replay coverage')
        need(set(report['configuration']['modes']) == modes and set(report['configuration']['backends']) == backends and
             report['configuration']['filter'] == '' and report['case_inputs_sha256'] == sha(case_bytes), 'fresh replay scope')
        need(report['input_sha256'] == report['input_sha256_after'] and report['aot_sha256'] == report['aot_sha256_after'], 'fresh replay drift')
        need(all(row['status'] == 'pass' and all(row['comparisons'].values()) for row in report['results']), 'fresh replay row failure')
        expected = {(case['name'], level, case['debug'], backend, mode) for case in case_inputs
                    for level in (0, 2) if level in case['levels'] for backend in backends for mode in modes}
        rows = exact(report['results'], ['case', 'optimization', 'debug', 'backend', 'mode'], expected)
        for key, row in rows.items():
            python = reference[key[:4] + ('wasmtime',)]
            native = reference[key[:3] + ('native', 'native')]
            case = case_map[key[0], key[2]]
            need(row['stdout'] == python['stdout'] == native['stdout'] and
                 row['exit_code'] == python['exit_code'] == native['exit_code'] == case['exit_code'],
                 'fresh replay differs from native/Python/case expectations')
            if case['stdout'] is not None:
                need(row['stdout'] == case['stdout'], 'fresh replay golden output')
            if not python['stderr']:
                need(row['stderr'] == '', 'fresh replay stderr-empty policy')
            if case['diagnostic']:
                need(case['diagnostic'].lower() in row['stderr'].lower(), 'fresh replay diagnostic policy')
            need(row['wasm_sha256'] == python['sha256'] and row['stdin_sha256'] == sha(case['stdin'].encode()),
                 'fresh replay guest/stdin identity')
            need(report['input_sha256'][row['module']] == row['wasm_sha256'] and row['fixture'] == case['fixture'],
                 'fresh replay module/fixture link')
            need(row['stdout_sha256'] == sha(row['stdout'].encode()) and
                 row['stderr_sha256'] == sha(row['stderr'].encode()) and not row['errors'], 'fresh replay output hashes/errors')
        need(report['compiler_sha256'] == COMPILER, 'fresh replay compiler identity')
        need(report['host_build']['host_sha256'] == identities['full_host_sha256'], 'fresh full-host identity')
        if label == 'minimal':
            need(report['aot_host_build']['host_sha256'] == identities['minimal_host_sha256'], 'fresh minimal-host identity')
        preparation_count = {'host': 1574, 'minimal': 679}[label]
        preparations = report['preparations']
        by_wasm = {row['wasm_sha256']: row for row in preparations}
        need(len(preparations) == len(by_wasm) == report['unique_wasm'] == len(report['aot_sha256']) == preparation_count,
             'fresh preparation coverage')
        need(set(by_wasm) == {row['sha256'] for row in report['modules']}, 'fresh preparation module inventory')
        for wasm, row in by_wasm.items():
            need(row['status'] == 'pass' and row['exit_code'] == 0 and not row['error'] and
                 report['input_sha256'][row['module']] == wasm and report['aot_sha256'][row['artifact']] == row['sha256'],
                 'fresh preparation status/identity')
            evidence.pin(row['artifact'], row['sha256'])
            need(evidence.index['inputs'][row['artifact'] + '@' + row['sha256']]['bytes'] == row['bytes'],
                 'fresh preparation artifact bytes')
        for module in report['modules']:
            prepared = by_wasm[module['sha256']]
            need(module['precompiled'] == prepared['artifact'] and module['precompiled_sha256'] == prepared['sha256'] and
                 report['input_sha256'][module['module']] == module['sha256'], 'fresh module/AOT link')
        for path, identity in report['input_sha256'].items():
            evidence.pin(path, identity)
    table_rows = audit_public_bindings(evidence)
    return {'status': 'passed', 'paired_rows': paired, 'examples': len(goldens), 'fresh_host_observations': 11484, 'fresh_minimal_observations': 1914,
            'rounded_host_table_rows': table_rows,
            'scope': 'Current observation matrices, output identities, medians/MADs and fresh replay pins. Byte closure is verified separately.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('publication', type=Path)
    parser.add_argument('--prior-root', type=Path, help='Immediate predecessor location for private previews')
    args = parser.parse_args()
    print(json.dumps(audit(args.publication, args.prior_root), indent=2, sort_keys=True))
