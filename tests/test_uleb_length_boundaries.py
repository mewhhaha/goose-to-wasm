#!/usr/bin/env python3
"""Bound the unsigned-prefix walker, target and named-Grow alias contract."""
import argparse
from pathlib import Path
import sys
import unittest

import test_packed_layout_boundaries as packed
import test_varint_boundaries as boundaries


class ULEBLengthBoundaries(unittest.TestCase):
    compile=boundaries.VarintBoundaries.compile
    check_gate=boundaries.VarintBoundaries.check_gate

    def test_containing_combined_array_requires_record_walkers(self):
        self.check_gate('struct R{tag:u8,values:varint[varint]} fn main(){let r=R{1,[64,-65]};print(r.values.len);}',
                        'containing varint-length arrays require general record walkers')

    def test_containing_unsigned_varint_lengths_require_record_walkers(self):
        self.check_gate('struct R{tag:u8,values:u8[varint]} fn main(){let r=R{1,[7;128]};print(r.values.len);}',
                        'containing varint-length arrays require general record walkers')

    def test_nonlocal_targets_remain_gated_across_inline_stacks(self):
        for modifier in ('recursive','inline'):
            self.check_gate(f'''{modifier} fn leave(){{return[7;128] from target;}}
{modifier} fn target()->u8[varint]{{leave();return[];}}
fn main(){{let a=target();print(a.len);}}''',
                            'varint-length nonlocal targets require dedicated image staging')

    def test_statically_oversized_canceled_fill_keeps_explicit_wasm32_frontier(self):
        self.check_gate('''recursive fn make<F>()->u8[varint]{return[F();4294967296];}
recursive fn target(flag:bool)->i64{let a=make(){if flag{return 7;}else{8}};return a.len;}
fn main(){print(target(true));}''',
                        'varint-length fills beyond the wasm32 element limit are not supported')

    def test_named_grow_later_calls_and_reads_require_prefix_alias_proof(self):
        for reader in (
            'recursive fn poison(a:u8[>..]&)->i64{for i in 0..10{a[i]=255;}return 9;}',
            'recursive fn poison(a:u8[>..]&)->i64{return a[0];}',
        ):
            self.check_gate(reader+'''recursive fn make()->u8[varint],i64{
var a:u8[>..]=[7;128];return a,poison(a);}
fn main(){let a,n=make();print(n);print(a.len);}''','bounded overlap proof')
        self.check_gate('''recursive fn make()->u8[varint],i64{
var a:u8[>..]=[7;128];let p:u8& =a[0];
fn poison()->i64{p=255;for i in 1..10{a[i]=255;}return 9;}
return a,poison();}fn main(){let a,n=make();print(n);print(a.len);}''','bounded overlap proof')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--goose',type=Path,default=packed.GOOSE)
    args,remaining=parser.parse_known_args();packed.GOOSE=args.goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
