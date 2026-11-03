#!/usr/bin/env python3
# Minimal linker for the ibprobe cave, so it builds on macOS too (no GNU ld there).
# Takes an x86-64 ELF relocatable with one .text section, places .text at --base and resolves
# R_X86_64_PC32 / R_X86_64_PLT32 against local .text labels and against --sym NAME=ADDR (absolute
# addresses inside NMXGPU). Any other relocation is an error.
#
#   elflink.py cave.o cave.bin --base 0x5aa5a0 --sym CONT=0x17a99 --sym PRINTF=0xbc46e ...
import argparse
import struct
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('obj')
    ap.add_argument('out')
    ap.add_argument('--base', type=lambda s: int(s, 0), required=True)
    ap.add_argument('--sym', action='append', default=[])
    a = ap.parse_args()
    syms_abs = {}
    for s in a.sym:
        k, v = s.split('=')
        syms_abs[k] = int(v, 0)

    d = open(a.obj, 'rb').read()
    if d[:4] != b'\x7fELF' or d[4] != 2 or d[5] != 1:
        sys.exit('not a little-endian ELF64 object')
    e_shoff, = struct.unpack_from('<Q', d, 0x28)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from('<HHH', d, 0x3a)
    secs = []
    for i in range(e_shnum):
        secs.append(struct.unpack_from('<IIQQQQIIQQ', d, e_shoff + i * e_shentsize))
    shstr = secs[e_shstrndx]

    def name(off, tab):
        o = tab[4] + off
        return d[o:d.index(b'\0', o)].decode()

    by_name = {name(s[0], shstr): (i, s) for i, s in enumerate(secs)}
    ti, text = by_name['.text']
    code = bytearray(d[text[4]:text[4] + text[5]])
    _, symtab = by_name['.symtab']
    strtab = secs[symtab[6]]
    syms = []
    for k in range(symtab[5] // 24):
        st_name, st_info, st_other, st_shndx, st_value, st_size = struct.unpack_from('<IBBHQQ', d, symtab[4] + k * 24)
        syms.append((name(st_name, strtab) if st_name else '', st_shndx, st_value))

    for sname in ('.rela.text', '.rel.text'):
        if sname not in by_name:
            continue
        if sname == '.rel.text':
            sys.exit('REL relocations are not supported')
        _, rs = by_name[sname]
        for k in range(rs[5] // 24):
            r_off, r_info, r_add = struct.unpack_from('<QQq', d, rs[4] + k * 24)
            rtype, rsym = r_info & 0xffffffff, r_info >> 32
            sn, shndx, val = syms[rsym]
            if shndx == ti:
                S = a.base + val
            elif sn in syms_abs:
                S = syms_abs[sn]
            elif shndx == 0xfff1:          # SHN_ABS (.set NAME, 0x...)
                S = val
            else:
                sys.exit(f'unresolved symbol {sn!r} at {r_off:#x}')
            P = a.base + r_off
            if rtype in (2, 4):            # PC32, PLT32
                v = S + r_add - P
                if not -2**31 <= v < 2**31:
                    sys.exit(f'{sn}: out of range at {r_off:#x}')
                struct.pack_into('<i', code, r_off, v)
            else:
                sys.exit(f'relocation type {rtype} at {r_off:#x} not supported')
    open(a.out, 'wb').write(code)
    print(f'{a.out}: {len(code)} bytes at {a.base:#x}')


if __name__ == '__main__':
    main()
