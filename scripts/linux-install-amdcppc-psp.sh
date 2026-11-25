#!/bin/bash
# Step87: AmdCppc (rog-control-macos, branch diag/psp-snapshot) logs "AmdCppc: psp at start: reset=... ring_lo=..." about
# 8 s before NMXGPU touches the GPU, so a boot where PSP LOAD_IP_FW fails shows what the previous session left in the PSP.
#
#   scripts/linux-install-amdcppc-psp.sh <AmdCppc.kext>      (the ESP is user-writable on this install, no root needed)
#
# The kext keeps everything of the installed 0.2.1 build and only adds the snapshot and sysctl debug.amdcppc.psp.
set -euo pipefail
SRC=${1:?path to the built AmdCppc.kext}
DST=${DST:-/boot/EFI/OC/Kexts/AmdCppc.kext}
BK=${BK:-/boot/EFI/OC/Backup/AmdCppc.kext-$(date -u +%Y%m%dT%H%M%SZ)}
strings "$SRC/Contents/MacOS/AmdCppc" | grep -q 'psp at start' || { echo "$SRC: not the build with the PSP snapshot"; exit 1; }
mkdir -p "$(dirname "$BK")"
cp -a "$DST" "$BK"
echo "backup $BK"
rm -rf "$DST"
cp -r "$SRC" "$DST"
sync
sha256sum "$DST/Contents/MacOS/AmdCppc"
