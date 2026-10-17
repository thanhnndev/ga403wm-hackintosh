#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
#
# Binary patches for NullMoth NMXGPU 1.0.0 (NullMoth 2.0.4 package) on the Radeon 890M / macOS 26. Run as root;
# rebuilds the AuxKC. Each patch checks its original bytes, so the script is idempotent.
#   macos-nmxgpu-pcie-patch.sh [--undo] [kext]      (default /Library/Extensions/NMXGPU.kext)
#
# pcie (docs/890M-TRACE.md Step26): amdgpu_device_get_pcie_info() does not see the APU on a root bus (LinuxKPI builds a
#   bridge chain for it) and falls into amdgpu_device_partner_bandwidth(), whose pci_upstream_bridge() walk never ends -
#   the attach thread spins in amdgpu_device_init+0x11e0..0x124b. At amdgpu_device_init+0x11b0 jump to +0x1181, the
#   root-bus/APU branch (pcie_gen_mask 0x30007, pcie_mlw_mask 0x2f0000, as Linux sets for this APU).
# fbpm (Step28): NMXGPUFB::start() calls registerPowerDriver() right after IOFramebuffer::start(). On Tahoe's
#   IOGraphics, IOFramebuffer::powerStateWillChangeTo() dereferences fPrivate->controller, which is only set in
#   IOFramebuffer::open(); a power change before the open panics (page fault CR2 0x120 in powerStateWillChangeTo+0x25,
#   seen 10-24 s into both boots where amdgpu got the VBIOS). Drop that call (IOFramebuffer::start already joined the
#   PM tree).
set -euo pipefail
UNDO=0; [ "${1:-}" = --undo ] && { UNDO=1; shift; }
K=${1:-/Library/Extensions/NMXGPU.kext}; B=$K/Contents/MacOS/NMXGPU
ORIG_SHA=33aa04a8681223e56228223491c8205ec3023289a49187d8668c0458eda61c77
# name offset original patched      (file offset == vmaddr: __TEXT at 0, fileoff 0)
PATCHES="
pcie 0x1a7f0  83bba464010000740d e9ccffffff9090900d
fbpm 0x9ced22 ff90a8070000       31c00f1f4000
"

auxkc() {
  kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions \
    -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc -z
}

# refuse anything that is not the stock build or a build carrying only these patches
check=$(mktemp); cp "$B" "$check"
echo "$PATCHES" | while read -r n off orig new; do
  [ -n "$n" ] || continue
  echo "$orig" | xxd -r -p | dd of="$check" bs=1 seek=$((off)) conv=notrunc status=none
done
[ "$(shasum -a 256 "$check" | cut -d' ' -f1)" = $ORIG_SHA ] || { rm -f "$check"; echo "unknown NMXGPU build - not patching"; exit 1; }
rm -f "$check"

echo "$PATCHES" | while read -r n off orig new; do
  [ -n "$n" ] || continue
  len=$(( ${#orig} / 2 )); cur=$(xxd -p -s $((off)) -l $len "$B")
  if [ $UNDO = 1 ]; then want=$orig; else want=$new; fi
  [ "$cur" = "$want" ] && { echo "$n: already $([ $UNDO = 1 ] && echo stock || echo patched)"; continue; }
  echo "$want" | xxd -r -p | dd of="$B" bs=1 seek=$((off)) conv=notrunc status=none
  echo "$n: $cur -> $want"
done
echo "sha256: $(shasum -a 256 "$B" | cut -d' ' -f1)"
[ -n "${NO_AUXKC:-}" ] || case "$K" in /Library/Extensions/*) auxkc && echo "AuxKC rebuilt";; esac
# NMXGPU's boot guard parks the GPU after an attach that never returned (NVRAM nullmoth-gpu-attaching=1): clear it so
# the patched driver gets a fresh attach on the next boot.
nvram -d nullmoth-gpu-attaching 2>/dev/null || true
