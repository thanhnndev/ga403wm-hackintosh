#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step112 (macOS, run as root): StrixS0ix 0.1.3, S0i3 as Linux amd_pmc + cpuidle do it.
# Step111 slept with the 890M suspended but the SoC never left S0i2-ish idle: no SMU OS_HINT, cores only in C1
# (HLT / MWAITX), so the fans kept running. 0.1.3 sends LOG_RESET/LOG_START + OS_HINT(1) through the PMC mailbox after
# the _DSM entry calls and OS_HINT(0) + LOG_DUMP_DATA on wake (S0ix,Smu* properties say whether S0i3 was reached and
# which IP blocks blocked it), and parks the non-boot CPUs in CC6 (IO port CStateBaseAddr+1) instead of HLT.
# Boot-args: s0ix_pmc=0 (no SMU hint), s0ix_cc6=0 (HLT again), s0ix_cc6boot=1 (boot CPU in CC6 too). Loads at next boot.
#
#   sudo scripts/macos-install-step112.sh
#   sudo scripts/macos-install-step112.sh --undo   # back to the StrixS0ix saved by this script, relink
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
E=/Library/Extensions/StrixS0ix.kext
G=/Library/Extensions/NMXGPU.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
mkdir -p /Library/NullMoth
exec > >(tee -a "/Library/NullMoth/step112-$TS.log") 2>&1

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
        grep -qa 'StrixS0ix: PMC mailbox at' "$1" || { echo "StrixS0ix 0.1.3 is not in $1"; exit 1; }
    fi
}

relink() {
    local new=$KC.step112
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
    BK=$(ls -d /Library/NullMoth/step112-bk-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/StrixS0ix.kext ]] || { echo "no backup"; exit 1; }
    rm -rf "$E"; ditto "$BK/StrixS0ix.kext" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
    echo "restored StrixS0ix from $BK"
    relink
    echo "Step112 undone; reboot to apply"
    exit 0
fi

B=$REPO/build/StrixS0ix.kext
grep -qa 'StrixS0ix: PMC mailbox at' "$B/Contents/MacOS/StrixS0ix" || { echo "$B is not 0.1.3: scripts/build.sh StrixS0ix"; exit 1; }
BK=/Library/NullMoth/step112-bk-$TS
mkdir -p "$BK"
ditto "$E" "$BK/StrixS0ix.kext"
cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
echo "backup $BK"
rm -rf "$E"; ditto "$B" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
echo "StrixS0ix $(shasum -a 256 "$E/Contents/MacOS/StrixS0ix" | cut -c1-16) installed"
relink with-facp
echo "Step112 installed: StrixS0ix 0.1.3 in AuxKC (NMXGPU caves, NMXBacklight 0.4.0 checked); reboot to load it"
