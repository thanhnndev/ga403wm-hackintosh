#!/usr/bin/env python3
# Minimal linker for C caves (no GNU ld on macOS). Takes an x86-64 ELF relocatable, lays out its allocated read-only
# sections at --base (.text.entry first, then the other .text*, then .rodata*), and resolves R_X86_64_PC32 /
# R_X86_64_PLT32 against its own symbols and against --sym NAME=ADDR (addresses inside NMXGPU).
# Writable sections, GOT relocations or anything else are an error: the cave lives in __TEXT.
#
#   elflink2.py cave.o cave.bin --base 0x5ab300 --sym PRINTF=0xbc46e ...
import argparse
import struct
import sys

SHF_WRITE, SHF_ALLOC, SHF_EXEC = 1, 2, 4


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('obj')
    ap.add_argument('out')
    ap.add_argument('--base', type=lambda s: int(s, 0), required=True)
    ap.add_argument('--limit', type=lambda s: int(s, 0), help='first address the cave must not reach')
    ap.add_argument('--sym', action='append', default=[])
    ap.add_argument('--map', action='store_true')
    a = ap.parse_args()
    ext = {k: int(v, 0) for k, v in (s.split('=') for s in a.sym)}

    d = open(a.obj, 'rb').read()
    if d[:4] != b'\x7fELF' or d[4] != 2 or d[5] != 1:
        sys.exit('not a little-endian ELF64 object')
    e_shoff, = struct.unpack_from('<Q', d, 0x28)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from('<HHH', d, 0x3a)
    secs = [struct.unpack_from('<IIQQQQIIQQ', d, e_shoff + i * e_shentsize) for i in range(e_shnum)]
    shstr = secs[e_shstrndx]

    def cstr(tab, off):
        o = tab[4] + off
        return d[o:d.index(b'\0', o)].decode()

    names = [cstr(shstr, s[0]) for s in secs]
    alloc = [i for i, s in enumerate(secs) if s[2] & SHF_ALLOC and s[5]]
    for i in alloc:
        if secs[i][2] & SHF_WRITE:
            sys.exit(f'writable section {names[i]} ({secs[i][5]} bytes): the cave cannot hold data')
        if secs[i][1] == 8:
            sys.exit(f'NOBITS section {names[i]}')

    def rank(i):
        n = names[i]
        return (0 if n == '.text.entry' else 1 if n.startswith('.text') else 2, i)

    order = sorted(alloc, key=rank)
    place = {}
    img = bytearray()
    for i in order:
        al = max(secs[i][8], 1)
        while (a.base + len(img)) % al:
            img.append(0xcc)
        place[i] = a.base + len(img)
        img += d[secs[i][4]:secs[i][4] + secs[i][5]]

    symtab = next(s for s in secs if s[1] == 2)
    strtab = secs[symtab[6]]
    syms = []
    for k in range(symtab[5] // 24):
        st_name, st_info, st_other, st_shndx, st_value, st_size = struct.unpack_from('<IBBHQQ', d, symtab[4] + k * 24)
        syms.append((cstr(strtab, st_name) if st_name else '', st_shndx, st_value))

    def sym_addr(k):
        n, shndx, val = syms[k]
        if shndx == 0:
            if n not in ext:
                sys.exit(f'unresolved symbol {n!r}')
            return ext[n]
        if shndx == 0xfff1:
            return val
        if shndx in place:
            return place[shndx] + val
        sys.exit(f'symbol {n!r} in unplaced section {names[shndx]}')

    for ri, rs in enumerate(secs):
        if rs[1] == 9:
            sys.exit(f'REL section {names[ri]} not supported')
        if rs[1] != 4 or rs[7] not in place:
            if rs[1] == 4 and secs[rs[7]][2] & SHF_ALLOC and secs[rs[7]][5]:
                sys.exit(f'relocations for unplaced {names[rs[7]]}')
            continue
        tgt = rs[7]
        for k in range(rs[5] // 24):
            r_off, r_info, r_add = struct.unpack_from('<QQq', d, rs[4] + k * 24)
            rtype, rsym = r_info & 0xffffffff, r_info >> 32
            S = sym_addr(rsym)
            P = place[tgt] + r_off
            if rtype not in (2, 4):
                sys.exit(f'relocation type {rtype} ({syms[rsym][0]!r}) in {names[tgt]} at {r_off:#x} not supported')
            v = S + r_add - P
            if not -2**31 <= v < 2**31:
                sys.exit(f'{syms[rsym][0]}: out of range')
            struct.pack_into('<i', img, P - a.base, v)

    end = a.base + len(img)
    if a.limit is not None and end > a.limit:
        sys.exit(f'cave ends at {end:#x}, past the limit {a.limit:#x}')
    open(a.out, 'wb').write(img)
    print(f'{a.out}: {len(img)} bytes at {a.base:#x}..{end:#x}')
    if a.map:
        for i in order:
            print(f'  {names[i]:24s} {place[i]:#x} {secs[i][5]:#x}')
        for n, shndx, val in syms:
            if n and shndx in place:
                print(f'  {place[shndx] + val:#x} {n}')


if __name__ == '__main__':
    main()
