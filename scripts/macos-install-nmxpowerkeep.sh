#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Installs NMXBacklight 0.2.0+ (NMXPowerKeep: NMXGPU stays powered during display sleep; 0.3.0 adds the sleep/wake timeline) into /Library/Extensions
# and relinks the auxiliary kernel collection. Loads at the next boot. Run as root.
#   sudo scripts/macos-install-nmxpowerkeep.sh          install build/NMXBacklight.kext
#   sudo scripts/macos-install-nmxpowerkeep.sh --undo   put back the kext and the collection saved by the last install
# Off switch without undo: boot-arg -nmxkeepoff (the backlight part keeps working).
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$HERE")
E=/Library/Extensions/NMXBacklight.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
TS=$(date -u +%Y%m%dT%H%M%SZ)

kc_has() {  # $1 = kext name: is that binary's LC_UUID in the collection on disk?
    local u; u=$(otool -l "/Library/Extensions/$1.kext/Contents/MacOS/$1" | awk '/LC_UUID/{f=1} f&&/uuid/{print $2; exit}' | tr -d -)
    /usr/bin/python3 -I -c 'import sys; sys.exit(0 if bytes.fromhex(sys.argv[2]) in open(sys.argv[1],"rb").read() else 1)' "$KC" "$u"
}
relink() {
    local new=$KC.powerkeep
    rm -f "$new"
    /usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
        -B /System/Library/KernelCollections/BootKernelExtensions.kc \
        -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
        --repository /Library/Extensions -A "$new" -z
    mv -f "$new" "$KC"; sync
    # kernelmanagerd once replaced a fresh collection with its own list (no NMXGPU/NMXAGDC, Step100b): check again later
    sleep 45
    for b in NMXGPU NMXAccel NMXAGDC NMXBacklight; do
        kc_has "$b" || { echo "AuxKC on disk lost $b after the relink (kernelmanagerd?): run this script again"; exit 1; }
    done
    echo "AuxKC holds NMXGPU, NMXAccel, NMXAGDC, NMXBacklight after 45 s; reboot to load it"
}

if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/nmxpowerkeep-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/NMXBacklight.kext ]] || { echo "no backup"; exit 1; }
    rm -rf "$E"; ditto "$BK/NMXBacklight.kext" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
    echo "restored NMXBacklight from $BK"
    relink; exit 0
fi

B=$REPO/build/NMXBacklight.kext
grep -qa 'NMXPowerKeep: holding' "$B/Contents/MacOS/NMXBacklight" || { echo "$B has no NMXPowerKeep: run scripts/build.sh NMXBacklight"; exit 1; }
BK=/Library/NullMoth/nmxpowerkeep-$TS
mkdir -p "$BK"; ditto "$E" "$BK/NMXBacklight.kext"; cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
echo "backup $BK"
rm -rf "$E"; ditto "$B" "$E"; chown -R 0:0 "$E"; chmod -R go-w "$E"
echo "NMXBacklight $(shasum -a 256 "$E/Contents/MacOS/NMXBacklight" | cut -c1-16) installed"
relink
