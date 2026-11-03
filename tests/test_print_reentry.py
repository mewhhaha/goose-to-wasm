#!/usr/bin/env python3
"""Preserve print scratch restoration after caught traps in host reentry."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import unittest

import test_strip_loops as strip

REENTRY_SOURCE='''export fn blow(index:i64)->u8 {
    var bytes:u8[60000]=[index as! u8;60000];
    assert(index!=0); return bytes[1];
}
recursive fn allocate(index:i64)->u8 {
    var bytes:u8[60000]=[index as! u8;60000];
    bytes[0]=bytes[59999]+1; return bytes[1];
}
export fn next(index:i64)->u8 { return allocate(index); }
fn main() { print(1); print(next(7)); }
'''
REENTRY_HOST=r'''
const fs=require("node:fs");
const module_=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
let e,entered=false,caught=0,output="",trapped=false;
const number=value=>{
  if(!entered) {
    entered=true;
    try {e.blow(0n);}
    catch(error) {if(!(error instanceof WebAssembly.RuntimeError)) throw error; caught++;}
  }
  output+=value.toString();
};
const goose={print_i64:number,print_u64:number,newline:()=>{output+="\n";}};
for(const item of WebAssembly.Module.imports(module_)) if(!(item.name in goose)) goose[item.name]=()=>{};
e=new WebAssembly.Instance(module_,{goose}).exports;
try {e._start();}
catch(error) {if(!(error instanceof WebAssembly.RuntimeError)) throw error; trapped=true;}
process.stdout.write(JSON.stringify({output,caught,trapped}));
'''


class PrintReentry(unittest.TestCase):
    setUp=strip.StripLoops.setUp

    def test_scalar_output_reentry_caught_trap_still_restores_scratch(self):
        source=self.work/"main.goose"; source.write_text(REENTRY_SOURCE)
        for level in (0,2):
            for debug in (False,True):
                path=self.work/"reentry.wasm"; stats=self.work/"stats.json"
                command=[str(strip.GOOSE),str(source),"--offline","--target","wasm-direct",f"-O{level}",
                         "--wasm-initial-pages","2","--wasm-max-pages","2","--wasm-stats",str(stats),"-o",str(path)]
                if debug: command.append("--debug")
                compiled=subprocess.run(command,capture_output=True,text=True,timeout=60)
                self.assertEqual(compiled.returncode,0,compiled.stdout+compiled.stderr)
                self.assertEqual(json.loads(stats.read_text())["region_count"],0)
                result=subprocess.run([strip.NODE,"-e",REENTRY_HOST,str(path)],capture_output=True,text=True,timeout=30)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                with self.subTest(level=level,debug=debug):
                    self.assertEqual(json.loads(result.stdout),{"output":"1\n7\n","caught":1,"trapped":False})


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose",type=Path,default=strip.GOOSE)
    parser.add_argument("--node",default=strip.NODE)
    args,remaining=parser.parse_known_args(); strip.GOOSE=args.goose.resolve(); strip.NODE=args.node
    unittest.main(argv=[sys.argv[0],*remaining])
