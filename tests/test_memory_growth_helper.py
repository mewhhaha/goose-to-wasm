#!/usr/bin/env python3
"""Qualify shared growth arithmetic, capacity boundaries and caller-side aborts."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from test_function_value_forwarding import function_bodies
from test_static_data import sections, uleb
from test_strip_loops import instructions

ROOT = Path(__file__).resolve().parents[1]
GOOSE = ROOT/"build/bin/goose"
REFERENCE = None
NODE = "node"
FAILURE = '''var observed:i64=0;
export fn read()->i64 { observed }
export fn peek()->i64 { observed+1 }
recursive fn huge(n:i64)->i64 {
    var bytes:u8[70000]=[0;70000]; bytes[0]=n as u8; bytes[69999]=7;
    return bytes[0] as i64+bytes[69999] as i64;
}
export fn attempt()->i64 { observed=7; return huge(5); }
fn main() {}
'''
BODY_FAILURE = '''var observed:i64=0;
export fn read()->i64 { observed }
export fn peek()->i64 { observed+1 }
recursive fn attempt(xs:u8[:])->i64 { observed=7; print(xs); return observed; }
fn main() { var empty:u8[0]; attempt(empty[..]); observed=0; }
'''
BOUNDARIES = '\n'.join(
    f'export fn touch{size}()->i64 {{ var xs:u8[{size}]; xs[0]=3; xs[{size-1}]=7; return xs[0] as i64+xs[{size-1}] as i64; }}'
    for size in (64000,65536,131072)
)+'\nfn main() {}\n'
MIXED = '''var rows:u8[>..]=[17,34,51];
export fn count()->i64 { rows.len }
export fn first()->u8 { rows[0] }
fn main() {}
'''
TOPS = [65537,131072,0x7fffffff,0x80000000,0xffffffff]
NODE_HOST = r'''
const fs=require('node:fs');const [path,mode,helper]=process.argv.slice(1);
const module_=new WebAssembly.Module(fs.readFileSync(path));let e;const aborts=[];
const goose=Object.fromEntries(WebAssembly.Module.imports(module_).map(i=>[i.name,()=>{}]));
goose.abort=(p,n,line)=>aborts.push({message:new TextDecoder().decode(new Uint8Array(e.memory.buffer,p>>>0,n>>>0)),line,
state:String(e.read()),reentry:String(e.peek()),pages:e.memory.buffer.byteLength/65536});
e=new WebAssembly.Instance(module_,{goose}).exports;e._start();
let output={pages:e.memory.buffer.byteLength/65536};
if(mode==='boundaries') {
 output={values:[],pages:[e.memory.buffer.byteLength/65536]};
 for(const size of [64000,65536,131072]) {output.values.push(String(e['touch'+size]()));output.pages.push(e.memory.buffer.byteLength/65536);}
} else if(mode==='failure') {
 let trapped=false,helper_on_stack=false;
 try {
  if(e.attempt.length) e.attempt(70000n<<32n);
  else e.attempt();
 } catch(error) {if(!(error instanceof WebAssembly.RuntimeError))throw error;trapped=true;helper_on_stack=error.stack.includes('wasm-function['+helper+']');}
 output={trapped,helper_on_stack,aborts,state:String(e.read()),reentry:String(e.peek()),pages:e.memory.buffer.byteLength/65536};
} else if(mode==='body-success') {
 const value=e.attempt(70000n<<32n);
 output={value:String(value),state:String(e.read()),reentry:String(e.peek()),pages:e.memory.buffer.byteLength/65536,aborts};
} else if(mode==='mixed') {output.count=String(e.count());output.first=e.first();}
process.stdout.write(JSON.stringify(output));
'''


def unsigned(value):
    result=bytearray()
    while value>=128:
        result.append((value&127)|128);value>>=7
    result.append(value)
    return bytes(result)


def section(kind,payload):
    return bytes([kind])+unsigned(len(payload))+payload


def one_page_maximum(data):
    offset=8
    while offset<len(data):
        kind=data[offset];size,start=uleb(data,offset+1);end=start+size
        if kind==5:
            assert data[start:end]==bytes([1,1,1,16]),'expected one memory with min1/max16'
            return data[:end-1]+b'\x01'+data[end:]
        offset=end
    raise AssertionError('memory section missing')


def expose_attempt(data,index):
    # Public Goose exports reject slice parameters. Expose this already
    # reachable private function only in the test module; its packed-i64 ABI,
    # body and all function indices remain unchanged.
    offset=8
    while offset<len(data):
        kind=data[offset];size,start=uleb(data,offset+1);end=start+size
        if kind==7:
            count,entries=uleb(data,start)
            payload=unsigned(count+1)+data[entries:end]+b'\x07attempt\x00'+unsigned(index)
            return data[:offset]+section(7,payload)+data[end:]
        offset=end
    raise AssertionError('export section missing')


class MemoryGrowthHelper(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(dir=ROOT/'build');self.addCleanup(self.tmp.cleanup)
        self.work=Path(self.tmp.name)

    def compile(self,source,level=2,debug=False,compiler=None):
        if compiler is None:compiler=GOOSE
        path=self.work/'main.goose';path.write_text(source)
        wasm=self.work/'program.wasm';stats=self.work/'stats.json'
        command=[str(compiler),str(path),'--offline','--target','wasm-direct',f'-O{level}',
                 '--wasm-initial-pages','1','--wasm-max-pages','16','--wasm-stats',str(stats),'-o',str(wasm)]
        if debug:command.append('--debug')
        result=subprocess.run(command,capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        info=json.loads(stats.read_text())
        if source==BODY_FAILURE:
            index=next(row['index'] for row in info['function_info'] if row['name'].split('#')[0]=='attempt')
            wasm.write_bytes(expose_attempt(wasm.read_bytes(),index))
        return wasm,info

    def v8(self,path,mode,helper=-1):
        result=subprocess.run([NODE,'-e',NODE_HOST,str(path),mode,str(helper)],capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        return json.loads(result.stdout)

    def wasmtime(self,path,mode,limited=False):
        import wasmtime
        engine=wasmtime.Engine();module=wasmtime.Module.from_file(engine,str(path));store=wasmtime.Store(engine)
        if limited:store.set_limits(memory_size=65536)
        linker=wasmtime.Linker(engine);aborts=[];exports=None
        def abort(caller,pointer,length,line):
            memory=caller.get('memory')
            aborts.append({'message':bytes(memory.read(caller,pointer,pointer+length)).decode(),'line':line,
                           'state':str(exports['read'](caller)),'reentry':str(exports['peek'](caller)),
                           'pages':memory.size(caller)})
        for item in module.imports:
            if item.name=='abort':linker.define_func(item.module,item.name,item.type,abort,access_caller=True)
            else:linker.define_func(item.module,item.name,item.type,lambda *args:None)
        exports=linker.instantiate(store,module).exports(store);exports['_start'](store);memory=exports['memory']
        output={'pages':memory.size(store)}
        if mode=='boundaries':
            output={'values':[],'pages':[memory.size(store)]}
            for size in (64000,65536,131072):
                output['values'].append(str(exports['touch'+str(size)](store)));output['pages'].append(memory.size(store))
        elif mode=='failure':
            trapped=False;helper_on_stack=False
            try:
                if exports['attempt'].type(store).params:exports['attempt'](store,70000<<32)
                else:exports['attempt'](store)
            except wasmtime.Trap as error:
                trapped=True;helper_on_stack=any(frame.func_name=='grow_memory' for frame in error.frames)
            output={'trapped':trapped,'helper_on_stack':helper_on_stack,'aborts':aborts,
                    'state':str(exports['read'](store)),'reentry':str(exports['peek'](store)),'pages':memory.size(store)}
        elif mode=='body-success':
            value=exports['attempt'](store,70000<<32)
            output={'value':str(value),'state':str(exports['read'](store)),'reentry':str(exports['peek'](store)),
                    'pages':memory.size(store),'aborts':aborts}
        elif mode=='mixed':output.update(count=str(exports['count'](store)),first=exports['first'](store))
        return output

    def test_absent_shared_and_mixed_uleb_helper_indices_validate(self):
        for source,shared,uleb_helper,mode in [('fn main() {}',False,False,'validate'),
                                             (BOUNDARIES,False,False,'validate'),
                                             (BODY_FAILURE,True,False,'validate'),(MIXED,True,True,'mixed')]:
            path,stats=self.compile(source)
            names={row['name'] for row in stats['function_info']}
            self.assertEqual('grow_memory' in names,shared)
            self.assertEqual('read_uleb_array' in names,uleb_helper)
            self.assertEqual(self.v8(path,mode),self.wasmtime(path,mode))

    def test_fixed_frames_grow_at_page_boundaries(self):
        expected={'values':['10','10','10'],'pages':[1,1,2,3]}
        for level in (0,2):
            for debug in (False,True):
                for compiler in self.compilers():
                    with self.subTest(level=level,debug=debug,compiler=compiler):
                        path,_=self.compile(BOUNDARIES,level,debug,compiler)
                        self.assertEqual(self.v8(path,'boundaries'),expected)
                        self.assertEqual(self.wasmtime(path,'boundaries'),expected)

    def compilers(self):
        result=[GOOSE]
        if REFERENCE is not None:result.append(REFERENCE)
        return result

    def test_growth_failure_keeps_caller_abort_line_state_and_reentry(self):
        expected={'trapped':True,'helper_on_stack':False,'state':'7','reentry':'8','pages':1,
                  'aborts':[{'message':'linear memory exhausted','line':4,'state':'7','reentry':'8','pages':1}]}
        for level in (0,2):
            for debug in (False,True):
                for compiler in self.compilers():
                    for label,source in [('inline-frame',FAILURE),('shared-body',BODY_FAILURE)]:
                        with self.subTest(level=level,debug=debug,compiler=compiler,fixture=label):
                            path,stats=self.compile(source,level,debug,compiler)
                            self.assertEqual(self.wasmtime(path,'failure',limited=True),expected)
                            data=one_page_maximum(path.read_bytes());path.write_bytes(data)
                            helper=-1
                            for row in stats['function_info']:
                                if row['name']=='grow_memory':helper=row['index']
                            self.assertEqual(self.v8(path,'failure',helper),expected)
                            self.assertEqual(self.wasmtime(path,'failure'),expected)

    def test_body_growth_precedes_copy_and_preserves_success_observables(self):
        expected={'value':'7','state':'7','reentry':'8','pages':2,'aborts':[]}
        for compiler in self.compilers():
            path,_=self.compile(BODY_FAILURE,compiler=compiler)
            self.assertEqual(self.v8(path,'body-success'),expected)
            self.assertEqual(self.wasmtime(path,'body-success'),expected)

    def test_actual_helper_unsigned_rounding_without_large_allocations(self):
        path,stats=self.compile(BODY_FAILURE)
        body=next(body for name,body in function_bodies(path,stats) if name=='grow_memory')
        self.assertEqual(list(instructions(body)).count(0x40),1)
        self.assertEqual(body[-6:],bytes.fromhex('4000417f460b'))
        # Actual helper instructions; only memory.grow0 becomes call0, also two bytes.
        probe_body=body[:-6]+bytes.fromhex('1000')+body[-4:]
        module=(b'\0asm\1\0\0\0'+section(1,bytes.fromhex('0160017f017f'))+
                section(2,b'\x01\x05probe\x05delta\x00\x00')+section(3,b'\x01\x00')+
                section(5,b'\x01\x01\x01\x01')+section(7,b'\x01\x04grow\x00\x01')+
                section(10,b'\x01'+unsigned(len(probe_body))+probe_body))
        probe=self.work/'arithmetic.wasm';probe.write_bytes(module)
        expected=[(top+65535)//65536-1 for top in TOPS]
        import wasmtime
        engine=wasmtime.Engine();store=wasmtime.Store(engine);recorded=[];linker=wasmtime.Linker(engine)
        def delta(pages):recorded.append(pages&0xffffffff);return 1
        linker.define_func('probe','delta',wasmtime.FuncType([wasmtime.ValType.i32()],[wasmtime.ValType.i32()]),delta)
        exports=linker.instantiate(store,wasmtime.Module(engine,module)).exports(store)
        for top in TOPS:
            signed=top
            if signed>=1<<31:signed-=1<<32
            self.assertEqual(exports['grow'](store,signed),0)
        self.assertEqual(recorded,expected)
        host="const fs=require('node:fs');const delta=[];const e=new WebAssembly.Instance(new WebAssembly.Module(fs.readFileSync(process.argv[1])),{probe:{delta:n=>{delta.push(n>>>0);return 1;}}}).exports;for(const n of JSON.parse(process.argv[2]))if(e.grow(n)!==0)throw Error('failed');process.stdout.write(JSON.stringify(delta));"
        result=subprocess.run([NODE,'-e',host,str(probe),json.dumps(TOPS)],capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr);self.assertEqual(json.loads(result.stdout),expected)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--goose',type=Path,default=GOOSE)
    parser.add_argument('--node',default=NODE);parser.add_argument('--reference-goose',type=Path)
    args,remaining=parser.parse_known_args();GOOSE=args.goose.resolve();NODE=args.node
    if args.reference_goose:REFERENCE=args.reference_goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
