#!/bin/bash
# Step100c: black screen after Step100. The irqfix state words (ST[], 23 u64 at 0x927010..0x9270c8) overlapped the
# Step99 flip state at 0x9270a0: ST[18] (H_MAXJ) is the flip lock, so the first page flip spun forever inside the
# display-pipe gate, WindowServer blocked behind it and the userspace watchdog panicked the Mac (docs/890M-TRACE.md
# Step100c). scripts/nmx-irqfix/st_move.py moves ST[] to 0x927208 (dead CI dpm state), changing only the 69 rip
# displacements in the irqfix cave: NMXGPU d4830f51 -> 3e1b6619. Then the one-shot relink is re-armed (it checks the
# collection again 45 s later and also checks the patched NMXGPU bytes, since the UUID does not change).
#
#   pkexec scripts/linux-patch-step100c.sh
set -euo pipefail
DEV=${DEV:-/dev/nvme0n1p4}
MNT=${MNT:-/mnt/macos-rw}
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
FROM=d4830f51a1f71664a9ed8e38d33b2327b818f84f75a0d2ce6807f4b729b17848
RESULT=3e1b661990d08e35ad129fceafb2c62b3d53c72eb6278abe6b8f7481f5edfbe1
[[ $EUID == 0 ]] || { echo "run with pkexec or sudo"; exit 1; }

for t in $(findmnt -rn -S "$DEV" -o TARGET | tac); do umount "$t"; echo "unmounted $t"; done
mkdir -p "$MNT"
mount -t apfs -o readwrite,uid=0,gid=0,vol=0 "$DEV" "$MNT"
findmnt -rn -T "$MNT" -o OPTIONS | tr ',' '\n' | grep -qx rw || { echo "not rw: $(findmnt -rn -T "$MNT" -o OPTIONS)"; exit 1; }

G="$MNT/Library/Extensions/NMXGPU.kext/Contents/MacOS/NMXGPU"
CUR=$(sha256sum "$G" | cut -d' ' -f1)
if [[ $CUR != "$RESULT" ]]; then
    [[ $CUR == "$FROM" ]] || { echo "NMXGPU is $CUR, not the Step100 build -- not touching it"; umount "$MNT"; exit 1; }
    BK="$MNT/Library/NullMoth/step100c-bk-$TS"
    mkdir -p "$BK"
    cp -a "$MNT/Library/Extensions/NMXGPU.kext" "$BK/"
    cp -a "$MNT/Library/KernelCollections/AuxiliaryKernelExtensions.kc" "$BK/"
    echo "backup $BK"
    T="$G.step100c"
    cp -p "$G" "$T"
    python3 -I "$HERE/nmx-irqfix/st_move.py" "$T"
    [[ $(sha256sum "$T" | cut -d' ' -f1) == "$RESULT" ]] || { echo "patched NMXGPU is not $RESULT"; rm -f "$T"; umount "$MNT"; exit 1; }
    mv -f "$T" "$G"
fi
sha256sum "$G"

S="$MNT/Library/StrixGraphicsFix"
mkdir -p "$S"
install -o 0 -g 0 -m 755 "$HERE/nmx-relink/nmx-relink.sh" "$S/nmx-relink.sh"
install -o 0 -g 0 -m 644 "$HERE/nmx-relink/com.itlmt7925.nmx-relink.plist" "$MNT/Library/LaunchDaemons/com.itlmt7925.nmx-relink.plist"
printf '0x509100 0x40\n0x509800 0x40\n0x509e00 0x40\n' >"$S/nmx-relink.probes"
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
echo "armed: boot macOS once (relink + checks, ~2-3 min, then it reboots by itself); log in on the boot after that"
