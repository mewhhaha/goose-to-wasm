#!/usr/bin/env python3
"""Run the host ABI through the official minimal AOT runtime and check its limits."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import unittest

import test_native_wasmtime as native

ROOT = native.ROOT
FULL_HOST = native.HOST
AOT_HOST = ROOT / 'build/bin/goose-wasmtime-aot'


class AotHost(native.NativeHost):
    def invoke(self, command, data=b''):
        return subprocess.run(list(map(str, command)), input=data, capture_output=True, timeout=30)

    def prepare(self, path):
        artifact = path.with_suffix('.cwasm')
        result = self.invoke([FULL_HOST, '--aot-profile', 'minimal', '--no-cache',
                              '--compile', path, artifact])
        self.assertEqual(result.returncode, 0, result.stderr)
        return artifact

    def execute(self, command, data=b''):
        if Path(command[0]).resolve() == FULL_HOST:
            self.assertEqual(len(command), 2)
            artifact = self.prepare(command[1])
            return self.invoke([AOT_HOST, '--precompiled', artifact], data)
        return self.invoke(command, data)

    def compare(self, path, data=b'', diagnostic=None):
        reference = self.invoke([sys.executable, ROOT / 'scripts/run_wasmtime.py', path], data)
        artifact = self.prepare(path)
        for command in ([FULL_HOST, '--aot-profile', 'minimal', '--precompiled', artifact],
                        [AOT_HOST, '--precompiled', artifact]):
            with self.subTest(command=command):
                actual = self.invoke(command, data)
                self.assertEqual(actual.returncode, reference.returncode, actual.stderr)
                self.assertEqual(actual.stdout, reference.stdout)
                if diagnostic is not None:
                    self.assertIn(diagnostic, actual.stderr)
                elif reference.returncode == 0 or b'goose runtime error:' in reference.stderr:
                    self.assertEqual(actual.stderr, reference.stderr)
        return reference

    def test_timing_boundaries_and_explicit_precompiled_mode(self):
        path = self.module('(module (func (export "_start")))')
        artifact = self.prepare(path)
        timing = self.directory / 'timing.json'
        result = self.invoke([AOT_HOST, '--precompiled', artifact, '--timing-json', timing])
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, b'', b''))
        data = json.loads(timing.read_text())
        self.assertEqual(data['aot_profile'], 'minimal')
        self.assertEqual(data['optimization'], 'precompiled artifact')
        self.assertFalse(data['parallel_compilation'])
        self.assertFalse(data['compilation_cache_enabled'])
        self.assertEqual(data['engine_total_ns'], data['compile_instantiate_ns'] + data['start_function_ns'])
        self.assertGreater(data['engine_total_ns'], 0)

    def test_simd_tail_calls_bulk_memory_and_multiple_results(self):
        path = self.module('''(module
          (import "goose" "print_i64" (func $print (param i64)))
          (import "goose" "write" (func $write (param i32 i32)))
          (memory (export "memory") 1)
          (func $pair (result i64 i32) (i64.const 11) (i32.const 13))
          (func $tail (result i64 i32) (return_call $pair))
          (func (export "_start")
            (v128.store (i32.const 0) (i64x2.splat (i64.const 7)))
            (memory.copy (i32.const 16) (i32.const 0) (i32.const 16))
            (call $print (i64.load (i32.const 16)))
            (call $tail) drop (call $print)
            (memory.fill (i32.const 32) (i32.const 65) (i32.const 3))
            (call $write (i32.const 32) (i32.const 3))))''')
        self.assertEqual(self.compare(path).stdout, b'711AAA')

    def test_unsupported_proposals_keep_the_general_host_available(self):
        for wat in ('(module (type (struct (field i32))) (func (export "_start")))',
                    '(module (tag $e) (func (export "_start") (throw $e)))'):
            path = self.module(wat)
            artifact = path.with_suffix('.cwasm')
            limited = self.invoke([FULL_HOST, '--aot-profile', 'minimal', '--no-cache',
                                   '--compile', path, artifact])
            self.assertNotEqual(limited.returncode, 0)
            self.assertTrue(limited.stderr)
            ordinary = self.invoke([FULL_HOST, '--no-cache', '--compile', path, artifact])
            self.assertEqual(ordinary.returncode, 0, ordinary.stderr)

    def test_runtime_rejects_default_profile_and_non_aot_modes(self):
        path = self.module('(module (func (export "_start")))')
        artifact = path.with_suffix('.cwasm')
        ordinary = self.invoke([FULL_HOST, '--no-cache', '--compile', path, artifact])
        self.assertEqual(ordinary.returncode, 0, ordinary.stderr)
        result = self.invoke([AOT_HOST, '--precompiled', artifact])
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(result.stderr)
        for arguments in ([path], ['--serve'], ['--cache'], ['--no-cache'],
                          ['--no-parallel-compilation'], ['--compile', path, artifact],
                          ['--aot-profile', 'full', '--precompiled', artifact]):
            with self.subTest(arguments=arguments):
                result = self.invoke([AOT_HOST, *arguments])
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(result.stderr)
        for arguments in (['--aot-profile', 'minimal', path],
                          ['--aot-profile', 'minimal', '--serve']):
            result = self.invoke([FULL_HOST, *arguments])
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(result.stderr)

    @unittest.skipUnless(Path('/dev/full').exists(), 'requires /dev/full')
    def test_preparation_and_timing_write_failures(self):
        path = self.module('(module (func (export "_start")))')
        for profile in ([], ['--aot-profile', 'minimal']):
            result = self.invoke([FULL_HOST, *profile, '--no-cache', '--compile', path, '/dev/full'])
            self.assertEqual(result.returncode, 1)
            self.assertIn(b'cannot write', result.stderr)
        artifact = self.prepare(path)
        result = self.invoke([AOT_HOST, '--precompiled', artifact, '--timing-json', '/dev/full'])
        self.assertEqual(result.returncode, 1)
        self.assertIn(b'cannot write', result.stderr)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', type=Path, default=FULL_HOST)
    parser.add_argument('--aot-host', type=Path, default=AOT_HOST)
    args, remaining = parser.parse_known_args()
    FULL_HOST = args.host.resolve()
    AOT_HOST = args.aot_host.resolve()
    native.HOST = FULL_HOST
    unittest.main(argv=[sys.argv[0], *remaining])
