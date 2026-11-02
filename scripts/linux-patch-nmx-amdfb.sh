#!/bin/bash
# Rename the 890M framebuffer class NMXGPUFB -> NMXAMDFB in the installed NMXGPU/NMXAccel/NMXAGDC binaries (Step74).
#
#   pkexec scripts/linux-patch-nmx-amdfb.sh          # patch + arm the AuxKC relink (reboots by itself once relinked)
#   pkexec scripts/linux-patch-nmx-amdfb.sh undo     # put the NMXGPUFB binaries back + relink
#
# CoreDisplay tells the GPU vendor from the framebuffer's class name (GetGPUVendorForFramebufferService looks for
# "Intel", "AMD", "AppleParavirt"); any other name gives vendor 1, IOPresentment off, and WindowServer's CDDisplay gets
# CompositorSW, whose CA software contexts assert in Context::push_surface on every start (the boot loop of 2026-11-02).
# The class name is one C string per binary ("NMXGPUFB\0": OSMetaClass name in NMXGPU, serviceMatching/metaCast in
# NMXAccel and NMXAGDC); the kexts are unsigned, so a same-length rewrite needs no re-signing. Symbols keep the old name.
set -euo pipefail
MODE=${1:-patch}
DEV=${DEV:-/dev/nvme0n1p4}
MNT=${MNT:-/mnt/macos-rw}
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
[[ $EUID == 0 ]] || { echo "run with pkexec or sudo"; exit 1; }
case $MODE in patch) FROM=NMXGPUFB TO=NMXAMDFB ;; undo) FROM=NMXAMDFB TO=NMXGPUFB ;; *) echo "patch|undo"; exit 1 ;; esac

for t in $(findmnt -rn -S "$DEV" -o TARGET | tac); do umount "$t"; echo "unmounted $t"; done
mkdir -p "$MNT"
mount -t apfs -o readwrite,uid=0,gid=0,vol=0 "$DEV" "$MNT"
findmnt -rn -T "$MNT" -o OPTIONS | tr ',' '\n' | grep -qx rw || { echo "not rw: $(findmnt -rn -T "$MNT" -o OPTIONS)"; exit 1; }

E="$MNT/Library/Extensions"
BK="$MNT/Library/NullMoth/nmx-amdfb-$MODE-$TS"
mkdir -p "$BK/Library/KernelCollections"
for k in NMXGPU NMXAccel NMXAGDC; do cp -a "$E/$k.kext" "$BK/"; done
cp -a "$MNT/Library/KernelCollections/AuxiliaryKernelExtensions.kc" "$BK/Library/KernelCollections/"
echo "backup $BK"

for k in NMXGPU NMXAccel NMXAGDC; do
    python3 -I - "$E/$k.kext/Contents/MacOS/$k" "$FROM" "$TO" <<'PY'
import sys
p, a, b = sys.argv[1], sys.argv[2].encode(), sys.argv[3].encode()
d = open(p, 'rb').read()
old, new = b'\0' + a + b'\0', b'\0' + b + b'\0'
n, m = d.count(old), d.count(new)
if n == 0 and m == 1:
    print(f'{p}: already {b.decode()}'); sys.exit(0)
if n != 1 or m != 0:
    sys.exit(f'{p}: expected one "{a.decode()}" C string, found {n} (and {m} "{b.decode()}") -- not touching it')
i = d.index(old)
open(p, 'r+b').write(d[:i] + new + d[i + len(old):])
print(f'{p}: {a.decode()} -> {b.decode()} at {i + 1:#x}')
PY
    sha256sum "$E/$k.kext/Contents/MacOS/$k"
done

S="$MNT/Library/StrixGraphicsFix"
install -o 0 -g 0 -m 755 "$HERE/nmx-relink/nmx-relink.sh" "$S/nmx-relink.sh"
install -o 0 -g 0 -m 644 "$HERE/nmx-relink/com.itlmt7925.nmx-relink.plist" "$MNT/Library/LaunchDaemons/com.itlmt7925.nmx-relink.plist"
rm -f "$S/nmx-relink.done" "$S/nmx-relink.status" "$S/nmx-relink.log"
date -u >"$S/nmx-relink.reboot"
sync
umount "$MNT"
echo "armed: boot macOS once (it relinks the AuxKC, ~1-2 min, then reboots by itself); the boot after that loads $TO"
