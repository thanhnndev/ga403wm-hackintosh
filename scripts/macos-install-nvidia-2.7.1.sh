#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# NullMoth NVIDIA 2.7.1 on top of the 890M stack (run as root; one reboot afterwards). The 890M keeps the OLED, the
# display path and the brightness slider; NVIDIA stays the headless second GPU.
#   1. upstream install.sh from the verified package (NVRM/NVRMFB/NVAccel/NVRMAGDC, NVK userland, firmware). It keeps
#      NMXGPU.kext and copies /Library/NullMoth/gpu-userland (our patched RADV) back beside NVK.
#   2. NMXAudio.kext (new in the package) is taken out again: a new kext is what made kernelmanagerd rebuild the AuxKC
#      without NMXGPU in Step100b (black OLED). HDMI audio can come later in its own batch.
#   3. our 890M NVMTL plugin (desc-cache branch, scripts/nvmtl-desccache/install.sh) and our allow list (WindowServer
#      only since Step70) go back; the package's plugin lacks the 890M work and its allow list is "*".
#   4. own relink + checks: every NMXGPU patch probe, the cave registry, the eight kext UUIDs, again after 45 s.
# The NVRM boot guard and its bootguard job stay as upstream ships them (WindowServer is on the 890M now, so a parked
# NVIDIA driver no longer takes the desktop with it).
#   sudo scripts/macos-install-nvidia-2.7.1.sh
# Undo: sudo /Library/NullMoth/uninstall.sh <backup printed below> (2.5.2 back), then
#       sudo scripts/nvmtl-desccache/install.sh install, then restore the allow list copy saved in $STEP.
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
U=${SUDO_USER:-thanhnndev}; UH=$(eval echo "~$U")
PKG=$UH/efi-audit/upgrade-2.7.1/pkg/pkgroot
TAR=$UH/efi-audit/upgrade-2.7.1/dl/nullmoth-nvidia-2.7.1.tar.gz
TAR_SHA=0b28f420dbc0f8a796a8a67c60490b1909886d302fd2008ad884cc12231e7851
G=/Library/Extensions/NMXGPU.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
NMX_SHA=3e1b661990d08e35
TS=$(date -u +%Y%m%dT%H%M%SZ)
STEP=/Library/NullMoth/nv271-$TS
mkdir -p "$STEP"
exec > >(tee -a "$STEP/install.log") 2>&1

echo "== 0. checks"
[[ $(shasum -a 256 "$TAR" | cut -d' ' -f1) == "$TAR_SHA" ]] || { echo "package tarball is not the verified 2.7.1"; exit 1; }
[[ $(cat "$PKG/VERSION") == 2.7.1 ]] || { echo "$PKG is not 2.7.1"; exit 1; }
[[ $(shasum -a 256 "$G/Contents/MacOS/NMXGPU" | cut -c1-16) == "$NMX_SHA" ]] || { echo "NMXGPU is not the live Step100c build"; exit 1; }
cp -p /Library/GPUBundles/nvmtl-allow.txt "$STEP/nvmtl-allow.txt"
ditto /Library/GPUBundles/NVMTLDriver.bundle "$STEP/NVMTLDriver.bundle"
cp -p "$KC" "$STEP/AuxiliaryKernelExtensions.kc"
echo "saved allow list, plugin and AuxKC in $STEP"

echo "== 1. upstream installer"
set +e
/bin/bash "$PKG/install.sh"; rc=$?
set -e
[[ $rc == 0 ]] || { echo "upstream install.sh failed ($rc): it rolls itself back; nothing else changed"; exit 1; }
BK=$(grep -oE '/Library/NullMoth/backup-[0-9]{8}-[0-9]{6}\.[A-Za-z0-9]+' "$STEP/install.log" | tail -1 || true)
echo "upstream backup (2.5.2): ${BK:-none recorded}"
[[ $(shasum -a 256 "$G/Contents/MacOS/NMXGPU" | cut -c1-16) == "$NMX_SHA" ]] || { echo "the installer changed NMXGPU"; exit 1; }

echo "== 2. NMXAudio out (Step100b: a new kext made kernelmanagerd drop NMXGPU)"
if [[ -d /Library/Extensions/NMXAudio.kext ]]; then
    ditto /Library/Extensions/NMXAudio.kext "$STEP/NMXAudio.kext"
    rm -rf /Library/Extensions/NMXAudio.kext
    echo "NMXAudio.kext moved to $STEP"
fi

echo "== 3. 890M plugin and allow list back"
"$HERE/nvmtl-desccache/install.sh" install
install -o 0 -g 0 -m 644 "$STEP/nvmtl-allow.txt" /Library/GPUBundles/nvmtl-allow.txt
sudo -u _windowserver /bin/test -r /Library/GPUBundles/nvmtl-allow.txt || { echo "WindowServer cannot read the allow list"; exit 1; }
echo "allow list: $(grep -v '^#' /Library/GPUBundles/nvmtl-allow.txt | tr '\n' ' ')"

echo "== 4. relink and verify"
/usr/bin/python3 -I "$HERE/nmx-caves/check.py" "$G/Contents/MacOS/NMXGPU" || { echo "cave registry check failed -- not linking"; exit 1; }
NEW=$KC.nv271
rm -f /Library/KernelCollections/AuxiliaryKernelExtensions.kc.nv271
/usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
    --repository /Library/Extensions -A "$NEW" -z
B=$G/Contents/MacOS/NMXGPU
/usr/bin/python3 -I "$HERE/nmx-mmfix/step97b_patch.py" --check-kc "$NEW" "$B"
/usr/bin/python3 -I "$HERE/nmx-flip/step99_patch.py" --check-kc "$NEW" "$B"
/usr/bin/python3 -I "$HERE/nmx-irqfix/patch_irqfix.py" --check-kc "$NEW" "$B"
/usr/bin/python3 -I "$HERE/nmx-mmfix2/step100_mm_patch.py" --check-kc "$NEW" "$B"
uuids_in() {  # <kc>: every kext the boot needs must be linked in it
    local k u bad=0
    for k in NMXGPU NMXAccel NMXAGDC NMXBacklight NVRM NVAccel NVRMFB NVRMAGDC; do
        u=$(otool -l "/Library/Extensions/$k.kext/Contents/MacOS/$k" | awk '/LC_UUID/{f=1} f&&/uuid/{print $2; exit}' | tr -d -)
        if /usr/bin/python3 -I -c 'import sys; sys.exit(0 if bytes.fromhex(sys.argv[2]) in open(sys.argv[1],"rb").read() else 1)' "$1" "$u"; then
            echo "  $k in collection"; else echo "  $k MISSING"; bad=1; fi
    done
    return $bad
}
uuids_in "$NEW" || { echo "new collection is missing a kext -- not installed (old one stays)"; exit 1; }
mv -f "$NEW" "$KC"
sync
echo "relinked; checking again in 45 s (kernelmanagerd, Step100b)"
sleep 45
uuids_in "$KC" || { echo "AuxKC on disk lost a kext after the relink (kernelmanagerd?): run this script's step 4 again"; exit 1; }
echo "NVIDIA $(cat /Library/NullMoth/driver-version 2>/dev/null || echo 2.7.1) installed; 890M keeps OLED/display/brightness; reboot to load it"
