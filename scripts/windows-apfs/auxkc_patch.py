# Patch NMXGPU's weak proc_starttime call out of the installed AuxKC, in place, on the raw APFS partition.
# Two bytes, je -> jmp (always take the "no proc_starttime" path, start = 0). File size, metadata and B-trees are
# untouched: APFS checksums metadata objects only, not file data. Usage: auxkc_patch.py dry|apply
import os, sys, io, time, struct, datetime
mode = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, 'apfs_pull.py'), encoding='utf-8').read()
src = src[:src.index("pers = '/private")].replace("'pull2.log'", "'patch_%s.log'" % mode)
g = {'__file__': os.path.join(here, 'apfs_pull.py')}
exec(compile(src, 'apfs_pull.py', 'exec'), g)
P, data, fs = g['P'], g['data'], g['fs']
BS = fs.block_size
PATH = '/Library/KernelCollections/AuxiliaryKernelExtensions.kc'
# file offset, expected bytes at that offset (je rel8 + following context), patched first byte
SITES = [(0x7c5907, bytes.fromhex('7428488b0d'), 0xeb),
         (0x7c7170, bytes.fromhex('7437ba00000000'), 0xeb)]
local = open(os.path.join(here, 'apfs_out9', 'KC_AuxiliaryKernelExtensions.kc'), 'rb').read()
ino = data.get(PATH)
P('inode', ino.oid if hasattr(ino, 'oid') else '?', 'size', ino.size, 'compressed', ino.is_compressed(), 'mtime', ino.mtime)
if ino.is_compressed() or ino.size != len(local) or data.is_encrypted:
    P('ABORT: compressed/size/encrypted'); sys.exit(2)
st = ino.open()
plan = []
for off, exp, new in SITES:
    la, pa, ln, cid = st._lookup(off)
    phys_block = pa + (off - la) // BS
    in_blk = (off - la) % BS
    via_fs = st._read(off - in_blk, BS) if False else None
    st.seek(off - (off % BS)); via_fs = st.read(BS)
    raw = fs._read_block(phys_block, 1)
    P('site %#x: extent logical %#x phys %#x len %#x -> block %#x (+%#x)' % (off, la, pa, ln, phys_block, in_blk))
    ok = raw == via_fs == local[off - off % BS: off - off % BS + BS] and raw[in_blk:in_blk + len(exp)] == exp
    P('  raw==fs==local and pattern ok:', ok, raw[in_blk:in_blk + 8].hex())
    if not ok: P('ABORT'); sys.exit(3)
    if (off - la) % BS != off % BS: P('ABORT: extent not block aligned'); sys.exit(4)
    plan.append((phys_block, in_blk, new, raw))
if mode != 'apply':
    P('DRY OK'); sys.exit(0)
stamp = datetime.datetime.now().strftime('%Y%m%dT%H%M%S')
for pb, ib, new, raw in plan:
    open(os.path.join(here, 'auxkc_block_%x_%s.orig' % (pb, stamp)), 'wb').write(raw)
g['fs'].fh  # reader stays open read-only; write through a separate handle
w = open(g['DEV'], 'r+b', buffering=0)
for pb, ib, new, raw in plan:
    blk = bytearray(raw); blk[ib] = new
    w.seek(pb * BS); n = w.write(bytes(blk)); P('wrote block %#x: %d bytes' % (pb, n))
w.close()
r = open(g['DEV'], 'rb', buffering=0)
for pb, ib, new, raw in plan:
    r.seek(pb * BS); back = r.read(BS)
    P('verify block %#x: byte now %02x, rest unchanged %s' % (pb, back[ib], back[:ib] == raw[:ib] and back[ib+1:] == raw[ib+1:]))
r.close()
P('APPLY DONE')
