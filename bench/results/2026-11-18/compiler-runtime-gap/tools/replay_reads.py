"""Count x86 instructions from life_replay's leaf load to its next load, both inclusive.

Use the sampling artifacts; pass the original native executable and the named Wasmtime
serialization as positional arguments. The function-relative locations refer to the
pinned binaries. No workload execution or profiler is needed to regenerate this receipt.
"""
import argparse
from bisect import bisect_right
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import subprocess


def disassemble(artifact, symbol):
    args = ['objdump', '-d', '-M', 'intel', '--no-show-raw-insn', '--disassemble=' + symbol, str(artifact)]
    dump = subprocess.check_output(args, text=True)
    start = int(re.search(r'(?m)^([0-9a-f]+) <' + re.escape(symbol) + r'>:$', dump)[1], 16)
    instructions = {}
    for pc, instruction in re.findall(r'^\s*([0-9a-f]+):\s+(.+)$', dump, re.M):
        instructions[int(pc, 16) - start] = instruction.split('#')[0].strip()
    return start, instructions


def summarize(artifact, symbol, first, last, decisions):
    base, instructions = disassemble(artifact, symbol)
    offsets = list(instructions)
    observed = set()
    rows = []
    groups = Counter()
    pc = first
    while True:
        instruction = instructions[pc]
        opcode, operands = instruction.split(maxsplit=1)
        line = f'+{pc:#06x}  {opcode:<8} {operands.split(" <")[0]}'
        if pc == first or pc == last:
            group = 'requested field loads'
        elif (opcode == 'cmp' and 'PTR [rip+' in operands) or opcode == 'cmova':
            group = 'Cranelift memory64 address guards (compare or conditional move)'
        elif 'PTR [rsp+' in operands:
            group = 'explicit x86 stack reads and writes'
        elif opcode in ('vmovq', 'vpinsrq', 'vpextrq'):
            group = 'pack or extract slice base and length'
        elif opcode in ('test', 'je'):
            group = 'ordinary array mode tests and branches'
        elif opcode in ('cmp', 'jae'):
            group = 'Goose element index check and branch'
        else:
            group = 'remaining address calculations, loads and register moves'
        groups[group] += 1
        if opcode.startswith('j'):
            taken = decisions[pc]
            observed.add(pc)
            target = int(operands.split()[0], 16) - base
            outcome = 'not taken'
            if taken:
                outcome = 'taken'
            line = f'+{pc:#06x}  {opcode:<8} +{target:#06x} ({outcome})'
        rows.append(line)
        if pc == last:
            break
        if decisions.get(pc):
            pc = target
        else:
            pc = offsets[bisect_right(offsets, pc)]
        if len(rows) > 100:
            raise ValueError('unexpected branch path')
    assert observed == set(decisions)
    return {'artifact_sha256': hashlib.sha256(artifact.read_bytes()).hexdigest(),
            'function': symbol, 'function_start': hex(base), 'instruction_count': len(rows),
            'groups': dict(groups), 'function_relative_instructions': rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('native', type=Path)
    parser.add_argument('wasmtime_serialization', type=Path)
    args = parser.parse_args()
    native = summarize(args.native, 'g_fn168147', 0x5f2, 0x5f6, {})
    wasm = summarize(args.wasmtime_serialization, 'wasm[0]::function[810]::life_replay',
                     0x5fe6, 0x6500, {0x6049: True, 0x6273: True, 0x64c3: False})
    assert native['instruction_count'] == 2 and wasm['instruction_count'] == 45
    report = {
        'compiler_source_commit': '2e42394d3b9638e2d8f2a8900d62e70d0ee5dfaf',
        'source': 'selfhost/checker_lifetimes.goose:5696',
        'goose': 'let entry = read; let leaf = l.summary_reads[entry].leaf as i64; read = l.summary_reads[entry].next as i64;',
        'field_layout': 'LifeReadEntry is 32 bytes. leaf is at byte 8 and next at byte 24.',
        'scope': 'Ordinary array mode zero, valid index. Both counts begin after the first element address was computed and include both field loads. This is a control-flow instruction count, not a time measurement.',
        'input_wasm_sha256': 'a3616562b88af337cb5baa89a29a087077794e729c21118a4353fd2ecc2c2b06',
        'name_section_appended_wasm_sha256': 'e10888552103970b310b876b0ea8bf23c0cac7aa8e71a5e1416f14bc78f747ae',
        'reproduce': 'python replay_reads.py /path/to/compiler-native /path/to/compiler.cwasm',
        'native_clang_23_1_5': native, 'wasmtime_50_0_1_memory64': wasm,
    }
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
