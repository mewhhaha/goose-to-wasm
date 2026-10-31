#!/usr/bin/env python3
"""Keep mutable encoded-image effects and Value-form escape gates explicit."""
import argparse
from pathlib import Path
import sys
import unittest

import test_packed_layout_boundaries as packed
import test_varint_boundaries as boundaries


class VarintGrowBoundaries(unittest.TestCase):
    compile=boundaries.VarintBoundaries.compile
    check_gate=boundaries.VarintBoundaries.check_gate

    def test_named_grow_later_observations_require_overlap_proof(self):
        for source in (
            '''recursive fn reset(a:varint[>..]&)->i64{a.clear();a.push(0);return a.len;}
recursive fn make()->varint[>..],i64{var a:varint[>..]=[-9223372036854775808,-9223372036854775808];return a,reset(a);}
fn main(){let a,n=make();print(n," ",a);}''',
            '''recursive fn grow(a:varint[>..]&)->i64{a.push(8192);return a.len;}
recursive fn make()->varint[u8],i64,varint[u16]{var a:varint[>..]=[1,64];return a,grow(a),copy(a);}
fn main(){let a,n,b=make();print(a," ",n," ",b);}''',
        ):
            self.check_gate(source,'bounded overlap proof')

    def test_grow_nonlocal_targets_require_dedicated_staging(self):
        for modifier in ('recursive','inline'):
            self.check_gate(f'''{modifier} fn leave(){{return[64,-65] from target;}}
{modifier} fn target()->varint[>..]{{leave();return[];}}
fn main(){{let a=target();print(a);}}''',
                            'varint-element nonlocal targets require dedicated image staging')

    def test_cancelable_value_form_dispatch_requires_raw_landing_proof(self):
        for count in (3,128):
            self.check_gate(f'''enum C{{A,B}}
var a:varint[>..]=[];
recursive fn values<F>(c:C.A)->varint[u8]{{return[F();{count}];}}
recursive fn values<F>(c:C.B)->varint[u8]{{return[F();{count}];}}
recursive fn target(flag:bool)->i64{{let c:C=if flag{{C.A}}else{{C.B}};
a.append(values(c){{if flag{{return 7;}}else{{64}}}});return 0;}}
fn main(){{print(target(true));a.push(9223372036854775807);print(a);}}''',
                            'cancelable varint value results require qualified raw landing')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--goose',type=Path,default=packed.GOOSE)
    args,remaining=parser.parse_known_args();packed.GOOSE=args.goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
