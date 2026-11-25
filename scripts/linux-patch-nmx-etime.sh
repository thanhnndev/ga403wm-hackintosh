#!/bin/bash
# Step80: the desktop ran for a minute, then WindowServer died and the verbose console came back (boot 0577C74D, 266 s):
# "NVMTL: vk: fence wait -> -13 after 295 ms" -> command buffer failure -> WindowServer exit.
#
#   pkexec scripts/linux-patch-nmx-etime.sh
#
# drm_syncobj_array_wait_timeout returns -ETIME on timeout. FreeBSD's linuxkpi defines ETIME as ETIMEDOUT, so the ioctl
# fails with errno 60. Mesa (vk_drm_syncobj.c) treats only errno == ETIME as VK_TIMEOUT, and on macOS ETIME is 101, so
# any syncobj wait that times out is VK_ERROR_UNKNOWN. NVMTL waits on its fences in 250 ms slices, so the first frame
# whose fence took longer than 250 ms killed the backend, then WindowServer.
#  - NMXGPU (no CI build): the timeout value in drm_syncobj_array_wait_timeout (0x437ba6, movq $-0x3c,%r15) becomes
#    -101, the macOS ETIME. Only DRM_IOCTL_SYNCOBJ_WAIT and _TIMELINE_WAIT call it, and both return it as is.
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
BK="$MNT/Library/NullMoth/nmx-etime-$TS"
mkdir -p "$BK/Library/KernelCollections"
cp -a "$E/NMXGPU.kext" "$BK/"
cp -a "$MNT/Library/KernelCollections/AuxiliaryKernelExtensions.kc" "$BK/Library/KernelCollections/"
echo "backup $BK"

python3 -I - "$E/NMXGPU.kext/Contents/MacOS/NMXGPU" <<'PY'
import sys
p = sys.argv[1]
d = bytearray(open(p, 'rb').read())
OFF = 0x437ba6
OLD, NEW = bytes.fromhex('49c7c7c4ffffff'), bytes.fromhex('49c7c79bffffff')    # movq $-60 / $-101, %r15
cur = bytes(d[OFF:OFF + 7])
if cur == NEW:
    print(f'{p}: syncobj wait already returns ETIME'); sys.exit(0)
if cur != OLD:
    sys.exit(f'{p}: {OFF:#x} is not "movq $-ETIMEDOUT,%r15" ({cur.hex()}) -- not the expected build, not touching it')
d[OFF:OFF + 7] = NEW
open(p, 'wb').write(d)
print(f'{p}: syncobj wait timeout now returns errno 101 (macOS ETIME)')
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
