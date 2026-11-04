#!/usr/bin/env python3
"""Measure compiler builds and fresh-process Goose-to-Wasm compilation."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import shutil
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
HERE = Path(__file__).resolve().parent


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--build-samples', type=int, default=3)
    parser.add_argument('--samples', type=int, default=21)
    parser.add_argument('--warmups', type=int, default=2)
    parser.add_argument('--cpu', type=int, default=2)
    parser.add_argument('--jobs', type=int, default=2)
    args = parser.parse_args()
    if min(args.build_samples, args.samples, args.jobs) < 1 or args.warmups < 0:
        parser.error('invalid sample, warmup or job count')
    original_affinity = sorted(os.sched_getaffinity(0))
    if args.cpu not in original_affinity:
        parser.error('CPU is outside current affinity')
    out = args.output_dir.resolve()
    out.mkdir(parents=True, exist_ok=False)
    (out / 'tmp').mkdir()
    env = dict(os.environ, TMPDIR=str(out / 'tmp'), CCACHE_DISABLE='1')
    oracle = ROOT / 'build/next-runtime-hills/final/bin/goose'
    host = ROOT / 'build/bin/goose-wasmtime'
    source = ROOT / 'build/source'
    stdlib = ROOT / 'build/bin/stdlib'
    pin = json.loads((HERE / 'oracle.json').read_text())
    if digest(oracle) != pin['binary_sha256']:
        parser.error('oracle identity differs')
    for name, expected in pin['files'].items():
        if digest(ROOT / name) != expected:
            parser.error('oracle source differs: ' + name)
    tools = {name: Path(shutil.which(name))
             for name in ['cmake', 'ninja', 'clang', 'clang++', 'gcc']}
    inputs = {Path(__file__), HERE / 'oracle.json', ROOT / 'examples/manifest.json', oracle, host, *tools.values()}
    for directory in [HERE, ROOT / 'examples', stdlib, source / 'src', source / 'cmake', source / 'third_party']:
        for path in directory.rglob('*'):
            if path.is_file() and 'results' not in path.parts and '__pycache__' not in path.parts:
                inputs.add(path)
    inputs.add(source / 'CMakeLists.txt')
    pins = {str(path): digest(path) for path in sorted(inputs)}
    snapshot = out / 'sources'
    snapshot.mkdir()
    for path in sorted(HERE.glob('*.goose')):
        shutil.copyfile(path, snapshot / path.name)
    shutil.copytree(stdlib, out / 'stdlib')
    report = {'schema': 'goose-selfhost-compile-times-v1', 'status': 'running',
              'base_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'configuration': {**vars(args), 'output_dir': str(out)},
              'environment': {'platform': platform.platform(), 'affinity_builds': original_affinity,
                              'affinity_programs': [args.cpu], 'load_start': os.getloadavg()},
              'tool_versions': {name: subprocess.check_output([path, '--version'], text=True).splitlines()[0]
                                for name, path in tools.items()},
              'input_sha256': pins, 'commands': [], 'builds': [], 'qualification': [], 'observations': [],
              'method': 'Prepared local sources; warm filesystem, no object/compiler caches. Clean CMake Release '
                        'Clang O3 builds include TinyCC/shader support. Goose bootstrap is pinned C++ source-to-C '
                        'at language O0 plus GCC O0 or O2. Different feature coverage; not language-equivalent builds. '
                        'Program timing includes fresh process startup, loading, checking, optimization, emission '
                        'and writing Wasm; no Wasm execution or Python startup. Configured warmups, paired shuffled '
                        'rounds at each configured language optimization level. Output bytes need not match.'}
    counter = 0

    def save():
        (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')

    def execute(command, label, timeout=600):
        nonlocal counter
        command = list(map(str, command))
        directory = out / 'logs' / f'{counter:05d}-{label}'
        counter += 1
        directory.mkdir(parents=True)
        started = time.perf_counter_ns()
        process = subprocess.run(command, cwd=ROOT, env=env, stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        seconds = (time.perf_counter_ns() - started) / 1e9
        (directory / 'stdout').write_bytes(process.stdout)
        (directory / 'stderr').write_bytes(process.stderr)
        row = {'command': command, 'log': str(directory.relative_to(out)),
               'seconds': seconds, 'exit_code': process.returncode}
        report['commands'].append(row)
        if process.returncode:
            save()
            raise RuntimeError(label + ': ' + (directory / 'stderr').read_text()[-3000:])
        return row

    save()
    try:
        profiles = ['cpp-release', 'goose-gcc-O0', 'goose-gcc-O2']
        executables = {'cpp-release': oracle}
        randomizer = random.Random(67104)
        for sample in range(args.build_samples):
            order = list(profiles)
            randomizer.shuffle(order)
            for profile in order:
                directory = out / 'builds' / f'{sample}-{profile}'
                directory.mkdir(parents=True)
                if profile == 'cpp-release':
                    configured = execute([tools['cmake'], '-S', source, '-B', directory, '-G', 'Ninja',
                        '-DCMAKE_BUILD_TYPE=Release', '-DGOOSE_BUILTIN_LIBS=',
                        '-DCMAKE_C_COMPILER=' + str(tools['clang']),
                        '-DCMAKE_CXX_COMPILER=' + str(tools['clang++']),
                        '-DCMAKE_C_COMPILER_LAUNCHER=', '-DCMAKE_CXX_COMPILER_LAUNCHER='], 'configure')
                    built = execute([tools['cmake'], '--build', directory, '--target', 'goose',
                                     '--parallel', args.jobs], 'cpp-build')
                    row = {'profile': profile, 'sample': sample, 'configure_s': configured['seconds'],
                           'compile_link_s': built['seconds'], 'total_s': configured['seconds'] + built['seconds'],
                           'executable_sha256': digest(directory / 'goose')}
                else:
                    c_file = directory / 'compiler.c'
                    executable = directory / 'goose'
                    emitted = execute([oracle, snapshot / 'main.goose', '--target', 'native', '--standalone',
                        '--stdlib', out / 'stdlib', '-O0', '-o', c_file], 'goose-to-c')
                    flag = '-O0'
                    if profile == 'goose-gcc-O2':
                        flag = '-O2'
                    built = execute([tools['gcc'], '-std=gnu11', flag, c_file, '-lm', '-ldl', '-pthread',
                                     '-o', executable], 'c-build')
                    row = {'profile': profile, 'sample': sample, 'goose_to_c_s': emitted['seconds'],
                           'compile_link_s': built['seconds'], 'total_s': emitted['seconds'] + built['seconds'],
                           'generated_c_sha256': digest(c_file), 'executable_sha256': digest(executable)}
                    if sample == 0:
                        executables[profile] = executable
                report['builds'].append(row)
                save()
                print('BUILD', profile, sample, round(row['total_s'], 3), flush=True)
        report['executables'] = {name: {'path': str(path), 'sha256': digest(path)} for name, path in executables.items()}
        report['build_summary'] = []
        for profile in profiles:
            selected = [row for row in report['builds'] if row['profile'] == profile]
            summary = {'profile': profile, 'samples': len(selected)}
            for key in ['total_s', 'configure_s', 'goose_to_c_s', 'compile_link_s']:
                values = [row[key] for row in selected if key in row]
                if values:
                    summary[key] = statistics.median(values)
            report['build_summary'].append(summary)
        examples = json.loads((ROOT / 'examples/manifest.json').read_text())['examples']
        cells = [(name, example, level) for example in examples for level in [0, 2] for name in profiles]
        artifacts = out / 'wasm'
        artifacts.mkdir()

        def compile_cell(name, example, level):
            artifact = artifacts / f'{name}-{example["name"]}-O{level}.wasm'
            row = execute([executables[name], ROOT / 'examples' / example['file'], '--target', 'wasm-direct',
                           '--stdlib', out / 'stdlib', f'-O{level}', '-o', artifact], 'program', timeout=None)
            return row, artifact

        os.sched_setaffinity(0, [args.cpu])
        for name, example, level in cells:
            row, artifact = compile_cell(name, example, level)
            result = execute([host, '--no-cache', artifact], 'qualify')
            stdout = out / result['log'] / 'stdout'
            expected = ROOT / 'examples' / example['expected']
            if stdout.read_bytes() != expected.read_bytes():
                raise RuntimeError('runtime mismatch: ' + str(artifact))
            report['qualification'].append({'profile': name, 'example': example['name'], 'level': level,
                'artifact_sha256': digest(artifact), 'module_bytes': artifact.stat().st_size,
                'stdout_sha256': digest(stdout), 'golden_sha256': digest(expected)})
        for phase, count in [('warmup', args.warmups), ('measure', args.samples)]:
            for sample in range(count):
                order = list(cells)
                randomizer.shuffle(order)
                for name, example, level in order:
                    row, artifact = compile_cell(name, example, level)
                    report['observations'].append({'profile': name, 'example': example['name'], 'level': level,
                                                  'phase': phase, 'sample': sample, 'seconds': row['seconds']})
                save()
            print('PROGRAMS', phase, count, flush=True)
        report['program_summary'] = []
        for name, example, level in cells:
            values = [row['seconds'] for row in report['observations'] if row['phase'] == 'measure'
                      and (row['profile'], row['example'], row['level']) == (name, example['name'], level)]
            report['program_summary'].append({'profile': name, 'example': example['name'], 'level': level,
                'median_ms': statistics.median(values) * 1000, 'min_ms': min(values) * 1000,
                'max_ms': max(values) * 1000, 'samples': len(values)})
        report['input_sha256_after'] = {name: digest(name) for name in pins}
        if report['input_sha256_after'] != pins:
            raise RuntimeError('input files changed during measurement')
        report['environment']['load_end'] = os.getloadavg()
        report['status'] = 'passed'
    except BaseException as error:
        report.update(status='failed', error=type(error).__name__ + ': ' + str(error))
        raise
    finally:
        os.sched_setaffinity(0, original_affinity)
        save()
    print(out / 'report.json')


if __name__ == '__main__':
    main()
