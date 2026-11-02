#!/usr/bin/env python3
"""Qualify bounded divisor clones while retaining generic calls and exports."""
import argparse
from pathlib import Path
import subprocess
import sys
import unittest

import test_prefix_resolution as prefix
import test_strip_loops as strip
from test_fill_loops import function_body

WRAP = '''export fn wrap(a:i64,w:i64,h:i64)->i64 { (a%w)*100+a%h }
fn main() {
    print(wrap(-17,12,8)); print(wrap(-17,64,32));
    print(wrap(-17,16,8)); print(wrap(-17,12,8));
}
'''
MIXED = '''var order=0; var calls=0;
fn observe(tag:i64,value:i64)->i64 { order=order*10+tag; calls++; return value; }
recursive fn mixed(a:i64,w:i64,tail:i64,h:i64,last:i64)->i64 { (a%w)*100+a%h+tail+last }
fn main() { print(mixed(observe(1,-17),8,observe(2,100),-3,observe(3,7))," ",order," ",calls); }
'''
FALLBACK = '''recursive fn changed(a:i64,var b:i64)->i64 { b++; return a%b; }
recursive fn addressed(a:i64,var b:i64)->i64 { let alias:i64& = b; alias++; return a%b; }
recursive fn captured(a:i64,var b:i64)->i64 { recursive fn bump() { b++; } bump(); return a%b; }
recursive fn observe()->i64 { return 0; }
recursive fn called(a:i64,b:i64)->i64 { let side=observe(); return a%b+side; }
recursive fn shadowed(a:i64,b:i64)->i64 { { var b=3; b++; } return a%b; }
recursive fn narrow(a:i32,b:i32)->i32 { a%b }
'''
EXPORT_HOST = r'''
const fs=require("node:fs"),m=new WebAssembly.Module(fs.readFileSync(process.argv[1])),goose={};
for(const item of WebAssembly.Module.imports(m))goose[item.name]=()=>{};
const e=new WebAssembly.Instance(m,{goose}).exports;e._start();
process.stdout.write(String(e.wrap(-17n,5n,3n)));
'''


class ConstantDivisors(unittest.TestCase):
    setUp = strip.StripLoops.setUp
    compile = strip.StripLoops.compile
    native = prefix.PrefixResolution.native

    def engines(self, path):
        for engine, command in (
            ("v8", [strip.NODE, str(strip.ROOT/"scripts/run_wasm.mjs"), str(path)]),
            ("wasmtime", [sys.executable, str(strip.ROOT/"scripts/run_wasmtime.py"), str(path)]),
        ):
            yield engine, subprocess.run(command, capture_output=True, text=True, timeout=30)

    def qualify(self, path, level, expected):
        self.assertEqual(self.native(self.work/"main.goose",level),expected)
        for engine, result in self.engines(path):
            with self.subTest(engine=engine):
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertEqual(result.stdout,expected)

    def test_two_packs_reuse_and_generic_export(self):
        import wasmtime
        for level in (0,2):
            for debug in (False,True):
                path, stats = self.compile(level,debug=debug,text=WRAP)
                info = {item["name"].split("#")[0]:item for item in stats["function_info"]}
                clones = [name for name in info if name.startswith("wrap_const_")]
                with self.subTest(level=level,debug=debug):
                    self.assertEqual(len(clones),2)
                    self.assertIn("wrap",info)
                    self.assertTrue({info[name]["index"] for name in clones+["wrap"]} <= set(info["main"]["dependencies"]))
                    remainders = [list(strip.instructions(function_body(path,stats,name))).count(0x81) for name in clones]
                    self.assertEqual(sorted(remainders),[0,1])
                    for name in clones:
                        self.assertNotIn(0x55,list(strip.instructions(function_body(path,stats,name))))
                self.qualify(path,level,"707\n4715\n1507\n707\n")
                host = subprocess.run([strip.NODE,"-e",EXPORT_HOST,str(path)],capture_output=True,text=True,timeout=30)
                self.assertEqual(host.returncode,0,host.stderr); self.assertEqual(host.stdout,"301")
                engine=wasmtime.Engine(); module=wasmtime.Module.from_file(engine,str(path))
                store=wasmtime.Store(engine); linker=wasmtime.Linker(engine)
                for item in module.imports: linker.define_func(item.module,item.name,item.type,lambda *args:None)
                exports=linker.instantiate(store,module).exports(store); exports["_start"](store)
                self.assertEqual(exports["wrap"](store,-17,5,3),301)

    def test_negative_constant_and_nonconstant_argument_effects(self):
        for level in (0,2):
            for debug in (False,True):
                path, stats = self.compile(level,debug=debug,text=MIXED)
                clones = [item["name"].split("#")[0] for item in stats["function_info"] if item["name"].startswith("mixed_const_")]
                with self.subTest(level=level,debug=debug):
                    self.assertEqual(len(clones),1)
                    ops=list(strip.instructions(function_body(path,stats,clones[0])))
                    self.assertEqual(ops.count(0x81),1)
                    self.assertNotIn(0x55,ops)
                self.qualify(path,level,"808 123 3\n")

    def test_mutation_addresses_captures_calls_width_and_budget(self):
        large = "recursive fn large(var a:i64,b:i64)->i64 {"+"a+=1;"*100+"return a%b;}"
        source = FALLBACK+large+'''fn main() {
    print(changed(-17,8)," ",addressed(-17,8)," ",captured(-17,8)," ",called(-17,8));
    print(shadowed(-17,8)," ",narrow(-17,8)," ",large(-17,8));
}'''
        for level in (0,2):
            for debug in (False,True):
                path, stats = self.compile(level,debug=debug,text=source)
                names = [item["name"].split("#")[0] for item in stats["function_info"]]
                with self.subTest(level=level,debug=debug):
                    for name in ("changed","addressed","captured","called","narrow"):
                        self.assertFalse(any(item.startswith(name+"_const_") for item in names))
                    self.assertTrue(any(item.startswith("shadowed_const_") for item in names))
                    if level == 0:
                        self.assertFalse(any(item.startswith("large_const_") for item in names))
                self.qualify(path,level,"1 1 1 7\n7 7 3\n")

    def test_partial_pack_preserves_runtime_divisor_and_argument_effects(self):
        declarations = '''var order=0; var calls=0;
fn observe(tag:i64,value:i64)->i64 {
    order=order*10+tag; calls++; print(tag," ",order); return value;
}
recursive fn partial(a:i64,w:i64,tail:i64,h:i64,last:i64)->i64 { (a%w)*100+a%h+tail+last }
'''
        effects = "1 1\n2 12\n3 123\n4 1234\n"
        for divisors in ((4,3,-3),(0,)):
            statements = []; expected = ""
            for divisor in divisors:
                statements.append("order=0; calls=0; print(partial(observe(1,-17),8,observe(2,100),"
                                  f"observe(3,{divisor}),observe(4,7)),\" \",order,\" \",calls);")
                expected += effects
                if divisor:
                    expected += f"{(-17%8)*100+(-17%abs(divisor))+107} 1234 4\n"
            source = declarations+"fn main() {"+"".join(statements)+"}"
            for level in (0,2):
                for debug in (False,True):
                    path, stats = self.compile(level,debug=debug,text=source)
                    clones = [item["name"].split("#")[0] for item in stats["function_info"] if item["name"].startswith("partial_const_")]
                    with self.subTest(level=level,debug=debug,divisors=divisors):
                        self.assertEqual(len(clones),1)
                        ops=list(strip.instructions(function_body(path,stats,clones[0])))
                        self.assertEqual(ops.count(0x81),1)
                        self.assertEqual(ops.count(0x55),1)
                    if divisors != (0,):
                        self.qualify(path,level,expected)
                        continue
                    for engine, result in self.engines(path):
                        with self.subTest(level=level,debug=debug,engine=engine):
                            self.assertNotEqual(result.returncode,0)
                            self.assertEqual(result.stdout,expected)
                            self.assertIn("division by zero",result.stderr)

    def test_zero_in_mixed_pack_traps_after_all_call_arguments(self):
        source = '''var order=0;
fn observe(tag:i64,value:i64)->i64 { order=order*10+tag; print(tag," ",order); return value; }
recursive fn mixed(a:i64,w:i64,tail:i64,h:i64,last:i64)->i64 { (a%w)*100+a%h+tail+last }
fn main() { print("before"); print(mixed(observe(1,-17),8,observe(2,100),0,observe(3,7))); }
'''
        for level in (0,2):
            for debug in (False,True):
                path, stats = self.compile(level,debug=debug,text=source)
                self.assertTrue(any(item["name"].startswith("mixed_const_") for item in stats["function_info"]))
                for engine, result in self.engines(path):
                    with self.subTest(level=level,debug=debug,engine=engine):
                        self.assertNotEqual(result.returncode,0)
                        self.assertEqual(result.stdout,"before\n1 1\n2 12\n3 123\n")
                        self.assertIn("division by zero",result.stderr)


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose",type=Path,default=strip.GOOSE)
    parser.add_argument("--node",default=strip.NODE)
    parser.add_argument("--cc",default=prefix.CC)
    args,remaining=parser.parse_known_args()
    strip.GOOSE=prefix.GOOSE=args.goose.resolve(); strip.NODE=args.node; prefix.CC=args.cc
    unittest.main(argv=[sys.argv[0],*remaining])
