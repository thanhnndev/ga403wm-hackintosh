#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step124 (macOS, run as root): NVRM waits for NMXAMDFB before this card's MSI enable + RmInitAdapter
# (nmx-translator-271 a039577, branch nvrm-wait-nmxamdfb). The 15:43/15:48 black boots: NVRM's MSI enable came while
# NMXGPU was still attaching, the 890M lost its next MSI, NMXAMDFB came ~5 s late (after NVRM's boot hold ended) and
# WindowServer took the virtual display. Good boots won the race by 0.11-0.12 s. NVRM now holds its boot busy until
# NMXAMDFB is registered (boot-arg nvrmnmxwait=N s, default 20, 0 = off) and logs the 890M MSI registers around its
# own MSI enable. The kext is built outside this repo (PolyForm); pass its path. StrixS0ix and NMXGPU are not touched.
#
#   sudo scripts/macos-install-step124.sh ~/nvrm-build-nmxwait/NVRM.kext
#   sudo scripts/macos-install-step124.sh --undo   # back to the NVRM saved by this script, relink
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
E=/Library/Extensions/NVRM.kext
G=/Library/Extensions/NMXGPU.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
mkdir -p /Library/NullMoth
exec > >(tee -a "/Library/NullMoth/step124-$TS.log") 2>&1

checks() {  # $1 = collection; $2 = with-wait to require the new NVRM
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
    grep -qa 'published for xkpi' "$1" || { echo "StrixS0ix 0.1.2 is not in $1"; exit 1; }
    grep -qa 'EC queries that ask for a full wake' "$1" || { echo "StrixS0ix 0.1.12 is not in $1"; exit 1; }
    if [[ ${2:-} == with-wait ]]; then
        grep -qa '890M wait: NMXAMDFB registered' "$1" || { echo "NVRM nmx-wait is not in $1"; exit 1; }
    fi
}

relink() {
    local new=$KC.step124
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
    BK=$(ls -d /Library/NullMoth/step124-bk-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/NVRM.kext ]] || { echo "no backup"; exit 1; }
    rm -rf "$E"; ditto "$BK/NVRM.kext" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
    echo "restored NVRM from $BK"
    relink
    echo "Step124 undone; reboot to apply"
    exit 0
fi

B=${1:?path to the nmx-wait NVRM.kext}
grep -qa '890M wait: NMXAMDFB registered' "$B/Contents/MacOS/NVRM" || { echo "$B is not the nmx-wait NVRM"; exit 1; }
BK=/Library/NullMoth/step124-bk-$TS
mkdir -p "$BK"
ditto "$E" "$BK/NVRM.kext"
cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
echo "backup $BK"
rm -rf "$E"; ditto "$B" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
echo "NVRM $(shasum -a 256 "$E/Contents/MacOS/NVRM" | cut -c1-16) installed"
relink with-wait
echo "Step124 installed: NVRM waits for NMXAMDFB (AuxKC checked: NMXGPU caves, StrixS0ix 0.1.12, NMXBacklight); reboot to load it"
