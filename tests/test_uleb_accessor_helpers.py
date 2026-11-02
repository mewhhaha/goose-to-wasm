#!/usr/bin/env python3
"""Keep dynamic control-header dispatch and cold ULEB diagnostics intact."""
import argparse
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

from test_regions import metadata

ROOT = Path(__file__).resolve().parents[1]
GOOSE = ROOT / "build/bin/goose"
NODE = "node"
SOURCE = '''var rows:u8[>..]=[17,34,51];
export fn count()->i64 { rows.len }
export fn first()->u8 { rows[0] }
export fn clear() { rows.clear(); }
export fn resize() { rows.resize(6,0); }
fn main() {}
'''
NODE_HOST = r'''
const fs=require("node:fs");
const [file,input]=process.argv.slice(1),test=JSON.parse(input);
const module_=new WebAssembly.Module(fs.readFileSync(file));
const info=JSON.parse(new TextDecoder().decode(WebAssembly.Module.customSections(module_,"goose.regions")[0]));
let exports_;
const goose={};
for(const item of WebAssembly.Module.imports(module_)) goose[item.name]=()=>{};
goose.abort=(pointer,length)=>{throw new Error(new TextDecoder().decode(new Uint8Array(exports_.memory.buffer,pointer>>>0,length>>>0)));};
exports_=new WebAssembly.Instance(module_,{goose}).exports;exports_._start();
const bytes=new Uint8Array(exports_.memory.buffer),view=new DataView(bytes.buffer);
const controls=[];
for(let at=0;at+24<=info.activation_base;at+=4) {
  if(view.getUint32(at,true)===info.activation_limit && view.getUint32(at+4,true)===3 &&
     view.getUint32(at+8,true)===info.activation_limit+info.region_bytes && view.getUint32(at+20,true)===0) controls.push(at);
}
if(controls.length!==1) throw new Error("expected one static Grow control");
const header=controls[0];
let image=bytes.length-64;
if(test.alias_mode) image=header+20;
bytes.set(test.image,image);
const words=[image+test.prefix,99,image+test.limit,test.width,image,test.mode];
if(test.keep_region_limit) words[2]=info.activation_limit+info.region_bytes;
if(test.mode===0 || test.mode>6) words[1]=3;
words.forEach((word,index)=>view.setUint32(header+index*4,word,true));
let count=null,first=null,error="";
try {
  if(test.resize) exports_.resize();
  else if(test.clear) exports_.clear();
  else {count=exports_.count().toString();first=exports_.first();}
} catch(failure) {error=String(failure.message);}
const result={count,first,error,stored_count:view.getUint32(header+4,true),image:Array.from(bytes.slice(image,image+test.image.length))};
if(test.resize) result.mode=view.getUint32(header+20,true);
process.stdout.write(JSON.stringify(result));
'''


def wasmtime_run(path, test):
    import wasmtime
    engine=wasmtime.Engine();module=wasmtime.Module.from_file(engine,str(path))
    store=wasmtime.Store(engine);linker=wasmtime.Linker(engine)

    def abort(caller,pointer,length,line):
        memory=caller.get("memory")
        raise wasmtime.Trap(bytes(memory.read(caller,pointer,pointer+length)).decode())

    for item in module.imports:
        if item.name=="abort":
            linker.define_func(item.module,item.name,item.type,abort,access_caller=True)
        else:
            linker.define_func(item.module,item.name,item.type,lambda *args:None)
    exports=linker.instantiate(store,module).exports(store);exports["_start"](store)
    memory=exports["memory"];end=memory.data_len(store);image=end-64
    info=metadata(path.read_bytes());static=bytes(memory.read(store,0,info["activation_base"]))
    controls=[]
    for at in range(0,len(static)-23,4):
        base,count,limit,_,_,mode=struct.unpack_from("<IIIIII",static,at)
        if base==info["activation_limit"] and count==3 and limit==base+info["region_bytes"] and mode==0:
            controls.append(at)
    assert len(controls)==1,"expected one static Grow control"
    header=controls[0]
    if test.get("alias_mode"):
        image=header+20
    count=99
    if test["mode"]==0 or test["mode"]>6:
        count=3
    memory.write(store,bytes(test["image"]),image)
    limit=image+test["limit"]
    if test.get("keep_region_limit"):
        limit=info["activation_limit"]+info["region_bytes"]
    memory.write(store,struct.pack("<IIIIII",image+test["prefix"],count,limit,
                                  test["width"],image,test["mode"]),header)
    observed={"count":None,"first":None,"error":""}
    try:
        if test.get("resize"):
            exports["resize"](store)
        elif test.get("clear"):
            exports["clear"](store)
        else:
            observed["count"]=str(exports["count"](store))
            observed["first"]=exports["first"](store)
    except wasmtime.Trap as failure:
        observed["error"]=str(failure)
    observed["stored_count"]=int.from_bytes(memory.read(store,header+4,header+8),"little")
    observed["image"]=list(memory.read(store,image,image+len(test["image"])))
    if test.get("resize"):
        observed["mode"]=int.from_bytes(memory.read(store,header+20,header+24),"little")
    return observed


class ULEBAccessorHelpers(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(dir=ROOT/"build")
        self.addCleanup(self.tmp.cleanup)
        self.work=Path(self.tmp.name)

    def compile(self,level):
        source=self.work/"main.goose";source.write_text(SOURCE)
        output=self.work/"program.wasm"
        result=subprocess.run([str(GOOSE),str(source),"--offline",f"-O{level}","--target","wasm-direct",
                               "-o",str(output)],capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        return output

    def engines(self,path,test):
        result=subprocess.run([NODE,"-e",NODE_HOST,str(path),json.dumps(test)],
                              capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stderr)
        yield "v8",json.loads(result.stdout)
        yield "wasmtime",wasmtime_run(path,test)

    def test_forged_grow_header_keeps_all_physical_modes_authoritative(self):
        images=[(0,b"\x11\x22\x33",0),(1,b"\x03\x11\x22\x33",1),
                (2,struct.pack("<H",3)+b"\x11\x22\x33",2),
                (3,struct.pack("<I",3)+b"\x11\x22\x33",4),
                (4,struct.pack("<Q",3)+b"\x11\x22\x33",8),
                (5,struct.pack("<II",3,3)+b"\x11\x22\x33",8),
                (6,b"\x83\x00\x11\x22\x33",2),
                (7,b"\x11\x22\x33",0),(0xFFFFFFFF,b"\x11\x22\x33",0)]
        for level in (0,2):
            path=self.compile(level)
            for mode,image,prefix in images:
                test={"mode":mode,"image":list(image),"prefix":prefix,"width":prefix,"limit":len(image)}
                stored=99
                if mode==0 or mode>6:
                    stored=3
                expected={"count":"3","first":17,"error":"","stored_count":stored,"image":list(image)}
                for engine,observed in self.engines(path,test):
                    with self.subTest(level=level,mode=mode,engine=engine):
                        self.assertEqual(observed,expected)

    def test_length_failures_keep_diagnostics_and_pretrap_length_store(self):
        cases=[(6,[128],1,1,False,"truncated varint image"),
               (6,[255]*9+[2],10,10,False,"varint image exceeds 64 bits"),
               (6,[128,128,128,128,16],5,5,False,"array image length exceeds wasm32 range"),
               (4,list(struct.pack("<Q",1<<32)),8,8,False,"array image length exceeds wasm32 range"),
               (6,[3,17,34,51],4,0,True,"invalid ULEB construction prefix"),
               (6,[3,17,34,51],4,11,True,"invalid ULEB construction prefix")]
        for level in (0,2):
            path=self.compile(level)
            for mode,image,limit,width,clear,diagnostic in cases:
                prefix=1
                if mode==4:
                    prefix=8
                test={"mode":mode,"image":image,"prefix":prefix,"width":width,"limit":limit,"clear":clear}
                stored=99
                if clear:
                    stored=0
                for engine,observed in self.engines(path,test):
                    with self.subTest(level=level,mode=mode,diagnostic=diagnostic,width=width,engine=engine):
                        self.assertIn(diagnostic,observed["error"])
                        self.assertEqual(observed["count"],None)
                        self.assertEqual(observed["first"],None)
                        self.assertEqual(observed["stored_count"],stored)
                        self.assertEqual(observed["image"],image)

    def test_writes_keep_unknown_modes_and_capture_mode_before_aliasing_store(self):
        cases=[]
        for mode in (7,0xFFFFFFFF):
            test={"mode":mode,"image":[17,34,51],"prefix":0,"width":0,"limit":3,"clear":True}
            expected={"count":None,"first":None,"error":"","stored_count":0,"image":[17,34,51]}
            cases.append((test,expected))
        # The VarU8 length byte aliases the mode word. Its final write turns
        # mode 1 into mode 6; the captured mode must prevent a ULEB patch.
        # Width zero is ignored by VarU8 but would trap in that wrong patch.
        # Keep the real owner limit so resize uses its existing cursor slot.
        test={"mode":1,"image":[1,0,0,0,17,34,51],"prefix":1,"width":0,"limit":7,
              "alias_mode":True,"resize":True,"keep_region_limit":True}
        expected={"count":None,"first":None,"error":"","stored_count":6,
                  "image":[6,0,0,0,17,34,51],"mode":6}
        cases.append((test,expected))
        for level in (0,2):
            path=self.compile(level)
            for test,expected in cases:
                for engine,observed in self.engines(path,test):
                    with self.subTest(level=level,mode=test["mode"],alias_mode=test.get("alias_mode",False),engine=engine):
                        self.assertEqual(observed,expected)


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose",type=Path,default=GOOSE)
    parser.add_argument("--node",default=NODE)
    args,remaining=parser.parse_known_args()
    GOOSE=args.goose.resolve();NODE=args.node
    unittest.main(argv=[sys.argv[0],*remaining])
