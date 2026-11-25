#!/bin/bash
# Step75: the 890M display pipe goes active, so WindowServer's frames reach the OLED.
#
#   pkexec scripts/linux-patch-nmx-scanout.sh <NMXAccel binary from CI>
#
# NMXAMDFB answered the accelerator's scanout query with phys 0, so NMXAccel's initFramebufferResource made no
# framebuffer resource, IOAcceleratorFamily never marked the display pipe active, and every WindowServer transaction
# ended "Fallback GPU Display Pipe transaction submission failed" before performTransaction ran: WindowServer and
# loginwindow were up, the panel never showed them (boot 8550F017, 2026-11-02).
#  - NMXGPU (no CI build): one 24-byte rewrite in NMXGPUFB::callPlatformFunction, "r->phys = 0; r->handle = 0" ->
#    "r->phys = fInfo.phys (this+0x1e8); r->handle = 0". Same length, the kext is unsigned.
#  - NMXAccel: the CI build of nvidia-macos-driver 30237fd (nmxArm accepts a non-zero phys; l10r frames narrowed).
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
if d.count(b'\0NMXAMDFB\0') != 1 or b'\0NMXGPUFB\0' in d: sys.exit('CI NMXAccel does not match NMXAMDFB')
if b'is not BGRA or l10r' not in d: sys.exit('CI NMXAccel predates the l10r change')
print('CI NMXAccel ok')
PY

for t in $(findmnt -rn -S "$DEV" -o TARGET | tac); do umount "$t"; echo "unmounted $t"; done
mkdir -p "$MNT"
mount -t apfs -o readwrite,uid=0,gid=0,vol=0 "$DEV" "$MNT"
findmnt -rn -T "$MNT" -o OPTIONS | tr ',' '\n' | grep -qx rw || { echo "not rw: $(findmnt -rn -T "$MNT" -o OPTIONS)"; exit 1; }

E="$MNT/Library/Extensions"
BK="$MNT/Library/NullMoth/nmx-scanout-$TS"
mkdir -p "$BK/Library/KernelCollections"
for k in NMXGPU NMXAccel; do cp -a "$E/$k.kext" "$BK/"; done
cp -a "$MNT/Library/KernelCollections/AuxiliaryKernelExtensions.kc" "$BK/Library/KernelCollections/"
echo "backup $BK"

python3 -I - "$E/NMXGPU.kext/Contents/MacOS/NMXGPU" <<'PY'
import sys
p = sys.argv[1]
d = open(p, 'rb').read()
# movq %rsi,0x20(%rcx); movq $0,0x18(%rcx); movq $0,0x28(%rcx); movq %r9,0x10(%rcx)
old = bytes.fromhex('48897120' '48c7411800000000' '48c7412800000000' '4c894910')
# movq %rsi,0x20(%rcx); movq 0x1e8(%rdi),%r10; movq %r10,0x18(%rcx); andq $0,0x28(%rcx); movq %r9,0x10(%rcx)
new = bytes.fromhex('48897120' '4c8b97e8010000' '4c895118' '4883612800' '4c894910')
assert len(old) == len(new)
n, m = d.count(old), d.count(new)
if n == 0 and m == 1:
    print(f'{p}: already reports phys'); sys.exit(0)
if n != 1 or m != 0:
    sys.exit(f'{p}: expected one scanout store sequence, found {n} (and {m} patched) -- not touching it')
i = d.index(old)
open(p, 'r+b').write(d[:i] + new + d[i + len(old):])
print(f'{p}: scanout phys = fInfo.phys at {i:#x}')
PY
sha256sum "$E/NMXGPU.kext/Contents/MacOS/NMXGPU"

install -o 0 -g 0 -m 755 "$NEWACCEL" "$E/NMXAccel.kext/Contents/MacOS/NMXAccel"
sha256sum "$E/NMXAccel.kext/Contents/MacOS/NMXAccel"

S="$MNT/Library/StrixGraphicsFix"
install -o 0 -g 0 -m 755 "$HERE/nmx-relink/nmx-relink.sh" "$S/nmx-relink.sh"
install -o 0 -g 0 -m 644 "$HERE/nmx-relink/com.itlmt7925.nmx-relink.plist" "$MNT/Library/LaunchDaemons/com.itlmt7925.nmx-relink.plist"
rm -f "$S/nmx-relink.done" "$S/nmx-relink.status" "$S/nmx-relink.log"
date -u >"$S/nmx-relink.reboot"
sync
umount "$MNT"
echo "armed: boot macOS once (it relinks the AuxKC, ~1-2 min, then reboots by itself); the boot after that drives the OLED through the display pipe"
