#!/usr/bin/env python3
"""Build direct WebAssembly or a native executable with the Goose compiler."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def invoke(command, verbose=False):
    command = list(map(str, command))
    if verbose:
        print(subprocess.list2cmdline(command), file=sys.stderr)
    start = time.perf_counter()
    result = subprocess.run(command, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace') or result.stdout.decode(errors='replace'))
    if verbose:
        sys.stderr.write(result.stderr.decode(errors='replace'))
    return (time.perf_counter() - start) * 1000


def same_file(a, b):
    """Whether writing resolved path a would write b: the same path, or one file under two names."""
    if a == b:
        return True
    try:
        return os.path.samefile(a, b)
    except OSError:
        return False


def check_destinations(destinations, inputs):
    """Reject an output that aliases an input or another output, before anything is written."""
    if any(same_file(path, source) for path in destinations for source in inputs):
        raise RuntimeError('an output would overwrite an input')
    if any(same_file(a, b) for i, a in enumerate(destinations) for b in destinations[i + 1:]):
        raise RuntimeError('output, C output and stats must use different paths')


def build(args):
    started = time.perf_counter()
    source = args.source.resolve(strict=True)
    compiler = Path(args.goose or args.build_dir / 'bin/goose').resolve(strict=True)
    output = args.output.resolve()
    library = args.stdlib or compiler.parent / 'stdlib'
    protected = {source, compiler, *(p.resolve() for p in args.c_source), *(p.resolve() for p in args.include)}
    destinations = [output, *(p.resolve() for p in (args.emit_c, args.stats) if p)]
    check_destinations(destinations, protected)
    if args.backend == 'direct':
        if output.suffix != '.wasm':
            raise RuntimeError('direct output must end in .wasm')
        if args.c_source or args.include or args.c_include_dir or args.emit_c:
            raise RuntimeError('C inputs require the native backend')
    if not 1 <= args.initial_pages <= args.maximum_pages <= 32768:
        raise RuntimeError('memory pages require 1 <= initial <= maximum <= 32768')
    output.parent.mkdir(parents=True, exist_ok=True)
    report = {'schema': 'goose-build-v3', 'implementation': 'goose', 'backend': args.backend,
              'compiler': str(compiler), 'compiler_sha256': digest(compiler), 'source': str(source),
              'source_sha256': digest(source), 'output': str(output), 'optimization': args.optimization,
              'cache': 'disabled', 'frontend_ms': 0.0, 'cc_ms': 0.0}
    with tempfile.TemporaryDirectory(prefix='.goose-build-', dir=output.parent) as directory:
        stage = Path(directory)
        generated = stage / 'program.c'
        artifact = stage / 'program.wasm'
        target = 'wasm-direct'
        if args.backend == 'native':
            target = 'native'
            artifact = generated
        deps, stats = stage / 'dependencies.json', stage / 'stats.json'
        command = [compiler, source, '--target', target, '--stdlib', library, args.optimization,
                   '-o', artifact, '--wasm-deps', deps, '--wasm-stats', stats,
                   '--wasm-initial-pages', str(args.initial_pages), '--wasm-max-pages', str(args.maximum_pages)]
        if args.debug:
            command.append('--debug')
        report['frontend_ms'] = invoke(command, args.verbose)
        # Every file in the dependency manifest is an input, imported sources
        # included; only the trailing build record names no file.
        for entry in json.loads(deps.read_text()):
            if entry.get('path'):
                protected.add(Path(entry['path']).resolve())
        check_destinations(destinations, protected)
        report['backend_stats'] = json.loads(stats.read_text())
        if report['backend_stats'].get('implementation') != 'goose':
            raise RuntimeError('installed compiler is outdated; run scripts/bootstrap.py')
        if args.backend == 'direct':
            if artifact.read_bytes()[:8] != b'\0asm\x01\0\0\0':
                raise RuntimeError('compiler did not emit WebAssembly')
        else:
            cc = shutil.which(args.cc or os.environ.get('CC', 'gcc'))
            if not cc:
                raise RuntimeError('native C compiler not found')
            if args.include:
                headers = ''.join('#include ' + json.dumps(str(p.resolve())) + '\n' for p in args.include)
                generated.write_text(headers + generated.read_text())
            artifact = stage / 'program'
            command = [cc, '-std=gnu11', args.optimization, '-fno-strict-aliasing', '-ffp-contract=off',
                       '-rdynamic', generated, *args.c_source, '-lm', '-ldl', '-pthread', '-o', artifact]
            for path in args.c_include_dir:
                command.extend(['-I', str(path.resolve())])
            report['cc_ms'] = invoke(command, args.verbose)
            report.update(cc=str(Path(cc).resolve()), cc_sha256=digest(cc))
            if args.emit_c:
                args.emit_c.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(generated, args.emit_c)
        report.update(output_bytes=artifact.stat().st_size, output_sha256=digest(artifact))
        if args.backend == 'direct':
            report['module_sha256'] = report['output_sha256']
        os.replace(artifact, output)
    report['total_ms'] = (time.perf_counter() - started) * 1000
    if args.stats:
        args.stats.parent.mkdir(parents=True, exist_ok=True)
        args.stats.write_text(json.dumps(report, indent=2) + '\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('version')
    command = commands.add_parser('build')
    command.add_argument('source', type=Path)
    command.add_argument('-o', '--output', type=Path, required=True)
    command.add_argument('--backend', choices=('direct', 'native'), default='direct')
    command.add_argument('--build-dir', type=Path, default=ROOT / 'build')
    command.add_argument('--goose', type=Path)
    command.add_argument('--stdlib', type=Path)
    command.add_argument('--cc')
    command.add_argument('--debug', action='store_true')
    command.add_argument('--no-cache', action='store_true', help='all current builds compile from source')
    command.add_argument('--initial-pages', type=int, default=16)
    command.add_argument('--maximum-pages', type=int, default=256)
    levels = command.add_mutually_exclusive_group()
    for flag in ('-O0', '-O1', '-O2'):
        levels.add_argument(flag, dest='optimization', action='store_const', const=flag)
    command.set_defaults(optimization='-O2')
    for name in ('c-source', 'c-include-dir', 'include'):
        command.add_argument('--' + name, type=Path, action='append', default=[])
    command.add_argument('--emit-c', type=Path)
    command.add_argument('--stats', type=Path)
    command.add_argument('--json', action='store_true')
    command.add_argument('--verbose', '-v', action='store_true')
    args = parser.parse_args()
    try:
        if args.command == 'version':
            print((ROOT / 'toolchain.json').read_text(), end='')
            return 0
        report = build(args)
        if args.json:
            print(json.dumps(report))
        else:
            print(str(args.output) + ' (' + str(report['output_bytes']) + ' bytes)')
        return 0
    except (OSError, RuntimeError, ValueError) as error:
        print('goose-wasm: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
