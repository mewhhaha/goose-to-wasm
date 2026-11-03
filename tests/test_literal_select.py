#!/usr/bin/env python3
"""Qualify exact integer literal selects and effectful/cast arm fallbacks."""
import argparse
from pathlib import Path
import subprocess
import sys
import unittest

import test_loop_ordinals as ordinal
import test_prefix_resolution as prefix
import test_strip_loops as strip
from test_fill_loops import function_body


class LiteralSelect(unittest.TestCase):
    setUp=strip.StripLoops.setUp;compile=strip.StripLoops.compile
    native=prefix.PrefixResolution.native;qualify=ordinal.LoopOrdinals.qualify

    def test_fixed_integer_widths_and_signed_values(self):
        functions=[];calls=[];answers=[]
        for type_,yes,no in (("i8",12,34),("u8",0,255),("i16",123,32767),("u16",0,65535),
                              ("i32",17,2147483647),("u32",0,4294967295),
                              ("i64",37,9223372036854775807),("u64",0,18446744073709551615)):
            functions.append(f"export fn pick_{type_}(flag:bool)->{type_} {{ if flag {{ {yes} }} else {{ {no} }} }}")
            calls.append(f'print(pick_{type_}(true)," ",pick_{type_}(false));');answers.append(f"{yes} {no}\n")
        source="\n".join(functions)+"\nfn main(){"+"".join(calls)+"}"
        self.qualify(source,"".join(answers))
        for level in (0,2):
            path,stats=self.compile(level,text=source)
            for type_ in ("i8","u8","i16","u16","i32","u32","i64","u64"):
                with self.subTest(level=level,type=type_):
                    self.assertEqual(list(strip.instructions(function_body(path,stats,"pick_"+type_))).count(0x1b),1)
        self.qualify('''recursive fn signed(flag:bool)->i8 { if flag { -128 } else { -1 } }
fn main() { print(signed(true)," ",signed(false)); }''',"-128 -1\n")

    def test_condition_once_and_selected_arm_effects_only(self):
        self.qualify('''var calls=0;
recursive fn condition(value:i64)->bool { calls++; return value>0; }
recursive fn pick(value:i64)->i64 { if condition(value) { 123 } else { 456 } }
recursive fn observe(value:i64)->i64 { calls++; return value; }
recursive fn effect(flag:bool)->i64 { if flag { observe(11) } else { observe(22) } }
fn main() {
    print(pick(1)," ",calls," ",pick(0)," ",calls); calls=0;
    print(effect(true)," ",calls," ",effect(false)," ",calls);
}''',"123 1 456 2\n11 1 22 2\n")

    def test_cast_arms_retain_their_checks_and_lazy_evaluation(self):
        source='''export fn casted(flag:bool,value:i64)->u8 { if flag { value as u8 } else { 7 } }
export fn literals(flag:bool)->u8 { if flag { 1 as! u8 } else { 2 as! u8 } }
fn main() { print(casted(false,256)); print(casted(true,256)); }'''
        for level in (0,2):
            for debug in (False,True):
                path,stats=self.compile(level,text=source,debug=debug)
                self.assertNotIn(0x1b,strip.instructions(function_body(path,stats,"casted")))
                # Frontend constant folding can erase literal casts even at O0.
                # Variable checked casts above must retain lazy branch evaluation.
                for engine,command in (("v8",[strip.NODE,str(strip.ROOT/"scripts/run_wasm.mjs"),str(path)]),
                                       ("wasmtime",[sys.executable,str(strip.ROOT/"scripts/run_wasmtime.py"),str(path)])):
                    result=subprocess.run(command,capture_output=True,text=True,timeout=30)
                    with self.subTest(level=level,debug=debug,engine=engine):
                        if debug:
                            self.assertNotEqual(result.returncode,0);self.assertEqual(result.stdout,"7\n")
                            self.assertIn("out of range",result.stderr)
                        else:
                            self.assertEqual(result.returncode,0,result.stdout+result.stderr);self.assertEqual(result.stdout,"7\n0\n")


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--goose",type=Path,default=strip.GOOSE)
    parser.add_argument("--node",default=strip.NODE);parser.add_argument("--cc",default=prefix.CC);args,remaining=parser.parse_known_args()
    strip.GOOSE=prefix.GOOSE=args.goose.resolve();strip.NODE=args.node;prefix.CC=args.cc
    unittest.main(argv=[sys.argv[0],*remaining])
