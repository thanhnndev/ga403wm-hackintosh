#!/usr/bin/env python3
# Disassemble a range of an x86-64 binary (file offset == address, as in NMXGPU) with symbol names on branch targets
# and rip-relative operands. Needs capstone.
#   nm -m NMXGPU | awk '$2=="(__TEXT,__text)"||$2~/__DATA|__cstring/{print $1,$NF}' > nmx.syms
#   nmx-disasm.py NMXGPU nmx.syms 5a790 5a8c8
import bisect
import re
import sys

from capstone import CS_ARCH_X86, CS_MODE_64, Cs

b = open(sys.argv[1], 'rb').read()
syms = sorted((int(a, 16), n) for a, n in (l.split() for l in open(sys.argv[2])))
addrs = [a for a, _ in syms]


def name(x):
    i = bisect.bisect_right(addrs, x) - 1
    if i < 0:
        return ''
    a, n = syms[i]
    return n if x == a else f'{n}+{x - a:#x}'


start, end = int(sys.argv[3], 16), int(sys.argv[4], 16)
for ins in Cs(CS_ARCH_X86, CS_MODE_64).disasm(b[start:end], start):
    s = f'{ins.address:8x}: {ins.bytes.hex():24s} {ins.mnemonic} {ins.op_str}'
    m = re.search(r'rip \+ (0x[0-9a-f]+)', ins.op_str)
    if m:
        s += f'   ; {name(ins.address + ins.size + int(m.group(1), 16))}'
    elif ins.mnemonic == 'call' or ins.mnemonic.startswith('j'):
        try:
            s += f'   ; {name(int(ins.op_str, 16))}'
        except ValueError:
            pass
    print(s)
