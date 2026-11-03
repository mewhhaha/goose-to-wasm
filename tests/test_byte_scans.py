#!/usr/bin/env python3
"""Qualify byte scan masks, private accumulators, scalar tails and trap fallback."""
import argparse
import hashlib
from datetime import datetime, timezone
import json
from pathlib import Path
import struct
import subprocess
import sys
import unittest

import test_merge_bounds as merge
import test_function_value_forwarding as fv
import test_strip_loops as strip
from test_fill_loops import function_body

REFERENCE = None
EVIDENCE = strip.ROOT / 'build/stride-hills/scan-tests'
COUNTS = dict(compiles=0, compile_failures=0, engine_cases=0, oracle_cases=0, body_checks=0)
SOURCE = '''var saved:{kind}[:]; var backing:{kind}[4]=[17,34,51,68];
var final_cur:i64=-777; var final_last:i64=-888; var effects:i64=0;
export fn scan(begin:i64,end:i64,seed:i64)->i64 {{
    let xs=saved; var cur=begin; var count=seed; var last:i64=-99;
    while cur{comparison}end {{ if xs[cur]=={literal} {{ last=cur; count++; }} {update} }}
    final_cur=cur; final_last=last; return count;
}}
export fn cursor()->i64 {{ return final_cur; }}
export fn latest()->i64 {{ return final_last; }}
fn main() {{ saved=backing[..]; }}
'''


def source_for(kind, step=1, comparison='<', literal=None, update=None):
    if literal is None:
        literal = 213
        if kind == 'i8':
            literal = -43
    if update is None:
        update = f'cur+={step};'
    return SOURCE.format(kind=kind, comparison=comparison, literal=literal, update=update)


def case(**changes):
    row = dict(pointer=16384, length=128, begin=0, end=32, seed=7,
               data=[(i * 37 + 17) & 255 for i in range(128)])
    row.update(changes)
    return row


NODE_HOST = r'''
const fs=require('node:fs'),module_=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
const cases=JSON.parse(fs.readFileSync(0,'utf8'));
const results=cases.map(c=>{
  let e;const goose={},aborts=[];for(const item of WebAssembly.Module.imports(module_))goose[item.name]=()=>{};
  goose.abort=(p,n,line)=>aborts.push([Buffer.from(e.memory.buffer).subarray(p>>>0,(p>>>0)+(n>>>0)).toString(),line]);
  e=new WebAssembly.Instance(module_,{goose}).exports;e._start();const image=Buffer.from(e.memory.buffer),size=image.length;
  const backing=image.indexOf(Buffer.from([17,34,51,68]));if(backing<0)throw Error('missing backing');
  const header=Buffer.alloc(8);header.writeUInt32LE(backing);header.writeUInt32LE(4,4);const headers=[];
  for(let p=image.indexOf(header);p>=0;p=image.indexOf(header,p+1))headers.push(p);
  if(!headers.length)throw Error('missing slice header');
  let pointer=c.pointer;if(pointer<0)pointer+=size;
  for(const [at,n]of [[16320,4096],[size-4096,4096]])for(let i=at;i<at+n;i++)image[i]=(i*37+17)&255;
  c.data.forEach((value,i)=>{if(pointer+i>=0&&pointer+i<size)image[pointer+i]=value;});
  for(const at of headers){image.writeUInt32LE(pointer>>>0,at);image.writeUInt32LE(c.length,at+4);}
  const before=[[0,4096],[16320,4096],[size-4096,4096]].map(([at,n])=>[at,Array.from(image.subarray(at,at+n))]);
  let trapped=false,result=null;
  try{result=[String(e.scan(BigInt(c.begin),BigInt(c.end),BigInt(c.seed))),String(e.cursor()),String(e.latest())];}
  catch(error){if(!(error instanceof WebAssembly.RuntimeError))throw error;trapped=true;}
  return {size,pointer,before,trapped,result,aborts};
});process.stdout.write(JSON.stringify(results));
'''


def wasmtime_run(path, cases):
    import wasmtime
    engine = wasmtime.Engine()
    module = wasmtime.Module.from_file(engine, str(path))
    results = []
    for row in cases:
        store = wasmtime.Store(engine)
        linker = wasmtime.Linker(engine)
        aborts = []
        def abort(pointer, length, line):
            aborts.append([bytes(memory.read(store, pointer, pointer + length)).decode(errors='replace'), line])
        for item in module.imports:
            callback = lambda *args: None
            if item.name == 'abort':
                callback = abort
            linker.define_func(item.module, item.name, item.type, callback)
        exports = linker.instantiate(store, module).exports(store)
        memory = exports['memory']
        exports['_start'](store)
        image = bytearray(memory.read(store))
        size = len(image)
        backing = image.index(bytes([17, 34, 51, 68]))
        header = struct.pack('<II', backing, 4)
        headers = []
        at = image.find(header)
        while at >= 0:
            headers.append(at)
            at = image.find(header, at + 1)
        if not headers:
            raise AssertionError('missing slice header')
        pointer = row['pointer']
        if pointer < 0:
            pointer += size
        for at in (16320, size - 4096):
            image[at:at + 4096] = bytes((i * 37 + 17) & 255 for i in range(at, at + 4096))
        for i, value in enumerate(row['data']):
            if 0 <= pointer + i < size:
                image[pointer + i] = value
        for at in headers:
            struct.pack_into('<II', image, at, pointer & 0xffffffff, row['length'])
        memory.write(store, image)
        before = [[at, list(image[at:at + 4096])] for at in (0, 16320, size - 4096)]
        trapped = False
        result = None
        try:
            count = exports['scan'](store, row['begin'], row['end'], row['seed'])
            result = [str(count), str(exports['cursor'](store)), str(exports['latest'](store))]
        except wasmtime.Trap:
            trapped = True
        results.append(dict(size=size, pointer=pointer, before=before, trapped=trapped,
                            result=result, aborts=aborts))
    return results


def signed(value):
    return ((value + (1 << 63)) & ((1 << 64) - 1)) - (1 << 63)


def expected(row, observed, step, literal, inclusive=False, debug=False):
    memory = {at + i: value for at, data in observed['before'] for i, value in enumerate(data)}
    cur, count, last = row['begin'], row['seed'], -99
    end = row['end']
    if inclusive:
        end += 1
    trapped = False
    iterations = 0
    try:
        while cur < end:
            if cur < 0 or cur >= row['length']:
                raise IndexError()
            pointer = (observed['pointer'] + cur) & 0xffffffff
            if pointer >= observed['size']:
                raise IndexError()
            if memory[pointer] == literal & 255:
                last = cur
                if debug and count == (1 << 63) - 1:
                    raise IndexError()
                count = signed(count + 1)
            if debug and cur > (1 << 63) - 1 - step:
                raise IndexError()
            cur = signed(cur + step)
            iterations += 1
            if iterations > 1024:
                raise AssertionError('nonterminating fixture')
    except IndexError:
        trapped = True
    result = None
    if not trapped:
        result = list(map(str, (count, cur, last)))
    return dict(trapped=trapped, result=result)


class ByteScans(unittest.TestCase):
    setUp = strip.StripLoops.setUp
    native = fv.FunctionValueForwarding.native
    run_engines = fv.FunctionValueForwarding.run_engines

    def compile(self, source, level, debug=False, compiler=None):
        COUNTS['compiles'] += 1
        digest = hashlib.sha256(source.encode()).hexdigest()
        EVIDENCE.mkdir(parents=True, exist_ok=True)
        (EVIDENCE / f'{digest}.goose').write_text(source)
        try:
            return merge.MergeBounds.compile(self, source, level, debug, compiler)
        except Exception:
            COUNTS['compile_failures'] += 1
            with (EVIDENCE / 'failed-fixtures.jsonl').open('a') as output:
                output.write(json.dumps(dict(source=digest, level=level, debug=debug, status='compile-failed')) + '\n')
            raise

    def engines(self, path, cases):
        node_cases = []
        for row in cases:
            copy = dict(row)
            for key in ('begin', 'end', 'seed'):
                copy[key] = str(copy[key])
            node_cases.append(copy)
        run = subprocess.run([strip.NODE, '-e', NODE_HOST, str(path)], input=json.dumps(node_cases),
                             capture_output=True, text=True, timeout=90)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        v8 = json.loads(run.stdout)
        COUNTS['engine_cases'] += len(v8)
        wasmtime = wasmtime_run(path, cases)
        COUNTS['engine_cases'] += len(wasmtime)
        return dict(v8=v8, wasmtime=wasmtime)

    def qualify(self, source, rows, step=1, literal=213, inclusive=False,
                level=2, debug=False, optimized=True):
        path, stats = self.compile(source, level, debug)
        outputs = self.engines(path, rows)
        self.assertEqual(outputs['v8'], outputs['wasmtime'])
        for engine, observed in outputs.items():
            for index, (row, actual) in enumerate(zip(rows, observed)):
                oracle = expected(row, actual, step, literal, inclusive, debug)
                self.assertEqual({key: actual[key] for key in ('trapped', 'result')}, oracle,
                                 (engine, index, row))
                COUNTS['oracle_cases'] += 1
        if REFERENCE is not None:
            reference, reference_stats = self.compile(source, level, debug, REFERENCE)
            old = self.engines(reference, rows)
            self.assertEqual(outputs, old)
            body = function_body(path, stats, 'scan')
            reference_body = function_body(reference, reference_stats, 'scan')
            if optimized and not debug:
                self.assertNotEqual(body, reference_body, 'eligible byte scan did not change')
            else:
                self.assertEqual(body, reference_body)
            COUNTS['body_checks'] += 1

    def test_basic_masks_all_byte_inputs_strides_and_wrapping_count(self):
        for kind, literal in (('u8', 213), ('i8', -43)):
            for step in (1, 2, 4, 8):
                rows = [case(data=[value] * 128) for value in range(256)]
                for begin in (0, 1, 3):
                    for lane in range(16):
                        data = [0] * 128
                        data[begin + lane] = literal & 255
                        rows.append(case(begin=begin, end=begin + 16, data=data))
                rows.extend([case(data=[literal & 255] * 128, seed=(1 << 63) - 3),
                             case(begin=3, end=40, data=[literal & 255] * 128),
                             case(end=0, seed=-(1 << 63))])
                with self.subTest(kind=kind, step=step):
                    self.qualify(source_for(kind, step), rows, step, literal)

    def test_boundaries_invalid_views_and_debug_scalar_fallback(self):
        for kind, step in (('u8', 1), ('u8', 8), ('i8', 2), ('i8', 4)):
            literal = 213
            if kind == 'i8':
                literal = -43
            for comparison in ('<', '<='):
                inclusive = comparison == '<='
                rows = []
                for begin in (0, 1, 3, 15, 16, 17):
                    for span in (0, 1, 7, 8, 15, 16, 17, 31, 32, 33):
                        end = begin + span
                        if inclusive:
                            end -= 1
                        rows.append(case(begin=begin, end=end, data=[literal & 255] * 128))
                rows.extend([
                    case(length=0), case(length=1), case(length=15), case(length=31),
                    case(begin=-1), case(begin=128), case(end=(1 << 63) - 1),
                    case(begin=0, end=-1), case(begin=-2, end=-3),
                    case(begin=1, end=0, pointer=0xffffffff, length=0),
                    case(pointer=-8), case(pointer=-16), case(pointer=-17),
                    case(pointer=-8, end=8, length=8),
                    case(pointer=-9, end=8, length=9),
                    case(pointer=0xfffffff8), case(pointer=0xffffffff),
                    case(pointer=0xffffffff, begin=1, end=2, length=16),
                    case(begin=1 << 30, end=(1 << 30) + 1, length=0xffffffff),
                    case(begin=(1 << 63) - 1, end=(1 << 63) - 1, length=0xffffffff),
                    case(seed=(1 << 63) - 1, data=[literal & 255] * 128),
                    case(pointer=16385, begin=3, end=40, data=[literal & 255] * 128),
                ])
                for level in (0, 2):
                    for debug in (False, True):
                        with self.subTest(kind=kind, step=step, comparison=comparison,
                                          level=level, debug=debug):
                            self.qualify(source_for(kind, step, comparison), rows, step, literal,
                                         inclusive, level, debug)

    def test_equality_literals_and_increment_syntax(self):
        for kind in ('u8', 'i8'):
            for bits in (0, 1, 127, 128, 255):
                literal = bits
                if kind == 'i8' and bits >= 128:
                    literal -= 256
                rows = [case(data=[value] * 128) for value in (0, 1, 127, 128, 213, 255)]
                rows.append(case(begin=3, end=35, data=[bits] * 128))
                self.qualify(source_for(kind, literal=literal, update='cur++;'), rows,
                             literal=literal)

    def test_literal_and_slice_length_endpoints(self):
        for bound in ('16', 'xs.len'):
            for step in (1, 2, 4, 8):
                rows = [case(length=16, end=16), case(length=16, end=16, begin=16),
                        case(length=16, end=16, begin=3, data=[213] * 128),
                        case(length=16, end=16, pointer=-8),
                        case(length=16, end=16, pointer=0xffffffff, begin=1)]
                source = source_for('u8', step).replace('cur<end', 'cur<' + bound)
                self.qualify(source, rows, step)

    def test_scalar_rejections_keep_identical_function_bodies(self):
        source = source_for('u8')
        variants = {
            'extra-effect': source.replace('cur+=1;', 'effects++; cur+=1;'),
            'call': 'recursive fn side() { effects++; }\n' + source.replace('cur+=1;', 'side(); cur+=1;'),
            'extra-read': source.replace('last=cur; count++;', 'last=cur; count++; effects+=(xs[cur] as i64);'),
            'last-count-alias': source.replace('last=cur;', 'count=cur;'),
            'cursor-count-alias': source.replace('count++;', 'cur++;'),
            'cursor-last-alias': source.replace('last=cur;', 'cur=cur;'),
            'count-bound': source.replace('cur<end', 'cur<count'),
            'last-bound': source.replace('cur<end', 'cur<last'),
            'cursor-bound': source.replace('cur<end', 'cur<cur'),
            'unsupported-step': source.replace('cur+=1;', 'cur+=3;'),
            'non-byte': source.replace('u8', 'u16'),
            'widened-predicate': source.replace('xs[cur]==213', '(xs[cur] as i64)==213'),
            'reversed-predicate': source.replace('xs[cur]==213', '213==xs[cur]'),
        }
        for name in ('cur', 'count', 'last', 'end'):
            variants['address-' + name] = 'recursive fn expose(value:i64&)->i64 { value }\n' + source.replace(
                'while cur<end', 'let observed=expose(' + name + '); while cur<end')
            variants['capture-' + name] = source.replace('while cur<end',
                'recursive fn observe()->i64 { ' + name + ' } let observed=observe(); while cur<end')
        variants['address-view'] = 'recursive fn expose(value:u8[:]&)->i64 { value.len }\n' + source.replace(
            'while cur<end', 'let observed=expose(xs); while cur<end')
        variants['capture-view'] = source.replace('while cur<end',
            'recursive fn observe()->i64 { xs.len } let observed=observe(); while cur<end')
        for label, variant in variants.items():
            for level in (0, 2):
                with self.subTest(variant=label, level=level):
                    path, stats = self.compile(variant, level)
                    if REFERENCE is None:
                        continue
                    reference, reference_stats = self.compile(variant, level, compiler=REFERENCE)
                    self.assertEqual(function_body(path, stats, 'scan'),
                                     function_body(reference, reference_stats, 'scan'))
                    COUNTS['body_checks'] += 1
                    if label == 'non-byte':
                        continue
                    rows = [case(end=32, seed=64, data=[213] * 128),
                            case(length=3, end=32), case(begin=1, end=0)]
                    self.assertEqual(self.engines(path, rows), self.engines(reference, rows))

    def test_fixed_storage_and_owner_rejection_with_native_oracle(self):
        for kind, literal in (('u8', 213), ('i8', -43)):
            for storage in ('frame', 'global', 'owner-frame', 'owner-global'):
                declaration = f'var xs:{kind}[64]=[{literal};64];'
                if storage.startswith('owner'):
                    declaration = f'var xs:{kind}[>..]=[{literal};64];'
                global_declaration = ''
                local_declaration = declaration
                if storage.endswith('global'):
                    global_declaration = declaration
                    local_declaration = ''
                source = global_declaration + '''
export fn scan(begin:i64,end:i64,seed:i64)->i64 {{
    {declaration} var cur=begin; var count=seed; var last:i64=-99;
    while cur<end {{ if xs[cur]=={literal} {{ last=cur; count++; }} cur+=4; }}
    return count+cur+last;
}}
fn main() {{ print(scan(1,64,7)); print(scan(64,64,7)); print(scan(3,18,7)); }}
'''.format(declaration=local_declaration, literal=literal)
                for level in (0, 2):
                    with self.subTest(kind=kind, storage=storage, level=level):
                        path, stats = self.compile(source, level)
                        oracle = self.native(source, level, False)
                        self.assertEqual(oracle, '149\n-28\n45\n')
                        for engine, output in self.run_engines(path):
                            self.assertEqual(output, oracle, engine)
                            COUNTS['engine_cases'] += 1
                            COUNTS['oracle_cases'] += 1
                        if REFERENCE is not None:
                            reference, reference_stats = self.compile(source, level, compiler=REFERENCE)
                            body = function_body(path, stats, 'scan')
                            old_body = function_body(reference, reference_stats, 'scan')
                            if storage.startswith('owner'):
                                self.assertEqual(body, old_body)
                            else:
                                self.assertNotEqual(body, old_body)
                            COUNTS['body_checks'] += 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--goose', type=Path, default=strip.GOOSE)
    parser.add_argument('--reference-compiler', type=Path)
    parser.add_argument('--node', default=strip.NODE)
    parser.add_argument('--evidence', type=Path, default=EVIDENCE)
    args, remaining = parser.parse_known_args()
    strip.GOOSE = args.goose.resolve()
    strip.NODE = args.node
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
    EVIDENCE = args.evidence.resolve() / stamp
    if args.reference_compiler:
        REFERENCE = args.reference_compiler.resolve()
    program = unittest.main(argv=[sys.argv[0], *remaining], exit=False)
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    identities = {}
    for label, compiler in (('candidate', strip.GOOSE), ('reference', REFERENCE)):
        if compiler is not None:
            identities[label] = dict(path=str(compiler), sha256=hashlib.sha256(compiler.read_bytes()).hexdigest())
    status = 'failed'
    if program.result.wasSuccessful():
        status = 'passed'
    (EVIDENCE / 'result.json').write_text(json.dumps(dict(
        status=status,
        counts=COUNTS, tests_run=program.result.testsRun, failures=len(program.result.failures),
        errors=len(program.result.errors), identities=identities,
        source_hashes=sorted(path.stem for path in EVIDENCE.glob('*.goose')),
        harness_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()), indent=2) + '\n')
    sys.exit(not program.result.wasSuccessful())
