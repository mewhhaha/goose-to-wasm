"""Execute the instrumented compiler through the normal Wasmtime host and read its counters."""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import sys
import threading
from importlib.metadata import version
from unittest.mock import patch

import wasmtime
from wasmtime import _ffi

p = argparse.ArgumentParser(description=__doc__)
for field in ('repo', 'stage', 'workload', 'named', 'module', 'expected', 'results'):
    p.add_argument(field, type=lambda x: Path(x).resolve())
p.add_argument('--mode', choices=['check', 'emit'], required=True)
p.add_argument('--cpu', type=int, required=True)
a = p.parse_args()
sys.path[:0] = [str(a.repo / 'scripts'), str(a.repo / 'bench')]
from run_wasmtime import run_module, create_hosted_config, HOSTED_STACK_BYTES
from selfhost_comparison import SOURCE, WASM_FLAGS, identity, verify_frozen_source

built, workload = (json.loads((d / 'builds.json').read_text()) for d in (a.stage, a.workload))
for d, record in ((a.stage, built), (a.workload, workload)):
    verify_frozen_source(d/'source', record['source_commit'], record['source_archive_sha256'])
base = a.stage / 'build-1/compiler.wasm'
assert identity(base) == built['samples'][0]['artifacts']['compiler.wasm']
assert identity(a.stage/'build-1/compiler-native') == built['samples'][0]['artifacts']['compiler-native']
plain, named = base.read_bytes(), a.named.read_bytes()
assert named.startswith(plain) and named[len(plain)] == 0
from instrument import read
size, pos = read(named, len(plain) + 1)
assert pos + size == len(named) and named[pos:pos+5] == b'\x04name'

data = a.module.read_bytes()
meta = json.loads(a.module.with_suffix('.map.json').read_text())
assert meta['input_sha256'] == identity(a.named)['sha256']
assert meta['output_sha256'] == hashlib.sha256(data).hexdigest()

# Keep the guest instance and store alive after the normal runner returns.
original = wasmtime.Linker.instantiate
held = []
def keep_instance(linker, store, module):
    instance = original(linker, store, module)
    held.append((store, instance))
    return instance

# A literal, fixed-length output argument keeps copies of CLI paths identical in both variants.
run_dir = a.results.parent / ('work-' + a.mode)
run_dir.mkdir(exist_ok=True)
for folder in ('selfhost', 'stdlib', 'native'):
    link = run_dir / folder
    target = (a.workload / 'source' / folder).resolve()
    if not link.exists():
        link.symlink_to(target, target_is_directory=True)
    assert link.resolve() == target
out = run_dir / 'emitted.wasm'
if a.mode == 'emit':
    out.unlink(missing_ok=True)
args = list(SOURCE)
if a.mode == 'check':
    args.append('--check')
else:
    args.extend([*WASM_FLAGS, '-o', out.name])
os.chdir(run_dir)
os.sched_setaffinity(0, {a.cpu})
threading.stack_size(HOSTED_STACK_BYTES + (64 << 20))
config = create_hosted_config()
config.cache = True
with patch.object(wasmtime.Linker, 'instantiate', keep_instance), ThreadPoolExecutor(1) as worker:
    result = worker.submit(run_module, data, b'', arguments=['compiler', *args],
                           config=config, timing=False).result()
assert (result['exit_code'], result['stdout'], result['stderr']) == (0, b'', ''), result
expected = None
if a.mode == 'emit':
    expected = identity(out)
    assert expected == identity(a.expected)
[(store, instance)] = held
exports = instance.exports(store)
per_site = {}
for i, (fid, function, kind, size, site, metric) in enumerate(meta['counters']):
    val = exports[f'probe.{i}'].value(store)
    assert val >= 0
    if not val:
        continue
    key = (fid, function, kind, size, site)
    item = per_site.setdefault(key, dict(function_id=fid, function=function, kind=kind, size=size, offset=site,
                                         calls=0, bytes=0))
    item[metric] = val
    if size >= 0:
        assert metric == 'calls'
        item['bytes'] = val*size
parts = list(per_site.values())
for row in parts:
    assert row['calls'] > 0

report = dict(compiler=built['source_commit'], compiler_archive_sha256=built['source_archive_sha256'],
              workload=workload['source_commit'], workload_archive_sha256=workload['source_archive_sha256'],
              wasm=identity(base), named=identity(a.named), instrumented=identity(a.module), wasmtime=version('wasmtime'),
              engine=identity(Path(_ffi.dll._name)), native=identity(a.stage/'build-1/compiler-native'),
              mode=a.mode, arguments=args,
              cpu=a.cpu, exit_code=0, expected_emission=expected,
              static_site_count=meta['static_sites'], counter_count=len(meta['counters']), active=parts)
a.results.write_text(json.dumps(report, separators=(',', ':'))+'\n')
rows = Counter()
for row in parts:
    if row['kind'] == 'copy':
        rows[row['function']] += row['bytes']
print(a.mode, 'total memory.copy', sum(rows.values()), 'top', rows.most_common(12))
