#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
"""List every reference to an external symbol inside a kext, grouped by enclosing function.

Why this exists: kexts have no __stubs / indirect symbol table. The KX resolves external
references from the `call rel32` sites recorded as X86_64_RELOC_BRANCH entries in
LC_DYSYMTAB's *local* relocation block (r_extern=1, r_symbolnum = symtab index). Reading
that block is the only reliable way to find "who calls ml_set_interrupts_enabled" etc.

    tools/890m/kext_relocscan.py NMXGPU                     # summary: rxtern symbol -> callers
    tools/890m/kext_relocscan.py NMXGPU _ml_set_interrupts_enabled
    tools/890m/kext_relocscan.py NMXGPU _ml_set_interrupts_enabled --disasm

capstone is optional (only needed for --disasm / instruction validation).
"""
import argparse
import bisect
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from macho_lite import MachO, N_TYPE, N_SECT

X86_64_RELOC_BRANCH = 2
X86_64_RELOC_GOT_LOAD = 3
X86_64_RELOC_GOT = 4
RELOC_NAMES = {0: 'UNSIGNED', 1: 'SIGNED', 2: 'BRANCH', 3: 'GOT_LOAD', 4: 'GOT', 5: 'SUBTRACTOR',
               6: 'SIGNED_1', 7: 'SIGNED_2', 8: 'SIGNED_4', 9: 'TLV'}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('binary')
    ap.add_argument('symbol', nargs='?', help='undefined symbol name (e.g. _ml_set_interrupts_enabled)')
    ap.add_argument('--disasm', action='store_true', help='decode a window around each site (needs capstone)')
    ap.add_argument('--window', type=int, default=24, help='instructions of context for --disasm')
    args = ap.parse_args()

    m = MachO(args.binary)
    syms = m.symbols()
    by_name = {}
    for i, (name, typ, sect, value) in enumerate(syms):
        by_name.setdefault(name, i)
    funcs = m.defined_functions()
    faddrs = [f[0] for f in funcs]

    def enclosing(va):
        i = bisect.bisect_right(faddrs, va) - 1
        if i < 0:
            return None
        return funcs[i][1]

    sites = []          # (addr_of_opcode, symbol_name, reloc_type, r_address)
    for ra, r_symbolnum, r_pcrel, r_length, r_extern, r_type in m.relocs():
        if not r_extern or r_symbolnum >= len(syms):
            continue
        name = syms[r_symbolnum][0]
        # The relocation points at the 4-byte displacement; the opcode sits right before it
        # for branch/GOT relocs (resulting in a 5-byte call/jmp). r_address is relative to the
        # __TEXT start, which is 0 for kexts, so it doubles as the vmaddr.
        noise = m.read_va(ra - 1, 1)
        opcode = noise[0] if noise else None
        sites.append((ra - 1 if opcode in (0xE8, 0xE9, 0x0F) else ra, name, r_type, ra))
    if args.symbol:
        sites = [s for s in sites if s[1] == args.symbol]

    if not sites:
        print("no matching external reference found")
        return 1

    if args.symbol:
        md = None
        if args.disasm:
            try:
                import capstone
                md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
                md.detail = True
            except Exception as e:  # pragma: no cover
                print(f"(no capstone: {e})", file=sys.stderr)
        print(f"{args.binary}: {len(sites)} reference(s) to {args.symbol}")
        for va, name, r_type, raw in sites:
            print(f"  {va:#08x}  in {enclosing(va)}   reloc@{raw:#x} {RELOC_NAMES.get(r_type, r_type)}")
            if md:
                text = m.section('__text')
                start = max(text[2], va - args.window * 4)
                code = m.read_va(start, (va - start) + 8)
                for ins in md.disasm(code, start):
                    mark = '  <<<' if ins.address <= va < ins.address + ins.size else ''
                    print(f"      {ins.address:#08x}  {ins.mnemonic:7} {ins.op_str}{mark}")
        return 0

    # summary mode: group by symbol then by enclosing function
    per = {}
    for va, name, r_type, raw in sites:
        per.setdefault(name, {}).setdefault(enclosing(va), []).append(va)
    print(f"{args.binary}: {len(per)} referenced extern symbols, {len(sites)} sites")
    for name in sorted(per):
        callers = per[name]
        print(f"\n{name}: {sum(len(v) for v in callers.values())} site(s)")
        for fn in sorted(callers, key=lambda k: (k is None, k)):
            addrs = ', '.join(f'{a:#x}' for a in sorted(callers[fn]))
            print(f"    {fn or '?'}  ->  {addrs}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
