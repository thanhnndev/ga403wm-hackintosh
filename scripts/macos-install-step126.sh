#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step126 (macOS, run as root): StrixS0ix 0.1.13 = 0.1.12 + NBIO trace. At each sleep it logs, per root port and the
# endpoint behind it, ASPM / L1 PM Substates / LTR (supported/enabled), link speed/width and DLL active
# ("StrixS0ix: link ..." lines, S0ix,Links), and at wake the root ports' DLL-active bit at halt entry and at wake.
# Read only: no link setting is changed. Relinks the AuxKC the way auxguard does (kccheck + nmx-relink.probes), so it
# works on top of the Step125 source-built NMXGPU (the old step97..124 cave checkers do not apply any more).
#   sudo scripts/macos-install-step126.sh
#   sudo scripts/macos-install-step126.sh --undo   # back to the StrixS0ix saved by this script, relink
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$HERE/.." && pwd)
L=/Library/Extensions; E=$L/StrixS0ix.kext; KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
G=/Library/StrixGraphicsFix; TS=$(date -u +%Y%m%dT%H%M%SZ)
KX="$L/NMXGPU.kext $L/NMXAccel.kext $L/NMXAGDC.kext $L/NMXBacklight.kext $L/NVRM.kext $L/NVAccel.kext $L/NVRMFB.kext $L/NVRMAGDC.kext $L/StrixS0ix.kext"
mkdir -p /Library/NullMoth
exec > >(tee -a "/Library/NullMoth/step126-$TS.log") 2>&1
relink() {
    rm -f "$KC.relink"
    kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
        -B /System/Library/KernelCollections/BootKernelExtensions.kc \
        -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
        --repository /Library/Extensions -A "$KC.relink" -z
    "$G/kccheck" "$KC.relink" --probes "$G/nmx-relink.probes" "$L/NMXGPU.kext/Contents/MacOS/NMXGPU" $KX
    grep -qa 'EC queries that ask for a full wake' "$KC.relink" || { echo "StrixS0ix >= 0.1.12 is not in the new AuxKC"; exit 1; }
    mv -f "$KC.relink" "$KC"; sync
    echo "AuxKC relinked and checked; reboot to load it"
}
if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/step126-bk-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/StrixS0ix.kext ]] || { echo "no backup"; exit 1; }
    rm -rf "$E"; ditto "$BK/StrixS0ix.kext" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
    echo "restored StrixS0ix from $BK"; relink; echo "Step126 undone; reboot to apply"; exit 0
fi
B=$REPO/build/StrixS0ix.kext
grep -qa 'root port DLL active at halt/wake' "$B/Contents/MacOS/StrixS0ix" || { echo "$B is not 0.1.13: scripts/build.sh StrixS0ix"; exit 1; }
BK=/Library/NullMoth/step126-bk-$TS; mkdir -p "$BK"
ditto "$E" "$BK/StrixS0ix.kext"; cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"; echo "backup $BK"
rm -rf "$E"; ditto "$B" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
echo "StrixS0ix $(shasum -a 256 "$E/Contents/MacOS/StrixS0ix" | cut -c1-16) installed"
relink
grep -qa 'root port DLL active at halt/wake' "$KC" || { echo "0.1.13 is not in the AuxKC"; exit 1; }
echo "Step126 installed: StrixS0ix 0.1.13 (NBIO link trace) in AuxKC; reboot to load it"
