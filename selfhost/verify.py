#!/usr/bin/env python3
"""Measure parity without substituting oracle output for candidate output."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
HERE = Path(__file__).resolve().parent
sys.dont_write_bytecode = True


def digest(path):
    with Path(path).open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def execute(command, directory, stdin=b'', timeout=90):
    command = list(map(str, command))
    directory.mkdir(parents=True, exist_ok=False)
    started = time.monotonic()
    result = {'command': command, 'exit_code': None, 'stdout': '', 'stderr': '', 'error': ''}
    try:
        process = subprocess.run(command, cwd=ROOT, input=stdin, capture_output=True, timeout=timeout)
        stdout, stderr = process.stdout, process.stderr
        result['exit_code'] = process.returncode
    except subprocess.TimeoutExpired as error:
        stdout, stderr = error.stdout or b'', error.stderr or b''
        result['error'] = str(error)
    except OSError as error:
        stdout, stderr = b'', b''
        result['error'] = str(error)
    (directory / 'stdout').write_bytes(stdout)
    (directory / 'stderr').write_bytes(stderr)
    result.update(seconds=time.monotonic() - started, stdout=stdout.decode(errors='replace'),
                  stderr=stderr.decode(errors='replace'), stdout_sha256=hashlib.sha256(stdout).hexdigest(),
                  stderr_sha256=hashlib.sha256(stderr).hexdigest())
    (directory / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def save(path, report):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(report, indent=2) + '\n')
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--oracle', type=Path, default=ROOT / 'build/next-runtime-hills/final/bin/goose')
    parser.add_argument('--host', type=Path, default=ROOT / 'build/bin/goose-wasmtime')
    parser.add_argument('--stdlib', type=Path, default=ROOT / 'build/bin/stdlib')
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--full', action='store_true', help='all existing978 differential cases at O0/O2')
    parser.add_argument('--examples', action='store_true', help='all ten full examples')
    parser.add_argument('--filter', default='')
    parser.add_argument('--levels', type=int, nargs='+', choices=(0, 1, 2), default=[0, 2])
    parser.add_argument('--timeout', type=float, default=90, help='seconds allowed for each compiler or runtime invocation')
    parser.add_argument('--runtime-only', action='store_true', help='report byte differences but gate only runtime parity')
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    out = args.output_dir.resolve()
    out.mkdir(parents=True, exist_ok=False)
    pin = json.loads((HERE / 'oracle.json').read_bytes())
    oracle, candidate, host = args.oracle.resolve(), args.candidate.resolve(), args.host.resolve()
    if digest(oracle) != pin['binary_sha256']:
        parser.error('C++ oracle identity differs')
    inputs = {str(path): digest(path) for path in [Path(__file__), HERE / 'oracle.json', oracle, candidate, host]}
    data_inputs = set(args.stdlib.resolve().rglob('*.goose'))
    specifications = []
    if args.full:
        data_inputs.update((ROOT / 'tests/fixtures').rglob('*.goose'))
        data_inputs.update([ROOT / 'tests/run_differential.py', ROOT / 'bench/command_logs.py'])
        sys.path.insert(0, str(ROOT / 'tests'))
        from run_differential import cases
        for case in cases():
            if args.filter in case.name:
                specifications.append({'name': case.name, 'source': ROOT / 'tests/fixtures' / (case.fixture + '.goose'),
                    'stdin': case.stdin.encode(), 'expected': case.stdout, 'exit_code': case.exit_code,
                    'diagnostic': case.diagnostic, 'debug': case.debug, 'levels': case.levels,
                    'maximum_pages': case.maximum_pages})
    elif args.examples:
        data_inputs.add(ROOT / 'examples/manifest.json')
        data_inputs.update((ROOT / 'examples').rglob('*.goose'))
        for example in json.loads((ROOT / 'examples/manifest.json').read_bytes())['examples']:
            if args.filter in example['name']:
                data_inputs.add(ROOT / 'examples' / example['expected'])
                specifications.append({'name': example['name'], 'source': ROOT / 'examples' / example['file'],
                    'stdin': b'', 'expected': (ROOT / 'examples' / example['expected']).read_text(),
                    'exit_code': 0, 'diagnostic': '', 'debug': False, 'levels': args.levels})
    else:
        fixtures = {
            'empty': 'fn main() {}\n',
            'integer': 'fn main() { print(6 * 7); }\n',
            'variables': 'fn main() { var n:i64=4; n+=3; print(n); }\n',
            'function': 'fn twice(n:i64)->i64 { n+n } fn main() { print(twice(21)); }\n',
            'branch': 'fn main() { var n:i64=3; if n<4 { print(11); } else { print(22); } }\n',
            'loop': 'fn main() { var n:i64=0; for i in 8 { n+=i; } print(n); }\n',
            'array': 'fn main() { var a:i64[3]=[3,4,5]; print(a[1]); }\n',
            'record': 'struct Point {x:i64,y:i64} fn main() { let p=Point{3,9}; print(p.x+p.y); }\n',
            'generic': 'fn twice(x) {x+x} fn main() {print(twice(21));}\n',
            'invalid': 'fn main() { let x = ; }\n',
        }
        for name, text in fixtures.items():
            if args.filter in name:
                source = out / (name + '.goose')
                source.write_text(text)
                specifications.append({'name': name, 'source': source, 'stdin': b'', 'expected': None,
                    'exit_code': 0, 'diagnostic': '', 'debug': False, 'levels': args.levels, 'invalid': name == 'invalid'})
    if not specifications:
        parser.error('no selected cases')
    for spec in specifications:
        inputs[str(spec['source'])] = digest(spec['source'])
    for path in sorted(data_inputs):
        inputs[str(path)] = digest(path)
    snapshots = out / 'inputs'
    for name in inputs:
        path = Path(name)
        if path in (oracle, candidate, host):
            continue
        if path.is_relative_to(ROOT):
            destination = snapshots / path.relative_to(ROOT)
        else:
            destination = snapshots / 'external' / path.relative_to(path.anchor)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, destination)
    report = {'schema': 'goose-selfhost-parity-v1', 'status': 'running', 'input_sha256': inputs,
              'method': 'Independent candidate/oracle compilation and native-C-API Wasm execution. '
                        'Exact Wasm bytes, exit/stdout, expected goldens and diagnostic categories are separate gates. '
                        'Two generic refusals never establish valid-program parity. No oracle fallback in candidate.',
              'configuration': vars(args), 'results': []}
    report['workloads'] = [{key: str(value) if isinstance(value, Path) else value.decode() if isinstance(value, bytes) else value
                            for key, value in spec.items()} for spec in specifications]
    report['configuration'] = {key: str(value) if isinstance(value, Path) else value for key, value in vars(args).items()}
    save(out / 'report.json', report)
    rows = []
    for number, spec in enumerate(specifications):
        for level in args.levels:
            if level not in spec['levels']:
                continue
            directory = out / f'{number:04d}-O{level}'
            directory.mkdir()
            row = {'case': spec['name'], 'optimization': level, 'status': 'fail', 'byte_equal': False,
                   'runtime_equal': False, 'golden_equal': False, 'compile_equal': False}
            modules = {name: directory / (name + '.wasm') for name in ('oracle', 'candidate')}
            compiled = {}
            for name, compiler in [('oracle', oracle), ('candidate', candidate)]:
                command = [compiler, spec['source'], '--target', 'wasm-direct', '-o', modules[name], f'-O{level}']
                if name == 'candidate':
                    command += ['--stdlib', args.stdlib.resolve()]
                if spec['debug']:
                    command.append('--debug')
                if spec.get('maximum_pages') is not None:
                    command += ['--wasm-initial-pages', '1', '--wasm-max-pages', str(spec['maximum_pages'])]
                compiled[name] = execute(command, directory / (name + '-compile'), timeout=args.timeout)
            row['compilation'] = compiled
            valid = all(value['exit_code'] == 0 and not value['error'] for value in compiled.values())
            if spec.get('invalid'):
                row['compile_equal'] = all(value['exit_code'] not in (None, 0) and not value['error'] for value in compiled.values())
                if row['compile_equal'] and not any(path.exists() for path in modules.values()):
                    row.update(status='pass', kind='invalid-source-refusal')
            elif valid and all(path.is_file() for path in modules.values()):
                row['compile_equal'] = True
                row['artifacts'] = {name: {'path': str(path), 'sha256': digest(path), 'bytes': path.stat().st_size} for name, path in modules.items()}
                row['byte_equal'] = modules['oracle'].read_bytes() == modules['candidate'].read_bytes()
                executions = {name: execute([host, '--no-cache', path], directory / (name + '-run'), spec['stdin'], timeout=args.timeout)
                              for name, path in modules.items()}
                row['execution'] = executions
                before, after = executions['oracle'], executions['candidate']
                row['runtime_equal'] = not before['error'] and not after['error'] and before['exit_code'] == after['exit_code'] and before['stdout_sha256'] == after['stdout_sha256']
                row['golden_equal'] = after['exit_code'] == spec['exit_code'] and (spec['expected'] is None or after['stdout'] == spec['expected'])
                diagnostic = spec['diagnostic']
                row['diagnostic_equal'] = diagnostic.lower() in after['stderr'].lower()
                if not diagnostic and not before['stderr']:
                    row['diagnostic_equal'] = not after['stderr']
                if row['runtime_equal'] and row['golden_equal'] and row['diagnostic_equal'] and (args.runtime_only or row['byte_equal']):
                    row['status'] = 'pass'
            rows.append(row)
            report['results'] = rows
            save(out / 'report.json', report)
            print(row['status'].upper(), spec['name'], 'O' + str(level), 'bytes', row['byte_equal'], 'runtime', row['runtime_equal'], flush=True)
    report['input_sha256_after'] = {path: digest(path) for path in inputs}
    report['summary'] = {key: sum(bool(row.get(key)) for row in rows) for key in ['compile_equal', 'byte_equal', 'runtime_equal', 'golden_equal']}
    report['failures'] = sum(row['status'] != 'pass' for row in rows)
    report['status'] = 'passed'
    if report['failures'] or report['input_sha256_after'] != inputs:
        report['status'] = 'failed'
    save(out / 'report.json', report)
    print(report['summary'], 'failures', report['failures'])
    return int(report['status'] != 'passed')


if __name__ == '__main__':
    raise SystemExit(main())
