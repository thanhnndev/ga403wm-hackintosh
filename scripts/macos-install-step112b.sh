#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step112b (macOS, run as root): the headless NVRM build (nmx-translator-271 c54e304) in the same reboot as Step112.
# On an OLED-only boot NVRM's auto-go waited 20 x 1 s for RTX heads plus accel retries while holding the registry busy,
# so WindowServer's IOKitWaitQuiet waited 36 s. The new NVRM releases the boot hold once every NVRMDisplay nub reports
# 0 connected displays. The kext is built outside this repo (PolyForm); pass its path.
#
#   sudo scripts/macos-install-step112b.sh ~/nvrm-build-headless/NVRM.kext
#   sudo scripts/macos-install-step112b.sh --undo   # back to the NVRM saved by this script, relink
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
E=/Library/Extensions/NVRM.kext
G=/Library/Extensions/NMXGPU.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
mkdir -p /Library/NullMoth
exec > >(tee -a "/Library/NullMoth/step112b-$TS.log") 2>&1

checks() {  # $1 = collection; $2 = with-wake to require 0.4.0
    /usr/bin/python3 -I "$HERE/nmx-mmfix/step97b_patch.py" --check-kc "$1" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-flip/step99_patch.py" --check-kc "$1" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-irqfix/patch_irqfix.py" --check-kc "$1" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-mmfix2/step100_mm_patch.py" --check-kc "$1" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-s0ix/patch_s0ix.py" --check-kc "$1" "$G/Contents/MacOS/NMXGPU"
    grep -qa 'sleep/wake interest' "$1" || { echo "NMXBacklight is not in $1"; exit 1; }
    grep -qa 'StrixS0ix: pmCPUHalt registered' "$1" || { echo "StrixS0ix is not in $1"; exit 1; }
    grep -qa 'paging wake %s (setPowerState slot' "$1" || { echo "NMXBacklight 0.4.0 is not in $1"; exit 1; }
    if [[ ${2:-} == with-facp ]]; then
        grep -qa 'NVRMFB reports 0 connected displays on every nub' "$1" || { echo "headless NVRM is not in $1"; exit 1; }
        grep -qa 'published for xkpi' "$1" || { echo "StrixS0ix 0.1.2 is not in $1"; exit 1; }
        grep -qa 'StrixS0ix: PMC mailbox at' "$1" || { echo "StrixS0ix 0.1.3 is not in $1"; exit 1; }
    fi
}

relink() {
    local new=$KC.step112b
    rm -f "$new"
    /usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
        -B /System/Library/KernelCollections/BootKernelExtensions.kc \
        -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
        --repository /Library/Extensions -A "$new" -z
    checks "$new" "${1:-}"
    mv -f "$new" "$KC"; sync
    # kernelmanagerd once replaced a fresh collection with its own list (Step100b): check again after it had time to act
    /usr/bin/perl -e 'select(undef, undef, undef, 45)'
    checks "$KC" "${1:-}"
}

if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/step112b-bk-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/NVRM.kext ]] || { echo "no backup"; exit 1; }
    rm -rf "$E"; ditto "$BK/NVRM.kext" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
    echo "restored NVRM from $BK"
    relink
    echo "Step112b undone; reboot to apply"
    exit 0
fi

B=${1:?path to the headless NVRM.kext}
grep -qa 'NVRMFB reports 0 connected displays on every nub' "$B/Contents/MacOS/NVRM" || { echo "$B is not the headless NVRM"; exit 1; }
BK=/Library/NullMoth/step112b-bk-$TS
mkdir -p "$BK"
ditto "$E" "$BK/NVRM.kext"
cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
echo "backup $BK"
rm -rf "$E"; ditto "$B" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
echo "NVRM $(shasum -a 256 "$E/Contents/MacOS/NVRM" | cut -c1-16) installed"
relink with-facp
echo "Step112b installed: headless NVRM in AuxKC (StrixS0ix 0.1.3, NMXGPU caves checked); reboot to load it"
