#!/usr/bin/env python3
"""Inspect combined unsigned lengths and sequential signed element images."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import test_enum_images as enums
from test_varint_records import encoded
from test_uleb_lengths import encoded as length_bytes


class CombinedVarints(unittest.TestCase):
    def test_copy_preserves_encoded_bytes_and_extent(self):
        source='''var values:varint[varint]=[64,-65];
export fn clone()->i64{let rows=copy(values);var total=0;for n in rows{total+=n;}return total;}
export fn length()->i64{values.len}
fn main(){}'''
        expected={'value':'-65','copied':[2,128,0,129,1],'source_cursor':5,'copy_cursor':5,'length_only':'1'}
        host=r'''
const fs=require('node:fs');const m=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
const info=JSON.parse(new TextDecoder().decode(WebAssembly.Module.customSections(m,'goose.regions')[0]));
const imports={goose:{}};for(const x of WebAssembly.Module.imports(m))imports.goose[x.name]=()=>{};
const e=new WebAssembly.Instance(m,imports).exports;e._start();
new Uint8Array(e.memory.buffer).set([1,128,128,128,128,128,128,128,128,128,128],info.activation_limit);
const length_only=String(e.length());
new Uint8Array(e.memory.buffer).set([130,0,128,0,129,1],info.activation_limit);
const value=String(e.clone()),base=info.activation_limit+info.region_bytes;
const copied=Array.from(new Uint8Array(e.memory.buffer,base,5)),view=new DataView(e.memory.buffer);
process.stdout.write(JSON.stringify({value,copied,length_only,source_cursor:view.getUint32(info.cursor_base,true)-info.activation_limit,
copy_cursor:view.getUint32(info.cursor_base+4,true)-base}));
'''
        with tempfile.TemporaryDirectory(dir=enums.ROOT/'build') as name:
            path=Path(name)/'copy.goose';path.write_text(source)
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
                    memory=e['memory'];info=enums.metadata(output.read_bytes());base=info['activation_limit'];copy_base=base+info['region_bytes']
                    memory.write(store,bytes([1]+[128]*10),base);length_only=str(e['length'](store))
                    memory.write(store,bytes([130,0,128,0,129,1]),base);value=str(e['clone'](store))
                    source_cursor=int.from_bytes(memory.read(store,info['cursor_base'],info['cursor_base']+4),'little')-base
                    copy_cursor=int.from_bytes(memory.read(store,info['cursor_base']+4,info['cursor_base']+8),'little')-copy_base
                    self.assertEqual({'value':value,'copied':list(memory.read(store,copy_base,copy_base+5)),
                                      'source_cursor':source_cursor,'copy_cursor':copy_cursor,'length_only':length_only},expected)


    def test_prefix_boundaries_have_packed_signed_elements(self):
        checker=enums.EnumImages('test_fixed_payload_image_has_only_active_bytes')
        for count in (0,1,127,128,16383,16384):
            with self.subTest(count=count):
                checker.check_bytes(f'var rows:varint[varint]=[-65;{count}];',
                    (length_bytes(count)+encoded(-65)*count).hex())

    def test_default_and_named_grow_keep_exact_extents(self):
        checker=enums.EnumImages('test_fixed_payload_image_has_only_active_bytes')
        checker.check_bytes('var rows:varint[varint];','00')
        checker.check_bytes('recursive fn make()->varint[varint]{var a:varint[>..]=[8192;128];return a;}var rows=make();',
            (length_bytes(128)+encoded(8192)*128).hex())


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--goose',type=Path,default=enums.GOOSE)
    args,remaining=parser.parse_known_args();enums.GOOSE=args.goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
