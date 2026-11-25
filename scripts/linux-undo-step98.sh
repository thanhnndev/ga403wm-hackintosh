#!/bin/bash
# Step98 undo from Linux: put back the Step97 NMXGPU and the a24692f NMXAccel that macos-install-step98.sh backed up and arm
# nmx-relink, which rebuilds the AuxKC on the next macOS boot and reboots by itself.
#
#   pkexec scripts/linux-undo-step98.sh
set -euo pipefail
DEV=${DEV:-/dev/nvme0n1p4}
MNT=${MNT:-/mnt/macos-rw}
HERE=$(cd "$(dirname "$0")" && pwd)
[[ $EUID == 0 ]] || { echo "run with pkexec or sudo"; exit 1; }

for t in $(findmnt -rn -S "$DEV" -o TARGET | tac); do umount "$t"; echo "unmounted $t"; done
mkdir -p "$MNT"
mount -t apfs -o readwrite,uid=0,gid=0,vol=0 "$DEV" "$MNT"
findmnt -rn -T "$MNT" -o OPTIONS | tr ',' '\n' | grep -qx rw || { echo "not rw: $(findmnt -rn -T "$MNT" -o OPTIONS)"; exit 1; }

BK=$(ls -d "$MNT"/Library/NullMoth/step98-bk-* 2>/dev/null | sort | tail -1)
[[ -n $BK && -f $BK/NMXGPU.kext/Contents/MacOS/NMXGPU && -f $BK/NMXAccel.kext/Contents/MacOS/NMXAccel ]] || { echo "no step98 backup"; umount "$MNT"; exit 1; }
E="$MNT/Library/Extensions"
rm -rf "$E/NMXGPU.kext" "$E/NMXAccel.kext"
cp -a "$BK/NMXGPU.kext" "$BK/NMXAccel.kext" "$E/"
echo "restored NMXGPU from $BK: $(sha256sum "$E/NMXGPU.kext/Contents/MacOS/NMXGPU" | cut -c1-16)"

S="$MNT/Library/StrixGraphicsFix"
install -o 0 -g 0 -m 755 "$HERE/nmx-relink/nmx-relink.sh" "$S/nmx-relink.sh"
install -o 0 -g 0 -m 644 "$HERE/nmx-relink/com.itlmt7925.nmx-relink.plist" "$MNT/Library/LaunchDaemons/com.itlmt7925.nmx-relink.plist"
rm -f "$S/nmx-relink.done" "$S/nmx-relink.status" "$S/nmx-relink.log"
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
echo "armed: boot macOS once (it relinks the AuxKC, ~1-2 min, then reboots by itself)"
