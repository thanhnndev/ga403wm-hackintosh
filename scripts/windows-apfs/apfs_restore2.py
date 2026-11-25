# Put the 20:36 good boot set back (NMXGPU 591E7D5A cave chain + its AuxKC + Info.plist + probes) from the Step125
# installer's own backup /Library/NullMoth/step125-bk-20261107T135605Z, in place on the raw APFS partition (file data
# inside existing extents only; a shorter source is padded: Mach-O zeros, plist/probes newlines).
# Refuses when a target block is shared with any other file under /Library/{NullMoth,StrixGraphicsFix,KernelCollections,
# Extensions} or the out-6 build. Usage: apfs_restore2.py dry|apply
import os, sys, hashlib, datetime
mode = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, 'apfs_pull.py'), encoding='utf-8').read()
src = src[:src.index("pers = '/private")].replace("'pull2.log'", "'restore2_%s.log'" % mode)
g = {'__file__': os.path.join(here, 'apfs_pull.py')}
exec(compile(src, 'apfs_pull.py', 'exec'), g)
P, data, fs, ls = g['P'], g['data'], g['fs'], g['ls']
BS = fs.block_size
BK = '/Library/NullMoth/step125-bk-20261107T135605Z'
JOBS = [('/Library/KernelCollections/AuxiliaryKernelExtensions.kc', BK + '/AuxiliaryKernelExtensions.kc', b'\0'),
        ('/Library/Extensions/NMXGPU.kext/Contents/MacOS/NMXGPU', BK + '/NMXGPU.kext/Contents/MacOS/NMXGPU', b'\0'),
        ('/Library/Extensions/NMXGPU.kext/Contents/Info.plist', BK + '/NMXGPU.kext/Contents/Info.plist', b'\n'),
        ('/Library/StrixGraphicsFix/nmx-relink.probes', BK + '/nmx-relink.probes', b'\n')]
def extents(p):
    ino = data.get(p); st = ino.open(); out = []; off = 0
    while off < ino.size:
        la, pa, ln, cid = st._lookup(off); out.append((la, pa, ln)); off = la + ln
    return ino, st, out
def walk(path, acc):
    try: rows = ls(path)
    except Exception: return acc
    for n, sz, mt in rows:
        p = path.rstrip('/') + '/' + n
        if sz == -1: walk(p, acc)
        elif sz > 0: acc.append(p)
    return acc
others = []
for d in ['/Library/NullMoth', '/Library/StrixGraphicsFix', '/Library/KernelCollections', '/Library/Extensions',
          '/Users/thanhnndev/develop/projects/nmx-build-xkpi/out-6']:
    others += walk(d, [])
targets = {t for t, s, p in JOBS}
used = {}
for p in others:
    if p in targets: continue
    try:
        for la, pa, ln in extents(p)[2]: used.setdefault(p, []).append((pa, pa + (ln + BS - 1) // BS))
    except Exception as ex: P('extent fail', p, ex)
P('other files checked', len(used))
dev = open(g['DEV'], 'rb', buffering=0)
plan = []
for t, s, pad in JOBS:
    ino, st, ex = extents(t); size = ino.size
    sino = data.get(s); sst = sino.open(); sst.seek(0); new_src = sst.read(sino.size)
    st.seek(0); cur = st.read(size)
    fl = getattr(ino.inode, 'internal_flags', None) if hasattr(ino, 'inode') else None
    if ino.is_compressed() or data.is_encrypted or len(new_src) > size or sino.is_compressed():
        P('ABORT', t, 'compressed/encrypted/size', size, len(new_src)); sys.exit(2)
    for la, pa, ln in ex:
        a, b = pa, pa + (ln + BS - 1) // BS
        for p, rs in used.items():
            for x, y in rs:
                if x < b and a < y: P('ABORT shared blocks', t, p, hex(x)); sys.exit(7)
    new = new_src + pad * (size - len(new_src))
    runs = []
    for la, pa, ln in ex:
        if la % BS: P('ABORT unaligned', t); sys.exit(4)
        n = min(ln, size - la); nb = (n + BS - 1) // BS
        dev.seek(pa * BS); old = dev.read(nb * BS)
        if old[:n] != cur[la:la + n]: P('ABORT raw != fs', t, hex(pa)); sys.exit(5)
        runs.append((pa, old, new[la:la + n] + old[n:]))
    P('PLAN', t, 'flags', fl, 'size', size, 'src', len(new_src), 'pad', size - len(new_src),
      'cur', hashlib.sha256(cur).hexdigest()[:16], 'src', hashlib.sha256(new_src).hexdigest()[:16],
      'changed blocks', sum(1 for pa, o, b in runs for i in range(0, len(o), BS) if o[i:i+BS] != b[i:i+BS]))
    plan.append((t, runs))
dev.close()
if mode != 'apply': P('DRY OK'); sys.exit(0)
stamp = datetime.datetime.now().strftime('%Y%m%dT%H%M%S')
bk = os.path.join(here, 'restore2_bk_' + stamp); os.makedirs(bk)
for t, runs in plan:
    for pa, old, blk in runs: open(os.path.join(bk, '%s_%x.blk' % (os.path.basename(t), pa)), 'wb').write(old)
P('raw backups in', bk)
w = open(g['DEV'], 'r+b', buffering=0)
for t, runs in plan:
    for pa, old, blk in runs:
        for i in range(0, len(blk), 1 << 20):
            w.seek(pa * BS + i); c = blk[i:i + (1 << 20)]
            if w.write(c) != len(c): P('SHORT WRITE', t); sys.exit(6)
    P('wrote', t)
w.close()
r = open(g['DEV'], 'rb', buffering=0)
for t, runs in plan:
    ok = True
    for pa, old, blk in runs: r.seek(pa * BS); ok &= r.read(len(blk)) == blk
    P('verify raw', t, ok)
r.close()
P('APPLY DONE')
