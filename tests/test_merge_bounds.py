#!/usr/bin/env python3
"""Qualify guarded merge bounds against ordered scalar reads and writes."""
import argparse
import json
from pathlib import Path
import struct
import subprocess
import sys
import unittest

import test_function_value_forwarding as fv
import test_strip_loops as strip
from test_fill_loops import function_body

REFERENCE = None
MARKERS = ([17, 34, 51, 68], [81, 82, 83, 84], list(range(111, 119)))
SOURCE = '''var saved_left:{kind}[:]; var saved_right:{kind}[:]; var saved_out:{kind}[:];
var first:{kind}[4]=[17,34,51,68]; var second:{kind}[4]=[81,82,83,84];
var destination:{kind}[8]=[111,112,113,114,115,116,117,118];
var effects:i64=0;
export fn merge(begin_left:i64,end_left:i64,begin_right:i64,end_right:i64,begin_out:i64)->i64 {{
    let left=saved_left; let right=saved_right; let output=saved_out;
    var a=begin_left; var b=begin_right; var out=begin_out;
    while a<=end_left && b<=end_right {{
        if left[a]<=right[b] {{ output[out]=left[a]; a++; }}
        else {{ output[out]=right[b]; b++; }}
        out++;
    }}
    return out;
}}
fn main() {{
    saved_left=first[..]; saved_right=second[..]; saved_out=destination[..];
    print(merge(0,3,0,3,0));
    destination=[111,112,113,114,115,116,117,118];
}}
'''


def cases(kind):
    width = int(kind[1:]) // 8
    left = [-7, 0, 7, 9]
    right = [-4, 0, 8, 10]
    if kind.startswith('u'):
        high = 1 << (width * 8 - 1)
        left = [0, high - 1, high, high * 2 - 1]
        right = [1, high - 1, high + 1, high * 2 - 1]
    base = dict(left=left, right=right, src=16384, other=24576, dst=32768,
                nl=4, nr=4, nd=8, a=0, ae=3, b=0, be=3, out=0)
    variants = [dict(), dict(left=[3] * 4, right=[3] * 4),
                dict(dst=16384), dict(dst=16384 + width), dict(dst=16384 - width),
                dict(dst=24576 + width), dict(dst=24576 - width),
                dict(other=16384), dict(other=16384 + width),
                dict(a=1, ae=0), dict(b=0, be=-1), dict(a=0, ae=-1),
                dict(a=-1, b=0, be=-1), dict(src=0xfffffff8, ae=-1),
                dict(nl=2), dict(nr=2), dict(nd=2), dict(nd=0), dict(nl=0), dict(nr=0),
                dict(a=-1), dict(b=-1), dict(out=-1), dict(out=8),
                dict(a=4), dict(ae=4), dict(be=4), dict(ae=(1 << 63) - 1), dict(out=(1 << 63) - 1),
                dict(src=-2 * width), dict(other=-2 * width), dict(dst=-2 * width),
                dict(src=0xfffffff8), dict(dst=0xfffffff8),
                dict(src=0xfffffff8, a=1, ae=1, b=0, be=0, nl=2),
                dict(a=1 << 30, ae=1 << 30, nl=0xffffffff, b=0, be=0)]
    return [dict(base, **variant) for variant in variants]


def long_cases(kind, invalid=False):
    width = int(kind[1:]) // 8
    left = [i * 2 - 32 for i in range(32)]
    right = [value + 1 for value in left]
    if kind.startswith('u'):
        high = 1 << (width * 8 - 1)
        left = list(range(16)) + [high + i for i in range(16)]
        right = [value + 1 for value in left]
    base = dict(cases(kind)[0], left=left, right=right, nl=32, nr=32, nd=64, ae=31, be=31)
    variants = [dict(), dict(left=[3] * 32, right=[3] * 32),
                dict(dst=16384 + width), dict(dst=16384 - width),
                dict(dst=24576 + width), dict(dst=24576 - width),
                dict(other=16384 + width), dict(other=16384 - width),
                dict(a=17), dict(a=16), dict(a=15), dict(nr=1, be=0, right=right[:1])]
    if invalid:
        variants = [dict(nl=31), dict(nr=31), dict(nd=32), dict(out=49),
                    dict(src=-24 * width), dict(other=-24 * width), dict(dst=-24 * width),
                    dict(src=0xfffffff8), dict(dst=0xfffffff8)]
    return [dict(base, **variant) for variant in variants]


def regions(size):
    return [(0, 1024), (16320, 1024), (24512, 1024), (32704, 1024), (size - 1024, 1024)]


def encode(values, width):
    mask = (1 << (width * 8)) - 1
    return b''.join((int(value) & mask).to_bytes(width, 'little') for value in values)


NODE_HOST = r'''
const fs=require('node:fs'),module_=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
const cases=JSON.parse(process.argv[2]),width=Number(process.argv[3]),markers=JSON.parse(process.argv[4]);
const encode=values=>{const b=Buffer.alloc(values.length*width);values.forEach((v,i)=>{
  const n=BigInt.asUintN(width*8,BigInt(v));if(width===8)b.writeBigUInt64LE(n,i*width);else b.writeUInt32LE(Number(n),i*width);
});return b;};
const results=cases.map(c=>{
  let e;const aborts=[],goose={};for(const item of WebAssembly.Module.imports(module_))goose[item.name]=()=>{};
  goose.abort=(p,n,line)=>aborts.push([Buffer.from(e.memory.buffer).subarray(p>>>0,(p>>>0)+(n>>>0)).toString(),line]);
  e=new WebAssembly.Instance(module_,{goose}).exports;e._start();const image=Buffer.from(e.memory.buffer),size=image.length;
  const headers=markers.map(values=>{const at=image.indexOf(encode(values));if(at<0)throw Error('missing backing');
    const h=Buffer.alloc(8);h.writeUInt32LE(at);h.writeUInt32LE(values.length,4);const positions=[];
    for(let p=image.indexOf(h);p>=0;p=image.indexOf(h,p+1))positions.push(p);
    if(!positions.length)throw Error('missing slice header');return positions;});
  const ptrs=[c.src,c.other,c.dst].map(p=>{if(p<0)return size+p;return p;});
  for(const [at,n]of [[16320,1024],[24512,1024],[32704,1024],[size-1024,1024]])for(let i=at;i<at+n;i++)image[i]=(i*37+17)&255;
  for(const [slot,values]of [[0,c.left],[1,c.right]]){const data=encode(values),at=ptrs[slot];
    for(let i=0;i<data.length;i++)if(at+i>=0&&at+i<size)image[at+i]=data[i];}
  headers.forEach((positions,i)=>positions.forEach(at=>{image.writeUInt32LE(ptrs[i]>>>0,at);image.writeUInt32LE([c.nl,c.nr,c.nd][i],at+4);}));
  const windows=()=>[[0,1024],[16320,1024],[24512,1024],[32704,1024],[size-1024,1024]].map(([at,n])=>[at,Array.from(image.subarray(at,at+n))]);
  const before=windows();let trapped=false,result=null;
  try{result=String(e.merge(...[c.a,c.ae,c.b,c.be,c.out].map(BigInt)));}
  catch(error){if(!(error instanceof WebAssembly.RuntimeError))throw error;trapped=true;}
  return {size,ptrs,before,after:windows().slice(1),trapped,result,aborts};
});process.stdout.write(JSON.stringify(results));
'''


def wasmtime_run(path, scenarios, width):
    import wasmtime
    engine = wasmtime.Engine()
    module = wasmtime.Module.from_file(engine, str(path))
    results = []
    for case in scenarios:
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
        headers = []
        for values in MARKERS:
            backing = image.index(encode(values, width))
            header = struct.pack('<II', backing, len(values))
            # Addressed/captured views can leave additional frame copies.
            positions = []
            at = image.find(header)
            while at >= 0:
                positions.append(at)
                at = image.find(header, at + 1)
            if not positions:
                raise AssertionError('missing slice header')
            headers.append(positions)
        pointers = [case[key] for key in ('src', 'other', 'dst')]
        for i, pointer in enumerate(pointers):
            if pointer < 0:
                pointers[i] += size
        for at, length in regions(size)[1:]:
            image[at:at + length] = bytes((i * 37 + 17) & 255 for i in range(at, at + length))
        for pointer, values in zip(pointers, (case['left'], case['right'])):
            for i, value in enumerate(encode(values, width)):
                if 0 <= pointer + i < size:
                    image[pointer + i] = value
        for positions, pointer, length in zip(headers, pointers, (case['nl'], case['nr'], case['nd'])):
            for at in positions:
                struct.pack_into('<II', image, at, pointer & 0xffffffff, length)
        memory.write(store, image)
        before = [[at, list(image[at:at + length])] for at, length in regions(size)]
        trapped = False
        result = None
        try:
            result = str(exports['merge'](store, *(case[key] for key in ('a', 'ae', 'b', 'be', 'out'))))
        except wasmtime.Trap:
            trapped = True
        results.append(dict(size=size, ptrs=pointers, before=before,
                            after=[[at, list(memory.read(store, at, at + length))] for at, length in regions(size)[1:]],
                            trapped=trapped, result=result, aborts=aborts))
    return results


def expected(case, observed, kind, exclusive=False, comparison='<='):
    width = int(kind[1:]) // 8
    image = {at + i: byte for at, data in observed['before'] for i, byte in enumerate(data)}
    a, b, out = (case[key] for key in ('a', 'b', 'out'))
    ae, be = case['ae'] + 1, case['be'] + 1
    if exclusive:
        ae, be = case['ae'], case['nr']
    def address(slot, index):
        length = (case['nl'], case['nr'], case['nd'])[slot]
        if index < 0 or index >= length:
            raise IndexError()
        pointer = (observed['ptrs'][slot] + index * width) & 0xffffffff
        if pointer + width > observed['size']:
            raise IndexError()
        return pointer
    def read(slot, index):
        pointer = address(slot, index)
        return int.from_bytes(bytes(image[pointer + i] for i in range(width)), 'little', signed=kind.startswith('i'))
    trapped = False
    try:
        while a < ae and b < be:
            slot, index = 1, b
            left, right = read(0, a), read(1, b)
            choose_left = left <= right
            if comparison == '>':
                choose_left = left > right
            elif comparison == '>=':
                choose_left = left >= right
            if choose_left:
                slot, index = 0, a
            value = read(slot, index)
            pointer = address(2, out)
            for i, byte in enumerate(encode([value], width)):
                image[pointer + i] = byte
            if slot == 0:
                a += 1
            else:
                b += 1
            out += 1
    except IndexError:
        trapped = True
    result = None
    if not trapped:
        result = str(out)
    return dict(trapped=trapped, result=result,
                after=[[at, [image[at + i] for i in range(len(data))]] for at, data in observed['before'][1:]])


class MergeBounds(unittest.TestCase):
    setUp = strip.StripLoops.setUp
    native = fv.FunctionValueForwarding.native
    run_engines = fv.FunctionValueForwarding.run_engines

    def compile(self, source, level, debug, compiler=None):
        if compiler is None:
            compiler = strip.GOOSE
        source_path = self.work / 'main.goose'
        source_path.write_text(source)
        output = self.work / f'program-{len(list(self.work.glob("*.wasm")))}.wasm'
        stats = output.with_suffix('.json')
        command = [str(compiler), str(source_path), '--offline', '--target', 'wasm-direct',
                   f'-O{level}', '--wasm-stats', str(stats), '-o', str(output)]
        if debug:
            command.append('--debug')
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return output, json.loads(stats.read_text())

    def engines(self, path, scenarios, kind):
        width = int(kind[1:]) // 8
        node_cases = [{key: value for key, value in case.items()} for case in scenarios]
        for case in node_cases:
            for key in ('a', 'ae', 'b', 'be', 'out'):
                case[key] = str(case[key])
            for key in ('left', 'right'):
                case[key] = list(map(str, case[key]))
        run = subprocess.run([strip.NODE, '-e', NODE_HOST, str(path), json.dumps(node_cases), str(width), json.dumps(MARKERS)],
                             capture_output=True, text=True, timeout=60)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        return {'v8': json.loads(run.stdout), 'wasmtime': wasmtime_run(path, scenarios, width)}

    def qualify(self, source, kind, scenarios, exclusive=False, fallback=False, comparison='<='):
        for level in (0, 2):
            for debug in (False, True):
                with self.subTest(kind=kind, level=level, debug=debug):
                    path, stats = self.compile(source, level, debug)
                    oracle = self.native(source, level, debug)
                    self.assertEqual(oracle, '4\n')
                    for engine, output in self.run_engines(path):
                        self.assertEqual(output, oracle, engine)
                    results = self.engines(path, scenarios, kind)
                    self.assertEqual(results['v8'], results['wasmtime'])
                    for engine, rows in results.items():
                        for case, observed in zip(scenarios, rows, strict=True):
                            with self.subTest(engine=engine, case=case):
                                wanted = expected(case, observed, kind, exclusive, comparison)
                                self.assertEqual({key: observed[key] for key in wanted}, wanted)
                    if REFERENCE is None:
                        continue
                    reference, old_stats = self.compile(source, level, debug, REFERENCE)
                    self.assertEqual(results, self.engines(reference, scenarios, kind))
                    body = function_body(path, stats, 'merge')
                    old_body = function_body(reference, old_stats, 'merge')
                    if debug or fallback:
                        self.assertEqual(body, old_body)
                    elif level == 2:
                        self.assertNotEqual(body, old_body, 'eligible merge did not change')

    def test_numeric_widths_equal_keys_high_bits_and_overlapping_views(self):
        for kind in ('i32', 'u32', 'i64', 'u64'):
            self.qualify(SOURCE.format(kind=kind), kind, cases(kind)[:14] + long_cases(kind))

    def test_failed_guards_preserve_partial_writes_and_traps(self):
        for kind in ('i64', 'u32'):
            self.qualify(SOURCE.format(kind=kind), kind, cases(kind)[14:] + long_cases(kind, invalid=True))

    def test_greater_comparisons_preserve_signed_and_unsigned_order(self):
        for kind in ('i64', 'u32'):
            for comparison in ('>', '>='):
                source = SOURCE.format(kind=kind).replace('left[a]<=right[b]', 'left[a]' + comparison + 'right[b]')
                self.qualify(source, kind, long_cases(kind), comparison=comparison)

    def test_renamed_exclusive_ends_and_right_first_comparison(self):
        source = SOURCE.format(kind='i64').replace('a<=end_left && b<=end_right', 'a<end_left && b<right.len')
        source = source.replace('if left[a]<=right[b] { output[out]=left[a]; a++; }\n        else { output[out]=right[b]; b++; }',
                                'if right[b]<left[a] { output[out]=right[b]; b++; }\n        else { output[out]=left[a]; a++; }')
        source = source.replace('merge(0,3,0,3,0)', 'merge(0,4,0,4,0)')
        for old, new in [('begin_left', 'start_l'), ('begin_right', 'start_r'), ('end_left', 'limit'), ('end_right', 'unused_limit')]:
            source = source.replace(old, new)
        scenarios = cases('i64')[:14] + long_cases('i64')
        for case in scenarios:
            case['ae'] += 1
        self.qualify(source, 'i64', scenarios, exclusive=True)

    def test_extra_effects_and_address_exposure_keep_scalar_bodies(self):
        source = SOURCE.format(kind='i64')
        effects = source.replace('out++;', 'effects++; out++;')
        addressed = 'recursive fn touch(view:i64[:]&)->i64 { view.len }\n' + source.replace(
            'var a=begin_left;', 'let visible=touch(left); var a=begin_left;')
        captured = source.replace('var a=begin_left;',
                                  'recursive fn length()->i64 { left.len } let visible=length(); var a=begin_left;')
        for variant in (effects, addressed, captured):
            self.qualify(variant, 'i64', cases('i64')[:3], fallback=True)


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
