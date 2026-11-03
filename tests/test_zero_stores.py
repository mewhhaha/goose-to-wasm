#!/usr/bin/env python3
"""Qualify zero-filled fresh images and initializer ordering under host edits."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import unittest

import test_loop_ordinals as ordinal
import test_prefix_resolution as prefix
import test_strip_loops as strip

NODE_HOST = r'''
const fs=require("node:fs");
const module_=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
let exports_, touched=false;
const callback=()=>{
  const memory=Buffer.from(exports_.memory.buffer);
  const pattern=Buffer.from("88776655fe322310","hex");
  const at=memory.indexOf(pattern);
  if(at<0 || memory.indexOf(pattern,at+1)>=0) throw new Error("fresh image must be unique");
  memory.fill(255,at+16,at+24); touched=true; return 29n;
};
const goose={};
for(const item of WebAssembly.Module.imports(module_)) if(item.module==="goose") goose[item.name]=()=>{};
exports_=new WebAssembly.Instance(module_,{goose,env:{callback}}).exports;
exports_._start();
process.stdout.write(JSON.stringify({value:exports_.tick().toString(),touched}));
'''


def wasmtime_run(path):
    import wasmtime
    engine=wasmtime.Engine(); module=wasmtime.Module.from_file(engine,str(path))
    store=wasmtime.Store(engine); linker=wasmtime.Linker(engine); touched=False
    def callback(caller):
        nonlocal touched
        memory=caller.get("memory"); image=bytes(memory.read(caller))
        pattern=bytes.fromhex("88776655fe322310"); at=image.find(pattern)
        assert at>=0 and image.find(pattern,at+1)<0, "fresh image must be unique"
        memory.write(caller,bytes([255])*8,at+16); touched=True
        return 29
    for item in module.imports:
        if (item.module,item.name)==("env","callback"):
            linker.define_func(item.module,item.name,item.type,callback,access_caller=True)
        else:
            assert item.module=="goose"
            linker.define_func(item.module,item.name,item.type,lambda *args:None)
    exports=linker.instantiate(store,module).exports(store); exports["_start"](store)
    return {"value":str(exports["tick"](store)),"touched":touched}


class ZeroStores(unittest.TestCase):
    setUp=strip.StripLoops.setUp
    compile=strip.StripLoops.compile
    native=prefix.PrefixResolution.native
    qualify=ordinal.LoopOrdinals.qualify

    def test_zero_fills_reused_frames_and_scalar_widths(self):
        self.qualify('''var calls=0;
recursive fn zero()->u16 { calls++; return 0; }
recursive fn image(clear:bool)->u16[4] { if clear { return [0;4]; } return [7;4]; }
struct Values { a:i8,b:u16,c:i32,d:u64,z:f64 }
fn main() {
    print(image(false)); print(image(true)); print(image(true));
    let filled:u16[4]=[zero();4]; print(filled," ",calls);
    print(Values {0,0,0,0,-0.0});
}''', "[7, 7, 7, 7]\n[0, 0, 0, 0]\n[0, 0, 0, 0]\n[0, 0, 0, 0] 1\nValues { 0, 0, 0, 0, -0.0 }\n")

    def test_zero_after_callback_overwrites_host_modified_fresh_image(self):
        for declaration,result in (
            ("recursive fn make()->u64[3] { return [0x102332FE55667788,callback(),0]; }", "make()[2]"),
            ("struct R { head:u64,middle:u64,tail:u64 } recursive fn make()->R { return R {0x102332FE55667788,callback(),0}; }", "make().tail"),
        ):
            source="extern fn callback()->u64; "+declaration+" export fn tick()->u64 { return "+result+"; } fn main() {}"
            for level in (0,2):
                for debug in (False,True):
                    path,_=self.compile(level,debug=debug,text=source)
                    node=subprocess.run([strip.NODE,"-e",NODE_HOST,str(path)],capture_output=True,text=True,timeout=30)
                    self.assertEqual(node.returncode,0,node.stdout+node.stderr)
                    for engine,observed in (("v8",json.loads(node.stdout)),("wasmtime",wasmtime_run(path))):
                        with self.subTest(result=result,level=level,debug=debug,engine=engine):
                            self.assertEqual(observed,{"value":"0","touched":True})


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose",type=Path,default=strip.GOOSE)
    parser.add_argument("--node",default=strip.NODE); parser.add_argument("--cc",default=prefix.CC)
    args,remaining=parser.parse_known_args(); strip.GOOSE=prefix.GOOSE=args.goose.resolve()
    strip.NODE=args.node; prefix.CC=args.cc
    unittest.main(argv=[sys.argv[0],*remaining])
