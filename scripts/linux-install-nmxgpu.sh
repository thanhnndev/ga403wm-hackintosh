#!/bin/bash
# Install a rebuilt NMXGPU binary into the macOS Data volume from Linux and arm the one-shot AuxKC relink daemon.
#
#   pkexec scripts/linux-install-nmxgpu.sh /path/to/NMXGPU      # the Mach-O, not the bundle
#
# Only the executable is replaced: the installed Info.plist carries keys (NMXOwnsDisplay on the AMD personality) that a
# fresh build's plist does not. The first macOS boot afterwards relinks the collection, the second one loads it.
set -euo pipefail
SRC=${1:?path to the NMXGPU Mach-O}
DEV=${DEV:-/dev/nvme0n1p4}
MNT=${MNT:-/mnt/macos-rw}
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)

[[ $EUID == 0 ]] || { echo "run with pkexec or sudo"; exit 1; }
[[ -f $SRC ]] || { echo "$SRC is not a file"; exit 1; }
file "$SRC" | grep -q 'Mach-O 64-bit' || { echo "$SRC is not a Mach-O"; exit 1; }

for t in $(findmnt -rn -S "$DEV" -o TARGET | tac); do umount "$t"; echo "unmounted $t"; done
mkdir -p "$MNT"
mount -t apfs -o readwrite,vol=0 "$DEV" "$MNT"
findmnt -rn -T "$MNT" -o OPTIONS | tr ',' '\n' | grep -qx rw || { echo "not rw: $(findmnt -rn -T "$MNT" -o OPTIONS)"; exit 1; }

E="$MNT/Library/Extensions"
BK="$MNT/Library/NullMoth/nmxgpu-step69-$TS"
mkdir -p "$BK/Library/Extensions" "$BK/Library/KernelCollections"
cp -a "$E/NMXGPU.kext" "$BK/Library/Extensions/"
cp -a "$MNT/Library/KernelCollections/AuxiliaryKernelExtensions.kc" "$BK/Library/KernelCollections/"
echo "backup $BK"
sha256sum "$BK/Library/Extensions/NMXGPU.kext/Contents/MacOS/NMXGPU"

install -o 0 -g 0 -m 755 "$SRC" "$E/NMXGPU.kext/Contents/MacOS/NMXGPU"
install -o 0 -g 0 -m 755 "$HERE/nmx-relink/nmx-relink.sh" "$MNT/Library/StrixGraphicsFix/nmx-relink.sh"
install -o 0 -g 0 -m 644 "$HERE/nmx-relink/com.itlmt7925.nmx-relink.plist" \
    "$MNT/Library/LaunchDaemons/com.itlmt7925.nmx-relink.plist"
rm -f "$MNT/Library/StrixGraphicsFix/nmx-relink.done" \
      "$MNT/Library/StrixGraphicsFix/nmx-relink.status" \
      "$MNT/Library/StrixGraphicsFix/nmx-relink.log"

sha256sum "$E/NMXGPU.kext/Contents/MacOS/NMXGPU"
sync
umount "$MNT"
echo "installed; reboot macOS once for the relink, then once more to load it (backup $BK)"
