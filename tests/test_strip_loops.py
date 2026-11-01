#!/usr/bin/env python3
"""Verify strip-mined byte loads, tails, trap ordering and modulo elimination."""
import argparse
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

from test_fill_loops import function_body
from test_static_data import uleb

ROOT = Path(__file__).resolve().parents[1]
GOOSE = ROOT / "build/bin/goose"
NODE = "node"
TAIL = bytes(range(161, 169))
SOURCE = '''var saved:u8[:];
var backing:u8[4]=[17,34,51,68];
var total_seen:i64=0; var visited_count:i64=0;
recursive fn observe(value:i64)->i64 {{ return value; }}
export fn tick(seed:i64)->i64 {{
    let xs=saved;
    for value,i in xs {{ {body} }}
    return total_seen;
}}
export fn total()->i64 {{ return total_seen; }}
export fn visited()->i64 {{ return visited_count; }}
fn main() {{ saved=backing[..]; }}
'''
BODIES = {
    "normal": "let term=(value as i64)+i+(i%3); total_seen+=term; visited_count++;",
    "call": "total_seen+=observe((value as i64)+i+(i%3)); visited_count++;",
    "divide": "let term=100/(i-2); total_seen+=(value as i64)+term+(i%3); visited_count++;",
    "overflow": "let risky=seed+i; let delta=risky-seed; total_seen+=(value as i64)+delta+(i%3); visited_count++;",
}
NODE_HOST = r'''
const fs = require("node:fs");
const [file, scenario, seed] = process.argv.slice(1);
const module_ = new WebAssembly.Module(fs.readFileSync(file));
const goose = {};
for (const item of WebAssembly.Module.imports(module_)) goose[item.name] = () => {};
const exports_ = new WebAssembly.Instance(module_, {goose}).exports;
exports_._start();
const bytes = Buffer.from(exports_.memory.buffer);
const backing = bytes.indexOf(Buffer.from([17,34,51,68]));
if (backing < 0) throw new Error("missing backing sentinel");
const header = Buffer.alloc(8);
header.writeUInt32LE(backing,0); header.writeUInt32LE(4,4);
const at = bytes.indexOf(header);
if (at < 0 || bytes.indexOf(header,at+1) >= 0) throw new Error("slice header must be unique");
const end = bytes.length;
const cases = {valid:[end-4,4], group_trap:[end-2,4], tail_trap:[end-1,2], short:[end-2,2], empty:[end,0]};
bytes.set([161,162,163,164,165,166,167,168],end-8);
const [pointer,length] = cases[scenario];
bytes.writeUInt32LE(pointer,at); bytes.writeUInt32LE(length,at+4);
let trapped=false;
try { exports_.tick(BigInt(seed)); } catch (error) {
  if (!(error instanceof WebAssembly.RuntimeError)) throw error;
  trapped=true;
}
process.stdout.write(JSON.stringify({trapped,total:exports_.total().toString(),visited:exports_.visited().toString(),tail:Array.from(bytes.subarray(end-8))}));
'''


def wasmtime_run(path, scenario, seed):
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
    backing = image.find(bytes([17,34,51,68]))
    assert backing >= 0, "missing backing sentinel"
    header = struct.pack("<II", backing, 4)
    at = image.find(header)
    assert at >= 0 and image.find(header, at+1) < 0, "slice header must be unique"
    end = len(image)
    cases = {"valid": (end-4,4), "group_trap": (end-2,4), "tail_trap": (end-1,2),
             "short": (end-2,2), "empty": (end,0)}
    memory.write(store, TAIL, end-8)
    memory.write(store, struct.pack("<II", *cases[scenario]), at)
    trapped = False
    try:
        exports["tick"](store, seed)
    except wasmtime.Trap:
        trapped = True
    return {"trapped": trapped, "total": str(exports["total"](store)),
            "visited": str(exports["visited"](store)), "tail": list(memory.read(store,end-8,end))}


def instructions(body):
    """Decode instruction boundaries, so immediates cannot mimic rem opcodes."""
    groups, offset = uleb(body, 0)
    for _ in range(groups):
        _, offset = uleb(body, offset)
        offset += 1  # local value type
    while offset < len(body):
        op = body[offset]
        offset += 1
        yield op
        if op in (0x02,0x03,0x04,0x0c,0x0d,0x10,0x20,0x21,0x22,0x23,0x24,0x3f,0x40,0x41,0x42):
            _, offset = uleb(body, offset)  # Signed and unsigned LEB have the same byte boundary.
        elif op == 0x0e:
            count, offset = uleb(body, offset)
            for _ in range(count+1):
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
            if sub in (10,14):
                _, offset = uleb(body, offset)
                _, offset = uleb(body, offset)
            elif sub in (11,15,16,17):
                _, offset = uleb(body, offset)
            else:
                raise AssertionError(f"unexpected prefixed instruction {sub}")
        elif not (op in (0x00,0x01,0x05,0x0b,0x0f,0x1a,0x1b) or 0x45 <= op <= 0xc4):
            raise AssertionError(f"unexpected instruction {op:#x}")


class StripLoops(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT / "build")
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)

    def compile(self, level, body="normal", debug=False):
        source = self.work / "main.goose"
        source.write_text(SOURCE.format(body=BODIES[body]))
        output = self.work / "program.wasm"
        stats = self.work / "stats.json"
        command = [str(GOOSE), str(source), "--offline", "--target", "wasm-direct", f"-O{level}",
                   "--wasm-stats", str(stats), "-o", str(output)]
        if debug:
            command.append("--debug")
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        return output, json.loads(stats.read_text())

    def engines(self, path, scenario, seed=0):
        result = subprocess.run([NODE, "-e", NODE_HOST, str(path), scenario, str(seed)],
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        yield "v8", json.loads(result.stdout)
        yield "wasmtime", wasmtime_run(path,scenario,seed)

    def test_loads_and_tail_preserve_prior_iteration_effects(self):
        cases = {"valid": (False,675,4), "group_trap": (True,337,2),
                 "tail_trap": (True,168,1), "short": (False,337,2), "empty": (False,0,0)}
        for level in (0,2):
            for debug in (False,True):
                path, _ = self.compile(level, debug=debug)
                for scenario, (trapped,total,visited) in cases.items():
                    for engine, observed in self.engines(path,scenario):
                        with self.subTest(level=level,debug=debug,scenario=scenario,engine=engine):
                            self.assertEqual(observed,{"trapped":trapped,"total":str(total),"visited":str(visited),"tail":list(TAIL)})

    def test_later_lane_arithmetic_traps_preserve_prior_updates(self):
        for level in (0,2):
            for body, debug, seed, total in (("divide",False,0,182),("divide",True,0,182),
                                             ("overflow",True,(1<<63)-2,333)):
                path, _ = self.compile(level, body, debug)
                for engine, observed in self.engines(path,"valid",seed):
                    with self.subTest(level=level,body=body,debug=debug,engine=engine):
                        self.assertEqual(observed,{"trapped":True,"total":str(total),"visited":"2","tail":list(TAIL)})

    def test_only_eligible_loop_eliminates_modulo(self):
        for level in (0,2):
            for body in ("normal","call"):
                path, stats = self.compile(level,body)
                ops = list(instructions(function_body(path,stats,"tick")))
                with self.subTest(level=level,body=body):
                    self.assertEqual(0x81 in ops or 0x82 in ops, body=="call")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=GOOSE)
    parser.add_argument("--node", default=NODE)
    args, remaining = parser.parse_known_args()
    GOOSE = args.goose.resolve()
    NODE = args.node
    unittest.main(argv=[sys.argv[0],*remaining])
