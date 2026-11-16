#!/usr/bin/env python3
"""measure.py COMPILER BEFORE OUT.json: the compiler as a Wasm module under three hosts, timed and compared.

COMPILER is the compiler measured; BEFORE the previous one, for the size and start-up it had. Builds
selfhost/main.goose as a 64-bit module with region statistics for Wasmtime (256 GiB declared), takes a region
profile from a self-check there, builds a 64-bit (16 GiB) and a 32-bit module with that profile for V8, and
runs: a small example, the self-check and the self-compiles, each output compared with COMPILER's own.
The profile is taken from the self-compile to 32-bit Wasm under Wasmtime.
Wall times, three runs each unless noted. Run from the repository root with the venv's python; needs node
and host/rust built."""
import hashlib, json, os, subprocess, sys, tempfile, time
from pathlib import Path

compiler, before, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve(), Path(sys.argv[3])
work = Path(tempfile.mkdtemp(prefix='m2-'))
rust = Path('host/rust/target/release/goose-wasmtime').resolve()
rows = []

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def locals_of(module):
    data = Path(module).read_bytes()
    def unsigned(at):
        value = shift = 0
        while True:
            byte = data[at]; at += 1; value |= (byte & 0x7F) << shift; shift += 7
            if byte < 0x80: return value, at
    at, counts = 8, []
    while at < len(data):
        section = data[at]; size, at = unsigned(at + 1)
        if section == 10:
            bodies, cursor = unsigned(at)
            for _ in range(bodies):
                length, cursor = unsigned(cursor); groups, inner = unsigned(cursor); total = 0
                for _ in range(groups):
                    count, inner = unsigned(inner); inner += 1; total += count
                counts.append(total); cursor += length
        at += size
    return {'functions': len(counts), 'locals': sum(counts), 'most_in_one_function': max(counts)}

def row(name, command, expect=0, output=None, same_as=None, runs=3, environment=None):
    times, last = [], None
    for _ in range(runs):
        started = time.perf_counter()
        last = subprocess.run(list(map(str, command)), capture_output=True, stdin=subprocess.DEVNULL, env=dict(os.environ, **(environment or {})))
        times.append(round(time.perf_counter() - started, 3))
    text = ' '.join(map(str, command)).replace(str(work), '$WORK').replace(str(compiler), '$COMPILER').replace(str(before), '$BEFORE').replace(str(rust), 'goose-wasmtime').replace(sys.executable, 'python')
    entry = {'name': name, 'command': text, 'seconds': times, 'exit_code': last.returncode, 'stderr': last.stderr.decode(errors='replace')[-500:], 'as_expected': last.returncode == expect}
    if output is not None and Path(output).is_file():
        entry['bytes'] = Path(output).stat().st_size; entry['sha256'] = sha(output)
        if same_as is not None:
            entry['same_as_native'] = Path(same_as).is_file() and sha(same_as) == entry['sha256']
    rows.append(entry)
    print(name, times, last.returncode, entry.get('same_as_native'), flush=True)
    return entry

std = ['--stdlib', 'stdlib']
self_ = ['selfhost/main.goose', *std, '--target', 'wasm-direct', '-O2']
profile = work / 'goose.profile'
big, v64, v32, old = work / 'goose64.wasm', work / 'goose-v8-64.wasm', work / 'goose-v8-32.wasm', work / 'before64.wasm'
big_options = ['--debug', '--wasm-memory64', '--wasm-region-stats', '--wasm-max-pages', '4194304']
v64_options = ['--debug', '--wasm-memory64', '--wasm-max-pages', '262144', '--wasm-region-profile', profile]
v32_options = ['--debug', '--wasm-max-pages', '65535', '--wasm-region-profile', profile]
row('native: emit the compiler, 64-bit, 256 GiB, region statistics', [compiler, *self_, *big_options, '-o', big], output=big)
row('previous compiler: emit the compiler, 64-bit, 16 GiB', [before, *self_, '--debug', '--wasm-memory64', '--wasm-max-pages', '262144', '-o', old], output=old, runs=1)
wasmtime = [rust, big, '--cache', work / 'goose64.cwasm', '--']
python = [sys.executable, 'scripts/run_wasmtime.py', big, '--cache', work / 'goose64.py.cwasm', '--']
squares = ['examples/squares.goose', *std, '--target', 'wasm-direct', '-O2']
reference = work / 'squares.native.wasm'
row('native: squares to wasm32', [compiler, *squares, '-o', reference], output=reference)
row('wasmtime (rust host), first run, compiles the module: squares', [*wasmtime, *squares, '-o', work / 'first.wasm'], output=work / 'first.wasm', same_as=reference, runs=1)
row('wasmtime (rust host): squares', [*wasmtime, *squares, '-o', work / 'sq.rs.wasm'], output=work / 'sq.rs.wasm', same_as=reference)
row('wasmtime (python runner), first run, compiles the module: squares', [*python, *squares, '-o', work / 'firstpy.wasm'], output=work / 'firstpy.wasm', same_as=reference, runs=1)
row('wasmtime (python runner): squares', [*python, *squares, '-o', work / 'sq.py.wasm'], output=work / 'sq.py.wasm', same_as=reference)
row('native: check itself', [compiler, 'selfhost/main.goose', *std, '--check'])
row('wasmtime (rust host): check itself', [*wasmtime, 'selfhost/main.goose', *std, '--check'])
row('wasmtime (python runner): check itself', [*python, 'selfhost/main.goose', *std, '--check'])
for name, options, suffix in (('itself to wasm32', ['--target', 'wasm-direct', '-O2', '--wasm-max-pages', '65535'], 'wasm'),
                              ('itself to 64-bit Wasm', ['--target', 'wasm-direct', '-O2', *big_options], 'wasm'),
                              ('itself to C', ['--target', 'native', '-O2'], 'c')):
    key = name.replace(' ', '-'); native = work / f'{key}.native.{suffix}'; hosted = work / f'{key}.wasmtime.{suffix}'
    row(f'native: {name}', [compiler, 'selfhost/main.goose', *std, *options, '-o', native], output=native)
    # The region profile is what the first of these, a whole compile, needed.
    taking = {'GOOSE_REGION_PROFILE': str(profile), 'GOOSE_REGION_STATS': '1'} if name == 'itself to wasm32' else None
    row(f'wasmtime (rust host): {name}' + (', writing the region profile' if taking else ''), [*wasmtime, 'selfhost/main.goose', *std, *options, '-o', hosted], output=hosted, same_as=native, environment=taking)
row('native: emit the compiler, 64-bit, 16 GiB, profile', [compiler, *self_, *v64_options, '-o', v64], output=v64, runs=1)
row('native: emit the compiler, 32-bit, 4 GiB, profile', [compiler, *self_, *v32_options, '-o', v32], output=v32, runs=1)
for label, module, options in (('v8, 64-bit module', v64, v64_options), ('v8, 32-bit module', v32, v32_options)):
    node = ['node', 'scripts/run_wasm.mjs', module, '--']
    row(f'{label}: squares', [*node, *squares, '-o', work / 'sq.v8.wasm'], output=work / 'sq.v8.wasm', same_as=reference)
    row(f'{label}: check itself', [*node, 'selfhost/main.goose', *std, '--check'])
    again = work / (module.name + '.again')
    row(f'{label}: itself, with the options it was built with', [*node, *self_, *options, '-o', again], output=again, same_as=module)
# The previous compiler's module is only built, for its size and locals: these hosts cannot run it (it has
# no goose.reserve). Its times are in ../wasm-memory64.
equal = work / 'goose-v8-equal.wasm'
row('native: emit the compiler, 64-bit, 16 GiB, no profile', [compiler, *self_, '--debug', '--wasm-memory64', '--wasm-max-pages', '262144', '-o', equal], output=equal, runs=1)
row('v8, 64-bit module without a profile: check itself', ['node', 'scripts/run_wasm.mjs', equal, '--', 'selfhost/main.goose', *std, '--check'], expect=1, runs=1)
versions = {'node': subprocess.run(['node', '-p', 'process.version + " v8 " + process.versions.v8'], capture_output=True, text=True).stdout.strip(),
            'wasmtime': __import__('importlib.metadata').metadata.version('wasmtime'),
            'rust_host_sha256': sha(rust), 'rustc': subprocess.run(['rustc', '--version'], capture_output=True, text=True).stdout.strip(),
            'source': subprocess.run(['git', 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip(),
            'source_dirty': bool(subprocess.run(['git', 'status', '--porcelain', 'selfhost', 'scripts', 'stdlib', 'host'], capture_output=True, text=True).stdout.strip())}
out.write_text(json.dumps({'versions': versions, 'profile': profile.read_text(),
                           'locals': {'this compiler, 64-bit 256 GiB module': locals_of(big), 'previous compiler, 64-bit 16 GiB module': locals_of(old)},
                           'rows': rows}, indent=1) + '\n')
print('done')
