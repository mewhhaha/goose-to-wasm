#!/usr/bin/env python3
"""Retain deep-reference and formatter frontiers in fixed-value rendering."""
import argparse
from pathlib import Path
import sys
import unittest

import test_packed_layout_boundaries as packed
import test_varint_boundaries as boundaries


class AggregatePrintBoundaries(unittest.TestCase):
    compile=boundaries.VarintBoundaries.compile
    check_gate=boundaries.VarintBoundaries.check_gate

    def test_reference_fields_require_deep_snapshots(self):
        for declaration,expression,annotation in (
            ('struct R{value:i64&}','R{n}',''),
            ('enum E{Empty,Data{value:i64&}}','E.Data{n}',':E'),
            ('struct R{values:const i64[:]}','R{rows[..]}',''),
        ):
            self.check_gate(declaration+'fn main(){var n=7;let rows:i64[2]=[1,2];let r'+annotation+'='+expression+';print(r);}',
                'printing aggregates containing references or slices is not supported')

    def test_slices_of_indirect_records_require_deep_snapshots(self):
        self.check_gate('''struct R{value:i64&} fn main(){var n=7;let a:R[u8]=[R{n}];print(a);}''',
            'printing slices with indirect aggregate elements is not supported')

    def test_user_formatters_keep_their_explicit_frontier(self):
        formatter='struct R{value:i64} fn format(out:u8[>..]&,r:R){out.append("custom");}'
        for declaration,expression in (
            ('','R{7}'),
            ('struct Outer{value:R}','Outer{R{7}}'),
            ('','[R{7},R{9}]'),
        ):
            self.check_gate(formatter+declaration+'fn main(){print('+expression+');}',
                'custom formatters are not supported')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--goose',type=Path,default=packed.GOOSE)
    args,remaining=parser.parse_known_args();packed.GOOSE=args.goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
