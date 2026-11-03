#!/bin/bash
# Step78: the session started after login, then the Mac panicked 40 s later: "thread_invoke: preemption_level -1, possible
# cause: unlocking an unlocked mutex or spinlock" (WindowServer, amdgpu_cs_ioctl -> amdgpu_bo_kmap -> vmap -> lck_mtx_lock).
#
#   pkexec scripts/linux-patch-nmx-mtxguard.sh
#
# On x86 xnu, lck_mtx_unlock of a free mutex is handled as the release of a mutex held in spin mode, so it calls
# enable_preemption. The CPU's preemption level drops to -1, and the next thread_block panics far from the culprit.
# xkpi's FreeBSD mutex records its owner, so nmx_mtx_unlock can tell a free mutex apart.
#  - NMXGPU (no CI build): nmx_mtx_unlock now jumps to a copy of itself in dce_v6_0_crtc_disable, which only runs on
#    SI display hardware (nmx-mtxguard/cave.s). An unlock with no owner prints
#    "NullMoth xkpi: unlock of unlocked mutex <name> (<mutex>) from <caller>" and returns without touching the lock.
#    The lock and spin paths reuse the original lck_spin_unlock, ml_set_interrupts_enabled and lck_mtx_unlock call
#    sites, so no relocation moves.
set -euo pipefail
DEV=${DEV:-/dev/nvme0n1p4}
MNT=${MNT:-/mnt/macos-rw}
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
[[ $EUID == 0 ]] || { echo "run with pkexec or sudo"; exit 1; }
for f in cave.bin jmp.bin; do [[ -f $HERE/nmx-mtxguard/$f ]] || { echo "no $HERE/nmx-mtxguard/$f"; exit 1; }; done

for t in $(findmnt -rn -S "$DEV" -o TARGET | tac); do umount "$t"; echo "unmounted $t"; done
mkdir -p "$MNT"
mount -t apfs -o readwrite,uid=0,gid=0,vol=0 "$DEV" "$MNT"
findmnt -rn -T "$MNT" -o OPTIONS | tr ',' '\n' | grep -qx rw || { echo "not rw: $(findmnt -rn -T "$MNT" -o OPTIONS)"; exit 1; }

E="$MNT/Library/Extensions"
BK="$MNT/Library/NullMoth/nmx-mtxguard-$TS"
mkdir -p "$BK/Library/KernelCollections"
cp -a "$E/NMXGPU.kext" "$BK/"
cp -a "$MNT/Library/KernelCollections/AuxiliaryKernelExtensions.kc" "$BK/Library/KernelCollections/"
echo "backup $BK"

python3 -I - "$E/NMXGPU.kext/Contents/MacOS/NMXGPU" "$HERE/nmx-mtxguard" <<'PY'
import hashlib, sys
p, dirp = sys.argv[1], sys.argv[2]
d = bytearray(open(p, 'rb').read())
patches = [
    # (offset, sha256 of the original bytes, new bytes)
    (0x156ef0, '0796f73acdba5bf7', open(dirp + '/cave.bin', 'rb').read()),   # dce_v6_0_crtc_disable
    (0x6d8850, 'fc12521a95b92cf5', open(dirp + '/jmp.bin', 'rb').read()),    # nmx_mtx_unlock entry
]
if all(bytes(d[o:o + len(n)]) == n for o, _, n in patches):
    print(f'{p}: mutex unlock guard already in'); sys.exit(0)
for o, h, n in patches:
    got = hashlib.sha256(d[o:o + len(n)]).hexdigest()
    if not got.startswith(h):
        sys.exit(f'{p}: bytes at {o:#x} are not the expected build ({got[:16]}) -- not touching it')
for o, _, n in patches:
    d[o:o + len(n)] = n
open(p, 'wb').write(d)
print(f'{p}: nmx_mtx_unlock guarded (cave at 0x156ef0)')
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
