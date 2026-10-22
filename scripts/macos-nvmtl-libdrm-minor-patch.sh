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
# drmGetNodeTypeFromDevId and drmGetDeviceNameFromFd2. An open fd's st_rdev also carries its open sequence, so the
# places that find a node by comparing an fd's st_rdev with a stat of each /dev/dri path (drmGetDeviceFromDevId, behind
# drmGetDevice2(fd) which Mesa's ac_query_gpu_info calls, and drmGetDeviceNameFromFd) compare the low byte only:
# `cmp %r14d, m32` -> `cmp %r14b, m8` (Step33c).
set -euo pipefail
L=/Library/GPUBundles/nvmtl/libdrm.2.dylib; BK=/Library/NullMoth/libdrm-backup
STOCK=0b99f7555436be1e0c54de88f0e4cddf0c416d4fcda6a19eaea05a8d9b883f27
# immediate of each `and $0xffffff, reg` (file offset == vmaddr)
IMMS="0x51d6 0x5395 0x55b7 0x5677 0x58be 0x5b9a 0x5d72 0x610f"
# opcode byte of each `cmp %r14d, -0x...(%rbp)` against a stat'ed st_rdev
CMPS="0x5143 0x59be 0x59e5 0x5a16"

if [ "${1:-}" = --undo ]; then
  [ -f "$BK/libdrm.2.dylib" ] || { echo "no backup in $BK"; exit 1; }
  ditto "$BK/libdrm.2.dylib" "$L"; echo "libdrm restored: $(shasum -a 256 "$L" | cut -c1-16)"; exit 0
fi

# patch from the stock dylib: the backup once one exists (re-running applies the current patch set)
SRC=$L; [ -f "$BK/libdrm.2.dylib" ] && SRC=$BK/libdrm.2.dylib
[ "$(shasum -a 256 "$SRC" | cut -d' ' -f1)" = $STOCK ] || { echo "$SRC is not the stock 2.3.1/2.0.4 build - not patching"; exit 1; }
mkdir -p "$BK"; [ "$SRC" = "$L" ] && ditto "$L" "$BK/libdrm.2.dylib"
T=$(mktemp); cp "$SRC" "$T"
for o in $IMMS; do
  [ "$(xxd -p -s $((o)) -l 4 "$T")" = ffffff00 ] || { rm -f "$T"; echo "unexpected bytes at $o"; exit 1; }
  printf '\xff\x00\x00\x00' | dd of="$T" bs=1 seek=$((o)) conv=notrunc status=none
done
for o in $CMPS; do
  [ "$(xxd -p -s $((o)) -l 1 "$T")" = 39 ] || { rm -f "$T"; echo "unexpected opcode at $o"; exit 1; }
  printf '\x38' | dd of="$T" bs=1 seek=$((o)) conv=notrunc status=none
done
codesign -f -s - "$T" 2>/dev/null
chown root:wheel "$T"; chmod 755 "$T"; mv -f "$T" "$L"
echo "libdrm patched: $(shasum -a 256 "$L" | cut -c1-16)"
