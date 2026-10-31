#!/usr/bin/env python3
"""Inspect fixed alignment pads and explicit-only variable prefix pads."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import test_enum_images as enums
import test_record_images as records


class RecordPadding(unittest.TestCase):
    def test_fixed_copy_preserves_host_modified_padding(self):
        source='''struct P{pad 1,a:u8,pad,pad 2,b:u32,pad 3}
var rows:P[>..]=[P{0x11,0x22334455},P{0,0}];
export fn clone(){rows[1]=rows[0];}
fn main(){}'''
        original=bytes.fromhex('a111a2a3a4a555443322a6a7a8')
        host=r'''
const fs=require('node:fs');
const m=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
const info=JSON.parse(new TextDecoder().decode(WebAssembly.Module.customSections(m,'goose.regions')[0]));
const imports={goose:{}};for(const x of WebAssembly.Module.imports(m))imports.goose[x.name]=()=>{};
const e=new WebAssembly.Instance(m,imports).exports;e._start();
const memory=new Uint8Array(e.memory.buffer),base=info.activation_limit;
memory.set(Buffer.from(process.argv[2],'hex'),base);e.clone();
process.stdout.write(Buffer.from(memory.slice(base+13,base+26)).toString('hex'));
'''
        with tempfile.TemporaryDirectory(dir=enums.ROOT/'build') as name:
            path=Path(name)/'copy.goose';path.write_text(source)
            for level in (0,2):
                with self.subTest(level=level):
                    output=path.with_suffix('.wasm')
                    result=subprocess.run([str(enums.GOOSE),str(path),'--offline',f'-O{level}','--target','wasm-direct','-o',str(output)],capture_output=True,text=True)
                    self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                    actual=subprocess.run(['node','-e',host,str(output),original.hex()],check=True,capture_output=True,text=True)
                    self.assertEqual(actual.stdout,original.hex())
                    import wasmtime
                    engine=wasmtime.Engine();module=wasmtime.Module.from_file(engine,str(output));store=wasmtime.Store(engine);linker=wasmtime.Linker(engine)
                    for item in module.imports:linker.define_func(item.module,item.name,item.type,lambda *args:None)
                    instance=linker.instantiate(store,module);exports=instance.exports(store);exports['_start'](store)
                    memory=exports['memory'];base=enums.metadata(output.read_bytes())['activation_limit']
                    memory.write(store,original,base);exports['clone'](store)
                    self.assertEqual(bytes(memory.read(store,base+13,base+26)),original)

    def test_fixed_leading_bare_consecutive_and_trailing_pads(self):
        checker=enums.EnumImages('test_fixed_payload_image_has_only_active_bytes')
        checker.check_bytes('struct P{pad 1,a:u8,pad,pad 2,b:u32,pad 3} var rows:P[>..]=[P{0x11,0x22334455}];',
                            '00110000000055443322000000')

    def test_empty_and_pad_only_enum_payload_sizes(self):
        checker=enums.EnumImages('test_empty_image_reserves_no_inactive_payload')
        for variant,expected in [('None','00'),('Zero','01'),('Bytes','02000000')]:
            with self.subTest(variant=variant):
                checker.check_bytes(f'enum E{{None{{pad}},Zero{{pad 0}},Bytes{{pad 3}}}} var e:E..=E.{variant}{{}};',expected)

    def test_variable_prefix_pads_do_not_align_the_next_scalar(self):
        checker=records.RecordImages('test_global_record_prefix_and_tail_are_contiguous')
        checker.check_image('struct R{tag:u8,pad 3,word:u16,pad,values:u8[u8]} var r=R{0x11,0x2233,[0x44,0x55]};',
                            'r','110000003322024455',4,6)

    def test_variable_enum_payload_retains_padded_prefix_views(self):
        checker=records.RecordImages('test_global_record_prefix_and_tail_are_contiguous')
        checker.check_image('struct R{tag:u8,pad 2,word:u16,pad,values:u8[u8]} enum E{Data{tag:u8,pad 2,word:u16,pad,values:u8[u8]},Empty} var e:E..=E.Data{0x11,0x2233,[0x44,0x55]}; var payload:const E.Data& =match e{Data &p=>p,_=>abort("bad")};',
                            'payload','001100003322024455',4,6)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--goose',type=Path,default=enums.GOOSE)
    args,remaining=parser.parse_known_args();enums.GOOSE=args.goose.resolve();records.GOOSE=enums.GOOSE
    unittest.main(argv=[sys.argv[0],*remaining])
