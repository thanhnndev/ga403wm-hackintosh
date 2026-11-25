#!/bin/bash
# Step90: map write-combined / uncached GPU memory one physically contiguous range at a time (docs/890M-TRACE.md
# Step90). On top of the Step89 NMXGPU (sha256 47eec16d...).
#
#   pkexec scripts/linux-patch-nmx-step90.sh
#
# A multi-range physical IOMemoryDescriptor makes xnu set the cache mode on the PHYSICAL page (every PTE of it) at
# each mapping and reset it to write-back when any such mapping dies, so WC user maps turned write-back under RADV
# once Step89's TTM order 0 made every BO multi-range. The cave (scripts/nmx-wcsplit/cave.s, at 0x5aac00 in the dead
# SI dpm code) replaces nmx_xnu_map_user / nmx_xnu_unmap_user / nmx_xnu_map_pages / nmx_xnu_unmap: WC/UC page lists
# with more than one range get a VA reservation plus one single-range (contiguous, block-mapped) mapping per range.
set -euo pipefail
DEV=${DEV:-/dev/nvme0n1p4}
MNT=${MNT:-/mnt/macos-rw}
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
STEP89=47eec16d24b42bedfbc67a8f38079c7ca2b698c5140b513d955ff1501b77fd30
STEP90=c9bf8730c975d1c1aa5974b316329955eb0cdce7f2cc1995c09bd8796b5bf693
[[ $EUID == 0 ]] || { echo "run with pkexec or sudo"; exit 1; }
[[ $(sha256sum "$HERE/nmx-wcsplit/cave.bin" | cut -d' ' -f1) == 087a7687d33062872db3d3df01ac67a447c9b1a7b59b3a7a6c3837ce98060736 ]] \
    || { echo "cave.bin is not the reviewed build"; exit 1; }

for t in $(findmnt -rn -S "$DEV" -o TARGET | tac); do umount "$t"; echo "unmounted $t"; done
mkdir -p "$MNT"
mount -t apfs -o readwrite,uid=0,gid=0,vol=0 "$DEV" "$MNT"
findmnt -rn -T "$MNT" -o OPTIONS | tr ',' '\n' | grep -qx rw || { echo "not rw: $(findmnt -rn -T "$MNT" -o OPTIONS)"; exit 1; }

E="$MNT/Library/Extensions"
BIN="$E/NMXGPU.kext/Contents/MacOS/NMXGPU"
CUR=$(sha256sum "$BIN" | cut -d' ' -f1)
[[ $CUR == "$STEP89" || $CUR == "$STEP90" ]] || { echo "NMXGPU is $CUR, not the Step89 build -- not touching it"; umount "$MNT"; exit 1; }

BK="$MNT/Library/NullMoth/nmx-step90-$TS"
mkdir -p "$BK/Library/KernelCollections"
cp -a "$E/NMXGPU.kext" "$BK/"
cp -a "$MNT/Library/KernelCollections/AuxiliaryKernelExtensions.kc" "$BK/Library/KernelCollections/"
echo "backup $BK"

python3 -I "$HERE/nmx-wcsplit/step90_patch.py" "$BIN" "$HERE/nmx-wcsplit/cave.bin"
[[ $(sha256sum "$BIN" | cut -d' ' -f1) == "$STEP90" ]] || { echo "patched NMXGPU has an unexpected hash"; exit 1; }
echo "NMXGPU $STEP90"

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
