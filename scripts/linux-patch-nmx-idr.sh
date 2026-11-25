#!/bin/bash
# Step79: after login WindowServer hung in drm_syncobj_create -> idr_preload -> nmx_mtx_lock on a mutex "owned by" a
# thread that no longer existed (watchdog, boot B0BE89DF), and earlier boots panicked with preemption_level -1.
#
#   pkexec scripts/linux-patch-nmx-idr.sh
#
# The same per-CPU fault as Step77. idr_preload locks linux_idr_cache[curcpu] and idr_preload_end unlocks
# linux_idr_cache[curcpu] again. sched_pin on xnu only counts, so a caller that migrates between them unlocks another
# CPU's cache mutex: either a free one (lck_mtx_unlock of an unheld mutex -> preemption level -1 -> panic), or one that
# another thread holds. Its own CPU's mutex stays locked after the thread is gone, and the next idr_preload on that CPU
# blocks forever.
#  - NMXGPU (no CI build): the 6 nmx_curcpu calls that index linux_idr_cache (idr_preload, idr_preload_end, and the
#    reserve paths of idr_get_new_locked / idr_get_new_above_locked) become "xor eax,eax", so every caller uses the
#    CPU-0 cache and the lock and unlock always hit the same mutex. idr_preload_init/uninit still set up every CPU.
set -euo pipefail
DEV=${DEV:-/dev/nvme0n1p4}
MNT=${MNT:-/mnt/macos-rw}
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
[[ $EUID == 0 ]] || { echo "run with pkexec or sudo"; exit 1; }

for t in $(findmnt -rn -S "$DEV" -o TARGET | tac); do umount "$t"; echo "unmounted $t"; done
mkdir -p "$MNT"
mount -t apfs -o readwrite,uid=0,gid=0,vol=0 "$DEV" "$MNT"
findmnt -rn -T "$MNT" -o OPTIONS | tr ',' '\n' | grep -qx rw || { echo "not rw: $(findmnt -rn -T "$MNT" -o OPTIONS)"; exit 1; }

E="$MNT/Library/Extensions"
BK="$MNT/Library/NullMoth/nmx-idr-$TS"
mkdir -p "$BK/Library/KernelCollections"
cp -a "$E/NMXGPU.kext" "$BK/"
cp -a "$MNT/Library/KernelCollections/AuxiliaryKernelExtensions.kc" "$BK/Library/KernelCollections/"
echo "backup $BK"

python3 -I - "$E/NMXGPU.kext/Contents/MacOS/NMXGPU" <<'PY'
import struct, sys
p = sys.argv[1]
d = bytearray(open(p, 'rb').read())
CURCPU = 0x6d7970
SITES = (0x6bc632, 0x6bc6d6, 0x6bce85, 0x6bcfe9, 0x6bd27e, 0x6bd3f2)
NEW = bytes.fromhex('31c00f1f00')    # xor eax,eax ; nopl (rax)
todo = []
for o in SITES:
    cur = bytes(d[o:o + 5])
    if cur == NEW: continue
    if cur[0] != 0xe8 or o + 5 + struct.unpack('<i', cur[1:])[0] != CURCPU:
        sys.exit(f'{p}: {o:#x} is not "call nmx_curcpu" ({cur.hex()}) -- not the expected build, not touching it')
    todo.append(o)
if not todo:
    print(f'{p}: idr cache already CPU 0'); sys.exit(0)
for o in todo: d[o:o + 5] = NEW
open(p, 'wb').write(d)
print(f'{p}: {len(todo)} idr cache lookups now use CPU 0')
PY
sha256sum "$E/NMXGPU.kext/Contents/MacOS/NMXGPU"

S="$MNT/Library/StrixGraphicsFix"
install -o 0 -g 0 -m 755 "$HERE/nmx-relink/nmx-relink.sh" "$S/nmx-relink.sh"
install -o 0 -g 0 -m 644 "$HERE/nmx-relink/com.itlmt7925.nmx-relink.plist" "$MNT/Library/LaunchDaemons/com.itlmt7925.nmx-relink.plist"
rm -f "$S/nmx-relink.done" "$S/nmx-relink.status" "$S/nmx-relink.log"
# An earlier relink ran "launchctl disable", and launchd skips a disabled label even with its plist back (Step78).
python3 -I - "$MNT/private/var/db/com.apple.xpc.launchd/disabled.plist" <<'PY2'
import plistlib, sys
p = sys.argv[1]
d = plistlib.load(open(p, 'rb'))
if d.pop('com.itlmt7925.nmx-relink', None) is not None:
    plistlib.dump(d, open(p, 'wb')); print('nmx-relink: enabled again in launchd')
PY2
date -u >"$S/nmx-relink.reboot"
sync
umount "$MNT"
echo "armed: boot macOS once (it relinks the AuxKC, ~1-2 min, then reboots by itself); log in on the boot after that"
