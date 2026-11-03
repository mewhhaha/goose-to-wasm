#!/usr/bin/env python3
"""Private u32 lane recurrences: tails, live aliases and ordered trap effects."""
import argparse
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve()
while not (ROOT / "tests/test_strip_loops.py").exists():
    ROOT = ROOT.parent
sys.path.insert(0, str(ROOT / "tests"))
from test_fill_loops import function_body
from test_static_data import uleb

GOOSE = ROOT / "build/bin/goose"
NODE = "node"
EXPECT_SIMD = True
TAIL = bytes(range(161, 185))
INITIAL = [0x102332FE, 0x55667788, 0x12345678, 0xF00DBABE,
           0x81234567, 0x76543210, 0xDEADBEEF, 0xFEEDABCD]


def source(width, variant, a=33, b=1025, shift=6):
    seeds = INITIAL[:width].copy()
    seeds[0] ^= 0x01010101
    prefix = ""
    update = ""
    body = f"hash=hash*{a}+(value as u32); hash=(hash*{b})^(hash>>{shift});"
    if variant == "shift_add":
        body = "hash=(hash<<5)+hash+value; hash=(hash+(hash<<10))^(hash>>6);"
    if variant == "divide":
        update = "hash+=((100/(i-2)) as! u32);"
    if variant == "overflow":
        update = "hash+=((seed+i) as! u32);"
    if variant == "ordinal":
        update = "hash+=(i as u32);"
    if variant == "early_store":
        update = "lanes[lane]=hash; hash+=1;"
    if variant == "call":
        update = "hash=observe(hash);"
    if variant == "alias_write":
        prefix = "let alias=lanes[..];"
        update = "alias[lane]=hash+1; hash=alias[lane];"
    if variant.startswith("cast_"):
        target = variant.removeprefix("cast_")
        update = f"hash=hash+(hash as! {target});"
        if target.startswith("i"):
            update = f"hash=hash+((hash as! {target}) as! u32);"
    if variant == "mixed_cast":
        update = "hash=hash+(((hash as! i8) as! i16) as! u32);"
    if variant == "bit_ops":
        update = "hash=((hash-0x12345678)&0xFFFF00FF)|0x00A00000; hash=(hash<<0)^(hash>>31); hash=hash*17+3; hash=(hash<<32)^(hash>>63);"
    return f'''extern fn prepared();
var saved:u8[:]; var backing:u8[4]=[17,34,51,68];
recursive fn observe(value:u32)->u32 {{ return value; }}
export fn tick(seed:i64)->u32 {{
    var lanes:u32[{width}]=[{','.join(hex(x) for x in seeds)}];
    lanes[0]^=0x01010101;
    {prefix}
    prepared();
    let xs=saved;
    for value,i in xs {{
        let lane=i%{width}; var hash=lanes[lane];
        {body} {update} lanes[lane]=hash;
    }}
    return lanes[0];
}}
fn main() {{ saved=backing[..]; }}
'''


def expected(width, scenario, variant, seed=0, a=33, b=1025, shift=6):
    image = bytearray(struct.pack("<"+"I"*width, *INITIAL[:width]))
    count = {"valid":23, "exact":width, "short":5, "empty":0, "group_trap":width+1,
             "tail_trap":width+1, "alias":width*2+1, "wrap":4}[scenario]
    available = {"valid":TAIL[-23:], "exact":TAIL[-width:], "short":TAIL[-5:], "empty":b"",
                 "group_trap":TAIL[-(width-1):], "tail_trap":TAIL[-width:], "wrap":b""}
    trapped = False
    for i in range(count):
        if scenario == "alias":
            value = image[i]
        elif i >= len(available[scenario]):
            trapped = True
            break
        else:
            value = available[scenario][i]
        at = i%width*4
        h = struct.unpack_from("<I", image, at)[0]
        h = (h*a+value)&0xFFFFFFFF
        h = ((h*b)&0xFFFFFFFF)^(h>>(shift&31))
        if variant.startswith("cast_") or variant == "mixed_cast":
            target = variant.removeprefix("cast_")
            if variant == "mixed_cast":
                target = "i8"
            bits = int(target[1:])
            narrowed = h&((1<<bits)-1)
            if target.startswith("i") and narrowed >= (1<<(bits-1)):
                narrowed -= 1<<bits
            h = (h+narrowed)&0xFFFFFFFF
        if variant == "bit_ops":
            h = (((h-0x12345678)&0xFFFFFFFF)&0xFFFF00FF)|0x00A00000
            h ^= h>>31
            h = (h*17+3)&0xFFFFFFFF
            h ^= h>>31
        if variant == "divide":
            if i == 2:
                trapped = True
                break
            h += 100//(i-2)
        if variant == "overflow":
            if seed+i > (1<<63)-1:
                trapped = True
                break
            h += seed+i
        if variant == "ordinal":
            h += i
        if variant in ("early_store", "alias_write"):
            h += 1
        struct.pack_into("<I", image, at, h&0xFFFFFFFF)
    return {"trapped":trapped, "lanes":list(struct.unpack("<"+"I"*width,image)), "tail":list(TAIL)}


NODE_HOST = r'''
const fs=require("node:fs");
const [file,scenario,width_,seed]=process.argv.slice(1), width=Number(width_);
const initial=INITIAL, tail=TAIL;
const module_=new WebAssembly.Module(fs.readFileSync(file));
let exports_,headerAt,laneAt;
const goose={};
for(const item of WebAssembly.Module.imports(module_)) if(item.module==="goose") goose[item.name]=()=>{};
const prepared=()=>{
    const bytes=Buffer.from(exports_.memory.buffer), pattern=Buffer.alloc(width*4);
    initial.slice(0,width).forEach((x,i)=>pattern.writeUInt32LE(x,i*4));
    laneAt=bytes.indexOf(pattern);
    if(laneAt<0 || bytes.indexOf(pattern,laneAt+1)>=0) throw Error("live lanes must be unique");
    const end=bytes.length;
    bytes.set(tail,end-tail.length);
    const cases={valid:[end-23,23],exact:[end-width,width],short:[end-5,5],empty:[end,0],group_trap:[end-width+1,width+1],
                 tail_trap:[end-width,width+1],alias:[laneAt,width*2+1],wrap:[0xfffffffe,4]};
    const [pointer,length]=cases[scenario];
    bytes.writeUInt32LE(pointer,headerAt); bytes.writeUInt32LE(length,headerAt+4);
};
exports_=new WebAssembly.Instance(module_,{goose,env:{prepared}}).exports;
exports_._start();
let bytes=Buffer.from(exports_.memory.buffer);
const backing=bytes.indexOf(Buffer.from([17,34,51,68])), header=Buffer.alloc(8);
if(backing<0) throw Error("missing backing sentinel");
header.writeUInt32LE(backing,0); header.writeUInt32LE(4,4);
headerAt=bytes.indexOf(header);
if(headerAt<0 || bytes.indexOf(header,headerAt+1)>=0) throw Error("slice header must be unique");
let trapped=false;
try { exports_.tick(BigInt(seed)); } catch(error) {
    if(!(error instanceof WebAssembly.RuntimeError)) throw error;
    trapped=true;
}
bytes=Buffer.from(exports_.memory.buffer);
process.stdout.write(JSON.stringify({trapped,lanes:Array.from({length:width},(_,i)=>bytes.readUInt32LE(laneAt+i*4)),
                                    tail:Array.from(bytes.subarray(bytes.length-tail.length))}));
'''.replace("INITIAL", json.dumps(INITIAL)).replace("TAIL", json.dumps(list(TAIL)))


def wasmtime_run(path, width, scenario, seed):
    import wasmtime
    engine = wasmtime.Engine()
    module = wasmtime.Module.from_file(engine, str(path))
    store = wasmtime.Store(engine)
    linker = wasmtime.Linker(engine)
    lane_at = header_at = None

    def prepared(caller):
        nonlocal lane_at
        memory = caller.get("memory")
        image = bytes(memory.read(caller))
        pattern = struct.pack("<"+"I"*width,*INITIAL[:width])
        lane_at = image.find(pattern)
        assert lane_at >= 0 and image.find(pattern,lane_at+1) < 0, "live lanes must be unique"
        end = len(image)
        cases = {"valid":(end-23,23), "exact":(end-width,width), "short":(end-5,5), "empty":(end,0),
                 "group_trap":(end-width+1,width+1), "tail_trap":(end-width,width+1),
                 "alias":(lane_at,width*2+1), "wrap":(0xFFFFFFFE,4)}
        memory.write(caller,TAIL,end-len(TAIL))
        memory.write(caller,struct.pack("<II",*cases[scenario]),header_at)

    for item in module.imports:
        if (item.module,item.name) == ("env","prepared"):
            linker.define_func(item.module,item.name,item.type,prepared,access_caller=True)
        else:
            assert item.module == "goose", (item.module,item.name)
            linker.define_func(item.module,item.name,item.type,lambda *args: None)
    exports = linker.instantiate(store,module).exports(store)
    exports["_start"](store)
    memory = exports["memory"]
    image = bytes(memory.read(store))
    backing = image.find(bytes([17,34,51,68]))
    assert backing >= 0
    header = struct.pack("<II",backing,4)
    header_at = image.find(header)
    assert header_at >= 0 and image.find(header,header_at+1) < 0
    trapped = False
    try:
        exports["tick"](store,seed)
    except wasmtime.Trap:
        trapped = True
    image = bytes(memory.read(store))
    return {"trapped":trapped,"lanes":list(struct.unpack_from("<"+"I"*width,image,lane_at)),"tail":list(image[-len(TAIL):])}


def simd_ops(body):
    """Decode boundaries; immediates must never count as SIMD instructions."""
    groups, offset = uleb(body,0)
    for _ in range(groups):
        _,offset = uleb(body,offset)
        offset += 1
    while offset < len(body):
        op = body[offset]
        offset += 1
        if op == 0xFD:
            sub,offset = uleb(body,offset)
            yield sub
            if sub in (0,0x5C):
                _,offset = uleb(body,offset)
                _,offset = uleb(body,offset)
            elif sub == 0x1B:
                offset += 1
            else:
                assert sub in (0x11,0x89,0xA9,0xAB,0xAD,0xAE,0xB1,0xB5,0x4E,0x50,0x51), hex(sub)
        elif op in (0x02,0x03,0x04,0x0C,0x0D,0x10,0x20,0x21,0x22,0x23,0x24,0x3F,0x40,0x41,0x42):
            _,offset = uleb(body,offset)
        elif op == 0x0E:
            count,offset = uleb(body,offset)
            for _ in range(count+1):
                _,offset = uleb(body,offset)
        elif op == 0x11 or 0x28 <= op <= 0x3E:
            _,offset = uleb(body,offset)
            _,offset = uleb(body,offset)
        elif op == 0x43:
            offset += 4
        elif op == 0x44:
            offset += 8
        elif op == 0xFC:
            sub,offset = uleb(body,offset)
            for _ in range({10:2,11:1}[sub]):
                _,offset = uleb(body,offset)
        else:
            assert op in (0,1,5,0x0B,0x0F,0x1A,0x1B) or 0x45 <= op <= 0xC4, hex(op)


class LaneWriteback(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT / "build")
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)

    def compile(self, width, level, variant="normal", debug=False, a=33, b=1025, shift=6):
        path = self.work / "main.goose"
        path.write_text(source(width,variant,a,b,shift))
        output = self.work / "program.wasm"
        stats = self.work / "stats.json"
        command = [str(GOOSE),str(path),"--offline","--target","wasm-direct",f"-O{level}",
                   "--wasm-stats",str(stats),"-o",str(output)]
        if debug:
            command.append("--debug")
        result = subprocess.run(command,capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        return output,json.loads(stats.read_text())

    def engines(self, path, width, scenario, seed=0):
        result = subprocess.run([NODE,"-e",NODE_HOST,str(path),scenario,str(width),str(seed)],
                                capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stderr)
        yield "v8",json.loads(result.stdout)
        yield "wasmtime",wasmtime_run(path,width,scenario,seed)

    def test_complete_lanes_tails_aliases_and_physical_bounds(self):
        for width in (4,8):
            for level in (0,2):
                for variant,a,b,shift in (("normal",33,1025,6),("normal",17,65537,13),("shift_add",33,1025,6)):
                    path,_ = self.compile(width,level,variant,a=a,b=b,shift=shift)
                    for scenario in ("valid","exact","short","empty","group_trap","tail_trap","alias","wrap"):
                        for engine,observed in self.engines(path,width,scenario):
                            with self.subTest(width=width,level=level,variant=variant,a=a,scenario=scenario,engine=engine):
                                self.assertEqual(observed,expected(width,scenario,variant,a=a,b=b,shift=shift))

    def test_ineligible_bodies_preserve_ordered_effects(self):
        cases = [("divide",False,0),("overflow",True,(1<<63)-2),("normal",True,0),
                 ("call",False,0),("alias_write",False,0),("ordinal",False,0),("early_store",False,0),
                 ("cast_u8",False,0),("cast_i8",False,0),("cast_u16",False,0),("cast_i16",False,0),("cast_i32",False,0),("mixed_cast",False,0)]
        for width in (4,8):
            for variant,debug,seed in cases:
                path,_ = self.compile(width,0,variant,debug)
                for scenario in ("valid","alias"):
                    for engine,observed in self.engines(path,width,scenario,seed):
                        with self.subTest(width=width,variant=variant,scenario=scenario,engine=engine):
                            self.assertEqual(observed,expected(width,scenario,variant,seed))

    def test_bit_operations_and_boundary_shifts(self):
        for width in (4,8):
            path,stats = self.compile(width,0,"bit_ops")
            ops = list(simd_ops(function_body(path,stats,"tick")))
            if EXPECT_SIMD:
                for op in (0xB1,0x4E,0x50,0xAB):
                    self.assertIn(op,ops)
            for scenario in ("exact","valid","alias"):
                for engine,observed in self.engines(path,width,scenario):
                    with self.subTest(width=width,scenario=scenario,engine=engine):
                        self.assertEqual(observed,expected(width,scenario,"bit_ops"))

    def test_generic_vector_emission_and_scalar_fallbacks(self):
        for width in (4,8):
            for a,b,shift in ((33,1025,6),(17,65537,13)):
                path,stats = self.compile(width,0,a=a,b=b,shift=shift)
                ops = list(simd_ops(function_body(path,stats,"tick")))
                if EXPECT_SIMD:
                    self.assertEqual(ops.count(0xB5),2*(width//4))
                    for op in (0x5C,0x89,0xA9,0xAD,0x51):
                        self.assertEqual(ops.count(op),width//4)
                else:
                    self.assertEqual(ops,[])
            for variant,debug in (("normal",True),("ordinal",False),("early_store",False),("divide",False),("alias_write",False),
                                  ("cast_u8",False),("cast_i8",False),("cast_u16",False),("cast_i16",False),("cast_i32",False),("mixed_cast",False)):
                path,stats = self.compile(width,0,variant,debug)
                self.assertEqual(list(simd_ops(function_body(path,stats,"tick"))),[])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose",type=Path,default=GOOSE)
    parser.add_argument("--node",default=NODE)
    parser.add_argument("--expect-simd",action=argparse.BooleanOptionalAction,default=True)
    args,remaining = parser.parse_known_args()
    GOOSE = args.goose.resolve()
    NODE = args.node
    EXPECT_SIMD = args.expect_simd
    unittest.main(argv=[sys.argv[0],*remaining])
