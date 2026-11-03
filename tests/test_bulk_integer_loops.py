#!/usr/bin/env python3
"""Qualify integer bulk paths against ordered scalar writes and overlap."""
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

SOURCE='''var incoming:TYPE[:]; var outgoing:TYPE[:];
var first:TYPE[4]=[17,34,51,68]; var second:TYPE[4]=[81,82,83,84];
export fn clear() { let xs=outgoing; for i in xs.len { xs[i]=0; } }
export fn move(count:i64) { let src=incoming; let dst=outgoing; for i in count { dst[i]=src[i]; } }
export fn move_length() { let src=incoming; let dst=outgoing; for i in src.len { dst[i]=src[i]; } }
fn main() { incoming=first[..]; outgoing=second[..]; }
'''
TAIL=bytes((i*37+17)&255 for i in range(128))


def cases(width):
    def at(base,offset): return {"base":base,"offset":offset}
    def case(mode,src,dst,ns=4,nd=4,count=4):
        return {"mode":mode,"src":src,"dst":dst,"ns":ns,"nd":nd,"count":str(count)}
    tail=lambda offset:at("tail",offset)
    end=lambda offset:at("end",offset)
    result=[case("clear",tail(0),tail(33)),case("clear",tail(0),end(-4*width)),case("clear",tail(0),end(0),nd=0),
            case("clear",tail(0),end(1),nd=0),case("clear",tail(0),end(-(width+width//2)),nd=4),
            case("clear",tail(0),end(-(2*width+1)),nd=0xffffffff),
            case("clear",tail(0),at("absolute",0xfffffffe),nd=4)]
    for destination in (16-width,16,16+width,16+1,16-1,16+4*width,64):
        result.append(case("move",tail(16),tail(destination)))
    result += [case("move",tail(0),end(-4*width)),case("move",end(-4*width),tail(64)),case("move_length",tail(16),tail(64)),case("move",end(1),end(1),ns=0,nd=0,count=0),
               case("move",tail(0),tail(64),count=-1),case("move",tail(0),tail(64),count=-(1<<63)),case("move",tail(0),tail(64),count=0),
               case("move",tail(0),tail(64),ns=2),case("move",tail(0),tail(64),nd=2),
               case("move",tail(0),tail(64),count=(1<<63)-1),
               case("move",end(-(2*width+1)),tail(64)),case("move",tail(0),end(-(2*width+1))),
               case("move",at("absolute",0xfffffffe),tail(64)),case("move",tail(0),at("absolute",0xfffffffe))]
    # Exercise both sides of the runtime bulk crossover, including successful
    # exact-end spans and overlap/partial-trap fallbacks above the crossover.
    bulk_count=64//width
    result += [case("move",tail(0),tail(64),ns=bulk_count,nd=bulk_count,count=bulk_count),
               case("move",tail(64),tail(0),ns=bulk_count,nd=bulk_count,count=bulk_count),
               case("move",tail(33),tail(1),ns=bulk_count,nd=bulk_count,count=bulk_count),
               case("move",tail(0),tail(1),ns=bulk_count,nd=bulk_count,count=bulk_count),
               case("move",tail(0),tail(64),ns=bulk_count,nd=bulk_count//2,count=bulk_count),
               case("move",tail(96),tail(0),ns=bulk_count,nd=bulk_count,count=bulk_count),
               case("move",tail(0),tail(96),ns=bulk_count,nd=bulk_count,count=bulk_count)]
    for count in (bulk_count-1,bulk_count+1):
        result.append(case("move",tail(32),tail(0),ns=count,nd=count,count=count))
    return result


NODE_HOST=r'''
const fs=require("node:fs");
const module_=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
const width=Number(process.argv[2]),cases=JSON.parse(process.argv[3]),goose={};
for(const item of WebAssembly.Module.imports(module_)) goose[item.name]=()=>{};
const results=cases.map(scenario=>{
  const e=new WebAssembly.Instance(module_,{goose}).exports; e._start();
  const bytes=Buffer.from(e.memory.buffer),end=bytes.length;
  const headerFor=values=>{
    const pattern=Buffer.alloc(4*width);
    values.forEach((value,i)=>{for(let j=0;j<width;j++)pattern[i*width+j]=Number((BigInt(value)>>BigInt(j*8))&255n);});
    const base=bytes.indexOf(pattern); if(base<0)throw new Error("missing backing");
    const header=Buffer.alloc(8);header.writeUInt32LE(base);header.writeUInt32LE(4,4);
    const at=bytes.indexOf(header);if(at<0||bytes.indexOf(header,at+1)>=0)throw new Error("header must be unique");
    return at;
  };
  const source=headerFor([17,34,51,68]),dest=headerFor([81,82,83,84]);
  for(let i=0;i<128;i++)bytes[end-128+i]=(i*37+17)&255;
  const address=place=>{let base=0;if(place.base==="tail")base=end-128;if(place.base==="end")base=end;return(base+place.offset)>>>0;};
  bytes.writeUInt32LE(address(scenario.src),source);bytes.writeUInt32LE(scenario.ns,source+4);
  bytes.writeUInt32LE(address(scenario.dst),dest);bytes.writeUInt32LE(scenario.nd,dest+4);
  let trapped=false;
  try {if(scenario.mode==="move")e.move(BigInt(scenario.count));else e[scenario.mode]();}
  catch(error){if(!(error instanceof WebAssembly.RuntimeError))throw error;trapped=true;}
  return {trapped,memory_bytes:end,tail:Array.from(bytes.subarray(end-128))};
});
process.stdout.write(JSON.stringify(results));
'''


def expected(scenario,width,size):
    memory=bytearray(size);memory[-128:]=TAIL
    def base(place):
        value=0
        if place["base"]=="tail":value=size-128
        if place["base"]=="end":value=size
        return (value+place["offset"])&0xffffffff
    source=base(scenario["src"]);destination=base(scenario["dst"])
    count=int(scenario["count"])
    if scenario["mode"]=="clear":count=scenario["nd"]
    if scenario["mode"]=="move_length":count=scenario["ns"]
    trapped=False
    try:
        for index in range(max(0,count)):
            if index>=scenario["nd"]:raise IndexError()
            target=(destination+index*width)&0xffffffff
            value=bytes(width)
            if scenario["mode"]!="clear":
                if index>=scenario["ns"]:raise IndexError()
                at=(source+index*width)&0xffffffff
                if at+width>size:raise IndexError()
                value=memory[at:at+width]
            if target+width>size:raise IndexError()
            memory[target:target+width]=value
    except IndexError:trapped=True
    return {"trapped":trapped,"memory_bytes":size,"tail":list(memory[-128:])}


def wasmtime_run(path,width,scenarios):
    import wasmtime
    engine=wasmtime.Engine();module=wasmtime.Module.from_file(engine,str(path));results=[]
    for scenario in scenarios:
        store=wasmtime.Store(engine);linker=wasmtime.Linker(engine)
        for item in module.imports:linker.define_func(item.module,item.name,item.type,lambda *args:None)
        exports=linker.instantiate(store,module).exports(store);exports["_start"](store)
        memory=exports["memory"];image=bytes(memory.read(store));size=len(image)
        def header_for(values):
            pattern=b"".join(value.to_bytes(width,"little")for value in values);base=image.find(pattern);assert base>=0
            header=struct.pack("<II",base,4);at=image.find(header);assert at>=0 and image.find(header,at+1)<0
            return at
        source=header_for([17,34,51,68]);dest=header_for([81,82,83,84]);memory.write(store,TAIL,size-128)
        def address(place):
            base=0
            if place["base"]=="tail":base=size-128
            if place["base"]=="end":base=size
            return(base+place["offset"])&0xffffffff
        memory.write(store,struct.pack("<II",address(scenario["src"]),scenario["ns"]),source)
        memory.write(store,struct.pack("<II",address(scenario["dst"]),scenario["nd"]),dest)
        trapped=False
        try:
            if scenario["mode"]=="move":exports["move"](store,int(scenario["count"]))
            else:exports[scenario["mode"]](store)
        except wasmtime.Trap:trapped=True
        results.append({"trapped":trapped,"memory_bytes":size,"tail":list(memory.read(store,size-128,size))})
    return results


class BulkIntegerLoops(unittest.TestCase):
    setUp=strip.StripLoops.setUp;compile=strip.StripLoops.compile
    native=prefix.PrefixResolution.native;qualify=ordinal.LoopOrdinals.qualify

    def test_effectful_rhs_preserves_calls_and_forward_overlap_propagation(self):
        source='''var calls=0;
recursive fn read(value:i16)->i16 { calls++; return value; }
recursive fn traced(dst:i16[:],src:i16[:],count:i64) { for i in count { dst[i]=read(src[i]); } }
fn main() {
    var rows:i16[5]=[1,2,3,4,5]; traced(rows[1..],rows[..4],4); print(rows," ",calls);
}'''
        self.qualify(source,"[1, 1, 1, 1, 1] 4\n")
        for level in (0,2):
            path,stats=self.compile(level,text=source)
            self.assertNotIn(b"\xfc\x0a\x00\x00",function_body(path,stats,"traced"))

    def test_region_cursors_keep_both_operations_scalar(self):
        source="var owned:u8[>..]=[];\n"+SOURCE.replace("TYPE","u32").replace("incoming=first[..];", "owned.push(7); incoming=first[..];")
        for level in (0,2):
            path,stats=self.compile(level,text=source)
            self.assertGreater(stats["region_count"],0)
            self.assertNotIn(b"\xfc\x0b\x00",function_body(path,stats,"clear"))
            self.assertNotIn(b"\xfc\x0a\x00\x00",function_body(path,stats,"move"))

    def test_bulk_and_fallback_paths_match_ordered_scalar_writes(self):
        for storage,width in (("u8",1),("i8",1),("u16",2),("i16",2),("u32",4),("i32",4),("u64",8),("i64",8)):
            scenarios=cases(width)
            for level in (0,2):
                for debug in (False,True):
                    path,stats=self.compile(level,debug=debug,text=SOURCE.replace("TYPE",storage))
                    self.assertIn(b"\xfc\x0b\x00",function_body(path,stats,"clear"))
                    self.assertIn(b"\xfc\x0a\x00\x00",function_body(path,stats,"move"))
                    self.assertIn(b"\xfc\x0a\x00\x00",function_body(path,stats,"move_length"))
                    node=subprocess.run([strip.NODE,"-e",NODE_HOST,str(path),str(width),json.dumps(scenarios)],capture_output=True,text=True,timeout=60)
                    self.assertEqual(node.returncode,0,node.stdout+node.stderr)
                    for engine,results in (("v8",json.loads(node.stdout)),("wasmtime",wasmtime_run(path,width,scenarios))):
                        for scenario,observed in zip(scenarios,results,strict=True):
                            with self.subTest(storage=storage,level=level,debug=debug,engine=engine,scenario=scenario):
                                self.assertEqual(observed,expected(scenario,width,observed["memory_bytes"]))

    def test_nonzero_wide_fills_floats_bools_and_effects_keep_scalar_lowering(self):
        for storage,value in (("u16","1"),("u32","1"),("u64","1"),("f32","0.0"),("f64","0.0"),("bool","false")):
            source=f'''var outgoing:{storage}[:]; var incoming:{storage}[:];
export fn keep(count:i64) {{ let dst=outgoing; let src=incoming;
    for i in dst.len {{ dst[i]={value}; }} for i in count {{ dst[i]=src[i]; }}
}} fn main() {{}}'''
            for level in (0,2):
                path,stats=self.compile(level,text=source)
                body=function_body(path,stats,"keep")
                self.assertNotIn(b"\xfc\x0b\x00",body)
                if storage in ("f32","f64","bool"):self.assertNotIn(b"\xfc\x0a\x00\x00",body)


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--goose",type=Path,default=strip.GOOSE)
    parser.add_argument("--node",default=strip.NODE);parser.add_argument("--cc",default=prefix.CC);args,remaining=parser.parse_known_args()
    strip.GOOSE=prefix.GOOSE=args.goose.resolve();strip.NODE=args.node;prefix.CC=args.cc
    unittest.main(argv=[sys.argv[0],*remaining])
