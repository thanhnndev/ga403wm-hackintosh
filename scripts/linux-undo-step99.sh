#!/bin/bash
# Step99 undo from Linux:
# - put back the Step98b NMXGPU that macos-install-step99.sh backed up;
# - remove the flip default daemon;
# - arm nmx-relink, which rebuilds the AuxKC on the next macOS boot and reboots by itself.
# If the Step99 boot shows no picture (DC with GPU VM), this is the way back.
#
#   pkexec scripts/linux-undo-step99.sh
set -euo pipefail
DEV=${DEV:-/dev/nvme0n1p4}
MNT=${MNT:-/mnt/macos-rw}
HERE=$(cd "$(dirname "$0")" && pwd)
[[ $EUID == 0 ]] || { echo "run with pkexec or sudo"; exit 1; }

for t in $(findmnt -rn -S "$DEV" -o TARGET | tac); do umount "$t"; echo "unmounted $t"; done
mkdir -p /mnt/macos-rw
[[ $MNT == /mnt/macos-rw ]] || { echo "MNT must be /mnt/macos-rw"; exit 1; }
mount -t apfs -o readwrite,uid=0,gid=0,vol=0 "$DEV" /mnt/macos-rw
findmnt -rn -T /mnt/macos-rw -o OPTIONS | tr ',' '\n' | grep -qx rw || { echo "not rw: $(findmnt -rn -T /mnt/macos-rw -o OPTIONS)"; exit 1; }

BK=$(ls -d /mnt/macos-rw/Library/NullMoth/step99-bk-* 2>/dev/null | sort | tail -1)
[[ -n $BK && -f $BK/NMXGPU.kext/Contents/MacOS/NMXGPU ]] || { echo "no step99 backup"; umount /mnt/macos-rw; exit 1; }
rm -rf /mnt/macos-rw/Library/Extensions/NMXGPU.kext
cp -a "$BK/NMXGPU.kext" /mnt/macos-rw/Library/Extensions/
rm -f /mnt/macos-rw/Library/LaunchDaemons/com.ga403wm.nmx-flip-default.plist
echo "restored NMXGPU from $BK: $(sha256sum /mnt/macos-rw/Library/Extensions/NMXGPU.kext/Contents/MacOS/NMXGPU | cut -c1-16); flip default daemon removed"

S=/mnt/macos-rw/Library/StrixGraphicsFix
install -o 0 -g 0 -m 755 "$HERE/nmx-relink/nmx-relink.sh" "$S/nmx-relink.sh"
install -o 0 -g 0 -m 644 "$HERE/nmx-relink/com.itlmt7925.nmx-relink.plist" /mnt/macos-rw/Library/LaunchDaemons/com.itlmt7925.nmx-relink.plist
rm -f /mnt/macos-rw/Library/StrixGraphicsFix/nmx-relink.done /mnt/macos-rw/Library/StrixGraphicsFix/nmx-relink.status /mnt/macos-rw/Library/StrixGraphicsFix/nmx-relink.log
python3 -I - /mnt/macos-rw/private/var/db/com.apple.xpc.launchd/disabled.plist <<'PY2'
import plistlib, sys
p = sys.argv[1]
d = plistlib.load(open(p, 'rb'))
if d.pop('com.itlmt7925.nmx-relink', None) is not None:
    plistlib.dump(d, open(p, 'wb')); print('nmx-relink: enabled again in launchd')
PY2
date -u >"$S/nmx-relink.reboot"
sync
umount /mnt/macos-rw
echo "armed: boot macOS once (it relinks the AuxKC, ~1-2 min, then reboots by itself)"
