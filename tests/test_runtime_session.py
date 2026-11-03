#!/usr/bin/env python3
"""Qualify cached launches and isolated runs on a reused native engine."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

import wasmtime

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
from wasmtime_session import RuntimeSession

HOST = ROOT/'build/bin/goose-wasmtime'
ECHO = '''(module
  (import "env" "bench_input" (func $input (result i64)))
  (import "goose" "print_i64" (func $print (param i64)))
  (global $counter (mut i64) (i64.const 0))
  (memory (export "memory") 1)
  (func (export "_start")
    (global.set $counter (i64.add (global.get $counter) (i64.const 1)))
    (call $print (i64.add (i64.mul (global.get $counter) (i64.const 1000)) (call $input)))))'''


class RuntimeReuse(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT/'build')
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)

    def module(self, name, wat):
        path = self.directory/(name+'.wasm')
        path.write_bytes(wasmtime.wat2wasm(wat))
        return path

    def launch(self, module, *flags, stdin=b''):
        options = list(map(str, flags))
        if '--cache-config' not in options and '--cache' not in options:
            options.insert(0, '--no-cache')
        return subprocess.run([str(HOST), *options, str(module)], input=stdin,
                              capture_output=True, timeout=30)

    def test_fresh_state_and_input_on_every_request_including_concurrent_clients(self):
        module = self.module('echo', ECHO)
        with RuntimeSession(HOST) as session:
            for i in (1, 9, 23):
                result = session.run(module, str(i))
                self.assertEqual((result.returncode, result.stdout, result.stderr),
                                 (0, str(1000+i).encode(), b''))
                self.assertEqual(result.module_cache_hit, i != 1)
                self.assertGreater(result.prepare_ns, 0)
                self.assertGreater(result.start_ns, 0)
            with ThreadPoolExecutor(max_workers=4) as pool:
                results = list(pool.map(lambda n: session.run(module, str(n)), range(20)))
            self.assertEqual([r.stdout for r in results], [str(1000+n).encode() for n in range(20)])
            self.assertTrue(all(r.module_cache_hit and r.returncode == 0 and not r.stderr for r in results))

    def test_byte_identity_invalidates_same_mtime_and_shares_identical_paths(self):
        def wat(value):
            return f'''(module (import "goose" "print_i64" (func $p (param i64)))
              (func (export "_start") (call $p (i64.const {value}))))'''
        module = self.module('value', wat(1)); stamp = module.stat()
        duplicate = self.directory/'duplicate.wasm'; duplicate.write_bytes(module.read_bytes())
        with RuntimeSession(HOST) as session:
            self.assertFalse(session.run(module).module_cache_hit)
            self.assertTrue(session.run(duplicate).module_cache_hit)
            module.write_bytes(wasmtime.wat2wasm(wat(2)))
            os.utime(module, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
            changed = session.run(module)
            self.assertFalse(changed.module_cache_hit)
            self.assertEqual(changed.stdout, b'2')
            restored = session.run(duplicate)
            self.assertTrue(restored.module_cache_hit)
            self.assertEqual(restored.stdout, b'1')

    def test_lru_evicts_old_modules(self):
        modules = [self.module(str(i), f'(module (func (export "_start") (drop (i32.const {i}))))')
                   for i in range(9)]
        with RuntimeSession(HOST) as session:
            for module in modules:
                self.assertFalse(session.run(module).module_cache_hit)
            self.assertTrue(session.run(modules[-1]).module_cache_hit)
            self.assertFalse(session.run(modules[0]).module_cache_hit)
            self.assertTrue(session.run(modules[-1]).module_cache_hit)

    def test_errors_exits_and_binary_output_remain_request_local(self):
        good = self.module('good', ECHO)
        bad = self.module('bad', '(module (import "goose" "unknown" (func)) (func (export "_start")))')
        partial = self.module('partial', '''(module
          (import "goose" "write" (func $write (param i32 i32)))
          (import "goose" "exit" (func $exit (param i32)))
          (memory (export "memory") 1) (data (i32.const 0) "A\\00B\\ffC")
          (func (export "_start") (call $write (i32.const 0) (i32.const 5)) (call $exit (i32.const 257))))''')
        trap = self.module('trap', '(module (func (export "_start") unreachable))')
        with RuntimeSession(HOST) as session:
            for _ in range(2):
                result = session.run(bad)
                self.assertEqual(result.returncode, 1)
                self.assertIn(b'host import', result.stderr)
                self.assertEqual(result.stdout, b'')
                for path in (partial, trap):
                    ordinary = self.launch(path); reused = session.run(path)
                    self.assertEqual((reused.returncode, reused.stdout), (ordinary.returncode, ordinary.stdout))
                    if path == partial:
                        self.assertEqual(reused.stderr, ordinary.stderr)
                        self.assertEqual(reused.stdout, b'A\0B\xffC')
                    else:
                        self.assertIn(b'unreachable', reused.stderr)
                missing = session.run(self.directory/'missing.wasm')
                self.assertEqual(missing.returncode, 1)
                self.assertIn(b'cannot open', missing.stderr)
                recovered = session.run(good, '7')
                self.assertEqual((recovered.returncode, recovered.stdout, recovered.stderr), (0, b'1007', b''))

    def test_disk_cache_and_configuration_keep_results_coherent(self):
        cache = self.directory/'cache'; config = self.directory/'cache.toml'
        config.write_text('[cache]\ndirectory = '+json.dumps(str(cache))+'\n')
        module = self.module('disk', ECHO)
        for i in (1, 2, 3):
            result = self.launch(module, '--cache-config', config, stdin=str(i).encode())
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, str(1000+i).encode(), b''))
        entries = [p for p in cache.rglob('*') if p.is_file() and 'modules' in p.parts]
        self.assertTrue(entries, 'Wasmtime did not populate its configured compilation cache')
        for path in entries:
            path.write_bytes(b'corrupt cache entry')
        result = self.launch(module, '--cache-config', config, stdin=b'4')
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, b'1004', b''))
        stamp = module.stat()
        module.write_bytes(wasmtime.wat2wasm(ECHO.replace('1000', '2000')))
        os.utime(module, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
        changed = self.launch(module, '--cache-config', config, '--no-parallel-compilation', stdin=b'6')
        self.assertEqual((changed.returncode, changed.stdout, changed.stderr), (0, b'2006', b''))
        config.write_text('invalid TOML [')
        invalid = self.launch(module, '--cache-config', config)
        self.assertEqual(invalid.returncode, 1)
        uncached = self.launch(module, '--cache-config', config, '--no-cache', stdin=b'5')
        self.assertEqual((uncached.returncode, uncached.stdout, uncached.stderr), (0, b'2005', b''))

    def test_normal_launch_uses_cache_and_unavailable_default_falls_back(self):
        module = self.module('default', ECHO)
        env = os.environ.copy()
        env['XDG_CACHE_HOME'] = str(self.directory/'xdg-cache')
        env['XDG_CONFIG_HOME'] = str(self.directory/'xdg-config')
        timing = self.directory/'default.json'
        result = subprocess.run([str(HOST), str(module), '--timing-json', str(timing)],
                                input=b'8', capture_output=True, env=env, timeout=30)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, b'1008', b''))
        self.assertTrue(json.loads(timing.read_bytes())['compilation_cache_enabled'])
        (self.directory/'xdg-blocked').write_text('not a directory')
        env['XDG_CACHE_HOME'] = str(self.directory/'xdg-blocked'/'nested')
        result = subprocess.run([str(HOST), str(module), '--timing-json', str(timing)],
                                input=b'9', capture_output=True, env=env, timeout=30)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, b'1009', b''))
        self.assertFalse(json.loads(timing.read_bytes())['compilation_cache_enabled'])

    def test_worker_death_makes_the_client_terminal_and_reaps_it(self):
        module = self.module('echo', ECHO)
        session = RuntimeSession(HOST)
        session._process.kill()
        session._process.wait(timeout=5)
        with self.assertRaises((BrokenPipeError, RuntimeError)):
            session.run(module, b'123')
        self.assertIsNotNone(session._process.poll())
        self.assertTrue(session._process.stdout.closed)
        self.assertTrue(session._diagnostics.closed)
        with self.assertRaisesRegex(RuntimeError, 'closed'):
            session.run(module, b'1')
        session.close()

    def test_truncated_protocol_exits_instead_of_hanging(self):
        process = subprocess.run([str(HOST), '--serve'], input=struct.pack('<II', 4, 9)+b'file'+b'xx',
                                 capture_output=True, timeout=10)
        self.assertEqual(process.returncode, 1)
        self.assertEqual(process.stdout, b'GWRT\1\0\0\0')
        self.assertIn(b'truncated runtime request payload', process.stderr)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--host', type=Path, default=HOST)
    args, remaining = parser.parse_known_args(); HOST = args.host.resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
