#!/bin/bash
# Step88: put GTT back on upstream's APU coherence model. Step40's forced write-combined GTT (nmx_gtt_wc=1) leaves
# every system-memory PTE unsnooped, while each page keeps its write-back kernel alias (nmx_kva) and userptr pages stay
# write-back in the process. This CPU has no self-snoop, so CPU and GPU disagree about memory (docs/890M-TRACE.md
# Step87). Upstream amdgpu on an APU, and the working 780M driver, use cached + SNOOPED GTT instead.
#
#   pkexec scripts/linux-patch-nmx-snoopgtt.sh
#
#  - nmx_gtt_wc (0x9255b0) 1 -> 0: amdgpu_ttm_tt_create gives ttm_cached unless the BO asked for USWC (stock), so
#    amdgpu_ttm_tt_pde_flags sets AMDGPU_PTE_SNOOPED.
#  - nmx_umap_cache (0x9264d0) 1 -> 2: user mmaps follow the TT's cache mode (stock) instead of always uncached, so a
#    cached BO is write-back everywhere and no UC alias sits next to the write-back one.
set -euo pipefail
DEV=${DEV:-/dev/nvme0n1p4}
MNT=${MNT:-/mnt/macos-rw}
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
[[ $EUID == 0 ]] || { echo "run with pkexec or sudo"; exit 1; }

for t in $(findmnt -rn -S "$DEV" -o TARGET | tac); do umount "$t"; echo "unmounted $t"; done
mkdir -p "$MNT"
mount -t apfs -o readwrite,uid=0,gid=0,vol=0 "$DEV" "$MNT"
findmnt -rn -T "$MNT" -o OPTIONS | tr ',' '\n' | grep -qx rw || { echo "not rw: $(findmnt -rn -T "$MNT" -o OPTIONS)"; exit 1; }

E="$MNT/Library/Extensions"
BK="$MNT/Library/NullMoth/nmx-snoopgtt-$TS"
mkdir -p "$BK/Library/KernelCollections"
cp -a "$E/NMXGPU.kext" "$BK/"
cp -a "$MNT/Library/KernelCollections/AuxiliaryKernelExtensions.kc" "$BK/Library/KernelCollections/"
echo "backup $BK"

python3 -I - "$E/NMXGPU.kext/Contents/MacOS/NMXGPU" <<'PY'
import sys
p = sys.argv[1]
d = bytearray(open(p, 'rb').read())
patches = [  # (offset, old, new); in __DATA the file offset equals the vmaddr
    (0x9255b0, b'\x01\0\0\0', b'\0\0\0\0'),      # nmx_gtt_wc
    (0x9264d0, b'\x01\0\0\0', b'\x02\0\0\0'),    # nmx_umap_cache
]
if all(bytes(d[o:o + 4]) == n for o, _, n in patches):
    print(f'{p}: snooped GTT already in'); sys.exit(0)
for o, old, n in patches:
    if bytes(d[o:o + 4]) not in (old, n):
        sys.exit(f'{p}: {o:#x} holds {bytes(d[o:o + 4]).hex()}, not the expected build -- not touching it')
for o, _, n in patches:
    d[o:o + 4] = n
open(p, 'wb').write(d)
print(f'{p}: nmx_gtt_wc=0, nmx_umap_cache=2')
PY
sha256sum "$E/NMXGPU.kext/Contents/MacOS/NMXGPU"

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
