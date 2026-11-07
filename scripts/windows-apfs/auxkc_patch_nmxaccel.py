# Step128: NMXAccel deliverModeChange skips display_mode_will/did_change while its framebuffer is not open yet
# (fFB->fPrivate->controller == NULL; IOFramebuffer::getAttributeExt dereferences it with no test, the 10.15 s panic).
# The two ALOG calls at the start of deliverModeChange (KC 0xcff4e..0xcff88, 58 bytes) are replaced by the test.
# In place on the raw APFS partition, like auxkc_patch.py. Usage: auxkc_patch_nmxaccel.py dry|apply <local AuxKC copy>
import os, sys, datetime
mode, localpath = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, 'apfs_pull.py'), encoding='utf-8').read()
src = src[:src.index("pers = '/private")].replace("'pull2.log'", "'patchacc_%s.log'" % mode)
g = {'__file__': os.path.join(here, 'apfs_pull.py')}
exec(compile(src, 'apfs_pull.py', 'exec'), g)
P, data, fs = g['P'], g['data'], g['fs']
BS = fs.block_size
PATH = '/Library/KernelCollections/AuxiliaryKernelExtensions.kc'
OFF = 0xcff4e
ORIG = bytes.fromhex('4889fb418bb70c010000418b97080100004c8d355e5e00004c89f731c0e80a85f4ff'
                     '418bb70c010000418b97080100004c89f731c0e87880f4ff')
NEW = bytes.fromhex('4889fb'            # mov rbx, rdi
                    '488b8720100000'    # mov rax, [rdi+0x1020]   fFB
                    '4885c0' '0f84a7010000'          # NULL -> return (0xd0108)
                    '488b80c8010000'    # mov rax, [rax+0x1c8]    IOFramebuffer fPrivate
                    '4885c0' '0f8497010000'
                    '48833800' '0f848d010000'        # controller NULL (not opened) -> return
                    'eb0b' + '90' * 11)              # jmp 0xcff88 (the original will_change call)
assert len(ORIG) == len(NEW) == 58
local = open(localpath, 'rb').read()
ino = data.get(PATH)
P('size', ino.size, 'compressed', ino.is_compressed(), 'mtime', ino.mtime)
if ino.is_compressed() or ino.size != len(local) or data.is_encrypted: P('ABORT: compressed/size/encrypted'); sys.exit(2)
st = ino.open()
la, pa, ln, cid = st._lookup(OFF)
if (OFF - la) % BS != OFF % BS: P('ABORT: extent not block aligned'); sys.exit(4)
pb = pa + (OFF - la) // BS; ib = (OFF - la) % BS
if ib + len(NEW) > BS: P('ABORT: spans blocks'); sys.exit(5)
st.seek(OFF - OFF % BS); via_fs = st.read(BS)
raw = fs._read_block(pb, 1)
P('extent logical %#x phys %#x len %#x -> block %#x (+%#x)' % (la, pa, ln, pb, ib))
cur = raw[ib:ib + 58]
P('raw==fs==local', raw == via_fs == local[OFF - OFF % BS: OFF - OFF % BS + BS], 'current', 'ORIG' if cur == ORIG else 'NEW' if cur == NEW else cur.hex())
if not (raw == via_fs == local[OFF - OFF % BS: OFF - OFF % BS + BS] and cur == ORIG): P('ABORT'); sys.exit(3)
if mode != 'apply': P('DRY OK'); sys.exit(0)
stamp = datetime.datetime.now().strftime('%Y%m%dT%H%M%S')
open(os.path.join(os.path.dirname(os.path.abspath(localpath)), 'auxkc_block_%x_%s.orig' % (pb, stamp)), 'wb').write(raw)
blk = bytearray(raw); blk[ib:ib + 58] = NEW
w = open(g['DEV'], 'r+b', buffering=0); w.seek(pb * BS); P('wrote', w.write(bytes(blk))); w.close()
r = open(g['DEV'], 'rb', buffering=0); r.seek(pb * BS); back = r.read(BS); r.close()
P('verify: patch present', back[ib:ib + 58] == NEW, 'rest unchanged', back[:ib] == raw[:ib] and back[ib + 58:] == raw[ib + 58:])
P('APPLY DONE')
