# Restore the 14:29 good boot set (AuxKC 07:18Z, NMXGPU 591E7D5A, StrixS0ix 0.1.12, probes) in place on the raw APFS
# partition. Only file data inside existing extents is written: sizes, mtimes, metadata and B-trees stay as they are
# (APFS checksums metadata, not file data). A shorter source is padded (Mach-O: zeros; plist: newlines).
# Usage: apfs_restore.py dry|apply
import os, sys, hashlib, datetime
mode = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, 'apfs_pull.py'), encoding='utf-8').read()
src = src[:src.index("pers = '/private")].replace("'pull2.log'", "'restore_%s.log'" % mode)
g = {'__file__': os.path.join(here, 'apfs_pull.py')}
exec(compile(src, 'apfs_pull.py', 'exec'), g)
P, data, fs = g['P'], g['data'], g['fs']
BS = fs.block_size
D = os.path.join(here, 'apfs_out13')
rd = lambda n: open(os.path.join(D, n), 'rb').read()
BK5 = 'S_Library_NullMoth_step125-bk-20261107T083523Z_'
BK6 = 'S_Library_NullMoth_step126-bk-20261107T084026Z_'
JOBS = [  # target, current copy pulled at 18:12, source bytes, pad byte
 ('/Library/KernelCollections/AuxiliaryKernelExtensions.kc', 'T_Library_KernelCollections_AuxiliaryKernelExtensions.kc', rd(BK5 + 'AuxiliaryKernelExtensions.kc'), b'\0'),
 ('/Library/Extensions/NMXGPU.kext/Contents/MacOS/NMXGPU', 'T_Library_Extensions_NMXGPU.kext_Contents_MacOS_NMXGPU', rd(BK5 + 'NMXGPU.kext_Contents_MacOS_NMXGPU'), b'\0'),
 ('/Library/Extensions/NMXGPU.kext/Contents/Info.plist', 'T_Library_Extensions_NMXGPU.kext_Contents_Info.plist', rd(BK5 + 'NMXGPU.kext_Contents_Info.plist'), b'\n'),
 ('/Library/Extensions/StrixS0ix.kext/Contents/MacOS/StrixS0ix', 'T_Library_Extensions_StrixS0ix.kext_Contents_MacOS_StrixS0ix', rd(BK6 + 'StrixS0ix.kext_Contents_MacOS_StrixS0ix'), b'\0'),
 ('/Library/Extensions/StrixS0ix.kext/Contents/Info.plist', 'T_Library_Extensions_StrixS0ix.kext_Contents_Info.plist', rd(BK6 + 'StrixS0ix.kext_Contents_Info.plist'), b'\n'),
 ('/Library/StrixGraphicsFix/nmx-relink.probes', 'T_Library_StrixGraphicsFix_nmx-relink.probes', open(os.path.join(here, 'probes.new'), 'rb').read(), b'\n'),
]
dev = open(g['DEV'], 'rb', buffering=0)
def raw(pb, n):
    dev.seek(pb * BS); return dev.read(n * BS)
plan = []
for t, cur_name, new_src, pad in JOBS:
    ino = data.get(t); size = ino.size
    cur = rd(cur_name)
    if ino.is_compressed() or data.is_encrypted or len(cur) != size or len(new_src) > size:
        P('ABORT', t, 'compressed/encrypted/size', size, len(cur), len(new_src)); sys.exit(2)
    st = ino.open(); st.seek(0); via_fs = st.read(size)
    if via_fs != cur:
        P('ABORT', t, 'changed since the 18:12 pull'); sys.exit(3)
    new = new_src + pad * (size - len(new_src))
    off = 0; runs = []
    while off < size:
        la, pa, ln, cid = st._lookup(off)
        if la % BS or ln % BS: P('ABORT unaligned extent', t); sys.exit(4)
        nb = (min(la + ln, size) - la + BS - 1) // BS
        old = raw(pa, nb)
        if old[:min(ln, size - la)] != cur[la:la + min(ln, size - la)]:
            P('ABORT raw != fs', t, hex(pa)); sys.exit(5)
        body = new[la:la + min(ln, size - la)]
        blk = body + old[len(body):]          # keep the bytes past EOF in the last block
        runs.append((pa, old, blk))
        off = la + ln
    P('PLAN', t, 'size', size, 'src', len(new_src), 'pad', size - len(new_src), 'runs', [(hex(p), len(o) // BS) for p, o, b in runs],
      'cur sha', hashlib.sha256(cur).hexdigest()[:16], 'new sha', hashlib.sha256(new).hexdigest()[:16],
      'src sha', hashlib.sha256(new_src).hexdigest()[:16], 'changed blocks',
      sum(1 for p, o, b in runs for i in range(0, len(o), BS) if o[i:i+BS] != b[i:i+BS]))
    plan.append((t, size, new, runs))
dev.close()
if mode != 'apply':
    P('DRY OK'); sys.exit(0)
stamp = datetime.datetime.now().strftime('%Y%m%dT%H%M%S')
bk = os.path.join(here, 'restore_bk_' + stamp); os.makedirs(bk)
for t, size, new, runs in plan:
    for pa, old, blk in runs:
        open(os.path.join(bk, '%s_%x.blk' % (os.path.basename(t), pa)), 'wb').write(old)
P('raw backups in', bk)
w = open(g['DEV'], 'r+b', buffering=0)
for t, size, new, runs in plan:
    for pa, old, blk in runs:
        for i in range(0, len(blk), 1 << 20):
            w.seek(pa * BS + i); n = w.write(blk[i:i + (1 << 20)])
            if n != len(blk[i:i + (1 << 20)]): P('SHORT WRITE', t, hex(pa), i, n); sys.exit(6)
    P('wrote', t)
w.close()
r = open(g['DEV'], 'rb', buffering=0)
for t, size, new, runs in plan:
    good = True
    for pa, old, blk in runs:
        r.seek(pa * BS); good &= r.read(len(blk)) == blk
    P('verify raw', t, good)
r.close()
P('APPLY DONE')
