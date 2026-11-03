#!/usr/bin/env python3
"""Qualify descending groups, scalar tails, traps and overlapping-view fallbacks."""
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

SOURCE='''var saved:i64[:]; var secondary:i64[:];
var backing:i64[8]=[11,22,33,44,55,66,77,88];
var other:i64[8]=[201,202,203,204,205,206,207,208];
export fn run(start:i64,key:i64)->i64 {
    let xs=saved; let dst=secondary; var j=start;
    while j>0 && xs[j-1]>key { DEST[j]=xs[j-1]; j--; }
    return j;
}
fn main() { saved=backing[..]; secondary=other[..]; }
'''
CASES=[{"pointer":"tail","length":8,"start":j,"key":0} for j in (-2,-1,0,1,2,3,4,5,6,7,8,9,(1<<63)-1,-(1<<63))]
CASES += [{"pointer":"tail","length":8,"start":7,"key":key} for key in (77,66,55,44,33)]
CASES += [{"pointer":"tail","length":length,"start":start,"key":0} for length,start in ((0,1),(3,3),(4,4),(5,6))]
CASES += [{"pointer":pointer,"length":8,"start":start,"key":-1} for pointer,start in ((0xfffffff0,3),(0xffffffe8,4),(0xffffffd0,7))]

NODE_HOST=r'''
const fs=require("node:fs");
const module_=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
const cases=JSON.parse(process.argv[2]),goose={};
for(const item of WebAssembly.Module.imports(module_)) goose[item.name]=()=>{};
const results=cases.map(scenario=>{
  const e=new WebAssembly.Instance(module_,{goose}).exports; e._start();
  const bytes=Buffer.from(e.memory.buffer),end=bytes.length;
  const headerFor=values=>{
    const pattern=Buffer.alloc(64); values.forEach((v,i)=>pattern.writeBigInt64LE(BigInt(v),i*8));
    const base=bytes.indexOf(pattern); if(base<0) throw new Error("missing backing");
    const header=Buffer.alloc(8); header.writeUInt32LE(base); header.writeUInt32LE(8,4);
    const at=bytes.indexOf(header);
    if(at<0 || bytes.indexOf(header,at+1)>=0) throw new Error("header must be unique");
    return at;
  };
  const source=headerFor([11,22,33,44,55,66,77,88]),dest=headerFor([201,202,203,204,205,206,207,208]);
  [91,92,11,22,33,44,55,66,77,88].forEach((v,i)=>bytes.writeBigInt64LE(BigInt(v),end-80+i*8));
  [109,110].forEach((v,i)=>bytes.writeBigInt64LE(BigInt(v),i*8));
  let pointer=scenario.pointer;
  if(pointer==="tail") pointer=end-64;
  bytes.writeUInt32LE(pointer,source); bytes.writeUInt32LE(scenario.length,source+4);
  bytes.writeUInt32LE((pointer-16)>>>0,dest); bytes.writeUInt32LE(scenario.length,dest+4);
  let trapped=false,result=null;
  try {result=e.run(BigInt(scenario.start),BigInt(scenario.key)).toString();}
  catch(error) {if(!(error instanceof WebAssembly.RuntimeError)) throw error; trapped=true;}
  return {trapped,result,memory_bytes:end,window:Array.from({length:10},(_,i)=>bytes.readBigInt64LE(end-80+i*8).toString()),head:[0,1].map(i=>bytes.readBigInt64LE(i*8).toString())};
});
process.stdout.write(JSON.stringify(results));
'''


def expected(scenario,size,overlap):
    memory=bytearray(size); struct.pack_into("<10q",memory,size-80,91,92,11,22,33,44,55,66,77,88)
    struct.pack_into("<2q",memory,0,109,110)
    pointer=scenario["pointer"]
    if pointer=="tail": pointer=size-64
    destination=pointer
    if overlap: destination=(pointer-16)&0xffffffff
    length=scenario["length"]; j=scenario["start"]; trapped=False
    def address(base,index):
        if not 0<=index<length: raise IndexError()
        value=(base+index*8)&0xffffffff
        if value+8>size: raise IndexError()
        return value
    try:
        while j>0:
            if struct.unpack_from("<q",memory,address(pointer,j-1))[0]<=scenario["key"]: break
            # Pinning checks the destination's logical extent first; its
            # physical store follows the RHS load.
            if not 0<=j<length: raise IndexError()
            value=struct.unpack_from("<q",memory,address(pointer,j-1))[0]
            struct.pack_into("<q",memory,address(destination,j),value); j-=1
    except IndexError: trapped=True
    result=None
    if not trapped: result=str(j)
    return {"trapped":trapped,"result":result,"memory_bytes":size,
            "window":list(map(str,struct.unpack_from("<10q",memory,size-80))),"head":list(map(str,struct.unpack_from("<2q",memory)))}


def wasmtime_run(path,overlap):
    import wasmtime
    engine=wasmtime.Engine(); module=wasmtime.Module.from_file(engine,str(path)); results=[]
    for scenario in CASES:
        store=wasmtime.Store(engine); linker=wasmtime.Linker(engine)
        for item in module.imports: linker.define_func(item.module,item.name,item.type,lambda *args:None)
        exports=linker.instantiate(store,module).exports(store); exports["_start"](store)
        memory=exports["memory"]; image=bytes(memory.read(store)); size=len(image)
        def header_for(values):
            base=image.find(struct.pack("<8q",*values)); assert base>=0
            header=struct.pack("<II",base,8); at=image.find(header)
            assert at>=0 and image.find(header,at+1)<0
            return at
        source=header_for([11,22,33,44,55,66,77,88]); dest=header_for(list(range(201,209)))
        memory.write(store,struct.pack("<10q",91,92,11,22,33,44,55,66,77,88),size-80)
        memory.write(store,struct.pack("<2q",109,110),0)
        pointer=scenario["pointer"]
        if pointer=="tail": pointer=size-64
        memory.write(store,struct.pack("<II",pointer,scenario["length"]),source)
        memory.write(store,struct.pack("<II",(pointer-16)&0xffffffff,scenario["length"]),dest)
        trapped=False; result=None
        try: result=str(exports["run"](store,scenario["start"],scenario["key"]))
        except wasmtime.Trap: trapped=True
        image=bytes(memory.read(store))
        results.append({"trapped":trapped,"result":result,"memory_bytes":size,
                        "window":list(map(str,struct.unpack_from("<10q",image,size-80))),"head":list(map(str,struct.unpack_from("<2q",image)))})
    return results


class DescendingWhile(unittest.TestCase):
    setUp=strip.StripLoops.setUp; compile=strip.StripLoops.compile
    native=prefix.PrefixResolution.native; qualify=ordinal.LoopOrdinals.qualify

    def test_ordered_shifts_and_traps_with_logical_physical_and_overlapping_views(self):
        for overlap in (False,True):
            destination="xs"
            if overlap: destination="dst"
            for level in (0,2):
                for debug in (False,True):
                    path,_=self.compile(level,debug=debug,text=SOURCE.replace("DEST",destination))
                    cases=[dict(case,start=str(case["start"])) for case in CASES]
                    node=subprocess.run([strip.NODE,"-e",NODE_HOST,str(path),json.dumps(cases)],capture_output=True,text=True,timeout=60)
                    self.assertEqual(node.returncode,0,node.stdout+node.stderr)
                    for engine,results in (("v8",json.loads(node.stdout)),("wasmtime",wasmtime_run(path,overlap))):
                        for scenario,observed in zip(CASES,results,strict=True):
                            with self.subTest(overlap=overlap,level=level,debug=debug,engine=engine,scenario=scenario):
                                self.assertEqual(observed,expected(scenario,observed["memory_bytes"],overlap))

    def test_exits_and_mutating_conditions_keep_the_original_loop(self):
        self.qualify('''recursive fn visit(mode:i64)->i64 {
    var values:i64[8]=[11,22,33,44,55,66,77,88]; let xs=values[..]; var j=7;
    while j>0 && xs[j-1]>0 {
        xs[j]=xs[j-1];
        if mode==0 && j==5 { break; }
        if mode==1 && j==5 { xs[j-1]=0; continue; }
        if mode==2 && j==5 { return j; }
        j--;
    }
    return j;
}
recursive fn observed(xs:i64[:],j:i64&)->i64 { j-=1; return xs[j]; }
recursive fn mutating()->i64 {
    var values:i64[8]=[11,22,33,44,55,66,77,88]; let xs=values[..]; var j=7;
    while j>0 && observed(xs,j)>0 { xs[j+1]=xs[j]; j--; }
    return j;
}
fn main() { print(visit(0)," ",visit(1)," ",visit(2)," ",visit(3)," ",mutating()); }
''', "5 5 5 0 -1\n")


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument("--goose",type=Path,default=strip.GOOSE)
    parser.add_argument("--node",default=strip.NODE); parser.add_argument("--cc",default=prefix.CC)
    args,remaining=parser.parse_known_args(); strip.GOOSE=prefix.GOOSE=args.goose.resolve(); strip.NODE=args.node; prefix.CC=args.cc
    unittest.main(argv=[sys.argv[0],*remaining])
