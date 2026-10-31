#!/usr/bin/env python3
"""Inspect fixed-prefix records with terminal encoded array images."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import test_enum_images as enums
import test_record_images as records
from test_varint_records import encoded
from test_uleb_lengths import encoded as length_bytes


class EncodedRecordTails(unittest.TestCase):
    def test_copy_preserves_encoded_bytes_and_extent(self):
        source='''struct R{tag:u8,word:u16,values:varint[varint]}
var row=R{0x11,0x2233,[64,-65]};
export fn clone()->i64{let r=copy(row);var total=0;for n in r.values{total+=n;}return total;}
export fn length()->i64{row.values.len}
fn main(){}'''
        expected={'value':'-65','copied':[17,51,34,130,0,128,0,129,1],'source_cursor':8,'copy_cursor':9,'length_only':'1'}
        host=r'''
const fs=require('node:fs');const m=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
const info=JSON.parse(new TextDecoder().decode(WebAssembly.Module.customSections(m,'goose.regions')[0]));
const imports={goose:{}};for(const x of WebAssembly.Module.imports(m))imports.goose[x.name]=()=>{};
const e=new WebAssembly.Instance(m,imports).exports;e._start();
new Uint8Array(e.memory.buffer).set([1,128,128,128,128,128,128,128,128,128,128],info.activation_limit+3);
const length_only=String(e.length());
new Uint8Array(e.memory.buffer).set([130,0,128,0,129,1],info.activation_limit+3);
const value=String(e.clone()),base=info.activation_limit+info.region_bytes;
const copied=Array.from(new Uint8Array(e.memory.buffer,base,9)),view=new DataView(e.memory.buffer);
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
                    memory.write(store,bytes([1]+[128]*10),base+3);length_only=str(e['length'](store))
                    memory.write(store,bytes([130,0,128,0,129,1]),base+3);value=str(e['clone'](store))
                    source_cursor=int.from_bytes(memory.read(store,info['cursor_base'],info['cursor_base']+4),'little')-base
                    copy_cursor=int.from_bytes(memory.read(store,info['cursor_base']+4,info['cursor_base']+8),'little')-copy_base
                    self.assertEqual({'value':value,'copied':list(memory.read(store,copy_base,copy_base+9)),
                                      'source_cursor':source_cursor,'copy_cursor':copy_cursor,'length_only':length_only},expected)


    def test_signed_tail_and_unsigned_counts_are_contiguous(self):
        checker=enums.EnumImages('test_fixed_payload_image_has_only_active_bytes')
        checker.check_bytes('struct R{tag:u8,word:u16,values:varint[u16]}var r=R{0x11,0x2233,[64,-65]};',
            '1133220200'+(encoded(64)+encoded(-65)).hex())
        checker.check_bytes('struct R{tag:u8,word:u16,values:varint[varint]}var r=R{0x11,0x2233,[-65;128]};',
            (bytes.fromhex('113322')+length_bytes(128)+encoded(-65)*128).hex())
        checker.check_bytes('struct R{tag:u8,values:u16[varint]}var r=R{0x11,[0x2233;128]};',
            (bytes([17])+length_bytes(128)+bytes.fromhex('3322')*128).hex())

    def test_nested_defaults_and_variant_extents(self):
        checker=enums.EnumImages('test_fixed_payload_image_has_only_active_bytes')
        checker.check_bytes('struct R{tag:u8,values:varint[varint]}struct Outer{lead:u16,inner:R}var r:Outer;',
            '00000000')
        checker.check_bytes('enum E{Empty,Data{tag:u8,values:varint[varint]}}var r=E.Data{0x11,[64,-65]};',
            '1102'+(encoded(64)+encoded(-65)).hex())

    def test_prefix_references_and_byte_authoritative_counts_survive_calls(self):
        checker=records.RecordImages('test_global_record_prefix_and_tail_are_contiguous')
        checker.check_image('struct R{tag:u8,word:u16,values:u8[varint]}var r=R{0x11,0x2233,[0x44,0x55]};',
            'r','113322024455',1,3)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--goose',type=Path,default=enums.GOOSE)
    args,remaining=parser.parse_known_args();enums.GOOSE=records.GOOSE=args.goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
