# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
"""Annotate indirect calls in a disassembly dump from tools/collect_native_wifi_abi.py with vtable slot names.

  python3 tools/annotate_vcalls.py abi/native-wifi/24H32/IO80211Controller-start.asm.txt \
      abi/native-wifi/24H32/IO80211Controller.vtable.txt [more.vtable.txt ...]

`call qword ptr [reg + 0xN]` after `mov reg, [obj]` is a virtual call; the vptr points 0x10 bytes into the vtable symbol, so
the slot is (N + 0x10) / 8. With several vtables the name from each is shown (the receiver class is not known from the
disassembly alone; choose by what the object is). Also prints calls through a plain `[rip+...]` GOT-style pointer unchanged.
"""
import re, sys


def load(path):
    t = {}
    for line in open(path):
        p = line.rstrip('\n').split('\t')
        if len(p) == 3 and p[0].isdigit():
            t[int(p[0])] = p[2]
    return t


def short(s):
    m = re.match(r'__ZN?K?(\d+)([A-Za-z0-9_]+?)(\d+)([A-Za-z0-9_~]+)', s)
    return s if not m else s


def main():
    asm, vts = sys.argv[1], [(p.split('/')[-1].split('.')[0], load(p)) for p in sys.argv[2:]]
    pat = re.compile(r'(call|jmp)\s+qword ptr \[(\w+) \+ (0x[0-9a-f]+)\]')
    for line in open(asm):
        line = line.rstrip('\n')
        m = pat.search(line)
        if m:
            off = int(m.group(3), 16)
            if off % 8 == 0 and off >= 0x10:
                slot = (off + 0x10) // 8
                names = ['%s:%d=%s' % (n, slot, t.get(slot, '?')) for n, t in vts]
                line += '   ; VCALL ' + ' | '.join(names)
        print(line)


if __name__ == '__main__':
    main()
