#!/usr/bin/env python3
"""Inspect unsigned prefix widths, reservation timing and byte authority."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import test_enum_images as enums


def encoded(value):
    result=bytearray()
    while value>=128:
        result.append((value&127)|128);value>>=7
    result.append(value)
    return bytes(result)


class ULEBLengths(unittest.TestCase):
    def test_prefix_width_changes_are_authoritative_without_cursor_changes(self):
        source='''var rows:u8[varint]=[7;128];
export fn length()->i64{rows.len}
export fn first()->u8{rows[0]}
export fn last()->u8{rows[rows.len-1]}
export fn clone()->i64{let out:u8[varint]=copy(rows);return out.len;}
fn main(){}'''
        expected={'short':['1','1','1'],'short_copy':'1','short_image':[1,1],
                  'wide':['128','7','0'],'wide_copy':'128','wide_prefix':[128,1],
                  'wide_tail':0,'source_cursor':130,'copy_cursor':130}
        host=r'''
const fs=require('node:fs');const m=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
const info=JSON.parse(new TextDecoder().decode(WebAssembly.Module.customSections(m,'goose.regions')[0]));
const imports={goose:{}};for(const x of WebAssembly.Module.imports(m))imports.goose[x.name]=()=>{};
const e=new WebAssembly.Instance(m,imports).exports;e._start();
const base=info.activation_limit,copybase=base+info.region_bytes,read=()=>[e.length(),e.first(),e.last()].map(String);
new Uint8Array(e.memory.buffer)[base]=1;
const short=read(),short_copy=String(e.clone()),short_image=Array.from(new Uint8Array(e.memory.buffer,copybase,2));
new Uint8Array(e.memory.buffer).set([128,129,0],base);
const wide=read(),wide_copy=String(e.clone()),wide_prefix=Array.from(new Uint8Array(e.memory.buffer,copybase,2));
const wide_tail=new Uint8Array(e.memory.buffer)[copybase+129],view=new DataView(e.memory.buffer);
process.stdout.write(JSON.stringify({short,short_copy,short_image,wide,wide_copy,wide_prefix,wide_tail,
source_cursor:view.getUint32(info.cursor_base,true)-base,copy_cursor:view.getUint32(info.cursor_base+4,true)-copybase}));
'''
        with tempfile.TemporaryDirectory(dir=enums.ROOT/'build') as name:
            path=Path(name)/'authority.goose';path.write_text(source)
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
                    instance=linker.instantiate(store,module);e=instance.exports(store);e['_start'](store);memory=e['memory']
                    info=enums.metadata(output.read_bytes());base=info['activation_limit'];copybase=base+info['region_bytes']
                    read=lambda:[str(e[x](store)) for x in ('length','first','last')]
                    memory.write(store,bytes([1]),base);observed={'short':read(),'short_copy':str(e['clone'](store)),
                        'short_image':list(memory.read(store,copybase,copybase+2))}
                    memory.write(store,bytes([128,129,0]),base);observed.update(wide=read(),wide_copy=str(e['clone'](store)),
                        wide_prefix=list(memory.read(store,copybase,copybase+2)),wide_tail=memory.read(store,copybase+129,copybase+130)[0],
                        source_cursor=int.from_bytes(memory.read(store,info['cursor_base'],info['cursor_base']+4),'little')-base,
                        copy_cursor=int.from_bytes(memory.read(store,info['cursor_base']+4,info['cursor_base']+8),'little')-copybase)
                    self.assertEqual(observed,expected)

    def test_known_prefix_widths_and_packed_stride(self):
        checker=enums.EnumImages('test_fixed_payload_image_has_only_active_bytes')
        for count in (0,1,127,128,16383,16384):
            with self.subTest(count=count):
                checker.check_bytes(f'var rows:u8[varint]=[7;{count}];',(encoded(count)+bytes([7])*count).hex())
        checker.check_bytes('struct P{a:u8,b:u16} var rows:P[varint]=[P{0x11,0x2233};128];',
                            (encoded(128)+bytes.fromhex('113322')*128).hex())

    def test_global_default_and_named_grow_result_have_exact_extents(self):
        checker=enums.EnumImages('test_fixed_payload_image_has_only_active_bytes')
        checker.check_bytes('var rows:u8[varint];','00')
        checker.check_bytes('recursive fn make()->u8[varint]{var a:u8[>..]=[7;128];return a;}var rows=make();',
                            (encoded(128)+bytes([7])*128).hex())

    def test_unknown_reservation_does_not_write_before_production(self):
        source='''extern fn probe()->i64;
recursive fn make()->u8[u8]{print(probe());return[7;128];}
export fn tick()->i64{let a:u8[varint]=make();return a.len;}
fn main(){}'''
        expected={'seen':[165],'count':'128','prefix':[128,1],'cursor':130}
        host=r'''
const fs=require('node:fs');const m=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
const info=JSON.parse(new TextDecoder().decode(WebAssembly.Module.customSections(m,'goose.regions')[0]));
let instance;const seen=[],imports={goose:{},env:{probe:()=>{seen.push(new Uint8Array(instance.exports.memory.buffer)[info.activation_limit]);return 0n;}}};
for(const x of WebAssembly.Module.imports(m))if(x.module==='goose')imports.goose[x.name]=()=>{};
instance=new WebAssembly.Instance(m,imports);const e=instance.exports;e._start();
const missing=info.activation_limit+1-e.memory.buffer.byteLength;if(missing>0)e.memory.grow(Math.ceil(missing/65536));
new Uint8Array(e.memory.buffer)[info.activation_limit]=165;
const count=String(e.tick()),prefix=Array.from(new Uint8Array(e.memory.buffer,info.activation_limit,2));
const cursor=new DataView(e.memory.buffer).getUint32(info.cursor_base,true)-info.activation_limit;
process.stdout.write(JSON.stringify({seen,count,prefix,cursor}));
'''
        with tempfile.TemporaryDirectory(dir=enums.ROOT/'build') as name:
            path=Path(name)/'reservation.goose';path.write_text(source)
            for level in (0,2):
                with self.subTest(level=level):
                    output=path.with_suffix('.wasm')
                    result=subprocess.run([str(enums.GOOSE),str(path),'--offline',f'-O{level}','--target','wasm-direct','-o',str(output)],capture_output=True,text=True)
                    self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                    actual=subprocess.run(['node','-e',host,str(output)],check=True,capture_output=True,text=True)
                    self.assertEqual(json.loads(actual.stdout),expected)
                    import wasmtime
                    engine=wasmtime.Engine();module=wasmtime.Module.from_file(engine,str(output));store=wasmtime.Store(engine);linker=wasmtime.Linker(engine)
                    info=enums.metadata(output.read_bytes());seen=[]
                    def probe(caller):
                        seen.append(caller.get('memory').read(caller,info['activation_limit'],info['activation_limit']+1)[0]);return 0
                    for item in module.imports:
                        if item.module=='env':linker.define_func(item.module,item.name,item.type,probe,access_caller=True)
                        else:linker.define_func(item.module,item.name,item.type,lambda *args:None)
                    instance=linker.instantiate(store,module);e=instance.exports(store);e['_start'](store);memory=e['memory'];base=info['activation_limit']
                    if memory.data_len(store)<=base:memory.grow(store,(base+1-memory.data_len(store)+65535)//65536)
                    memory.write(store,bytes([165]),base);count=str(e['tick'](store))
                    cursor=int.from_bytes(memory.read(store,info['cursor_base'],info['cursor_base']+4),'little')-base
                    self.assertEqual({'seen':seen,'count':count,'prefix':list(memory.read(store,base,base+2)),'cursor':cursor},expected)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--goose',type=Path,default=enums.GOOSE)
    args,remaining=parser.parse_known_args();enums.GOOSE=args.goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
