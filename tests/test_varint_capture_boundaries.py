#!/usr/bin/env python3
"""Aliases captured through a later call also require a replacement proof."""
import argparse
from pathlib import Path
import sys
import unittest

import test_packed_layout_boundaries as packed
import test_varint_boundaries as boundaries


class VarintCaptureBoundaries(unittest.TestCase):
    compile=boundaries.VarintBoundaries.compile
    check_gate=boundaries.VarintBoundaries.check_gate

    def test_later_recursive_call_cannot_hide_a_captured_alias(self):
        for reader in ('recursive fn later()->i64{return kept;}',
                       'recursive fn inner()->i64{return kept;} recursive fn later()->i64{return inner();}'):
            self.check_gate('''struct R{a:varint,gap:u8[16],b:varint}
recursive fn make(flag:bool)->R,i64{
let r=R{0,[255;16],1};let kept:const varint& =r.b;
'''+reader+'''
if flag{return r,0;}return R{9223372036854775807,[255;16],9223372036854775807},later();}
fn main(){let r,n=make(false);print(n);}''',
                            'calls after named varint record replacement require a bounded overlap proof')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--goose',type=Path,default=packed.GOOSE)
    args,remaining=parser.parse_known_args();packed.GOOSE=args.goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
