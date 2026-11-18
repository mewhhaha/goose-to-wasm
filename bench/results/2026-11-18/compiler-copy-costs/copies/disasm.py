"""Extract verified llvm-objdump instruction spans used by the pinned receipts."""
import re
import subprocess

def disasm(file, symbol, spans):
    lines = subprocess.check_output(['llvm-objdump', '--disassemble-symbols='+symbol, '--no-show-raw-insn',
                                     '--x86-asm-syntax=intel', file], text=True).splitlines()
    body = []
    for line in lines:
        m = re.match(r'^\s*([0-9a-f]+):\s+(.+)$',line)
        if m:
            body.append((int(m[1],16), m[2]))
    groups = []
    for start, end in spans:
        group = [f'{pc:#x}  {op}' for pc,op in body if start<=pc<=end]
        assert group[0].startswith(hex(start)+' ') and group[-1].startswith(hex(end)+' ')
        groups.append(group)
    return groups
