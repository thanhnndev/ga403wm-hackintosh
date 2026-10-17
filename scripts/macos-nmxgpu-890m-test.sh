#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
#
# Boot test of NullMoth's NMXGPU (Linux amdgpu on macOS via LinuxKPI) on the Radeon 890M (890M port milestone 4,
# docs/890M-TRACE.md Step25). Run as root (osascript "administrator privileges").
#
#   macos-nmxgpu-890m-test.sh <firmware-dir> <esp-mount>   install: firmware, NMXGPU + NMXAccel, RADV userland, AuxKC,
#                                                           boot-args nmxamd=1 -strixgopoff -strixaccoff -strixmetalgateoff,
#                                                           strix-probe=1 removed
#   macos-nmxgpu-890m-test.sh --undo <esp-mount>            restore the config backup, remove both kexts, rebuild AuxKC
#
# <firmware-dir> holds amdgpu/*.bin + LICENSES/LICENSE.amdgpu, already SHA-256 checked against NullMoth's manifest
# (linux-firmware afabaf773c4c2e2c841429933a6a084a5af4d14d). From Linux, undo = copy
# EFI/OC/config.plist.pre-nmxgpu-890m back over EFI/OC/config.plist.
set -euo pipefail
# NullMoth >= 2.2 ships the NVIDIA driver only: the NMX kexts then come from the copy saved out of the 2.0.4 package.
KD=${NMX_SRC:-/Library/NullMoth/kexts/26}
[ -d "$KD/NMXGPU.kext" ] || KD=/Users/$(stat -f %Su /dev/console)/efi-audit/nmxgpu-2.0.4
EXT=/Library/Extensions; GFW=/Library/NullMoth/firmware
B=7C436110-AB2A-4BBB-A880-FE41995C9F82

auxkc() {
  kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository "$EXT" \
    -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc -z
}

bootargs() {  # $1 config, then: +arg / -arg ...
  local cfg=$1; shift
  /usr/bin/python3 -I - "$cfg" "$@" <<'EOF'
import plistlib, sys
p = sys.argv[1]
d = plistlib.load(open(p, 'rb'))
nv = d['NVRAM']['Add']['7C436110-AB2A-4BBB-A880-FE41995C9F82']
args = nv['boot-args'].split()
for op in sys.argv[2:]:
    a = op[1:]
    key = a.split('=')[0]
    args = [x for x in args if x.split('=')[0] != key]
    if op[0] == '+':
        args.append(a)
nv['boot-args'] = ' '.join(args)
plistlib.dump(d, open(p, 'wb'))
print('boot-args:', nv['boot-args'])
EOF
}

if [ "${1:-}" = --undo ]; then
  ESP=$2; CFG="$ESP/EFI/OC/config.plist"
  [ -f "$CFG.pre-nmxgpu-890m" ] && cp "$CFG.pre-nmxgpu-890m" "$CFG" && echo "config restored"
  rm -rf "$EXT/NMXGPU.kext" "$EXT/NMXAccel.kext"
  auxkc && echo "AuxKC rebuilt without NMXGPU"
  exit 0
fi

FW=$1; ESP=$2; CFG="$ESP/EFI/OC/config.plist"
[ -d "$KD/NMXGPU.kext" ] && [ -d "$KD/NMXAccel.kext" ] || { echo "no NMXGPU/NMXAccel for macOS 26 in $KD"; exit 1; }
[ -f "$FW/amdgpu/gc_11_5_0_pfp.bin" ] || { echo "no 890M firmware in $FW"; exit 1; }
[ -f "$CFG" ] || { echo "no $CFG"; exit 1; }

mkdir -p "$GFW"
ditto "$FW" "$GFW"
chown -R root:wheel "$GFW"; chmod -R go-w,a+rX "$GFW"
echo "firmware: $(ls "$GFW/amdgpu" | wc -l | tr -d ' ') files in $GFW/amdgpu"

for k in NMXGPU NMXAccel; do
  rm -rf "$EXT/$k.kext"; ditto "$KD/$k.kext" "$EXT/$k.kext"
  chown -R root:wheel "$EXT/$k.kext"; chmod -R 755 "$EXT/$k.kext"
done
# amdgpu_device_init hangs in the PCIe partner-bandwidth walk on the 890M (Step26) - skip it like on a root bus.
NO_AUXKC=1 bash "$(dirname "$0")/macos-nmxgpu-pcie-patch.sh" "$EXT/NMXGPU.kext"
U=/Library/NullMoth/gpu-userland; [ -d "$U" ] || U=$KD/gpu-userland
ditto "$U" /Library/GPUBundles/nvmtl
chown -R root:wheel /Library/GPUBundles/nvmtl; chmod -R go-w,a+rX /Library/GPUBundles/nvmtl

auxkc
kmutil inspect -a x86_64 -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc 2>/dev/null \
  | /usr/bin/grep -E 'com.nullmoth.NMX(GPU|Accel)' || { echo "AuxKC did not take NMXGPU/NMXAccel"; exit 1; }

[ -f "$CFG.pre-nmxgpu-890m" ] || cp "$CFG" "$CFG.pre-nmxgpu-890m"
bootargs "$CFG" +nmxamd=1 +-strixgopoff +-strixaccoff +-strixmetalgateoff -strix-probe
# The 890M's OpenCore DeviceProperties hide it from macOS (class-code ffffffff, disable-gpu, name/IOName #display);
# NMXGPU matches display class 0x03 and the upstream setup also drops disable-gpu, so the test boot shows the real ones.
/usr/bin/python3 -I - "$CFG" <<'EOF'
import plistlib, sys
p = sys.argv[1]
d = plistlib.load(open(p, 'rb'))
dev = d['DeviceProperties']['Add'].get('PciRoot(0x0)/Pci(0x8,0x1)/Pci(0x0,0x0)', {})
gone = [k for k in ('class-code', 'disable-gpu', 'IOName', 'name') if dev.pop(k, None) is not None]
plistlib.dump(d, open(p, 'wb'))
print('890M DeviceProperties removed:', gone, 'left:', sorted(dev))
EOF
echo "installed - takes effect at the next restart (OLED only, HDMI unplugged)"
