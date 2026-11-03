#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step98b (macOS, run as root): the Step98 flip cave answered every call NotReady. It waited for fb->info.ok, which
# nmx_fb_open only sets on its caller's copy. The fixed cave checks the kva and size instead. This rebuilds NMXGPU from
# the Step97 build kept in the Step98 backup + the fixed cave. NMXAccel (the flip build) is not touched.
#
#   sudo scripts/macos-install-step98b.sh
#   undo: sudo scripts/macos-install-step98.sh --undo (both kexts back to the Step97 install)
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
G=/Library/Extensions/NMXGPU.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
STEP98=2d9102d8a5c6c297
STEP97=c2326f228e774181
SRC=/Library/NullMoth/step98-bk-20261103T171105Z/NMXGPU.kext
FLIP_CAVE_SHA=f446ceca1b89bf76aa524b03ba6de4e7f772f188f1709a0195573b6771f2e964
RESULT=da12984634097e2d597ba283cbb5ac259a496eed4d03ff3bb9ef650081bb5195
exec > >(tee -a "/Library/NullMoth/step98b-$TS.log") 2>&1
[[ $(shasum -a 256 "$HERE/nmx-flip/cave.bin" | cut -d' ' -f1) == "$FLIP_CAVE_SHA" ]] || { echo "nmx-flip/cave.bin is not the reviewed build"; exit 1; }
CUR=$(shasum -a 256 "$G/Contents/MacOS/NMXGPU" | cut -c1-16)
[[ $CUR == "$STEP98" ]] || { echo "NMXGPU is $CUR..., not the Step98 build -- not touching it"; exit 1; }
[[ $(shasum -a 256 "$SRC/Contents/MacOS/NMXGPU" | cut -c1-16) == "$STEP97" ]] || { echo "$SRC is not the Step97 build"; exit 1; }
rm -rf "$G.new"; ditto "$SRC" "$G.new"
/usr/bin/python3 -I "$HERE/nmx-flip/step98_patch.py" "$G.new/Contents/MacOS/NMXGPU"
[[ $(shasum -a 256 "$G.new/Contents/MacOS/NMXGPU" | cut -d' ' -f1) == "$RESULT" ]] || { echo "patched NMXGPU is not $RESULT"; rm -rf "$G.new"; exit 1; }
chown -R 0:0 "$G.new"; chmod -R go-w "$G.new"
rm -rf "$G"; mv "$G.new" "$G"
shasum -a 256 "$G/Contents/MacOS/NMXGPU"
NEW=$KC.step98b
rm -f "$NEW"
/usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
    --repository /Library/Extensions -A "$NEW" -z
/usr/bin/python3 -I "$HERE/nmx-irqwatch/step97_patch.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
/usr/bin/python3 -I "$HERE/nmx-mmfix/step97b_patch.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
/usr/bin/python3 -I "$HERE/nmx-flip/step98_patch.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
mv -f "$NEW" "$KC"
sync
echo "RELINKED $(date -u): reboot to load it"
