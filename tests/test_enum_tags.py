#!/usr/bin/env python3
"""Inspect compact enum tags, empty alternatives and fixed array strides."""
import argparse
from pathlib import Path
import sys
import tempfile
import unittest

import test_array_images as images


class EnumTagImages(unittest.TestCase):
    def check(self, source, expected, count):
        checker = images.ArrayImages("test_packed_record_elements_keep_their_byte_stride")
        with tempfile.TemporaryDirectory(dir=images.ROOT / "build") as name:
            for level in (0, 2):
                with self.subTest(level=level):
                    output = checker.compile(Path(name), source, level)
                    checker.check_engines(output, 1, bytes.fromhex(expected), count, 1)

    def test_fixed_enum_payloads_have_no_tag_or_trailing_padding(self):
        self.check('''enum E { Empty, Data { tag:u8,word:u16 } }
var values:E[u8] = [E.Data{0x11,0x2233},E.Data{0x44,0x5566}];
export fn count()->i64 { values.len } fn main() {}''', "020111332201446655", 2)

    def test_empty_alternatives_have_no_payload_slot(self):
        self.check('''enum E { A, B }
var values:E[u8] = [E.A,E.B,E.A];
export fn count()->i64 { values.len } fn main() {}''', "03000100", 3)

    def test_tag_width_changes_after_256_variants(self):
        for count, width in ((256, 1), (257, 2)):
            variants = ",".join(f"V{n}" for n in range(count))
            source = f'''enum E {{ {variants} }}
var values:E[u8] = [E.V{count-1},E.V0];
export fn count()->i64 {{ values.len }} fn main() {{}}'''
            expected = bytes([2]) + (count-1).to_bytes(width,"little") + bytes(width)
            with self.subTest(variants=count):
                self.check(source, expected.hex(), 2)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--goose", type=Path, default=images.GOOSE)
    args, remaining = parser.parse_known_args()
    images.GOOSE = args.goose.resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
