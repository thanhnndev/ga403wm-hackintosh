import struct, uuid, sys, os, hashlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import macho
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'apfs_out13')
rd = lambda n: open(os.path.join(D, n), 'rb').read()
kc = rd('S_Library_NullMoth_step125-bk-20261107T083523Z_AuxiliaryKernelExtensions.kc')
gpu = rd('S_Library_NullMoth_step125-bk-20261107T083523Z_NMXGPU.kext_Contents_MacOS_NMXGPU')
s0 = rd('S_Library_NullMoth_step126-bk-20261107T084026Z_StrixS0ix.kext_Contents_MacOS_StrixS0ix')
def lc_uuid(d):
    ncmds = struct.unpack_from('<I', d, 16)[0]; off = 32
    for _ in range(ncmds):
        c, s = struct.unpack_from('<II', d, off)
        if c == 0x1b: return d[off+8:off+24]
        off += s
for name, b in (('NMXGPU', gpu), ('StrixS0ix', s0)):
    u = lc_uuid(b); print(name, uuid.UUID(bytes=u), 'in old KC:', kc.count(u), 'sha', hashlib.sha256(b).hexdigest()[:16])
want = ['C18FD8B4-0354-3D4C-9A4E-EDA2AB2463F6','90C7A833-82AA-3769-9F9A-5AD9D382548D','EF716CC3-0F0D-3827-ADB3-C42FAF0305CD',
 '573209B7-3B14-3526-961F-97542E408CE5','3D45DC36-683C-3DB2-8DA6-E2F838F62A7F','64F97BB0-96CF-34A5-A0E4-261E1CC6132C','4DBD6B43-FC93-3573-8CBB-4CEFD621364C']
for w in want: print(w, 'in old KC:', kc.count(uuid.UUID(w).bytes))
# the original 42-byte probes still valid on the old pair?
for o in (0x509100, 0x509800, 0x509e00): print('orig probe %#x: bin %d kc %d' % (o, gpu.count(gpu[o:o+64]), kc.count(gpu[o:o+64])))
t = [s for s in macho.parse(gpu)['secs'] if s['sect'] == '__text'][0]
lo, hi = t['off'], t['off'] + t['size']; print('__text file range %#x..%#x' % (lo, hi))
def ok(o): w = gpu[o:o+64]; return lo <= o and o + 64 <= hi and gpu.count(w) == 1 and kc.count(w) == 1
pick = []
for target, rng in ((0.10, range(0x80000, 0x100000, 0x100)), (0.50, None), (0.90, None)):
    if rng is None:
        c = lo + int((hi - lo) * target) & ~0xff
        rng = list(range(c, hi - 64, 0x100)) 
    for o in rng:
        if ok(o): pick.append(o); break
txt = ''.join('%#x 0x40\n' % o for o in pick)
print('picked', [hex(p) for p in pick], 'len', len(txt)); print(repr(txt))
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'probes.new'), 'w', newline='\n').write(txt)
