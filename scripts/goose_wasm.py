#!/usr/bin/env python3
"""Build direct WebAssembly or a native executable with the Goose compiler."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
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


# Generated C marks where the runtime unit ends and program functions begin.
RUNTIME_END = '\n#else /* program units */\n'
FUNCTION_SLICE = '\n#if G_IN_'
# Automatic splitting: one program unit per this many bytes of emitted program
# functions, at most one per CPU. Each unit also parses the shared prelude.
UNIT_BYTES = 2 << 20


def native_layout(text):
    """The runtime unit's source, and the bytes of program functions, in C
    from a compiler that marks them (native/units.h); None from an older one."""
    end, first = text.find(RUNTIME_END), text.find(FUNCTION_SLICE)
    if end < 0 or first < 0:
        return None
    return text[:end + 1] + '#endif\n', len(text) - first


def jobs_value(text):
    if text == 'auto':
        return None
    value = int(text)
    if not 1 <= value <= 840:
        raise argparse.ArgumentTypeError('jobs must be auto or 1 to 840')
    return value


def native_units(jobs, function_bytes):
    if jobs:
        return jobs
    return max(1, min(os.process_cpu_count() or 1, function_bytes // UNIT_BYTES))


def runtime_key(cc, flags, source):
    """Names a runtime object by its source text, flags and C compiler."""
    version = subprocess.run([cc, '--version'], capture_output=True).stdout.decode(errors='replace')
    identity = [source, str(Path(cc).resolve()), digest(cc), version, flags]
    return hashlib.sha256(json.dumps(identity).encode()).hexdigest()


def compile_native(args, cc, generated, text, artifact, stage, report):
    """Compile native C as one translation unit (--jobs 1, or C without unit
    marks), or as program units beside the runtime unit, concurrently. The
    runtime object is cached under the build directory unless --no-cache."""
    flags = ['-std=gnu11', args.optimization, '-fno-strict-aliasing', '-ffp-contract=off']
    includes = [item for path in args.c_include_dir for item in ('-I', str(path.resolve()))]
    tail = [*args.c_source, '-lm', '-ldl', '-pthread', '-o', artifact, *includes]
    layout = None if args.jobs == 1 else native_layout(text)
    units = native_units(args.jobs, layout[1]) if layout else 1
    # Without a cache, one program unit beside the runtime unit only adds work.
    if layout is None or units == 1 and args.no_cache and not args.jobs:
        report.update(native_units=1, runtime_unit='embedded')
        return invoke([cc, *flags, '-rdynamic', generated, *tail], args.verbose)
    runtime, function_bytes = layout
    started = time.perf_counter()
    objects = [stage / f'unit{unit}.o' for unit in range(units)]
    commands = [[cc, *flags, f'-DG_UNITS={units}', f'-DG_UNIT={unit}', '-c', generated, '-o', objects[unit], *includes]
                for unit in range(units)]
    runtime_c, runtime_o, cached = stage / 'runtime.c', stage / 'runtime.o', None
    if not args.no_cache:
        cache = (args.cache_dir or args.build_dir / 'cache' / 'native-runtime').resolve()
        cached = cache / (runtime_key(cc, flags, runtime) + '.o')
    hit = cached is not None and cached.is_file()
    if not hit:
        runtime_c.write_text(runtime)
        commands.append([cc, *flags, '-DG_RUNTIME_UNIT', '-c', runtime_c, '-o', runtime_o])
    with ThreadPoolExecutor(min(len(commands), os.process_cpu_count() or 1)) as pool:
        list(pool.map(lambda argv: invoke(argv, args.verbose), commands))
    if hit:
        runtime_o = cached
    elif cached is not None:
        cached.parent.mkdir(parents=True, exist_ok=True)
        pending = cached.with_name(f'.{cached.name}.{os.getpid()}.tmp')
        shutil.copyfile(runtime_o, pending)
        os.replace(pending, cached)
    compiled = (time.perf_counter() - started) * 1000
    linked = invoke([cc, *flags, '-rdynamic', runtime_o, *objects, *tail], args.verbose)
    report.update(native_units=units, native_function_bytes=function_bytes,
                  runtime_unit='cached' if hit else 'compiled', cc_compile_ms=compiled, cc_link_ms=linked)
    return compiled + linked


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
            text = generated.read_text()
            if args.include:
                headers = ''.join('#include ' + json.dumps(str(p.resolve())) + '\n' for p in args.include)
                generated.write_text(headers + text)
            artifact = stage / 'program'
            report['cc_ms'] = compile_native(args, cc, generated, text, artifact, stage, report)
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
    command.add_argument('--jobs', type=jobs_value, default=None, metavar='N|auto',
                         help='native C compiles as N program units in parallel with the runtime unit; '
                              '1 compiles one translation unit with the runtime embedded (default: auto, '
                              'by program size and CPUs)')
    command.add_argument('--cache-dir', type=Path, help='runtime objects (default: BUILD_DIR/cache/native-runtime)')
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
