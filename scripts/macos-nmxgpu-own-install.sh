#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
#
# Install an NMXGPU.kext built from source (route B, docs/890M-TRACE.md Step31/32: NullMoth v2.0.4 sources + the
# ga403wm fixes on branch ga403wm-nmx of the fork; build with GPU_SRC=... AMD_ONLY=1 gpu-port/xkpi/kext/build.sh).
# Run as root; rebuilds the AuxKC and clears NMXGPU's boot guard.
#   macos-nmxgpu-own-install.sh <NMXGPU.kext>     back up the installed one to /Library/NullMoth/nmxgpu-backup, install
#   macos-nmxgpu-own-install.sh --undo            put the backed-up kext back
set -euo pipefail
EXT=/Library/Extensions; BK=/Library/NullMoth/nmxgpu-backup

auxkc() {
  kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository "$EXT" \
    -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc -z
}

if [ "${1:-}" = --undo ]; then
  [ -d "$BK/NMXGPU.kext" ] || { echo "no backup in $BK"; exit 1; }
  rm -rf "$EXT/NMXGPU.kext"; ditto "$BK/NMXGPU.kext" "$EXT/NMXGPU.kext"
else
  NEW=${1:?NMXGPU.kext}
  [ -f "$NEW/Contents/MacOS/NMXGPU" ] || { echo "not a built NMXGPU.kext: $NEW"; exit 1; }
  if [ ! -d "$BK/NMXGPU.kext" ]; then mkdir -p "$BK"; ditto "$EXT/NMXGPU.kext" "$BK/NMXGPU.kext"; fi
  rm -rf "$EXT/NMXGPU.kext"; ditto "$NEW" "$EXT/NMXGPU.kext"
fi
chown -R root:wheel "$EXT/NMXGPU.kext"; chmod -R 755 "$EXT/NMXGPU.kext"
echo "NMXGPU sha256 $(shasum -a 256 "$EXT/NMXGPU.kext/Contents/MacOS/NMXGPU" | cut -c1-16)"
auxkc
kmutil inspect -a x86_64 -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc 2>/dev/null \
  | /usr/bin/grep -q com.nullmoth.NMXGPU || { echo "AuxKC did not take NMXGPU"; exit 1; }
echo "AuxKC rebuilt"
nvram -d nullmoth-gpu-attaching 2>/dev/null || true
