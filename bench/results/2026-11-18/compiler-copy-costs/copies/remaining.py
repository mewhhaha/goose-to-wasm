"""Extract native and post-change Wasmtime code for two remaining snapshots."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

import wasmtime
from disasm import disasm

p = argparse.ArgumentParser(description=__doc__)
for key in ('repo','named','native_stage','scratch','focus_check','after_emit'):
    p.add_argument(key, type=lambda x: Path(x).resolve())
a = p.parse_args()
sys.path.insert(0, str(a.repo/'scripts'))
from run_wasmtime import create_engine, create_hosted_config
def digest(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()

check, emit = (json.loads(file.read_text()) for file in (a.focus_check, a.after_emit))
assert check['compiler'] == emit['compiler']
assert check['named'] == emit['named'] and digest(a.named) == check['named']['sha256']
cfg = create_hosted_config()
cfg.cache = True
obj = a.scratch/'compiled.cwasm'
obj.write_bytes(wasmtime.Module(create_engine(cfg), a.named.read_bytes()).serialize())
assert digest(obj) == '2701f6835ab3e92f4084c41110d6128d0a116737100b18315975648880f01fe6'
native = a.native_stage/'build-1/compiler-native'
mapping = json.loads((a.native_stage/'build-1/build.json').read_text())
assert digest(native) == mapping['output_sha256']
# The direct native compiler is itself built by the repository wrapper;
# its frozen source and binary identities are in the stage build record.
stage = json.loads((a.native_stage/'builds.json').read_text())
assert stage['source_commit'] == emit['compiler']
assert stage['samples'][0]['artifacts']['compiler-native']['sha256'] == digest(native)
fn_ids = {r['name']:r['id'] for r in mapping['backend_stats']['function_names']}
# Use function-relative addresses for native since final linking changes the
# machine code base. Assert the opcodes displaying each individual field read.
def native_extract(name, expected, context_after=5):
    symbol = 'g_fn'+str(fn_ids[name])
    raw = subprocess.check_output(['llvm-objdump','--disassemble-symbols='+symbol,'--no-show-raw-insn',
                                   '--x86-asm-syntax=intel',native], text=True)
    lines = [(int(pc,16), op.strip()) for pc,op in re.findall(r'^\s*([0-9a-f]+):\s+(.+)$',raw,re.M)]
    result = []
    for pattern in expected:
        matches = [i for i,(_,op) in enumerate(lines) if re.fullmatch(pattern,op)]
        assert len(matches)==1, (symbol,pattern,matches)
        i=matches[0]
        result.extend(disasm(native,symbol,[(lines[i][0],lines[i+context_after][0])]))
    return result

def row(rows,function,offset=None):
    return [r for r in rows if r['kind']=='copy' and r['function']==function and (offset is None or r['offset']==offset)]
cg = row(emit['active'],'cg_function')
assert len(cg)==1 and cg[0]['size']==66
pair = row(check['active'],'life_contains',0xd30)
assert len(pair)==1 and pair[0]['size']==25
overlap = row(check['active'],'life_alt_overlaps')
assert {r['offset'] for r in overlap} == {0x195,0x1c5,0x1d7}
assert len({r['calls'] for r in overlap}) == 1
assert all(r['size']==27 for r in overlap)
report = {
    'compiler_commit':stage['source_commit'], 'native_sha256':digest(native), 'named_sha256':digest(a.named),
    'wasmtime_machine_code_sha256':digest(obj),
    'remaining':[
        {'function':'cg_function','mode':'emit','bytes_at_site':cg[0]['bytes'],'calls_at_site':cg[0]['calls'],
         'source':'selfhost/codegen.goose:349','wasm_offset':'0x118',
         'observation':'The function table scan snapshots 66 bytes before comparing one eight-byte symbol. The native loop reads the symbol directly.',
         'wasmtime':disasm(obj,'wasm[0]::function[919]::cg_function',[(0x76161c,0x7616b1)]),
         'native':native_extract('cg_function',[r'cmp\s+qword ptr \[rsi\], rcx'],5)},
        {'function':'life_alt_overlaps','mode':'check','bytes_at_sites':sum(r['bytes'] for r in overlap),
         'calls_per_site':overlap[0]['calls'], 'wasm_offsets':['0x195','0x1c5','0x1d7'],
         'source':'selfhost/checker_lifetimes.goose:2948',
         'observation':'The ordinary path snapshots the alternative and two arguments to the inlined alias test. '
                       'Clang reads next, root, exact and component directly on its ordinary path. '
                       'The two later Wasm argument copies for the class-alias call were never executed.',
         'wasmtime':disasm(obj,'wasm[0]::function[718]::life_alt_overlaps',[(0x53a170,0x53a2ae)]),
         'native':native_extract('life_alt_overlaps',[r'mov\s+r12d, dword ptr \[rax \+ 0x13\]'],9)},
        {'function':'life_contains','mode':'check','bytes_at_site':pair[0]['bytes'],'calls_at_site':pair[0]['calls'],
         'source':'selfhost/checker_lifetimes.goose:1010','wasm_offset':'0xd30',
         'observation':'The type-pair cache loop snapshots 25 bytes before comparing owner and pointee. Native reads fields directly, selecting next on a miss or answer after a match.',
         'wasmtime':disasm(obj,'wasm[0]::function[589]::life_contains',[(0x45fe41,0x45fec4)]),
         'native':native_extract('life_contains',[r'mov\s+rdi, qword ptr \[rcx \+ 0x11\]',r'cmp\s+qword ptr \[rcx\], r14'],6)},
        {'function':'life_eval_body and life_eval','mode':'check',
         'observation':'Largest combined volume. Value initialization, argument staging, and returning 72-byte LifeValue records all contribute. The compact-read example in lowering.json demonstrates that native can stage the same value twice; aggregate bytes alone cannot assign the time difference.',
         'bytes_by_function':{f:sum(r['bytes'] for r in row(check['active'],f)) for f in ('life_eval_body','life_eval')}}
    ]}
print(json.dumps(report,indent=2))
