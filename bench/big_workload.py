#!/usr/bin/env python3
"""Time one compiler on the frozen compiler-goose fixture.

Extracts bench/fixtures/compiler-goose/fixture.tar.gz to a fresh scratch
directory, then runs the compiler in one mode (parse, check or emit) from the
fixture's compiler-goose directory. Each sample runs in a fresh measuring
process, so getrusage(RUSAGE_CHILDREN) reports only that compiler process:
wall time, user and system CPU, and maximum resident set size.
"""

import argparse
import hashlib
import json
import resource
import statistics
import subprocess
import sys
import tarfile
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'bench/fixtures/compiler-goose'

# The reference checker is built with GOOSE_REACHABLE_PROGRAM and a
# 1000000-node expansion limit (manifest.json reference_compiler.build); the
# selfhost compiler takes the same settings as options.
REFERENCE_SETTINGS = ['--reachable-program', '--expansion-node-limit', '1000000']
# Argument templates; {stdlib} and {output} are filled per run.
STYLES = {
    'selfhost': {
        'parse': ['src/main.goose', '--target', 'native', '--parse', '--stdlib', '{stdlib}'],
        'check': ['src/main.goose', '--target', 'native', '--check', '--stdlib', '{stdlib}', *REFERENCE_SETTINGS],
        'emit': ['src/main.goose', '--target', 'native', '-O2', '--stdlib', '{stdlib}', '-o', '{output}', *REFERENCE_SETTINGS],
    },
    'upstream': {
        'parse': ['src/main.goose', '--parse', '--stdlib', '{stdlib}'],
        'check': ['check', 'src/main.goose', '--stdlib', '{stdlib}'],
        'emit': ['src/main.goose', '--stdlib', '{stdlib}', '-o', '{output}'],
    },
}


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


def measure(argv, cwd, out):
    """Runs argv once in this process's only child and writes its usage."""
    start = time.monotonic()
    with open(out + '.stdout', 'wb') as stdout, open(out + '.stderr', 'wb') as stderr:
        code = subprocess.run(argv, cwd=cwd, stdout=stdout, stderr=stderr).returncode
    wall = time.monotonic() - start
    usage = resource.getrusage(resource.RUSAGE_CHILDREN)
    Path(out + '.json').write_text(json.dumps({
        'exit': code, 'wall_s': round(wall, 3), 'user_s': round(usage.ru_utime, 3),
        'sys_s': round(usage.ru_stime, 3), 'max_rss_mib': round(usage.ru_maxrss / 1024, 1)}))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--mode', choices=('parse', 'check', 'emit'), default='parse')
    parser.add_argument('--style', choices=sorted(STYLES), default='selfhost',
                        help='command-line convention: this repository\'s compiler or upstream C++ goose')
    parser.add_argument('--samples', type=int, default=1)
    parser.add_argument('--output', type=Path, required=True, help='JSON report path')
    parser.add_argument('--scratch', type=Path, help='parent of the fresh extraction directory')
    parser.add_argument('--memory-max', help='run each sample under systemd-run with this MemoryMax, e.g. 8G')
    parser.add_argument('extra', nargs='*', help='arguments appended to the compiler command (after --)')
    args = parser.parse_args()

    manifest = json.loads((FIXTURE / 'manifest.json').read_text())
    archive = ROOT / manifest['archive']['path']
    if sha256(archive) != manifest['archive']['sha256']:
        sys.exit(f'{archive}: sha256 differs from manifest.json')
    if args.scratch:
        args.scratch.mkdir(parents=True, exist_ok=True)
    scratch = Path(tempfile.mkdtemp(prefix='big-workload-', dir=args.scratch))
    with tarfile.open(archive) as tar:
        tar.extractall(scratch, filter='data')
    cwd = scratch / 'compiler-goose'
    compiler = args.compiler.resolve()
    fill = {'stdlib': str(scratch / 'stdlib'), 'output': str(scratch / 'out.c')}
    argv = [str(compiler)] + [word.format(**fill) for word in STYLES[args.style][args.mode]] + args.extra
    if args.memory_max:
        argv = ['systemd-run', '--user', '--scope', '-q', '-p', f'MemoryMax={args.memory_max}', '-p', 'MemorySwapMax=0'] + argv

    samples = []
    for index in range(args.samples):
        out = str(scratch / f'sample-{index}')
        subprocess.run([sys.executable, '-I', __file__, '--measure', str(cwd), out, '--', *argv], check=True)
        sample = json.loads(Path(out + '.json').read_text())
        sample['stderr_tail'] = Path(out + '.stderr').read_text(errors='replace')[-2000:]
        samples.append(sample)
        print(f"sample {index}: exit {sample['exit']} wall {sample['wall_s']} s user {sample['user_s']} s "
              f"max_rss {sample['max_rss_mib']} MiB", file=sys.stderr)

    walls = [sample['wall_s'] for sample in samples]
    report = {
        'schema': 'goose-big-workload-v1',
        'fixture': {'archive_sha256': manifest['archive']['sha256'], 'program_commit': manifest['program']['commit'],
                    'stdlib_commit': manifest['stdlib']['commit']},
        'compiler': {'path': str(compiler), 'sha256': sha256(compiler), 'style': args.style},
        'mode': args.mode, 'argv': argv, 'cwd': str(cwd), 'scratch': str(scratch),
        'samples': samples,
        'summary': {'exits': sorted({sample['exit'] for sample in samples}),
                    'median_wall_s': round(statistics.median(walls), 3), 'min_wall_s': min(walls),
                    'median_user_s': round(statistics.median(sample['user_s'] for sample in samples), 3),
                    'max_rss_mib': max(sample['max_rss_mib'] for sample in samples)},
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=1) + '\n')


if __name__ == '__main__':
    if len(sys.argv) > 4 and sys.argv[1] == '--measure' and sys.argv[4] == '--':
        measure(sys.argv[5:], sys.argv[2], sys.argv[3])
    else:
        main()
