#!/usr/bin/env python3
"""Build the Goose compiler from a checked-in, reproducible C bootstrap seed."""
from __future__ import annotations

import argparse
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
    parser.add_argument('--verify', action='store_true', help='require identical next-generation C output')
    parser.add_argument('--seed-only', action='store_true', help='build the frozen seed, without compiling current sources')
    parser.add_argument('--timeout', type=float, default=900)
    args = parser.parse_args()
    out = args.output_dir.resolve()
    out.mkdir(parents=True, exist_ok=False)
    report = {'schema': 'goose-bootstrap-v2', 'status': 'running', 'commands': []}

    def command(argv, name):
        argv = list(map(str, argv))
        started = time.monotonic()
        result = subprocess.run(argv, cwd=ROOT, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=args.timeout)
        (out / (name + '.stdout')).write_bytes(result.stdout)
        (out / (name + '.stderr')).write_bytes(result.stderr)
        row = {'command': argv, 'exit_code': result.returncode,
               'seconds': time.monotonic() - started,
               'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(),
               'stderr_sha256': hashlib.sha256(result.stderr).hexdigest()}
        report['commands'].append(row)
        save(out / 'report.json', report)
        if result.returncode:
            raise RuntimeError(name + ' failed: ' + result.stderr[-4000:].decode(errors='replace'))
        return result.stdout

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
        report['cc_version'] = command([cc, '--version'], 'cc-version').decode(errors='replace')
        seed_executable = out / 'seed'
        command([cc, '-std=gnu11', '-O2', c_source, '-lm', '-ldl', '-pthread', '-o', seed_executable], 'build-seed')
        executable = out / 'goose'
        if args.seed_only:
            shutil.copyfile(seed_executable, executable)
            executable.chmod(0o755)
            report['source_kind'] = 'frozen-bootstrap-seed'
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
            invocation = [sources / 'main.goose', '--stdlib', library, '--target', 'native', '-O0']
            if source_hashes == pin['source_sha256'] and report['stdlib_sha256'] == seed_library and assets == pin.get('asset_sha256', {}):
                shutil.copyfile(c_source, generated)
                report['seed_matches_sources'] = True
                shutil.copyfile(seed_executable, executable)
                executable.chmod(0o755)
            else:
                command([seed_executable, *invocation, '-o', generated], 'compile-goose')
                command([cc, '-std=gnu11', '-O2', generated, '-lm', '-ldl', '-pthread', '-o', executable], 'build-goose')
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
                    command([cc, '-std=gnu11', '-O2', following, '-lm', '-ldl', '-pthread', '-o', second], 'build-next-generation')
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
