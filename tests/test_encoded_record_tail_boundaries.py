#!/usr/bin/env python3
"""Bound encoded record tails to fixed prefixes and normal result channels."""
import argparse
from pathlib import Path
import sys
import unittest

import test_packed_layout_boundaries as packed
import test_varint_boundaries as boundaries


class EncodedRecordTailBoundaries(unittest.TestCase):
    compile=boundaries.VarintBoundaries.compile
    check_gate=boundaries.VarintBoundaries.check_gate

    def test_variable_enum_envelopes_require_separate_staging(self):
        for tail in ('u8[varint]','varint[u8]','varint[varint]'):
            declaration='enum E{Empty,Data{tag:u8,values:'+tail+'}}'
            self.check_gate(declaration+'''fn main(){let e:E..=E.Data{1,[7;128]};
match e{Data p=>print(p.values.len),_=>{}}}''',
                'encoded record tails in variable enums require separate image staging')

    def test_actual_record_targets_remain_gated_across_inline_stacks(self):
        for tail in ('u8[varint]','varint[u8]','varint[varint]'):
            for modifier in ('recursive','inline'):
                self.check_gate(f'''struct R{{tag:u8,values:{tail}}}
{modifier} fn leave(){{return R{{1,[7;128]}} from target;}}
{modifier} fn target()->R{{leave();return R{{2,[]}};}}
fn main(){{let r=target();print(r.values.len);}}''',
                    'encoded record-tail nonlocal targets require dedicated image staging')

    def test_later_named_replacement_observations_require_overlap_proof(self):
        self.check_gate('''struct R{tag:u8,word:u16,values:varint[varint]}
recursive fn make(flag:bool)->R,i64{var r=R{1,7,[64;128]};let p:const u16& =r.word;
if flag{return r,0;}return R{2,9,[-65;127]},p;}
fn main(){let r,n=make(false);print(n," ",r.values.len);}''','bounded overlap proof')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--goose',type=Path,default=packed.GOOSE)
    args,remaining=parser.parse_known_args();packed.GOOSE=args.goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
