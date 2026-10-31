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


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--goose", type=Path, default=GOOSE)
    parser.add_argument("--node", default=NODE)
    args, remaining = parser.parse_known_args()
    GOOSE, NODE = args.goose.resolve(), args.node
    unittest.main(argv=[sys.argv[0], *remaining])
