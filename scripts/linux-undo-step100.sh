#!/bin/bash
# Step100 undo from Linux:
# - put back the Step99 NMXGPU that macos-install-step100.sh backed up;
# - remove NMXBacklight.kext;
# - put back the NVMTLDriver plugin from its newest backup;
# - arm nmx-relink, which rebuilds the AuxKC on the next macOS boot and reboots by itself.
# If the Step100 boot hangs or shows no picture, this is the way back.
#
#   pkexec scripts/linux-undo-step100.sh
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

BK=$(ls -d /mnt/macos-rw/Library/NullMoth/step100-bk-* 2>/dev/null | sort | tail -1)
[[ -n $BK && -f $BK/NMXGPU.kext/Contents/MacOS/NMXGPU ]] || { echo "no step100 backup"; umount /mnt/macos-rw; exit 1; }
rm -rf /mnt/macos-rw/Library/Extensions/NMXGPU.kext
cp -a "$BK/NMXGPU.kext" /mnt/macos-rw/Library/Extensions/
rm -rf /mnt/macos-rw/Library/Extensions/NMXBacklight.kext
PB=$(ls -d /mnt/macos-rw/Library/NullMoth/nvmtl-plugin-* 2>/dev/null | sort | tail -1)
if [[ -n $PB && -d $PB/NVMTLDriver.bundle ]]; then
    rm -rf /mnt/macos-rw/Library/GPUBundles/NVMTLDriver.bundle
    cp -a "$PB/NVMTLDriver.bundle" /mnt/macos-rw/Library/GPUBundles/
    echo "plugin restored from $PB"
fi
echo "restored NMXGPU from $BK: $(sha256sum /mnt/macos-rw/Library/Extensions/NMXGPU.kext/Contents/MacOS/NMXGPU | cut -c1-16); NMXBacklight removed"

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
