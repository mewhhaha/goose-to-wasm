#!/usr/bin/env python3
"""Keep containing walkers, array storage and image effects explicit."""
import argparse
from pathlib import Path
import sys
import tempfile
import unittest

import test_packed_layout_boundaries as packed


class VarintBoundaries(unittest.TestCase):
    compile=packed.PackedLayoutBoundaries.compile

    def check_gate(self,source,message):
        with tempfile.TemporaryDirectory(dir=packed.ROOT/'build') as name:
            for level in (0,2):
                native,_=self.compile(Path(name),source,'native',level)
                self.assertEqual(native.returncode,0,native.stdout+native.stderr)
                direct,path=self.compile(Path(name),source,'wasm-direct',level)
                self.assertNotEqual(direct.returncode,0)
                self.assertFalse(path.exists())
                self.assertIn(message,direct.stdout+direct.stderr)

    def test_byte_record_containing_array_tail_requires_general_walker(self):
        self.check_gate('struct R{n:varint,values:u8[u8]} fn main(){let r=R{1,[2]};print(r.n);}',
                        'byte-walked records currently require varint or fixed-size fields')

    def test_containing_byte_record_requires_general_walker(self):
        self.check_gate('struct Inner{n:varint} struct Outer{tag:u8,inner:Inner} fn main(){let r=Outer{1,Inner{2}};print(r.inner.n);}',
                        'containing byte-walked records require general image walkers')

    def test_varint_variant_payload_requires_general_walker(self):
        self.check_gate('enum E{Data{n:varint},Empty} fn main(){let e:E..=E.Data{1};match e{Data p=>print(p.n),Empty=>{}}}',
                        'variable enum payloads require one final nonresizable array tail')

    def test_varint_array_elements_remain_separate(self):
        self.check_gate('fn main(){let values:varint[>..]=[1,-2];for n in values{print(n);}}',
                        'varint storage is not supported')

    def test_byte_record_image_effects_remain_separate(self):
        self.check_gate('struct R{n:varint} fn target()->R{recursive fn leave(){return R{1} from target;}leave();return R{0};} fn main(){let r=target();print(r.n);}',
                        'this owned nonlocal target requires additional staging and landing support')

    def test_named_replacement_observations_require_bounded_overlap_proof(self):
        cases=(
            '''struct R{n:varint,w:u16}
recursive fn make(b:bool)->R,i64,i64{let r=R{1,2};let kept:const u16& =r.w;
if b{return r,0,0;}return R{65,7},kept as i64,r.w as i64;}
fn main(){let r,a,b=make(false);print(a,b);}''',
            '''struct R{a:varint,gap:u8[16],b:varint}
recursive fn make(flag:bool)->R,i64{let r=R{0,[255;16],1};let kept:const varint& =r.b;
if flag{return r,0;}return R{9223372036854775807,[255;16],9223372036854775807},kept;}
fn main(){let r,n=make(false);print(n);}''',
        )
        for source in cases:
            self.check_gate(source,'observing a named varint record after replacement requires a bounded overlap proof')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--goose',type=Path,default=packed.GOOSE)
    args,remaining=parser.parse_known_args();packed.GOOSE=args.goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
