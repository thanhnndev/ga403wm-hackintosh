#!/bin/bash
# Install a CI-built NMXAGDC.kext (the AGDC service for the 890M: IOPresentment's map needs it to get an AMD pipe)
# into the macOS Data volume from Linux, and arm the one-shot relink LaunchDaemon (kmutil only runs on macOS).
#
#   pkexec scripts/linux-install-nmxaccel.sh /path/to/NMXAGDC.kext
#
# The bundle comes from the `agdc` job of the build-nmxaccel.yml workflow. The first boot after this still runs the previously
# collected accelerator; the daemon relinks in that boot, and the boot after that runs this one.
set -euo pipefail
SRC=${1:?path to NMXAGDC.kext}
DEV=${DEV:-/dev/nvme0n1p4}
MNT=${MNT:-/mnt/macos-rw}
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)

[[ $EUID == 0 ]] || { echo "run with pkexec or sudo"; exit 1; }
[[ -f $SRC/Contents/MacOS/NMXAGDC && -f $SRC/Contents/Info.plist ]] || { echo "$SRC is not a kext bundle"; exit 1; }

for t in $(findmnt -rn -S "$DEV" -o TARGET | tac); do umount "$t"; echo "unmounted $t"; done
mkdir -p "$MNT"
mount -t apfs -o readwrite,vol=0 "$DEV" "$MNT"   # "rw" is accepted and ignored by this module
findmnt -rn -T "$MNT" -o OPTIONS | tr ',' '\n' | grep -qx rw || { echo "not rw: $(findmnt -rn -T "$MNT" -o OPTIONS)"; exit 1; }

E="$MNT/Library/Extensions"
BK="$MNT/Library/NullMoth/nmx-step65-$TS"
mkdir -p "$BK/Library/Extensions" "$BK/Library/KernelCollections"
[[ -d $E/NMXAGDC.kext ]] && cp -a "$E/NMXAGDC.kext" "$BK/Library/Extensions/"
cp -a "$MNT/Library/KernelCollections/AuxiliaryKernelExtensions.kc" "$BK/Library/KernelCollections/"
echo "backup $BK"


rm -rf "$E/NMXAGDC.kext"
mkdir -p "$E/NMXAGDC.kext/Contents/MacOS"
cp -a "$SRC/Contents/Info.plist" "$E/NMXAGDC.kext/Contents/Info.plist"
cp -a "$SRC/Contents/MacOS/NMXAGDC" "$E/NMXAGDC.kext/Contents/MacOS/NMXAGDC"
find "$E/NMXAGDC.kext" -type d -exec chmod 755 {} +
find "$E/NMXAGDC.kext" -type f -exec chmod 644 {} +
chmod 755 "$E/NMXAGDC.kext/Contents/MacOS/NMXAGDC"
chown -R 0:0 "$E/NMXAGDC.kext"

install -o 0 -g 0 -m 755 "$HERE/nmx-relink/nmx-relink.sh" "$MNT/Library/StrixGraphicsFix/nmx-relink.sh"
install -o 0 -g 0 -m 644 "$HERE/nmx-relink/com.itlmt7925.nmx-relink.plist" \
    "$MNT/Library/LaunchDaemons/com.itlmt7925.nmx-relink.plist"
rm -f "$MNT/Library/StrixGraphicsFix/nmx-relink.done" \
      "$MNT/Library/StrixGraphicsFix/nmx-relink.status" \
      "$MNT/Library/StrixGraphicsFix/nmx-relink.log"

sha256sum "$E/NMXAGDC.kext/Contents/MacOS/NMXAGDC"
ls -ln "$E/NMXAGDC.kext/Contents/MacOS/NMXAGDC" "$MNT/Library/LaunchDaemons/com.itlmt7925.nmx-relink.plist"
sync
umount "$MNT"
mkdir -p /mnt/macos-vol0
mount -t apfs -o ro,uid=1000,gid=1000,vol=0 "$DEV" /mnt/macos-vol0
echo "installed; reboot macOS once for the relink, then once more to load it (backup $BK)"
