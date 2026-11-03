#!/usr/bin/env python3
"""Qualify loops without index bindings across source changes and exits."""
import argparse
from pathlib import Path
import subprocess
import sys
import unittest

import test_prefix_resolution as prefix
import test_strip_loops as strip


class LoopOrdinals(unittest.TestCase):
    setUp = strip.StripLoops.setUp
    compile = strip.StripLoops.compile
    native = prefix.PrefixResolution.native

    def qualify(self, source, expected):
        for level in (0, 2):
            for debug in (False, True):
                path, _ = self.compile(level, debug=debug, text=source)
                self.assertEqual(self.native(self.work / "main.goose", level), expected)
                for engine, command in (
                    ("v8", [strip.NODE, str(strip.ROOT / "scripts/run_wasm.mjs"), str(path)]),
                    ("wasmtime", [sys.executable, str(strip.ROOT / "scripts/run_wasmtime.py"), str(path)]),
                ):
                    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
                    with self.subTest(level=level, debug=debug, engine=engine):
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertEqual(result.stdout, expected)

    def test_varint_growth_and_rebinding_survive_continue(self):
        self.qualify('''fn main() {
    var grown:varint[>..]=[1,64];
    for value in grown {
        print(value);
        if value==1 { grown.push(-65); continue; }
        if value==64 { grown.push(8192); continue; }
    }
    print(grown);
    var first:varint[]=[1,64,-65,8192];
    var second:varint[]=[-8193,2,300,4];
    var view:varint[:]=first[..];
    for value in view {
        print(value);
        if value==1 { view=second[..]; continue; }
        if value==300 { view=first[..]; continue; }
    }
}''', "1\n64\n-65\n8192\n[1, 64, -65, 8192]\n1\n2\n300\n8192\n")

    def test_byref_binding_and_owned_locals_survive_continue_and_return(self):
        self.qualify('''recursive fn visit(values:i64[:])->i64 {
    for &value in values {
        let temporary:i64[>..]=[value,value+1];
        if value==2 { value=20; continue; }
        if value==4 { return temporary[1]; }
        value+=temporary[1];
    }
    return -1;
}
fn main() {
    var values=[1,2,3,4];
    print(visit(values[..])," ",values);
    print(visit(values[..])," ",values);
}''', "5 [3, 20, 7, 4]\n5 [7, 41, 15, 4]\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=strip.GOOSE)
    parser.add_argument("--node", default=strip.NODE)
    parser.add_argument("--cc", default=prefix.CC)
    args, remaining = parser.parse_known_args()
    strip.GOOSE = prefix.GOOSE = args.goose.resolve()
    strip.NODE = args.node
    prefix.CC = args.cc
    unittest.main(argv=[sys.argv[0], *remaining])
