#!/usr/bin/env python3
"""Qualify grouped stores against ordered scalar writes and cursor updates."""
import argparse
import json
from pathlib import Path
import struct
import subprocess
import sys
import unittest

import test_function_value_forwarding as fv
import test_merge_bounds as merge
import test_strip_loops as strip
from test_fill_loops import function_body
from test_memory_growth_helper import expose_attempt
from test_static_data import sections

REFERENCE = None
LITERALS = {'i8': -43, 'u8': 213, 'i16': -23131, 'u16': 42480,
            'i32': -1515870811, 'u32': 4045620583,
            'i64': -6510615555426900571, 'u64': 17375808098319191535}
SOURCE = '''var saved:{kind}[:]; var backing:{kind}[4]=[17,34,51,68];
var effects:i64=0;
export fn paint(begin:i64,end:i64,stride:i64)->i64 {{
    let xs=saved; var cur=begin; var stop=end; var jump=stride;
    while cur{comparison}stop {{ xs[cur]={literal}; {update} }}
    return cur;
}}
fn main() {{ saved=backing[..]; print(paint(1,4,2)); backing=[17,34,51,68]; }}
'''


def source_for(kind, comparison='<', update='cur+=jump;'):
    return SOURCE.format(kind=kind, literal=LITERALS[kind], comparison=comparison, update=update)


def scenarios(inclusive=False):
    result = []
    for stride in (1, 2, 3, 7, 31):
        for count in (0, 1, 3, 4, 5, 7, 8, 9):
            end = 1 + count * stride
            if inclusive:
                end = 0
                if count:
                    end = 1 + (count - 1) * stride
            result.append(dict(pointer=16384, length=512, begin=1, end=end, step=stride))
    base = dict(pointer=16384, length=64, begin=0, end=16, step=3)
    variants = [dict(length=5), dict(length=0), dict(pointer=-9), dict(pointer=-1),
                dict(pointer=0xfffffff8), dict(pointer=0xfffffff8, begin=8, end=9, step=1),
                dict(begin=-1), dict(begin=64), dict(end=(1 << 63) - 1),
                dict(begin=0, end=0, step=0), dict(begin=1, end=0, step=-1),
                dict(length=0, step=0), dict(step=-1), dict(step=-(1 << 63)),
                dict(step=0xffffffff), dict(step=1 << 32), dict(step=(1 << 63) - 1),
                dict(begin=1, step=(1 << 63) - 1),
                dict(begin=1 << 30, end=(1 << 30) + 1, length=0xffffffff, step=7),
                dict(pointer=0xffffffff, length=0, begin=1, end=0, step=0)]
    if inclusive:
        # Zero stride is finite only when the first store traps or the loop is empty.
        variants[9] = dict(begin=1, end=0, step=0)
    result.extend(dict(base, **variant) for variant in variants)
    return result


def regions(size):
    return [(0, 4096), (16320, 4096), (size - 4096, 4096)]


NODE_HOST = r'''
const fs=require('node:fs'),module_=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
const cases=JSON.parse(process.argv[2]),width=Number(process.argv[3]),entry=process.argv[4];
const encode=values=>{const data=Buffer.alloc(values.length*width);values.forEach((value,j)=>{
  let bits=BigInt.asUintN(width*8,BigInt(value));for(let i=0;i<width;i++){data[j*width+i]=Number(bits&255n);bits>>=8n;}
});return data;};
const results=cases.map(c=>{
  let e;const goose={},aborts=[];for(const item of WebAssembly.Module.imports(module_))goose[item.name]=()=>{};
  goose.abort=(p,n,line)=>aborts.push([Buffer.from(e.memory.buffer).subarray(p>>>0,(p>>>0)+(n>>>0)).toString(),line]);
  e=new WebAssembly.Instance(module_,{goose}).exports;e._start();const image=Buffer.from(e.memory.buffer),size=image.length;
  const backing=image.indexOf(encode([17,34,51,68]));if(backing<0)throw Error('missing backing');
  const header=Buffer.alloc(8);header.writeUInt32LE(backing);header.writeUInt32LE(4,4);const headers=[];
  for(let p=image.indexOf(header);p>=0;p=image.indexOf(header,p+1))headers.push(p);
  if(!headers.length)throw Error('missing slice header');
  let pointer=c.pointer;if(pointer<0)pointer+=size;
  if(c.header_offset!==undefined)pointer=headers[0]+c.header_offset;
  for(const [at,n]of [[16320,4096],[size-4096,4096]])for(let i=at;i<at+n;i++)image[i]=(i*37+17)&255;
  for(const at of headers){image.writeUInt32LE(pointer>>>0,at);image.writeUInt32LE(c.length,at+4);}
  const windows=()=>[[0,4096],[16320,4096],[size-4096,4096]].map(([at,n])=>[at,Array.from(image.subarray(at,at+n))]);
  const before=windows();let trapped=false,result=null;
  try{result=String(e[entry](BigInt(c.begin),BigInt(c.end),BigInt(c.step)));}
  catch(error){if(!(error instanceof WebAssembly.RuntimeError))throw error;trapped=true;}
  return {size,pointer,before,after:windows(),trapped,result,aborts};
});process.stdout.write(JSON.stringify(results));
'''


def wasmtime_run(path, cases, width, entry='paint'):
    import wasmtime
    engine = wasmtime.Engine()
    module = wasmtime.Module.from_file(engine, str(path))
    results = []
    for case in cases:
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
        backing = image.index(merge.encode([17, 34, 51, 68], width))
        header = struct.pack('<II', backing, 4)
        headers = []
        at = image.find(header)
        while at >= 0:
            headers.append(at)
            at = image.find(header, at + 1)
        if not headers:
            raise AssertionError('missing slice header')
        pointer = case['pointer']
        if pointer < 0:
            pointer += size
        if 'header_offset' in case:
            pointer = headers[0] + case['header_offset']
        for at, length in regions(size)[1:]:
            image[at:at + length] = bytes((i * 37 + 17) & 255 for i in range(at, at + length))
        for at in headers:
            struct.pack_into('<II', image, at, pointer & 0xffffffff, case['length'])
        memory.write(store, image)
        before = [[at, list(image[at:at + length])] for at, length in regions(size)]
        result = None
        trapped = False
        try:
            result = str(exports[entry](store, case['begin'], case['end'], case['step']))
        except wasmtime.Trap:
            trapped = True
        results.append(dict(size=size, pointer=pointer, before=before,
                            after=[[at, list(memory.read(store, at, at + length))] for at, length in regions(size)],
                            trapped=trapped, result=result, aborts=aborts))
    return results


def expected(case, observed, kind, inclusive=False, unit=False):
    width = int(kind[1:]) // 8
    image = {at + i: byte for at, data in observed['before'] for i, byte in enumerate(data)}
    cur = case['begin']
    end = case['end']
    if inclusive:
        end += 1
    step = case['step']
    if unit:
        step = 1
    trapped = False
    iterations = 0
    try:
        while cur < end:
            if cur < 0 or cur >= case['length']:
                raise IndexError()
            pointer = (observed['pointer'] + cur * width) & 0xffffffff
            if pointer + width > observed['size']:
                raise IndexError()
            for i, value in enumerate(merge.encode([LITERALS[kind]], width)):
                image[pointer + i] = value
            cur = ((cur + step + (1 << 63)) & ((1 << 64) - 1)) - (1 << 63)
            iterations += 1
            if iterations > 1024:
                raise AssertionError('test scenario would not terminate')
    except IndexError:
        trapped = True
    result = None
    if not trapped:
        result = str(cur)
    return dict(trapped=trapped, result=result,
                after=[[at, [image[at + i] for i in range(len(data))]] for at, data in observed['before']])


def closed_source(kind, storage):
    declaration = 'var xs:' + kind + '[64]=[11;64];'
    global_declaration = ''
    if storage.startswith('owner'):
        declaration = 'var xs:' + kind + '[>..]=[11;64];'
    if storage.endswith('global'):
        global_declaration = declaration
        declaration = ''
    return global_declaration + '''
recursive fn work(end:i64,stride:i64)->i64 {{
    {declaration} var cur=1;
    while cur<end {{ xs[cur]={literal}; cur+=stride; }}
    var count:i64=0;
    for value,i in xs {{
        if i%3==1 {{ if value!={literal} {{ return -1; }} count++; }}
        else {{ if value!=11 {{ return -2; }} }}
    }}
    return count;
}}
fn main() {{ print(work(64,3)); }}
'''.format(declaration=declaration, literal=LITERALS[kind])


class StridedStores(unittest.TestCase):
    setUp = strip.StripLoops.setUp
    compile = merge.MergeBounds.compile
    native = fv.FunctionValueForwarding.native
    run_engines = fv.FunctionValueForwarding.run_engines

    def ordinary(self, source, level, debug=False, name='paint', optimized=True, output='5\n'):
        path, stats = self.compile(source, level, debug)
        self.assertEqual(self.native(source, level, debug), output)
        for engine, result in self.run_engines(path):
            self.assertEqual(result, output, engine)
        reference = None
        if REFERENCE is not None:
            reference, old_stats = self.compile(source, level, debug, REFERENCE)
            body = function_body(path, stats, name)
            old = function_body(reference, old_stats, name)
            if debug or not optimized:
                self.assertEqual(body, old)
            elif level == 2:
                self.assertNotEqual(body, old, 'eligible grouped store did not change')
        return path, reference

    def engines(self, path, cases, kind, entry='paint'):
        node_cases = []
        for case in cases:
            row = dict(case)
            for key in ('begin', 'end', 'step'):
                row[key] = str(row[key])
            node_cases.append(row)
        width = int(kind[1:]) // 8
        result = subprocess.run([strip.NODE, '-e', NODE_HOST, str(path), json.dumps(node_cases), str(width), entry],
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return {'v8': json.loads(result.stdout), 'wasmtime': wasmtime_run(path, cases, width, entry)}

    def test_raw_owner_header_overlap_uses_scalar_fallback_after_test_only_export(self):
        source = '''var xs:u32[>..]=[17,34,51,68];
recursive fn attempt(begin:i64,end:i64,stride:i64)->i64 {
    var cur=begin; var stop=end; var jump=stride;
    while cur<stop { xs[cur]=4045620583; cur+=jump; }
    return cur;
}
fn main() { print(attempt(1,0,2)); }
'''
        cases = [dict(pointer=16384, length=64, begin=0, end=9, step=1)]
        for offset in (-16, -8, -4, 0, 4, 8, 12, 20, 24):
            cases.append(dict(cases[0], header_offset=offset))
        cases.extend([dict(cases[0], pointer=0xffffffff, begin=1, end=0),
                      dict(cases[0], header_offset=0, begin=1, end=0),
                      dict(cases[0], pointer=-9)])
        for level in (0, 2):
            paths = []
            bodies = []
            for compiler in (strip.GOOSE, REFERENCE):
                if compiler is None:
                    continue
                path, stats = self.compile(source, level, False, compiler)
                index = next(row['index'] for row in stats['function_info'] if row['name'].split('#')[0] == 'attempt')
                original = path.read_bytes()
                bodies.append(function_body(path, stats, 'attempt'))
                # Expose the already compiled closed/raw body; source exports would disable its proof.
                changed = expose_attempt(original, index)
                self.assertEqual(dict(sections(original))[10], dict(sections(changed))[10])
                path.write_bytes(changed)
                paths.append(path)
            current = self.engines(paths[0], cases, 'u32', 'attempt')
            self.assertEqual(current['v8'], current['wasmtime'])
            if len(paths) == 2:
                if level == 2:
                    self.assertNotEqual(bodies[0], bodies[1], 'closed raw-owner loop must contain grouped stores')
                self.assertEqual(current, self.engines(paths[1], cases, 'u32', 'attempt'))

    def dynamic(self, source, kind, level, inclusive=False, unit=False):
        output = '5\n'
        if unit:
            output = '4\n'
        if inclusive:
            source = source.replace('paint(1,4,2)', 'paint(1,3,2)')
        path, reference = self.ordinary(source, level, output=output)
        cases = scenarios(inclusive)
        results = self.engines(path, cases, kind)
        self.assertEqual(results['v8'], results['wasmtime'])
        for engine, rows in results.items():
            for case, observed in zip(cases, rows, strict=True):
                with self.subTest(kind=kind, level=level, engine=engine, case=case):
                    wanted = expected(case, observed, kind, inclusive, unit)
                    self.assertEqual({key: observed[key] for key in wanted}, wanted)
        if reference is not None:
            self.assertEqual(results, self.engines(reference, cases, kind))

    def test_literal_bits_all_widths_groups_tails_and_guard_failures(self):
        for kind in LITERALS:
            for level in (0, 2):
                self.dynamic(source_for(kind), kind, level)

    def test_inclusive_unit_and_explicit_assignment_updates(self):
        for level in (0, 2):
            self.dynamic(source_for('u32', '<='), 'u32', level, inclusive=True)
            self.dynamic(source_for('u32', update='cur++;'), 'u32', level, unit=True)
            self.dynamic(source_for('u32', update='cur=cur+jump;'), 'u32', level)

    def test_fixed_and_raw_owned_receivers_keep_closed_program_results(self):
        for kind in ('u8', 'i16', 'u32', 'i64'):
            for storage in ('fixed-frame', 'fixed-global', 'owner-frame', 'owner-global'):
                source = closed_source(kind, storage)
                for level in (0, 2):
                    with self.subTest(kind=kind, storage=storage, level=level):
                        self.ordinary(source, level, name='work', output='21\n')

    def test_debug_capture_address_and_extra_effects_keep_scalar_bodies(self):
        source = source_for('u32')
        variants = [source.replace('cur+=jump;', 'xs[cur]=4045620583; cur+=jump;'),
                    source.replace('cur+=jump;', 'effects++; cur+=jump;'),
                    'recursive fn side() { effects++; }\n' + source.replace('cur+=jump;', 'side(); cur+=jump;')]
        for name in ('cur', 'stop', 'jump'):
            variants.append('recursive fn expose(value:i64&)->i64 { value }\n' + source.replace(
                'while cur<stop', 'let observed=expose(' + name + '); while cur<stop'))
            variants.append(source.replace('while cur<stop',
                'recursive fn observe()->i64 { ' + name + ' } let observed=observe(); while cur<stop'))
        for level in (0, 2):
            self.ordinary(source, level, debug=True)
            for variant in variants:
                self.ordinary(variant, level, optimized=False)
            broken = source.replace('cur+=jump;', 'break;')
            self.ordinary(broken, level, optimized=False, output='1\n')

    def test_encoded_and_host_observable_owners_keep_scalar_bodies(self):
        source = closed_source('u32', 'owner-global')
        exported = source.replace('recursive fn work', 'export fn work')
        encoded = 'var encoded:varint[>..]=[11];\n' + source.replace('print(work(64,3));',
            'for value in encoded { if value!=11 { abort("wrong encoded value"); } } print(work(64,3));')
        for level in (0, 2):
            self.ordinary(exported, level, name='work', optimized=False, output='21\n')
            self.ordinary(encoded, level, name='work', optimized=False, output='21\n')

    def test_forged_owner_headers_remain_on_the_original_mode_dispatch(self):
        source = '''var xs:u32[>..]=[17,34,51,68];
export fn paint(begin:i64,end:i64,stride:i64)->i64 {
    var cur=begin; var stop=end; var jump=stride;
    while cur<stop { xs[cur]=4045620583; cur+=jump; }
    return cur;
}
fn main() { print(paint(1,4,2)); xs=[17,34,51,68]; }
'''
        for level in (0, 2):
            path, reference = self.ordinary(source, level, optimized=False)
            cases = scenarios()[40:]
            results = self.engines(path, cases, 'u32')
            self.assertEqual(results['v8'], results['wasmtime'])
            # The export deliberately disables the closed-module raw-image proof.
            # Preserve its authoritative metadata checks rather than assuming raw layout.
            if reference is not None:
                self.assertEqual(results, self.engines(reference, cases, 'u32'))

    def test_full_sieve_golden_remains_unchanged(self):
        source = (strip.ROOT / 'examples/sieve.goose').read_text()
        expected_output = (strip.ROOT / 'examples/expected/sieve.out').read_text()
        for level in (0, 2):
            self.ordinary(source, level, name='main', output=expected_output)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--goose', type=Path, default=strip.GOOSE)
    parser.add_argument('--reference-compiler', type=Path)
    parser.add_argument('--node', default=strip.NODE)
    args, remaining = parser.parse_known_args()
    strip.GOOSE = args.goose.resolve()
    strip.NODE = args.node
    if args.reference_compiler:
        REFERENCE = args.reference_compiler.resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
