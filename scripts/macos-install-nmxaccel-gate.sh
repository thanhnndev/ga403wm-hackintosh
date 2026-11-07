#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Run as root: install an NMXAccel.kext built from nmxaccel-family-gate (display pipe gated on the IOAcceleratorFamily2
# layout instead of the exact 25G241 kernel string), relink the AuxKC the way auxguard does, and check it.
#   macos-install-nmxaccel-gate.sh <NMXAccel.kext>
#   macos-install-nmxaccel-gate.sh --undo        put back the NMXAccel saved by the last install, relink
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
L=/Library/Extensions; E=$L/NMXAccel.kext; KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
G=/Library/StrixGraphicsFix; TS=$(date -u +%Y%m%dT%H%M%SZ)
KX="$L/NMXGPU.kext $L/NMXAccel.kext $L/NMXAGDC.kext $L/NMXBacklight.kext $L/NVRM.kext $L/NVAccel.kext $L/NVRMFB.kext $L/NVRMAGDC.kext $L/StrixS0ix.kext"
relink() {
    rm -f "$KC.relink"
    kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
        -B /System/Library/KernelCollections/BootKernelExtensions.kc \
        -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
        --repository /Library/Extensions -A "$KC.relink" -z
    "$G/kccheck" "$KC.relink" --probes "$G/nmx-relink.probes" "$L/NMXGPU.kext/Contents/MacOS/NMXGPU" $KX
    cp -p "$KC" "$G/AuxKC.before-gate.$TS"; mv -f "$KC.relink" "$KC"; sync
    echo "AuxKC relinked and checked; reboot to load it"
}
if [ "${1:-}" = --undo ]; then
    BK=$(ls -d "$G"/nmxaccel-gate-bk-* | sort | tail -1)
    rm -rf "$E"; ditto "$BK/NMXAccel.kext" "$E"; chown -R 0:0 "$E"; relink; exit 0
fi
N=${1:?path to the new NMXAccel.kext}
strings -a "$N/Contents/MacOS/NMXAccel" | grep -q "family layout gate" || { echo "$N is not the family-gate build"; exit 1; }
mkdir -p "$G/nmxaccel-gate-bk-$TS"; ditto "$E" "$G/nmxaccel-gate-bk-$TS/NMXAccel.kext"
rm -rf "$E"; ditto "$N" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
relink
