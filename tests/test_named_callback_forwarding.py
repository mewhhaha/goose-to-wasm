#!/usr/bin/env python3
"""Qualify snapshot-preserving function-value tails that call named functions."""
import argparse
from pathlib import Path
import subprocess
import sys
import unittest

import test_function_value_forwarding as fv
import test_prefix_resolution as prefix
import test_strip_loops as strip

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = None
BASE = '''
struct Pair { first:i64, second:i64 }
fn invoke<F>(a:Pair,b:Pair) { F(a,b) }
var state=Pair { 1, 10 }; var observed:i64=0;
fn first()->Pair { state }
fn later()->Pair { state.first=99; return state; }
recursive fn terminal(a:Pair,b:Pair)->i64 { a.first*100+b.first }
recursive fn run() { print(invoke(first(),later()) { x,y => terminal(x,y) }," ",state.first); }
fn main() { run(); }
'''

NEGATIVE = {
    "extra-effects": BASE.replace("x,y => terminal(x,y)", "x,y => observed+=1; terminal(x,y)"),
    "mutable-callback": BASE.replace("{ x,y =>", "{ var x,var y =>"),
    "mutable-callee": BASE.replace("terminal(a:Pair,b:Pair)", "terminal(var a:Pair,var b:Pair)"),
    "capturing-callee": BASE.replace(
        "recursive fn run() {", "recursive fn run() { let offset=7; fn captured(a:Pair,b:Pair)->i64 { a.first*100+b.first+offset }"
    ).replace("x,y => terminal(x,y)", "x,y => captured(x,y)"),
    "materializing-original": BASE.replace(
        "recursive fn run() {", "recursive fn make()->i64[>..] { [1,2] } recursive fn run() {"
    ).replace("{ F(a,b) }", "{ F(Pair { make().len,a.second },b) }"),
    "reference": '''
struct Pair { first:i64, second:i64 }
fn invoke<F>(a:Pair&,b:Pair&) { F(a,b) }
recursive fn terminal(a:Pair&,b:Pair&)->i64 { a.first*100+b.first }
recursive fn run() { var a=Pair { 1,10 }; var b=Pair { 2,20 }; print(invoke(a,b) { x,y => terminal(x,y) }); }
fn main() { run(); }
''',
    "slice": '''
fn invoke<F>(a:i64[:],b:i64[:]) { F(a,b) }
recursive fn terminal(a:i64[:],b:i64[:])->i64 { a[0]*100+b[0] }
recursive fn run() { let a=[1,10]; let b=[2,20]; print(invoke(a[..],b[..]) { x,y => terminal(x,y) }); }
fn main() { run(); }
''',
}


class NamedCallbackForwarding(unittest.TestCase):
    setUp = fv.FunctionValueForwarding.setUp
    compile = fv.FunctionValueForwarding.compile
    compile_file = fv.FunctionValueForwarding.compile_file
    compile_input = fv.FunctionValueForwarding.compile_input
    native = fv.FunctionValueForwarding.native
    run_engines = fv.FunctionValueForwarding.run_engines
    reference_bodies = fv.FunctionValueForwarding.reference_bodies

    def qualify(self, source, expected=None, unchanged=False):
        for level in (0,2):
            for debug in (False,True):
                with self.subTest(level=level, debug=debug):
                    path, stats = self.compile_input(source, level, debug)
                    current = [(name, body) for name, body in fv.function_bodies(path, stats)
                               if name.split("#")[0] in {"run", "invoke", "terminal", "captured"}]
                    oracle = self.native(source, level, debug)
                    if expected is not None:
                        self.assertEqual(oracle, expected)
                    for engine, output in self.run_engines(path):
                        with self.subTest(engine=engine):
                            self.assertEqual(output, oracle)
                    if REFERENCE is not None and unchanged:
                        reference = self.reference_bodies(source, level, debug, {"run", "invoke", "terminal", "captured"})
                        self.assertTrue(current)
                        self.assertEqual(current, reference)

    def test_named_scalar_void_and_float_keep_original_snapshot_order(self):
        self.qualify(BASE, "199 99\n")
        floating = BASE.replace("->i64 { a.first*100+b.first }", "->f64 { (a.first*100+b.first) as f64+0.25 }")
        self.qualify(floating, "199.25 99\n")
        void = BASE.replace("->i64 { a.first*100+b.first }", "{ observed=a.first*100+b.first; }").replace(
            'print(invoke(first(),later()) { x,y => terminal(x,y) }," ",state.first);',
            'invoke(first(),later()) { x,y => terminal(x,y) }; print(observed," ",state.first);'
        )
        self.qualify(void, "199 99\n")

    def test_excluded_shapes_preserve_semantics_and_optional_reference_bytes(self):
        for label, source in NEGATIVE.items():
            with self.subTest(case=label):
                self.qualify(source, unchanged=True)

    def test_functions_example_keeps_output_and_removes_named_tail_copies(self):
        source = ROOT/"examples/functions.goose"
        expected = (ROOT/"examples/expected/functions.out").read_text()
        path, stats = self.compile_input(source, 2, False)
        current = sum(fv.memory_copy_count(body) for _, body in fv.function_bodies(path, stats))
        self.assertLess(current,317)
        for engine, output in self.run_engines(path):
            with self.subTest(engine=engine):
                self.assertEqual(output, expected)
        if REFERENCE is not None:
            previous = self.reference_bodies(source, 2, False, None)
            self.assertLess(current, sum(fv.memory_copy_count(body) for _, body in previous))

    def test_multi_result_callback_boundary_is_not_bypassed(self):
        # The pinned backend cannot receive a multi-result FV tail. Forwarding
        # must not silently turn that existing boundary into a different call.
        source = BASE.replace("->i64 { a.first*100+b.first }", "->i64,i64 { return a.first,b.first; }")
        path = self.work/"multi.goose"
        path.write_text(source)
        compilers = [strip.GOOSE]
        if REFERENCE is not None:
            compilers.append(REFERENCE)
        for level in (0,2):
            for debug in (False,True):
                for compiler in compilers:
                    with self.subTest(level=level, debug=debug, compiler=compiler):
                        output = self.work/"multi.wasm"
                        output.unlink(missing_ok=True)
                        command = [str(compiler),str(path),"--offline","--target","wasm-direct",f"-O{level}","-o",str(output)]
                        if debug:
                            command.append("--debug")
                        result = subprocess.run(command,capture_output=True,text=True,timeout=60)
                        self.assertNotEqual(result.returncode,0)
                        self.assertFalse(output.exists())
                        self.assertIn("expected one runtime value",result.stdout+result.stderr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=strip.GOOSE)
    parser.add_argument("--node", default=strip.NODE)
    parser.add_argument("--cc", default=prefix.CC)
    parser.add_argument("--reference-goose", type=Path)
    args, remaining = parser.parse_known_args()
    strip.GOOSE = prefix.GOOSE = args.goose.resolve()
    strip.NODE = args.node
    prefix.CC = args.cc
    if args.reference_goose:
        REFERENCE = fv.REFERENCE = args.reference_goose.resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
