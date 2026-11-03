#!/usr/bin/env python3
"""Keep SIMD writeback and restore scalar write-through for unsupported bodies."""
import argparse
from pathlib import Path
import sys
import unittest

import test_lane_writeback as lanes
from test_fill_loops import function_body


class SimdOnlyWriteback(lanes.LaneWriteback):
    def test_unsupported_ordinal_body_keeps_single_write_through_loop(self):
        for width in (4,8):
            path,stats=self.compile(width,0,"ordinal")
            body=function_body(path,stats,"tick")
            self.assertEqual(list(lanes.simd_ops(body)),[])
            # Literal initialization and pre-hook XOR are followed by one
            # group/tail loop; no additional deferred flush is emitted.
            from test_strip_loops import instructions
            self.assertEqual(list(instructions(body)).count(0x36),3*width+1)


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--goose",type=Path,default=lanes.GOOSE)
    parser.add_argument("--node",default=lanes.NODE);args,remaining=parser.parse_known_args()
    lanes.GOOSE=args.goose.resolve();lanes.NODE=args.node
    unittest.main(argv=[sys.argv[0],*remaining])
