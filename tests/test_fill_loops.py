#!/usr/bin/env python3
"""Check byte fill lowering and preserve scalar-loop trap/partial-write behavior."""
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
TAIL = bytes(range(161, 169))
SOURCE = '''var saved:{storage}[:];
var backing:{storage}[4]=[17,34,51,68];
export fn clear(input:{storage}) {{ let xs=saved; for i in xs.len {{ xs[i]={rhs}; }} }}
{extra}
fn main() {{ saved=backing[..]; {init} }}
'''

NODE_HOST = r'''
const fs = require("node:fs");
const [file, scenario, value] = process.argv.slice(1);
const module_ = new WebAssembly.Module(fs.readFileSync(file));
const goose = {};
for (const item of WebAssembly.Module.imports(module_)) goose[item.name] = () => {};
const exports_ = new WebAssembly.Instance(module_, {goose}).exports;
exports_._start();
const bytes = Buffer.from(exports_.memory.buffer);
const backing = bytes.indexOf(Buffer.from([17,34,51,68]));
if (backing < 0) throw new Error("missing backing sentinel");
const header = Buffer.alloc(8);
header.writeUInt32LE(backing, 0); header.writeUInt32LE(4, 4);
const at = bytes.indexOf(header);
if (at < 0 || bytes.indexOf(header, at + 1) >= 0) throw new Error("slice header must be unique");
const end = bytes.length;
const cases = {valid:[end-8,4], empty_end:[end,0], empty_past_end:[end+1,0],
               partial:[end-2,4], overflow:[0xfffffffe,4]};
bytes.set([161,162,163,164,165,166,167,168], end-8);
const [pointer, length] = cases[scenario];
bytes.writeUInt32LE(pointer, at); bytes.writeUInt32LE(length, at+4);
let trapped = false;
try { exports_.clear(Number(value)); } catch (error) {
  if (!(error instanceof WebAssembly.RuntimeError)) throw error;
  trapped = true;
}
process.stdout.write(JSON.stringify({trapped, tail:Array.from(bytes.subarray(end-8))}));
'''


def wasmtime_run(path, scenario, value):
    import wasmtime
    engine = wasmtime.Engine()
    module = wasmtime.Module.from_file(engine, str(path))
    store = wasmtime.Store(engine)
    linker = wasmtime.Linker(engine)
    for item in module.imports:
        assert item.module == "goose", item.module
        linker.define_func(item.module, item.name, item.type, lambda *args: None)
    exports = linker.instantiate(store, module).exports(store)
    exports["_start"](store)
    memory = exports["memory"]
    image = bytes(memory.read(store))
    backing = image.find(bytes([17, 34, 51, 68]))
    assert backing >= 0, "missing backing sentinel"
    header = struct.pack("<II", backing, 4)
    at = image.find(header)
    assert at >= 0 and image.find(header, at + 1) < 0, "slice header must be unique"
    end = len(image)
    cases = {"valid": (end - 8, 4), "empty_end": (end, 0),
             "empty_past_end": (end + 1, 0), "partial": (end - 2, 4),
             "overflow": (0xfffffffe, 4)}
    memory.write(store, TAIL, end - 8)
    memory.write(store, struct.pack("<II", *cases[scenario]), at)
    trapped = False
    try:
        exports["clear"](store, value)
    except wasmtime.Trap:
        trapped = True
    return {"trapped": trapped, "tail": list(memory.read(store, end - 8, end))}


def function_body(path, stats, name="clear"):
    payload = dict(sections(path.read_bytes()))[10]
    count, offset = uleb(payload, 0)
    functions = sorted(stats["function_info"], key=lambda item: item["index"])
    assert count == len(functions), "statistics must cover every defined function"
    for function in functions:
        size, start = uleb(payload, offset)
        body = payload[start:start + size]
        offset = start + size
        if function["name"].split("#")[0] == name:
            return body
    raise AssertionError(f"missing {name} function")


class FillLoops(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT / "build")
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)

    def compile(self, level, *, rhs="0", storage="u8", extra="", init="", text=None):
        source = self.work / "main.goose"
        if text is None:
            text = SOURCE.format(rhs=rhs, storage=storage, extra=extra, init=init)
        source.write_text(text)
        output = self.work / "program.wasm"
        stats = self.work / "stats.json"
        result = subprocess.run([str(GOOSE), str(source), "--offline", "--target", "wasm-direct",
                                 f"-O{level}", "--wasm-stats", str(stats), "-o", str(output)],
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return output, json.loads(stats.read_text())

    def engines(self, path, scenario, value=0):
        result = subprocess.run([NODE, "-e", NODE_HOST, str(path), scenario, str(value)],
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        yield "v8", json.loads(result.stdout)
        yield "wasmtime", wasmtime_run(path, scenario, value)

    def test_forged_slice_boundaries_preserve_scalar_semantics(self):
        cases = {
            "valid": (False, bytes(4) + TAIL[4:]),
            "empty_end": (False, TAIL),
            "empty_past_end": (False, TAIL),
            "partial": (True, TAIL[:-2] + bytes(2)),
            "overflow": (True, TAIL),
        }
        for level in (0, 2):
            path, stats = self.compile(level)
            self.assertIn(b"\xfc\x0b\x00", function_body(path, stats))
            for scenario, (trapped, tail) in cases.items():
                for engine, observed in self.engines(path, scenario):
                    with self.subTest(level=level, scenario=scenario, engine=engine):
                        self.assertEqual(observed, {"trapped": trapped, "tail": list(tail)})

    def test_local_byte_value(self):
        for level in (0, 2):
            for storage, value, byte in (("u8", 213, 213), ("i8", -1, 255)):
                path, stats = self.compile(level, rhs="input", storage=storage)
                self.assertIn(b"\xfc\x0b\x00", function_body(path, stats))
                for engine, observed in self.engines(path, "valid", value):
                    with self.subTest(level=level, storage=storage, engine=engine):
                        self.assertEqual(observed, {"trapped": False, "tail": [byte] * 4 + list(TAIL[4:])})

    def test_main_fill_requires_an_enclosing_loop(self):
        fill = "let xs=backing[..]; for i in xs.len { xs[i]=0; }"
        for level in (0, 2):
            for inline in (False, True):
                for nested in (False, True):
                    helper = ""
                    body = fill
                    if inline:
                        helper = "inline fn prepare() { " + fill + " }"
                        body = "prepare();"
                    if nested:
                        body = "for j in 2 { " + body + " }"
                    source = "var backing:u8[4]=[17,34,51,68]; " + helper + " fn main() { " + body + " }"
                    path, stats = self.compile(level, text=source)
                    with self.subTest(level=level, inline=inline, nested=nested):
                        # O0 keeps prepare out of line; its ordinary function
                        # body remains eligible regardless of its caller.
                        if inline and level == 0:
                            self.assertNotIn(b"\xfc\x0b\x00", function_body(path, stats, "main"))
                            self.assertIn(b"\xfc\x0b\x00", function_body(path, stats, "prepare"))
                        else:
                            self.assertEqual(b"\xfc\x0b\x00" in function_body(path, stats, "main"), nested)

    def test_region_cursors_disable_bulk_fill_in_clear(self):
        for level in (0, 2):
            path, stats = self.compile(level, extra="var owned:u8[>..]=[];", init="owned.push(7);")
            with self.subTest(level=level):
                self.assertGreater(stats["region_count"], 0)
                self.assertNotIn(b"\xfc\x0b\x00", function_body(path, stats))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=GOOSE)
    parser.add_argument("--node", default=NODE)
    args, remaining = parser.parse_known_args()
    GOOSE = args.goose.resolve()
    NODE = args.node
    unittest.main(argv=[sys.argv[0], *remaining])
