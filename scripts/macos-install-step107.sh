#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step107 (macOS, run as root): one reboot batch for system sleep on the s0ix (Modern Standby) path.
# - NMXGPU = Step100c (3e1b6619) + scripts/nmx-s0ix (amdgpu suspends through its s0ix path, not S3) -> 2a1bb264.
# - NMXBacklight 0.3.0 (NMXPowerKeep + system sleep/wake timeline in the log and PowerKeep,Sys* properties).
#
#   sudo scripts/macos-install-step107.sh
#   sudo scripts/macos-install-step107.sh --undo   # NMXGPU and NMXBacklight back to the backup, relink
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
G=/Library/Extensions/NMXGPU.kext
E=/Library/Extensions/NMXBacklight.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
BASE=3e1b661990d08e35
RESULT=2a1bb26463164e9a
BL_SHA=f4d904c5214c9451fbcd9466e70f03e9d9ed2082c6355d08cbec03d11d731527
mkdir -p /Library/NullMoth
exec > >(tee -a "/Library/NullMoth/step107-$TS.log") 2>&1

if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/step107-bk-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/NMXGPU.kext && -d $BK/NMXBacklight.kext ]] || { echo "no step107 backup"; exit 1; }
    rm -rf "$G" "$E"; ditto "$BK/NMXGPU.kext" "$G"; ditto "$BK/NMXBacklight.kext" "$E"
    echo "restored NMXGPU and NMXBacklight from $BK"
else
    CUR=$(shasum -a 256 "$G/Contents/MacOS/NMXGPU" | cut -c1-16)
    [[ $CUR == "$BASE" ]] || { echo "NMXGPU is $CUR..., not the Step100c build -- not touching it"; exit 1; }
    [[ $(shasum -a 256 "$REPO/build/NMXBacklight.kext/Contents/MacOS/NMXBacklight" | cut -d' ' -f1) == "$BL_SHA" ]] || { echo "build/NMXBacklight.kext is not the reviewed build"; exit 1; }
    BK=/Library/NullMoth/step107-bk-$TS
    mkdir -p "$BK"
    ditto "$G" "$BK/NMXGPU.kext"; ditto "$E" "$BK/NMXBacklight.kext"; cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
    echo "backup $BK"
    rm -rf "$G.new"; ditto "$G" "$G.new"
    /usr/bin/python3 -I "$HERE/nmx-s0ix/patch_s0ix.py" "$G.new/Contents/MacOS/NMXGPU"
    [[ $(shasum -a 256 "$G.new/Contents/MacOS/NMXGPU" | cut -c1-16) == "$RESULT" ]] || { echo "patched NMXGPU is not $RESULT"; rm -rf "$G.new"; exit 1; }
    /usr/bin/python3 -I "$HERE/nmx-caves/check.py" "$G.new/Contents/MacOS/NMXGPU" || { echo "cave registry check failed"; rm -rf "$G.new"; exit 1; }
    chown -R 0:0 "$G.new"; chmod -R go-w "$G.new"
    rm -rf "$G"; mv "$G.new" "$G"
    rm -rf "$E"; ditto "$REPO/build/NMXBacklight.kext" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
    echo "NMXGPU $RESULT and NMXBacklight 0.3.0 installed"
fi
NEW=$KC.step107
rm -f "$NEW"
/usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
    --repository /Library/Extensions -A "$NEW" -z
if [[ ${1:-} != --undo ]]; then
    /usr/bin/python3 -I "$HERE/nmx-mmfix/step97b_patch.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-flip/step99_patch.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-irqfix/patch_irqfix.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-mmfix2/step100_mm_patch.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-s0ix/patch_s0ix.py" --check-kc "$NEW" "$G/Contents/MacOS/NMXGPU"
    grep -qa 'sleep/wake interest' "$NEW" || { echo "NMXBacklight 0.3.0 is not in the new collection"; exit 1; }
fi
mv -f "$NEW" "$KC"; sync
# kernelmanagerd once replaced a fresh collection with its own list (Step100b): check again after it had time to act
sleep 45
for b in NMXGPU NMXAccel NMXAGDC NMXBacklight; do
    u=$(otool -l "/Library/Extensions/$b.kext/Contents/MacOS/$b" | awk '/LC_UUID/{f=1} f&&/uuid/{print $2; exit}' | tr -d -)
    /usr/bin/python3 -I -c 'import sys; sys.exit(0 if bytes.fromhex(sys.argv[2]) in open(sys.argv[1],"rb").read() else 1)' "$KC" "$u" \
        || { echo "AuxKC on disk lost $b after the relink (kernelmanagerd?): run this script again"; exit 1; }
done
echo "RELINKED $(date -u): AuxKC holds NMXGPU, NMXAccel, NMXAGDC, NMXBacklight; reboot to load it"
