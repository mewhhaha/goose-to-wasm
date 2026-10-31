#!/usr/bin/env python3
"""Inspect raw growable images, reset cursors and per-element encoded copies."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import test_enum_images as enums
from test_varint_records import encoded


class VarintGrow(unittest.TestCase):
    def test_push_and_append_use_raw_element_bytes(self):
        checker=enums.EnumImages('test_fixed_payload_image_has_only_active_bytes')
        checker.check_bytes('var rows:varint[>..]=[];fn initialize()->i64{rows.push(64);rows.append([-65,8192]);return 0;}var initialized=initialize();',
                            (encoded(64)+encoded(-65)+encoded(8192)).hex())

    def test_clear_and_whole_assignment_reset_the_cursor(self):
        checker=enums.EnumImages('test_fixed_payload_image_has_only_active_bytes')
        checker.check_bytes('var rows:varint[>..]=[-9223372036854775808];',
                            encoded(8192).hex(),main_body='rows.clear();rows.append([64,-65]);rows=[8192];')

    def test_borrowed_append_preserves_nonminimal_encoded_bytes(self):
        source='''var source:varint[u8]=[64,-65];var target:varint[>..]=[];
export fn append()->i64{target.append(source);return target.len;}
fn main(){}'''
        expected={'count':'2','image':[128,0,129,1],'cursor':4}
        host=r'''
const fs=require('node:fs');const m=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
const info=JSON.parse(new TextDecoder().decode(WebAssembly.Module.customSections(m,'goose.regions')[0]));
const imports={goose:{}};for(const x of WebAssembly.Module.imports(m))imports.goose[x.name]=()=>{};
const e=new WebAssembly.Instance(m,imports).exports;e._start();
new Uint8Array(e.memory.buffer)[info.activation_limit+2]=0;
const count=String(e.append()),base=info.activation_limit+info.region_bytes;
const image=Array.from(new Uint8Array(e.memory.buffer,base,4));
const cursor=new DataView(e.memory.buffer).getUint32(info.cursor_base+4,true)-base;
process.stdout.write(JSON.stringify({count,image,cursor}));
'''
        with tempfile.TemporaryDirectory(dir=enums.ROOT/'build') as name:
            path=Path(name)/'append.goose';path.write_text(source)
            for level in (0,2):
                with self.subTest(level=level):
                    output=path.with_suffix('.wasm')
                    result=subprocess.run([str(enums.GOOSE),str(path),'--offline',f'-O{level}','--target','wasm-direct','-o',str(output)],capture_output=True,text=True)
                    self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                    actual=subprocess.run(['node','-e',host,str(output)],check=True,capture_output=True,text=True)
                    self.assertEqual(json.loads(actual.stdout),expected)
                    import wasmtime
                    engine=wasmtime.Engine();module=wasmtime.Module.from_file(engine,str(output));store=wasmtime.Store(engine);linker=wasmtime.Linker(engine)
                    for item in module.imports:linker.define_func(item.module,item.name,item.type,lambda *args:None)
                    instance=linker.instantiate(store,module);e=instance.exports(store);e['_start'](store)
                    memory=e['memory'];info=enums.metadata(output.read_bytes());base=info['activation_limit']+info['region_bytes']
                    memory.write(store,b'\0',info['activation_limit']+2);count=str(e['append'](store))
                    cursor=int.from_bytes(memory.read(store,info['cursor_base']+4,info['cursor_base']+8),'little')-base
                    self.assertEqual({'count':count,'image':list(memory.read(store,base,base+4)),'cursor':cursor},expected)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--goose',type=Path,default=enums.GOOSE)
    args,remaining=parser.parse_known_args();enums.GOOSE=args.goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
