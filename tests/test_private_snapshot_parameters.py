#!/usr/bin/env python3
"""Qualify borrowing a private caller snapshot instead of copying it again."""
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

ROOT=Path(__file__).resolve().parents[1]
REFERENCE=None
ORDER='''struct Pair { first:i64, second:i64 }
var source=Pair { 1,2 };
fn first()->Pair { source }
fn second()->Pair { source.first=99; return source; }
recursive fn receive(a:Pair,b:Pair,n:i64)->i64 { a.first*100+b.first*10+n }
fn main() { print(receive(first(),second(),7)," ",source.first); }
'''
SLICES='''struct Name { text:u8[..12] }
recursive fn compare(a:const u8[:],b:const u8[:])->i64 {
    var count=a.len; if b.len<count { count=b.len; }
    for i in count {
        if a[i]<b[i] { return -1; }
        if a[i]>b[i] { return 1; }
    }
    return a.len-b.len;
}
recursive fn names(a:Name,b:Name)->i64 { compare(a.text[..],b.text[..]) }
fn main() { print(names(Name { "ada" },Name { "grace" })); }
'''
RECURSION='''struct Pair { first:i64, second:i64 }
recursive fn descend(p:Pair,n:i64)->i64 {
    if n==0 { return p.first; }
    var local=p; local.first+=n;
    let result=descend(local,n-1); return result+p.first;
}
recursive fn mutate(var p:Pair)->i64 { p.first+=10; return p.first+p.second; }
recursive fn isolated(var a:Pair,var b:Pair)->i64 { a.first=9; return a.first*100+b.first; }
fn main() {
    let original=Pair { 1,2 };
    print(descend(original,3)," ",mutate(original)," ",descend(original,0)," ",original.first);
    print(isolated(original,original)," ",original.first);
}
'''
FALLBACKS={
    'owner-parameter':('''recursive fn length(xs:i64[>..])->i64 { xs.len }
fn main() { var xs:i64[>..]=[1,2]; print(length(copy(xs))); }
''','2\n',{'length'}),
    'aggregate-result':('''struct Pair { first:i64, second:i64 }
recursive fn identity(p:Pair)->Pair { p }
fn main() { let p=identity(Pair { 3,4 }); print(p.first+p.second); }
''','7\n',{'identity'}),
    'borrowed-result':('''struct Pair { first:i64, second:i64 }
var backing:u8[2]=[4,5];
recursive fn borrowed(p:Pair)->const u8[:] { if p.first>0 { return backing[..]; } return backing[..0]; }
fn main() { let view=borrowed(Pair { 1,2 }); print(view[0]," ",view.len); }
''','4 2\n',{'borrowed'}),
    'captured-callee':('''struct Pair { first:i64, second:i64 }
fn main() {
    let bonus=9;
    recursive fn captured(p:Pair)->i64 { p.first+bonus }
    print(captured(Pair { 1,2 }));
}
''','10\n',{'captured'}),
    'reference-exposure':('''struct Pair { first:i64, second:i64 }
recursive fn bump(value:i64&) { value++; }
recursive fn exposed(p:Pair)->i64 { bump(p.first); return p.first+p.second; }
fn main() { let p=Pair { 1,2 }; print(exposed(p)," ",p.first); }
''','4 1\n',{'exposed'}),
    'dispatch-incoming-edge':('''enum Choice { A { value:i64 }, B { value:i64 } }
recursive fn score(c:Choice.A)->i64 { c.value+1 }
recursive fn score(c:Choice.B)->i64 { c.value+2 }
recursive fn selected(c:Choice)->i64 { score(c) }
fn main() {
    let c:Choice=Choice.B { 7 };
    print(selected(c)," ",score(Choice.A { 3 }));
}
''','9 4\n',{'score'}),
}
REENTRY='''struct Pair { first:i64, second:i64 }
var source=Pair { 1,2 };
export fn change() { source.first=90; }
recursive fn hold(p:Pair)->i64 { print(p.first); return p.first; }
fn main() { print(hold(source)," ",source.first); }
'''
TRAP='''var later_calls:i64=0; var entered:i64=0;
recursive fn receive(xs:u8[..1],n:i64)->i64 { entered=1; return xs.len+n; }
fn later()->i64 { later_calls++; return 7; }
export fn attempt()->i64 { let wide:u8[..2]=[1,2]; return receive(wide[..],later()); }
export fn state()->i64 { later_calls*10+entered }
fn main() {}
'''
ESCAPE='''struct Name { text:u8[..12] }
var saved:const u8[:];
recursive fn escape(p:Name) { saved=p.text[..]; }
fn main() { escape(Name { "ada" }); }
'''
NODE_HOST=r'''const fs=require('node:fs');
const [path,mode]=process.argv.slice(1);const m=new WebAssembly.Module(fs.readFileSync(path));
let e,output='',changed=false;const aborts=[];const goose={};
for(const i of WebAssembly.Module.imports(m))goose[i.name]=()=>{};
goose.print_i64=n=>{if(mode==='reentry'&&!changed){changed=true;e.change();}output+=String(n);};
goose.write=(p,n)=>{output+=new TextDecoder().decode(new Uint8Array(e.memory.buffer,p>>>0,n>>>0));};
goose.newline=()=>{output+='\n';};
goose.abort=(p,n,line)=>aborts.push({message:new TextDecoder().decode(new Uint8Array(e.memory.buffer,p>>>0,n>>>0)),line,state:String(e.state())});
e=new WebAssembly.Instance(m,{goose}).exports;e._start();
let trapped=false;if(mode==='trap'){try{e.attempt();}catch(error){if(!(error instanceof WebAssembly.RuntimeError))throw error;trapped=true;}}
const result={output,changed,trapped,aborts};if(mode==='trap')result.state=String(e.state());
process.stdout.write(JSON.stringify(result));
'''


def frame_bytes(body):
    groups,offset=uleb(body,0)
    for _ in range(groups):
        _,offset=uleb(body,offset);offset+=1
    if body[offset:offset+2]!=b'\x23\x00':
        raise AssertionError('expected activation-base global.get')
    offset+=2;op=body[offset];local,offset=uleb(body,offset+1)
    if op==0x21:
        if body[offset]!=0x20:return 0
        read,offset=uleb(body,offset+1)
        if read!=local:raise AssertionError('activation-base local differs')
    elif op!=0x22:raise AssertionError('expected activation-base local.set/tee')
    if body[offset]!=0x41:return 0
    size,offset=uleb(body,offset+1)
    if body[offset]!=0x6a:raise AssertionError('expected frame reservation addition')
    return size


class PrivateSnapshotParameters(unittest.TestCase):
    setUp=fv.FunctionValueForwarding.setUp
    compile=fv.FunctionValueForwarding.compile
    compile_file=fv.FunctionValueForwarding.compile_file
    compile_input=fv.FunctionValueForwarding.compile_input
    native=fv.FunctionValueForwarding.native
    run_engines=fv.FunctionValueForwarding.run_engines
    reference_bodies=fv.FunctionValueForwarding.reference_bodies

    def qualify(self,source,expected,optimized=None,unchanged=None):
        if optimized is None:optimized={}
        if unchanged is None:unchanged=set()
        for level in (0,2):
            for debug in (False,True):
                with self.subTest(level=level,debug=debug):
                    path,stats=self.compile_input(source,level,debug)
                    current=list(fv.function_bodies(path,stats))
                    oracle=self.native(source,level,debug);self.assertEqual(oracle,expected)
                    for engine,output in self.run_engines(path):
                        with self.subTest(engine=engine):self.assertEqual(output,oracle)
                    for name,count in optimized.items():
                        selected=[body for symbol,body in current if symbol.split('#')[0]==name]
                        self.assertTrue(selected,name)
                        for body in selected:self.assertEqual(fv.memory_copy_count(body),count)
                    if REFERENCE is None:continue
                    previous=self.reference_bodies(source,level,debug,None)
                    self.assertEqual([name for name,_ in current],[name for name,_ in previous])
                    for (name,body),(_,before) in zip(current,previous):
                        symbol=name.split('#')[0]
                        if symbol in unchanged:self.assertEqual(body,before,name)
                        if symbol in optimized:
                            self.assertLess(fv.memory_copy_count(body),fv.memory_copy_count(before),name)
                            self.assertLess(frame_bytes(body),frame_bytes(before),name)

    def test_argument_order_duplicate_aliases_and_fv_named_tail_keep_first_copy(self):
        self.qualify(ORDER,'1097 99\n',{'receive':0},{'main'})
        callback=ORDER.replace('fn main()', 'fn invoke<F>(a:Pair,b:Pair,n:i64) { F(a,b,n) }\nfn main()').replace(
            'receive(first(),second(),7)','invoke(first(),second(),7) { a,b,n=>receive(a,b,n) }')
        self.qualify(callback,'1097 99\n',{'receive':0},{'main'})

    def test_recursive_siblings_and_mutable_parameters_keep_private_values(self):
        self.qualify(RECURSION,'18 13 1 1\n901 1\n',{'isolated':0})

    def test_local_slice_reads_through_checked_scalar_callee_need_no_second_copy(self):
        self.qualify(SLICES,'-1\n',{'names':0},{'main','compare'})

    def test_unproved_incoming_edges_and_escaping_signatures_stay_staged(self):
        for label,(source,expected,names) in FALLBACKS.items():
            with self.subTest(case=label):self.qualify(source,expected,unchanged=names)

    def observations(self,path,mode):
        import wasmtime
        result=subprocess.run([strip.NODE,'-e',NODE_HOST,str(path),mode],capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        v8=json.loads(result.stdout)
        engine=wasmtime.Engine();module=wasmtime.Module.from_file(engine,str(path))
        store=wasmtime.Store(engine);linker=wasmtime.Linker(engine);output=[];aborts=[];changed=False
        def number(caller,value):
            nonlocal changed
            if mode=='reentry' and not changed:
                changed=True;exports['change'](caller)
            output.append(str(value))
        def write(caller,pointer,length):
            pointer&=0xffffffff;memory=caller.get('memory')
            output.append(bytes(memory.read(caller,pointer,pointer+length)).decode())
        def abort(caller,pointer,length,line):
            pointer&=0xffffffff;memory=caller.get('memory')
            aborts.append({'message':bytes(memory.read(caller,pointer,pointer+length)).decode(),
                           'line':line,'state':str(exports['state'](caller))})
        for item in module.imports:
            if item.name=='print_i64':linker.define_func(item.module,item.name,item.type,number,access_caller=True)
            elif item.name=='write':linker.define_func(item.module,item.name,item.type,write,access_caller=True)
            elif item.name=='abort':linker.define_func(item.module,item.name,item.type,abort,access_caller=True)
            elif item.name=='newline':linker.define_func(item.module,item.name,item.type,lambda:output.append('\n'))
            else:linker.define_func(item.module,item.name,item.type,lambda *args:None)
        exports=linker.instantiate(store,module).exports(store);exports['_start'](store);trapped=False
        if mode=='trap':
            try:exports['attempt'](store)
            except wasmtime.Trap:trapped=True
        observed={'output':''.join(output),'changed':changed,'trapped':trapped,'aborts':aborts}
        if mode=='trap':observed['state']=str(exports['state'](store))
        self.assertEqual(v8,observed)
        return observed

    def test_host_reentry_and_argument_conversion_traps_keep_snapshot_state(self):
        for mode,source in [('reentry',REENTRY),('trap',TRAP)]:
            for level in (0,2):
                for debug in (False,True):
                    reference=None;compilers=[strip.GOOSE]
                    if REFERENCE is not None:compilers.insert(0,REFERENCE)
                    for compiler in compilers:
                        with self.subTest(mode=mode,level=level,debug=debug,compiler=compiler):
                            selected=strip.GOOSE
                            try:
                                strip.GOOSE=compiler;path,stats=self.compile_input(source,level,debug)
                            finally:strip.GOOSE=selected
                            if mode=='reentry' and compiler==selected:
                                bodies=[body for name,body in fv.function_bodies(path,stats) if name.split('#')[0]=='hold']
                                self.assertEqual(len(bodies),1)
                                self.assertEqual(fv.memory_copy_count(bodies[0]),0)
                            observed=self.observations(path,mode)
                            if mode=='reentry':
                                self.assertEqual(observed,{'output':'1\n1 90\n','changed':True,'trapped':False,'aborts':[]})
                            else:
                                self.assertTrue(observed['trapped']);self.assertEqual(observed['state'],'0')
                                self.assertEqual(len(observed['aborts']),1)
                                self.assertIn('capacity',observed['aborts'][0]['message'])
                                self.assertEqual(observed['aborts'][0]['state'],'0')
                            if reference is None:reference=observed
                            else:self.assertEqual(observed,reference)

    def test_checker_rejects_a_parameter_slice_escaping_into_a_global(self):
        source=self.work/'escape.goose';source.write_text(ESCAPE)
        compilers=[strip.GOOSE]
        if REFERENCE is not None:compilers.append(REFERENCE)
        for compiler in compilers:
            for level in (0,2):
                for debug in (False,True):
                    with self.subTest(compiler=compiler,level=level,debug=debug):
                        output=self.work/'escape.wasm';output.unlink(missing_ok=True)
                        command=[str(compiler),str(source),'--offline','--target','wasm-direct',f'-O{level}','-o',str(output)]
                        if debug:command.append('--debug')
                        result=subprocess.run(command,capture_output=True,text=True,timeout=60)
                        self.assertNotEqual(result.returncode,0);self.assertFalse(output.exists())
                        self.assertRegex(result.stdout+result.stderr,r'(?i)(outlive|lifetime|escape|borrow|root|reference)')

    def test_functions_named_comparator_removes_only_callee_staging(self):
        source=ROOT/'examples/functions.goose';expected=(ROOT/'examples/expected/functions.out').read_text()
        self.qualify(source,expected,{'by_name':0})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--goose',type=Path,default=strip.GOOSE)
    parser.add_argument('--node',default=strip.NODE);parser.add_argument('--cc',default=prefix.CC)
    parser.add_argument('--reference-goose',type=Path)
    args,remaining=parser.parse_known_args();strip.GOOSE=prefix.GOOSE=args.goose.resolve()
    strip.NODE=args.node;prefix.CC=args.cc
    if args.reference_goose:REFERENCE=fv.REFERENCE=args.reference_goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
