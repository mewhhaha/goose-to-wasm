#!/usr/bin/env python3
"""Qualify guarded descending SIMD chunks and unchanged scalar fallbacks."""
import argparse
import json
from pathlib import Path
import struct
import subprocess
import sys
import unittest

import test_loop_ordinals as ordinal
import test_prefix_resolution as prefix
import test_strip_loops as strip
from test_fill_loops import function_body
from test_static_data import uleb

SOURCE='''var saved:TYPE[:]; var backing:TYPE[8]=[11,22,33,44,55,66,77,88];
export fn run(start:i64,key:TYPE)->i64 {
    let xs=saved; var j=start;
    while j>0 && xs[j-1]>key { xs[j]=xs[j-1]; j--; }
    return j;
}
fn main() { saved=backing[..]; }
'''
WORDS=[11,22,33,44,55,66,77,88]
CASES=[{"start":str(j),"key":0,"length":8,"pointer":"tail","words":WORDS}
       for j in (-2,-1,0,1,2,3,4,5,6,7,8,9,(1<<63)-1,-(1<<63))]
CASES += [{"start":"7","key":key,"length":8,"pointer":"tail","words":WORDS}for key in (77,66,55,44,33)]
CASES += [{"start":"7","key":key,"length":8,"pointer":"tail","words":words}for key,words in (
    (5,[5,5,5,5,5,5,5,0]),(3,[9,9,3,9,9,9,9,0]),
    (0,[0x80000000,0xffffffff,0,1,0x7fffffff,0x80000001,0x7ffffffe,0]),
    (0x80000000,[0,0x7fffffff,0x80000000,0xffffffff,0x80000001,0x80000002,0xfffffffe,0]))]
CASES += [{"start":str(j),"key":0,"length":length,"pointer":pointer,"words":WORDS}
          for j,length,pointer in ((6,8,"unaligned"),(7,8,"unaligned"),(4,0,"tail"),(4,4,"tail"),
                                   (7,8,0xffffffe8),(5,8,0xfffffff0),(4,8,0xfffffff4))]
LONG_WORDS=[10*i for i in range(1,18)]
# Start16 peels four scalar shifts, then reaches one eight-lane SIMD chunk.
CASES += [{"start":"16","key":key,"length":17,"pointer":"tail","words":LONG_WORDS}
          for key in (0,120,110,100,90,80,70,60,50,40,30,20,10)]
# Start15 reaches one eight-lane chunk followed by each scalar tail stop.
CASES += [{"start":"15","key":key,"length":17,"pointer":"tail","words":LONG_WORDS}
          for key in (0,10,20,30)]
CASES += [{"start":"16","key":key,"length":17,"pointer":"tail","words":words}for key,words in (
    (5,[5]*4+[9]*12+[0]),
    (0,[0xffffffff,0x7fffffff,0x80000001,1]*3+[9,10,11,12,0]),
    (0x80000000,[0x80000001+i for i in range(17)]))]
CASES += [{"start":"15","key":0,"length":17,"pointer":"unaligned","words":[1]*17},
          {"start":"24","key":0,"length":32,"pointer":0xffffffc0,"words":LONG_WORDS}]
WIDE_WORDS=[10*i for i in range(1,34)]
# After two vector chunks, starts25..27 leave5..7 for scalar4 plus tail1..3.
CASES += [{"start":str(j),"key":0,"length":33,"pointer":"tail","words":WIDE_WORDS}
          for j in (25,26,27)]
# Start32 peels four, then executes three successful eight-lane chunks.
# Thresholds cover every false position before/after those successes.
CASES += [{"start":"32","key":key,"length":33,"pointer":"tail","words":WIDE_WORDS}
          for key in [0,*range(280,40,-10),40,30,20,10]]
CASES += [{"start":"31","key":key,"length":33,"pointer":"tail","words":WIDE_WORDS}
          for key in (0,10,20,30)]
CASES += [{"start":"32","key":key,"length":33,"pointer":"tail","words":words}for key,words in (
    (5,[5]*4+[9]*28+[0]),
    (0,[0xffffffff,0x7fffffff,0x80000001,1]*7+[9,10,11,12,0]),
    (0x80000000,[0x80000001+i for i in range(33)]))]
CASES += [{"start":"31","key":0,"length":33,"pointer":"unaligned","words":[1]*33},
          {"start":"48","key":0,"length":64,"pointer":0xffffff80,"words":WIDE_WORDS}]
NODE_HOST=r'''
const fs=require("node:fs");
const module_=new WebAssembly.Module(fs.readFileSync(process.argv[1])),cases=JSON.parse(process.argv[2]),goose={};
for(const item of WebAssembly.Module.imports(module_))goose[item.name]=()=>{};
const results=cases.map(scenario=>{
  const e=new WebAssembly.Instance(module_,{goose}).exports;e._start();
  const bytes=Buffer.from(e.memory.buffer),end=bytes.length,pattern=Buffer.alloc(32);
  [11,22,33,44,55,66,77,88].forEach((v,i)=>pattern.writeUInt32LE(v,i*4));
  const backing=bytes.indexOf(pattern);if(backing<0)throw new Error("missing backing");
  const header=Buffer.alloc(8);header.writeUInt32LE(backing);header.writeUInt32LE(8,4);
  const at=bytes.indexOf(header);if(at<0||bytes.indexOf(header,at+1)>=0)throw new Error("header must be unique");
  const windowBytes=(scenario.words.length+2)*4;
  [91,92,...scenario.words].forEach((v,i)=>bytes.writeUInt32LE(v,end-windowBytes+i*4));
  Array.from({length:24},(_,i)=>109+i).forEach((v,i)=>bytes.writeUInt32LE(v,i*4));
  let pointer=scenario.pointer;if(pointer==="tail")pointer=end-scenario.words.length*4;if(pointer==="unaligned")pointer=end-scenario.words.length*4+1;
  bytes.writeUInt32LE(pointer,at);bytes.writeUInt32LE(scenario.length,at+4);
  let trapped=false,result=null;
  try{result=e.run(BigInt(scenario.start),scenario.key).toString();}
  catch(error){if(!(error instanceof WebAssembly.RuntimeError))throw error;trapped=true;}
  return{trapped,result,memory_bytes:end,window:Array.from(bytes.subarray(end-windowBytes)),head:Array.from(bytes.subarray(0,96))};
});process.stdout.write(JSON.stringify(results));
'''


def expected(scenario,size,signed):
    words=[91,92,*scenario["words"]];window_bytes=len(words)*4
    memory=bytearray(size);struct.pack_into("<"+"I"*len(words),memory,size-window_bytes,*words)
    struct.pack_into("<24I",memory,0,*range(109,133));pointer=scenario["pointer"]
    if pointer=="tail":pointer=size-len(scenario["words"])*4
    if pointer=="unaligned":pointer=size-len(scenario["words"])*4+1
    def address(index):
        if not 0<=index<scenario["length"]:raise IndexError()
        return(pointer+index*4)&0xffffffff
    def load(index):
        at=address(index)
        if at+4>size:raise IndexError()
        value=struct.unpack_from("<I",memory,at)[0]
        if signed and value>=1<<31:value-=1<<32
        return value
    key=scenario["key"]
    if signed and key>=1<<31:key-=1<<32
    j=int(scenario["start"]);trapped=False
    try:
        while j>0:
            if load(j-1)<=key:break
            target=address(j);value=load(j-1)
            if target+4>size:raise IndexError()
            struct.pack_into("<I",memory,target,value&0xffffffff);j-=1
    except IndexError:trapped=True
    result=None
    if not trapped:result=str(j)
    return{"trapped":trapped,"result":result,"memory_bytes":size,"window":list(memory[-window_bytes:]),"head":list(memory[:96])}


def wasmtime_run(path):
    import wasmtime
    engine=wasmtime.Engine();module=wasmtime.Module.from_file(engine,str(path));results=[]
    for scenario in CASES:
        store=wasmtime.Store(engine);linker=wasmtime.Linker(engine)
        for item in module.imports:linker.define_func(item.module,item.name,item.type,lambda *args:None)
        e=linker.instantiate(store,module).exports(store);e["_start"](store);memory=e["memory"];image=bytes(memory.read(store));size=len(image)
        backing=image.find(struct.pack("<8I",*WORDS));assert backing>=0
        header=struct.pack("<II",backing,8);at=image.find(header);assert at>=0 and image.find(header,at+1)<0
        words=[91,92,*scenario["words"]];window_bytes=len(words)*4
        memory.write(store,struct.pack("<"+"I"*len(words),*words),size-window_bytes)
        memory.write(store,struct.pack("<24I",*range(109,133)),0)
        pointer=scenario["pointer"]
        if pointer=="tail":pointer=size-len(scenario["words"])*4
        if pointer=="unaligned":pointer=size-len(scenario["words"])*4+1
        memory.write(store,struct.pack("<II",pointer,scenario["length"]),at);key=scenario["key"]
        if key>=1<<31:key-=1<<32
        trapped=False;result=None
        try:result=str(e["run"](store,int(scenario["start"]),key))
        except wasmtime.Trap:trapped=True
        image=bytes(memory.read(store));results.append({"trapped":trapped,"result":result,"memory_bytes":size,"window":list(image[-window_bytes:]),"head":list(image[:96])})
    return results


def simd_ops(body):
    groups,offset=uleb(body,0)
    for _ in range(groups):_,offset=uleb(body,offset);offset+=1
    while offset<len(body):
        op=body[offset];offset+=1
        if op==0xfd:
            sub,offset=uleb(body,offset);yield sub
            if sub in (0,0xb):_,offset=uleb(body,offset);_,offset=uleb(body,offset)
            else:assert sub in (0x11,0x3b,0x3c,0x4e,0xa3),hex(sub)
        elif op in (2,3,4,0xc,0xd,0x10,0x20,0x21,0x22,0x23,0x24,0x3f,0x40,0x41,0x42):_,offset=uleb(body,offset)
        elif op==0x11 or 0x28<=op<=0x3e:_,offset=uleb(body,offset);_,offset=uleb(body,offset)
        elif op==0xfc:
            sub,offset=uleb(body,offset)
            for _ in range({10:2,11:1}[sub]):_,offset=uleb(body,offset)
        else:assert op in (0,1,5,0xb,0xf,0x1a,0x1b)or 0x45<=op<=0xc4,hex(op)


class DescendingSimd(unittest.TestCase):
    setUp=strip.StripLoops.setUp;compile=strip.StripLoops.compile
    native=prefix.PrefixResolution.native;qualify=ordinal.LoopOrdinals.qualify

    def test_ordered_results_and_traps_for_signed_unsigned_and_unaligned_chunks(self):
        for storage,signed in (("i32",True),("u32",False)):
            for level in (0,2):
                for debug in (False,True):
                    path,stats=self.compile(level,text=SOURCE.replace("TYPE",storage),debug=debug)
                    ops=list(simd_ops(function_body(path,stats,"run")))
                    compare=0x3b
                    if not signed:compare=0x3c
                    for op in (0,0xb,compare):self.assertEqual(ops.count(op),2)
                    for op in (0x11,0x4e,0xa3):self.assertEqual(ops.count(op),1)
                    node=subprocess.run([strip.NODE,"-e",NODE_HOST,str(path),json.dumps(CASES)],capture_output=True,text=True,timeout=60)
                    self.assertEqual(node.returncode,0,node.stdout+node.stderr)
                    for engine,results in (("v8",json.loads(node.stdout)),("wasmtime",wasmtime_run(path))):
                        for scenario,observed in zip(CASES,results,strict=True):
                            with self.subTest(storage=storage,level=level,debug=debug,engine=engine,scenario=scenario):
                                self.assertEqual(observed,expected(scenario,observed["memory_bytes"],signed))

    def test_aliasable_key_stays_scalar_and_observes_the_first_store(self):
        source='''recursive fn alias()->i64 {
    var values:i32[8]=[11,22,33,44,55,66,77,0];let xs=values[..];let key:i32& =xs[7];var j=7;
    while j>0 && xs[j-1]>key { xs[j]=xs[j-1];j--; } print(values);return j;
} fn main() { print(alias()); }'''
        self.qualify(source,"[11, 22, 33, 44, 55, 66, 77, 77]\n6\n")
        for level in (0,2):
            path,stats=self.compile(level,text=source);self.assertEqual(list(simd_ops(function_body(path,stats,"alias"))),[])

    def test_region_cursors_without_prefix_maps_keep_simd_and_prefix_maps_reject_it(self):
        source="var reserve:i32[>..]=[7];\n"+SOURCE.replace("TYPE","i32")
        mapping=prefix.ENABLE+'''struct Packet { head:i32[8],tail:i32[>..] }
recursive fn make()->Packet { return Packet {[1,2,3,4,5,6,7,8],[9]}; }
var held=make();\n'''+source
        for level in (0,2):
            path,stats=self.compile(level,text=source);self.assertGreater(stats["region_count"],0)
            self.assertIn(0xa3,list(simd_ops(function_body(path,stats,"run"))))
            path,stats=self.compile(level,text=mapping);self.assertGreater(stats["region_count"],0)
            self.assertEqual(list(simd_ops(function_body(path,stats,"run"))),[])

    def test_other_storage_and_addressed_or_captured_keys_keep_scalar_paths(self):
        for storage in ("i16","u16","i64","u64","f32","f64"):
            for level in (0,2):
                path,stats=self.compile(level,text=SOURCE.replace("TYPE",storage))
                self.assertEqual(list(simd_ops(function_body(path,stats,"run"))),[])
        for prefix_,suffix in (("let retained:const i32& =key;","return j+(retained as i64);"),
                               ("recursive fn read_key()->i32 { return key; }","return j+(read_key() as i64);")):
            source=SOURCE.replace("TYPE","i32").replace("let xs=saved;",prefix_+" let xs=saved;").replace("return j;",suffix)
            for level in (0,2):
                path,stats=self.compile(level,text=source)
                self.assertEqual(list(simd_ops(function_body(path,stats,"run"))),[])


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--goose",type=Path,default=strip.GOOSE)
    parser.add_argument("--node",default=strip.NODE);parser.add_argument("--cc",default=prefix.CC);args,remaining=parser.parse_known_args()
    strip.GOOSE=prefix.GOOSE=args.goose.resolve();strip.NODE=args.node;prefix.CC=args.cc
    unittest.main(argv=[sys.argv[0],*remaining])
