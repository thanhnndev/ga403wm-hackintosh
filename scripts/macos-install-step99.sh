#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step99 (macOS, run as root): zero-copy page flips (mode 1) and flips on by default at boot.
# - NMXGPU = the Step97 build (c2326f22, kept in the Step98 backup) + scripts/nmx-flip step99_patch.py:
#   - the flip cave (mode 2 as in Step98b; the home buffer is now pinned for every mode);
#   - the import cave (nmxFlipImport: the IOSurface pages as a GTT scan-out buffer);
#   - the home buffer forced into VRAM;
#   - DC brought up with GPU VM (amdgpu_sg_display left at -1). This touches the boot-critical display bring-up.
# - LaunchDaemon com.ga403wm.nmx-flip-default: sets sysctl debug.nmxaccel_flip to the mode in
#   /Library/StrixGraphicsFix/nmx-flip.mode (2 = VRAM chain). Mode 1 is switched on by hand until it has run on this
#   machine.
# NMXAccel is the Step98 flip build, unchanged.
#
#   sudo scripts/macos-install-step99.sh
#   sudo scripts/macos-install-step99.sh --undo     # NMXGPU back to Step98b, daemon removed, relink
#   From Linux: pkexec scripts/linux-undo-step99.sh
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
G=/Library/Extensions/NMXGPU.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
PL=/Library/LaunchDaemons/com.ga403wm.nmx-flip-default.plist
SH=/Library/StrixGraphicsFix/nmx-flip-default.sh
MODEF=/Library/StrixGraphicsFix/nmx-flip.mode
STEP98B=da12984634097e2d
STEP97=c2326f228e774181
SRC=/Library/NullMoth/step98-bk-20261103T171105Z/NMXGPU.kext
CAVE_SHA=21e168f64251687187d1333aabc037551b21b1302e9cf41a73a6723a81cfb492
IMPORT_SHA=d2b3ca86a9a483219a11d87afbce4021aca92a4e24785b84b568293ee5eb2d22
RESULT=1907d9f993e920b5695038bcf8b2b4cf73b04a265f825738527ab24f14955e6d
exec > >(tee -a "/Library/NullMoth/step99-$TS.log") 2>&1

if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/step99-bk-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/NMXGPU.kext ]] || { echo "no step99 backup"; exit 1; }
    rm -rf /Library/Extensions/NMXGPU.kext; ditto "$BK/NMXGPU.kext" /Library/Extensions/NMXGPU.kext
    launchctl bootout system "$PL" 2>/dev/null || true
    rm -f /Library/LaunchDaemons/com.ga403wm.nmx-flip-default.plist /Library/StrixGraphicsFix/nmx-flip-default.sh
    echo "restored NMXGPU from $BK, flip default daemon removed"
else
    [[ $(shasum -a 256 "$HERE/nmx-flip/cave.bin" | cut -d' ' -f1) == "$CAVE_SHA" ]] || { echo "nmx-flip/cave.bin is not the reviewed build"; exit 1; }
    [[ $(shasum -a 256 "$HERE/nmx-flip/import.bin" | cut -d' ' -f1) == "$IMPORT_SHA" ]] || { echo "nmx-flip/import.bin is not the reviewed build"; exit 1; }
    CUR=$(shasum -a 256 "$G/Contents/MacOS/NMXGPU" | cut -c1-16)
    [[ $CUR == "$STEP98B" ]] || { echo "NMXGPU is $CUR..., not the Step98b build -- not touching it"; exit 1; }
    [[ $(shasum -a 256 "$SRC/Contents/MacOS/NMXGPU" | cut -c1-16) == "$STEP97" ]] || { echo "$SRC is not the Step97 build"; exit 1; }
    BK=/Library/NullMoth/step99-bk-$TS
    mkdir -p "$BK"
    ditto "$G" "$BK/NMXGPU.kext"; cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
    echo "backup $BK"
    rm -rf /Library/Extensions/NMXGPU.kext.new; ditto "$SRC" "$G.new"
    /usr/bin/python3 -I "$HERE/nmx-flip/step99_patch.py" "$G.new/Contents/MacOS/NMXGPU"
    [[ $(shasum -a 256 "$G.new/Contents/MacOS/NMXGPU" | cut -d' ' -f1) == "$RESULT" ]] || { echo "patched NMXGPU is not $RESULT"; rm -rf /Library/Extensions/NMXGPU.kext.new; exit 1; }
    chown -R 0:0 "$G.new"; chmod -R go-w "$G.new"
    rm -rf /Library/Extensions/NMXGPU.kext; mv "$G.new" "$G"
    install -o 0 -g 0 -m 755 "$HERE/nmx-flip/boot/nmx-flip-default.sh" "$SH"
    install -o 0 -g 0 -m 644 "$HERE/nmx-flip/boot/com.ga403wm.nmx-flip-default.plist" "$PL"
    [[ -f $MODEF ]] || echo 2 > "$MODEF"
    echo "flip default daemon installed, mode $(cat "$MODEF")"
fi
shasum -a 256 "$G/Contents/MacOS/NMXGPU"

NEW=$KC.step99
rm -f /Library/KernelCollections/AuxiliaryKernelExtensions.kc.step99
/usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
    --repository /Library/Extensions -A "$NEW" -z
if [[ ${1:-} != --undo ]]; then
    /usr/bin/python3 -I "$HERE/nmx-irqwatch/step97_patch.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-mmfix/step97b_patch.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-flip/step99_patch.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
fi
mv -f "$NEW" "$KC"
sync
echo "RELINKED $(date -u): reboot to load it"
