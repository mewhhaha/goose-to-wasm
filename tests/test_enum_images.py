#!/usr/bin/env python3
"""Inspect active enum images, physical cursors and persistent payload views."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import test_record_images as records
from test_regions import metadata

ROOT=Path(__file__).resolve().parents[1]
GOOSE=ROOT/'build/bin/goose'
NODE_HOST=r'''
const fs=require("node:fs");
const [path,count]=process.argv.slice(1);
const module=new WebAssembly.Module(fs.readFileSync(path));
const info=JSON.parse(new TextDecoder().decode(WebAssembly.Module.customSections(module,"goose.regions")[0]));
const imports={goose:{}};
for(const item of WebAssembly.Module.imports(module)) imports.goose[item.name]=()=>{};
const instance=new WebAssembly.Instance(module,imports); instance.exports._start();
const view=new DataView(instance.exports.memory.buffer);
process.stdout.write(JSON.stringify({image:Array.from(new Uint8Array(view.buffer,info.activation_limit,Number(count))),cursor:view.getUint32(info.cursor_base,true)-info.activation_limit}));
'''


class EnumImages(unittest.TestCase):
    def check_bytes(self,source,expected,main_body=''):
        expected=bytes.fromhex(expected)
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as name:
            path=Path(name)/'main.goose'; path.write_text(source+'\nfn main() {'+main_body+'}')
            for level in (0,2):
                with self.subTest(level=level):
                    output=path.with_suffix('.wasm')
                    result=subprocess.run([str(GOOSE),str(path),'--offline',f'-O{level}','--target','wasm-direct','-o',str(output)],capture_output=True,text=True)
                    self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                    result=subprocess.run(['node','-e',NODE_HOST,str(output),str(len(expected))],check=True,capture_output=True,text=True)
                    self.assertEqual(json.loads(result.stdout),{'image':list(expected),'cursor':len(expected)})
                    import wasmtime
                    engine=wasmtime.Engine(); module=wasmtime.Module.from_file(engine,str(output)); store=wasmtime.Store(engine); linker=wasmtime.Linker(engine)
                    for item in module.imports: linker.define_func(item.module,item.name,item.type,lambda *args:None)
                    instance=linker.instantiate(store,module); exports=instance.exports(store); exports['_start'](store)
                    info=metadata(output.read_bytes()); memory=exports['memory']; base=info['activation_limit']
                    self.assertEqual(bytes(memory.read(store,base,base+len(expected))),expected)
                    cursor=int.from_bytes(memory.read(store,info['cursor_base'],info['cursor_base']+4),'little')
                    self.assertEqual(cursor-base,len(expected))

    def test_empty_image_reserves_no_inactive_payload(self):
        self.check_bytes('enum E {Empty,Big{values:u64[8192]}} var e:E..=E.Empty;','00')

    def test_fixed_payload_image_has_only_active_bytes(self):
        self.check_bytes('enum E {Empty,Data{tag:u8,word:u16},Big{values:u64[8192]}} var e:E..=E.Data{0x11,0x2233};','01113322')

    def test_two_byte_tag_has_no_empty_payload_slot(self):
        variants=','.join(f'V{n}' for n in range(257))
        self.check_bytes(f'enum E {{{variants}}} var e:E..=E.V256;','0001')

    def test_variable_payload_prefix_reference_outlives_calls(self):
        checker=records.RecordImages('test_global_record_prefix_and_tail_are_contiguous')
        checker.check_image('struct R{tag:u8,word:u16,values:u8[u8]} enum E{Empty,Data{tag:u8,word:u16,values:u8[u8]}} var e:E..=E.Data{0x11,0x2233,[0x44,0x55]}; var payload:const E.Data& =match e {Data &p=>p,_=>abort("bad")};',
                            'payload','01113322024455',2,4)

    def test_limited_payload_keeps_capacity_and_persistent_prefix(self):
        checker=records.RecordImages('test_global_record_prefix_and_tail_are_contiguous')
        checker.check_image('struct R{tag:u8,word:u16,values:u8[u8]} enum E{Empty,Data{tag:u8,word:u16,values:u8[..]}} var e:E..=E.Data{0x11,0x2233,[..3]}; fn initialize()->i64 {match e {Data &p=>{p.values.push(9);p.values.push(10);},_=>{}} return 0;} var initialized=initialize(); var payload:const E.Data& =match e {Data &p=>p,_=>abort("bad")};',
                            'payload','011133220300000002000000090a00',2,8,4)


if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--goose',type=Path,default=GOOSE)
    args,remaining=parser.parse_known_args(); GOOSE=args.goose.resolve(); records.GOOSE=GOOSE
    unittest.main(argv=[sys.argv[0],*remaining])
