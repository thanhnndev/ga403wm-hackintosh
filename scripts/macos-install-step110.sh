#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step110 (macOS, run as root): NMXBacklight 0.4.0, the system wake work IOGraphics never does for NMXAMDFB.
# After the first S0 system sleep (Step109) WindowServer slept in IOFramebuffer::_extEntry until NMXAMDFB's
# pagingState came back, which never happened (NMXAMDFB replaces setPowerState), and watchdogd panicked 120 s later.
# 0.4.0 wraps NMXAMDFB's setPowerState in the framebuffer's private vtable copy and does the wake work under the
# framebuffer's workloop gate (DidWake, DidPowerOn, pagingState, wake WindowServer), as NVRMFB's familyDidWake does.
# Loads at the next boot. Boot-arg -nmxfbwakeoff turns only the wake work off.
#
#   sudo scripts/macos-install-step110.sh
#   sudo scripts/macos-install-step110.sh --undo   # back to the NMXBacklight saved by this script, relink
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
E=/Library/Extensions/NMXBacklight.kext
G=/Library/Extensions/NMXGPU.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
mkdir -p /Library/NullMoth
exec > >(tee -a "/Library/NullMoth/step110-$TS.log") 2>&1

checks() {  # $1 = collection; $2 = with-wake to require 0.4.0
    /usr/bin/python3 -I "$HERE/nmx-mmfix/step97b_patch.py" --check-kc "$1" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-flip/step99_patch.py" --check-kc "$1" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-irqfix/patch_irqfix.py" --check-kc "$1" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-mmfix2/step100_mm_patch.py" --check-kc "$1" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-s0ix/patch_s0ix.py" --check-kc "$1" "$G/Contents/MacOS/NMXGPU"
    grep -qa 'sleep/wake interest' "$1" || { echo "NMXBacklight is not in $1"; exit 1; }
    grep -qa 'StrixS0ix: pmCPUHalt registered' "$1" || { echo "StrixS0ix is not in $1"; exit 1; }
    if [[ ${2:-} == with-wake ]]; then
        grep -qa 'paging wake %s (setPowerState slot' "$1" || { echo "NMXBacklight 0.4.0 is not in $1"; exit 1; }
    fi
}

relink() {
    local new=$KC.step110
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
    BK=$(ls -d /Library/NullMoth/step110-bk-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/NMXBacklight.kext ]] || { echo "no backup"; exit 1; }
    rm -rf "$E"; ditto "$BK/NMXBacklight.kext" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
    echo "restored NMXBacklight from $BK"
    relink
    echo "Step110 undone; reboot to apply"
    exit 0
fi

B=$REPO/build/NMXBacklight.kext
grep -qa 'paging wake %s (setPowerState slot' "$B/Contents/MacOS/NMXBacklight" || { echo "$B is not 0.4.0: scripts/build.sh NMXBacklight"; exit 1; }
BK=/Library/NullMoth/step110-bk-$TS
mkdir -p "$BK"
ditto "$E" "$BK/NMXBacklight.kext"
cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
echo "backup $BK"
rm -rf "$E"; ditto "$B" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
echo "NMXBacklight $(shasum -a 256 "$E/Contents/MacOS/NMXBacklight" | cut -c1-16) installed"
relink with-wake
echo "Step110 installed: NMXBacklight 0.4.0 in AuxKC (NMXGPU caves and StrixS0ix checked); reboot to load it"
