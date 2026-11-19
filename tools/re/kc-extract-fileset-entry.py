# carve one fileset entry from a kernel collection into a standalone Mach-O (for disassembly). usage: kcx.py <kc> <bundle id> <out>
import sys, struct
kc, bid, out = sys.argv[1:4]
f = open(kc, 'rb'); h = f.read(32)
_, _, _, _, ncmds, scmds, _, _ = struct.unpack('<IiiIIIII', h); lc = f.read(scmds)
segs = []; ent = None; p = 0
for i in range(ncmds):
    cmd, cs = struct.unpack_from('<II', lc, p)
    if cmd == 0x19:
        va, vs, fo, fs = struct.unpack_from('<QQQQ', lc, p+24); segs.append((va, vs, fo, fs))
    if cmd == 0x80000035:
        va, fo, so = struct.unpack_from('<QQI', lc, p+8)
        if lc[p+so:p+cs].split(b'\0')[0].decode() == bid: ent = (va, fo)
    p += cs
def v2f(a):
    for va, vs, fo, fs in segs:
        if va <= a < va + fs: return fo + a - va
    raise Exception('unmapped %x' % a)
def rd(a, n): f.seek(v2f(a)); return f.read(n)
va, fo = ent
f.seek(fo); mh = bytearray(f.read(32))
ncmds, scmds = struct.unpack_from('<II', mh, 16); elc = bytearray(f.read(scmds))
data = bytearray(); p = 0; cmds = []
for i in range(ncmds):
    cmd, cs = struct.unpack_from('<II', elc, p); cmds.append((cmd, p)); p += cs
le = None
for cmd, p in cmds:
    if cmd != 0x19: continue
    name = elc[p+8:p+24].rstrip(b'\0').decode()
    sva, svs, sfo, sfs = struct.unpack_from('<QQQQ', elc, p+24)
    if name == '__LINKEDIT': le = (p, sva, sfo); continue
    while len(data) % 0x1000: data.append(0)
    no = len(data)
    if name == '__TEXT' and len(data) == 0: no = 0
    data += rd(sva, sfs) if sfs else b''
    struct.pack_into('<QQ', elc, p+40, no, sfs)
    for k in range(struct.unpack_from('<I', elc, p+64)[0]):
        sp = p + 72 + k*80; sa, ss, so = struct.unpack_from('<QQI', elc, sp+32)
        if so: struct.pack_into('<I', elc, sp+48, no + sa - sva)
# linkedit: copy symtab with compacted strings
lep, leva, lefo = le
while len(data) % 0x1000: data.append(0)
nl0 = len(data); L = bytearray()
for cmd, p in cmds:
    if cmd == 0x2:
        so, ns, sto, ssz = struct.unpack_from('<IIII', elc, p+8)
        f.seek(so); nl = bytearray(f.read(ns*16)); strs = bytearray(b'\0')
        for i in range(ns):
            sx = struct.unpack_from('<I', nl, i*16)[0]; f.seek(sto + sx); s = f.read(512).split(b'\0')[0]
            struct.pack_into('<I', nl, i*16, len(strs)); strs += s + b'\0'
        a = nl0 + len(L); L += nl; b = nl0 + len(L); L += strs
        struct.pack_into('<IIII', elc, p+8, a, ns, b, len(strs))
    elif cmd == 0xb:
        for o in range(8, 80, 4):
            if o >= 8+24 : struct.pack_into('<I', elc, p+o, 0)
    elif cmd in (0x26, 0x29, 0x1d, 0x80000034):
        struct.pack_into('<II', elc, p+8, 0, 0)
while len(L) % 8: L.append(0)
struct.pack_into('<QQQQ', elc, lep+24, leva, (len(L)+0xfff)&~0xfff, nl0, len(L))
data += L
data[0:32] = mh; data[32:32+scmds] = elc
struct.pack_into('<I', data, 12, 0xb)  # MH_KEXT_BUNDLE
open(out, 'wb').write(data); print(out, len(data))
