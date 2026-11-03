#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step98 (macOS, run as root): page flips, mode 2 (copy into a VRAM back buffer + vblank-latched flip).
# - NMXGPU: the Step97 build (irqwatch + mmfix, c2326f22) + the flip API cave (scripts/nmx-flip): nmxFlipCaps,
#   nmxFlipBuffers, nmxFlipSubmit, nmxFlipStatus, nmxFlipRelease on NMXGPUFB::callPlatformFunction.
# - NMXAccel: CI ci/nmxaccel-flip 37493db (= the live a24692f fence build + the flip path, docs/890M-FLIPS.md).
# Flips stay OFF until `sysctl -w debug.nmxaccel_flip=2`; with it 0, NMXAccel never calls the API.
#
#   sudo scripts/macos-install-step98.sh
#   sudo scripts/macos-install-step98.sh --undo     # both kexts back to the Step97 install + relink
#   From Linux: pkexec scripts/linux-undo-step98.sh
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
G=/Library/Extensions/NMXGPU.kext
A=/Library/Extensions/NMXAccel.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
STEP97=c2326f228e774181
ACCEL_LIVE=1b9c7b9f002962aa
FLIP_CAVE_SHA=f446ceca1b89bf76aa524b03ba6de4e7f772f188f1709a0195573b6771f2e964
RESULT=da12984634097e2d597ba283cbb5ac259a496eed4d03ff3bb9ef650081bb5195
ACCEL_SRC=${ACCEL_SRC:-/Users/thanhnndev/ga403-logs/step97/ci/NMXAccel.kext}
ACCEL_FLIP=bf7c7ea8c233d22a89ecc6395ddc8508fbdcbd9bc77865c657eff1ab38247944
exec > >(tee -a "/Library/NullMoth/step98-$TS.log") 2>&1

if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/step98-bk-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/NMXGPU.kext && -d $BK/NMXAccel.kext ]] || { echo "no step98 backup"; exit 1; }
    rm -rf "$G" "$A"; ditto "$BK/NMXGPU.kext" "$G"; ditto "$BK/NMXAccel.kext" "$A"
    echo "restored NMXGPU and NMXAccel from $BK"
else
    [[ $(shasum -a 256 "$HERE/nmx-flip/cave.bin" | cut -d' ' -f1) == "$FLIP_CAVE_SHA" ]] || { echo "nmx-flip/cave.bin is not the reviewed build"; exit 1; }
    CUR=$(shasum -a 256 "$G/Contents/MacOS/NMXGPU" | cut -c1-16)
    [[ $CUR == "$STEP97" ]] || { echo "NMXGPU is $CUR..., not the Step97 build -- not touching it"; exit 1; }
    CA=$(shasum -a 256 "$A/Contents/MacOS/NMXAccel" | cut -c1-16)
    [[ $CA == "$ACCEL_LIVE" ]] || { echo "NMXAccel is $CA..., not the a24692f fence build -- not touching it"; exit 1; }
    [[ $(shasum -a 256 "$ACCEL_SRC/Contents/MacOS/NMXAccel" | cut -d' ' -f1) == "$ACCEL_FLIP" ]] || { echo "$ACCEL_SRC is not the 37493db flip build"; exit 1; }
    BK=/Library/NullMoth/step98-bk-$TS
    mkdir -p "$BK"
    ditto "$G" "$BK/NMXGPU.kext"; ditto "$A" "$BK/NMXAccel.kext"; cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
    echo "backup $BK"
    rm -rf "$G.new" "$A.new"; ditto "$G" "$G.new"; ditto "$ACCEL_SRC" "$A.new"
    /usr/bin/python3 -I "$HERE/nmx-flip/step98_patch.py" "$G.new/Contents/MacOS/NMXGPU"
    [[ $(shasum -a 256 "$G.new/Contents/MacOS/NMXGPU" | cut -d' ' -f1) == "$RESULT" ]] || { echo "patched NMXGPU is not $RESULT"; rm -rf "$G.new" "$A.new"; exit 1; }
    chown -R 0:0 "$G.new" "$A.new"; chmod -R go-w "$G.new" "$A.new"
    rm -rf "$G"; mv "$G.new" "$G"
    rm -rf "$A"; mv "$A.new" "$A"
fi
shasum -a 256 "$G/Contents/MacOS/NMXGPU" "$A/Contents/MacOS/NMXAccel"

NEW=$KC.step98
rm -f "$NEW"
/usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
    --repository /Library/Extensions -A "$NEW" -z
if [[ ${1:-} != --undo ]]; then
    /usr/bin/python3 -I "$HERE/nmx-irqwatch/step97_patch.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-mmfix/step97b_patch.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-flip/step98_patch.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
fi
mv -f "$NEW" "$KC"
sync
echo "RELINKED $(date -u): reboot to load it"
