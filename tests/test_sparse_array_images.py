#!/usr/bin/env python3
"""Read valid image elements beyond a canceled producer's committed suffix."""
import argparse
from pathlib import Path
import sys
import unittest

import test_regions


class SparseArrayImages(unittest.TestCase):
    setUp = test_regions.StableRegions.setUp
    compile = test_regions.StableRegions.compile
    engines = test_regions.StableRegions.engines

    def check_extent(self, owner, element, count, index, preamble="", field=""):
        source = f'''{preamble}
recursive fn stop() -> {element} {{ return 9 from canceled; }}
recursive fn canceled() -> i64 {{ return [stop();{count}] from target; }}
recursive fn target() -> {owner} {{ print(canceled()); return []; }}
fn main() {{ let value=target(); print(value.len); print(value[{index}]{field} as i64); }}'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            self.assertEqual(runtime["region_count"], 1)
            for engine, observed in self.engines(path, runtime):
                with self.subTest(level=level, engine=engine):
                    self.assertEqual(observed["error"], "")
                    self.assertEqual(observed["numbers"], ["9", str(count), "0"])
                    self.assertEqual(observed["pages"], 3)

    def test_var_image_maps_its_advertised_extent(self):
        self.check_extent("u8[u32]", "u8", 70000, 66000)

    def test_limited_image_maps_its_advertised_capacity(self):
        self.check_extent("u8[..]", "u8", 70000, 66000)

    def test_packed_image_maps_its_full_byte_extent(self):
        self.check_extent("Cell[u32]", "Cell", 23000, 22000,
                          "struct Cell { tag:u8,value:u16 }", ".value")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--goose", type=Path, default=test_regions.GOOSE)
    args, remaining = parser.parse_known_args()
    test_regions.GOOSE = args.goose.resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
