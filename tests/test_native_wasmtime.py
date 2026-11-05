#!/usr/bin/env python3
"""Exercise the native host's public ABI and failure boundaries using small Wasm modules."""
import argparse
import json
from pathlib import Path
import random
import struct
import subprocess
import sys
import tempfile
import unittest

import wasmtime

ROOT=Path(__file__).resolve().parents[1]
HOST=ROOT/'build/bin/goose-wasmtime'
PRECOMPILED_HOST=None
MINIMAL_HOST=None


class NativeHost(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(dir=ROOT/'build')
        self.addCleanup(self.tmp.cleanup)
        self.directory=Path(self.tmp.name)
        self.count=0

    def module(self,wat):
        self.count+=1
        path=self.directory/f'case{self.count}.wasm'
        path.write_bytes(wasmtime.wat2wasm(wat))
        return path

    def execute(self,command,data=b''):
        if Path(command[0]).resolve() == HOST:
            command = [command[0], '--no-cache', *command[1:]]
        return subprocess.run(list(map(str,command)),input=data,capture_output=True,timeout=30)

    def compare(self,path,data=b'',diagnostic=None):
        reference=self.execute([sys.executable,ROOT/'scripts/run_wasmtime.py',path],data)
        compiled=path.with_suffix('.cwasm')
        prep=self.execute([HOST,'--no-parallel-compilation','--compile',path,compiled])
        self.assertEqual(prep.returncode,0,prep.stderr)
        modes=[[HOST,path],[HOST,'--no-parallel-compilation',path],[HOST,'--precompiled',compiled],
               [HOST,'--no-parallel-compilation','--precompiled',compiled]]
        if PRECOMPILED_HOST is not None:
            modes += [[PRECOMPILED_HOST,'--precompiled',compiled],
                      [PRECOMPILED_HOST,'--no-parallel-compilation','--precompiled',compiled]]
        if MINIMAL_HOST is not None:
            minimal=self.prepare_minimal(path)
            modes += [[HOST,'--aot-profile','minimal','--precompiled',minimal],
                      [MINIMAL_HOST,'--precompiled',minimal]]
        for command in modes:
            with self.subTest(command=command):
                actual=self.execute(command,data)
                self.assertEqual(actual.returncode,reference.returncode,actual.stderr)
                self.assertEqual(actual.stdout,reference.stdout)
                if diagnostic is not None:
                    self.assertIn(diagnostic,actual.stderr)
                elif reference.returncode==0 or b'goose runtime error:' in reference.stderr:
                    self.assertEqual(actual.stderr,reference.stderr)
        return reference

    def prepare_minimal(self,path):
        compiled=path.with_suffix('.minimal.cwasm')
        prep=self.execute([HOST,'--aot-profile','minimal','--no-parallel-compilation','--compile',path,compiled])
        self.assertEqual(prep.returncode,0,prep.stderr)
        return compiled

    def import_failure(self,path,diagnostic):
        modes=[[HOST,path]]
        if MINIMAL_HOST is not None:
            compiled=self.prepare_minimal(path)
            modes += [[HOST,'--aot-profile','minimal','--precompiled',compiled],
                      [MINIMAL_HOST,'--precompiled',compiled]]
        for command in modes:
            with self.subTest(command=command):
                actual=self.execute(command)
                self.assertEqual(actual.returncode,1)
                self.assertIn(diagnostic,actual.stderr)

    def test_float_spelling_and_integer_extremes(self):
        rng=random.Random(717732)
        f64=[0,1,0x8000000000000000,0x7ff0000000000000,0xfff0000000000000,
             0x7ff8000000000001,0x7fefffffffffffff,0x0010000000000000]
        f32=[0,1,0x80000000,0x7f800000,0xff800000,0x7fc00001,0x7f7fffff,0x00800000]
        f64 += [int.from_bytes(struct.pack('<d',v),'little')for v in [1e-5,1e-4,1e14,1e15,1e16,1.25,-1.25]]
        f64 += [rng.getrandbits(64)for _ in range(128)]
        f32 += [rng.getrandbits(32)for _ in range(128)]
        statements=[]
        for bits,width in [(v,64)for v in f64]+[(v,32)for v in f32]:
            signed=bits
            if signed >= 1<<(width-1):signed-=1<<width
            statements.append(f'(call $f{width} (f{width}.reinterpret_i{width} (i{width}.const {signed}))) (call $newline)')
        body='\n'.join(statements)
        path=self.module('''(module
          (import "goose" "print_f64" (func $f64 (param f64)))
          (import "goose" "print_f32" (func $f32 (param f32)))
          (import "goose" "print_i64" (func $signed (param i64)))
          (import "goose" "print_u64" (func $unsigned (param i64)))
          (import "goose" "newline" (func $newline))
          (func (export "_start") '''+body+'''
            (call $signed (i64.const -9223372036854775808)) (call $newline)
            (call $unsigned (i64.const -1)) (call $newline)))''')
        reference=self.compare(path)
        self.assertTrue(reference.stdout.endswith(b'-9223372036854775808\n18446744073709551615\n'))

    def test_float_format_buffers_preserve_width_and_sentinels(self):
        rng = random.Random(99413)
        statements = []
        for width, samples in ((64, [0, 1, 0x8000000000000000, 0x7ff0000000000000,
                                     0xfff0000000000000, 0x7ff8000000000001, 0x7fefffffffffffff]),
                               (32, [0, 1, 0x80000000, 0x7f800000, 0xff800000,
                                     0x7fc00001, 0x7f7fffff, 0x3dcccccd])):
            samples += [rng.getrandbits(width) for _ in range(16)]
            for bits in samples:
                if bits >= 1 << (width - 1):
                    bits -= 1 << width
                value = f'(f{width}.reinterpret_i{width} (i{width}.const {bits}))'
                statements.append(f'''
                  (memory.fill (i32.const 65504) (i32.const 35) (i32.const 32))
                  (local.set $n (call $format{width} (i32.const 65504) {value}))
                  (call $write (i32.const 65503) (i32.const 1))
                  (call $write (i32.const 65504) (local.get $n))
                  (call $write (i32.add (i32.const 65504) (local.get $n)) (i32.const 1))
                  (call $print{width} {value}) (call $newline)''')
        path = self.module('''(module
          (import "goose" "format_f64" (func $format64 (param i32 f64) (result i32)))
          (import "goose" "format_f32" (func $format32 (param i32 f32) (result i32)))
          (import "goose" "print_f64" (func $print64 (param f64)))
          (import "goose" "print_f32" (func $print32 (param f32)))
          (import "goose" "write" (func $write (param i32 i32)))
          (import "goose" "newline" (func $newline))
          (memory (export "memory") 1) (data (i32.const 65503) "~")
          (func (export "_start") (local $n i32) ''' + '\n'.join(statements) + '))')
        result = self.compare(path)
        self.assertEqual(result.returncode, 0, result.stderr)
        for line in result.stdout.splitlines():
            self.assertTrue(line.startswith(b'~'))
            formatted, printed = line[1:].split(b'#')
            self.assertEqual(formatted, printed)
        self.assertIn(b'~0.1#0.1\n', result.stdout)
        node = self.execute(['node', ROOT / 'scripts/run_wasm.mjs', path])
        self.assertEqual((node.returncode, node.stdout, node.stderr), (0, result.stdout, b''))

    def test_float_format_checks_the_full_buffer_range(self):
        for width in (32, 64):
            for pointer in (65505, -1):
                path = self.module(f'''(module
                  (import "goose" "format_f{width}" (func $format (param i32 f{width}) (result i32)))
                  (memory (export "memory") 1)
                  (func (export "_start") (drop (call $format (i32.const {pointer}) (f{width}.const 0)))))''')
                result = self.compare(path, diagnostic=b'outside exported memory')
                self.assertEqual(result.returncode, 1)
                node = self.execute(['node', ROOT / 'scripts/run_wasm.mjs', path])
                self.assertEqual(node.returncode, 1)
                self.assertIn(b'outside exported memory', node.stderr)

    def test_stdout_bytes_and_output_before_abort_or_exit(self):
        for finish in ['(call $exit (i32.const 7))','(call $abort (i32.const 0) (i32.const 5) (i32.const 42))']:
            path=self.module('''(module
              (import "goose" "write" (func $write (param i32 i32)))
              (import "goose" "exit" (func $exit (param i32)))
              (import "goose" "abort" (func $abort (param i32 i32 i32)))
              (memory (export "memory") 1) (data (i32.const 0) "A\\00B\\ffC")
              (func (export "_start") (call $write (i32.const 0) (i32.const 5)) '''+finish+'))')
            reference=self.compare(path)
            self.assertEqual(reference.stdout,b'A\0B\xffC')

    def test_checked_goose_ranges_and_empty_memory(self):
        for pointer,length in [(65536,0),(65537,0),(-1,0),(0,-1),(65535,2)]:
            path=self.module(f'''(module
              (import "goose" "write" (func $write (param i32 i32)))
              (memory (export "memory") 1)
              (func (export "_start") (call $write (i32.const {pointer}) (i32.const {length}))))''')
            diagnostic=None
            if pointer<0 or length<0:diagnostic=b'negative host address'
            elif pointer>65536 or pointer+length>65536:diagnostic=b'outside exported memory'
            self.compare(path,diagnostic=diagnostic)
        self.compare(self.module('''(module
          (import "goose" "write" (func $write (param i32 i32)))
          (memory (export "memory") 0)
          (func (export "_start") (call $write (i32.const 0) (i32.const 0))))'''))

    def test_duplicate_imports_and_invalid_signatures(self):
        path=self.module('''(module
          (import "goose" "print_i64" (func $a (param i64)))
          (import "goose" "print_i64" (func $b (param i64)))
          (func (export "_start") (call $a (i64.const 12)) (call $b (i64.const 34))))''')
        self.assertEqual(self.compare(path).stdout,b'1234')
        path=self.module('''(module
          (import "env" "emscripten_notify_memory_growth" (func (param i32)))
          (import "env" "emscripten_notify_memory_growth" (func (param i64)))
          (func (export "_start")))''')
        self.import_failure(path,b'invalid direct host import signature: env.emscripten_notify_memory_growth')
        for imports in ['(import "goose" "print_i64" (func (param f64)))',
                        '(import "env" "bench_input" (func (result i32)))',
                        '(import "goose" "unknown" (func))',
                        '(import "goose" "write" (memory 1))']:
            path=self.module('(module '+imports+' (func (export "_start")))')
            self.import_failure(path,b'host import')

    def test_interleaved_duplicate_imports_preserve_order(self):
        path=self.module('''(module
          (import "goose" "print_i64" (func $a (param i64)))
          (import "goose" "newline" (func $newline))
          (import "goose" "print_i64" (func $b (param i64)))
          (import "env" "bench_input" (func $input (result i64)))
          (import "goose" "newline" (func $newline2))
          (func $init (call $b (call $input)) (call $newline2)) (start $init)
          (func (export "_start") (call $a (call $input)) (call $newline)))''')
        self.assertEqual(self.compare(path,b'12 34').stdout,b'12\n34\n')

    def test_start_function_exit_abort_and_traps(self):
        cases=[('(call $exit (i32.const 7))',None),
               ('(call $abort (i32.const 0) (i32.const 5) (i32.const 42))',b'goose runtime error: ready (line 42)'),
               ('unreachable',b'unreachable'),
               ('(call $write (i32.const 65535) (i32.const 2))',b'outside exported memory')]
        for finish,diagnostic in cases:
            path=self.module('''(module
              (import "goose" "write" (func $write (param i32 i32)))
              (import "goose" "exit" (func $exit (param i32)))
              (import "goose" "abort" (func $abort (param i32 i32 i32)))
              (memory (export "memory") 1) (data (i32.const 0) "ready")
              (func $init (call $write (i32.const 0) (i32.const 5)) '''+finish+''') (start $init)
              (func (export "_start") (call $write (i32.const 0) (i32.const 5))))''')
            self.assertEqual(self.compare(path,diagnostic=diagnostic).stdout,b'ready')
        path=self.module('''(module
          (import "goose" "write" (func $write (param i32 i32)))
          (func $init (call $write (i32.const 0) (i32.const 0))) (start $init)
          (func (export "_start")))''')
        self.compare(path,diagnostic=b'module does not export memory')

    def test_imports_during_instantiation_and_memory_growth(self):
        path=self.module('''(module
          (import "goose" "write" (func $write (param i32 i32)))
          (memory (export "memory") 1 2) (data (i32.const 0) "before")
          (func $init (call $write (i32.const 0) (i32.const 6))) (start $init)
          (func (export "_start")
            (drop (memory.grow (i32.const 1)))
            (i32.store (i32.const 65536) (i32.const 1919251553))
            (call $write (i32.const 65536) (i32.const 4))))''')
        self.assertEqual(self.compare(path).stdout,b'beforeater')

    def test_iovec_output_before_invalid_later_range(self):
        path=self.module('''(module
          (import "wasi_snapshot_preview1" "fd_write" (func $write (param i32 i64 i64 i64) (result i32)))
          (memory (export "memory") i64 1) (data (i64.const 100) "kept")
          (func (export "_start")
            (i64.store (i64.const 0) (i64.const 100)) (i64.store (i64.const 8) (i64.const 4))
            (i64.store (i64.const 16) (i64.const 65535)) (i64.store (i64.const 24) (i64.const 2))
            (drop (call $write (i32.const 1) (i64.const 0) (i64.const 2) (i64.const 64)))))''')
        self.assertEqual(self.compare(path,diagnostic=b'outside exported memory').stdout,b'kept')

    def test_memory_growth_notifications_in_both_memory_models(self):
        for kind in ['i32','i64']:
            path=self.module(f'''(module
              (import "env" "emscripten_notify_memory_growth" (func $growth (param {kind})))
              (func (export "_start") (call $growth ({kind}.const 0))))''')
            self.compare(path)
        path=self.module('''(module
          (import "env" "emscripten_notify_memory_growth" (func $growth (param f64)))
          (func (export "_start") (call $growth (f64.const 0))))''')
        self.import_failure(path,b'invalid direct host import signature: env.emscripten_notify_memory_growth')

    def test_numeric_input_validation(self):
        path=self.module('''(module
          (import "env" "bench_input" (func $input (result i64)))
          (import "goose" "print_i64" (func $print (param i64)))
          (func (export "_start") (call $print (call $input))))''')
        for data in [b'+123',b'-9223372036854775808',b'1_234',b'+-1',b'9223372036854775808',b'']:
            self.compare(path,data)
        path=self.module('''(module
          (import "env" "bench_input_f64" (func $input (result f64)))
          (import "goose" "print_f64" (func $print (param f64)))
          (func (export "_start") (call $print (call $input))))''')
        for data in [b'1_234.5',b'+inf',b'-nan',b'1e999',b'0x1p0',b'nan(payload)']:
            self.compare(path,data)

    def test_memory64_iovecs_and_utf8_stderr(self):
        path=self.module('''(module
          (import "wasi_snapshot_preview1" "fd_write" (func $write (param i32 i64 i64 i64) (result i32)))
          (memory (export "memory") i64 1)
          (data (i64.const 100) "A\\ff\\00B")
          (func (export "_start")
            (i64.store (i64.const 0) (i64.const 100)) (i64.store (i64.const 8) (i64.const 4))
            (drop (call $write (i32.const 1) (i64.const 0) (i64.const 1) (i64.const 64)))
            (drop (call $write (i32.const 2) (i64.const 0) (i64.const 1) (i64.const 64)))))''')
        reference=self.compare(path)
        self.assertEqual(reference.stdout,b'A\xff\0B')
        self.assertEqual(reference.stderr,b'A\xef\xbf\xbd\0B\n')
        for pointer,count in [(0,-1),(65536,1),(65520,2)]:
            path=self.module(f'''(module
              (import "wasi_snapshot_preview1" "fd_write" (func $write (param i32 i64 i64 i64) (result i32)))
              (memory (export "memory") i64 1)
              (func (export "_start")
                (drop (call $write (i32.const 1) (i64.const {pointer}) (i64.const {count}) (i64.const 64)))))''')
            self.compare(path,diagnostic=b'host')

    def test_iovec_snapshot_before_aliasing_input_writes(self):
        path=self.module('''(module
          (import "wasi_snapshot_preview1" "fd_read" (func $read (param i32 i64 i64 i64) (result i32)))
          (import "wasi_snapshot_preview1" "fd_write" (func $write (param i32 i64 i64 i64) (result i32)))
          (memory (export "memory") i64 1)
          (func (export "_start")
            (i64.store (i64.const 0) (i64.const 16)) (i64.store (i64.const 8) (i64.const 16))
            (i64.store (i64.const 16) (i64.const 100)) (i64.store (i64.const 24) (i64.const 3))
            (drop (call $read (i32.const 0) (i64.const 0) (i64.const 2) (i64.const 64)))
            (i64.store (i64.const 0) (i64.const 100)) (i64.store (i64.const 8) (i64.const 3))
            (drop (call $write (i32.const 1) (i64.const 0) (i64.const 1) (i64.const 64)))))''')
        self.assertEqual(self.compare(path,b'abcdefghijklmnopXYZ').stdout,b'XYZ')

    def test_emscripten_stack_initialization(self):
        path=self.module('''(module
          (global $ready (mut i32) (i32.const 0))
          (func (export "emscripten_stack_init") (global.set $ready (i32.const 1)))
          (func (export "emscripten_stack_get_base") (result i64) (i64.const 99))
          (func (export "emscripten_stack_get_end") (result i64) (i64.const 22))
          (func (export "__set_stack_limits") (param i64 i64)
            (if (i32.eqz (global.get $ready)) (then unreachable))
            (if (i64.ne (local.get 0) (i64.const 99)) (then unreachable))
            (if (i64.ne (local.get 1) (i64.const 22)) (then unreachable))
            (global.set $ready (i32.const 2)))
          (func (export "_start")
            (if (i32.ne (global.get $ready) (i32.const 2)) (then unreachable))))''')
        self.compare(path)

    def test_timing_boundaries_and_explicit_precompiled_mode(self):
        path=self.module('(module (func (export "_start")))');timing=self.directory/'timing.json'
        actual=self.execute([HOST,path,'--timing-json',timing]);self.assertEqual(actual.returncode,0,actual.stderr)
        d=json.loads(timing.read_text())
        self.assertEqual(d['compile_instantiate_ns']+d['start_function_ns'],d['engine_total_ns'])
        self.assertTrue(all(type(d[k])is int and d[k]>=0 for k in ['compile_instantiate_ns','start_function_ns','engine_total_ns']))
        artifact=path.with_suffix('.cwasm')
        self.assertEqual(self.execute([HOST,'--compile',path,artifact]).returncode,0)
        self.assertEqual(self.execute([HOST,artifact]).returncode,1)
        self.assertEqual(self.execute([HOST,'--precompiled',artifact]).returncode,0)
        self.assertEqual(self.execute([HOST,'--compile',path,artifact,'--timing-json',timing]).returncode,1)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--host',type=Path,default=HOST)
    parser.add_argument('--precompiled-host',type=Path)
    parser.add_argument('--minimal-host',type=Path,help='also exercise a minimal-profile AOT companion')
    args,remaining=parser.parse_known_args();HOST=args.host.resolve()
    if args.precompiled_host is not None:PRECOMPILED_HOST=args.precompiled_host.resolve()
    if args.minimal_host is not None:MINIMAL_HOST=args.minimal_host.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
