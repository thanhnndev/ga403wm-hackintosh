#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step96 (macOS, run as root): NMXGPU = Step93 build + the CS trace cave rebuilt with the read-only userptr retry
# (scripts/nmx-cstrace/cave.c userptr_ro). A writable pin of a read-only mapping (WindowServer maps client
# CoreAnimation surfaces r--/r--) failed with -EFAULT and the surface fell back to CPU copies; the retry pins it
# read-only and marks the TT read-only so the GPU PTEs have no write bit. NMXAccel is not touched.
# Input is the Step93 NMXGPU kept in the Step95 backup; the installed Step95 NMXGPU is backed up first.
#
#   sudo scripts/macos-install-step96.sh
#   sudo scripts/macos-install-step96.sh --undo     # NMXGPU back to the Step95 build + relink
#   From Linux: pkexec scripts/linux-undo-step96.sh
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
G=/Library/Extensions/NMXGPU.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
STEP93=89969711
STEP95=4e856bbb
CAVE_SHA=9ececceaa89984efacc7cbb96453f24e5fad1793b529f00707ab22b3b37b7443
RESULT=44c7e55201a3bcfb
S95BK=/Library/NullMoth/step95-bk-20261103T152156Z
exec > >(tee -a "/Library/NullMoth/step96-$TS.log") 2>&1

if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/step96-bk-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/NMXGPU.kext ]] || { echo "no step96 backup"; exit 1; }
    rm -rf "$G"; ditto "$BK/NMXGPU.kext" "$G"
    echo "restored NMXGPU from $BK"
else
    [[ $(shasum -a 256 "$HERE/nmx-cstrace/cave.bin" | cut -d' ' -f1) == "$CAVE_SHA" ]] || { echo "cave.bin is not the reviewed build"; exit 1; }
    CUR=$(shasum -a 256 "$G/Contents/MacOS/NMXGPU" | cut -c1-8)
    [[ $CUR == "$STEP95" ]] || { echo "NMXGPU is $CUR..., not the Step95 build -- not touching it"; exit 1; }
    SRC=$S95BK/NMXGPU.kext
    [[ $(shasum -a 256 "$SRC/Contents/MacOS/NMXGPU" | cut -c1-8) == "$STEP93" ]] || { echo "$SRC is not the Step93 build"; exit 1; }
    BK=/Library/NullMoth/step96-bk-$TS
    mkdir -p "$BK"
    ditto "$G" "$BK/NMXGPU.kext"; cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
    echo "backup $BK"
    rm -rf "$G.new"; ditto "$SRC" "$G.new"
    /usr/bin/python3 -I "$HERE/nmx-cstrace/step95_patch.py" "$G.new/Contents/MacOS/NMXGPU"
    [[ $(shasum -a 256 "$G.new/Contents/MacOS/NMXGPU" | cut -c1-16) == "$RESULT" ]] || { echo "patched NMXGPU is not $RESULT"; rm -rf "$G.new"; exit 1; }
    chown -R 0:0 "$G.new"; chmod -R go-w "$G.new"
    rm -rf "$G"; mv "$G.new" "$G"
fi
shasum -a 256 "$G/Contents/MacOS/NMXGPU"

NEW=$KC.step96
rm -f "$NEW"
/usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
    --repository /Library/Extensions -A "$NEW" -z
[[ ${1:-} == --undo ]] || /usr/bin/python3 -I "$HERE/nmx-cstrace/step95_patch.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
mv -f "$NEW" "$KC"
sync
echo "RELINKED $(date -u): reboot to load it"
