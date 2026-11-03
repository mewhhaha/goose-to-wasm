#!/usr/bin/env python3
"""Qualify fixed-value copies across tail-only function-value forwarding."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import unittest

import test_prefix_resolution as prefix
import test_strip_loops as strip
from test_fill_loops import sections, uleb
from test_strip_loops import instructions

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = None

PAIR = '''
struct Pair { first:i64, second:i64 }
fn invoke<F>(a:Pair,b:Pair)->bool { F(a,b) }
fn forward1<F>(a:Pair,b:Pair)->bool { invoke(a,b) { x,y => F(x,y) } }
fn forward2<F>(a:Pair,b:Pair)->bool { forward1(a,b) { x,y => F(x,y) } }
var state=Pair { 1, 10 };
fn first()->Pair { return state; }
fn later()->Pair { state.first=99; return state; }
fn run()->i64 {
    var saw_first=0; var calls=0;
    for i in 3 {
        forward2(first(),later()) { a,b =>
            calls++;
            if a.first==1 && b.first==99 { saw_first=1; }
            if i==2 { return saw_first*10+calls; }
            false
        };
    }
    return saw_first*10+calls;
}
fn main() { print(run()); }
'''

NEGATIVES = {
    "extra-statement": PAIR.replace(
        "{ x,y => F(x,y) }", "{ x,y => let saved=x.first; F(x,y) && saved>=0 }"
    ),
    "capture-parent": PAIR.replace(
        "{ x,y => F(x,y) }", "{ x,y => if a.first>0 { F(x,y) } else { F(y,x) } }"
    ),
    "permuted": PAIR.replace("{ x,y => F(x,y) }", "{ x,y => F(y,x) }"),
    "duplicate": PAIR.replace("{ x,y => F(x,y) }", "{ x,y => F(x,x) }"),
    "mutable-parameters": PAIR.replace("{ x,y => F(x,y) }", "{ var x,var y => F(x,y) }").replace(
        "forward2(first(),later()) { a,b =>", "forward2(first(),later()) { var a,var b =>"
    ),
    "addressed": PAIR.replace("{ x,y => F(x,y) }", "{ x,y => F(&x,y) }").replace(
        "forward2(first(),later()) { a,b =>", "forward2(first(),later()) { a:Pair&,b =>"
    ),
    "type-adaptation": '''
fn invoke<F>(a:i32,b:i64)->bool { F(a,b) }
fn forward<F>(a:i32,b:i64)->bool { invoke(a,b) { x,y => F(x as i64,y) } }
fn run()->bool { forward(1,2) { x:i64,y:i64 => x<y } }
fn main() { print(run()); }
''',
}

REFERENCE_TYPES = {
    "reference": '''
fn invoke<F>(a:i64&,b:i64&)->bool { F(a,b) }
fn forward<F>(a:i64&,b:i64&)->bool { invoke(a,b) { x,y => F(x,y) } }
fn run()->bool { var a=1; var b=2; forward(a,b) { x,y => x<y } }
fn main() { print(run()); }
''',
    "slice": '''
fn invoke<F>(a:i64[:],b:i64[:])->bool { F(a,b) }
fn forward<F>(a:i64[:],b:i64[:])->bool { invoke(a,b) { x,y => F(x,y) } }
fn run()->bool { let a=[1]; let b=[2]; forward(a[..],b[..]) { x,y => x.len<y.len } }
fn main() { print(run()); }
''',
    "owned-var-enum": '''
enum Event { Empty, Data { value:i64 } }
fn invoke<F>(a:Event..,b:Event..)->bool { F(a,b) }
fn forward<F>(a:Event..,b:Event..)->bool { invoke(copy(a),copy(b)) { x,y => F(x,y) } }
fn below(a:Event..,b:Event..)->bool {
    match a { Data &left => match b { Data &right => left.value<right.value, Empty => false }, Empty => false }
}
fn run()->bool {
    let a:Event..=Event.Data { 1 }; let b:Event..=Event.Data { 2 };
    forward(copy(a),copy(b)) { x,y => below(copy(x),copy(y)) }
}
fn main() { print(run()); }
''',
}

CAPTURED_NAMED = '''
struct Pair { first:i64, second:i64 }
fn invoke<F>(a:Pair,b:Pair)->bool { F(a,b) }
fn forward<F>(a:Pair,b:Pair)->bool { invoke(a,b) { x,y => F(x,y) } }
fn run()->bool {
    let left=Pair { 1, 10 }; let right=Pair { 2, 20 };
    forward(left,right) { x,y =>
        fn nested()->bool { x.first<y.first }
        nested()
    }
}
fn main() { print(run()); }
'''


def function_bodies(path, stats):
    payload = dict(sections(path.read_bytes()))[10]
    count, offset = uleb(payload, 0)
    functions = sorted(stats["function_info"], key=lambda item: item["index"])
    if count != len(functions):
        raise AssertionError("statistics must cover every defined function")
    for function in functions:
        size, start = uleb(payload, offset)
        yield function["name"], payload[start:start + size]
        offset = start + size


def memory_copy_count(body):
    """Count memory.copy subopcodes while skipping Wasm instruction immediates."""
    groups, offset = uleb(body, 0)
    for _ in range(groups):
        _, offset = uleb(body, offset)
        offset += 1
    copies = 0
    while offset < len(body):
        op = body[offset]
        offset += 1
        if op in (0x02,0x03,0x04,0x0c,0x0d,0x10,0x20,0x21,0x22,0x23,0x24,0x3f,0x40,0x41,0x42):
            _, offset = uleb(body, offset)
        elif op == 0x0e:
            count, offset = uleb(body, offset)
            for _ in range(count + 1):
                _, offset = uleb(body, offset)
        elif op == 0x11 or 0x28 <= op <= 0x3e:
            _, offset = uleb(body, offset)
            _, offset = uleb(body, offset)
        elif op == 0x43:
            offset += 4
        elif op == 0x44:
            offset += 8
        elif op == 0xfc:
            sub, offset = uleb(body, offset)
            if sub == 10:
                copies += 1
                _, offset = uleb(body, offset)
                _, offset = uleb(body, offset)
            elif sub in (11,15,16,17):
                _, offset = uleb(body, offset)
            elif sub == 14:
                _, offset = uleb(body, offset)
                _, offset = uleb(body, offset)
        elif op not in (0x00,0x01,0x05,0x0b,0x0f,0x1a,0x1b) and not 0x45 <= op <= 0xc4:
            raise AssertionError(f"unexpected instruction {op:#x}")
    return copies


class FunctionValueForwarding(unittest.TestCase):
    setUp = strip.StripLoops.setUp
    compile = strip.StripLoops.compile

    def compile_file(self, source, level, debug):
        output = self.work / "program.wasm"
        stats = self.work / "stats.json"
        command = [str(strip.GOOSE), str(source), "--offline", "--target", "wasm-direct",
                   f"-O{level}", "--wasm-stats", str(stats), "-o", str(output)]
        if debug:
            command.append("--debug")
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return output, json.loads(stats.read_text())

    def compile_input(self, source, level, debug):
        if isinstance(source, Path):
            return self.compile_file(source, level, debug)
        return self.compile(level, debug=debug, text=source)

    def native(self, source, level, debug):
        path = source if isinstance(source, Path) else self.work / "main.goose"
        if not isinstance(source, Path):
            path.write_text(source)
        cfile = self.work / "oracle.c"
        binary = self.work / "oracle"
        command = [str(strip.GOOSE), str(path), "--offline", f"-O{level}", "--target", "native",
                   "--standalone", "-o", str(cfile)]
        if debug:
            command.append("--debug")
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = subprocess.run([prefix.CC, str(cfile), "-lm", "-o", str(binary)],
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def run_engines(self, wasm):
        for engine, command in (
            ("v8", [strip.NODE, str(ROOT / "scripts/run_wasm.mjs"), str(wasm)]),
            ("wasmtime", [sys.executable, str(ROOT / "scripts/run_wasmtime.py"), str(wasm)]),
        ):
            result = subprocess.run(command, capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            yield engine, result.stdout

    def test_nested_fixed_aggregate_forwarding_preserves_snapshots_and_exits(self):
        expected = "13\n"
        for level in (0,2):
            for debug in (False,True):
                path, stats = self.compile(level, debug=debug, text=PAIR)
                oracle = self.native(PAIR, level, debug)
                self.assertEqual(oracle, expected)
                for engine, output in self.run_engines(path):
                    with self.subTest(level=level, debug=debug, engine=engine):
                        self.assertEqual(output, oracle)

    def test_employee_limited_aggregate_forwarding_reduces_copy_instructions(self):
        source = ROOT / "examples" / "functions.goose"
        expected = (ROOT / "examples" / "expected" / "functions.out").read_text()
        for level in (0,2):
            for debug in (False,True):
                path, stats = self.compile_file(source, level, debug)
                oracle = self.native(source, level, debug)
                self.assertEqual(oracle, expected)
                for engine, output in self.run_engines(path):
                    with self.subTest(level=level, debug=debug, engine=engine):
                        self.assertEqual(output, oracle)
                if REFERENCE is not None and level == 2:
                    current_bodies = list(function_bodies(path, stats))
                    reference = self.reference_bodies(source, level, debug, None)
                    current_copies = sum(memory_copy_count(body) for _, body in current_bodies)
                    reference_copies = sum(memory_copy_count(body) for _, body in reference)
                    self.assertLess(current_copies, reference_copies)

    def reference_bodies(self, source, level, debug, names):
        if REFERENCE is None:
            return None
        compiler = strip.GOOSE
        try:
            strip.GOOSE = REFERENCE
            path, stats = self.compile_input(source, level, debug)
            return [(name, body) for name, body in function_bodies(path, stats)
                    if names is None or name.split("#")[0] in names]
        finally:
            strip.GOOSE = compiler

    def test_nonforwarding_shapes_keep_the_reference_run_body(self):
        cases = {**NEGATIVES, **REFERENCE_TYPES, "nested-named-capture": CAPTURED_NAMED}
        for label, source in cases.items():
            for level in (0,2):
                for debug in (False,True):
                    path, stats = self.compile_input(source, level, debug)
                    oracle = self.native(source, level, debug)
                    for engine, output in self.run_engines(path):
                        with self.subTest(case=label, level=level, debug=debug, engine=engine):
                            self.assertEqual(output, oracle)
                    if REFERENCE is None:
                        continue
                    names = {"run", "invoke", "forward1", "forward2", "forward"}
                    current = [(name, body) for name, body in function_bodies(path, stats)
                               if name.split("#")[0] in names]
                    previous = self.reference_bodies(source, level, debug, names)
                    with self.subTest(case=label, level=level, debug=debug):
                        self.assertEqual(current, previous)
                        for _, body in current:
                            list(instructions(body))


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
        REFERENCE = args.reference_goose.resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
