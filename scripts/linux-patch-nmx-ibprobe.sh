#!/bin/bash
# Step86: after login the GFX ring times out (CP stuck inside a WindowServer IB, "Illegal register access in command
# stream" on one boot) and WindowServer dies back to the console. Every software path that could leave the IB stale was
# ruled out (docs/890M-TRACE.md Step86), so this probe tells the two remaining causes apart on the next hang:
# corrupt IB in memory versus the GPU fetching something other than what memory holds.
#
#   pkexec scripts/linux-patch-nmx-ibprobe.sh
#
#  - NMXGPU (no CI build): after the "NullMoth ringdump" line, amdgpu_coredump jumps to nmx-ibprobe/cave.s, placed over
#    si_initialize_smc_cac_tables (SI dpm only). It finds the BO behind CP_IB1_BASE through the job's VM, reads the IB
#    through the BO vmap (A, what is in memory) and through the pages' write-back physmap alias (B), parses both as PM4
#    and prints "NullMoth ibprobe" lines: where parsing stops, how many dwords differ, and the dwords around the parse
#    stop, the first difference and the CP fetch position. It only reads.
set -euo pipefail
DEV=${DEV:-/dev/nvme0n1p4}
MNT=${MNT:-/mnt/macos-rw}
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
[[ $EUID == 0 ]] || { echo "run with pkexec or sudo"; exit 1; }
for f in cave.bin jmp.bin; do [[ -f $HERE/nmx-ibprobe/$f ]] || { echo "no $HERE/nmx-ibprobe/$f"; exit 1; }; done

for t in $(findmnt -rn -S "$DEV" -o TARGET | tac); do umount "$t"; echo "unmounted $t"; done
mkdir -p "$MNT"
mount -t apfs -o readwrite,uid=0,gid=0,vol=0 "$DEV" "$MNT"
findmnt -rn -T "$MNT" -o OPTIONS | tr ',' '\n' | grep -qx rw || { echo "not rw: $(findmnt -rn -T "$MNT" -o OPTIONS)"; exit 1; }

E="$MNT/Library/Extensions"
BK="$MNT/Library/NullMoth/nmx-ibprobe-$TS"
mkdir -p "$BK/Library/KernelCollections"
cp -a "$E/NMXGPU.kext" "$BK/"
cp -a "$MNT/Library/KernelCollections/AuxiliaryKernelExtensions.kc" "$BK/Library/KernelCollections/"
echo "backup $BK"

python3 -I - "$E/NMXGPU.kext/Contents/MacOS/NMXGPU" "$HERE/nmx-ibprobe" <<'PY'
import hashlib, sys
p, dirp = sys.argv[1], sys.argv[2]
d = bytearray(open(p, 'rb').read())
patches = [
    # (offset, sha256 of the original bytes, new bytes)
    (0x5aa5a0, 'fed3ba77cf34b002', open(dirp + '/cave.bin', 'rb').read()),   # si_initialize_smc_cac_tables
    (0x17a8c, 'f88880c7ae537b08', open(dirp + '/jmp.bin', 'rb').read()),     # amdgpu_coredump after the ringdump printf
]
if all(bytes(d[o:o + len(n)]) == n for o, _, n in patches):
    print(f'{p}: ibprobe already in'); sys.exit(0)
for o, h, n in patches:
    got = hashlib.sha256(d[o:o + len(n)]).hexdigest()
    if not got.startswith(h):
        sys.exit(f'{p}: bytes at {o:#x} are not the expected build ({got[:16]}) -- not touching it')
for o, _, n in patches:
    d[o:o + len(n)] = n
open(p, 'wb').write(d)
print(f'{p}: ibprobe in (cave at 0x5aa5a0)')
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
