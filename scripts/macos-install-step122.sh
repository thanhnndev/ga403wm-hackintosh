#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step122 (macOS, run as root): StrixS0ix 0.1.11 = 0.1.10 + EC query taken at an EC GPE wake, its _Qxx run from a thread, full wake (display wrangler tickle) on _QE7 = power button. Based on Step113:
# SMU still saw DISPLAY, CPU and NBIO busy: macOS leaves every PCI function except the XHCs in D0. 0.1.4 sends OS_HINT
# from the halt path (after every driver suspended, as Linux does), records each endpoint's D-state there
# (S0ix,PciStates) and, with S0ix,D3Mode 1/2 (runtime, build/s0ix-set), puts No_Soft_Reset functions into D3hot through
# ECAM for the sleep. Boot CPU CC6 is on by default. Boot-args: s0ix_d3=N, s0ix_halthint=0, s0ix_cc6boot=0.
#
#   sudo scripts/macos-install-step122.sh
#   sudo scripts/macos-install-step122.sh --undo   # back to the StrixS0ix saved by this script, relink
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
E=/Library/Extensions/StrixS0ix.kext
G=/Library/Extensions/NMXGPU.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
mkdir -p /Library/NullMoth
exec > >(tee -a "/Library/NullMoth/step122-$TS.log") 2>&1

checks() {  # $1 = collection; $2 = with-wake to require 0.4.0
    /usr/bin/python3 -I "$HERE/nmx-mmfix/step97b_patch.py" --check-kc "$1" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-flip/step99_patch.py" --check-kc "$1" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-irqfix/patch_irqfix.py" --check-kc "$1" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-mmfix2/step100_mm_patch.py" --check-kc "$1" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-s0ix/patch_s0ix.py" --check-kc "$1" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-s0ix/patch_fadt.py" --check-kc "$1" "$G/Contents/MacOS/NMXGPU"
    grep -qa 'NVRMFB reports 0 connected displays on every nub' "$1" || { echo "headless NVRM is not in $1"; exit 1; }
    grep -qa 'sleep/wake interest' "$1" || { echo "NMXBacklight is not in $1"; exit 1; }
    grep -qa 'StrixS0ix: pmCPUHalt registered' "$1" || { echo "StrixS0ix is not in $1"; exit 1; }
    grep -qa 'paging wake %s (setPowerState slot' "$1" || { echo "NMXBacklight 0.4.0 is not in $1"; exit 1; }
    if [[ ${2:-} == with-facp ]]; then
        grep -qa 'published for xkpi' "$1" || { echo "StrixS0ix 0.1.2 is not in $1"; exit 1; }
        grep -qa 'EC query %#x at the wake' "$1" || { echo "StrixS0ix 0.1.11 is not in $1"; exit 1; }
    fi
}

relink() {
    local new=$KC.step113
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
    BK=$(ls -d /Library/NullMoth/step122-bk-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/StrixS0ix.kext ]] || { echo "no backup"; exit 1; }
    rm -rf "$E"; ditto "$BK/StrixS0ix.kext" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
    echo "restored StrixS0ix from $BK"
    relink
    echo "Step122 undone; reboot to apply"
    exit 0
fi

B=$REPO/build/StrixS0ix.kext
grep -qa 'EC query %#x at the wake' "$B/Contents/MacOS/StrixS0ix" || { echo "$B is not 0.1.11: scripts/build.sh StrixS0ix"; exit 1; }
BK=/Library/NullMoth/step122-bk-$TS
mkdir -p "$BK"
ditto "$E" "$BK/StrixS0ix.kext"
cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
echo "backup $BK"
rm -rf "$E"; ditto "$B" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
echo "StrixS0ix $(shasum -a 256 "$E/Contents/MacOS/StrixS0ix" | cut -c1-16) installed"
relink with-facp
echo "Step122 installed: StrixS0ix 0.1.11 in AuxKC (NMXGPU caves, NMXBacklight 0.4.0 checked); reboot to load it"
