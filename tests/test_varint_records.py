#!/usr/bin/env python3
"""Inspect canonical signed variable-width record fields and dynamic offsets."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import test_enum_images as enums


def encoded(value):
    value=((value<<1)^(value>>63))&((1<<64)-1)
    result=bytearray()
    while value>=128:
        result.append((value&127)|128);value>>=7
    result.append(value)
    return bytes(result)


class VarintRecords(unittest.TestCase):
    def test_host_changed_width_updates_offsets_and_whole_copy_extent(self):
        source='''struct R{value:varint,after:u16}
var r=R{64,0x2233};var saved:const varint& =r.value;
export fn value()->i64{r.value}
export fn kept()->i64{saved}
export fn after()->i64{r.after}
export fn clone()->i64{let c=copy(r);return c.value+c.after as i64;}
fn main(){}'''
        expected={'before':['64','64','8755'],'after':['-1','-1','17493'],
                  'clone':'17492','copied':[1,85,68],'source_cursor':4}
        host=r'''
const fs=require('node:fs');const m=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
const info=JSON.parse(new TextDecoder().decode(WebAssembly.Module.customSections(m,'goose.regions')[0]));
const imports={goose:{}};for(const x of WebAssembly.Module.imports(m))imports.goose[x.name]=()=>{};
const e=new WebAssembly.Instance(m,imports).exports;e._start();
const read=()=>[e.value(),e.kept(),e.after()].map(String),before=read();
new Uint8Array(e.memory.buffer).set([1,85,68],info.activation_limit);
const after=read(),clone=String(e.clone());
const copied=Array.from(new Uint8Array(e.memory.buffer,info.activation_limit+info.region_bytes,3));
const source_cursor=new DataView(e.memory.buffer).getUint32(info.cursor_base,true)-info.activation_limit;
process.stdout.write(JSON.stringify({before,after,clone,copied,source_cursor}));
'''
        with tempfile.TemporaryDirectory(dir=enums.ROOT/'build') as name:
            path=Path(name)/'host.goose';path.write_text(source)
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
                    memory=e['memory'];info=enums.metadata(output.read_bytes());base=info['activation_limit']
                    read=lambda:[str(e[x](store)) for x in ('value','kept','after')]
                    observed={'before':read()};memory.write(store,bytes([1,85,68]),base)
                    observed['after']=read();observed['clone']=str(e['clone'](store))
                    copied=base+info['region_bytes'];observed['copied']=list(memory.read(store,copied,copied+3))
                    observed['source_cursor']=int.from_bytes(memory.read(store,info['cursor_base'],info['cursor_base']+4),'little')-base
                    self.assertEqual(observed,expected)

    def test_canonical_widths_cover_the_signed_64_bit_range(self):
        checker=enums.EnumImages('test_fixed_payload_image_has_only_active_bytes')
        values=(-9223372036854775808,-8193,-8192,-65,-64,-1,0,1,63,64,8191,8192,9223372036854775807)
        for value in values:
            with self.subTest(value=value):
                checker.check_bytes(f'struct R{{value:varint,after:u16}} var r=R{{{value},0x2233}};',
                                    (encoded(value)+bytes.fromhex('3322')).hex())

    def test_multiple_fields_and_explicit_padding_share_one_image(self):
        checker=enums.EnumImages('test_fixed_payload_image_has_only_active_bytes')
        checker.check_bytes('struct R{tag:u8,small:varint,pad 2,next:u16,large:varint,end:u8} var r=R{0x11,-65,0x2233,8192,0x44};',
                            '11'+encoded(-65).hex()+'00003322'+encoded(8192).hex()+'44')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--goose',type=Path,default=enums.GOOSE)
    args,remaining=parser.parse_known_args();enums.GOOSE=args.goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
