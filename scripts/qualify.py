#!/usr/bin/env python3
"""Qualify the current sources in one command.

Bootstraps the compiler with --verify, then runs these at once:
- the conformance suite, with each emitted C file as one translation unit;
- when native code generation changed, the native rows again as three
  program units beside a shared runtime unit;
- the native runtime checks;
- output equivalence against a baseline compiler, when one is given;
- the runner, bootstrap and backend unit tests.

Native builds and bootstrap executables are cached by content under
--cache-dir, so a rerun compiles only C that changed. Writes summary.json
and exits nonzero if a stage fails; equivalence differences are reported,
not judged.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
VENV = ROOT / '.venv/bin/python'
# Changes here can change emitted C or how it builds, so they rerun the native
# rows as split units.
NATIVE_PATHS = ['selfhost/codegen_c.goose', 'selfhost/codegen_c_images.goose', 'selfhost/codegen_c_storage.goose',
                'selfhost/codegen_c_threads.goose', 'native', 'tests/conformance.py']
UNIT_TESTS = ['tests.test_conformance_runner', 'tests.test_bootstrap_optimization', 'tests.test_native_units',
              'tests.test_driver_outputs', 'tests.test_cli_outputs', 'tests.test_root_struct_backends',
              'tests.test_slice_pool_backends']


def run(name, command, log, env=None):
    started = time.monotonic()
    with log.open('wb') as stream:
        code = subprocess.run(list(map(str, command)), cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                              env=env).returncode
    return {'stage': name, 'command': list(map(str, command)), 'exit': code,
            'seconds': round(time.monotonic() - started, 1), 'log': str(log)}


def last_line(path, prefix):
    lines = [line for line in path.read_text(errors='replace').splitlines() if line.startswith(prefix)]
    return lines[-1] if lines else None


def native_changed(since):
    if since is None:
        return True
    result = subprocess.run(['git', 'diff', '--name-only', since, '--', *NATIVE_PATHS], cwd=ROOT,
                            capture_output=True, text=True)
    if result.returncode:
        raise SystemExit('git diff against ' + since + ' failed: ' + result.stderr.strip())
    return bool(result.stdout.strip())


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--output-dir', type=Path, required=True, help='fresh directory for every stage')
    parser.add_argument('--cache-dir', type=Path, default=ROOT / 'build/qualify-cache',
                        help='content-addressed native builds and bootstrap executables (default: build/qualify-cache)')
    parser.add_argument('--baseline', type=Path, help='compiler to compare outputs with (tests/output_equivalence.py)')
    parser.add_argument('--since', default='origin/main',
                        help='git revision; the split-unit pass runs when native code generation differs from it '
                             '(default: origin/main)')
    parser.add_argument('--units-pass', choices=('auto', 'always', 'never'), default='auto')
    parser.add_argument('--jobs', type=int, default=os.cpu_count() or 1, help='CPU threads to share out')
    parser.add_argument('--cc', default='gcc', help='C compiler for conformance builds (default: gcc)')
    args = parser.parse_args()
    out = args.output_dir.resolve()
    out.mkdir(parents=True, exist_ok=False)
    cache = args.cache_dir.resolve()
    python = Path(sys.executable)
    # A worktree has no .venv of its own; use the main checkout's.
    common = subprocess.run(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], cwd=ROOT,
                            capture_output=True, text=True).stdout.strip()
    for candidate in (VENV, Path(common).parent / '.venv/bin/python' if common else None):
        if candidate is not None and candidate.exists():
            python = candidate
            break
    units = args.units_pass == 'always' or args.units_pass == 'auto' and native_changed(args.since)
    summary = {'schema': 'goose-qualification-v1', 'started': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
               'head': subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=ROOT, capture_output=True, text=True).stdout.strip(),
               'dirty': bool(subprocess.run(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=ROOT,
                                            capture_output=True, text=True).stdout.strip()),
               'since': args.since, 'units_pass': units, 'stages': []}

    def save():
        (out / 'summary.json').write_text(json.dumps(summary, indent=1) + '\n')

    started = time.monotonic()
    stage = run('bootstrap', [sys.executable, 'scripts/bootstrap.py', '--verify', '--build-dir', out / 'bootstrap',
                              '--cache-dir', cache / 'bootstrap'], out / 'bootstrap.log')
    summary['stages'].append(stage)
    if stage['exit']:
        summary['status'] = 'failed'
        save()
        print('bootstrap failed; see', stage['log'])
        return 1
    compiler = out / 'bootstrap/bin/goose'
    report = json.loads((out / 'bootstrap/bootstrap/report.json').read_text())
    summary['bootstrap'] = {key: report.get(key) for key in ('fixed_point', 'generated_c_sha256', 'next_generation_c_sha256',
                                                             'third_generation_c_sha256', 'executable_sha256', 'profile_used')}
    summary['bootstrap']['cached'] = {name: row.get('cache', {}).get('hit') for name, row in report.get('builds', {}).items()}
    save()

    # Share the threads out: the one-unit pass carries the most builds.
    share = max(1, args.jobs)
    conformance = [python, 'tests/conformance.py', '--compiler', compiler, '--levels', '0', '2', '--cc', args.cc,
                   '--known-gaps', 'tests/conformance/known-gaps.json', '--native-cache', cache / 'native']
    jobs = [('conformance', [*conformance, '--output-dir', out / 'conformance', '--jobs', max(1, share // 2)]),
            ('native-checks', [sys.executable, 'native/tests/check.py', '--output', out / 'native'])]
    if units:
        jobs.append(('conformance-native-units-3', [*conformance, '--output-dir', out / 'conformance-units',
                                                    '--jobs', max(1, share // 4), '--native-units', '3',
                                                    '--targets', 'native']))
    if args.baseline:
        frozen = out / 'frozen'
        shutil.copytree(ROOT / 'selfhost', frozen / 'selfhost', ignore=shutil.ignore_patterns('results'))
        shutil.copytree(ROOT / 'native', frozen / 'native')
        jobs.append(('equivalence', [python, 'tests/output_equivalence.py', '--baseline', args.baseline.resolve(),
                                     '--candidate', compiler, '--output-dir', out / 'equivalence',
                                     '--selfhost', frozen / 'selfhost', '--jobs', max(1, share // 4)]))
    environment = dict(os.environ, GOOSE_COMPILER=str(compiler))
    jobs.append(('unit-tests', [python, '-m', 'unittest', *UNIT_TESTS]))
    with ThreadPoolExecutor(len(jobs)) as pool:
        results = list(pool.map(lambda job: run(job[0], job[1], out / (job[0] + '.log'), environment), jobs))
    summary['stages'] += results
    failed = []
    for result in results:
        name, log = result['stage'], Path(result['log'])
        if name.startswith('conformance'):
            result['summary'] = last_line(log, "{'selected'")
            result['gaps'] = last_line(log, "{'open_gaps'")
            result['native_cache'] = last_line(log, "{'native_builds'")
        elif name == 'equivalence':
            result['summary'] = last_line(log, '{"compared"')
            differing = json.loads((out / 'equivalence/report.json').read_text()).get('differing', [])
            result['differing'] = differing
            continue  # differences are for review, not a failure
        elif name == 'native-checks':
            text = log.read_text(errors='replace')
            result['summary'] = f"{text.count(': ok')} steps ok"
        if result['exit']:
            failed.append(name)
    summary['seconds'] = round(time.monotonic() - started, 1)
    summary['status'] = 'failed' if failed else 'passed'
    summary['failed'] = failed
    save()
    for result in summary['stages']:
        print(f"{result['stage']:28s} exit {result['exit']}  {result['seconds']:7.1f} s  {result.get('summary') or ''}")
    print(summary['status'], 'in', summary['seconds'], 's;', out / 'summary.json')
    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
