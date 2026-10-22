#!/usr/bin/env python3
"""Extract one fileset entry (kext) from BootKernelExtensions.kc into a standalone Mach-O.

  python3 tools/kc_extract.py <KC path> <substring of the fileset name> <output path>

Keeps the original vmaddrs, so symbol addresses from tools/kc.py / kc_vtable.py stay valid when the
extracted image is opened in a disassembler (REA/Ghidra, Hopper, IDA, ...).

The load commands of a kernel-collection entry store file offsets that are absolute in the .kc file.
They are rebased to the start of the extracted image (LC_SEGMENT_64, sections, symtab, dysymtab,
dyld info, linkedit data and encryption info), otherwise every tool that follows them reads the
wrong bytes or refuses the file (Ghidra: "invalid file", lldb: missing __LINKEDIT).
"""
import struct
import sys

# Load commands that carry file offsets which have to be rebased to the start of the entry.
LINKEDIT_DATA = {0x1d, 0x1e, 0x26, 0x29, 0x2b, 0x2e, 0x33, 0x34}   # code signature, split info,
                                                                  # function starts, data in code,
                                                                  # dylib code sign drs, linker opt
                                                                  # hint, exports trie, chained fixups


def _sub(buf, off, size, base):
    val = struct.unpack_from('<I' if size == 4 else '<Q', buf, off)[0]
    if val and val >= base:
        struct.pack_into('<I' if size == 4 else '<Q', buf, off, val - base)


def rebase_load_commands(blob, base):
    """Rebase every file offset in blob's load commands from the .kc file to the blob start."""
    magic, _, _, _, ncmds, _, _, _ = struct.unpack_from('<IIIIIIII', blob, 0)
    assert magic == 0xfeedfacf, hex(magic)
    p = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', blob, p)
        if cmd == 0x19:                                    # LC_SEGMENT_64
            _sub(blob, p + 40, 8, base)                    # fileoff
            nsects = struct.unpack_from('<I', blob, p + 64)[0]
            for i in range(nsects):
                s = p + 72 + i * 80
                _sub(blob, s + 48, 4, base)                # section offset
                _sub(blob, s + 56, 4, base)                # section reloff
        elif cmd == 0x2:                                   # LC_SYMTAB
            _sub(blob, p + 8, 4, base)
            _sub(blob, p + 16, 4, base)
        elif cmd == 0xb:                                   # LC_DYSYMTAB
            for off in (p + 32, p + 40, p + 48, p + 56, p + 64, p + 72):
                _sub(blob, off, 4, base)
        elif cmd in (0x22, 0x80000022):                    # LC_DYLD_INFO[_ONLY]
            for off in (p + 8, p + 16, p + 24, p + 32, p + 40):
                _sub(blob, off, 4, base)
        elif cmd in LINKEDIT_DATA:
            _sub(blob, p + 8, 4, base)
        elif cmd == 0x2c:                                  # LC_ENCRYPTION_INFO_64
            _sub(blob, p + 8, 4, base)
        elif cmd == 0x16:                                  # LC_TWOLEVEL_HINTS
            _sub(blob, p + 8, 4, base)
        elif cmd == 0x80000028:                            # LC_MAIN
            _sub(blob, p + 8, 8, base)
        elif cmd == 0x31:                                  # LC_NOTE
            _sub(blob, p + 24, 8, base)
        p += size
    return blob


def main():
    kc, want, out = sys.argv[1], sys.argv[2], sys.argv[3]
    d = open(kc, 'rb').read()

    magic, cputype, cpusub, ftype, ncmds, sizeofcmds, flags, _ = struct.unpack_from('<IIIIIIII', d, 0)
    assert magic == 0xfeedfacf, hex(magic)
    p = 32
    entries = []
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', d, p)
        if cmd == 0x80000035:                                   # LC_FILESET_ENTRY
            vmaddr, fileoff, strx, _ = struct.unpack_from('<QQII', d, p + 8)
            ename = d[p + strx:d.index(b'\0', p + strx)].decode()
            entries.append((ename, vmaddr, fileoff))
        p += size

    match = [e for e in entries if want in e[0]]
    if not match:
        sys.exit('no entry matching %r among %d entries' % (want, len(entries)))
    name, vmaddr, fileoff = match[0]
    if len(match) > 1:
        print('warning: %d matches, taking %s' % (len(match), name))

    # size of the entry: max(segment fileoff+filesize) over its own load commands
    magic, cputype, cpusub, ftype, ncmds, sizeofcmds, flags, _ = struct.unpack_from('<IIIIIIII', d, fileoff)
    end = 0
    p = fileoff + 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', d, p)
        if cmd == 0x19:                                         # LC_SEGMENT_64
            seg_off, seg_size = struct.unpack_from('<QQ', d, p + 40)
            if seg_size:
                end = max(end, seg_off + seg_size)
        p += size
    blob = bytearray(d[fileoff:end])
    rebase_load_commands(blob, fileoff)
    open(out, 'wb').write(blob)
    print('%s: vmaddr %#x fileoff %#x size %#x -> %s' % (name, vmaddr, fileoff, len(blob), out))


if __name__ == '__main__':
    main()
