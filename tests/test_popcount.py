#!/usr/bin/env python3
"""Qualify local bit-count loops, observable fallbacks and checked overflow."""
import argparse
from pathlib import Path
import subprocess
import sys
import unittest

import test_prefix_resolution as prefix
import test_strip_loops as strip
from test_fill_loops import function_body


class Popcount(unittest.TestCase):
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
        self.assertEqual(self.native(self.work/"main.goose", level), expected)
        for engine, result in self.engines(path):
            with self.subTest(engine=engine):
                self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
                self.assertEqual(result.stdout, expected)

    def test_unsigned_widths_and_final_locals(self):
        functions = []; calls = []; answers = []
        for width, counter in ((8,"u8"),(16,"i64"),(32,"i32"),(64,"i8")):
            functions.append(f'''recursive fn tally{width}(value:u{width}) {{
    var bits=value; var count:{counter}=0;
    while bits!=0 {{ bits&=bits-1; count++; }}
    print(bits," ",count);
}}''')
            for value in (0,1,1<<(width-1),(1<<width)-1,0x55):
                calls.append(f"tally{width}({value:#x});")
                answers.append(f"0 {value.bit_count()}\n")
        source = "\n".join(functions)+"\nfn main() {"+"".join(calls)+"}"
        for level in (0,2):
            for debug in (False,True):
                path, stats = self.compile(level, debug=debug, text=source)
                for width in (8,16,32,64):
                    opcode = 0x69
                    if width == 64:
                        opcode = 0x7b
                    with self.subTest(level=level,debug=debug,width=width):
                        body = function_body(path, stats, f"tally{width}")
                        self.assertEqual(list(strip.instructions(body)).count(opcode), 1)
                self.qualify(path, level, "".join(answers))

    def test_alias_calls_and_other_loop_bodies_keep_scalar_behavior(self):
        source = '''var calls=0;
fn lower(value:u16)->u16 { calls++; return value-1; }
recursive fn alias(value:u16) {
    var bits=value; var count=0;
    while bits!=0 { bits&=bits-1; count++; }
    let kept:const u16& = bits; print(kept," ",count);
}
recursive fn captured(value:u16) {
    var bits=value; var count=0;
    while bits!=0 { bits&=bits-1; count++; }
    recursive fn read()->u16 { return bits; }
    print(read()," ",count);
}
recursive fn called(value:u16) {
    calls=0; var bits=value; var count=0;
    while bits!=0 { bits&=lower(bits); count++; }
    print(bits," ",count," ",calls);
}
recursive fn extra(value:u16) {
    var seen=0; var bits=value; var count=0;
    while bits!=0 { bits&=bits-1; count++; seen++; }
    print(bits," ",count," ",seen);
}
recursive fn seeded(value:u16) {
    var bits=value; var count=5;
    while bits!=0 { bits&=bits-1; count++; }
    print(bits," ",count);
}
recursive fn decrement(value:u16) {
    var bits=value; var count=0;
    while bits!=0 { bits&=bits-1; count--; }
    print(bits," ",count);
}
recursive fn signed(value:i16) {
    var bits=value; var count=0;
    while bits!=0 { bits&=bits-1; count++; }
    print(bits," ",count);
}
'''
        calls = []; answers = []
        for value in (0,0x8001,0xffff):
            count = value.bit_count()
            for name in ("alias","captured","called","extra","seeded","decrement"):
                calls.append(f"{name}({value:#x});")
            calls.append(f"signed({value&0x7fff:#x});")
            answers.extend([f"0 {count}\n"]*2+[f"0 {count} {count}\n"]*2+
                           [f"0 {count+5}\n",f"0 {-count}\n",f"0 {(value&0x7fff).bit_count()}\n"])
        source += "fn main() {"+"".join(calls)+"}"
        for level in (0,2):
            for debug in (False,True):
                path, stats = self.compile(level, debug=debug, text=source)
                for name in ("alias","captured","called","extra","seeded","decrement","signed"):
                    body = list(strip.instructions(function_body(path, stats, name)))
                    with self.subTest(level=level,debug=debug,function=name):
                        self.assertNotIn(0x69, body)
                        self.assertNotIn(0x7b, body)
                self.qualify(path, level, "".join(answers))

    def test_every_u16_mask_with_wrapping_checksum(self):
        source = '''recursive fn count_bits(mask:u16)->i64 {
    var bits=mask; var count=0;
    while bits!=0 { bits&=bits-1; count++; }
    return count;
}
fn main() {
    var total=0; var rolling:u64=0;
    for value in 65536 {
        let n=count_bits(value as u16); total+=n;
        rolling=rolling*131+(n as u64);
    }
    print(total," ",rolling);
}'''
        total = 0; rolling = 0
        for value in range(65536):
            count = value.bit_count()
            total += count; rolling = (rolling*131+count)&((1<<64)-1)
        for level in (0,2):
            for debug in (False,True):
                path, stats = self.compile(level, debug=debug, text=source)
                body = function_body(path, stats, "count_bits")
                with self.subTest(level=level,debug=debug):
                    self.assertEqual(list(strip.instructions(body)).count(0x69), 1)
                self.qualify(path, level, f"{total} {rolling}\n")

    def test_nonzero_counter_keeps_wrapping_and_debug_traps(self):
        source = '''recursive fn overflow(value:u8) {
    var bits=value; var count:i8=127;
    while bits!=0 { bits&=bits-1; count++; }
    print(bits," ",count);
}
fn main() { print("before"); overflow(1); }'''
        for level in (0,2):
            for debug in (False,True):
                path, _ = self.compile(level, debug=debug, text=source)
                if not debug:
                    self.qualify(path, level, "before\n0 -128\n")
                    continue
                for engine, result in self.engines(path):
                    with self.subTest(level=level,debug=debug,engine=engine):
                        self.assertNotEqual(result.returncode, 0)
                        self.assertEqual(result.stdout, "before\n")
                        self.assertIn("overflow", result.stderr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose",type=Path,default=strip.GOOSE)
    parser.add_argument("--node",default=strip.NODE)
    parser.add_argument("--cc",default=prefix.CC)
    args, remaining = parser.parse_known_args()
    strip.GOOSE = prefix.GOOSE = args.goose.resolve()
    strip.NODE = args.node; prefix.CC = args.cc
    unittest.main(argv=[sys.argv[0],*remaining])
