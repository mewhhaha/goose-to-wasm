#!/usr/bin/env python3
"""Check nonlocal enum tags and sparse Limited images on both engines."""
import argparse
from pathlib import Path
import sys
import unittest

import test_enum_images as images
import test_regions as regions


class EnumImageReturns(unittest.TestCase):
    setUp=regions.StableRegions.setUp
    compile=regions.StableRegions.compile
    engines=regions.StableRegions.engines

    def test_catch_preserves_tag_width_at_256_variants(self):
        checker=images.EnumImages('test_empty_image_reserves_no_inactive_payload')
        for count,width in ((256,1),(257,2)):
            variants=','.join(f'V{n}' for n in range(count))
            source=f'''enum E {{{variants}}}
recursive fn leave() {{return E.V{count-1} from target;}}
recursive fn target()->E.. {{leave();return E.V0;}}
var e:E..=target();'''
            with self.subTest(variants=count): checker.check_bytes(source,(count-1).to_bytes(width,'little').hex())

    def test_sparse_limited_prefix_retains_physical_cursor(self):
        source='''enum E {Data{id:u8,values:u8[..]},Empty}
recursive fn stop()->u8 {return 9 from canceled;}
recursive fn canceled()->i64 {return E.Data{17,[stop();70000]} from target;}
recursive fn target()->E.. {print(canceled());return E.Empty;}
fn main() {let e=target();match e {Data &p=>print(p.id as i64," ",p.values.cap," ",p.values.len," ",p.values[0] as i64," ",p.values[66000] as i64),Empty=>{}}}'''
        for level in (0,2):
            path,info=self.compile(source,level)
            self.assertEqual(info['region_count'],1)
            for engine,observed in self.engines(path,info):
                with self.subTest(level=level,engine=engine):
                    self.assertEqual(observed['error'],'')
                    self.assertEqual(observed['numbers'],['9','17','70000','70000','1','0'])
                    self.assertEqual(observed['pages'],3)


if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--goose',type=Path,default=regions.GOOSE)
    args,remaining=parser.parse_known_args(); regions.GOOSE=args.goose.resolve(); images.GOOSE=regions.GOOSE
    unittest.main(argv=[sys.argv[0],*remaining])
