#!/usr/bin/env python3
"""Run frozen source/output contracts without a reference compiler."""
from __future__ import annotations
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


# Programs that use these share files and directories in their working
# directory, so their executions are serialized.
FILESYSTEM = re.compile(r'\b(read_file|write_file|write_file_atomic|append_file|file_exists|delete_file|'
                        r'rename_file|make_dir|is_dir|delete_dir|list_dir|gs_os_(?:read|write|append|remove|'
                        r'rename|make|list|file|is)_\w+)\b')


def native_source_paths(case):
    paths = []
    for source in case.get('native_sources', []):
        relative = Path(source)
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('native_sources paths must be ROOT-relative: ' + str(source))
        path = ROOT / relative
        if not path.is_file():
            raise FileNotFoundError(path)
        paths.append(path)
    return tuple(paths)


def native_compile_command(cc, flag, defines, artifact, native_sources):
    command = [cc, '-std=gnu11', flag, *defines, artifact]
    if native_sources:
        command.extend(native_sources)
        command.append('-rdynamic')
    command += ['-lm', '-ldl', '-pthread', '-o', artifact.parent / 'program']
    return command


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, default=ROOT / 'tests/conformance/cases.json')
    parser.add_argument('--stdlib', type=Path, default=ROOT / 'stdlib')
    parser.add_argument('--filter', default='')
    parser.add_argument('--levels', type=int, nargs='+', choices=(0, 2), default=[0, 2])
    parser.add_argument('--engine', choices=('wasmtime', 'v8'), default='wasmtime')
    parser.add_argument('--host', type=Path)
    parser.add_argument('--cc', default='gcc')
    parser.add_argument('--timeout', type=float, default=15)
    parser.add_argument('--frontend-only', action='store_true', help='check positive programs without lowering or execution')
    parser.add_argument('--cc-timeout', type=float, default=120,
                        help='seconds allowed to compile emitted C; --timeout bounds the compiler and programs')
    parser.add_argument('--jobs', type=int, default=os.cpu_count() or 1,
                        help='rows checked concurrently; each execution is still a fresh process (default: CPU count)')
    parser.add_argument('--known-gaps', type=Path,
                        help='exit 0 only if the failing selected rows are exactly the recorded open gaps')
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    out = args.output_dir.resolve()
    out.mkdir(parents=True, exist_ok=False)
    library = args.stdlib.resolve()
    manifest = json.loads(args.manifest.read_text())
    archive = ROOT / manifest['upstream']['archive']
    if digest(archive) != manifest['upstream']['sha256']:
        parser.error('upstream source bundle changed')
    upstream = out / 'upstream'
    upstream.mkdir()
    needs_upstream = any(
        args.filter in case['id'] and case['source'].startswith('upstream:')
        for case in manifest['cases'])
    if needs_upstream:
        with tarfile.open(archive) as bundle:
            for member in bundle:
                relative = Path(member.name)
                if relative.is_absolute() or '..' in relative.parts or not member.isfile():
                    parser.error('unexpected upstream archive member: ' + member.name)
                path = upstream / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                with bundle.extractfile(member) as source, path.open('wb') as target:
                    shutil.copyfileobj(source, target)
    shutil.copytree(library, upstream / 'stdlib')
    host = args.host
    if host is None and (ROOT / 'build/bin/goose-wasmtime').exists():
        host = ROOT / 'build/bin/goose-wasmtime'
    cc = shutil.which(args.cc)
    if not cc:
        parser.error('C compiler unavailable: ' + args.cc)
    pins = {str(path): digest(path) for path in [compiler, args.manifest, archive, Path(__file__), Path(cc)]}
    for path in library.rglob('*.goose'):
        pins[str(path)] = digest(path)
    if host is not None:
        host = host.resolve()
        pins[str(host)] = digest(host)
    report = {'schema': 'goose-conformance-v1', 'status': 'running',
              'configuration': {'compiler': str(compiler), 'manifest': str(args.manifest), 'levels': args.levels,
                  'filter': args.filter, 'engine': args.engine, 'host': str(host), 'frontend_only': args.frontend_only,
                  'upstream_extracted': needs_upstream, 'jobs': args.jobs,
                  'timeout': args.timeout, 'cc_timeout': args.cc_timeout},
              'method': 'Only the compiler under test runs. Sources, stdin, expected stdout, exit status and '
                        'failure phases are frozen data. No expected-output update mode, reference fallback, '
                        'expected failures or silent skips. Compilations with identical inputs share an artifact '
                        'within this run; every execution is a fresh process. Rows run concurrently; results keep manifest order.',
              'input_sha256': pins, 'commands': [], 'results': []}
    if args.jobs < 1:
        parser.error('--jobs must be positive')
    # Rows run concurrently. The lock guards the report, pins and the
    # compilation slots; each slot's own lock makes identical compilations
    # share one artifact.
    lock = threading.Lock()
    filesystem = threading.Lock()
    slots = {}

    def save():
        (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')

    def execute(command, cwd, stdin='', timeout=None):
        command = list(map(str, command))
        start = time.monotonic()
        row = {'command': command, 'cwd': str(cwd), 'exit_code': None, 'error': '', 'stdout': '', 'stderr': ''}
        try:
            process = subprocess.run(command, cwd=cwd, input=stdin.encode(), capture_output=True,
                                     timeout=timeout or args.timeout)
            row.update(exit_code=process.returncode, stdout=process.stdout.decode(errors='replace'),
                       stderr=process.stderr.decode(errors='replace'))
        except (OSError, subprocess.TimeoutExpired) as error:
            row['error'] = str(error)
        row['seconds'] = time.monotonic() - start
        with lock:
            index = len(report['commands'])
            report['commands'].append(row)
        return index, row

    def compile_case(case, source, level, action):
        native_sources = native_source_paths(case)
        key = (str(source), case['target'], level, bool(case.get('debug')), case.get('maximum_pages'),
               tuple(case.get('native_defines', [])), tuple(map(str, native_sources)), action)
        with lock:
            slot = slots.get(key)
            if slot is None:
                slot = slots[key] = {'lock': threading.Lock(), 'value': None, 'index': len(slots)}
        with slot['lock']:
            if slot['value'] is None:
                slot['value'] = build_case(case, source, level, action, native_sources, slot['index'])
            return slot['value']

    def build_case(case, source, level, action, native_sources, number):
        directory = out / 'artifacts' / str(number)
        directory.mkdir(parents=True)
        artifact = directory / 'program.wasm'
        if case['target'] == 'native':
            artifact = directory / 'program.c'
        command = [compiler, source, '--target', case['target'], '--stdlib', library, f'-O{level}']
        if action == 'emit':
            command += ['--standalone', '-o', artifact]
        else:
            command.append('--' + action)
        if case.get('debug'):
            command.append('--debug')
        if case.get('maximum_pages') is not None:
            command += ['--wasm-initial-pages', '1', '--wasm-max-pages', str(case['maximum_pages'])]
        index, result = execute(command, ROOT)
        value = {'command': index, 'result': result, 'artifact': artifact}
        if action == 'emit' and result['exit_code'] == 0 and artifact.is_file() and case['target'] == 'native':
            binary = directory / 'program'
            flag = '-O0'
            if level == 2:
                flag = '-O2'
            defines = ['-D' + value for value in case.get('native_defines', [])]
            command = native_compile_command(cc, flag, defines, artifact, native_sources)
            index, native = execute(command, directory, timeout=args.cc_timeout)
            value.update(native_command=index, native_result=native, binary=binary)
        return value

    def normal_error(result):
        return result['exit_code'] == 1 and not result['error'] and ': error:' in result['stderr']

    def check(case, source, cwd, level, uses_files):
        row = {'case': case['id'], 'level': level, 'status': 'fail', 'phase': case['phase']}
        phase = case['phase']
        action = 'emit'
        if phase in ('parse', 'parse-error'):
            action = 'parse'
        elif phase == 'tokens':
            action = 'tokens'
        elif phase in ('check', 'type-error') or args.frontend_only:
            action = 'check'
        if phase == 'type-error':
            parsed = compile_case(case, source, level, 'parse')
            row['parse_command'] = parsed['command']
            if parsed['result']['exit_code'] != 0:
                row['reason'] = 'type-error source failed during parsing'
        compiled = compile_case(case, source, level, action)
        row['compile_command'] = compiled['command']
        result = compiled['result']
        if phase in ('parse-error', 'type-error'):
            if normal_error(result) and 'reason' not in row:
                row['status'] = 'pass'
        elif action in ('parse', 'check'):
            if result['exit_code'] == 0 and not result['error']:
                row['status'] = 'pass'
        elif action == 'tokens':
            expected = case['expect']
            actual = result['stdout']
            stdout = expected['stdout']
            if expected.get('normalize') == 'trailing-newlines':
                actual = actual.rstrip('\n')
                stdout = stdout.rstrip('\n')
            row['stdout_equal'] = actual == stdout
            if row['stdout_equal'] and result['exit_code'] == expected['exit'] and not result['error']:
                row['status'] = 'pass'
        elif result['exit_code'] == 0 and compiled['artifact'].is_file():
            command = []
            if case['target'] == 'native':
                row['native_command'] = compiled.get('native_command')
                if compiled.get('native_result', {}).get('exit_code') == 0:
                    command = [compiled['binary']]
            elif args.engine == 'v8':
                command = ['node', ROOT / 'scripts/run_wasm.mjs', compiled['artifact']]
            elif host is not None:
                command = [host, '--no-cache', compiled['artifact']]
            else:
                command = [sys.executable, ROOT / 'scripts/run_wasmtime.py', compiled['artifact']]
            if command:
                if uses_files:
                    with filesystem:
                        index, observed = execute(command, cwd, case.get('stdin', ''))
                else:
                    index, observed = execute(command, cwd, case.get('stdin', ''))
                row['run_command'] = index
                expected = case['expect']
                stdout = expected.get('stdout', '')
                if 'stdout_file' in expected:
                    stdout = (ROOT / expected['stdout_file']).read_text()
                actual = observed['stdout']
                if expected.get('normalize') == 'trailing-newlines':
                    stdout = stdout.rstrip('\n')
                    actual = actual.rstrip('\n')
                code_ok = observed['exit_code'] == expected['exit']
                if expected['exit'] == 'nonzero':
                    code_ok = observed['exit_code'] not in (None, 0, -11, -7, -4)
                row['stdout_equal'] = actual == stdout
                row['exit_equal'] = code_ok
                row['diagnostic_equal'] = all(text.lower() in observed['stderr'].lower()
                                              for text in expected.get('stderr_contains', []))
                if row['stdout_equal'] and code_ok and row['diagnostic_equal'] and not observed['error']:
                    row['status'] = 'pass'
        return row

    selected = 0
    jobs = []
    save()
    try:
        for case in manifest['cases']:
            if args.filter not in case['id']:
                continue
            source_name = case['source']
            source = ROOT / source_name
            cwd = ROOT
            if source_name.startswith('upstream:'):
                source = upstream / source_name[len('upstream:'):]
                cwd = upstream
            pins[str(source)] = digest(source)
            for dependency in case.get('dependencies', []):
                path = ROOT / dependency
                pins[str(path)] = digest(path)
            for path in native_source_paths(case):
                pins[str(path)] = digest(path)
            # Pins are complete before any worker starts.
            if 'stdout_file' in case.get('expect', {}):
                path = ROOT / case['expect']['stdout_file']
                pins[str(path)] = digest(path)
            text = source.read_text(errors='replace')
            for dependency in case.get('dependencies', []):
                text += (ROOT / dependency).read_text(errors='replace')
            uses_files = FILESYSTEM.search(text) is not None
            for level in args.levels:
                if level in case['levels']:
                    jobs.append((case, source, cwd, level, uses_files))
        selected = len(jobs)
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            for row in pool.map(lambda job: check(*job), jobs):
                report['results'].append(row)
                if len(report['results']) % 100 == 0:
                    with lock:
                        save()
                    print(len(report['results']), 'checked;', sum(x['status'] == 'pass' for x in report['results']), 'passed', flush=True)
        if not selected:
            raise RuntimeError('no selected contracts')
        report['input_sha256_after'] = {path: digest(path) for path in pins}
        if report['input_sha256_after'] != pins:
            raise RuntimeError('contract inputs changed during the run')
        report['summary'] = {'selected': selected, 'passed': sum(x['status'] == 'pass' for x in report['results']),
                             'failed': sum(x['status'] != 'pass' for x in report['results'])}
        report['status'] = 'failed'
        if report['summary']['failed'] == 0:
            report['status'] = 'passed'
    except BaseException as error:
        report.update(status='failed', error=repr(error))
        raise
    finally:
        save()
    print(report['summary'])
    if args.known_gaps:
        return known_gaps(report, args.known_gaps)
    return int(report['status'] != 'passed')


def known_gaps(report, path):
    """Compare failures with the recorded open gaps among the selected rows.

    A failure outside the record is a regression; a recorded gap that now
    passes must be removed from the record."""
    rows = {(row['case'], row['level']): row['status'] for row in report['results']}
    recorded = {(case, level) for case, level in json.loads(path.read_text())['gaps']}
    expected = {key for key in recorded if key in rows}
    failing = {key for key, status in rows.items() if status != 'pass'}
    unexpected = sorted(failing - expected)
    fixed = sorted(expected - failing)
    print({'open_gaps': len(expected), 'unexpected_failures': len(unexpected), 'fixed_gaps': len(fixed)})
    for case, level in unexpected:
        print('unexpected failure:', case, 'level', level)
    for case, level in fixed:
        print('recorded gap now passes; remove it from', path.name + ':', case, 'level', level)
    return int(bool(unexpected or fixed))


if __name__ == '__main__':
    raise SystemExit(main())
