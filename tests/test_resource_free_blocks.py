#!/usr/bin/env python3
"""Qualify region-free blocks inside owner activations and retained frontiers."""
import argparse
from pathlib import Path
import sys
import unittest

import test_loop_ordinals as ordinal
import test_prefix_resolution as prefix
import test_strip_loops as strip
from test_fill_loops import function_body

REFERENCE=None
POSITIVE='''recursive fn leaf(xs:i64[:])->i64 { return xs[0]+xs[1]; }
export fn run(n:i64)->i64 {
    var kept:i64[>..]=[n,n+1]; var total=0;
    for i in 17 { total+=leaf(kept); }
    var later:i64[>..]=[n+2]; return total+later[0];
}
fn main() {
    print(run(7)," ",run(8)); var checksum=0;
    for i in 1000 { checksum+=run(i%4); } print(checksum);
}
'''


class ResourceFreeBlocks(unittest.TestCase):
    setUp=strip.StripLoops.setUp;compile=strip.StripLoops.compile
    native=prefix.PrefixResolution.native;qualify=ordinal.LoopOrdinals.qualify

    def reference(self,level,source,debug=False):
        compiler=strip.GOOSE
        try:
            strip.GOOSE=REFERENCE
            path,stats=self.compile(level,text=source,debug=debug)
            return function_body(path,stats,"run")
        finally:strip.GOOSE=compiler

    def test_borrowed_owner_views_and_leaf_calls_do_not_consume_regions(self):
        self.qualify(POSITIVE,"264 299\n71500\n")
        if REFERENCE:
            for level in (0,2):
                for debug in (False,True):
                    path,stats=self.compile(level,text=POSITIVE,debug=debug)
                    current=list(strip.instructions(function_body(path,stats,"run")))
                    previous=list(strip.instructions(self.reference(level,POSITIVE,debug)))
                    with self.subTest(level=level,debug=debug):
                        self.assertEqual(previous.count(0x23)-current.count(0x23),1)
                        self.assertEqual(previous.count(0x24)-current.count(0x24),1)

    def test_foreign_calls_allocations_addresses_and_direct_exits_keep_scopes(self):
        bodies=[
            ("extern fn foreign(value:i64)->i64;","total+=foreign(i);"),
            ("recursive fn leaf(xs:i64[:])->i64 { return xs[0]; }","total+=leaf(&kept);"),
            ("recursive fn allocated(value:i64)->i64 { var xs:i64[>..]=[value]; return xs[0]; }","total+=allocated(i);"),
            ("","var xs:i64[>..]=[i]; total+=xs[0];"),
            ("","let alias:i64& =total; alias+=i;"),
            ("","if i==2 { continue; } if i==5 { break; } total+=i;"),
            ("","if i==5 { return kept[0]; } total+=i;"),
        ]
        for declarations,body in bodies:
            source=declarations+'''export fn run(n:i64)->i64 {
    var kept:i64[>..]=[n]; var total=0; for i in 17 { '''+body+''' } return total+kept[0];
} fn main() {}'''
            for level in (0,2):
                path,stats=self.compile(level,text=source)
                current=function_body(path,stats,"run")
                if REFERENCE:
                    with self.subTest(body=body,level=level):self.assertEqual(current,self.reference(level,source))


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--goose",type=Path,default=strip.GOOSE)
    parser.add_argument("--node",default=strip.NODE);parser.add_argument("--cc",default=prefix.CC)
    parser.add_argument("--reference-goose",type=Path);args,remaining=parser.parse_known_args()
    strip.GOOSE=prefix.GOOSE=args.goose.resolve();strip.NODE=args.node;prefix.CC=args.cc
    if args.reference_goose:REFERENCE=args.reference_goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
