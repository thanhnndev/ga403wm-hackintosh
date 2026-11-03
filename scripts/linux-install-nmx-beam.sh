#!/bin/bash
# Step83: tearing on the OLED. NMXAccel's K6 path copies each frame into the buffer DCN is scanning out with no regard
# for the scan, so a refresh shows the top of one frame over the bottom of the last. The CI build of
# nvidia-macos-driver b5d7a79 writes the frame in 48-row bands that trail the scan (OTG0 vertical counter over BAR5).
#
#   pkexec scripts/linux-install-nmx-beam.sh <NMXAccel binary from CI>
set -euo pipefail
NEWACCEL=${1:?usage: $0 <NMXAccel binary built by CI>}
DEV=${DEV:-/dev/nvme0n1p4}
MNT=${MNT:-/mnt/macos-rw}
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
[[ $EUID == 0 ]] || { echo "run with pkexec or sudo"; exit 1; }
[[ -f $NEWACCEL ]] || { echo "no $NEWACCEL"; exit 1; }
python3 -I - "$NEWACCEL" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
if d[:4] != b'\xcf\xfa\xed\xfe': sys.exit('not a 64-bit Mach-O')
if d.count(b'\0NMXAMDFB\0') != 1 or b'is not BGRA or l10r' not in d: sys.exit('not the NMXAMDFB/l10r NMXAccel')
if b'iop: beam: OTG%u' not in d: sys.exit('CI NMXAccel predates the scan-paced copy')
print('CI NMXAccel ok')
PY

for t in $(findmnt -rn -S "$DEV" -o TARGET | tac); do umount "$t"; echo "unmounted $t"; done
mkdir -p "$MNT"
mount -t apfs -o readwrite,uid=0,gid=0,vol=0 "$DEV" "$MNT"
findmnt -rn -T "$MNT" -o OPTIONS | tr ',' '\n' | grep -qx rw || { echo "not rw: $(findmnt -rn -T "$MNT" -o OPTIONS)"; exit 1; }

E="$MNT/Library/Extensions"
BK="$MNT/Library/NullMoth/nmx-beam-$TS"
mkdir -p "$BK/Library/KernelCollections"
cp -a "$E/NMXAccel.kext" "$BK/"
cp -a "$MNT/Library/KernelCollections/AuxiliaryKernelExtensions.kc" "$BK/Library/KernelCollections/"
echo "backup $BK"
install -o 0 -g 0 -m 755 "$NEWACCEL" "$E/NMXAccel.kext/Contents/MacOS/NMXAccel"
sha256sum "$E/NMXAccel.kext/Contents/MacOS/NMXAccel"

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
echo "armed: boot macOS once (it relinks the AuxKC, ~1-2 min, then reboots by itself); log in on the boot after that"
