#!/usr/bin/env python3
"""Build the Goose compiler from a checked-in, reproducible C bootstrap seed."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import gzip
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
SEED = ROOT / 'bootstrap'


def digest(path):
    with Path(path).open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def save(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path, default=ROOT / 'selfhost')
    parser.add_argument('--seed-dir', type=Path, default=SEED)
    parser.add_argument('--stdlib', type=Path, default=ROOT / 'stdlib')
    parser.add_argument('--native-dir', type=Path, default=ROOT / 'native')
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'build' / 'selfhost')
    parser.add_argument('--cc', default=os.environ.get('CC', 'clang'))
    parser.add_argument('--optimization', type=int, choices=(0, 1, 2), default=2,
                        help='Goose optimization level for compiler emission (default: 2)')
    parser.add_argument('--verify', action='store_true', help='require identical next-generation C output')
    parser.add_argument('--seed-only', action='store_true', help='build the frozen seed, without compiling current sources')
    parser.add_argument('--timeout', type=float, default=900)
    parser.add_argument('--jobs', type=int, default=1,
                        help='compile C that marks its units (native/units.h) as this many program units '
                             'in parallel, without a profile; development builds only (default: 1)')
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error('--jobs must be at least 1')
    out = args.output_dir.resolve()
    out.mkdir(parents=True, exist_ok=False)
    report = {'schema': 'goose-bootstrap-v2', 'status': 'running', 'commands': [],
              'goose_optimization': args.optimization,
              'requested_goose_optimization': args.optimization}

    recording = threading.Lock()

    def command(argv, name, cwd=out, allow_failure=False):
        argv = list(map(str, argv))
        started = time.monotonic()
        result = subprocess.run(argv, cwd=cwd, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=args.timeout)
        (out / (name + '.stdout')).write_bytes(result.stdout)
        (out / (name + '.stderr')).write_bytes(result.stderr)
        row = {'name': name, 'command': argv, 'cwd': str(cwd), 'exit_code': result.returncode,
               'seconds': time.monotonic() - started,
               'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(),
               'stderr_sha256': hashlib.sha256(result.stderr).hexdigest()}
        with recording:
            report['commands'].append(row)
            save(out / 'report.json', report)
        if result.returncode and not allow_failure:
            raise RuntimeError(name + ' failed: ' + result.stderr[-4000:].decode(errors='replace'))
        return result

    try:
        seed = args.seed_dir.resolve()
        pin = json.loads((seed / 'seed.json').read_bytes())
        compressed = seed / 'seed.c.gz'
        bundle = seed / 'sources.tar.gz'
        if digest(compressed) != pin['compressed_sha256']:
            raise RuntimeError('bootstrap seed checksum differs')
        if digest(bundle) != pin['source_bundle_sha256']:
            raise RuntimeError('bootstrap source bundle checksum differs')
        c_source = out / 'seed.c'
        c_source.write_bytes(gzip.decompress(compressed.read_bytes()))
        if digest(c_source) != pin['c_sha256']:
            raise RuntimeError('decompressed bootstrap seed checksum differs')
        cc = shutil.which(args.cc)
        if not cc:
            raise RuntimeError('C compiler not found: ' + args.cc)
        cc = Path(cc).resolve()
        report.update(seed_c_sha256=pin['c_sha256'], cc=str(cc), cc_sha256=digest(cc),
                      bootstrap_source_sha256=pin['source_sha256'],
                      input_sha256={str(p): digest(p) for p in [Path(__file__), seed / 'seed.json', compressed, bundle, cc]})
        report['cc_version'] = command([cc, '--version'], 'cc-version').stdout.decode(errors='replace')
        report['cc_target'] = command([cc, '-dumpmachine'], 'cc-target').stdout.decode().strip()
        base_flags = ['-std=gnu11', '-O2', '-lm', '-ldl', '-pthread']
        clang = re.search(r'\bclang version (\d+)\.', report['cc_version'])
        identity = {'clang_major': None, 'target': report['cc_target'],
                    'base_flags': base_flags, 'c_basename': 'seed.c'}
        if clang:
            identity['clang_major'] = int(clang.group(1))
        report['profile_identity'] = identity
        profile = None
        profile_reason = 'optional profile metadata absent'
        metadata_path = seed / 'profile.json'
        data_path = seed / 'profile.profdata'
        if metadata_path.is_file():
            report['input_sha256'][str(metadata_path)] = digest(metadata_path)
            try:
                profile = json.loads(metadata_path.read_bytes())
                if not isinstance(profile, dict):
                    raise ValueError('metadata must be an object')
                if data_path.is_file():
                    report['input_sha256'][str(data_path)] = digest(data_path)
                else:
                    profile_reason = 'profile data absent'
                    profile = None
            except (ValueError, OSError) as error:
                profile_reason = 'invalid profile metadata: ' + str(error)
                profile = None
        report['builds'] = {}

        def build(source, executable, name, optimization):
            # LLVM keys internal functions by the translation unit basename.
            # Keep original inputs intact and compile each stage as seed.c.
            stage = out / ('cc-' + name)
            stage.mkdir()
            staged_c = stage / 'seed.c'
            shutil.copyfile(source, staged_c)
            c_hash = digest(staged_c)
            row = {'c_sha256': c_hash, 'goose_optimization': optimization,
                   'profile_used': False, 'profile_reason': profile_reason}
            report['builds'][name] = row
            text = staged_c.read_text() if args.jobs > 1 else ''
            runtime_end = text.find('\n#else /* program units */\n')
            if runtime_end >= 0:
                # Development builds: units compile at once, and the profile,
                # keyed by one translation unit's functions, does not apply.
                row.update(units=args.jobs, profile_reason='compiled as ' + str(args.jobs) + ' units without profile')
                (stage / 'runtime.c').write_text(text[:runtime_end + 1] + '#endif\n')
                compiles = [([cc, *base_flags[:2], '-DG_RUNTIME_UNIT', '-c', 'runtime.c', '-o', 'runtime.o'], name + '-runtime')]
                for unit in range(args.jobs):
                    compiles.append(([cc, *base_flags[:2], f'-DG_UNITS={args.jobs}', f'-DG_UNIT={unit}', '-c', 'seed.c',
                                      '-o', f'unit{unit}.o'], f'{name}-unit{unit}'))
                with ThreadPoolExecutor(len(compiles)) as pool:
                    list(pool.map(lambda job: command(*job, cwd=stage), compiles))
                command([cc, *base_flags[:2], 'runtime.o', *(f'unit{unit}.o' for unit in range(args.jobs)),
                         *base_flags[2:], '-o', executable], name, cwd=stage)
                return row
            matched = False
            if not clang:
                row['profile_reason'] = 'C compiler is not Clang'
            elif profile is not None:
                expected = dict(identity, schema='goose-bootstrap-profile-v1', c_sha256=c_hash)
                differing = [key for key, value in expected.items() if profile.get(key) != value]
                if differing:
                    row['profile_reason'] = 'profile identity differs: ' + ', '.join(differing)
                elif digest(data_path) != profile.get('data_sha256'):
                    row['profile_reason'] = 'profile data checksum differs'
                else:
                    matched = True
            argv = [cc, *base_flags[:2], 'seed.c', *base_flags[2:], '-o', executable]
            if matched:
                profile_flags = ['-fprofile-instr-use=' + str(data_path),
                                 '-Werror=profile-instr-out-of-date',
                                 '-Werror=profile-instr-missing',
                                 '-Werror=profile-instr-unprofiled']
                result = command([*argv, *profile_flags], name + '-profile', cwd=stage, allow_failure=True)
                if result.returncode == 0:
                    row.update(profile_used=True, profile_reason='exact profile identity matched',
                               profile_sha256=digest(data_path))
                    return row
                row['profile_reason'] = 'profile compilation failed; compiled without profile'
                row['profile_failed_command'] = report['commands'][-1]
            command(argv, name, cwd=stage)
            return row

        seed_executable = out / 'seed'
        actual_build = build(c_source, seed_executable, 'build-seed', pin.get('goose_optimization', 0))
        executable = out / 'goose'
        if args.seed_only:
            shutil.copyfile(seed_executable, executable)
            executable.chmod(0o755)
            report['source_kind'] = 'frozen-bootstrap-seed'
            report['goose_optimization'] = pin.get('goose_optimization', 0)
        else:
            sources = out / 'sources'
            sources.mkdir()
            for path in sorted(args.source_dir.resolve().glob('*.goose')):
                shutil.copyfile(path, sources / path.name)
            if not (sources / 'main.goose').is_file():
                raise RuntimeError('compiler source directory has no main.goose')
            library = out / 'stdlib'
            shutil.copytree(args.stdlib.resolve(), library)
            source_hashes = {p.name: digest(p) for p in sources.glob('*.goose')}
            assets = {}
            for source in sources.glob('*.goose'):
                for match in re.finditer(r'\bembed_file\(\s*"\.\./native/([^"\n]+)"\s*\)', source.read_text()):
                    relative = Path(match.group(1))
                    if relative.is_absolute() or '..' in relative.parts:
                        raise RuntimeError('invalid native runtime asset path: ' + str(relative))
                    original = args.native_dir.resolve() / relative
                    target = out / 'native' / relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(original, target)
                    assets['native/' + relative.as_posix()] = digest(target)
                    report['input_sha256'][str(original)] = digest(original)
            report.update(source_kind='current-goose-sources', source_sha256=source_hashes,
                          asset_sha256=assets,
                          stdlib_sha256={str(p.relative_to(library)): digest(p) for p in library.rglob('*.goose')})
            seed_library = pin.get('stdlib_sha256')
            if seed_library is None:
                seed_library = {}
                with tarfile.open(bundle) as archive:
                    for member in archive:
                        if member.isfile() and member.name.startswith('stdlib/') and member.name.endswith('.goose'):
                            data = archive.extractfile(member).read()
                            seed_library[member.name.removeprefix('stdlib/')] = hashlib.sha256(data).hexdigest()
            generated = out / 'compiler.c'
            invocation = ['sources/main.goose', '--stdlib', 'stdlib', '--target', 'native', f'-O{args.optimization}']
            if (source_hashes == pin['source_sha256'] and report['stdlib_sha256'] == seed_library and
                    assets == pin.get('asset_sha256', {}) and
                    pin.get('goose_optimization', 0) == args.optimization):
                shutil.copyfile(c_source, generated)
                report['seed_matches_sources'] = True
                shutil.copyfile(seed_executable, executable)
                executable.chmod(0o755)
            else:
                command([seed_executable, *invocation, '-o', generated], 'compile-goose')
                actual_build = build(generated, executable, 'build-goose', args.optimization)
            report['generated_c_sha256'] = digest(generated)
            report['executable_c_sha256'] = digest(generated)
            if args.verify:
                following = out / 'next-generation.c'
                command([executable, *invocation, '-o', following], 'verify-selfhost')
                report['next_generation_c_sha256'] = digest(following)
                if digest(generated) != digest(following):
                    # A changed backend can legitimately emit different C from
                    # the older seed. Compare two generations of that backend.
                    second = out / 'next-generation'
                    actual_build = build(following, second, 'build-next-generation', args.optimization)
                    third = out / 'third-generation.c'
                    command([second, *invocation, '-o', third], 'verify-next-generation')
                    report['third_generation_c_sha256'] = digest(third)
                    if digest(following) != digest(third):
                        raise RuntimeError('self-hosted C output differs between generations')
                    pending = out / '.verified-goose'
                    shutil.copyfile(second, pending)
                    pending.chmod(0o755)
                    pending.replace(executable)
                    report['executable_c_sha256'] = digest(following)
                report['fixed_point'] = True
        report['executable_build'] = actual_build
        report['goose_optimization'] = actual_build['goose_optimization']
        report['profile_used'] = actual_build['profile_used']
        report['executable_c_sha256'] = actual_build['c_sha256']
        report['input_sha256_after'] = {path: digest(path) for path in report['input_sha256']}
        if report['input_sha256_after'] != report['input_sha256']:
            raise RuntimeError('bootstrap inputs changed during the build')
        report.update(status='passed', executable=str(executable), executable_sha256=digest(executable))
    except BaseException as error:
        report.update(status='failed', error=type(error).__name__ + ': ' + str(error))
        save(out / 'report.json', report)
        print(report['error'], file=sys.stderr)
        return 1
    save(out / 'report.json', report)
    print(executable)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
