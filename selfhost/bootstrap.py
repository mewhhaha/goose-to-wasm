#!/usr/bin/env python3
"""Build the Goose implementation with a SHA-pinned, separate C++ oracle."""
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


def digest(path):
    with Path(path).open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def save(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def command(argv, directory, name, timeout=900):
    argv = list(map(str, argv))
    started = time.monotonic()
    result = subprocess.run(argv, cwd=ROOT, stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    (directory / (name + '.stdout')).write_bytes(result.stdout)
    (directory / (name + '.stderr')).write_bytes(result.stderr)
    return {'command': argv, 'exit_code': result.returncode,
            'seconds': time.monotonic() - started,
            'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(),
            'stderr_sha256': hashlib.sha256(result.stderr).hexdigest(),
            'stderr_tail': result.stderr[-4000:].decode(errors='replace')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--oracle', type=Path, default=ROOT / 'build/next-runtime-hills/final/bin/goose')
    parser.add_argument('--output-dir', type=Path, default=Path('/dev/shm/goose-selfhost-work/bootstrap'))
    parser.add_argument('--cc', default=os.environ.get('CC', 'gcc'))
    parser.add_argument('--check', action='store_true', help='typecheck the complete implementation without building')
    args = parser.parse_args()
    out = args.output_dir.resolve()
    out.mkdir(parents=True, exist_ok=False)
    pin = json.loads((HERE / 'oracle.json').read_bytes())
    oracle = args.oracle.resolve()
    if digest(oracle) != pin['binary_sha256']:
        parser.error('oracle binary differs from selfhost/oracle.json')
    for name, expected in pin['files'].items():
        if digest(ROOT / name) != expected:
            parser.error('C++ oracle source changed: ' + name)
    sources = sorted(HERE.glob('*.goose'))
    stdlib = oracle.parent / 'stdlib'
    if not stdlib.is_dir():
        stdlib = ROOT / 'build/bin/stdlib'
    library_sources = sorted(stdlib.rglob('*.goose'))
    inputs = {str(path): digest(path) for path in [Path(__file__), HERE / 'oracle.json', *sources, *library_sources, oracle]}
    snapshots = out / 'sources'
    snapshots.mkdir()
    for path in [Path(__file__), HERE / 'oracle.json', *sources]:
        shutil.copyfile(path, snapshots / path.name)
    shutil.copytree(stdlib, out / 'stdlib', ignore=shutil.ignore_patterns('__pycache__'))
    report = {'schema': 'goose-selfhost-bootstrap-v1', 'status': 'running',
              'method': 'The pinned C++ compiler bootstraps the Goose-written compiler through native C. '
                        'The produced implementation does not delegate compilation back to this oracle. '
                        'Bootstrap success does not establish language, Wasm-byte or runtime parity.',
              'oracle_sha256': pin['binary_sha256'], 'source_files': len(sources),
              'source_lines': sum(len(path.read_bytes().splitlines()) for path in sources),
              'input_sha256': inputs, 'commands': []}
    save(out / 'report.json', report)
    source = out / 'goose-selfhost.c'
    executable = out / 'goose-selfhost'
    try:
        invocation = [oracle, snapshots / 'main.goose', '--stdlib', out / 'stdlib', '--target', 'native', '--standalone', '-O0']
        if args.check:
            invocation.append('--check')
        else:
            invocation += ['-o', source]
        row = command(invocation, out, 'oracle')
        report['commands'].append(row)
        save(out / 'report.json', report)
        if row['exit_code']:
            raise RuntimeError('bootstrap typechecking failed: ' + row['stderr_tail'])
        if not args.check:
            cc = shutil.which(args.cc)
            if not cc:
                raise RuntimeError('native C compiler not found: ' + args.cc)
            inputs[str(Path(cc).resolve())] = digest(Path(cc).resolve())
            row = command([cc, '-std=gnu11', '-O0', source, '-lm', '-ldl', '-pthread', '-o', executable], out, 'cc')
            report['commands'].append(row)
            if row['exit_code']:
                raise RuntimeError('bootstrap C compilation failed: ' + row['stderr_tail'])
            report.update(executable=str(executable), executable_sha256=digest(executable),
                          generated_c_sha256=digest(source))
        after = {path: digest(path) for path in inputs}
        if after != inputs:
            raise RuntimeError('implementation changed during bootstrap; freeze writers before rebuilding')
        report.update(status='passed', input_sha256_after=after)
    except BaseException as error:
        report.update(status='failed', error=type(error).__name__ + ': ' + str(error))
        save(out / 'report.json', report)
        print(report['error'], file=sys.stderr)
        return 1
    save(out / 'report.json', report)
    print(json.dumps({key: report[key] for key in ('status', 'source_files', 'source_lines')}, indent=2))
    if not args.check:
        print(executable)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
