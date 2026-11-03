#!/usr/bin/env python3
"""Qualify direct initialization of fresh fixed aggregate storage."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import unittest

import test_function_value_forwarding as fv
import test_prefix_resolution as prefix
import test_strip_loops as strip
from test_static_data import uleb

REFERENCE = None
LITERALS = '''
struct Cell { pad 1, tag:u8, pad, value:i32, pad 3, bytes:u8[..4] }
struct Box { cells:Cell[2], tail:i16[3], name:u8[..8] }
struct Defaults { value:i64=7, bytes:u8[3]=[4,5,6] }
enum Choice { Value { number:i64=11, flag:u8=9 }, Empty }
recursive fn run() {
    let box=Box { [Cell { 1,17,[3,4] },Cell { 2,23,[] }],[-2,0,9],"hi" };
    print(box.cells[0].tag," ",box.cells[0].value," ",box.cells[0].bytes.len," ",box.cells[0].bytes.cap);
    print(box.cells[1].bytes.len," ",box.tail[0]," ",box.tail[2]," ",box.name);
    let zero=default<Box>();
    print(zero.cells[0].value," ",zero.cells[0].bytes.len," ",zero.tail[2]," ",zero.name.len);
    let filled=default<Defaults[2]>();
    print(filled[0].value," ",filled[1].bytes[2]);
    let choice=default<Choice>();
    print(match choice { Value v=>v.number+v.flag as i64, Empty=>-1 });
    let empty:u16[..0]=[]; print(empty.len," ",empty.cap);
}
fn main() { run(); }
'''

EFFECTS = '''
struct Pair { first:i64, second:i64 }
var calls:i64=0;
recursive fn step(n:i64)->i64 { calls=calls*10+n; return calls; }
recursive fn run() {
    let values:i64[3]=[step(1);3];
    let pair=Pair { step(2),step(3) };
    print(values[0]," ",values[2]," ",pair.first," ",pair.second," ",calls);
    let empty:i64[0]=[step(4);0]; print(empty.len," ",calls);
}
fn main() { run(); }
'''

FALLBACKS = {
    "assignment-and-observing-callback": '''
struct Pair { first:i64, second:i64 }
recursive fn seed()->Pair { Pair { 1,2 } }
recursive fn run() {
    var pair=seed();
    pair=Pair { pair.second,pair.first };
    print(pair.first," ",pair.second);
    fn observe()->i64 { pair.first }
    pair=Pair { 9,observe() };
    print(pair.first," ",pair.second);
}
fn main() { run(); }
''',
    "reference-field": '''
struct Ref { point:i64&, value:i64 }
export fn run() {
    var value:i64=7; let holder=Ref { value,3 };
    value=19; print(holder.point," ",holder.value);
}
fn main() { run(); }
''',
    "slice-field": '''
struct View { bytes:u8[:], value:i64 }
recursive fn seed()->u8[3] { [1,2,3] }
export fn run() {
    var values=seed(); let holder=View { values[..],5 };
    values[0]=9; print(holder.bytes[0]," ",holder.value);
}
fn main() { run(); }
''',
    "effectful-default": '''
var calls:i64=0;
recursive fn next()->i64 { calls++; return calls; }
struct Item { first:i64=next(), second:i64=next() }
recursive fn run() {
    let items=default<Item[2]>();
    print(items[0].first," ",items[0].second," ",items[1].first," ",items[1].second," ",calls);
}
fn main() { run(); }
''',
}

GLOBALS = '''
struct Record { pad 1, tag:u8, pad, value:i64, pad 3, name:u8[..8] }
var zero:u8[1024];
var record=Record { 3,17,"ok" };
export fn dirty() { for &item in zero { item=99; } record.tag=90; record.value=91; record.name="bad"; }
export fn checksum()->i64 { var total:i64=0; for item in zero { total+=item as i64; } return total; }
export fn literal()->i64 { return record.tag as i64+record.value+record.name.len; }
fn main() {}
'''
CAPACITY = '''struct R { x:u8[..1] }
var target=R { x:default<u8[2]>() };
export fn dirty() { target.x=[7]; }
export fn read()->i64 { return target.x.len*100+target.x[0] as i64; }
fn main() {}
'''


def frame_size(body):
    """Read the actual activation reservation at the function prologue."""
    groups, offset = uleb(body, 0)
    for _ in range(groups):
        _, offset = uleb(body, offset)
        offset += 1
    if body[offset:offset+2] != b"\x23\x00":
        raise AssertionError("expected activation-base global.get")
    offset += 2
    op = body[offset]
    local, offset = uleb(body, offset+1)
    if op == 0x21:
        if body[offset] != 0x20:
            raise AssertionError("expected activation-base local.get")
        read, offset = uleb(body, offset+1)
        if read != local:
            raise AssertionError("activation-base local mismatch")
    elif op != 0x22:
        raise AssertionError("expected activation-base local.set/tee")
    if body[offset] != 0x41:
        raise AssertionError("expected frame-size i32.const")
    size, offset = uleb(body, offset+1)
    if body[offset] != 0x6a:
        raise AssertionError("expected frame-size addition")
    return size


class FreshInitialization(unittest.TestCase):
    setUp = fv.FunctionValueForwarding.setUp
    compile = fv.FunctionValueForwarding.compile
    compile_file = fv.FunctionValueForwarding.compile_file
    compile_input = fv.FunctionValueForwarding.compile_input
    native = fv.FunctionValueForwarding.native
    run_engines = fv.FunctionValueForwarding.run_engines
    reference_bodies = fv.FunctionValueForwarding.reference_bodies

    def qualify(self, source, expected, unchanged=False):
        for level in (0,2):
            for debug in (False,True):
                with self.subTest(level=level, debug=debug):
                    path, stats = self.compile_input(source, level, debug)
                    current = [(name, body) for name, body in fv.function_bodies(path, stats)
                               if name.split("#")[0] == "run"]
                    oracle = self.native(source, level, debug)
                    self.assertEqual(oracle, expected)
                    for engine, output in self.run_engines(path):
                        with self.subTest(engine=engine):
                            self.assertEqual(output, oracle)
                    if REFERENCE is not None and unchanged:
                        self.assertTrue(current)
                        self.assertEqual(current, self.reference_bodies(source, level, debug, {"run"}))

    def test_nested_literals_padding_lengths_and_nonzero_defaults(self):
        self.qualify(LITERALS, "1 17 2 4\n0 -2 9 hi\n0 0 0 0\n7 6\n20\n0 0\n")

    def test_fill_runs_once_in_order_including_zero_length(self):
        self.qualify(EFFECTS, "1 1 12 123 123\n0 1234\n", unchanged=True)

    def test_observable_construction_and_assignment_keep_snapshots(self):
        expected = ["2 1\n9 2\n", "19 3\n", "9 5\n", "1 2 3 4 4\n"]
        for (label, source), output in zip(FALLBACKS.items(), expected):
            with self.subTest(case=label):
                self.qualify(source, output, unchanged=True)

    def test_pure_limited_default_and_literal_remove_copy_and_frame_staging(self):
        for initializer, expected in (("default<u32[..128]>()", "0 128\n0\n"), ("[7;128]", "128 128\n14\n")):
            source = f'''recursive fn run()->i64 {{
    let values:u32[..128]={initializer}; print(values.len," ",values.cap);
    if values.len>0 {{ return values[0] as i64+values[127] as i64; }}
    return 0;
}}
fn main() {{ print(run()); }}'''
            self.qualify(source, expected)
            if REFERENCE is None:
                continue
            for level in (0,2):
                for debug in (False,True):
                    with self.subTest(initializer=initializer, level=level, debug=debug):
                        path, stats = self.compile_input(source, level, debug)
                        current = [body for name, body in fv.function_bodies(path, stats) if name.split("#")[0] == "run"]
                        previous = self.reference_bodies(source, level, debug, {"run"})
                        self.assertEqual(len(current),1)
                        self.assertEqual(len(previous),1)
                        before = previous[0][1]
                        self.assertLess(fv.memory_copy_count(current[0]), fv.memory_copy_count(before))
                        self.assertLess(frame_size(current[0]), frame_size(before))

    def test_local_fixed_arrays_and_records_keep_reference_staging(self):
        for initializer, expected in (("default<u32[128]>()", "0\n"), ("[7;128]", "14\n")):
            source = f'''recursive fn run()->i64 {{
    let values:u32[128]={initializer}; return values[0] as i64+values[127] as i64;
}}
fn main() {{ print(run()); }}'''
            with self.subTest(initializer=initializer):
                self.qualify(source, expected, unchanged=True)
        self.qualify('''struct Pair { first:i64, second:i64 }
recursive fn run()->i64 { let pair=Pair { 7,11 }; return pair.first+pair.second; }
fn main() { print(run()); }
''', "18\n", unchanged=True)

    def test_global_initializers_clear_dirty_storage_on_every_start(self):
        import wasmtime
        host = '''const fs=require('node:fs');
const m=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
const imports={};for(const x of WebAssembly.Module.imports(m)){imports[x.module]??={};imports[x.module][x.name]=()=>{};}
const e=new WebAssembly.Instance(m,imports).exports;
for(let i=0;i<3;i++){e._start();if(e.checksum()!==0n||e.literal()!==22n)throw Error('dirty initialization');e.dirty();if(e.checksum()!==101376n)throw Error('dirty fixture');}
'''
        for level in (0,2):
            for debug in (False,True):
                with self.subTest(level=level, debug=debug):
                    path, _ = self.compile_input(GLOBALS, level, debug)
                    result = subprocess.run([strip.NODE,"-e",host,str(path)],capture_output=True,text=True,timeout=30)
                    self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                    engine=wasmtime.Engine(); module=wasmtime.Module.from_file(engine,str(path))
                    store=wasmtime.Store(engine); linker=wasmtime.Linker(engine)
                    for item in module.imports:
                        linker.define_func(item.module,item.name,item.type,lambda *args:None)
                    exports=linker.instantiate(store,module).exports(store)
                    for _ in range(3):
                        exports['_start'](store)
                        self.assertEqual(exports['checksum'](store),0)
                        self.assertEqual(exports['literal'](store),22)
                        exports['dirty'](store)
                        self.assertEqual(exports['checksum'](store),101376)

    def test_contextual_default_capacity_abort_preserves_old_global_and_reentry(self):
        import wasmtime
        host = '''const fs=require('node:fs');
const m=new WebAssembly.Module(fs.readFileSync(process.argv[1]));let e;const observed=[];
const goose={};for(const x of WebAssembly.Module.imports(m))goose[x.name]=()=>{};
goose.abort=(p,n,line)=>observed.push([new TextDecoder().decode(new Uint8Array(e.memory.buffer,p>>>0,n>>>0)),line,String(e.read())]);
e=new WebAssembly.Instance(m,{goose}).exports;
for(let i=0;i<3;i++){e.dirty();let trapped=false;try{e._start();}catch(error){if(!(error instanceof WebAssembly.RuntimeError))throw error;trapped=true;}if(!trapped||e.read()!==107n)throw Error('global changed before abort');}
process.stdout.write(JSON.stringify(observed));
'''
        for level in (0,2):
            for debug in (False,True):
                reference = None
                compilers = [strip.GOOSE]
                if REFERENCE is not None:
                    compilers.insert(0,REFERENCE)
                for compiler in compilers:
                    with self.subTest(level=level, debug=debug, compiler=compiler):
                        selected = strip.GOOSE
                        try:
                            strip.GOOSE = compiler
                            path, _ = self.compile_input(CAPACITY, level, debug)
                        finally:
                            strip.GOOSE = selected
                        result = subprocess.run([strip.NODE,"-e",host,str(path)],capture_output=True,text=True,timeout=30)
                        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                        v8 = json.loads(result.stdout)
                        engine=wasmtime.Engine(); module=wasmtime.Module.from_file(engine,str(path))
                        store=wasmtime.Store(engine); linker=wasmtime.Linker(engine); observed=[]
                        def abort(caller,pointer,length,line):
                            memory=caller.get('memory')
                            observed.append([bytes(memory.read(caller,pointer,pointer+length)).decode(),line,str(exports['read'](caller))])
                        for item in module.imports:
                            if item.name=='abort':
                                linker.define_func(item.module,item.name,item.type,abort,access_caller=True)
                            else:
                                linker.define_func(item.module,item.name,item.type,lambda *args:None)
                        exports=linker.instantiate(store,module).exports(store)
                        for _ in range(3):
                            exports['dirty'](store)
                            with self.assertRaises(wasmtime.Trap):
                                exports['_start'](store)
                            self.assertEqual(exports['read'](store),107)
                        self.assertEqual(v8,observed)
                        self.assertEqual(len(observed),3)
                        for message,line,state in observed:
                            self.assertIn('capacity',message)
                            self.assertEqual(line,2)
                            self.assertEqual(state,'107')
                        if reference is None:
                            reference = observed
                        else:
                            self.assertEqual(observed,reference)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=strip.GOOSE)
    parser.add_argument("--node", default=strip.NODE)
    parser.add_argument("--cc", default=prefix.CC)
    parser.add_argument("--reference-goose", type=Path)
    args, remaining = parser.parse_known_args()
    strip.GOOSE = prefix.GOOSE = args.goose.resolve()
    strip.NODE = args.node
    prefix.CC = args.cc
    if args.reference_goose:
        REFERENCE = fv.REFERENCE = args.reference_goose.resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
