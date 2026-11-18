#!/usr/bin/env python3
"""Exercise the Wasm owner-control ABI across a host call and two indexed reads."""
import argparse
from pathlib import Path
import struct
import subprocess
import sys
import unittest

import wasmtime

sys.path.insert(0, str(Path(__file__).resolve().parent))
import goose_stats


SOURCE = '''extern fn prepare(rows: u8[>..]&) -> i64;
var rows: u8[>..] = [17, 34, 51];
fn main() {
    let index = prepare(rows);
    let a = rows[0] as i64;
    let b = rows[index] as i64;
    print(a * 100 + b);
}'''


def run_image(engine, module, width, payload, index, truncated=False):
    store = wasmtime.Store(engine)
    linker = wasmtime.Linker(engine)
    observed = []
    word = {32: 'I', 64: 'Q'}[width]
    header = struct.Struct('<' + word * 6)

    def prepare(caller, address):
        mem = caller.get('memory')
        base, count, limit, capacity, _, mode = header.unpack(mem.read(caller, address, address + header.size))
        assert (count, mode) == (3, 0)
        image = mem.data_len(caller) - len(payload)
        mem.write(caller, payload, image)
        # Mode 1 reads a one-byte length prefix. Mode 6 reads a ULEB prefix.
        mode = 1
        if truncated:
            mode = 6
        mem.write(caller, header.pack(base, count, limit, capacity, image, mode), address)
        return index

    def abort(caller, address, length, line):
        message = bytes(caller.get('memory').read(caller, address, address + length)).decode()
        observed.append((message, line))
        raise RuntimeError('guest abort')

    def unexpected(*args):
        raise AssertionError('unexpected host import')

    callbacks = {'prepare': (prepare, True), 'abort': (abort, True),
                 'print_i64': (observed.append, False), 'newline': (lambda: None, False)}
    for item in module.imports:
        callback, caller = callbacks.get(item.name, (unexpected, False))
        linker.define_func(item.module, item.name, item.type, callback, access_caller=caller)
    try:
        linker.instantiate(store, module).exports(store)['_start'](store)
    except RuntimeError as error:
        if str(error) != 'guest abort':
            raise
    return observed


class OwnerViewHost(unittest.TestCase):
    setUp = goose_stats.Compile.setUp

    def test_host_image_and_source_diagnostics(self):
        source = self.work / 'main.goose'
        source.write_text(SOURCE)
        output = self.work / 'program.wasm'
        engine = wasmtime.Engine()
        for width in (32, 64):
            for level in (0, 2):
                with self.subTest(width=width, level=level):
                    command = [str(goose_stats.GOOSE), str(source), '--stdlib', str(goose_stats.ROOT / 'stdlib'),
                               '--target', 'wasm-direct', f'-O{level}', '-o', str(output)]
                    if width == 64:
                        command.append('--wasm-memory64')
                    for flags in ([], ['--wasm-bundled-host']):
                        with self.subTest(flags=flags):
                            subprocess.run([*command, *flags], check=True, capture_output=True, timeout=60)
                            module = wasmtime.Module.from_file(engine, str(output))
                            self.assertEqual(run_image(engine, module, width, b'\x02MN', 1), [7778])
                            self.assertEqual(run_image(engine, module, width, b'\x02MN', 2), [('array index out of bounds', 6)])
                            self.assertEqual(run_image(engine, module, width, b'\x80', 1, True), [('truncated varint image', 5)])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--goose', type=Path, default=goose_stats.GOOSE)
    options, remaining = parser.parse_known_args()
    goose_stats.GOOSE = options.goose.resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
