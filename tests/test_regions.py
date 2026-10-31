#!/usr/bin/env python3
"""Check stable-region resource bounds, isolation and repeated-call cleanup."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

from test_static_data import sections, uleb

ROOT = Path(__file__).resolve().parents[1]
GOOSE = ROOT / "build/bin/goose"
NODE = "node"
CANARY = 987654321

NODE_HOST = r'''
const fs = require("node:fs");
const [file, input, repeats, canaryIndex] = process.argv.slice(1);
const module_ = new WebAssembly.Module(fs.readFileSync(file));
const metadata = JSON.parse(new TextDecoder().decode(WebAssembly.Module.customSections(module_, "goose.regions")[0]));
let instance;
const numbers=[];
const imports = {goose: {}, env: {bench_input: () => BigInt(input)}};
for (const item of WebAssembly.Module.imports(module_)) {
  if (item.module === "goose") imports.goose[item.name] = () => {};
}
imports.goose.abort = (p,n) => { throw new Error(new TextDecoder().decode(new Uint8Array(instance.exports.memory.buffer,p>>>0,n>>>0))); };
imports.goose.print_i64 = value => numbers.push(value.toString());
instance = new WebAssembly.Instance(module_,imports);
let error = "";
try {
  instance.exports._start();
  for(let i=0;i<Number(repeats);i++) {
    if(instance.exports.tick(BigInt(i)) !== BigInt(i+1)) throw new Error("wrong repeated result");
  }
} catch(e) { error = String(e.message); }
let canary = null;
if(Number(canaryIndex)>=0) {
  const p=metadata.activation_limit+Number(canaryIndex)*metadata.region_bytes;
  canary=new DataView(instance.exports.memory.buffer).getBigInt64(p,true).toString();
}
process.stdout.write(JSON.stringify({error,canary,numbers,pages:instance.exports.memory.buffer.byteLength/65536}));
'''


def metadata(data):
    for kind, body in sections(data):
        if kind == 0:
            length, offset = uleb(body, 0)
            if body[offset:offset + length] == b"goose.regions":
                return json.loads(body[offset + length:])
    raise AssertionError("missing runtime resource metadata")


def wasmtime_run(path, runtime, input_value, repeats, canary_index):
    import wasmtime
    engine = wasmtime.Engine()
    module = wasmtime.Module.from_file(engine, str(path))
    store = wasmtime.Store(engine)
    linker = wasmtime.Linker(engine)
    numbers = []

    def abort(caller, pointer, length, line):
        memory = caller.get("memory")
        message = bytes(memory.read(caller, pointer, pointer + length)).decode()
        raise wasmtime.Trap(message)

    for item in module.imports:
        if (item.module, item.name) == ("goose", "abort"):
            linker.define_func(item.module, item.name, item.type, abort, access_caller=True)
        elif (item.module, item.name) == ("env", "bench_input"):
            linker.define_func(item.module, item.name, item.type, lambda: input_value)
        elif (item.module, item.name) == ("goose", "print_i64"):
            linker.define_func(item.module, item.name, item.type, lambda value: numbers.append(str(value)))
        elif item.module == "goose":
            linker.define_func(item.module, item.name, item.type, lambda *args: None)
        else:
            raise AssertionError(f"unexpected import {item.module}.{item.name}")
    instance = linker.instantiate(store, module)
    exports = instance.exports(store)
    error = ""
    try:
        exports["_start"](store)
        for value in range(repeats):
            assert exports["tick"](store, value) == value + 1
    except wasmtime.Trap as failure:
        error = str(failure)
    memory = exports["memory"]
    canary = None
    if canary_index >= 0:
        start = runtime["activation_limit"] + canary_index * runtime["region_bytes"]
        canary = str(struct.unpack("<q", memory.read(store, start, start + 8))[0])
    return {"error": error, "canary": canary, "numbers": numbers, "pages": memory.size(store)}


class StableRegions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT / "build")
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)

    def compile(self, source, level):
        path = self.work / f"O{level}.goose"
        path.write_text(source)
        output = path.with_suffix(".wasm")
        command = [str(GOOSE), str(path), "--target", "wasm-direct", "--offline", f"-O{level}",
                   "--wasm-initial-pages", "1", "--wasm-max-pages", "3", "-o", str(output)]
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        runtime = metadata(output.read_bytes())
        self.assertGreater(runtime["region_bytes"], 0)
        self.assertLessEqual(runtime["activation_limit"] + runtime["region_count"] * runtime["region_bytes"], 3 * 65536)
        return output, runtime

    def engines(self, path, runtime, input_value=0, repeats=0, canary_index=-1):
        result = subprocess.run([NODE, "-e", NODE_HOST, str(path), str(input_value), str(repeats), str(canary_index)],
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        yield "v8", json.loads(result.stdout)
        yield "wasmtime", wasmtime_run(path, runtime, input_value, repeats, canary_index)

    def test_growth_cannot_overwrite_next_region(self):
        for operation in ("resize", "push", "append"):
            extra = {"resize": "", "push": "values.push(0);", "append": "values.append([0]);"}[operation]
            source = f'''extern fn bench_input() -> i64;
var values: i64[>..] = [];
var neighbor: i64[>..] = [{CANARY}];
fn main() {{ values.resize(bench_input(), 0); {extra} }}'''
            for level in (0, 2):
                path, runtime = self.compile(source, level)
                # Cross the region boundary while remaining inside already-
                # grown memory. A missing region check corrupts neighbor.
                count = runtime["region_bytes"] // 8 + (operation == "resize")
                for engine, observed in self.engines(path, runtime, count, canary_index=1):
                    with self.subTest(operation=operation, level=level, engine=engine):
                        self.assertIn("data region exhausted", observed["error"])
                        self.assertEqual(observed["canary"], str(CANARY))

    def test_scratch_cannot_overwrite_data_region(self):
        source = f'''extern fn bench_input() -> i64;
var first: i64[>..] = [];
var second: i64[>..] = [];
fn main() {{
    let count = bench_input(); first.resize(count, 0); first[0] = {CANARY};
    second.resize(count, 11); print(first, second);
}}'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            for engine, observed in self.engines(path, runtime, runtime["region_bytes"] // 8, canary_index=0):
                with self.subTest(level=level, engine=engine):
                    self.assertIn("activation/scratch arena exhausted", observed["error"])
                    self.assertEqual(observed["canary"], str(CANARY))

    def test_constructor_effects_precede_exhaustion(self):
        programs = {
            "fill": f'''var neighbor: i64[>..] = [{CANARY}];
fn value() -> i64 {{ print(123); return 1; }}
fn main() {{ var values: i64[>..] = [value(); 1000000]; }}''',
            "elements": f'''var data: i64[4096];
var neighbor: i64[>..] = [{CANARY}];
fn value(n: i64) -> const i64[4096]& {{ print(n); return data; }}
fn main() {{ var values: i64[4096][>..] = [value(1), value(2)]; }}''',
        }
        for name, source in programs.items():
            for level in (0, 2):
                path, runtime = self.compile(source, level)
                for engine, observed in self.engines(path, runtime, canary_index=0):
                    with self.subTest(program=name, level=level, engine=engine):
                        self.assertIn("data region exhausted", observed["error"])
                        self.assertEqual(observed["canary"], str(CANARY))
                        self.assertEqual(observed["numbers"], ["123"] if name == "fill" else ["1", "2"])

    def test_activation_cannot_overwrite_data_region(self):
        source = f'''extern fn bench_input() -> i64;
var neighbor: i64[>..] = [{CANARY}];
recursive fn dive(n: i64) -> i64 {{
    if n <= 0 {{ return 0; }}
    let values: i64[1024] = [n; 1024];
    let previous = dive(n - 1);
    return previous + values[n % 1024];
}}
fn main() {{ dive(bench_input()); }}'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            for engine, observed in self.engines(path, runtime, 200, canary_index=0):
                with self.subTest(level=level, engine=engine):
                    self.assertIn("activation/scratch arena exhausted", observed["error"])
                    self.assertEqual(observed["canary"], str(CANARY))

    def test_repeated_calls_release_owner_regions(self):
        source = '''export fn tick(n: i64) -> i64 {
    var values: i64[>..] = [if n % 2 == 0 { return n + 1; } else { n }];
    values.push(n + 1); return values[1];
}
fn main() {}'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            self.assertEqual(runtime["region_count"], 1)
            for engine, observed in self.engines(path, runtime, repeats=10000):
                with self.subTest(level=level, engine=engine):
                    self.assertEqual(observed["error"], "")
                    self.assertLessEqual(observed["pages"], 3)

    def test_global_regions_and_live_call_owners_are_separate(self):
        source = f'''var first: i64[>..] = [{CANARY}];
var second: i64[>..] = [22];
fn helper() -> i64 {{ var local: i64[>..] = [3]; return local[0]; }}
fn main() {{ var caller: i64[>..] = [4]; print(helper() + caller[0]); }}'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            self.assertEqual((runtime["global_regions"], runtime["region_count"]), (2, 4))
            for engine, observed in self.engines(path, runtime, canary_index=0):
                with self.subTest(level=level, engine=engine):
                    self.assertEqual(observed["error"], "")
                    self.assertEqual(observed["canary"], str(CANARY))

    def test_owned_results_forward_one_destination_through_recursion(self):
        source = f'''var neighbor: i64[>..] = [{CANARY}];
recursive fn forward(n: i64) -> i64[>..] {{
    if n <= 0 {{ var local: i64[>..] = [7]; return local; }}
    return forward(n - 1);
}}
fn main() {{ let values = forward(100); print(values[0]); }}'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            # One global, one caller result, one base-case local. Recursive
            # forwarding must not acquire another result region per call.
            self.assertEqual((runtime["global_regions"], runtime["region_count"]), (1, 3))
            for engine, observed in self.engines(path, runtime, canary_index=0):
                with self.subTest(level=level, engine=engine):
                    self.assertEqual(observed["error"], "")
                    self.assertEqual(observed["numbers"], ["7"])
                    self.assertEqual(observed["canary"], str(CANARY))

    def test_owned_results_release_between_export_calls(self):
        source = '''fn make(n: i64) -> i64[>..] { return [n, n + 1]; }
export fn tick(n: i64) -> i64 { let values = make(n); return values[1]; }
fn main() {}'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            self.assertEqual(runtime["region_count"], 1)
            for engine, observed in self.engines(path, runtime, repeats=10000):
                with self.subTest(level=level, engine=engine):
                    self.assertEqual(observed["error"], "")
                    self.assertLessEqual(observed["pages"], 3)

    def test_owned_arguments_release_on_call_and_interrupted_construction(self):
        source = f'''var neighbor: i64[>..] = [{CANARY}];
fn transform(values: i64[>..]) -> i64[>..] {{ values.push(9); return values; }}
fn consume(values: i64[>..]) -> i64 {{ return values[0] + 1; }}
export fn tick(n: i64) -> i64 {{
    let result = transform([if n % 2 == 0 {{ return n + 1; }} else {{ n }}]);
    return consume(copy(result));
}}
fn main() {{ print(consume([1]) + consume([2]) + consume([3])); }}'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            self.assertEqual((runtime["global_regions"], runtime["region_count"]), (1, 3))
            for engine, observed in self.engines(path, runtime, repeats=10000, canary_index=0):
                with self.subTest(level=level, engine=engine):
                    self.assertEqual(observed["error"], "")
                    self.assertEqual(observed["numbers"], ["9"])
                    self.assertEqual(observed["canary"], str(CANARY))
                    self.assertLessEqual(observed["pages"], 3)

    def test_owned_argument_growth_cannot_overwrite_later_argument(self):
        source = f'''extern fn bench_input() -> i64;
fn grow(values: i64[>..], neighbor: i64[>..]) -> i64 {{
    values.resize(bench_input(), 7); return neighbor[0];
}}
fn main() {{ print(grow([1], [{CANARY}])); }}'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            self.assertEqual(runtime["region_count"], 2)
            count = runtime["region_bytes"] // 8 + 1
            for engine, observed in self.engines(path, runtime, input_value=count, canary_index=1):
                with self.subTest(level=level, engine=engine):
                    self.assertIn("data region exhausted", observed["error"])
                    self.assertEqual(observed["canary"], str(CANARY))

    def test_later_argument_exits_release_already_constructed_arguments(self):
        bodies = (
            'return consume([n], [if n % 2 == 0 { return n + 1; } else { 0 }]);',
            '''var answer = 0;
    for i in 3 {
        answer += consume([n], [if i == 0 { continue; } else { if i == 2 { break; } else { 0 } }]);
    }
    return answer;''',
        )
        for body in bodies:
            source = '''fn consume(a: i64[>..], b: i64[>..]) -> i64 { return a[0] + b[0] + 1; }
export fn tick(n: i64) -> i64 { ''' + body + ' }\nfn main() {}'
            for level in (0, 2):
                path, runtime = self.compile(source, level)
                self.assertEqual(runtime["region_count"], 2)
                for engine, observed in self.engines(path, runtime, repeats=10000):
                    with self.subTest(body=body, level=level, engine=engine):
                        self.assertEqual(observed["error"], "")

    def test_nested_owned_calls_count_peak_regions(self):
        source = '''fn transform(values: i64[>..]) -> i64[>..] { values.push(9); return values; }
export fn tick(n: i64) -> i64 {
    let result = transform(transform([n])); return result[0] + 1;
}
fn main() {}'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            # At O2 the inline parameter bindings are named results and
            # construct directly in the receiving region.
            self.assertEqual(runtime["region_count"], 3 if level == 0 else 1)
            for engine, observed in self.engines(path, runtime, repeats=10000):
                with self.subTest(level=level, engine=engine):
                    self.assertEqual(observed["error"], "")

    def test_named_results_share_data_but_publish_separate_lengths(self):
        source = f'''var neighbor: i64[>..] = [{CANARY}];
fn grow(values: i64[>..]&) -> i64 {{ values[0] += 10; values.push(99); return values.len; }}
fn make(n: i64) -> i64[>..], i64, i64[>..] {{
    var values: i64[>..] = [n]; return values, grow(values), values;
}}
export fn tick(n: i64) -> i64 {{
    let first, length, second = make(n);
    if first.len != 1 || second.len != 2 || length != 2 || first[0] != n + 10 || second[1] != 99 {{ abort("bad result"); }}
    return first[0] - 9;
}}
fn main() {{}}'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            self.assertEqual((runtime["global_regions"], runtime["region_count"]), (1, 3))
            for engine, observed in self.engines(path, runtime, repeats=10000, canary_index=0):
                with self.subTest(level=level, engine=engine):
                    self.assertEqual(observed["error"], "")
                    self.assertEqual(observed["canary"], str(CANARY))

    def test_recursive_multiple_results_forward_two_regions(self):
        source = '''recursive fn forward(n: i64) -> i64[>..], i64, i64[>..] {
    if n <= 0 { return [7], 8, [9]; } return forward(n - 1);
}
fn main() { let a, b, c = forward(100); print(a[0] + b + c[0]); }'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            self.assertEqual(runtime["region_count"], 2)
            for engine, observed in self.engines(path, runtime):
                with self.subTest(level=level, engine=engine):
                    self.assertEqual(observed["error"], "")
                    self.assertEqual(observed["numbers"], ["24"])

    def test_two_named_locals_bind_independent_result_regions(self):
        source = '''fn make(n: i64) -> i64[>..], i64[>..] {
    var a: i64[>..] = [n]; var b: i64[>..] = [n + 1]; return a, b;
}
export fn tick(n: i64) -> i64 {
    let a, b = make(n); a[0] += 100;
    if b[0] != n + 1 { abort("aliased result regions"); } return b[0];
}
fn main() {}'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            self.assertEqual(runtime["region_count"], 2)
            for engine, observed in self.engines(path, runtime, repeats=10000):
                with self.subTest(level=level, engine=engine):
                    self.assertEqual(observed["error"], "")

    def test_nested_owned_control_values_release_iteration_regions(self):
        source = '''export fn tick(n: i64) -> i64 {
    var step = 0;
    let result: i64[>..] = loop {
        var local: i64[>..] = [n];
        if step == 0 { step++; continue; }
        break match n % 2 {
            0 => block { var nested: i64[>..] = [n + 1]; break copy(nested); },
            _ => { local.push(n + 1); copy(local) }
        };
    };
    return result[result.len - 1];
}
fn main() {}'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            self.assertEqual(runtime["region_count"], 3)
            for engine, observed in self.engines(path, runtime, repeats=10000):
                with self.subTest(level=level, engine=engine):
                    self.assertEqual(observed["error"], "")

    def test_interrupted_global_assignment_cannot_publish_unsafe_extent(self):
        for count in (1000000, 4294967296):
            source = f'''extern fn bench_input() -> i64;
var values: i64[>..] = [1]; var neighbor: i64[>..] = [{CANARY}];
fn reset() -> i64 {{ values = [if bench_input() >= 0 {{ return 7; }} else {{ 1 }}; {count}]; return 0; }}
fn main() {{ reset(); values[bench_input()] = 123; }}'''
            for level in (0, 2):
                path, runtime = self.compile(source, level)
                self.assertEqual((runtime["global_regions"], runtime["region_count"]), (2, 2))
                index = runtime["region_bytes"] // 8
                for engine, observed in self.engines(path, runtime, input_value=index, canary_index=1):
                    with self.subTest(count=count, level=level, engine=engine):
                        self.assertIn("data region exhausted", observed["error"])
                        self.assertEqual(observed["canary"], str(CANARY))

    def test_abandoned_dying_headers_do_not_reserve_their_extent(self):
        source = '''fn local(n: i64) -> i64 {
    var values: i64[>..] = [1]; let alias: i64[>..]& = values;
    alias = [if n >= 0 { return 7; } else { 1 }; 4294967296]; return 0;
}
fn parameter(values: i64[>..], n: i64) -> i64 {
    let alias: i64[>..]& = values;
    alias = [if n >= 0 { return 7; } else { 1 }; 4294967296]; return 0;
}
fn named(n: i64) -> i64[>..] {
    var values: i64[>..] = [1];
    values = [if n >= 0 { return [7]; } else { 1 }; 4294967296]; return values;
}
export fn tick(n: i64) -> i64 {
    let a = local(n); let b = parameter([1], n);
    for i in 2 {
        var dying: i64[>..] = [1];
        dying = [if n >= 0 { continue; } else { 1 }; 4294967296];
    }
    let result = named(n);
    if a != 7 || b != 7 { abort("wrong interrupted result"); } return n + result[0] - 6;
}
fn main() {}'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            self.assertEqual(runtime["region_count"], 1)
            for engine, observed in self.engines(path, runtime, repeats=10000):
                with self.subTest(level=level, engine=engine):
                    self.assertEqual(observed["error"], "")

    def test_outer_headers_surviving_loop_exits_check_their_extent(self):
        bodies = (
            'loop { values = [if bench_input() >= 0 { break; } else { 1 }; 1000000]; }',
            'for i in 1 { values = [if bench_input() >= 0 { continue; } else { 1 }; 1000000]; }',
        )
        for body in bodies:
            source = f'''extern fn bench_input() -> i64;
fn main() {{
    var values: i64[>..] = [1]; var neighbor: i64[>..] = [{CANARY}];
    {body}
    values[bench_input()] = 123;
}}'''
            for level in (0, 2):
                path, runtime = self.compile(source, level)
                self.assertEqual(runtime["region_count"], 2)
                index = runtime["region_bytes"] // 8
                for engine, observed in self.engines(path, runtime, input_value=index, canary_index=1):
                    with self.subTest(body=body, level=level, engine=engine):
                        self.assertIn("data region exhausted", observed["error"])
                        self.assertEqual(observed["canary"], str(CANARY))

    def test_fixed_and_slice_results_adapt_in_two_receiving_regions(self):
        source = '''var numbers: i64[2] = [10, 11];
fn sources(n: i64) -> i64[2], i64[:], i64 { return [n, n + 1], numbers[..], n + 2; }
fn roots(n: i64) -> i64[>..], i64[>..], i64 { return sources(n); }
export fn tick(n: i64) -> i64 {
    let a, b, c = roots(n);
    if a[1] != n + 1 || b[0] != 10 || c != n + 2 { abort("wrong adapted result"); } return a[1];
}
fn main() {}'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            self.assertEqual(runtime["region_count"], 2)
            for engine, observed in self.engines(path, runtime, repeats=10000):
                with self.subTest(level=level, engine=engine):
                    self.assertEqual(observed["error"], "")

    def test_borrowed_arguments_survive_nested_inline_calls_and_later_allocations(self):
        source = '''extern fn bench_input() -> i64;
recursive fn make(n: i64) -> i64[>..] { return [n, n + 1]; }
fn keep(owned: i64[>..], view: const i64[:]) -> const i64[:] { owned.push(99); return view; }
inline fn relay(owned: i64[>..], view: const i64[:]) -> const i64[:] {
    let body_temporary = make(200).len; if body_temporary != 2 { abort("bad body temp"); } return view;
}
fn churn(a: i64[>..], b: i64[>..], c: i64[>..]) -> i64 {
    return a[bench_input() % 2] + b[bench_input() % 2] + c[bench_input() % 2];
}
fn observe(view: const i64[:], marker: i64) -> i64 { return view[0] + view[1] + marker; }
export fn tick(n: i64) -> i64 {
    let got = observe(relay([90], keep([80], make(n))), churn([900, 901], [910, 911], [920, 921]));
    return got - n - 2730;
}
fn main() {}'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            self.assertEqual(runtime["region_count"], 6)
            for engine, observed in self.engines(path, runtime, repeats=10000):
                with self.subTest(level=level, engine=engine):
                    self.assertEqual(observed["error"], "")

    def test_owned_control_temporary_survives_body_cleanup(self):
        expressions = (
            'block { var local: i64[>..] = [n, n + 1]; break copy(local); }',
            'if n % 2 == 0 { make(n) } else { make(n) }',
            'loop { break make(n); }',
            'match n % 2 { 0 => make(n), _ => make(n) }',
        )
        for expression in expressions:
            source = '''extern fn bench_input() -> i64;
recursive fn make(n: i64) -> i64[>..] { return [n, n + 1]; }
fn churn(a: i64[>..], b: i64[>..], c: i64[>..]) -> i64 {
    return a[bench_input() % 2] + b[bench_input() % 2] + c[bench_input() % 2];
}
fn observe(view: const i64[:], marker: i64) -> i64 { return view[0] + view[1] + marker; }
export fn tick(n: i64) -> i64 {
    let got = observe((''' + expression + ''')[..], churn([900, 901], [910, 911], [920, 921]));
    return got - n - 2730;
}
fn main() {}'''
            for level in (0, 2):
                path, runtime = self.compile(source, level)
                self.assertEqual(runtime["region_count"], 4)
                for engine, observed in self.engines(path, runtime, repeats=10000):
                    with self.subTest(expression=expression, level=level, engine=engine):
                        self.assertEqual(observed["error"], "")

    def test_condition_sequence_and_default_temporaries_release_between_evaluations(self):
        source = '''extern fn bench_input() -> i64;
recursive fn make(n: i64) -> i64[>..] { return [n, n + 1]; }
struct Defaulted { value: i64 = make(1).len }
fn churn(a: i64[>..], b: i64[>..], c: i64[>..]) -> i64 {
    return a[bench_input() % 2] + b[bench_input() % 2] + c[bench_input() % 2];
}
export fn tick(n: i64) -> i64 {
    var remaining = 20;
    while make(remaining).len == 2 && remaining > 0 { remaining--; }
    var total = 0;
    for value in make(n) { make(200); churn([900, 901], [910, 911], [920, 921]); total += value; }
    let defaults = default<Defaulted[300]>();
    return total + defaults[299].value - n - 2;
}
fn main() {}'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            self.assertEqual(runtime["region_count"], 4)
            for engine, observed in self.engines(path, runtime, repeats=10000):
                with self.subTest(level=level, engine=engine):
                    self.assertEqual(observed["error"], "")

    def test_completed_temporary_statement_releases_region_before_recursion(self):
        source = '''recursive fn make(n: i64) -> i64[>..] { return [n, n + 1]; }
recursive fn total(n: i64) -> i64 {
    if n <= 0 { return 0; } let value = make(n).len; return total(n - 1) + value;
}
export fn tick(n: i64) -> i64 { if total(50) != 100 { abort("bad recursion"); } return n + 1; }
fn main() {}'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            self.assertEqual(runtime["region_count"], 1)
            for engine, observed in self.engines(path, runtime, repeats=10000):
                with self.subTest(level=level, engine=engine):
                    self.assertEqual(observed["error"], "")

    def test_later_argument_exit_releases_earlier_anonymous_value(self):
        source = '''extern fn bench_input() -> i64;
recursive fn make(n: i64) -> i64[>..] { return [n, n + 1]; }
fn churn(a: i64[>..], b: i64[>..], c: i64[>..]) -> i64 {
    return a[bench_input() % 2] + b[bench_input() % 2] + c[bench_input() % 2];
}
fn observe(view: const i64[:], marker: i64) -> i64 { return view[0] + view[1] + marker; }
export fn tick(n: i64) -> i64 {
    let got = observe(make(n)[..], churn([if n % 2 == 0 { return n + 1; } else { 900 }, 901], [910, 911], [920, 921]));
    return got - n - 2730;
}
fn main() {}'''
        for level in (0, 2):
            path, runtime = self.compile(source, level)
            self.assertEqual(runtime["region_count"], 4)
            for engine, observed in self.engines(path, runtime, repeats=10000):
                with self.subTest(level=level, engine=engine):
                    self.assertEqual(observed["error"], "")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--goose", type=Path, default=GOOSE)
    parser.add_argument("--node", default=NODE)
    args, remaining = parser.parse_known_args()
    GOOSE, NODE = args.goose.resolve(), args.node
    unittest.main(argv=[sys.argv[0], *remaining])
