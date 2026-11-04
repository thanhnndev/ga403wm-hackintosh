#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step102: Metal for sandboxed apps on the 890M (run as root; one reboot afterwards).
# The App Sandbox refuses /dev/dri ("deny file-read-data /dev/dri"), so sandboxed apps (TextEdit, App Store apps,
# browser GPU processes) found no GPU and drew on the CPU. Two pieces, both in the fork:
#   - NMXAccel (branch ci/nmxaccel-drmuc): an NMDR user client on the accelerator. The sandbox allows user clients of an
#     IOAccelerator; the kernel opens the render node for the caller and runs its ioctls on it.
#   - NVMTL plugin (branch desc-cache 923deca): only in sandboxed processes, RADV/libdrm's open/ioctl/close/stat of
#     /dev/dri go to that client when the real call is refused. WindowServer and other unsandboxed processes are unchanged.
# The allow list is not touched: apps still need a rung in nvmtl-allow.txt (or NVMTL_ENABLE=1) to get the device.
#   sudo scripts/macos-install-step102.sh [NMXAccel binary] [NVMTLDriver]
#   sudo scripts/macos-install-step102.sh --undo     # NMXAccel + plugin back from the newest step102 backup, relink
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
U=${SUDO_USER:-thanhnndev}; UH=$(eval echo "~$U")
G=/Library/Extensions/NMXGPU.kext
A=/Library/Extensions/NMXAccel.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
NMX_SHA=3e1b661990d08e35
ACCEL_LIVE=bf7c7ea8c233d22a                       # ci/nmxaccel-flip 37493db (live since Step98)
ACCEL_NEW=${1:-$UH/ga403-logs/step102/ci/NMXAccel}
ACCEL_NEW_SHA=48b3f689c1fc6b2322c70a0c2c8ce98d31fbde4befe6d8e712b66ea58599ebb5   # CI run 41789977284 (fork ci/nmxaccel-drmuc)
PLUGIN_NEW=${2:-$UH/develop/projects/nmx-plugin-890m/out/plugin-desccache-923deca/NVMTLDriver}
PLUGIN_SHA=f425b2069544f91809bcaa81e34e314462435bfb4096e53e33fc6de6c1597c1e
TS=$(date -u +%Y%m%dT%H%M%SZ)

relink() {
    /usr/bin/python3 -I "$HERE/nmx-caves/check.py" "$G/Contents/MacOS/NMXGPU" || { echo "cave registry check failed -- not linking"; exit 1; }
    local NEW=$KC.step102 B=$G/Contents/MacOS/NMXGPU
    rm -f /Library/KernelCollections/AuxiliaryKernelExtensions.kc.step102
    /usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
        -B /System/Library/KernelCollections/BootKernelExtensions.kc \
        -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
        --repository /Library/Extensions -A "$NEW" -z
    /usr/bin/python3 -I "$HERE/nmx-mmfix/step97b_patch.py" --check-kc "$NEW" "$B"
    /usr/bin/python3 -I "$HERE/nmx-flip/step99_patch.py" --check-kc "$NEW" "$B"
    /usr/bin/python3 -I "$HERE/nmx-irqfix/patch_irqfix.py" --check-kc "$NEW" "$B"
    /usr/bin/python3 -I "$HERE/nmx-mmfix2/step100_mm_patch.py" --check-kc "$NEW" "$B"
    uuids_in "$NEW" || { echo "new collection is missing a kext -- not installed (old one stays)"; exit 1; }
    mv -f "$NEW" "$KC"
    sync
    echo "relinked; checking again in 45 s (kernelmanagerd, Step100b)"
    sleep 45
    uuids_in "$KC" || { echo "AuxKC on disk lost a kext after the relink (kernelmanagerd?): run this script again"; exit 1; }
}
uuids_in() {  # <kc>: every kext the boot needs must be linked in it
    local k u bad=0
    for k in NMXGPU NMXAccel NMXAGDC NMXBacklight NVRM NVAccel NVRMFB NVRMAGDC; do
        u=$(otool -l "/Library/Extensions/$k.kext/Contents/MacOS/$k" | awk '/LC_UUID/{f=1} f&&/uuid/{print $2; exit}' | tr -d -)
        if /usr/bin/python3 -I -c 'import sys; sys.exit(0 if bytes.fromhex(sys.argv[2]) in open(sys.argv[1],"rb").read() else 1)' "$1" "$u"; then
            echo "  $k in collection"; else echo "  $k MISSING"; bad=1; fi
    done
    return $bad
}
swap_accel_binary() {  # <binary>: the live bundle (Info.plist included) with only the executable replaced
    local T=$A.new.$TS
    ditto "$A" "$T"
    install -o 0 -g 0 -m 755 "$1" "$T/Contents/MacOS/NMXAccel"
    chown -R 0:0 "$T"
    mv "$A" "$A.old.$TS" && mv "$T" "$A" && rm -rf "$A.old.$TS"
}

if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/step102-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -f $BK/NMXAccel ]] || { echo "no step102 backup"; exit 1; }
    STEP=$BK; exec > >(tee -a "$STEP/undo.log") 2>&1
    swap_accel_binary "$BK/NMXAccel"
    "$HERE/nvmtl-desccache/install.sh" install
    relink
    echo "Step102 undone (NMXAccel $(shasum -a 256 "$A/Contents/MacOS/NMXAccel" | cut -c1-16), plugin fbb6ca4); reboot to load it"
    exit 0
fi

STEP=/Library/NullMoth/step102-$TS
mkdir -p "$STEP"
exec > >(tee -a "$STEP/install.log") 2>&1
echo "== 0. checks"
[[ $(shasum -a 256 "$G/Contents/MacOS/NMXGPU" | cut -c1-16) == "$NMX_SHA" ]] || { echo "NMXGPU is not the live Step100c build"; exit 1; }
[[ $(shasum -a 256 "$A/Contents/MacOS/NMXAccel" | cut -c1-16) == "$ACCEL_LIVE" ]] || { echo "NMXAccel is not the live 37493db build -- not touching it"; exit 1; }
[[ $(file -b "$ACCEL_NEW") == *'Mach-O 64-bit kext bundle x86_64'* ]] || { echo "$ACCEL_NEW is not an x86_64 kext binary"; exit 1; }
[[ $(shasum -a 256 "$ACCEL_NEW" | cut -d' ' -f1) == "$ACCEL_NEW_SHA" ]] || { echo "$ACCEL_NEW is not the CI NMDR build"; exit 1; }
strings -a "$ACCEL_NEW" | grep -q 'drm-uc: pid' || { echo "$ACCEL_NEW has no NMDR client"; exit 1; }
strings -a "$ACCEL_NEW" | grep -q 'flip: NMXGPU flip API' || { echo "$ACCEL_NEW lacks the 37493db flip path"; exit 1; }
[[ $(shasum -a 256 "$PLUGIN_NEW" | cut -d' ' -f1) == "$PLUGIN_SHA" ]] || { echo "$PLUGIN_NEW is not the 923deca build"; exit 1; }
cp -p "$A/Contents/MacOS/NMXAccel" "$STEP/NMXAccel"
cp -p "$KC" "$STEP/AuxiliaryKernelExtensions.kc"
echo "saved NMXAccel and AuxKC in $STEP (new NMXAccel $(shasum -a 256 "$ACCEL_NEW" | cut -c1-16))"

echo "== 1. NMXAccel with the NMDR client"
swap_accel_binary "$ACCEL_NEW"

echo "== 2. plugin 923deca (sandbox-safe DRM path)"
"$HERE/macos-nvmtl-plugin-install.sh" "$PLUGIN_NEW"
sudo -u _windowserver /bin/test -r /Library/GPUBundles/nvmtl-allow.txt || { echo "WindowServer cannot read the allow list"; exit 1; }
echo "allow list (unchanged): $(grep -v '^#' /Library/GPUBundles/nvmtl-allow.txt | tr '\n' ' ')"

echo "== 3. relink and verify"
relink
echo "Step102 installed; reboot to load NMXAccel. Undo: sudo $0 --undo"
