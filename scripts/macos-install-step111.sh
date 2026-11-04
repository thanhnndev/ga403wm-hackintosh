#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step111 (macOS, run as root): StrixS0ix 0.1.2 hands the live FADT to NMXGPU's xkpi.
# xkpi reads ACPI tables from the first "ACPI Tables" dictionary in the registry (StrixVFCT's, VFCT only on Tahoe), so
# its FADT copy was zero, amdgpu saw LOW_POWER_S0 clear and skipped suspend: the 890M stayed powered in S0 sleep.
# 0.1.2 adds FACP (from IOACPIPlatformDevice::getACPITableData) to that dictionary before NMXGPU starts, so amdgpu
# takes its s0ix suspend/resume path (NMXGPU s0ix cave, Step107). Loads at the next boot.
# Boot-arg -s0ixnofacp skips only the FACP part (back to Step110 behaviour).
#
#   sudo scripts/macos-install-step111.sh
#   sudo scripts/macos-install-step111.sh --undo   # back to the StrixS0ix saved by this script, relink
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
E=/Library/Extensions/StrixS0ix.kext
G=/Library/Extensions/NMXGPU.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
mkdir -p /Library/NullMoth
exec > >(tee -a "/Library/NullMoth/step111-$TS.log") 2>&1

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
        grep -qa 'published for xkpi' "$1" || { echo "StrixS0ix 0.1.2 is not in $1"; exit 1; }
    fi
}

relink() {
    local new=$KC.step111
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
    BK=$(ls -d /Library/NullMoth/step111-bk-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/StrixS0ix.kext ]] || { echo "no backup"; exit 1; }
    rm -rf "$E"; ditto "$BK/StrixS0ix.kext" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
    echo "restored StrixS0ix from $BK"
    relink
    echo "Step111 undone; reboot to apply"
    exit 0
fi

B=$REPO/build/StrixS0ix.kext
grep -qa 'published for xkpi' "$B/Contents/MacOS/StrixS0ix" || { echo "$B is not 0.1.2: scripts/build.sh StrixS0ix"; exit 1; }
BK=/Library/NullMoth/step111-bk-$TS
mkdir -p "$BK"
ditto "$E" "$BK/StrixS0ix.kext"
cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
echo "backup $BK"
rm -rf "$E"; ditto "$B" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
echo "StrixS0ix $(shasum -a 256 "$E/Contents/MacOS/StrixS0ix" | cut -c1-16) installed"
relink with-facp
echo "Step111 installed: StrixS0ix 0.1.2 in AuxKC (NMXGPU caves, NMXBacklight 0.4.0 checked); reboot to load it"
