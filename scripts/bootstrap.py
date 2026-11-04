#!/usr/bin/env python3
"""Build and install the Goose compiler with a C compiler and the frozen seed."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', type=Path, default=ROOT / 'build')
    parser.add_argument('--source-dir', type=Path, default=ROOT / 'selfhost')
    parser.add_argument('--stdlib', type=Path, default=ROOT / 'stdlib')
    parser.add_argument('--cc', default=os.environ.get('CC', 'clang'))
    parser.add_argument('--verify', action='store_true', help='verify identical self-hosted C output')
    args = parser.parse_args()
    build = args.build_dir.resolve()
    build.mkdir(parents=True, exist_ok=True)
    evidence = build / 'bootstrap'
    evidence.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='goose-bootstrap-') as directory:
        stage = Path(directory) / 'compiler'
        command = [sys.executable, str(ROOT / 'selfhost/bootstrap.py'),
                   '--source-dir', str(args.source_dir.resolve()), '--stdlib', str(args.stdlib.resolve()),
                   '--output-dir', str(stage), '--cc', args.cc]
        if args.verify:
            command.append('--verify')
        result = subprocess.run(command, check=False)
        for path in stage.glob('*'):
            if path.name == 'report.json' or path.suffix in ('.stdout', '.stderr'):
                shutil.copy2(path, evidence / path.name)
        if result.returncode:
            return result.returncode
        report = json.loads((stage / 'report.json').read_text())
        install = build / 'bin'
        install.mkdir(exist_ok=True)
        pending = install / '.goose.new'
        shutil.copy2(stage / 'goose', pending)
        pending.replace(install / 'goose')
        pending_library = install / '.stdlib.new'
        if pending_library.exists():
            shutil.rmtree(pending_library)
        shutil.copytree(args.stdlib.resolve(), pending_library)
        library = install / 'stdlib'
        if library.exists():
            shutil.rmtree(library)
        pending_library.rename(library)
        metadata = {'schema': 'goose-toolchain-v2', 'implementation': 'goose',
                    'compiler': str(install / 'goose'), 'compiler_sha256': report['executable_sha256'],
                    'source_sha256': report['source_sha256'], 'stdlib_sha256': report['stdlib_sha256'],
                    'cc': report['cc'], 'cc_sha256': report['cc_sha256'],
                    'seed_c_sha256': report['seed_c_sha256'],
                    'fixed_point': report.get('fixed_point', False)}
        (build / 'toolchain.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(install / 'goose')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
