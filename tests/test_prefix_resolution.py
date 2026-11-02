#!/usr/bin/env python3
"""Qualify prefix remapping and independent array-header publication."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from test_regions import CANARY, NODE_HOST, metadata, wasmtime_run

ROOT = Path(__file__).resolve().parents[1]
GOOSE = ROOT / "build/bin/goose"
NODE = "node"
CC = "cc"

# An array-only nonlocal result enables the cursor/publication machinery
# without introducing any positive-prefix owner mapping of its own.
ENABLE = '''recursive fn leave() { return [1] from enable; }
fn enable()->i64[>..] { leave(); return []; }
'''

GLOBAL = ENABLE + '''struct Packet { id:i64, values:i64[>..] }
fn observe()->i64 {
    print(41);
    return 42;
}
recursive fn initial()->Packet { return Packet { 41, [observe()] }; }
inline fn startup()->i64 {
    let packet=initial();
    print(packet.id," ",packet.values.len," ",packet.values[0]);
    let kept:const i64& =packet.id;
    packet.id+=3;
    print(kept," ",packet.id," ",packet.values[0]);
    return kept;
}
// O2 inlines this receiving constructor into _start. No ordinary function
// then registers a positive-prefix mapping before _start is emitted.
var initialized=startup();
fn main() {
    print(initialized);
    print(enable().len);
}
'''

NESTED = ENABLE + '''struct Inner { id:i64, values:i64[>..] }
struct Outer { tag:u8, inner:Inner }
recursive fn make(n:i64)->Outer {
    recursive fn observe()->i64 { return n+1; }
    return Outer { 7, Inner { n, [observe()] } };
}
fn main() {
    let packet=make(10);
    let kept:const i64& =packet.inner.id;
    recursive fn read_kept()->i64 { return kept; }
    for i in 16 {
        let temporary=make(i);
        if temporary.inner.id!=i || temporary.inner.values[0]!=i+1 { abort("bad temporary"); }
    }
    let duplicate=copy(packet);
    duplicate.inner.id+=100;
    duplicate.inner.values[0]+=200;
    print(read_kept()," ",packet.inner.id," ",packet.inner.values[0]," ",duplicate.inner.id," ",duplicate.inner.values[0]," ",packet.tag);
    print(enable().len);
}
'''

ARRAY = ENABLE + '''var values:i64[>..]=[9];
fn create<F>()->i64[] { return [F(),F()+1,F()+2]; }
fn install() {
    values=create() { print(7); 7 };
}
fn main() {
    print(enable().len);
    install();
    print(values.len," ",values[0]," ",values[1]," ",values[2]);
    let kept:const i64& =values.push(17);
    values.push(23);
    print(kept," ",values.len," ",values[4]);
}
'''

TRAP = ENABLE + f'''extern fn bench_input()->i64;
var values:i64[>..]=[9];
var neighbor:i64[>..]=[{CANARY}];
fn create<F>()->i64[] {{ return [F();1000000]; }}
fn target()->i64 {{
    values=create() {{ if bench_input()>=0 {{ return 7; }} 4 }};
    return 0;
}}
fn main() {{ print(enable().len); print(target()); }}
'''


class PrefixResolution(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT / "build")
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)

    def compile(self, source, level, limited=False):
        path = self.work / "main.goose"
        path.write_text(source)
        wasm = self.work / "program.wasm"
        stats = self.work / "stats.json"
        command = [str(GOOSE),str(path),"--offline",f"-O{level}","--target","wasm-direct",
                   "--wasm-stats",str(stats),"-o",str(wasm)]
        if limited:
            command += ["--wasm-initial-pages","1","--wasm-max-pages","3"]
        result = subprocess.run(command,capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        return path,wasm,json.loads(stats.read_text())

    def native(self, path, level):
        c = self.work / "oracle.c"
        binary = self.work / "oracle"
        result = subprocess.run([str(GOOSE),str(path),"--offline",f"-O{level}","--target","native",
                                 "--standalone","-o",str(c)],capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        result = subprocess.run([CC,str(c),"-lm","-o",str(binary)],capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        result = subprocess.run([str(binary)],capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        return result.stdout

    def qualify(self, source, positive_prefix, expected=None, startup_only=False):
        for level in (0,2):
            path,wasm,stats = self.compile(source,level)
            oracle = self.native(path,level)
            if expected is not None:
                self.assertEqual(oracle,expected)
            self.assertTrue(oracle)
            sizes = {item["name"]:item["code_bytes"] for item in stats["function_info"]}
            if startup_only and level==2:
                names = {name.split("#")[0] for name in sizes}
                self.assertNotIn("startup",names)
            if positive_prefix:
                self.assertGreater(sizes["resolve_prefix"],8)
            else:
                self.assertLessEqual(sizes["resolve_prefix"],8)
                resolver = next(item["index"] for item in stats["function_info"] if item["name"]=="resolve_prefix")
                for function in stats["function_info"]:
                    if function["name"] not in ("resolve_prefix","publish_header"):
                        self.assertNotIn(resolver,function["dependencies"],function["name"])
            self.assertGreater(sizes["publish_header"],8)
            for engine,command in (
                ("v8",[NODE,str(ROOT/"scripts/run_wasm.mjs"),str(wasm)]),
                ("wasmtime",[sys.executable,str(ROOT/"scripts/run_wasmtime.py"),str(wasm)]),
            ):
                with self.subTest(level=level,engine=engine):
                    result = subprocess.run(command,capture_output=True,text=True,timeout=30)
                    self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                    self.assertEqual(result.stdout,oracle)

    def test_global_initializer_is_the_only_positive_prefix_constructor(self):
        self.qualify(GLOBAL,True,"41\n41 1 42\n44 44 42\n44\n1\n",startup_only=True)

    def test_nested_constructor_keeps_captured_prefix_aliases_current(self):
        self.qualify(NESTED,True,"10 10 11 110 211 7\n1\n")

    def test_zero_prefix_still_publishes_growable_array_headers(self):
        self.qualify(ARRAY,False,"1\n7\n7\n7\n3 7 8 9\n17 5 23\n")

    def test_abandoned_published_extent_still_traps_before_neighbor_corruption(self):
        for level in (0,2):
            _,wasm,stats = self.compile(TRAP,level,limited=True)
            sizes = {item["name"]:item["code_bytes"] for item in stats["function_info"]}
            self.assertLessEqual(sizes["resolve_prefix"],8)
            self.assertGreater(sizes["publish_header"],8)
            runtime = metadata(wasm.read_bytes())
            result = subprocess.run([NODE,"-e",NODE_HOST,str(wasm),"0","0","1","false"],
                                    capture_output=True,text=True,timeout=60)
            self.assertEqual(result.returncode,0,result.stderr)
            observations = [("v8",json.loads(result.stdout)),
                            ("wasmtime",wasmtime_run(wasm,runtime,0,0,1))]
            for engine,observed in observations:
                with self.subTest(level=level,engine=engine):
                    self.assertIn("data region exhausted",observed["error"])
                    self.assertEqual(observed["numbers"],["1"])
                    self.assertEqual(observed["canary"],str(CANARY))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose",type=Path,default=GOOSE)
    parser.add_argument("--node",default=NODE)
    parser.add_argument("--cc",default=CC)
    args,remaining = parser.parse_known_args()
    GOOSE = args.goose.resolve()
    NODE = args.node
    CC = args.cc
    unittest.main(argv=[sys.argv[0],*remaining])
