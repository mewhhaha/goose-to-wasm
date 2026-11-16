#!/usr/bin/env python3
"""measure.py COMPILER OUT.json: the compiler as a 64-bit-memory Wasm module, timed and compared.

Builds selfhost/main.goose with COMPILER for 64-bit memory (256 GiB declared for Wasmtime, 16 GiB for V8),
runs the module under both hosts on a small example and on the compiler's own source, and compares every
output with COMPILER's own. Wall times, three runs each; run from the repository root with the venv's python.
"""
import hashlib, json, subprocess, sys, tempfile, time
from pathlib import Path

compiler, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2])
work = Path(tempfile.mkdtemp(prefix='m64-'))
RUNS = 3
rows = []

def run(command, **extra):
    started = time.perf_counter()
    result = subprocess.run(list(map(str, command)), capture_output=True, stdin=subprocess.DEVNULL, **extra)
    return time.perf_counter() - started, result

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def row(name, command, expect=0, output=None, same_as=None, runs=RUNS):
    times, last = [], None
    for _ in range(runs):
        seconds, last = run(command)
        times.append(round(seconds, 3))
    entry = {'name': name, 'command': ' '.join(map(str, command)).replace(str(work), '$WORK').replace(str(compiler), '$COMPILER'),
             'seconds': times, 'exit_code': last.returncode, 'stderr': last.stderr.decode(errors='replace')[-400:]}
    if output is not None and Path(output).is_file():
        entry['bytes'] = Path(output).stat().st_size
        entry['sha256'] = sha(output)
        if same_as is not None:
            entry['same_as_native'] = Path(same_as).is_file() and sha(same_as) == entry['sha256']
    entry['as_expected'] = last.returncode == expect
    rows.append(entry)
    print(name, times, last.returncode, entry.get('same_as_native'), flush=True)
    return entry

std = ['--stdlib', 'stdlib']
big = work / 'goose64.wasm'; v8 = work / 'goose64-v8.wasm'; cache = work / 'goose64.cwasm'
wide = ['--debug', '--wasm-memory64', '--wasm-max-pages', '4194304']
row('native: emit the compiler, 64-bit memory, 256 GiB', [compiler, 'selfhost/main.goose', *std, '--target', 'wasm-direct', '-O2', *wide, '-o', big], output=big)
row('native: emit the compiler, 64-bit memory, 16 GiB', [compiler, 'selfhost/main.goose', *std, '--target', 'wasm-direct', '-O2', '--debug', '--wasm-memory64', '--wasm-max-pages', '262144', '-o', v8], output=v8, runs=1)
wasmtime = [sys.executable, 'scripts/run_wasmtime.py', big, '--cache', cache, '--']
node = ['node', 'scripts/run_wasm.mjs', v8, '--']
# Native references.
for name, arguments, suffix in (
        ('squares to wasm32', ['examples/squares.goose', *std, '--target', 'wasm-direct', '-O2'], 'wasm'),
        ('squares to C', ['examples/squares.goose', *std, '--target', 'native', '-O2'], 'c'),
        ('itself to wasm32', ['selfhost/main.goose', *std, '--target', 'wasm-direct', '-O2', '--wasm-max-pages', '65535'], 'wasm'),
        ('itself to 64-bit Wasm', ['selfhost/main.goose', *std, '--target', 'wasm-direct', '-O2', *wide], 'wasm'),
        ('itself to C', ['selfhost/main.goose', *std, '--target', 'native', '-O2'], 'c')):
    key = name.replace(' ', '-')
    reference = work / f'{key}.native.{suffix}'
    row(f'native: {name}', [compiler, *arguments, '-o', reference], output=reference)
    if name == 'squares to wasm32':
        row('wasmtime, first run (compiles the module): squares to wasm32', [*wasmtime, *arguments, '-o', work / 'first.wasm'], output=work / 'first.wasm', same_as=reference, runs=1)
    hosted = work / f'{key}.wasmtime.{suffix}'
    row(f'wasmtime: {name}', [*wasmtime, *arguments, '-o', hosted], output=hosted, same_as=reference)
    if name.startswith('squares'):
        hosted = work / f'{key}.v8.{suffix}'
        row(f'v8: {name}', [*node, *arguments, '-o', hosted], output=hosted, same_as=reference)
row('native: check itself', [compiler, 'selfhost/main.goose', *std, '--check'])
row('wasmtime: check itself', [*wasmtime, 'selfhost/main.goose', *std, '--check'])
row('v8: check itself (16 GiB)', [*node, 'selfhost/main.goose', *std, '--check'], expect=1, runs=1)
import os
os.environ['GOOSE_REGION_STATS'] = '1'
row('v8: check itself, region use', [*node, 'selfhost/main.goose', *std, '--check'], expect=1, runs=1)
fixed = sha(work / 'itself-to-64-bit-Wasm.wasmtime.wasm') == sha(big)
versions = {'node': subprocess.run(['node', '-p', 'process.version + " v8 " + process.versions.v8'], capture_output=True, text=True).stdout.strip(),
            'wasmtime': __import__('importlib.metadata').metadata.version('wasmtime'),
            'source': subprocess.run(['git', 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip(),
            'source_dirty': bool(subprocess.run(['git', 'status', '--porcelain', 'selfhost', 'scripts', 'stdlib'], capture_output=True, text=True).stdout.strip())}
out.write_text(json.dumps({'versions': versions, 'fixed_point_64bit_module_reproduces_itself': fixed, 'rows': rows}, indent=1) + '\n')
print('fixed point', fixed)
