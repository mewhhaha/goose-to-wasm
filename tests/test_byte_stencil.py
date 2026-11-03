#!/usr/bin/env python3
"""Qualify guarded byte stencils against ordered scalar torus updates."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import unittest

import test_strip_loops as strip
from test_fill_loops import function_body

HELPER='''fn nearby(g:u8[:],w:i64,h:i64,x:i64,y:i64)->i64 {
    var n=0;
    for dy in -1..2 { for dx in -1..2 {
        if dx==0 && dy==0 { continue; }
        let nx=(x+dx)%w; let ny=(y+dy)%h;
        n+=g[ny*w+nx];
    }}
    return n;
}
'''
SOURCE=HELPER+'''var incoming:u8[:]; var outgoing:u8[:];
var first:u8[4]=[17,34,51,68]; var second:u8[4]=[81,82,83,84];
export fn evolve(w:i64,h:i64) {
    let src=incoming; let dst=outgoing;
    for y in h { for x in w {
        let n=nearby(src,w,h,x,y);
        let alive=src[y*w+x]==1;
        dst[y*w+x]=if n==3 || (alive && n==2) {1} else {0};
    }}
}
fn main() { incoming=first[..]; outgoing=second[..]; }
'''


def scenarios():
    cases=[]
    for w in (0,1,2,7,8,9,17,18,63,64,65):
        for h in (0,1,2,3,32):
            for pattern in (0,1,2):
                cases.append(dict(w=w,h=h,pattern=pattern,src=4096,dst=8192,ns=w*h,nd=w*h))
    for src,dst in ((4096,4096),(4096,4097),(4097,4096),(4097,8193)):
        for pattern in (0,1,2):
            cases.append(dict(w=18,h=3,pattern=pattern,src=src,dst=dst,ns=54,nd=54))
    for changes in (dict(ns=8),dict(nd=8),dict(src=-16),dict(dst=-16),
                    dict(src=0xfffffff8),dict(dst=0xfffffff8),dict(w=-1),dict(h=-1),
                    dict(w=1<<32),dict(h=1<<32),dict(w=(1<<63)-1)):
        case=dict(w=18,h=3,pattern=2,src=4096,dst=8192,ns=54,nd=54)
        case.update(changes);cases.append(case)
    return cases


HOST=r'''
const fs=require('node:fs'),mod=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
const cases=JSON.parse(process.argv[2]),goose={};
for(const i of WebAssembly.Module.imports(mod))goose[i.name]=()=>{};
const result=cases.map(c=>{
    const e=new WebAssembly.Instance(mod,{goose}).exports;e._start();
    const bytes=new Uint8Array(e.memory.buffer),size=bytes.length;
    const headerFor=values=>{
        const base=Buffer.from(bytes).indexOf(Buffer.from(values));if(base<0)throw new Error('missing backing');
        const header=Buffer.alloc(8);header.writeUInt32LE(base);header.writeUInt32LE(4,4);
        const at=Buffer.from(bytes).indexOf(header);if(at<0)throw new Error('missing header');return at;
    };
    const sourceHeader=headerFor([17,34,51,68]),destHeader=headerFor([81,82,83,84]);
    for(const at of [0,4096,8192,size-128])for(let i=at;i<Math.min(size,at+2176);i++)bytes[i]=(i*37+17)&255;
    const base=p=>{if(p<0)return size+p;return p;};
    const src=base(c.src),dst=base(c.dst);
    for(let i=0;i<Math.min(c.ns,4096)&&src+i<size;i++) {
        if(src+i<0)continue;
        if(c.pattern===0)bytes[src+i]=Number((i*13+7)%5===0);
        if(c.pattern===1)bytes[src+i]=(i*37+255)&255;
        if(c.pattern===2)bytes[src+i]=Number((i*13+7)%3===0)*2;
    }
    let trapped=false;
    const image=Buffer.from(bytes.buffer);image.writeUInt32LE(src>>>0,sourceHeader);image.writeUInt32LE(c.ns,sourceHeader+4);
    image.writeUInt32LE(dst>>>0,destHeader);image.writeUInt32LE(c.nd,destHeader+4);
    try{e.evolve(BigInt(c.w),BigInt(c.h));}
    catch(error){if(!(error instanceof WebAssembly.RuntimeError))throw error;trapped=true;}
    return {trapped,size,src,dst,sourceHeader,destHeader,windows:[0,4096,8192,size-128].map(at=>[at,Array.from(bytes.subarray(at,Math.min(size,at+2176)))])};
});process.stdout.write(JSON.stringify(result));
'''


def initial_image(size):
    image=bytearray(size)
    for at in (0,4096,8192,size-128):
        image[at:min(size,at+2176)]=bytes((i*37+17)&255 for i in range(at,min(size,at+2176)))
    return image


def expected(case,observed,rule=0):
    size=observed['size'];image=initial_image(size);w=case['w'];h=case['h']
    src=observed['src'];dst=observed['dst'];trapped=False
    for i in range(min(case['ns'],4096)):
        if not 0<=src+i<size:continue
        if case['pattern']==0:image[src+i]=int((i*13+7)%5==0)
        if case['pattern']==1:image[src+i]=(i*37+255)&255
        if case['pattern']==2:image[src+i]=int((i*13+7)%3==0)*2
    def read(index):
        if not 0<=index<case['ns']:raise IndexError()
        address=(src+index)&0xffffffff
        if address>=size:raise IndexError()
        return image[address]
    import struct
    struct.pack_into('<II',image,observed['sourceHeader'],src&0xffffffff,case['ns'])
    struct.pack_into('<II',image,observed['destHeader'],dst&0xffffffff,case['nd'])
    try:
        for y in range(max(0,h)):
            for x in range(max(0,w)):
                n=0
                for dy in (-1,0,1):
                    for dx in (-1,0,1):
                        if dx==0 and dy==0:continue
                        n+=read(((y+dy)%h)*w+(x+dx)%w)
                alive=read(y*w+x)==1
                value=int(n==3 or (alive and n==2))
                if rule:
                    value=19
                    if n>=256 or (not alive and n!=2):value=7
                index=y*w+x
                if index>=case['nd']:raise IndexError()
                address=(dst+index)&0xffffffff
                if address>=size:raise IndexError()
                image[address]=value
    except IndexError:trapped=True
    return trapped,[[at,list(image[at:at+len(values)])]for at,values in observed['windows']]


def wasmtime_run(path,cases):
    import wasmtime
    engine=wasmtime.Engine();module=wasmtime.Module.from_file(engine,str(path));results=[]
    for case in cases:
        store=wasmtime.Store(engine);linker=wasmtime.Linker(engine)
        for item in module.imports:linker.define_func(item.module,item.name,item.type,lambda *args:None)
        e=linker.instantiate(store,module).exports(store);e['_start'](store);memory=e['memory'];size=memory.data_len(store)
        import struct
        initial=bytes(memory.read(store))
        def header_for(values):
            base=initial.index(bytes(values));return initial.index(struct.pack('<II',base,4))
        source_header=header_for([17,34,51,68]);dest_header=header_for([81,82,83,84])
        image=initial_image(size)
        src=case['src'];dst=case['dst']
        if src<0:src+=size
        if dst<0:dst+=size
        for i in range(min(case['ns'],4096)):
            if not 0<=src+i<size:continue
            if case['pattern']==0:image[src+i]=int((i*13+7)%5==0)
            if case['pattern']==1:image[src+i]=(i*37+255)&255
            if case['pattern']==2:image[src+i]=int((i*13+7)%3==0)*2
        struct.pack_into('<II',image,source_header,src&0xffffffff,case['ns'])
        struct.pack_into('<II',image,dest_header,dst&0xffffffff,case['nd'])
        memory.write(store,image);trapped=False
        try:e['evolve'](store,case['w'],case['h'])
        except wasmtime.Trap:trapped=True
        image=bytes(memory.read(store))
        windows=[[at,list(image[at:min(size,at+2176)])]for at in (0,4096,8192,size-128)]
        results.append(dict(trapped=trapped,size=size,src=src,dst=dst,sourceHeader=source_header,destHeader=dest_header,windows=windows))
    return results


class ByteStencil(unittest.TestCase):
    setUp=strip.StripLoops.setUp
    compile=strip.StripLoops.compile

    def run_cases(self,path,cases,rule=0):
        node_cases=[dict(case,w=str(case['w']),h=str(case['h']))for case in cases]
        run=subprocess.run([strip.NODE,'-e',HOST,str(path),json.dumps(node_cases)],capture_output=True,text=True,timeout=60)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        for engine,results in (('v8',json.loads(run.stdout)),('wasmtime',wasmtime_run(path,cases))):
            for case,result in zip(cases,results,strict=True):
                with self.subTest(engine=engine,case=case):
                    trapped,image=expected(case,result,rule)
                    self.assertEqual((result['trapped'],result['windows']),(trapped,image))

    def test_generic_helper_stencils_and_scalar_fallbacks(self):
        for level in (0,2):
            for debug in (False,True):
                path,stats=self.compile(level,text=SOURCE,debug=debug)
                body=function_body(path,stats,'evolve')
                if debug:self.assertNotIn(b'\xfd\x02\x00\x00',body)
                else:
                    self.assertIn(b'\xfd\x02\x00\x00',body)  # unsigned eight-byte widening load
                    self.assertIn(b'\xfd\x8e\x01',body)      # exact word-lane addition
                    self.assertIn(b'\xfd\x66',body)          # unsigned narrowing
                self.run_cases(path,scenarios())

    def test_renamed_rule_uses_arbitrary_bytes_without_saturation(self):
        source=SOURCE.replace('nearby','around').replace('n==3 || (alive && n==2) {1} else {0}',
                                                        'n>=256 || (!alive && n!=2) {7} else {19}')
        for level in (0,2):
            path,stats=self.compile(level,text=source)
            self.assertIn(b'\xfd\x02\x00\x00',function_body(path,stats,'evolve'))
            self.run_cases(path,scenarios(),rule=1)

    def test_inline_helper_and_unchanged_life_example_emit_vectors(self):
        for level in (0,2):
            path,stats=self.compile(level,text=SOURCE.replace('fn nearby','inline fn nearby'))
            self.assertIn(b'\xfd\x02\x00\x00',function_body(path,stats,'evolve'))
            cases=[dict(w=64,h=32,pattern=0,src=4096,dst=8192,ns=2048,nd=2048),
                   dict(w=17,h=2,pattern=1,src=4096,dst=4097,ns=34,nd=34)]
            self.run_cases(path,cases)
            source=(strip.ROOT/'examples/life.goose').read_text()
            path,stats=self.compile(level,text=source)
            bodies=[function_body(path,stats,item['name'].split('#')[0])for item in stats['function_info']
                    if item['name'].split('#')[0] in ('main','step')]
            self.assertTrue(any(b'\xfd\x02\x00\x00'in body for body in bodies))

    def test_extra_effects_and_unproved_arithmetic_keep_scalar(self):
        for source in (SOURCE.replace('let n=nearby','var extra=1/(x-2); let n=nearby'),
                       'extern fn side();\n'+SOURCE.replace('let n=nearby','side(); let n=nearby'),
                       'var pool:u8[>..]=[0];\n'+SOURCE.replace('let n=nearby',
                                                                         'let checked=x as (u32 in pool); let n=nearby'),
                       SOURCE.replace('x:i64,y:i64','x:i32,y:i64').replace('nearby(src,w,h,x,y)',
                                                                                 'nearby(src,w,h,x as i32,y)'),
                       SOURCE.replace('let alive=src[y*w+x]==1;',
                                      'var alive=src[y*w+x]==1;'+'alive=alive&&alive;'*10),
                       SOURCE.replace('let alive=', 'dst[y*w+x]=99; let alive='),
                       SOURCE.replace('n+=g[ny*w+nx];','n+=g[ny*w+nx]; n+=9223372036854775807;')):
            for level in (0,2):
                path,stats=self.compile(level,text=source)
                self.assertNotIn(b'\xfd\x02\x00\x00',function_body(path,stats,'evolve'))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--goose',type=Path,default=strip.GOOSE)
    parser.add_argument('--node',default=strip.NODE)
    args,remaining=parser.parse_known_args();strip.GOOSE=args.goose.resolve();strip.NODE=args.node
    unittest.main(argv=[sys.argv[0],*remaining])
