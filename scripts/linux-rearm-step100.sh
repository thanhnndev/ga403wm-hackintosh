#!/bin/bash
# Step100b: the Step100 boot ran without NMXGPU. The installer's relink was good, but kernelmanagerd replaced the AuxKC
# 7 s later (NMXBacklight was a new kext in /Library/Extensions) with a collection built from its own list, which has no
# NMXGPU and no NMXAGDC (docs/890M-TRACE.md Step100b). Nothing in the Step100 kexts changes here: this only re-arms the
# one-shot relink, which now checks the collection again after kernelmanagerd has had time to act and rebuilds it if
# it was replaced, and reboots by itself once the collection holds NMXGPU, NMXAccel, NMXAGDC and NMXBacklight.
#
#   pkexec scripts/linux-rearm-step100.sh
set -euo pipefail
DEV=${DEV:-/dev/nvme0n1p4}
MNT=${MNT:-/mnt/macos-rw}
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
RESULT=d4830f51a1f71664a9ed8e38d33b2327b818f84f75a0d2ce6807f4b729b17848
BL_SHA=8a57847a2892121e7a955429393ac4c940b6430c9bbc70a655947689dbdb150e
[[ $EUID == 0 ]] || { echo "run with pkexec or sudo"; exit 1; }

for t in $(findmnt -rn -S "$DEV" -o TARGET | tac); do umount "$t"; echo "unmounted $t"; done
mkdir -p "$MNT"
mount -t apfs -o readwrite,uid=0,gid=0,vol=0 "$DEV" "$MNT"
findmnt -rn -T "$MNT" -o OPTIONS | tr ',' '\n' | grep -qx rw || { echo "not rw: $(findmnt -rn -T "$MNT" -o OPTIONS)"; exit 1; }

E="$MNT/Library/Extensions"
[[ $(sha256sum "$E/NMXGPU.kext/Contents/MacOS/NMXGPU" | cut -d' ' -f1) == "$RESULT" ]] \
    || { echo "NMXGPU is not the Step100 build -- not arming"; umount "$MNT"; exit 1; }
[[ $(sha256sum "$E/NMXBacklight.kext/Contents/MacOS/NMXBacklight" | cut -d' ' -f1) == "$BL_SHA" ]] \
    || { echo "NMXBacklight is not the reviewed build -- not arming"; umount "$MNT"; exit 1; }
for k in NMXAccel NMXAGDC; do [[ -f "$E/$k.kext/Contents/MacOS/$k" ]] || { echo "$k missing"; umount "$MNT"; exit 1; }; done

BK="$MNT/Library/NullMoth/step100b-$TS"
mkdir -p "$BK"
cp -a "$MNT/Library/KernelCollections/AuxiliaryKernelExtensions.kc" "$BK/"
cp -a "$MNT/private/var/db/KernelExtensionManagement/AuxKC/CurrentAuxKC/com.apple.kcgen.instructions.plist" "$BK/" 2>/dev/null || true
echo "backup $BK (the kernelmanagerd collection without NMXGPU)"

S="$MNT/Library/StrixGraphicsFix"
mkdir -p "$S"
install -o 0 -g 0 -m 755 "$HERE/nmx-relink/nmx-relink.sh" "$S/nmx-relink.sh"
install -o 0 -g 0 -m 644 "$HERE/nmx-relink/com.itlmt7925.nmx-relink.plist" "$MNT/Library/LaunchDaemons/com.itlmt7925.nmx-relink.plist"
rm -f "$S/nmx-relink.done" "$S/nmx-relink.status" "$S/nmx-relink.log"
# An earlier relink ran "launchctl disable", and launchd skips a disabled label even with its plist back (Step78).
python3 -I - "$MNT/private/var/db/com.apple.xpc.launchd/disabled.plist" <<'PY'
import plistlib, sys
p = sys.argv[1]
d = plistlib.load(open(p, 'rb'))
if d.pop('com.itlmt7925.nmx-relink', None) is not None:
    plistlib.dump(d, open(p, 'wb')); print('nmx-relink: enabled again in launchd')
PY
date -u >"$S/nmx-relink.reboot"
sync
umount "$MNT"
echo "armed: boot macOS once (relink + 45 s on-disk check, ~2-3 min, then it reboots by itself); log in on the boot after that"
