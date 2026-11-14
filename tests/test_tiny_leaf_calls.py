#!/usr/bin/env python3
"""Qualify tiny leaf expansion, argument snapshots, and ordered trap effects."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import struct
import subprocess
import sys
import unittest

import test_strip_loops as strip
from test_fill_loops import function_body, uleb

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'build/tiny-tests'

REPEATED = '''fn exchange(xs:i64[:],i:i64,j:i64) {
    let saved=xs[i]; xs[i]=xs[j]; xs[j]=saved;
}
recursive fn drive(xs:i64[:]) {
    exchange(xs,0,3); exchange(xs,1,2); exchange(xs,0,0);
}
fn main() { var xs=[11,22,33,44]; drive(xs[..]); print(xs); }
'''
ORDER = '''var first:i64[4]=[17,34,51,68]; var second:i64[4]=[81,82,83,84];
var saved:i64[:]; var effects:i64=0;
fn write(xs:i64[:],index:i64,value:i64) { xs[index]=value; }
recursive fn next(n:i64)->i64 {
    effects=effects*10+n; if n==2 { saved=second[..]; } return n;
}
recursive fn drive() { write(saved,next(1),next(2)); write(saved,next(0),next(3)); }
fn main() { saved=first[..]; drive(); print(first[0]," ",first[1]," ",second[0]," ",second[1]," ",effects); }
'''
TRAPS = '''var backing:i64[4]=[17,34,51,68]; var saved:i64[:];
fn write(xs:i64[:],i:i64,j:i64,value:i64) { xs[i]=value; xs[j]=value+1; }
recursive fn drive(i:i64,j:i64,value:i64) { write(saved,i,j,value); }
export fn tick(i:i64,j:i64,value:i64) { drive(i,j,value); }
fn main() { saved=backing[..]; tick(0,1,7); print(backing); backing=[17,34,51,68]; }
'''


def calls(body):
    """Decode call indices at instruction boundaries, never raw byte matches."""
    count, offset = uleb(body, 0)
    for _ in range(count):
        _, offset = uleb(body, offset)
        offset += 1
    result = []
    while offset < len(body):
        op = body[offset]
        offset += 1
        if op in (0x02,0x03,0x04,0x0c,0x0d,0x10,0x20,0x21,0x22,0x23,0x24,0x3f,0x40,0x41,0x42):
            value, offset = uleb(body, offset)
            if op == 0x10:
                result.append(value)
        elif op == 0x0e:
            count, offset = uleb(body, offset)
            for _ in range(count + 1):
                _, offset = uleb(body, offset)
        elif op == 0x11 or 0x28 <= op <= 0x3e:
            _, offset = uleb(body, offset)
            _, offset = uleb(body, offset)
        elif op == 0x43:
            offset += 4
        elif op == 0x44:
            offset += 8
        elif op == 0xfc:
            sub, offset = uleb(body, offset)
            if sub in (10,14):
                _, offset = uleb(body, offset)
                _, offset = uleb(body, offset)
            elif sub in (11,15,16,17):
                _, offset = uleb(body, offset)
            else:
                raise AssertionError(f'unexpected prefixed instruction {sub}')
        elif not (op in (0x00,0x01,0x05,0x0b,0x0f,0x1a,0x1b) or 0x45 <= op <= 0xc4):
            raise AssertionError(f'unexpected instruction {op:#x}')
    return result


NODE_TRAPS = r'''
const fs=require('node:fs'),module_=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
const cases=JSON.parse(process.argv[2]),marker=Buffer.alloc(32);
[17n,34n,51n,68n].forEach((v,i)=>marker.writeBigInt64LE(v,i*8));
const rows=cases.map(c=>{
  const goose={};for(const item of WebAssembly.Module.imports(module_))goose[item.name]=()=>{};
  const e=new WebAssembly.Instance(module_,{goose}).exports;e._start();
  const image=Buffer.from(e.memory.buffer),backing=image.indexOf(marker);
  if(backing<0)throw Error('missing sentinel');const header=Buffer.alloc(8);
  header.writeUInt32LE(backing);header.writeUInt32LE(4,4);const headers=[];
  for(let p=image.indexOf(header);p>=0;p=image.indexOf(header,p+1))headers.push(p);
  if(!headers.length)throw Error('missing slice header');
  let at=backing,count=4;if(c.tail){at=image.length-8;count=1;image.writeBigInt64LE(99n,at);}
  for(const p of headers){image.writeUInt32LE(at,p);image.writeUInt32LE(c.length,p+4);}
  let trapped=false;try{e.tick(BigInt(c.i),BigInt(c.j),7n);}catch(err){if(!(err instanceof WebAssembly.RuntimeError))throw err;trapped=true;}
  const values=[];for(let i=0;i<count;i++)values.push(String(image.readBigInt64LE(at+i*8)));
  return {trapped,values};
});process.stdout.write(JSON.stringify(rows));
'''


def wasmtime_traps(path, scenarios):
    import wasmtime
    engine = wasmtime.Engine()
    module = wasmtime.Module.from_file(engine, str(path))
    results = []
    for case in scenarios:
        store = wasmtime.Store(engine)
        linker = wasmtime.Linker(engine)
        for item in module.imports:
            linker.define_func(item.module, item.name, item.type, lambda *args: None)
        exports = linker.instantiate(store, module).exports(store)
        exports['_start'](store)
        memory = exports['memory']
        image = bytearray(memory.read(store))
        backing = image.index(struct.pack('<qqqq',17,34,51,68))
        header = struct.pack('<II',backing,4)
        positions = []
        at = image.find(header)
        while at >= 0:
            positions.append(at)
            at = image.find(header, at + 1)
        assert positions, 'missing slice header'
        at = backing
        count = 4
        if case['tail']:
            at = len(image) - 8
            count = 1
            struct.pack_into('<q', image, at, 99)
        for position in positions:
            struct.pack_into('<II', image, position, at, case['length'])
        memory.write(store, image)
        trapped = False
        try:
            exports['tick'](store, case['i'], case['j'], 7)
        except wasmtime.Trap:
            trapped = True
        values = struct.unpack('<' + 'q' * count, memory.read(store, at, at + count * 8))
        results.append(dict(trapped=trapped,values=list(map(str,values))))
    return results


class TinyLeafCalls(unittest.TestCase):
    def setUp(self):
        stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
        self.work = EVIDENCE / (stamp + '-' + self._testMethodName)
        self.work.mkdir(parents=True)
        self.serial = 0

    def command(self, command, label):
        result = subprocess.run(list(map(str,command)),capture_output=True,text=True,timeout=60)
        (self.work / (label + '.log')).write_text(json.dumps(dict(command=list(map(str,command)),
            returncode=result.returncode,stdout=result.stdout,stderr=result.stderr),indent=2))
        self.assertEqual(result.returncode,0,result.stdout + result.stderr)
        return result.stdout

    def compile(self, source, level, debug):
        self.serial += 1
        stem = f'{self.serial:03d}-O{level}-debug{int(debug)}'
        path = self.work / (stem + '.goose')
        path.write_text(source)
        output = path.with_suffix('.wasm')
        stats = path.with_suffix('.json')
        command = [strip.GOOSE,path,'--offline','--target','wasm-direct',f'-O{level}',
                   '--wasm-stats',stats,'-o',output]
        if debug:
            command.append('--debug')
        self.command(command,stem + '-compile')
        return output,json.loads(stats.read_text())

    def native(self, source, level, debug):
        path = self.work / f'native-{self.serial:03d}.goose'
        path.write_text(source)
        cfile = path.with_suffix('.c')
        binary = path.with_suffix('')
        command = [strip.GOOSE,path,'--offline',f'-O{level}','--target','native','--standalone','-o',cfile]
        if debug:
            command.append('--debug')
        stem = f'{path.stem}-O{level}-debug{int(debug)}'
        self.command(command,stem + '-compile')
        self.command(['cc',cfile,'-lm','-o',binary],stem + '-cc')
        return self.command([binary],stem + '-run')

    def engines(self, path):
        for engine,command in (
            ('v8',[strip.NODE,ROOT/'scripts/run_wasm.mjs',path]),
            ('wasmtime',[sys.executable,ROOT/'scripts/run_wasmtime.py',path]),
        ):
            yield engine,self.command(command,path.stem + '-' + engine)

    def lowering(self, path, stats, caller, callee, expanded):
        helper = next(item for item in stats['function_info'] if item['name'].split('#')[0] == callee)
        body = function_body(path,stats,caller)
        self.assertEqual(helper['index'] not in calls(body),expanded,
                         f'{caller} calls retained helper {callee}: {calls(body)}')

    def qualify(self, source, expected, caller, callee, eligible=True):
        for level in (0,2):
            for debug in (False,True):
                with self.subTest(level=level,debug=debug):
                    path,stats = self.compile(source,level,debug)
                    for name in callee.split(','):
                        self.lowering(path,stats,caller,name,eligible and not debug)
                    self.assertEqual(self.native(source,level,debug),expected)
                    for engine,output in self.engines(path):
                        self.assertEqual(output,expected,engine)

    def test_repeated_sites_bind_fresh_locals_and_same_index(self):
        self.qualify(REPEATED,'[44, 33, 22, 11]\n','drive','exchange')

    def test_actuals_evaluate_once_in_order_and_snapshot_old_slice(self):
        self.qualify(ORDER,'17 2 3 82 1203\n','drive','write')

    def test_all_scalar_widths_and_wrapped_narrowing(self):
        declarations = []
        setup = []
        operations = []
        output = []
        expected = []
        names = []
        for kind in ('i8','u8','i16','u16','i32','u32','i64','u64','f32','f64','bool'):
            name = 'exchange_' + kind
            names.append(name)
            first, second = '3','7'
            values = '7 3'
            if kind.startswith('f'):
                first, second = '1.25','2.5'
                values = '2.5 1.25'
            elif kind == 'bool':
                first, second = 'false','true'
                values = 'true false'
            declarations.append(f'fn {name}(xs:{kind}[:]) {{ let saved=xs[0]; xs[0]=xs[1]; xs[1]=saved; }}')
            setup.append(f'var v_{kind}:{kind}[2]=[{first},{second}];')
            operations.append(f'{name}(v_{kind}[..]);')
            output.append(f'print(v_{kind}[0]," ",v_{kind}[1]);')
            expected.append(values)
        declarations.append('fn narrow(xs:u8[:],value:u8) { xs[0]=((xs[0] as u64)+(value as u64)) as! u8; }')
        setup.append('var narrowed:u8[1]=[250];')
        operations.append('narrow(narrowed[..],10);')
        output.append('print(narrowed[0]);')
        expected.append('4')
        source = '\n'.join(declarations) + '\nrecursive fn drive() { ' + ' '.join(setup + operations + output) + ' }\nfn main() { drive(); }\n'
        self.qualify(source,'\n'.join(expected) + '\n','drive',','.join(names + ['narrow']))

    def test_private_parameter_mutation_and_overlapping_views(self):
        source = '''fn adjust(xs:i64[:],var value:i64) { value+=3; xs[0]=value; }
fn exchange(xs:i64[:],ys:i64[:]) { let saved=xs[0]; xs[0]=ys[0]; ys[0]=saved; }
recursive fn drive() {
    var xs=[11,22,33,44]; var n=5;
    adjust(xs[..],n); exchange(xs[..],xs[1..]); exchange(xs[1..],xs[1..]);
    print(xs," ",n);
}
fn main() { drive(); }
'''
        self.qualify(source,'[22, 8, 33, 44] 5\n','drive','adjust,exchange')

    def test_unsafe_bodies_keep_original_calls(self):
        variants = {
            'global': ('var effects:i64=0;','effects++; xs[index]=value;'),
            'reference-local': ('','let alias:i64& = index; xs[alias]=value;'),
            'call': ('recursive fn identity(n:i64)->i64 { return n; }','xs[index]=identity(value);'),
            'loop': ('','for i in 1 { xs[index]=value; }'),
            'branch': ('','if index>=0 { xs[index]=value; }'),
            'return': ('','if index<0 { return; } xs[index]=value;'),
            'owner': ('','var owned:i64[>..]=[value]; xs[index]=owned[0];'),
            'capture': ('','recursive fn current()->i64 { return value; } xs[index]=current();'),
        }
        for name,(prefix,body) in variants.items():
            source = prefix + ' fn write(xs:i64[:],index:i64,value:i64) { ' + body + ''' }
recursive fn drive() { var xs=[1,2]; write(xs[..],0,7); print(xs); }
fn main() { drive(); }
'''
            with self.subTest(fallback=name):
                self.qualify(source,'[7, 2]\n','drive','write',eligible=False)

    def test_bounds_and_memory_traps_preserve_prior_stores(self):
        scenarios = [dict(i=0,j=1,length=4,tail=False),dict(i=0,j=0,length=4,tail=False),
                     dict(i=0,j=4,length=4,tail=False),dict(i=-1,j=0,length=4,tail=False),
                     dict(i=0,j=1,length=0,tail=False),dict(i=0,j=1,length=4,tail=True),
                     dict(i=1,j=0,length=4,tail=True)]
        wanted = [dict(trapped=False,values=['7','8','51','68']),
                  dict(trapped=False,values=['8','34','51','68']),
                  dict(trapped=True,values=['7','34','51','68']),
                  dict(trapped=True,values=['17','34','51','68']),
                  dict(trapped=True,values=['17','34','51','68']),
                  dict(trapped=True,values=['7']),dict(trapped=True,values=['99'])]
        for level in (0,2):
            for debug in (False,True):
                with self.subTest(level=level,debug=debug):
                    path,stats = self.compile(TRAPS,level,debug)
                    self.lowering(path,stats,'drive','write',not debug)
                    self.assertEqual(self.native(TRAPS,level,debug),'[7, 8, 51, 68]\n')
                    v8 = json.loads(self.command([strip.NODE,'-e',NODE_TRAPS,path,json.dumps(scenarios)],path.stem + '-v8-traps'))
                    wt = wasmtime_traps(path,scenarios)
                    (self.work / (path.stem + '-traps.json')).write_text(json.dumps(dict(v8=v8,wasmtime=wt),indent=2))
                    self.assertEqual(v8,wanted)
                    self.assertEqual(wt,wanted)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--goose',type=Path,default=strip.GOOSE)
    parser.add_argument('--node',default=strip.NODE)
    parser.add_argument('--evidence',type=Path,default=EVIDENCE)
    args,remaining = parser.parse_known_args()
    strip.GOOSE = args.goose.resolve()
    strip.NODE = args.node
    EVIDENCE = args.evidence.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
