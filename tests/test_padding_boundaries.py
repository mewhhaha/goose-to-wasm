#!/usr/bin/env python3
"""Keep padding's unproved suffix, frame, enum and overlap shapes explicit."""
import argparse
from pathlib import Path
import sys
import tempfile
import unittest

import test_packed_layout_boundaries as packed


class PaddingBoundaries(unittest.TestCase):
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

    def test_padded_frame_objects_remain_separate(self):
        self.check_gate('struct R{a:u8,pad 1,values:i64[>..]} fn main(){let r=R{1,[2]};print(r.values.len);}',
                        'padding in frame objects is not supported')

    def test_padding_after_variable_tail_requires_suffix_walker(self):
        for suffix in ('pad 1','pad'):
            self.check_gate(f'struct R{{values:u8[u8],{suffix}}} fn main(){{let r=R{{[1]}};print(r.values.len);}}',
                            'padding after an owned tail requires a suffix-aware image walker')

    def test_variable_enum_fixed_payload_bare_gap_is_not_assumed_equivalent(self):
        for init,extra in [('E.A{0x11,0x22334455}',''),('make()','recursive fn make()->E.A{return E.A{0x11,0x22334455};}')]:
            self.check_gate(f'enum E{{A{{a:u8,pad,b:u32}},Empty}} {extra} fn main(){{let e:E..={init};match e{{A p=>print(p.b as i64),Empty=>{{}}}}}}',
                            'bare-pad gaps require physical-layout qualification')

    def test_padded_images_remain_outside_effect_proof(self):
        self.check_gate('''struct P{a:u8,pad 1,b:u16}
fn target()->P[u8]{recursive fn leave(){return [P{1,2}] from target;}leave();return [];}
fn main(){let p=target();print(p.len);}''','this owned nonlocal target requires additional staging and landing support')

    def test_oversized_and_cumulative_padding_cannot_wrap(self):
        for fields in ('pad 9223372036854775807','pad 200000000,pad 200000000'):
            with tempfile.TemporaryDirectory(dir=packed.ROOT/'build') as name:
                for level in (0,2):
                    direct,path=self.compile(Path(name),f'struct P{{{fields}}} fn main(){{let p=P{{}};}}','wasm-direct',level)
                    self.assertNotEqual(direct.returncode,0)
                    self.assertFalse(path.exists())
                    self.assertIn('configured linear-memory limit',direct.stdout+direct.stderr)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--goose',type=Path,default=packed.GOOSE)
    args,remaining=parser.parse_known_args();packed.GOOSE=args.goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
