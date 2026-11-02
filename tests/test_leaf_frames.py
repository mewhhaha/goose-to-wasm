#!/usr/bin/env python3
"""Qualify frame-free numeric leaves and ownership/addressing fallbacks."""
import argparse
from pathlib import Path
import subprocess
import sys
import unittest

import test_prefix_resolution as prefix
import test_strip_loops as strip
from test_fill_loops import function_body

POSITIVE = '''extern fn root(x:f64)->f64="sqrt";
recursive fn kernel(xs:i64[:],limit:i64)->i64 {
    var sum=0;
    for i in xs.len {
        if i==1 { continue; }
        sum+=xs[i]; if sum>limit { return sum; }
    }
    return sum;
}
recursive fn numeric(x:f64)->f64 { root(x)+1.0 }
fn main() {
    var rows:i64[>..]=[2,3,4,5]; var captured=0;
    recursive fn touch() { captured++; }
    touch(); print(kernel(rows,100)," ",kernel(rows,3)," ",numeric(9.0)," ",captured);
}
'''
FALLBACK = '''recursive fn referenced(value:i64)->i64 {
    let alias:i64& = value; alias+=2; return alias;
}
recursive fn called(value:i64)->i64 { referenced(value) }
recursive fn produced()->i64[>..] { return [7,8]; }
recursive fn viewed(xs:i64[:])->i64 {
    for &x in xs { x+=1; }
    return xs[0];
}
fn main() {
    var rows:i64[>..]=produced();
    print(referenced(3)," ",called(4)," ",viewed(rows)," ",rows);
}
'''
PREFIX = prefix.ENABLE+'''struct Packet { head:i64[2], values:i64[>..] }
recursive fn make(n:i64)->Packet { return Packet {[n,n+1],[9]}; }
recursive fn read_prefix(xs:i64[:])->i64 {
    var total=0; for value in xs { total+=value; } return total;
}
fn main() {
    let packet=make(10); let kept=packet.head[..]; let temporary=make(3);
    print(read_prefix(kept)," ",read_prefix(temporary.head[..])," ",packet.values[0]);
    packet.head[0]+=2;
    print(read_prefix(kept)," ",packet.head[0]," ",enable().len);
}
'''


class LeafFrames(unittest.TestCase):
    setUp = strip.StripLoops.setUp
    compile = strip.StripLoops.compile
    native = prefix.PrefixResolution.native

    def qualify(self, source, expected, names, frame_free):
        for level in (0,2):
            for debug in (False,True):
                path,stats=self.compile(level,debug=debug,text=source)
                for name in names:
                    ops=list(strip.instructions(function_body(path,stats,name)))
                    with self.subTest(level=level,debug=debug,function=name):
                        if frame_free:
                            self.assertNotIn(0x23,ops)
                            self.assertNotIn(0x24,ops)
                        else:
                            self.assertIn(0x24,ops)
                self.assertEqual(self.native(self.work/"main.goose",level),expected)
                for engine,command in (
                    ("v8",[strip.NODE,str(strip.ROOT/"scripts/run_wasm.mjs"),str(path)]),
                    ("wasmtime",[sys.executable,str(strip.ROOT/"scripts/run_wasmtime.py"),str(path)]),
                ):
                    with self.subTest(level=level,debug=debug,engine=engine):
                        result=subprocess.run(command,capture_output=True,text=True,timeout=30)
                        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                        self.assertEqual(result.stdout,expected)

    def test_numeric_views_intrinsics_and_unrelated_captures_need_no_frame(self):
        self.qualify(POSITIVE,"11 6 4.0 1\n",["kernel","numeric"],True)

    def test_addresses_calls_owners_and_reference_loops_keep_frames(self):
        self.qualify(FALLBACK,"5 6 8 [8, 9]\n",["referenced","called","produced","viewed"],False)

    def test_leaf_keeps_caller_prefix_mapping_active(self):
        self.qualify(PREFIX,"21 7 9\n23 12 1\n",["read_prefix"],True)


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose",type=Path,default=strip.GOOSE)
    parser.add_argument("--node",default=strip.NODE)
    parser.add_argument("--cc",default=prefix.CC)
    args,remaining=parser.parse_known_args()
    strip.GOOSE=prefix.GOOSE=args.goose.resolve()
    strip.NODE=prefix.NODE=args.node
    prefix.CC=args.cc
    unittest.main(argv=[sys.argv[0],*remaining])
