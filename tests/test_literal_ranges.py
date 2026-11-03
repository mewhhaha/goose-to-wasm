#!/usr/bin/env python3
"""Qualify bounded literal ranges and unchanged partial effects on traps."""
import argparse
from pathlib import Path
import subprocess
import sys
import unittest

import test_loop_ordinals as ordinal
import test_prefix_resolution as prefix
import test_strip_loops as strip
from test_fill_loops import function_body


class LiteralRanges(ordinal.LoopOrdinals):
    def test_small_narrow_boundary_ranges_keep_the_checked_counter_type(self):
        source = '''recursive fn narrowed()->i64 {
    var total=0; for value:u8 in 254..256 { total+=value; } return total;
}
recursive fn indexed()->i64 {
    var total=0; for value:u8,index in 254..256 { total+=value+100*index; } return total;
}
fn main() { print(narrowed()," ",indexed()); }
'''
        self.qualify(source,"509 609\n")
        for level in (0,2):
            path,stats=self.compile(level,text=source)
            for name in ("narrowed","indexed"):
                with self.subTest(level=level,function=name):
                    self.assertIn(0x03,strip.instructions(function_body(path,stats,name)))

    def test_range_past_the_u8_one_past_boundary_is_refused_before_execution(self):
        for binder in ("value:u8","value:u8,index"):
            source=self.work/"main.goose"
            source.write_text("fn main() { for "+binder+" in 254..258 { print(value); } }")
            for target in ("wasm-direct","native"):
                for level in (0,2):
                    for debug in (False,True):
                        output=self.work/f"refused-{target}-{level}-{debug}"
                        command=[str(strip.GOOSE),str(source),"--offline","--target",target,f"-O{level}","-o",str(output)]
                        if target=="native": command.append("--standalone")
                        if debug: command.append("--debug")
                        result=subprocess.run(command,capture_output=True,text=True,timeout=30)
                        with self.subTest(binder=binder,target=target,level=level,debug=debug):
                            self.assertNotEqual(result.returncode,0)
                            self.assertIn("258",result.stdout+result.stderr)
                            self.assertIn("u8",result.stdout+result.stderr)
                            self.assertFalse(output.exists())

    def test_nested_negative_ranges_and_indices_preserve_lexical_exits(self):
        source = '''recursive fn stencil(xs:u8[:])->i64 {
    var total=0;
    for dy in -1..2 {
        for dx,index in -1..2 {
            if dx==0 && dy==0 { continue; }
            if dy==1 && dx==1 { break; }
            let position=(dy+1)*3+dx+1;
            total+=xs[position]+index;
        }
    }
    return total;
}
recursive fn choose(seed:i64)->i64 {
    var total=seed;
    for value,index in -2..3 {
        let observed=value*10+index;
        if value == -1 { continue; }
        if value==1 { return total+observed; }
        total+=observed;
    }
    return total;
}
fn main() { let values:u8[9]=[1,2,3,4,5,6,7,8,9]; print(stencil(values[..])," ",choose(100)); }
'''
        self.qualify(source, "37 95\n")
        for level in (0, 2):
            path, stats = self.compile(level, text=source)
            for name in ("stencil", "choose"):
                with self.subTest(level=level, function=name):
                    self.assertNotIn(0x03, strip.instructions(function_body(path, stats, name)))

    def test_invalid_views_preserve_earlier_iteration_effects(self):
        source = '''var saved:u8[:]; var backing:u8[4]=[17,34,51,68];
var observed:i64[2]=[0,0];
export fn tick(seed:i64)->i64 {
    let xs=saved; let state=observed[..];
    for index in -1..2 {
        let value=xs[index+1]; state[0]+=value; state[1]++;
    }
    return state[0];
}
export fn total()->i64 { return observed[0]; }
export fn visited()->i64 { return observed[1]; }
fn main() { saved=backing[..]; }
'''
        cases = {"valid": (False,498,3), "group_trap": (True,335,2),
                 "tail_trap": (True,168,1), "short": (True,335,2), "empty": (True,0,0)}
        for level in (0, 2):
            for debug in (False, True):
                path, _ = self.compile(level, debug=debug, text=source)
                for scenario, (trapped, total, visited) in cases.items():
                    for engine, observed in strip.StripLoops.engines(self, path, scenario):
                        with self.subTest(level=level, debug=debug, scenario=scenario, engine=engine):
                            self.assertEqual(observed, {"trapped": trapped, "total": str(total),
                                                       "visited": str(visited), "tail": list(strip.TAIL)})


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
