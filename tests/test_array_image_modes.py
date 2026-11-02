#!/usr/bin/env python3
"""Qualify the closed-module raw-image proof and its conservative boundaries."""
import argparse
from pathlib import Path
import struct
import subprocess
import sys
import unittest

import test_prefix_resolution as prefix
from test_regions import metadata

RAW = '''var shared:i64[>..]=[2,3];
var shrinking:i64[>..<]=[7,8,9];
fn bump(xs:i64[:]) { for i in xs.len { xs[i]+=1; } }
fn escaped()->i64[>..] {
    var local:i64[>..]=[10,11];
    recursive fn leave() { return copy(local) from escaped; }
    leave(); return [];
}
fn main() {
    bump(shared[..]); shrinking.pop();
    let result=escaped(); var captured:i64[>..]=[20,21];
    recursive fn append() { captured.push(22); }
    append(); print(shared," ",shrinking," ",result," ",captured);
}
'''
CAPACITY = '''fn capacity()->i64 { return 5; }
fn main() {
    var limited:i64[..]=[..capacity()]; limited.push(7); limited.push(8);
    print(limited.len," ",limited.cap," ",limited);
}
'''
NESTED = '''enum Leaf { Data { values:i64[u16] } }
struct Inner { code:u8, leaf:Leaf.Data }
struct Outer { tag:u8, inner:Inner }
fn main() {
    let box=Outer {1,Inner {2,Leaf.Data {[7,8]}}};
    var grow:i64[>..]=copy(box.inner.leaf.values); grow.push(9);
    print(box.tag," ",box.inner.code," ",grow," ",box.inner.leaf.values.len);
}
'''
FORGED = '''extern fn forge()->i64;
var rows:u8[>..]=[17,34,51];
fn main() { let ignored=forge(); print(rows.len," ",rows[0]); }
'''
FORGE_HOST = r'''
const fs=require("node:fs"),m=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
const info=JSON.parse(new TextDecoder().decode(WebAssembly.Module.customSections(m,"goose.regions")[0]));
let e;const chunks=[];
const forge=()=>{
  const bytes=new Uint8Array(e.memory.buffer),v=new DataView(bytes.buffer),headers=[];
  for(let at=0;at+24<=info.activation_base;at+=4)
    if(v.getUint32(at,true)===info.activation_limit && v.getUint32(at+4,true)===3 &&
       v.getUint32(at+8,true)===info.activation_limit+info.region_bytes && v.getUint32(at+20,true)===0)headers.push(at);
  if(headers.length!==1)throw new Error("expected one static Grow control");
  const at=headers[0],image=bytes.length-64,limit=v.getUint32(at+8,true);
  bytes.set([1,77],image);
  [info.activation_limit,99,limit,1,image,1].forEach((word,i)=>v.setUint32(at+i*4,word,true));
  return 0n;
};
const goose={print_i64:x=>chunks.push(String(x)),print_u64:x=>chunks.push(String(BigInt.asUintN(64,x))),
  write:(p,n)=>chunks.push(Buffer.from(e.memory.buffer,p>>>0,n>>>0).toString()),newline:()=>chunks.push("\n")};
for(const item of WebAssembly.Module.imports(m))if(item.module==="goose" && !(item.name in goose))
  goose[item.name]=()=>{throw new Error("unexpected host call: "+item.name);};
e=new WebAssembly.Instance(m,{goose,env:{forge}}).exports;e._start();
process.stdout.write(chunks.join(""));
'''


def forged_wasmtime(path):
    import wasmtime
    engine=wasmtime.Engine(); module=wasmtime.Module.from_file(engine,str(path))
    store=wasmtime.Store(engine); linker=wasmtime.Linker(engine); chunks=[]
    info=metadata(path.read_bytes())

    def forge(caller):
        memory=caller.get("memory"); image=memory.data_len(caller)-64
        static=bytes(memory.read(caller,0,info["activation_base"])); headers=[]
        for at in range(0,len(static)-23,4):
            base,count,limit,_,_,mode=struct.unpack_from("<IIIIII",static,at)
            if base==info["activation_limit"] and count==3 and limit==base+info["region_bytes"] and mode==0:
                headers.append((at,limit))
        assert len(headers)==1,"expected one static Grow control"
        at,limit=headers[0]; memory.write(caller,bytes([1,77]),image)
        memory.write(caller,struct.pack("<IIIIII",info["activation_limit"],99,limit,1,image,1),at)
        return 0

    functions={"forge":(forge,True),"print_i64":(lambda x:chunks.append(str(x)),False),
               "print_u64":(lambda x:chunks.append(str(x&((1<<64)-1))),False),
               "write":(lambda c,p,n:chunks.append(bytes(c.get("memory").read(c,p,p+n)).decode()),True),
               "newline":(lambda:chunks.append("\n"),False)}
    def unexpected(*args):
        raise AssertionError("unexpected host call")
    for item in module.imports:
        callback,caller=functions.get(item.name,(unexpected,False))
        linker.define_func(item.module,item.name,item.type,callback,access_caller=caller)
    linker.instantiate(store,module).exports(store)["_start"](store)
    return "".join(chunks)


class ArrayImageModes(unittest.TestCase):
    setUp = prefix.PrefixResolution.setUp
    compile = prefix.PrefixResolution.compile
    native = prefix.PrefixResolution.native

    def qualify(self, source, expected, *, raw):
        for level in (0, 2):
            path, wasm, stats = self.compile(source, level)
            with self.subTest(level=level, check="native"):
                self.assertEqual(self.native(path, level), expected)
            names = {function["name"].split("#")[0] for function in stats["function_info"]}
            for helper in ("read_uleb_array", "patch_uleb_array_length"):
                if raw is None:
                    continue
                with self.subTest(level=level, helper=helper):
                    if raw:
                        self.assertNotIn(helper, names)
                    else:
                        self.assertIn(helper, names)
            for engine, command in (
                ("v8", [prefix.NODE, str(prefix.ROOT/"scripts/run_wasm.mjs"), str(wasm)]),
                ("wasmtime", [sys.executable, str(prefix.ROOT/"scripts/run_wasmtime.py"), str(wasm)]),
            ):
                with self.subTest(level=level, engine=engine):
                    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
                    self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
                    self.assertEqual(result.stdout, expected)

    def test_raw_ownership_and_view_channels_need_no_uleb_dispatch(self):
        self.qualify(RAW, "[3, 4] [7, 8] [10, 11] [20, 21, 22]\n", raw=True)

    def test_public_export_keeps_general_dispatch_for_host_visible_memory(self):
        source = '''var values:i64[>..]=[7,8];
export fn count()->i64 { values.len }
fn main() { print(values.len); }'''
        self.qualify(source, "2\n", raw=False)

    def test_reachable_user_extern_keeps_general_dispatch(self):
        for level in (0, 2):
            _, wasm, stats = self.compile(FORGED, level)
            names = {function["name"].split("#")[0] for function in stats["function_info"]}
            with self.subTest(level=level):
                self.assertTrue({"read_uleb_array", "patch_uleb_array_length"} <= names)
            host=subprocess.run([prefix.NODE,"-e",FORGE_HOST,str(wasm)],capture_output=True,text=True,timeout=30)
            self.assertEqual(host.returncode,0,host.stdout+host.stderr)
            for engine,stdout in (("v8",host.stdout),("wasmtime",forged_wasmtime(wasm))):
                with self.subTest(level=level,engine=engine):
                    self.assertEqual(stdout,"1 77\n")

    def test_pure_math_intrinsic_preserves_the_raw_proof(self):
        source='''extern fn root(x:f64)->f64="sqrt";
var values:i64[>..]=[9,16];
fn main() { print(root(values[0] as f64)," ",values.len); }'''
        self.qualify(source,"3.0 2\n",raw=True)

    def test_each_prefixed_array_keeps_general_dispatch(self):
        for storage in ("u8", "u16", "u32", "u64", "varint"):
            source = f'''var values:i64[{storage}]=[7,8];
fn main() {{ var grow:i64[>..]=copy(values); grow.push(9); print(grow," ",values.len); }}'''
            with self.subTest(storage=storage):
                raw = False
                if storage == "varint":
                    # ULEB images inline their accessors instead of emitting helpers.
                    raw = None
                self.qualify(source, "[7, 8, 9] 2\n", raw=raw)

    def test_capacity_expression_and_runtime_limited_images_are_not_raw(self):
        self.qualify(CAPACITY, "2 5 [7, 8]\n", raw=False)

    def test_nested_record_and_enum_fields_constrain_the_proof(self):
        self.qualify(NESTED, "1 2 [7, 8, 9] 2\n", raw=False)

    def test_normal_and_inline_natural_results_constrain_grow_receivers(self):
        for declaration, storage in (("recursive", "u8"), ("inline", "varint")):
            source = f'''{declaration} fn produced()->i64[{storage}] {{ return [3,4]; }}
fn main() {{ var grow:i64[>..]=produced(); grow.push(9); print(grow); }}'''
            with self.subTest(declaration=declaration):
                raw = False
                if declaration == "inline":
                    # Inlining may construct the literal directly in the grow receiver.
                    raw = None
                self.qualify(source, "[3, 4, 9]\n", raw=raw)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=prefix.GOOSE)
    parser.add_argument("--node", default=prefix.NODE)
    parser.add_argument("--cc", default=prefix.CC)
    args, remaining = parser.parse_known_args()
    prefix.GOOSE = args.goose.resolve()
    prefix.NODE = args.node
    prefix.CC = args.cc
    unittest.main(argv=[sys.argv[0], *remaining])
