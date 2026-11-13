#!/usr/bin/env python3
"""Check that two compilers produce identical diagnostics and outputs.

A behavior-preserving compiler change (a faster analysis, a different data
layout) must leave every observable result unchanged. This runs a baseline
and a candidate compiler over the conformance sources and the compiler's own
sources and compares exit status, stdout, stderr and emitted bytes.

Every unique conformance source is checked with --check. Corpus sources (and
upstream sources with --emit-upstream) are also emitted as native C at -O0 and
-O2 and as direct Wasm at -O2. The compiler's own sources are emitted as
native C at -O0 and -O2.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import time

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def extract_upstream(archive, target):
    with tarfile.open(archive) as bundle:
        for member in bundle:
            relative = Path(member.name)
            if relative.is_absolute() or '..' in relative.parts:
                raise RuntimeError('unexpected upstream archive member: ' + member.name)
            if not member.isfile():
                continue
            path = target / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            with bundle.extractfile(member) as source, path.open('wb') as out:
                shutil.copyfileobj(source, out)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True, help='fresh directory for outputs and the report')
    parser.add_argument('--stdlib', type=Path, default=ROOT / 'stdlib')
    parser.add_argument('--manifest', type=Path, default=ROOT / 'tests/conformance/cases.json')
    parser.add_argument('--selfhost', default=str(ROOT / 'selfhost'), help='compiler sources to emit; "" skips them')
    parser.add_argument('--emit-upstream', action='store_true', help='also emit every upstream source')
    parser.add_argument('--filter', default='', help='only sources whose path contains this text')
    parser.add_argument('--jobs', type=int, default=max(1, (os.cpu_count() or 2) // 2))
    parser.add_argument('--timeout', type=float, default=300)
    args = parser.parse_args()

    out = args.output_dir.resolve()
    if out.exists() and any(out.iterdir()):
        parser.error('output directory must be fresh')
    out.mkdir(parents=True, exist_ok=True)
    compilers = {'baseline': args.baseline.resolve(strict=True), 'candidate': args.candidate.resolve(strict=True)}
    manifest = json.loads(args.manifest.read_text())
    upstream = out / 'upstream'
    archive = ROOT / manifest['upstream']['archive']
    if digest(archive) != manifest['upstream']['sha256']:
        parser.error('upstream source bundle changed')
    extract_upstream(archive, upstream)
    shutil.copytree(args.stdlib, upstream / 'stdlib')
    library = args.stdlib.resolve()

    # (label, source, cwd, library, modes)
    sources = {}
    for case in manifest['cases']:
        name = case['source']
        if name in sources or args.filter not in name:
            continue
        if name.startswith('upstream:'):
            path = upstream / name[len('upstream:'):]
            modes = ['check'] + (['native0', 'native2', 'wasm2'] if args.emit_upstream else [])
            sources[name] = (path, upstream, upstream / 'stdlib', modes)
        else:
            sources[name] = (ROOT / name, ROOT, library, ['check', 'native0', 'native2', 'wasm2'])
    if args.selfhost and args.filter in 'selfhost/main.goose':
        main_source = Path(args.selfhost).resolve() / 'main.goose'
        sources['selfhost/main.goose'] = (main_source, ROOT, library, ['check', 'native0', 'native2'])

    flags = {'check': ['--target', 'native', '--check'], 'native0': ['--target', 'native', '-O0'],
             'native2': ['--target', 'native', '-O2'], 'wasm2': ['--target', 'wasm-direct', '-O2']}
    jobs = [(name, mode) for name, (_, _, _, modes) in sources.items() for mode in modes]

    def run(name, mode, role):
        path, cwd, lib, _ = sources[name]
        key = hashlib.sha256(f'{name}\0{mode}'.encode()).hexdigest()[:16]
        directory = out / role / key
        directory.mkdir(parents=True, exist_ok=True)
        command = [str(compilers[role]), str(path), *flags[mode], '--stdlib', str(lib)]
        output = None
        if mode != 'check':
            output = directory / ('out.wasm' if mode == 'wasm2' else 'out.c')
            command += ['-o', str(output)]
        started = time.monotonic()
        try:
            result = subprocess.run(command, cwd=cwd, capture_output=True, timeout=args.timeout)
            code, stdout, stderr = result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired as error:
            code, stdout, stderr = 'timeout', error.stdout or b'', error.stderr or b''
        stderr = stderr.replace(str(directory).encode(), b'<out>')
        return {'exit': code, 'stdout': hashlib.sha256(stdout).hexdigest(),
                'stderr': hashlib.sha256(stderr).hexdigest(), 'stderr_head': stderr[:400].decode(errors='replace'),
                'output': digest(output) if output is not None and output.exists() else None,
                'seconds': round(time.monotonic() - started, 3)}

    def compare(job):
        name, mode = job
        a = run(name, mode, 'baseline')
        b = run(name, mode, 'candidate')
        same = all(a[k] == b[k] for k in ('exit', 'stdout', 'stderr', 'output'))
        return {'source': name, 'mode': mode, 'same': same, 'baseline': a, 'candidate': b}

    results = []
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for index, row in enumerate(pool.map(compare, jobs), 1):
            results.append(row)
            if not row['same']:
                print('DIFFERS', row['mode'], row['source'], file=sys.stderr, flush=True)
            if index % 500 == 0:
                print(f'{index}/{len(jobs)} compared', flush=True)
    differing = [row for row in results if not row['same']]
    seconds = {role: round(sum(row[role]['seconds'] for row in results), 3) for role in compilers}
    report = {'schema': 'goose-output-equivalence-v1',
              'compilers': {role: {'path': str(path), 'sha256': digest(path)} for role, path in compilers.items()},
              'manifest_sha256': digest(args.manifest), 'stdlib': str(library),
              'selfhost': args.selfhost, 'emit_upstream': args.emit_upstream,
              'summary': {'compared': len(results), 'differing': len(differing), 'seconds': seconds},
              'differing': differing, 'results': results}
    (out / 'report.json').write_text(json.dumps(report, indent=1) + '\n')
    print(json.dumps(report['summary']))
    return 1 if differing else 0


if __name__ == '__main__':
    sys.exit(main())
