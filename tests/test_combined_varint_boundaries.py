#!/usr/bin/env python3
"""Retain alias and cancellation gates with encoded counts and elements."""
import argparse
from pathlib import Path
import sys
import unittest

import test_packed_layout_boundaries as packed
import test_varint_boundaries as boundaries


class CombinedVarintBoundaries(unittest.TestCase):
    compile=boundaries.VarintBoundaries.compile
    check_gate=boundaries.VarintBoundaries.check_gate

    def test_named_grow_later_calls_require_overlap_proof(self):
        self.check_gate('''recursive fn mutate(a:varint[>..]&)->i64{a.clear();a.push(0);return 9;}
recursive fn make()->varint[varint],i64{var a:varint[>..]=[64;128];return a,mutate(a);}
fn main(){let a,n=make();print(n," ",a);}''','bounded overlap proof')

    def test_nonlocal_targets_remain_gated_across_inline_stacks(self):
        for modifier in ('recursive','inline'):
            self.check_gate(f'''{modifier} fn leave(){{return[64;128] from target;}}
{modifier} fn target()->varint[varint]{{leave();return[];}}
fn main(){{let a=target();print(a.len);}}''',
                'varint-length nonlocal targets require dedicated image staging')

    def test_cancelable_dispatch_requires_raw_landing_proof(self):
        self.check_gate('''enum C{A,B} var a:varint[>..]=[];
recursive fn values<F>(c:C.A)->varint[varint]{return[F();128];}
recursive fn values<F>(c:C.B)->varint[varint]{return[F();128];}
recursive fn target(flag:bool)->i64{let c:C=if flag{C.A}else{C.B};
a.append(values(c){if flag{return 7;}else{64}});return 0;}
fn main(){print(target(true));a.push(9223372036854775807);print(a);}''',
                'cancelable varint value results require qualified raw landing')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--goose',type=Path,default=packed.GOOSE)
    args,remaining=parser.parse_known_args();packed.GOOSE=args.goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
