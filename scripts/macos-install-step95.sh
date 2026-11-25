#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step95 (macOS, run as root), one reboot for two things:
#  1. NMXGPU CS trace (scripts/nmx-cstrace): logs "NMX cs-trace: <site> -> <errno>" for failing CS stages and every
#     -EPERM ioctl return, to find the intermittent "CS has been rejected (-1)" on userptr submits.
#  2. Fence-ordered swap: NMXAccel built by CI from ci/nmxaccel-fence (a24692f, run 41659964136). The K6 copy waits
#     for the surface's NMXFenceDone; NVMTL (already installed) then lets WindowServer return at submit.
#     Kill switch at run time: sysctl -w debug.nmxaccel_fence_wait=0 (WindowServer then waits for completion again).
#
#   sudo scripts/macos-install-step95.sh <NMXAccel.kext from CI>
#   sudo scripts/macos-install-step95.sh --undo     # both kexts back from the backup + relink
#   From Linux: pkexec scripts/linux-undo-step95.sh
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
G=/Library/Extensions/NMXGPU.kext; A=/Library/Extensions/NMXAccel.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
STEP93=89969711
ACCEL_SHA=1b9c7b9f002962aa
CAVE_SHA=5a8213a33b38795bb5be43e16cca80bc6adfb6b3eefaa841ccbb42f6aa3ee175
exec > >(tee -a "/Library/NullMoth/step95-$TS.log") 2>&1

if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/step95-bk-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/NMXGPU.kext && -d $BK/NMXAccel.kext ]] || { echo "no step95 backup"; exit 1; }
    rm -rf "$G" "$A"; ditto "$BK/NMXGPU.kext" "$G"; ditto "$BK/NMXAccel.kext" "$A"
    echo "restored NMXGPU and NMXAccel from $BK"
else
    NEWA=${1:?usage: $0 <NMXAccel.kext> | --undo}
    [[ $(shasum -a 256 "$NEWA/Contents/MacOS/NMXAccel" | cut -c1-16) == "$ACCEL_SHA" ]] || { echo "NMXAccel is not the CI build $ACCEL_SHA"; exit 1; }
    [[ $(shasum -a 256 "$HERE/nmx-cstrace/cave.bin" | cut -d' ' -f1) == "$CAVE_SHA" ]] || { echo "cave.bin is not the reviewed build"; exit 1; }
    CUR=$(shasum -a 256 "$G/Contents/MacOS/NMXGPU" | cut -c1-8)
    [[ $CUR == "$STEP93" ]] || { echo "NMXGPU is $CUR..., not the Step93 build -- not touching it"; exit 1; }
    BK=/Library/NullMoth/step95-bk-$TS
    mkdir -p "$BK"
    ditto "$G" "$BK/NMXGPU.kext"; ditto "$A" "$BK/NMXAccel.kext"; cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
    echo "backup $BK"
    /usr/bin/python3 -I "$HERE/nmx-cstrace/step95_patch.py" "$G/Contents/MacOS/NMXGPU"
    rm -rf "$A.new"; ditto "$NEWA" "$A.new"; chown -R 0:0 "$A.new"; chmod -R go-w "$A.new"
    rm -rf "$A"; mv "$A.new" "$A"
fi
shasum -a 256 "$G/Contents/MacOS/NMXGPU" "$A/Contents/MacOS/NMXAccel"

NEW=$KC.step95
rm -f "$NEW"
/usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
    --repository /Library/Extensions -A "$NEW" -z
if [[ ${1:-} != --undo ]]; then
    /usr/bin/python3 -I "$HERE/nmx-cstrace/step95_patch.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I - "$NEW" "$A/Contents/MacOS/NMXAccel" <<'PY'
import sys
kc = open(sys.argv[1], 'rb').read(); a = open(sys.argv[2], 'rb').read()
s = b'iop: fence: surface 0x%x pending'
ok = s in kc and a.find(s) >= 0
print('NMXAccel fence build:', 'present' if ok else 'MISSING', 'in the new collection'); sys.exit(0 if ok else 1)
PY
fi
mv -f "$NEW" "$KC"
sync
echo "RELINKED $(date -u): reboot to load it"
