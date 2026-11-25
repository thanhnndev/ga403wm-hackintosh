#!/bin/bash
# One boot repair/collection after Linux stages the current graphics bundles.
# Run as root by com.itlmt7925.graphics-bootstrap. Does not reboot the machine.
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
ROOT=/Library/StrixGraphicsFix
mkdir -p /Library/Logs/StrixGraphicsFix
OUT=/Library/Logs/StrixGraphicsFix/$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$OUT"
exec >"$OUT/bootstrap.log" 2>&1
date -u
sw_vers
sleep 15

bundles=(NVRM NVRMEdpBL NVRMFB NVRMAGDC NVAccel StrixAccel StrixGOP)
ids=(com.nullmoth.NVRM com.nullmoth.NVRMEdpBL com.nullmoth.NVRMFB
     com.nullmoth.NVRMAGDC com.nullmoth.NVAccel com.itlmt7925.strixaccel com.itlmt7925.strixgop)
snapshot() {
    kmutil showloaded >"$OUT/loaded-$1.txt" 2>&1
    ioreg -rc StrixGOPFramebuffer -l >"$OUT/gop-$1.txt"
    ioreg -rc StrixAccelerator -l >"$OUT/accel-$1.txt"
    ioreg -rc StrixMetalGate -l >"$OUT/gate-$1.txt"
}
missing() {
    local id
    for id in "${ids[@]}"; do
        grep -Fq "$id (" "$1" || return 0
    done
    return 1
}
snapshot before
if missing "$OUT/loaded-before.txt"; then
    args=()
    for bundle in "${bundles[@]}"; do args+=(-p "/Library/Extensions/$bundle.kext"); done
    kmutil load --no-authorization "${args[@]}"
    rc=$?
    echo "kmutil_load_exit=$rc"
    snapshot after
    if missing "$OUT/loaded-after.txt"; then
        if [[ $rc == 0 || $rc == 27 || $rc == 28 ]]; then
            echo REBOOT_REQUIRED | tee "$ROOT/status"
        else
            echo "LOAD_FAILED exit=$rc" | tee "$ROOT/status"
        fi
    else
        echo DRIVERS_LOADED | tee "$ROOT/status"
    fi
else
    echo DRIVERS_LOADED | tee "$ROOT/status"
fi
log show --last 3m --style compact --predicate \
    'process == "WindowServer" OR (process == "kernel" AND (eventMessage CONTAINS "Strix" OR eventMessage CONTAINS "NVRM" OR eventMessage CONTAINS "NVAccel"))' \
    >"$OUT/display-log.txt" 2>&1
ps -axo pid,lstart,comm | grep WindowServer >"$OUT/windowserver.txt"
echo "Evidence: $OUT"
