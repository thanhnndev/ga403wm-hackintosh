#!/bin/bash
# Install a CI-built NMXAccel.kext into the macOS Data volume from Linux, and arm a one-shot LaunchDaemon that
# rebuilds the auxiliary kernel collection at the next macOS boot (kmutil only runs on macOS).
#
#   pkexec scripts/linux-install-nmxaccel.sh /path/to/NMXAccel.kext
#
# The bundle must come from the build-nmxaccel.yml workflow (it sets NMXDisplayPipeEnabled, which nmxArm() reads) or
# from build/nmxaccel_build.sh plus that same plist key. The first boot after this still runs the previously
# collected accelerator; the daemon relinks in that boot, and the boot after that runs this one.
set -euo pipefail
SRC=${1:?path to NMXAccel.kext}
DEV=${DEV:-/dev/nvme0n1p4}
MNT=${MNT:-/mnt/macos-rw}
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)

[[ $EUID == 0 ]] || { echo "run with pkexec or sudo"; exit 1; }
[[ -f $SRC/Contents/MacOS/NMXAccel && -f $SRC/Contents/Info.plist ]] || { echo "$SRC is not a kext bundle"; exit 1; }

for t in $(findmnt -rn -S "$DEV" -o TARGET | tac); do umount "$t"; echo "unmounted $t"; done
mkdir -p "$MNT"
mount -t apfs -o readwrite,vol=0 "$DEV" "$MNT"   # "rw" is accepted and ignored by this module
findmnt -rn -T "$MNT" -o OPTIONS | tr ',' '\n' | grep -qx rw || { echo "not rw: $(findmnt -rn -T "$MNT" -o OPTIONS)"; exit 1; }

E="$MNT/Library/Extensions"
BK="$MNT/Library/NullMoth/nmx-step60-$TS"
mkdir -p "$BK/Library/Extensions" "$BK/Library/KernelCollections"
cp -a "$E/NMXAccel.kext" "$BK/Library/Extensions/"
cp -a "$MNT/Library/KernelCollections/AuxiliaryKernelExtensions.kc" "$BK/Library/KernelCollections/"
echo "backup $BK"
sha256sum "$BK/Library/Extensions/NMXAccel.kext/Contents/MacOS/NMXAccel"

rm -rf "$E/NMXAccel.kext"
mkdir -p "$E/NMXAccel.kext/Contents/MacOS"
cp -a "$SRC/Contents/Info.plist" "$E/NMXAccel.kext/Contents/Info.plist"
cp -a "$SRC/Contents/MacOS/NMXAccel" "$E/NMXAccel.kext/Contents/MacOS/NMXAccel"
find "$E/NMXAccel.kext" -type d -exec chmod 755 {} +
find "$E/NMXAccel.kext" -type f -exec chmod 644 {} +
chmod 755 "$E/NMXAccel.kext/Contents/MacOS/NMXAccel"
chown -R 0:0 "$E/NMXAccel.kext"

install -o 0 -g 0 -m 755 "$HERE/nmx-relink/nmx-relink.sh" "$MNT/Library/StrixGraphicsFix/nmx-relink.sh"
install -o 0 -g 0 -m 644 "$HERE/nmx-relink/com.itlmt7925.nmx-relink.plist" \
    "$MNT/Library/LaunchDaemons/com.itlmt7925.nmx-relink.plist"
rm -f "$MNT/Library/StrixGraphicsFix/nmx-relink.done" \
      "$MNT/Library/StrixGraphicsFix/nmx-relink.status" \
      "$MNT/Library/StrixGraphicsFix/nmx-relink.log"

sha256sum "$E/NMXAccel.kext/Contents/MacOS/NMXAccel"
ls -ln "$E/NMXAccel.kext/Contents/MacOS/NMXAccel" "$MNT/Library/LaunchDaemons/com.itlmt7925.nmx-relink.plist"
sync
umount "$MNT"
mkdir -p /mnt/macos-vol0
mount -t apfs -o ro,uid=1000,gid=1000,vol=0 "$DEV" /mnt/macos-vol0
echo "installed; reboot macOS once for the relink, then once more to load it (backup $BK)"
