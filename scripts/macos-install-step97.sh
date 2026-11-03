#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step97 (macOS, run as root): NMXGPU lost-interrupt watch (scripts/nmx-irqwatch). On some boots the GPU's
# interrupts stop ~1 s after NMXGPU loads and every fence then completes only through the 0.5 s fallback timer
# (2026-11-03 23:09 boot: WindowServer crash loop, forced reboot). The cave detects that state in the fallback timer,
# logs the IH/PCI/MSI/event-source evidence once per episode ("NMX irqwatch:" lines), and keeps the desktop alive
# by polling the IH ring from a 2 ms fallback timer until the real interrupt handler dispatches again.
# Step97b (scripts/nmx-mmfix): the login crash loop of the 2026-11-03 boot. xkpi can free a process's mm from a
# kernel worker (linux_mm_dtor leaves proc->p_lkpi_mm dangling) and the next mm can be a different object, so
# amdgpu_bo_list_create's "userptr BO mm == current mm" check failed every WindowServer CS (-EPERM -> "CS rejected
# (-1)" -> WindowServer abort -> loginwindow loop). The mm is no longer freed (a small leak per process exit) and the
# check logs "NMX mmfix:" instead of failing.
# Input is the installed Step96 NMXGPU (44c7e552...); NMXAccel is not touched.
#
#   sudo scripts/macos-install-step97.sh
#   sudo scripts/macos-install-step97.sh --undo     # NMXGPU back to the Step96 build + relink
#   From Linux: pkexec scripts/linux-undo-step97.sh
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
G=/Library/Extensions/NMXGPU.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
STEP96=44c7e55201a3bcfb
CAVE_SHA=51cd5c3f8f94cb05e47b76abfd459ac39be3e23e9e94b651146b39b79da5d391
MM_SHA=2d7ab843b134cf24b1b029bc52b8b54692643fb92846ebfadc2c6a8625a2473a
RESULT=c2326f228e774181d6cdf6bbdc68af953b5380282274dfb0fb3284dd221697ce
exec > >(tee -a "/Library/NullMoth/step97-$TS.log") 2>&1

if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/step97-bk-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/NMXGPU.kext ]] || { echo "no step97 backup"; exit 1; }
    rm -rf "$G"; ditto "$BK/NMXGPU.kext" "$G"
    echo "restored NMXGPU from $BK"
else
    [[ $(shasum -a 256 "$HERE/nmx-irqwatch/cave.bin" | cut -d' ' -f1) == "$CAVE_SHA" ]] || { echo "cave.bin is not the reviewed build"; exit 1; }
    [[ $(shasum -a 256 "$HERE/nmx-mmfix/cave.bin" | cut -d' ' -f1) == "$MM_SHA" ]] || { echo "nmx-mmfix/cave.bin is not the reviewed build"; exit 1; }
    CUR=$(shasum -a 256 "$G/Contents/MacOS/NMXGPU" | cut -c1-16)
    [[ $CUR == "$STEP96" ]] || { echo "NMXGPU is $CUR..., not the Step96 build -- not touching it"; exit 1; }
    BK=/Library/NullMoth/step97-bk-$TS
    mkdir -p "$BK"
    ditto "$G" "$BK/NMXGPU.kext"; cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
    echo "backup $BK"
    rm -rf "$G.new"; ditto "$G" "$G.new"
    /usr/bin/python3 -I "$HERE/nmx-irqwatch/step97_patch.py" "$G.new/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-mmfix/step97b_patch.py" "$G.new/Contents/MacOS/NMXGPU"
    [[ $(shasum -a 256 "$G.new/Contents/MacOS/NMXGPU" | cut -d' ' -f1) == "$RESULT" ]] || { echo "patched NMXGPU is not $RESULT"; rm -rf "$G.new"; exit 1; }
    chown -R 0:0 "$G.new"; chmod -R go-w "$G.new"
    rm -rf "$G"; mv "$G.new" "$G"
fi
shasum -a 256 "$G/Contents/MacOS/NMXGPU"

NEW=$KC.step97
rm -f "$NEW"
/usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
    --repository /Library/Extensions -A "$NEW" -z
[[ ${1:-} == --undo ]] || /usr/bin/python3 -I "$HERE/nmx-irqwatch/step97_patch.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
[[ ${1:-} == --undo ]] || /usr/bin/python3 -I "$HERE/nmx-mmfix/step97b_patch.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
mv -f "$NEW" "$KC"
sync
echo "RELINKED $(date -u): reboot to load it"
