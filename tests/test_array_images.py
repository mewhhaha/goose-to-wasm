#!/usr/bin/env python3
"""Inspect array value images and verify that views read their stored metadata."""
import argparse
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

from test_regions import metadata

ROOT = Path(__file__).resolve().parents[1]
GOOSE = ROOT / "build/bin/goose"

NODE_HOST = r'''
const fs = require("node:fs");
const [path, prefix, initial, replacement] = process.argv.slice(1);
const module = new WebAssembly.Module(fs.readFileSync(path));
const info = JSON.parse(new TextDecoder().decode(WebAssembly.Module.customSections(module,"goose.regions")[0]));
const imports = {goose:{}};
for(const item of WebAssembly.Module.imports(module)) imports.goose[item.name] = () => {};
const instance = new WebAssembly.Instance(module,imports);
instance.exports._start();
const memory = instance.exports.memory;
const base = info.activation_limit;
const bytes = new Uint8Array(memory.buffer,base,Number(initial));
const result = {image:Array.from(bytes),before:instance.exports.count().toString()};
new Uint8Array(memory.buffer,base,Number(prefix)).fill(0);
new Uint8Array(memory.buffer)[base] = Number(replacement);
result.after = instance.exports.count().toString();
process.stdout.write(JSON.stringify(result));
'''


class ArrayImages(unittest.TestCase):
    def compile(self, directory, source, level):
        path = directory / "main.goose"
        path.write_text(source)
        output = directory / "program.wasm"
        subprocess.run([str(GOOSE), str(path), "--offline", f"-O{level}", "--target", "wasm-direct", "-o", str(output)], check=True, capture_output=True, text=True)
        return output

    def check_engines(self, path, prefix, expected, before, after, replacement=1):
        result = subprocess.run(["node", "-e", NODE_HOST, str(path), str(prefix), str(len(expected)), str(replacement)], check=True, capture_output=True, text=True)
        observed = json.loads(result.stdout)
        self.assertEqual(observed, {"image":list(expected), "before":str(before), "after":str(after)})
        import wasmtime
        engine = wasmtime.Engine()
        module = wasmtime.Module.from_file(engine, str(path))
        store = wasmtime.Store(engine)
        linker = wasmtime.Linker(engine)
        for item in module.imports:
            self.assertEqual(item.module, "goose")
            linker.define_func(item.module, item.name, item.type, lambda *args: None)
        instance = linker.instantiate(store, module)
        exports = instance.exports(store)
        exports["_start"](store)
        memory = exports["memory"]
        base = metadata(path.read_bytes())["activation_limit"]
        self.assertEqual(bytes(memory.read(store, base, base + len(expected))), expected)
        self.assertEqual(exports["count"](store), before)
        memory.write(store, bytes([replacement]) + bytes(prefix - 1), base)
        self.assertEqual(exports["count"](store), after)

    def test_unsigned_length_images_and_authoritative_views(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as name:
            for storage, width in [("",4), ("u8",1), ("u16",2), ("u32",4), ("u64",8)]:
                source = f'''var values: u16[{storage}] = [0x1122,0x3344,0x5566];
export fn count() -> i64 {{ values.len }} fn main() {{}}'''
                expected = (3).to_bytes(width,"little") + struct.pack("<HHH",0x1122,0x3344,0x5566)
                for level in (0,2):
                    with self.subTest(storage=storage,level=level):
                        self.check_engines(self.compile(Path(name),source,level),width,expected,3,1)

    def test_runtime_capacity_and_length_share_the_value_image(self):
        source = '''var values: u16[..] = [..5];
export fn count() -> i64 { values.cap * 100 + values.len }
fn main() { values.push(0x1122); values.push(0x3344); }'''
        expected = struct.pack("<IIHH",5,2,0x1122,0x3344)
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as name:
            for level in (0,2):
                with self.subTest(level=level):
                    # Replacing only the capacity preserves the stored count.
                    self.check_engines(self.compile(Path(name),source,level),4,expected,502,302,replacement=3)

    def test_packed_record_elements_keep_their_byte_stride(self):
        source = '''struct Cell { tag:u8, value:u16 }
var values: Cell[u8] = [Cell {1,0x1122},Cell {2,0x3344}];
export fn count() -> i64 { values.len } fn main() {}'''
        expected = bytes.fromhex("02012211024433")
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as name:
            for level in (0,2):
                self.check_engines(self.compile(Path(name),source,level),1,expected,2,1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--goose",type=Path,default=GOOSE)
    args,remaining = parser.parse_known_args()
    GOOSE = args.goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
