#!/bin/bash
# Step89 (macOS, run as root): NMXGPU binary patches and an optional CI NMXAccel, then the AuxKC is relinked in place
# so the NEXT boot loads them. Nothing changes for the running session.
#
#   sudo scripts/macos-patch-nmx-step89.sh [NMXAccel]   # patch (+ install a CI NMXAccel) + relink
#   sudo scripts/macos-patch-nmx-step89.sh --undo       # put the backed-up NMXGPU and NMXAccel back + relink
#
# 1. TTM order 0 (ttm_pool_alloc 0x5fd9b1): "cmpl $0xa,%eax; movl $0xa,%r12d; cmovbl %eax,%r12d" picks
#    min(fls(pages)-1, MAX_PAGE_ORDER=10) as the first order to try. Since Step88 GTT pages are cached, and upstream TTM
#    keeps no pool of cached pages on x86, every BO goes to linux_alloc_pages. On xkpi any order > 0 is
#    vm_page_alloc_noobj_contig -> IOBufferMemoryDescriptor::inTaskWithPhysicalMask -> cpm_allocate, which scans
#    for physically contiguous memory under xnu's free-page lock and blocks: 313 of 316 spindump samples of
#    WindowServer's GEM_CREATE, and ~70% of its render thread (NVMTL makes a new image per surface).
#    With both immediates 0 the order is always 0, and order-0 pages come from xkpi's 2 MB chunk free list
#    (vm_page_alloc_noobj, a spinlocked list pop). GTT gets 4 KB PTEs only, as order-0 Linux allocations do.
# 2. ibprobe v2 (scripts/nmx-ibprobe/cave.s): its lines are readable (snprintf + NMXGPU's own "%s\n") and also print
#    pasid, vm, mapping and bo. Only runs on a GFX ring timeout.
# 3. Optional NMXAccel from CI (nvidia-macos-driver ci/nmxaccel 414a235): the beam-paced K6 copy sleeps through its
#    waits instead of spinning (~3.4 ms of CPU per frame).
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
E=/Library/Extensions/NMXGPU.kext
A=/Library/Extensions/NMXAccel.kext
BIN=$E/Contents/MacOS/NMXGPU
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
LOG=/Library/NullMoth/step89-$TS.log
NEWACCEL=""
[[ ${1:-} != --undo && -n ${1:-} ]] && NEWACCEL=$1
exec > >(tee -a "$LOG") 2>&1

if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/nmx-step89-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -f $BK/NMXGPU.kext/Contents/MacOS/NMXGPU ]] || { echo "no step89 backup"; exit 1; }
    rm -rf "$E"; ditto "$BK/NMXGPU.kext" "$E"
    if [[ -d $BK/NMXAccel.kext ]]; then rm -rf "$A"; ditto "$BK/NMXAccel.kext" "$A"; fi
    echo "restored NMXGPU and NMXAccel from $BK"
else
    BK=/Library/NullMoth/nmx-step89-$TS
    mkdir -p "$BK"
    ditto "$E" "$BK/NMXGPU.kext"
    ditto "$A" "$BK/NMXAccel.kext"
    cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
    echo "backup $BK"
    /usr/bin/python3 -I "$HERE/nmx-ibprobe/step89_patch.py" "$BIN" "$HERE/nmx-ibprobe"
    if [[ -n $NEWACCEL ]]; then
        /usr/bin/python3 -I "$HERE/nmx-ibprobe/step89_patch.py" --check-accel "$NEWACCEL"
        install -o 0 -g 0 -m 755 "$NEWACCEL" "$A/Contents/MacOS/NMXAccel"
    fi
fi
shasum -a 256 "$BIN" "$A/Contents/MacOS/NMXAccel"

NEW=$KC.step89
rm -f "$NEW"
/usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
    --repository /Library/Extensions -A "$NEW" -z
# the new collection must hold what is now on disk (a binary patch keeps the UUID, so look for the patched bytes)
/usr/bin/python3 -I "$HERE/nmx-ibprobe/step89_patch.py" --check-kc "$NEW" "$BIN" "$A/Contents/MacOS/NMXAccel"
mv -f "$NEW" "$KC"
# NullMoth restores NMXAccel from this copy; keep it the one now in /Library/Extensions (as nmx-relink.sh does)
rm -rf /Library/NullMoth/kexts/26/NMXAccel.kext
mkdir -p /Library/NullMoth/kexts/26
ditto "$A" /Library/NullMoth/kexts/26/NMXAccel.kext
sync
echo "RELINKED $(date -u): reboot to load it"
