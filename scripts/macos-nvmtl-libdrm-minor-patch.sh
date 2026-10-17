#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
#
# libdrm (NullMoth gpu-userland, /Library/GPUBundles/nvmtl/libdrm.2.dylib) for the own-build NMXGPU (docs/890M-TRACE.md
# Step33). Run as root.
#   macos-nvmtl-libdrm-minor-patch.sh            back up the stock dylib, patch, re-sign ad hoc
#   macos-nvmtl-libdrm-minor-patch.sh --undo     put the stock dylib back
#
# NMXGPU's DRM nodes are xnu devfs clone nodes: devfs hands out a new minor at every lookup, stat(2) included. libdrm's
# macOS port recognises a DRM node by stat'ing /dev/dri/* for the same major:minor (drmNodeIsDRM) and names a node
# from its minor (card<minor>, renderD<minor>), so drmGetDevices2() found nothing and RADV saw 0 devices. The fork's
# nmx_devfs.cpp now builds every open minor as (sequence << 8) | DRM minor (renderD128 -> 128); here every minor()
# libdrm takes from a dev_t is narrowed to its low byte: `and $0xffffff` -> `and $0xff` in drmGetNodeTypeFromFd,
# drmNodeIsDRM, drmGet{Primary,Render}DeviceNameFromFd, drmGetDeviceFromDevId, process_device,
# drmGetNodeTypeFromDevId and drmGetDeviceNameFromFd2.
set -euo pipefail
L=/Library/GPUBundles/nvmtl/libdrm.2.dylib; BK=/Library/NullMoth/libdrm-backup
STOCK=0b99f7555436be1e0c54de88f0e4cddf0c416d4fcda6a19eaea05a8d9b883f27
# immediate of each `and $0xffffff, reg` (file offset == vmaddr)
IMMS="0x51d6 0x5395 0x55b7 0x5677 0x58be 0x5b9a 0x5d72 0x610f"

if [ "${1:-}" = --undo ]; then
  [ -f "$BK/libdrm.2.dylib" ] || { echo "no backup in $BK"; exit 1; }
  ditto "$BK/libdrm.2.dylib" "$L"; echo "libdrm restored: $(shasum -a 256 "$L" | cut -c1-16)"; exit 0
fi

[ "$(shasum -a 256 "$L" | cut -d' ' -f1)" = $STOCK ] || { echo "libdrm is not the stock 2.3.1/2.0.4 build - not patching"; exit 1; }
mkdir -p "$BK"; ditto "$L" "$BK/libdrm.2.dylib"
T=$(mktemp); cp "$L" "$T"
for o in $IMMS; do
  [ "$(xxd -p -s $((o)) -l 4 "$T")" = ffffff00 ] || { rm -f "$T"; echo "unexpected bytes at $o"; exit 1; }
  printf '\xff\x00\x00\x00' | dd of="$T" bs=1 seek=$((o)) conv=notrunc status=none
done
codesign -f -s - "$T" 2>/dev/null
chown root:wheel "$T"; chmod 755 "$T"; mv -f "$T" "$L"
echo "libdrm patched: $(shasum -a 256 "$L" | cut -c1-16)"
