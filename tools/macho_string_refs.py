#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
#
# Find the code in a userland Mach-O that references a string, then disassemble around it. Companion to the KC tools
# (tools/kc.py) for the userland side of the AWDL work (wifip2pd / CoreWiFi). x86_64 only, lea rip-relative + immediate.
#
# Usage:
#   lipo -thin x86_64 /usr/libexec/wifip2pd -output /tmp/wifip2pd-x86_64   # fat binaries need a slice first
#   python3 tools/macho_string_refs.py /tmp/wifip2pd-x86_64 "missing the capability"
#   python3 tools/macho_string_refs.py /tmp/wifip2pd-x86_64 "missing the capability" --disasm 0x60
import argparse
import struct
import sys

from capstone import Cs, CS_ARCH_X86, CS_MODE_64


def load(path):
    d = open(path, 'rb').read()
    magic, cputype, cpusub, ftype, ncmds, sizeofcmds, flags, _ = struct.unpack_from('<IIIIIIII', d, 0)
    assert magic == 0xfeedfacf, 'not a 64-bit Mach-O'
    segs = []
    p = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', d, p)
        if cmd == 0x19:  # LC_SEGMENT_64
            name = d[p + 8:p + 24].split(b'\0')[0].decode()
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', d, p + 24)
            segs.append((name, vmaddr, vmsize, fileoff, filesize))
        p += size
    return d, segs


def fileoff_to_va(segs, off):
    for name, vmaddr, vmsize, fileoff, filesize in segs:
        if fileoff <= off < fileoff + filesize:
            return vmaddr + (off - fileoff)
    return None


def va_to_off(segs, va):
    for name, vmaddr, vmsize, fileoff, filesize in segs:
        if vmaddr <= va < vmaddr + filesize:
            return fileoff + (va - vmaddr)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('binary')
    ap.add_argument('needle', help='string to find (substring)')
    ap.add_argument('--disasm', type=int, default=0x80, help='bytes to disassemble before the reference')
    args = ap.parse_args()

    d, segs = load(args.binary)
    needle = args.needle.encode()
    i = d.find(needle)
    if i < 0:
        sys.exit('string not found')
    sva = fileoff_to_va(segs, i)
    print('string at file offset %#x, VA %#x' % (i, sva))

    # find text sections to scan (rough: scan everything, check lea targets)
    md = Cs(CS_ARCH_X86, CS_MODE_64)
    md.detail = False
    hits = []
    for name, vmaddr, vmsize, fileoff, filesize in segs:
        if name != '__TEXT':
            continue
        seg = d[fileoff:fileoff + filesize]
        # scan for '48 8d' (lea r64) and '4c 8d' (lea r64 ext)
        for m in range(len(seg) - 7):
            if seg[m] in (0x48, 0x4c) and seg[m + 1] == 0x8d:
                modrm = seg[m + 2]
                if (modrm & 0xc7) == 0x05:  # rip-relative
                    disp = struct.unpack_from('<i', seg, m + 3)[0]
                    va = vmaddr + m
                    if va + 7 + disp == sva:
                        hits.append(va)
    print('%d lea references' % len(hits))
    for va in hits[:8]:
        print('  reference at %#x' % va)
        if args.disasm:
            start = va - args.disasm
            off = va_to_off(segs, start)
            if off is None:
                continue
            code = d[off:off + args.disasm + 0x20]
            for ins in md.disasm(code, start):
                txt = '    %x: %-8s %s' % (ins.address, ins.mnemonic, ins.op_str)
                if ins.mnemonic == 'lea' and 'rip' in ins.op_str:
                    import re
                    mm = re.search(r'rip \+ (0x[0-9a-f]+|\d+)\]', ins.op_str)
                    if mm:
                        tgt = ins.address + ins.size + int(mm.group(1), 0)
                        o2 = va_to_off(segs, tgt)
                        if o2 is not None:
                            s = d[o2:o2 + 64].split(b'\0')[0]
                            if len(s) >= 4 and all(0x20 <= c < 0x7f for c in s):
                                txt += '  ; "%s"' % s.decode()
                print(txt)
                if ins.address >= va + 0x20:
                    break


if __name__ == '__main__':
    main()
