#!/usr/bin/env python3
"""Inspect compact static-capacity metadata and packed element allocations."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from test_regions import metadata

ROOT=Path(__file__).resolve().parents[1]
GOOSE=ROOT/'build/bin/goose'
NODE_HOST=r'''
const fs=require("node:fs");
const [path,width,count,change]=process.argv.slice(1);
const module=new WebAssembly.Module(fs.readFileSync(path));
const info=JSON.parse(new TextDecoder().decode(WebAssembly.Module.customSections(module,"goose.regions")[0]));
const imports={goose:{}};
for(const item of WebAssembly.Module.imports(module)) imports.goose[item.name]=()=>{};
const instance=new WebAssembly.Instance(module,imports);instance.exports._start();
const view=new DataView(instance.exports.memory.buffer),base=info.activation_limit;
const result={image:Array.from(new Uint8Array(view.buffer,base,Number(count))),before:instance.exports.count().toString(),cursor:view.getUint32(info.cursor_base,true)-base};
new Uint8Array(view.buffer,base,Number(width)).fill(0);new Uint8Array(view.buffer)[base]=Number(change);
result.after=instance.exports.count().toString();process.stdout.write(JSON.stringify(result));
'''


class StaticLimitedImages(unittest.TestCase):
    def compile(self,work,source,level,target='wasm-direct'):
        path=work/'main.goose';path.write_text(source)
        output=work/('main.c' if target=='native' else 'main.wasm');output.unlink(missing_ok=True)
        command=[str(GOOSE),str(path),'--offline',f'-O{level}','--target',target,'-o',str(output)]
        if target=='native':command.append('--standalone')
        result=subprocess.run(command,capture_output=True,text=True)
        return result,output

    def check(self,capacity,element,elements,data,element_size,extra=''):
        width=1 if capacity<=255 else 2 if capacity<=65535 else 4
        length=len(elements);change=0 if length==1 else 1
        source=f'''{extra}
var rows:{element}[..{capacity}][>..]=[[{','.join(elements)}]];
export fn count()->i64{{rows[0].len}} fn main(){{}}'''
        expected={'image':list(length.to_bytes(width,'little')+bytes.fromhex(data)),
                  'before':str(length),'after':str(change),'cursor':width+capacity*element_size}
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as name:
            for level in (0,2):
                with self.subTest(capacity=capacity,element=element,level=level):
                    compiled,path=self.compile(Path(name),source,level)
                    self.assertEqual(compiled.returncode,0,compiled.stdout+compiled.stderr)
                    result=subprocess.run(['node','-e',NODE_HOST,str(path),str(width),str(len(expected['image'])),str(change)],check=True,capture_output=True,text=True)
                    self.assertEqual(json.loads(result.stdout),expected)
                    import wasmtime
                    engine=wasmtime.Engine();module=wasmtime.Module.from_file(engine,str(path));store=wasmtime.Store(engine);linker=wasmtime.Linker(engine)
                    for item in module.imports:linker.define_func(item.module,item.name,item.type,lambda *args:None)
                    instance=linker.instantiate(store,module);exports=instance.exports(store);exports['_start'](store)
                    memory=exports['memory'];info=metadata(path.read_bytes());base=info['activation_limit']
                    observed={'image':list(memory.read(store,base,base+len(expected['image']))),'before':str(exports['count'](store)),
                              'cursor':int.from_bytes(memory.read(store,info['cursor_base'],info['cursor_base']+4),'little')-base}
                    memory.write(store,change.to_bytes(width,'little'),base)
                    observed['after']=str(exports['count'](store));self.assertEqual(observed,expected)

    def test_unsigned_width_boundaries(self):
        for capacity in (255,256,65535,65536):
            self.check(capacity,'u8',['0x11','0x22'],'1122',1)

    def test_unaligned_u64_element_starts_after_one_byte(self):
        self.check(1,'u64',['0x1122334455667788'],'8877665544332211',8)

    def test_three_byte_record_capacity_has_no_trailing_padding(self):
        self.check(256,'Cell',['Cell{0x11,0x2233}','Cell{0x44,0x5566}'],'113322446655',3,'struct Cell{tag:u8,value:u16}')

    def test_zero_capacity_standalone_value_allocates_its_c_placeholder(self):
        source='''var before:u8[8]="__zero_A";
var empty:u64[..0];
var after:u8[8]="__zero_B";
export fn count()->i64{empty.len+empty.cap} fn main(){print(before[0],after[0]);}'''
        host=r'''const fs=require("node:fs");const module=new WebAssembly.Module(fs.readFileSync(process.argv[1]));const imports={goose:{}};for(const i of WebAssembly.Module.imports(module))imports.goose[i.name]=()=>{};const instance=new WebAssembly.Instance(module,imports);instance.exports._start();const bytes=Buffer.from(instance.exports.memory.buffer);const marker=Buffer.concat([Buffer.from("__zero_A"),Buffer.alloc(9),Buffer.from("__zero_B")]);process.stdout.write(JSON.stringify({found:bytes.indexOf(marker)>=0,count:instance.exports.count().toString()}));'''
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as name:
            for level in (0,2):
                compiled,path=self.compile(Path(name),source,level)
                self.assertEqual(compiled.returncode,0,compiled.stdout+compiled.stderr)
                result=subprocess.run(['node','-e',host,str(path)],check=True,capture_output=True,text=True)
                self.assertEqual(json.loads(result.stdout),{'found':True,'count':'0'})
                import wasmtime
                engine=wasmtime.Engine();module=wasmtime.Module.from_file(engine,str(path));store=wasmtime.Store(engine);linker=wasmtime.Linker(engine)
                for item in module.imports:linker.define_func(item.module,item.name,item.type,lambda *args:None)
                instance=linker.instantiate(store,module);exports=instance.exports(store);exports['_start'](store)
                self.assertIn(b'__zero_A'+bytes(9)+b'__zero_B',bytes(exports['memory'].read(store)))
                self.assertEqual(exports['count'](store),0)

    def test_zero_capacity_fields_and_elements_remain_frontend_invalid(self):
        sources=('struct Box{value:u64[..0]} fn main(){let b=Box{[]};print(b.value.len);}',
                 'fn main(){var rows:u64[..0][2];print(rows.len);}')
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as name:
            for source in sources:
                for level in (0,2):
                    for target in ('native','wasm-direct'):
                        compiled,path=self.compile(Path(name),source,level,target)
                        self.assertNotEqual(compiled.returncode,0)
                        self.assertFalse(path.exists())


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--goose',type=Path,default=GOOSE)
    args,remaining=parser.parse_known_args();GOOSE=args.goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
