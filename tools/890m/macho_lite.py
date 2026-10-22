#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
"""Minimal Mach-O reader for Linux-side analysis of macOS kexts / dylibs.

Exists because /tmp gets wiped: this is the parser we keep re-writing (was /tmp/opencode/macho.py).
Handles fat binaries (picks the x86_64 slice) and kexts' `nmx_sysinit` style layouts.

    from macho_lite import MachO
    m = MachO('NMXGPU')
    m.segments, m.sections          # [(name, vmaddr, vmsize, fileoff, filesize), ...]
    m.va2off(0x6d527f)              # -> file offset
    m.symbols()                     # [(name, n_type, n_sect, n_value), ...]
    m.dysymtab                      # {'locreloff': ..., 'nlocrel': ..., 'indirectsymoff': ...}
    m.relocs()                      # parsed local relocations (r_extern sites reference externs)

Kexts do NOT use __stubs/indirect symbols: every external call site is a plain `call rel32`
whose displacement carries an X86_64_RELOC_BRANCH local relocation pointing at the extern
symbol (the KX fixes these up at load). That is why `kext_relocscan.py` exists.
"""
import struct

MH_MAGIC = 0xfeedface
MH_CIGAM = 0xcefaedfe
MH_MAGIC_64 = 0xfeedfacf
MH_CIGAM_64 = 0xcffaedfe
FAT_MAGIC = 0xcafebabe
FAT_MAGIC_64 = 0xcafebabf
CPU_TYPE_X86_64 = 0x01000007

LC_SEGMENT = 0x1
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x2
LC_DYSYMTAB = 0xB

N_TYPE = 0x0e
N_SECT = 0x0e
N_UNDF = 0x00
N_INDR = 0x0a


def load(path):
    """Return the x86_64 slice bytes of a Mach-O (fat or thin)."""
    with open(path, 'rb') as fh:
        d = fh.read()
    magic = struct.unpack_from('>I', d, 0)[0]
    if magic in (FAT_MAGIC, FAT_MAGIC_64):
        n = struct.unpack_from('>I', d, 4)[0]
        chosen = None
        for i in range(n):
            if magic == FAT_MAGIC_64:
                cputype, cpusub, off, size, align = struct.unpack_from('>iiQQI', d, 8 + i * 32)
            else:
                cputype, cpusub, off, size, align = struct.unpack_from('>iiIII', d, 8 + i * 20)
            if cputype == CPU_TYPE_X86_64:
                chosen = (off, size)
                break
            if chosen is None:
                chosen = (off, size)
        off, size = chosen
        return d[off:off + size]
    return d


class MachO:
    def __init__(self, path):
        self.path = path
        self.data = load(path)
        self._parse()

    # ---------------- load commands ----------------
    def _parse(self):
        d = self.data
        magic = struct.unpack_from('<I', d, 0)[0]
        assert magic in (MH_MAGIC_64, MH_MAGIC), hex(magic)
        self.magic = magic
        self.ncmds = struct.unpack_from('<I', d, 16)[0]
        self.sizeofcmds = struct.unpack_from('<I', d, 20)[0]
        hdr = 32 if magic == MH_MAGIC_64 else 28
        self.segments = []       # (name, vmaddr, vmsize, fileoff, filesize)
        self.sections = []       # (segname, sectname, addr, size, offset, reserved1, flags)
        self.cmds = []           # (cmd, offset, cmdsize)
        self.symtab = None
        self.dysymtab = None
        off = hdr
        for _ in range(self.ncmds):
            cmd, cmdsize = struct.unpack_from('<II', d, off)
            self.cmds.append((cmd, off, cmdsize))
            if cmd == LC_SEGMENT_64:
                name = d[off + 8:off + 24].split(b'\0')[0].decode('utf-8', 'replace')
                vmaddr, vmsize, foff, fsize = struct.unpack_from('<QQQQ', d, off + 24)
                self.segments.append((name, vmaddr, vmsize, foff, fsize))
                nsects = struct.unpack_from('<I', d, off + 64)[0]
                so = off + 72
                for _ in range(nsects):
                    sname = d[so:so + 16].split(b'\0')[0].decode('utf-8', 'replace')
                    sseg = d[so + 16:so + 32].split(b'\0')[0].decode('utf-8', 'replace')
                    addr, size = struct.unpack_from('<QQ', d, so + 32)
                    soff = struct.unpack_from('<I', d, so + 48)[0]
                    res1 = struct.unpack_from('<I', d, so + 68)[0]
                    flags = struct.unpack_from('<I', d, so + 64)[0]
                    self.sections.append((sseg, sname, addr, size, soff, res1, flags))
                    so += 80
            elif cmd == LC_SYMTAB:
                symoff, nsyms, stroff, strsize = struct.unpack_from('<IIII', d, off + 8)
                self.symtab = {'symoff': symoff, 'nsyms': nsyms, 'stroff': stroff, 'strsize': strsize}
            elif cmd == LC_DYSYMTAB:
                v = struct.unpack_from('<18I', d, off)
                self.dysymtab = {
                    'ilocalsym': v[2], 'nlocalsym': v[3], 'iextdefsym': v[4], 'nextdefsym': v[5],
                    'iundefsym': v[6], 'nundefsym': v[7],
                    'indirectsymoff': v[14], 'nindirectsyms': v[15],
                    'extreloff': v[12], 'nextrel': v[13],
                    'locreloff': v[16], 'nlocrel': v[17],
                }
            off += cmdsize

    # ---------------- helpers ----------------
    def segment(self, name):
        for seg in self.segments:
            if seg[0] == name:
                return seg
        return None

    def section(self, value, segname=None):
        for s in self.sections:
            if s[1] == value and (segname is None or s[0] == segname):
                return s
        return None

    def va2off(self, va):
        for _name, vmaddr, vmsize, foff, fsize in self.segments:
            if vmaddr <= va < vmaddr + vmsize and va - vmaddr < fsize:
                return foff + (va - vmaddr)
        return None

    def off2va(self, off):
        for _name, vmaddr, vmsize, foff, fsize in self.segments:
            if foff <= off < foff + fsize:
                return vmaddr + (off - foff)
        return None

    def read_va(self, va, size):
        fo = self.va2off(va)
        if fo is None:
            return None
        return self.data[fo:fo + size]

    def cstr_at(self, va, maxlen=200):
        fo = self.va2off(va)
        if fo is None:
            return None
        end = self.data.find(b'\0', fo)
        if end < 0:
            return None
        return self.data[fo:min(end, fo + maxlen)].decode('utf-8', 'replace')

    def symbols(self):
        """[(name, n_type, n_sect, n_value), ...]"""
        if not self.symtab:
            return []
        d = self.data
        out = []
        for i in range(self.symtab['nsyms']):
            strx, typ, sect, desc, value = struct.unpack_from('<IBBHQ', d, self.symtab['symoff'] + i * 16)
            start = self.symtab['stroff'] + strx
            end = d.index(b'\0', start)
            out.append((d[start:end].decode('utf-8', 'replace'), typ, sect, value))
        return out

    def defined_functions(self):
        """Sorted [(address, name)] of defined text/global symbols (for address->name lookup)."""
        out = [(v, n) for n, t, s, v in self.symbols() if (t & N_TYPE) == N_SECT and v]
        return sorted(out)

    def relocs(self):
        """Parse LC_DYSYMTAB local relocations.

        Each entry: (r_address, r_symbolnum, r_pcrel, r_length, r_extern, r_type).
        r_address is relative to the __TEXT segment start (== vmaddr for kexts, whose
        __TEXT vmaddr is 0), i.e. it lands inside __text for code reference sites.
        """
        if not self.dysymtab:
            return []
        d = self.data
        base = self.dysymtab['locreloff']
        out = []
        for i in range(self.dysymtab['nlocrel']):
            ra, rb = struct.unpack_from('<iI', d, base + i * 8)
            out.append((ra, rb & 0xffffff, (rb >> 24) & 1, (rb >> 25) & 3, (rb >> 27) & 1, (rb >> 28) & 0xf))
        return out


if __name__ == '__main__':
    import sys
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    m = MachO(sys.argv[1])
    print(f"{sys.argv[1]}: {len(m.data)} bytes, magic={m.magic:#x}, ncmds={m.ncmds}")
    for seg in m.segments:
        print(f"  seg {seg[0]:12} vm={seg[1]:#x} size={seg[2]:#x} foff={seg[3]:#x} fsize={seg[4]:#x}")
    for s in m.sections:
        print(f"    {s[0]:10} {s[1]:20} addr={s[2]:#x} size={s[3]:#x} off={s[4]:#x} res1={s[5]}")
    syms = m.symbols()
    print(f"  symbols: {len(syms)}")
    if m.dysymtab:
        print(f"  dysymtab: {m.dysymtab}")
        print(f"  local relocations: {len(m.relocs())}")
