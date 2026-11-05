#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step112c (macOS, run as root): NMXGPU reads the FADT again right before its system-sleep suspend (nmx-s0ix/patch_fadt.py).
# xkpi copies the FADT once at NMXGPU start; StrixS0ix publishes FACP within ~50 ms of that, and the Step112 boot lost
# the race ("no FADT"), so amdgpu skipped its s0ix suspend. The patch makes the race irrelevant. Loads at the next boot.
#
#   sudo scripts/macos-install-step112c.sh
#   sudo scripts/macos-install-step112c.sh --undo   # back to the NMXGPU saved by this script, relink
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
G=/Library/Extensions/NMXGPU.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
mkdir -p /Library/NullMoth
exec > >(tee -a "/Library/NullMoth/step112c-$TS.log") 2>&1

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
        /usr/bin/python3 -I "$HERE/nmx-s0ix/patch_fadt.py" --check-kc "$1" "$G/Contents/MacOS/NMXGPU"
        grep -qa 'published for xkpi' "$1" || { echo "StrixS0ix 0.1.2 is not in $1"; exit 1; }
        grep -qa 'StrixS0ix: PMC mailbox at' "$1" || { echo "StrixS0ix 0.1.3 is not in $1"; exit 1; }
    fi
}

relink() {
    local new=$KC.step112c
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
    BK=$(ls -d /Library/NullMoth/step112c-bk-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/NMXGPU.kext ]] || { echo "no backup"; exit 1; }
    rm -rf "$G"; ditto "$BK/NMXGPU.kext" "$G"; chown -R 0:0 "$G"; chmod -R go-w "$G"
    echo "restored NMXGPU from $BK"
    relink
    echo "Step112c undone; reboot to apply"
    exit 0
fi

BK=/Library/NullMoth/step112c-bk-$TS
mkdir -p "$BK"
ditto "$G" "$BK/NMXGPU.kext"
cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
echo "backup $BK"
rm -rf "$G.new"; ditto "$G" "$G.new"
/usr/bin/python3 -I "$HERE/nmx-s0ix/patch_fadt.py" "$G.new/Contents/MacOS/NMXGPU"
[[ $(shasum -a 256 "$G.new/Contents/MacOS/NMXGPU" | cut -c1-16) == 5760efb63fc0eee9 ]] || { echo "patched NMXGPU is not 5760efb6"; rm -rf "$G.new"; exit 1; }
/usr/bin/python3 -I "$HERE/nmx-caves/check.py" "$G.new/Contents/MacOS/NMXGPU" || { echo "cave registry check failed"; rm -rf "$G.new"; exit 1; }
chown -R 0:0 "$G.new"; chmod -R go-w "$G.new"
rm -rf "$G"; mv "$G.new" "$G"
echo "NMXGPU 5760efb6 installed"
relink with-facp
echo "Step112c installed: NMXGPU re-reads the FADT before suspend (all caves, StrixS0ix 0.1.3, headless NVRM checked); reboot to load it"
