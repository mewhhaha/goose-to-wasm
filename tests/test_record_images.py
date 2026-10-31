#!/usr/bin/env python3
"""Inspect contiguous record bytes and prefix references after _start exits."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from test_regions import metadata

ROOT = Path(__file__).resolve().parents[1]
GOOSE = ROOT / "build/bin/goose"
NODE_HOST = r'''
const fs = require("node:fs");
const [path,size,wordOffset,lengthOffset,lengthWidth] = process.argv.slice(1);
const module = new WebAssembly.Module(fs.readFileSync(path));
const info = JSON.parse(new TextDecoder().decode(WebAssembly.Module.customSections(module,"goose.regions")[0]));
const imports={goose:{}};
for(const item of WebAssembly.Module.imports(module)) imports.goose[item.name]=()=>{};
const instance=new WebAssembly.Instance(module,imports);
instance.exports._start();
const base=info.activation_limit;
const read=()=>[instance.exports.read_word(),instance.exports.saved_word(),instance.exports.read_len()].map(String);
const result={image:Array.from(new Uint8Array(instance.exports.memory.buffer,base,Number(size))),before:read()};
for(let n=0;n<100;n++) if(instance.exports.churn(BigInt(n))!==BigInt(n+1)) throw new Error("bad churn");
result.retained=read();
const view=new DataView(instance.exports.memory.buffer);
view.setUint16(base+Number(wordOffset),0x6677,true);
if(Number(lengthWidth)===1) view.setUint8(base+Number(lengthOffset),1);
else view.setUint32(base+Number(lengthOffset),1,true);
result.after=read();
process.stdout.write(JSON.stringify(result));
'''


class RecordImages(unittest.TestCase):
    def check_image(self, declaration, projection, image, word_offset, length_offset, length_width=1, count=2, word=0x2233):
        source = declaration + f'''
var saved:const u16& = {projection}.word;
export fn read_word()->i64 {{ {projection}.word }}
export fn saved_word()->i64 {{ saved }}
export fn read_len()->i64 {{ {projection}.values.len }}
export fn churn(n:i64)->i64 {{ let local=R{{1,n as u16,[7]}}; local.word as i64+1 }}
fn main() {{}}
'''
        expected = {"image":list(bytes.fromhex(image)), "before":[str(word),str(word),str(count)],
                    "retained":[str(word),str(word),str(count)], "after":[str(0x6677),str(0x6677),"1"]}
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as name:
            directory=Path(name)
            path=directory/"main.goose"; path.write_text(source)
            for level in (0,2):
                with self.subTest(level=level):
                    output=directory/f"O{level}.wasm"
                    result=subprocess.run([str(GOOSE),str(path),"--offline",f"-O{level}","--target","wasm-direct","-o",str(output)],capture_output=True,text=True)
                    self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                    actual=subprocess.run(["node","-e",NODE_HOST,str(output),str(len(expected['image'])),str(word_offset),str(length_offset),str(length_width)],check=True,capture_output=True,text=True)
                    self.assertEqual(json.loads(actual.stdout),expected)
                    import wasmtime
                    engine=wasmtime.Engine(); module=wasmtime.Module.from_file(engine,str(output)); store=wasmtime.Store(engine); linker=wasmtime.Linker(engine)
                    for item in module.imports:
                        self.assertEqual(item.module,"goose")
                        linker.define_func(item.module,item.name,item.type,lambda *args:None)
                    instance=linker.instantiate(store,module); exports=instance.exports(store); exports['_start'](store)
                    memory=exports['memory']; base=metadata(output.read_bytes())['activation_limit']
                    read=lambda:[str(exports[x](store)) for x in ['read_word','saved_word','read_len']]
                    observed={"image":list(memory.read(store,base,base+len(expected['image']))),"before":read()}
                    for n in range(100): self.assertEqual(exports['churn'](store,n),n+1)
                    observed['retained']=read()
                    memory.write(store,bytes.fromhex('7766'),base+word_offset)
                    memory.write(store,(1).to_bytes(length_width,'little'),base+length_offset)
                    observed['after']=read(); self.assertEqual(observed,expected)

    def test_global_record_prefix_and_tail_are_contiguous(self):
        self.check_image('struct R {tag:u8,word:u16,values:u8[u8]} var r=R{0x11,0x2233,[0x44,0x55]};',
                         'r','113322024455',1,3)

    def test_nested_prefix_references_outlive_calls(self):
        self.check_image('struct R {tag:u8,word:u16,values:u8[u8]} struct Outer {lead:u8,inner:R} var r=Outer{0xaa,R{0x11,0x2233,[0x44,0x55]}};',
                         'r.inner','aa113322024455',2,4)

    def test_limited_capacity_image_follows_prefix(self):
        self.check_image('struct R {tag:u8,word:u16,values:u8[..]} var r=R{0x11,0x2233,[..3]}; fn initialize()->i64 {r.values.push(9);r.values.push(10);return 0;} var initialized=initialize();',
                         'r','1133220300000002000000090a00',1,7,4)

    def test_standalone_variant_uses_its_own_image(self):
        self.check_image('struct R {tag:u8,word:u16,values:u8[u8]} enum E {Data{tag:u8,word:u16,values:u8[u8]},Other{n:i64}} var r=E.Data{0x11,0x2233,[0x44,0x55]};',
                         'r','113322024455',1,3)

    def test_implicit_global_default_has_an_empty_tail(self):
        self.check_image('struct R {tag:u8,word:u16,values:u8[u8]} var r:R;',
                         'r','00000000',1,3,count=0,word=0)


if __name__ == "__main__":
    parser=argparse.ArgumentParser(); parser.add_argument('--goose',type=Path,default=GOOSE)
    args,remaining=parser.parse_known_args(); GOOSE=args.goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
