"""Prove counter extraction on a small Wasm module with predetermined counts."""
import argparse
from collections import Counter
import json
from pathlib import Path
import subprocess
import tempfile

import wasmtime
from instrument import instrument

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('decoder', type=lambda x: Path(x).resolve())
p.add_argument('--memory32', action='store_true', help='exercise i32 addresses and unsigned lengths')
a = p.parse_args()
address = "i64"
width = "memory64"
if a.memory32:
    address = "i32"
    width = "memory32"
wat = f'''
(module
 (import "test" "unused" (func))
 (memory (export "memory") {address} 1)
 (global i64 (i64.const 0))
 (func $control (export "control") (param $length {address}) (param $run i32)
   {address}.const 0 i32.const 70 {address}.const 16 memory.fill
   {address}.const 8 {address}.const 0 {address}.const 10 memory.copy
   {address}.const 32 {address}.const 8 local.get $length memory.copy
   {address}.const 48 {address}.const 32 i64.load i64.store
   {address}.const 64 i32.const 33 local.get $length memory.fill
   local.get $run if {address}.const 88 {address}.const 0 {address}.const 7 memory.copy end))
'''
with tempfile.TemporaryDirectory() as tmp:
    directory = Path(tmp)
    source, sites, out = (directory / f for f in ('control.wasm', 'sites.txt', 'measured.wasm'))
    source.write_bytes(wasmtime.wat2wasm(wat))
    sites.write_bytes(subprocess.check_output([a.decoder, source]))
    instrument(source, sites, out, {'control'})
    meta = json.loads(out.with_suffix('.map.json').read_text())
    assert meta['static_sites'] == 6
    cfg = wasmtime.Config()
    cfg.wasm_memory64 = True
    engine = wasmtime.Engine(cfg)
    snapshots = []
    for module in (source, out):
        store = wasmtime.Store(engine)
        instance = wasmtime.Instance(store, wasmtime.Module(engine, module.read_bytes()),
                                     [wasmtime.Func(store, wasmtime.FuncType([], []), lambda: None)])
        exports = instance.exports(store)
        for n in (8, 0):
            exports['control'](store, n, 0)
        snapshots.append(exports['memory'].read(store, 0, 96))
        if module == out:
            actual = Counter()
            for n, (_, _, kind, size, _, metric) in enumerate(meta['counters']):
                actual[kind, size, metric] += exports[f'probe.{n}'].value(store)
            expected = {('fill', 16, 'calls'): 2, ('copy', 10, 'calls'): 2, ('copy', -1, 'calls'): 2,
                        ('copy', -1, 'bytes'): 8, ('adjacent', 8, 'calls'): 2,
                        ('fill', -1, 'calls'): 2, ('fill', -1, 'bytes'): 8, ('copy', 7, 'calls'): 0}
            assert dict(actual) == expected, actual
    assert snapshots[0] == snapshots[1]
    assert snapshots[1][48:56] == b'F'*8 and snapshots[1][64:72] == b'!'*8
    print(json.dumps({'control': width + ', two calls, overlapping source/destination, zero dynamic length, '
                                'untaken copy, equal-width adjacent scalar load/store, memory compared',
                      'expected_equals_observed': True, 'source_and_instrumented_memory_equal': True,
                      'counters': [{'kind': k, 'size': w, 'metric': m, 'value': v}
                                   for (k, w, m), v in actual.items()]}, indent=2))
