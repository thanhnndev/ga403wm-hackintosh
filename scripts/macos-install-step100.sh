#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step100 (macOS, run as root): one reboot batch.
# - NMXGPU = Step99 (1907d9f9) + scripts/nmx-irqfix (H2: no printf on the IH thread; irqwatch rebuilt as a safety net
#   that names a blocked handler) + scripts/nmx-mmfix2 (stale xkpi thread/process records retired) -> d4830f51.
# - NMXBacklight.kext (kexts/NMXBacklight): brightness slider and keys through amdgpu DC's backlight.
# - NVMTLDriver desc-cache build (fork branch desc-cache d5da629) through scripts/nvmtl-desccache/install.sh.
#
#   sudo scripts/macos-install-step100.sh
#   sudo scripts/macos-install-step100.sh --undo   # NMXGPU back to Step99, NMXBacklight removed, plugin restored, relink
#   From Linux: pkexec scripts/linux-undo-step100.sh
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
G=/Library/Extensions/NMXGPU.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
STEP99=1907d9f993e920b5
RESULT=d4830f51a1f71664a9ed8e38d33b2327b818f84f75a0d2ce6807f4b729b17848
BL_SHA=8a57847a2892121e7a955429393ac4c940b6430c9bbc70a655947689dbdb150e
PLUGIN=$(dirname "$REPO")/nmx-plugin-890m/out/plugin-desccache-d5da629/NVMTLDriver
exec > >(tee -a "/Library/NullMoth/step100-$TS.log") 2>&1

if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/step100-bk-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/NMXGPU.kext ]] || { echo "no step100 backup"; exit 1; }
    rm -rf /Library/Extensions/NMXGPU.kext; ditto "$BK/NMXGPU.kext" /Library/Extensions/NMXGPU.kext
    rm -rf /Library/Extensions/NMXBacklight.kext
    "$HERE/nvmtl-desccache/install.sh" undo || echo "plugin undo failed (see above)"
    echo "restored NMXGPU from $BK, NMXBacklight removed"
else
    CUR=$(shasum -a 256 "$G/Contents/MacOS/NMXGPU" | cut -c1-16)
    if [[ $CUR == "${RESULT:0:16}" ]] && ls -d /Library/NullMoth/step100-bk-* >/dev/null 2>&1; then
        echo "NMXGPU already Step100 (an earlier run stopped later): keeping it, continuing"
    else
    [[ $CUR == "$STEP99" ]] || { echo "NMXGPU is $CUR..., not the Step99 build -- not touching it"; exit 1; }
    BK=/Library/NullMoth/step100-bk-$TS
    mkdir -p "$BK"
    ditto "$G" "$BK/NMXGPU.kext"; cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
    echo "backup $BK"
    rm -rf /Library/Extensions/NMXGPU.kext.new; ditto "$G" "$G.new"
    /usr/bin/python3 -I "$HERE/nmx-irqfix/patch_irqfix.py" "$G.new/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-mmfix2/step100_mm_patch.py" "$G.new/Contents/MacOS/NMXGPU"
    [[ $(shasum -a 256 "$G.new/Contents/MacOS/NMXGPU" | cut -d' ' -f1) == "$RESULT" ]] || { echo "patched NMXGPU is not $RESULT"; rm -rf /Library/Extensions/NMXGPU.kext.new; exit 1; }
    chown -R 0:0 "$G.new"; chmod -R go-w "$G.new"
    rm -rf /Library/Extensions/NMXGPU.kext; mv "$G.new" "$G"
    fi
    [[ $(shasum -a 256 "$REPO/build/NMXBacklight.kext/Contents/MacOS/NMXBacklight" | cut -d' ' -f1) == "$BL_SHA" ]] || { echo "build/NMXBacklight.kext is not the reviewed build"; exit 1; }
    rm -rf /Library/Extensions/NMXBacklight.kext
    ditto "$REPO/build/NMXBacklight.kext" /Library/Extensions/NMXBacklight.kext
    chown -R 0:0 /Library/Extensions/NMXBacklight.kext; chmod -R go-w /Library/Extensions/NMXBacklight.kext
    echo "NMXBacklight installed"
    "$HERE/nvmtl-desccache/install.sh" install "$PLUGIN"
fi
shasum -a 256 "$G/Contents/MacOS/NMXGPU"

# every cave's code and borrowed data must be registered and disjoint (Step100c: irqfix ST[] ran into the flip lock)
/usr/bin/python3 -I "$HERE/nmx-caves/check.py" "$G/Contents/MacOS/NMXGPU" || { echo "cave registry check failed -- not linking"; exit 1; }
install -o 0 -g 0 -m 755 "$HERE/nmx-caves/check.py" /Library/StrixGraphicsFix/nmx-caves-check.py
NEW=$KC.step100
rm -f /Library/KernelCollections/AuxiliaryKernelExtensions.kc.step100
/usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
    --repository /Library/Extensions -A "$NEW" -z
if [[ ${1:-} != --undo ]]; then
    /usr/bin/python3 -I "$HERE/nmx-mmfix/step97b_patch.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-flip/step99_patch.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-irqfix/patch_irqfix.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-mmfix2/step100_mm_patch.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
    grep -qa 'NMXBacklight: NMXGPU at' "$NEW" || { echo "NMXBacklight is not in the new collection"; exit 1; }
    echo "NMXBacklight: in the new collection"
fi
mv -f "$NEW" "$KC"
sync
# Step100 boot: kernelmanagerd replaced this collection 7 s after the mv (NMXBacklight was a new kext) with one built
# from its own list, without NMXGPU/NMXAGDC. Check the file again once it has had time to act.
sleep 45
for b in NMXGPU NMXAccel NMXAGDC NMXBacklight; do
    u=$(otool -l "/Library/Extensions/$b.kext/Contents/MacOS/$b" | awk '/LC_UUID/{f=1} f&&/uuid/{print $2; exit}' | tr -d -)
    /usr/bin/python3 -I -c 'import sys; sys.exit(0 if bytes.fromhex(sys.argv[2]) in open(sys.argv[1],"rb").read() else 1)' "$KC" "$u" \
        || { echo "AuxKC on disk lost $b after the relink (kernelmanagerd?): run this script again"; exit 1; }
done
echo "AuxKC still holds NMXGPU, NMXAccel, NMXAGDC, NMXBacklight after 45 s"
echo "RELINKED $(date -u): reboot to load it"
