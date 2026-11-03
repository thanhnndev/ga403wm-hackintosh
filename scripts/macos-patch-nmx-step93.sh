#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step93 (macOS, run as root): NMXGPU's per-submit GFX IB prepare (b15: kmap + clflush + 96-dword snapshot + printf for
# every GFX IB, ~80 log lines/s on the desktop) becomes opt-in, then the AuxKC is relinked in place for the next boot.
#
#   sudo scripts/macos-patch-nmx-step93.sh          # patch + relink
#   sudo scripts/macos-patch-nmx-step93.sh --undo   # put the backed-up NMXGPU back + relink
#   From Linux: pkexec scripts/linux-undo-nmx-step93.sh
#
# b15 was a workaround for IB corruption from dirty write-back aliases of WC pool pages (Step84 fixed the source:
# pmap_zero_page flushes) and from un-snooped GTT (Step88: cached GTT is snooped again). At run time:
#   sysctl -w debug.nmx_wbinvd=2   # b15 prepare back on, for a hang hunt (bit 0 is still the whole-cache invalidate)
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
E=/Library/Extensions/NMXGPU.kext
BIN=$E/Contents/MacOS/NMXGPU
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
STEP92=01ecc7bc
exec > >(tee -a "/Library/NullMoth/step93-$TS.log") 2>&1

if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/nmx-step93-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -f $BK/NMXGPU.kext/Contents/MacOS/NMXGPU ]] || { echo "no step93 backup"; exit 1; }
    rm -rf "$E"; ditto "$BK/NMXGPU.kext" "$E"
    echo "restored NMXGPU from $BK"
else
    CUR=$(shasum -a 256 "$BIN" | cut -c1-8)
    [[ $CUR == "$STEP92" ]] || { echo "NMXGPU is $CUR..., not the Step92 build -- not touching it"; exit 1; }
    BK=/Library/NullMoth/nmx-step93-$TS
    mkdir -p "$BK"
    ditto "$E" "$BK/NMXGPU.kext"
    cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
    echo "backup $BK"
    /usr/bin/python3 -I "$HERE/nmx-ibprep/step93_patch.py" "$BIN"
fi
shasum -a 256 "$BIN"

NEW=$KC.step93
rm -f "$NEW"
/usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
    --repository /Library/Extensions -A "$NEW" -z
if [[ ${1:-} != --undo ]]; then
    /usr/bin/python3 -I "$HERE/nmx-ibprep/step93_patch.py" --check-kc "$NEW" "$BIN"
fi
mv -f "$NEW" "$KC"
sync
echo "RELINKED $(date -u): reboot to load it"
