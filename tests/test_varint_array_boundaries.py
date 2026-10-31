#!/usr/bin/env python3
"""Retain the varint-element storage, containing and overlap frontiers."""
import argparse
from pathlib import Path
import sys
import unittest

import test_packed_layout_boundaries as packed
import test_varint_boundaries as boundaries


class VarintArrayBoundaries(unittest.TestCase):
    compile=boundaries.VarintBoundaries.compile
    check_gate=boundaries.VarintBoundaries.check_gate

    def test_varint_element_record_tails_require_general_walkers(self):
        self.check_gate('struct R{tag:u8,values:varint[u8]} fn main(){let r=R{1,[64,-65]};print(r.values.len);}',
                        'containing varint-element images require general record walkers')

    def test_array_targets_require_dedicated_image_staging(self):
        cases=(
            '''fn target()->varint[u8]{recursive fn leave(){return[64,-65] from target;}leave();return[];}
fn main(){let a=target();print(a);}''',
            '''inline fn stop()->i64{return 9 from canceled;}
inline fn canceled()->i64{return[stop();2] from target;}
inline fn target<F>()->varint[u8]{print(F());return[0;128];}
fn main(){let a=target(){canceled()};print(a.len," ",a);let b:varint[u16]=copy(a);print(b);}''',
        )
        for source in cases:
            self.check_gate(source,'varint-element nonlocal targets require dedicated image staging')

    def test_named_array_replacement_observations_require_overlap_proof(self):
        self.check_gate('''recursive fn first(xs:const varint[:])->const varint&{for x in xs{return x;}abort("empty");}
recursive fn make(flag:bool)->varint[u8],i64{
let a:varint[u8]=[1,64];let p:const varint& =first(a);
if flag{return a,0;}return[8192],p;}
fn main(){let a,p=make(false);print(p);}''',
                        'observing a named varint array after replacement requires a bounded overlap proof')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--goose',type=Path,default=packed.GOOSE)
    args,remaining=parser.parse_known_args();packed.GOOSE=args.goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
