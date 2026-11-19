# minimal dyld shared cache single-image extractor (x86_64). usage: dscx.py <cache base> <image path> <out>
# single-image extractor for this machine's dyld shared cache (Apple's dsc_extractor refuses the modified cache).
import sys, struct, glob, os
base, img, out = sys.argv[1:4]
files = [base] + sorted(f for f in glob.glob(base + '.*') if f.rsplit('.',1)[1].isdigit())
maps = []
for f in files:
    fh = open(f, 'rb'); h = fh.read(0x200)
    mo, mc = struct.unpack_from('<II', h, 16)
    fh.seek(mo); 
    for i in range(mc):
        a, s, o, mp, ip = struct.unpack('<QQQII', fh.read(32))
        maps.append((a, s, o, f))
fds = {}
def rd(addr, n):
    for a, s, o, f in maps:
        if a <= addr < a + s:
            fd = fds.setdefault(f, open(f, 'rb')); fd.seek(o + addr - a); return fd.read(n)
    raise Exception('unmapped %x' % addr)
# find image text address from .map
text = None; lines = open(base + '.map').read().split('\n')
for i, l in enumerate(lines):
    if l.strip() == img:
        text = int(lines[i+1].split()[1], 16); break
mh = rd(text, 32)
magic, cpu, sub, ft, ncmds, sizeofcmds, flags, res = struct.unpack('<IiiIIIII', mh)
lc = bytearray(rd(text + 32, sizeofcmds))
segs = []; off = 0; p = 0
cmds = []
while p < sizeofcmds:
    cmd, cs = struct.unpack_from('<II', lc, p); cmds.append((cmd, p, cs)); p += cs
outdata = bytearray()
linkedit = None
for cmd, p, cs in cmds:
    if cmd == 0x19:
        name = lc[p+8:p+24].rstrip(b'\0').decode()
        vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', lc, p+24)
        if name == '__LINKEDIT': linkedit = (p, vmaddr, fileoff); continue
        newoff = len(outdata) if name != '__TEXT' else 0
        if name == '__TEXT': outdata = bytearray(rd(vmaddr, filesize))
        else:
            while len(outdata) % 0x1000: outdata.append(0)
            newoff = len(outdata); outdata += rd(vmaddr, filesize)
        struct.pack_into('<Q', lc, p+40, newoff)
        nsect = struct.unpack_from('<I', lc, p+64)[0]
        for k in range(nsect):
            sp = p + 72 + k*80
            saddr, ssize, soff = struct.unpack_from('<QQI', lc, sp+32)
            if soff: struct.pack_into('<I', lc, sp+48, newoff + (saddr - vmaddr))
le_p, le_vm, le_off = linkedit
def lerd(o, n): return rd(le_vm + (o - le_off), n)
while len(outdata) % 0x1000: outdata.append(0)
newle = len(outdata); le = bytearray()
def put(b):
    o = newle + len(le); le.extend(b)
    while len(le) % 8: le.append(0)
    return o
for cmd, p, cs in cmds:
    if cmd == 0x2:  # symtab
        symoff, nsyms, stroff, strsize = struct.unpack_from('<IIII', lc, p+8)
        nl = bytearray(lerd(symoff, nsyms*16)); strs = bytearray(b'\0'); cache = {}
        for i in range(nsyms):
            sx = struct.unpack_from('<I', nl, i*16)[0]
            if sx not in cache:
                s = bytearray(); a = le_vm + (stroff - le_off) + sx
                while True:
                    ch = rd(a, 256); z = ch.find(b'\0')
                    if z >= 0: s += ch[:z]; break
                    s += ch; a += 256
                cache[sx] = len(strs); strs += s + b'\0'
            struct.pack_into('<I', nl, i*16, cache[sx])
        so = put(nl); st = put(strs)
        struct.pack_into('<IIII', lc, p+8, so, nsyms, st, len(strs))
    elif cmd == 0xb:  # dysymtab
        ind, nind = struct.unpack_from('<II', lc, p+56)
        if nind: struct.pack_into('<I', lc, p+56, put(lerd(ind, nind*4)))
        for o in (p+32, p+40, p+48, p+64, p+72):  # tocoff, modtab, extrefsym, extrel, locrel -> zero
            struct.pack_into('<II', lc, o, 0, 0)
    elif cmd in (0x26, 0x29, 0x80000033, 0x80000034, 0x1d, 0x2b):  # function starts, data in code, exports trie, chained, codesig, dylib_code_sign_drs
        o, n = struct.unpack_from('<II', lc, p+8)
        if n and cmd in (0x26, 0x29, 0x80000033): struct.pack_into('<II', lc, p+8, put(lerd(o, n)), n)
        else: struct.pack_into('<II', lc, p+8, 0, 0)
    elif cmd in (0x22, 0x80000022):  # dyld_info
        vals = list(struct.unpack_from('<10I', lc, p+8))
        for k in range(0, 10, 2):
            if vals[k+1] and k == 8: vals[k] = put(lerd(vals[k], vals[k+1]))
            else: vals[k] = vals[k] if k == 8 else 0; 
            if k != 8: vals[k+1] = 0
        struct.pack_into('<10I', lc, p+8, *vals)
struct.pack_into('<QQQQ', lc, le_p+24, le_vm, (len(le)+0xfff)&~0xfff, newle, len(le))
outdata += le
outdata[32:32+sizeofcmds] = lc
struct.pack_into('<I', outdata, 24, flags & ~0x80000000)  # clear MH_DYLIB_IN_CACHE
open(out, 'wb').write(outdata); print('wrote', out, len(outdata))
