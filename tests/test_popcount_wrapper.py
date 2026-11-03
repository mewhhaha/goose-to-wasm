#!/usr/bin/env python3
"""Qualify whole popcount wrappers, formal truncation and argument effects."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import unittest

import test_loop_ordinals as ordinal
import test_prefix_resolution as prefix
import test_strip_loops as strip
from test_fill_loops import function_body

WIDTHS=((8,"u8"),(16,"i8"),(32,"u32"),(64,"i64"))
SOURCE="\n".join(f'''recursive fn wrapper{width}(value:u{width})->{result} {{
    var bits=value; var count:{result}=0;
    while bits!=0 {{ bits&=bits-1; count++; }}
    return count;
}}
export fn apply{width}(value:u{width})->{result} {{ return wrapper{width}(value); }}'''
    for width,result in WIDTHS)+"\nfn main() {}"
INPUTS={str(width):[-(1<<31),-1,0,1,255,256,65535,(1<<31)-1] for width in (8,16,32)}
INPUTS["64"]=[-(1<<63),-1,0,1,1<<32,(1<<63)-1]
NODE_HOST=r'''
const fs=require("node:fs");
const module_=new WebAssembly.Module(fs.readFileSync(process.argv[1])),inputs=JSON.parse(process.argv[2]),goose={};
for(const item of WebAssembly.Module.imports(module_)) goose[item.name]=()=>{};
const e=new WebAssembly.Instance(module_,{goose}).exports; e._start();
const result={};
for(const [width,values] of Object.entries(inputs)) result[width]=values.map(value=>{
  let argument=Number(value); if(width==="64") argument=BigInt(value);
  return e["apply"+width](argument).toString();
});
process.stdout.write(JSON.stringify(result));
'''


def wasmtime_run(path):
    import wasmtime
    engine=wasmtime.Engine(); module=wasmtime.Module.from_file(engine,str(path)); store=wasmtime.Store(engine)
    linker=wasmtime.Linker(engine)
    for item in module.imports: linker.define_func(item.module,item.name,item.type,lambda *args:None)
    exports=linker.instantiate(store,module).exports(store); exports["_start"](store)
    return {width:[str(exports["apply"+width](store,value)) for value in values] for width,values in INPUTS.items()}


class PopcountWrapper(unittest.TestCase):
    setUp=strip.StripLoops.setUp; compile=strip.StripLoops.compile
    native=prefix.PrefixResolution.native; qualify=ordinal.LoopOrdinals.qualify

    def test_formal_width_is_normalized_before_counting_raw_host_arguments(self):
        answers={width:[str((value&((1<<int(width))-1)).bit_count()) for value in values] for width,values in INPUTS.items()}
        inputs={width:list(map(str,values)) for width,values in INPUTS.items()}
        for level in (0,2):
            for debug in (False,True):
                path,stats=self.compile(level,debug=debug,text=SOURCE)
                host=subprocess.run([strip.NODE,"-e",NODE_HOST,str(path),json.dumps(inputs)],capture_output=True,text=True,timeout=30)
                self.assertEqual(host.returncode,0,host.stdout+host.stderr)
                for engine,observed in (("v8",json.loads(host.stdout)),("wasmtime",wasmtime_run(path))):
                    with self.subTest(level=level,debug=debug,engine=engine): self.assertEqual(observed,answers)
                for width,_ in WIDTHS:
                    opcode=0x69
                    if width==64: opcode=0x7b
                    with self.subTest(level=level,debug=debug,width=width):
                        self.assertEqual(list(strip.instructions(function_body(path,stats,"apply"+str(width)))).count(opcode),1)

    def test_argument_evaluation_once_and_near_wrapper_fallbacks(self):
        source=SOURCE.replace("fn main() {}",'''var calls=0;
recursive fn input(value:i64)->u8 { calls++; return value as! u8; }
recursive fn seeded(value:u8)->i64 {
    var bits=value; var count=1;
    while bits!=0 { bits&=bits-1; count++; } return count;
}
recursive fn extra(value:u8)->i64 {
    var bits=value; var count=0;
    while bits!=0 { bits&=bits-1; count++; calls++; } return count;
}
recursive fn changed(value:u8)->i64 {
    var bits=value; var count=0;
    while bits!=0 { bits&=bits-1; count++; } return count+1;
}
recursive fn signed(value:i16)->i64 {
    var bits=value; var count=0;
    while bits!=0 { bits&=bits-1; count++; } return count;
}
fn main() {
    print(wrapper8(input(256))," ",calls," ",wrapper8(input(-1))," ",calls);
    calls=0; print(seeded(255)," ",extra(255)," ",changed(255)," ",signed(127)," ",calls);
}''')
        self.qualify(source,"0 1 8 2\n9 8 9 7 8\n")

    def test_checked_argument_trap_keeps_prior_effects_and_output(self):
        source=SOURCE.replace("fn main() {}",'''var calls=0;
recursive fn checked(value:i64)->u8 { calls++; print(calls); return value as u8; }
fn main() { print("before"); print(wrapper8(checked(256))); }''')
        for level in (0,2):
            for debug in (False,True):
                path,_=self.compile(level,debug=debug,text=source)
                for engine,command in (("v8",[strip.NODE,str(strip.ROOT/"scripts/run_wasm.mjs"),str(path)]),
                                       ("wasmtime",[sys.executable,str(strip.ROOT/"scripts/run_wasmtime.py"),str(path)])):
                    result=subprocess.run(command,capture_output=True,text=True,timeout=30)
                    with self.subTest(level=level,debug=debug,engine=engine):
                        if debug:
                            self.assertNotEqual(result.returncode,0); self.assertEqual(result.stdout,"before\n1\n")
                            self.assertIn("out of range",result.stderr)
                        else:
                            self.assertEqual(result.returncode,0,result.stdout+result.stderr); self.assertEqual(result.stdout,"before\n1\n0\n")


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument("--goose",type=Path,default=strip.GOOSE)
    parser.add_argument("--node",default=strip.NODE); parser.add_argument("--cc",default=prefix.CC)
    args,remaining=parser.parse_known_args(); strip.GOOSE=prefix.GOOSE=args.goose.resolve(); strip.NODE=args.node; prefix.CC=args.cc
    unittest.main(argv=[sys.argv[0],*remaining])
