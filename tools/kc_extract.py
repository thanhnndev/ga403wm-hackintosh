#!/usr/bin/env python3
"""Extract one fileset entry (kext) from BootKernelExtensions.kc into a standalone Mach-O.

  python3 tools/kc_extract.py <KC path> <substring of the fileset name> <output path>

Keeps the original vmaddrs, so symbol addresses from tools/kc.py / kc_vtable.py stay valid when the
extracted image is opened in a disassembler (REA/Hopper, IDA, ...).
"""
import struct
import sys

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
blob = d[fileoff:end]
open(out, 'wb').write(blob)
print('%s: vmaddr %#x fileoff %#x size %#x -> %s' % (name, vmaddr, fileoff, len(blob), out))
