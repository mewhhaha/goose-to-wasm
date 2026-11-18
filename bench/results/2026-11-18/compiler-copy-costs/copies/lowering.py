"""Recreate pinned x86 excerpts from the uninstrumented compiler and Wasmtime module."""
import argparse
from pathlib import Path
import hashlib
import json
import subprocess
import sys

import wasmtime

p = argparse.ArgumentParser(description=__doc__)
for field in ('repo', 'native', 'named', 'scratch'):
    p.add_argument(field, type=lambda x: Path(x).resolve())
a = p.parse_args()
sys.path.insert(0, str(a.repo/'scripts'))
from run_wasmtime import create_engine, create_hosted_config

def identity(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()

profile = json.loads((a.repo/'bench/results/2026-11-18/compiler-replay-and-captures/profile.json').read_text())
assert identity(a.native) == profile['native']['sha256']
assert identity(a.named) == profile['named']['sha256']
cfg = create_hosted_config()
cfg.cache = True
obj = a.scratch/'compiled.cwasm'
obj.write_bytes(wasmtime.Module(create_engine(cfg), a.named.read_bytes()).serialize())
assert identity(obj) == 'ebd941e1ed84b8e28c031c30650bf63f3ba721b4caf9ad9b178c8b3ba26150ee', 'different machine code'
from disasm import disasm

sites = [
    ('compact_read', 'life_replay', 817, 168406,
     [(0x6426c7,0x642844)], [(0x1ca8f8,0x1ca98c)],
     'The compact-read slow path loads a 72-byte LifeValue from the leaf and stages a by-value call. '
     'Both targets copy twice. Wasmtime forwards the final eight bytes of the second copy from rcx and '
     'runs three overflow and memory bound check pairs.'),
    ('scope_depth','life_depth',628,128091,[(0x4a0107,0x4a016b)],[(0xe65b2,0xe65c0)],
     'Wasmtime calls its memory_copy builtin for the 565-byte frame. Native reads its two used fields, '
     'function_node at byte zero and base at byte 40.'),
    ('held_root','life_held_into',726,142248,[(0x545719,0x545775)],[(0x1be0f5,0x1be13d)],
     'Wasmtime copies the 210-byte root. Native loads type_id, live_contents, class_frame, and first_kill.'),
    ('storage_root','life_held_into',726,142248,[(0x549bd8,0x549c35)],[(0x1bea24,0x1bea4d),(0x1beb40,0x1beb54)],
     'Wasmtime copies the 210-byte storage root. Native tests byteview before reading class_frame and '
     'conditionally reading type_id.')
]
report = {'native_sha256': identity(a.native), 'named_sha256':identity(a.named), 'cranelift_object_sha256':identity(obj),
          'objdump':subprocess.check_output(['llvm-objdump','--version'], text=True).splitlines()[0],
          'examples':{}}
for label, name, w, n, wranges, nranges, note in sites:
    report['examples'][label] = {'function': name, 'reading':note,
         'wasmtime_50_0_1':disasm(obj,f'wasm[0]::function[{w}]::{name}',wranges),
         'clang_23_1_5':disasm(a.native, f'g_fn{n}', nranges)}
print(json.dumps(report,indent=2))
