#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step92 (macOS, run as root): amdgpu userptr in NMXGPU (scripts/nmx-userptr), then the AuxKC is relinked in place so
# the next boot has it. Nothing changes for the running session.
#
#   sudo scripts/macos-patch-nmx-step92.sh          # patch + relink
#   sudo scripts/macos-patch-nmx-step92.sh --undo   # put the backed-up NMXGPU back + relink
#   From Linux: pkexec scripts/linux-undo-nmx-step92.sh
#
# The NMXGPU build has no HMM, so DRM_AMDGPU_GEM_USERPTR always failed (-ENODEV) and RADV refused every host-pointer
# import: NVMTL copied each IOSurface into a private image and back with the CPU (nvmtlSurfaceIn/Out, the largest
# share of WindowServer's CPU after Step91). The cave pins the pages once (xkpi get_user_pages) for the BO's lifetime,
# the submit path no longer rejects userptr BOs, and unpopulate puts the pages. NVMTL then renders and samples the
# IOSurfaces' own pages ("-> its own pages (host import, no copies)").
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
E=/Library/Extensions/NMXGPU.kext
BIN=$E/Contents/MacOS/NMXGPU
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
STEP91=b13ca867
CAVE_SHA=2a50dbe3c95dfccd1bee6f70930ee4e59437c47e3c1b03ca65f28c71ca6a4033
exec > >(tee -a "/Library/NullMoth/step92-$TS.log") 2>&1

if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/nmx-step92-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -f $BK/NMXGPU.kext/Contents/MacOS/NMXGPU ]] || { echo "no step92 backup"; exit 1; }
    rm -rf "$E"; ditto "$BK/NMXGPU.kext" "$E"
    echo "restored NMXGPU from $BK"
else
    [[ $(shasum -a 256 "$HERE/nmx-userptr/cave.bin" | cut -d' ' -f1) == "$CAVE_SHA" ]] || { echo "cave.bin is not the reviewed build"; exit 1; }
    CUR=$(shasum -a 256 "$BIN" | cut -c1-8)
    [[ $CUR == "$STEP91" ]] || { echo "NMXGPU is $CUR..., not the Step91 build -- not touching it"; exit 1; }
    BK=/Library/NullMoth/nmx-step92-$TS
    mkdir -p "$BK"
    ditto "$E" "$BK/NMXGPU.kext"
    cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
    echo "backup $BK"
    /usr/bin/python3 -I "$HERE/nmx-userptr/step92_patch.py" "$BIN" "$HERE/nmx-userptr"
fi
shasum -a 256 "$BIN"

NEW=$KC.step92
rm -f "$NEW"
/usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
    --repository /Library/Extensions -A "$NEW" -z
if [[ ${1:-} != --undo ]]; then
    /usr/bin/python3 -I "$HERE/nmx-userptr/step92_patch.py" --check-kc "$NEW" "$BIN"
fi
mv -f "$NEW" "$KC"
sync
echo "RELINKED $(date -u): reboot to load it"
