#!/usr/bin/env python3
"""Qualify runtime signed remainders and preserve operand evaluation effects."""
import argparse
from pathlib import Path
import subprocess
import sys
import unittest

import test_prefix_resolution as prefix
import test_strip_loops as strip

MIN = -(1 << 63)
MAX = (1 << 63)-1


def integer(value, width=64):
    return f"({value&((1<<width)-1):#x} as! i{width})"


class DynamicRemainder(unittest.TestCase):
    setUp = strip.StripLoops.setUp
    compile = strip.StripLoops.compile
    native = prefix.PrefixResolution.native

    def engines(self, path):
        for engine, command in (
            ("v8", [strip.NODE, str(strip.ROOT/"scripts/run_wasm.mjs"), str(path)]),
            ("wasmtime", [sys.executable, str(strip.ROOT/"scripts/run_wasmtime.py"), str(path)]),
        ):
            yield engine, subprocess.run(command, capture_output=True, text=True, timeout=30)

    def qualify(self, source, expected):
        for level in (0,2):
            for debug in (False,True):
                path, _ = self.compile(level, debug=debug, text=source)
                with self.subTest(level=level,debug=debug,engine="native"):
                    self.assertEqual(self.native(self.work/"main.goose", level), expected)
                for engine, result in self.engines(path):
                    with self.subTest(level=level,debug=debug,engine=engine):
                        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
                        self.assertEqual(result.stdout, expected)

    def test_runtime_divisors_and_exact_operand_order(self):
        source = '''var order=0; var left_calls=0; var right_calls=0;
fn left(value:i64)->i64 { order=order*10+1; left_calls++; return value; }
fn right(value:i64)->i64 { order=order*10+2; right_calls++; return value; }
recursive fn calculate(a:i64,b:i64) {
    order=0; left_calls=0; right_calls=0;
    let value=left(a)%right(b);
    print(value," ",order," ",left_calls," ",right_calls);
}
'''
        dividends = (MIN,MIN+1,-65,-17,-1,0,1,17,65,MAX)
        divisors = (MIN,-17,-16,-8,-3,-2,-1,1,2,3,8,16,17,32,64,1<<31,1<<62,MAX)
        pairs = [(a,b) for a in dividends for b in divisors]
        for magnitude in (32,64,1<<31,1<<62):
            for a in (-magnitude-1,-magnitude,-magnitude+1,magnitude-1,magnitude,magnitude+1):
                pairs.extend(((a,magnitude),(a,-magnitude)))
        calls = []; answers = []
        for a, b in dict.fromkeys(pairs):
            calls.append(f"calculate({integer(a)},{integer(b)});")
            answers.append(f"{a%abs(b)} 12 1 1\n")
        self.qualify(source+"fn main() {"+"".join(calls)+"}", "".join(answers))

    def test_other_integer_widths_unsigned_and_literals(self):
        source = '''recursive fn narrow(a:i32,b:i32)->i32 { a%b }
recursive fn unsigned32(a:u32,b:u32)->u32 { a%b }
recursive fn unsigned64(a:u64,b:u64)->u64 { a%b }
recursive fn literal(a:i64) { print(a%8," ",a%-8," ",a%3); }
'''
        calls = []; answers = []
        for a in (-(1<<31),-17,0,17,(1<<31)-1):
            for b in (-(1<<31),-8,-1,1,8,11):
                calls.append(f"print(narrow({integer(a,32)},{integer(b,32)}));")
                answers.append(f"{a%abs(b)}\n")
        for width in (32,64):
            top = 1<<(width-1); maximum = (1<<width)-1
            for a, b in ((0,1),(maximum,1),(maximum,8),(maximum,maximum),(top,top-1),(maximum,top)):
                calls.append(f"print(unsigned{width}({a:#x},{b:#x}));")
                answers.append(f"{a%b}\n")
        for a in (MIN,-17,-1,0,1,17,MAX):
            calls.append(f"literal({integer(a)});")
            answers.append(f"{a%8} {a%8} {a%3}\n")
        self.qualify(source+"fn main() {"+"".join(calls)+"}", "".join(answers))

    def test_zero_divisor_traps_after_both_operand_effects(self):
        source = '''var order=0; var left_calls=0; var right_calls=0;
fn left(value:i64)->i64 {
    order=order*10+1; left_calls++;
    print("left ",order," ",left_calls," ",right_calls); return value;
}
fn right(value:i64)->i64 {
    order=order*10+2; right_calls++;
    print("right ",order," ",left_calls," ",right_calls); return value;
}
recursive fn calculate(a:i64,b:i64)->i64 { left(a)%right(b) }
fn main() { print("before"); print(calculate('''+integer(MIN)+''',0)); }
'''
        for level in (0,2):
            for debug in (False,True):
                path, _ = self.compile(level, debug=debug, text=source)
                for engine, result in self.engines(path):
                    with self.subTest(level=level,debug=debug,engine=engine):
                        self.assertNotEqual(result.returncode, 0)
                        self.assertEqual(result.stdout, "before\nleft 1 1 0\nright 12 1 1\n")
                        self.assertIn("division by zero", result.stderr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose",type=Path,default=strip.GOOSE)
    parser.add_argument("--node",default=strip.NODE)
    parser.add_argument("--cc",default=prefix.CC)
    args, remaining = parser.parse_known_args()
    strip.GOOSE = prefix.GOOSE = args.goose.resolve()
    strip.NODE = args.node; prefix.CC = args.cc
    unittest.main(argv=[sys.argv[0],*remaining])
