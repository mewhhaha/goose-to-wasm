#!/usr/bin/env python3
"""Check while-loop tails and stores committed before later-copy traps."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import unittest

import test_strip_loops as strip

SOURCE = '''var values:i64[8]=[11,22,33,44,55,66,77,88];
export fn run(count:i64,offset:i64) {
    var xs=values[..]; var j=7;
    while j>7-count && xs[j-1]>0 { xs[j-offset]=xs[j-1]; j--; }
}
export fn read(i:i64)->i64 { values[i] }
fn main() {}
'''
CASES = [(count, 0) for count in range(6)] + [(7, 8-prior) for prior in range(5)]
NODE_HOST = r'''
const fs=require("node:fs");
const m=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
const cases=JSON.parse(process.argv[2]),goose={};
for(const item of WebAssembly.Module.imports(m))goose[item.name]=()=>{};
const result=cases.map(([count,offset])=>{
  const e=new WebAssembly.Instance(m,{goose}).exports;e._start();
  let trapped=false;
  try{e.run(BigInt(count),BigInt(offset));}
  catch(error){if(!(error instanceof WebAssembly.RuntimeError))throw error;trapped=true;}
  return {trapped,values:Array.from({length:8},(_,i)=>Number(e.read(BigInt(i))))};
});
process.stdout.write(JSON.stringify(result));
'''


def expected(count, offset):
    values = list(range(11, 89, 11))
    j = 7
    while j > 7-count and values[j-1] > 0:
        destination = j-offset
        if not 0 <= destination < len(values):
            return {"trapped": True, "values": values}
        values[destination] = values[j-1]
        j -= 1
    return {"trapped": False, "values": values}


def wasmtime_run(path):
    import wasmtime
    engine = wasmtime.Engine()
    module = wasmtime.Module.from_file(engine, str(path))
    result = []
    for count, offset in CASES:
        store = wasmtime.Store(engine)
        linker = wasmtime.Linker(engine)
        for item in module.imports:
            linker.define_func(item.module, item.name, item.type, lambda *args: None)
        exports = linker.instantiate(store, module).exports(store)
        exports["_start"](store)
        trapped = False
        try:
            exports["run"](store, count, offset)
        except wasmtime.Trap:
            trapped = True
        result.append({"trapped": trapped, "values": [exports["read"](store, i) for i in range(8)]})
    return result


class WhileUnroll(unittest.TestCase):
    setUp = strip.StripLoops.setUp
    compile = strip.StripLoops.compile

    def test_tails_and_partial_stores(self):
        answers = [expected(*case) for case in CASES]
        for level in (0, 2):
            for debug in (False, True):
                path, _ = self.compile(level, debug=debug, text=SOURCE)
                host = subprocess.run([strip.NODE, "-e", NODE_HOST, str(path), json.dumps(CASES)],
                                      capture_output=True, text=True, timeout=60)
                self.assertEqual(host.returncode, 0, host.stderr)
                for engine, observed in (("v8", json.loads(host.stdout)), ("wasmtime", wasmtime_run(path))):
                    for case, actual, answer in zip(CASES, observed, answers, strict=True):
                        with self.subTest(level=level, debug=debug, engine=engine, case=case):
                            self.assertEqual(actual, answer)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=strip.GOOSE)
    parser.add_argument("--node", default=strip.NODE)
    args, remaining = parser.parse_known_args()
    strip.GOOSE = args.goose.resolve()
    strip.NODE = args.node
    unittest.main(argv=[sys.argv[0], *remaining])
