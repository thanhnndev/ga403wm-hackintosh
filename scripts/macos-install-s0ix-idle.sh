#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# StrixS0ix 0.1.14 (macOS, run as root): runtime CPU idle hook (pmDispatch MachineIdle, docs/CPU-THERMALS.md).
# It loads in mode 0 = the kernel's own "sti; hlt; cli", so installing it changes nothing until it is switched on live:
#   sudo build/s0ix-set idle 1        HLT for short idles, _CST C2 (IO 0x414, CC6) for predicted idles >= 40 us
#   sudo build/s0ix-set idle 2        + _CST C3 (IO 0x415) for >= 2 ms when PM1 BM_STS is clear
#   sudo build/s0ix-set idle 0        back to HLT;  sudo build/s0ix-set idlestats reset|show -> ioreg S0ix,IdleStats
# Boot-arg s0ix_idle=N makes a mode the boot default; -s0ixidleoff leaves MachineIdle unregistered.
# Relinks the AuxKC the way scripts/macos-install-step126.sh does (kccheck + nmx-relink.probes).
#   sudo scripts/macos-install-s0ix-idle.sh
#   sudo scripts/macos-install-s0ix-idle.sh --undo   # back to the StrixS0ix saved by this script, relink
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$HERE/.." && pwd)
L=/Library/Extensions; E=$L/StrixS0ix.kext; KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
G=/Library/StrixGraphicsFix; TS=$(date -u +%Y%m%dT%H%M%SZ)
KX="$L/NMXGPU.kext $L/NMXAccel.kext $L/NMXAGDC.kext $L/NVRM.kext $L/NVAccel.kext $L/NVRMFB.kext $L/NVRMAGDC.kext $L/StrixS0ix.kext"
mkdir -p /Library/NullMoth
exec > >(tee -a "/Library/NullMoth/s0ix-idle-$TS.log") 2>&1
relink() {
    rm -f "$KC.relink"
    kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
        -B /System/Library/KernelCollections/BootKernelExtensions.kc \
        -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
        --repository /Library/Extensions -A "$KC.relink" -z
    "$G/kccheck" "$KC.relink" --probes "$G/nmx-relink.probes" "$L/NMXGPU.kext/Contents/MacOS/NMXGPU" $KX
    mv -f "$KC.relink" "$KC"; sync
    echo "AuxKC relinked and checked; reboot to load it"
}
if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/s0ix-idle-bk-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/StrixS0ix.kext ]] || { echo "no backup"; exit 1; }
    rm -rf "$E"; ditto "$BK/StrixS0ix.kext" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
    echo "restored StrixS0ix from $BK"; relink; exit 0
fi
B=$REPO/build/StrixS0ix.kext
grep -qa 'runtime idle mode now' "$B/Contents/MacOS/StrixS0ix" || { echo "$B is not 0.1.14: scripts/build.sh StrixS0ix"; exit 1; }
BK=/Library/NullMoth/s0ix-idle-bk-$TS; mkdir -p "$BK"
ditto "$E" "$BK/StrixS0ix.kext"; cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"; echo "backup $BK"
rm -rf "$E"; ditto "$B" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
echo "StrixS0ix $(shasum -a 256 "$E/Contents/MacOS/StrixS0ix" | cut -c1-16) installed"
relink
grep -qa 'runtime idle mode now' "$KC" || { echo "0.1.14 is not in the AuxKC"; exit 1; }
echo "StrixS0ix 0.1.14 in AuxKC (idle mode 0 at boot); reboot to load it, then: sudo build/s0ix-set idle 1"
