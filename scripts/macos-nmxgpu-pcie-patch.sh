#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
#
# NMXGPU 1.0.0 (NullMoth 2.0.4) hangs on the Radeon 890M right after "[drm] register mmio size" (docs/890M-TRACE.md
# Step26): amdgpu_device_get_pcie_info() does not see the APU on a root bus (LinuxKPI builds a bridge chain for it), so
# it falls into amdgpu_device_partner_bandwidth(), whose pci_upstream_bridge() walk never terminates - the attach thread
# spins in amdgpu_device_init+0x11e0..0x124b forever and the 890M never initialises.
#
# Patch: at amdgpu_device_init+0x11b0 (the non-root-bus branch) jump to +0x1181, the root-bus/APU branch, which sets
# the defaults Linux uses for this APU (pcie_gen_mask 0x30007, pcie_mlw_mask 0x2f0000) and returns. The
# amdgpu_pcie_gen_cap/lane_cap module params would do the same but live in __common (zero-fill) and NMXGPU reads no
# tunables. Run as root; rebuilds the AuxKC.
#   macos-nmxgpu-pcie-patch.sh [--undo] [kext]      (default /Library/Extensions/NMXGPU.kext)
set -euo pipefail
UNDO=0; [ "${1:-}" = --undo ] && { UNDO=1; shift; }
K=${1:-/Library/Extensions/NMXGPU.kext}; B=$K/Contents/MacOS/NMXGPU
ORIG_SHA=33aa04a8681223e56228223491c8205ec3023289a49187d8668c0458eda61c77
OFF=$((0x1a7f0))            # file offset == vmaddr (__TEXT at 0, fileoff 0); _amdgpu_device_init = 0x19640
ORIG=83bba464010000740d     # cmpl $0x0,0x164a4(%rbx) ; je +0xd
NEW=e9ccffffff9090900d      # jmp 0x1a7c1 (amdgpu_device_init+0x1181) ; nop x3 (rest unreachable)

cur() { xxd -p -s $OFF -l 9 "$B"; }
put() { echo "$1" | xxd -r -p | dd of="$B" bs=1 seek=$OFF conv=notrunc status=none; }
auxkc() {
  kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions \
    -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc -z
}

c=$(cur)
if [ $UNDO = 1 ]; then
  [ "$c" = "$NEW" ] || { echo "not patched ($c)"; exit 1; }
  put $ORIG
else
  if [ "$c" = "$NEW" ]; then echo "already patched"; exit 0; fi
  [ "$(shasum -a 256 "$B" | cut -d' ' -f1)" = $ORIG_SHA ] || { echo "unknown NMXGPU build - not patching"; exit 1; }
  [ "$c" = "$ORIG" ] || { echo "unexpected bytes at 0x1a7f0 ($c)"; exit 1; }
  put $NEW
fi
echo "bytes now: $(cur)  sha256: $(shasum -a 256 "$B" | cut -d' ' -f1)"
[ -n "${NO_AUXKC:-}" ] || case "$K" in /Library/Extensions/*) auxkc && echo "AuxKC rebuilt";; esac
