#!/bin/bash
# Runs as root at every boot (com.ga403wm.auxguard). Fresh-install guard for the GA403 graphics stack:
# 1. kernelmanagerd may rebuild the AuxKC from its own list (no NMXGPU/NMXAGDC, Step100b). Check it with kccheck
#    (no python/otool needed) and relink if it was replaced.
# 2. Run ws-sandbox-dri.sh once (adds the /dev/dri rule to WindowServer's sandbox, blesses a snapshot, reboots).
# 3. If only the AuxKC was rebuilt, reboot so it loads (at most 2 times, counted in auxguard.reboots).
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
ROOT=/Library/StrixGraphicsFix
exec >>"$ROOT/auxguard.log" 2>&1
echo "== $(date -u '+%F %T') build $(sw_vers -buildVersion)"
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
L=/Library/Extensions
KX="$L/NMXGPU.kext $L/NMXAccel.kext $L/NMXAGDC.kext $L/NMXBacklight.kext $L/NVRM.kext $L/NVAccel.kext $L/NVRMFB.kext $L/NVRMAGDC.kext $L/StrixS0ix.kext"
check() { "$ROOT/kccheck" "$1" --probes "$ROOT/nmx-relink.probes" "$L/NMXGPU.kext/Contents/MacOS/NMXGPU" $KX; }
build() {
    rm -f "$KC.relink"
    kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
        -B /System/Library/KernelCollections/BootKernelExtensions.kc \
        -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
        --repository /Library/Extensions -A "$KC.relink" -z || return 1
    check "$KC.relink" || return 1
    cp -p "$KC" "$ROOT/AuxKC.replaced.$(date -u +%Y%m%dT%H%M%SZ)" 2>/dev/null
    mv -f "$KC.relink" "$KC"; sync
}
sleep 45
rebuilt=0
if check "$KC"; then echo "AuxKC ok"; else
    echo "AuxKC missing our kexts: relinking"
    if build; then rebuilt=1; echo RELINKED; else rm -f "$KC.relink"; echo RELINK_FAILED; fi
fi
if [ ! -f "$ROOT/ws-sandbox-dri.done" ]; then
    echo "running ws-sandbox-dri.sh"; /bin/bash "$ROOT/ws-sandbox-dri.sh"; cat "$ROOT/ws-sandbox-dri.status"
    exit 0
fi
if [ $rebuilt = 1 ]; then
    n=$(cat "$ROOT/auxguard.reboots" 2>/dev/null || echo 0)
    if [ "$n" -lt 2 ]; then echo $((n + 1)) >"$ROOT/auxguard.reboots"; echo "rebooting to load the new AuxKC"; sync; /sbin/shutdown -r now; fi
fi
exit 0
