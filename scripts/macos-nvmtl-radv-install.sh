#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
#
# Install a source-built RADV as /Library/GPUBundles/nvmtl/libvulkan_radeon.dylib (docs/890M-TRACE.md, Edge video
# lag part 6). Run as root, then scripts/macos-install-strixsbxmap.sh --refresh (the dylib's CDHash is pinned).
#   macos-nvmtl-radv-install.sh <libvulkan_radeon.dylib>   back up the live dylib, install this one
#   macos-nvmtl-radv-install.sh --undo                     put the newest backup back
#
# Build: ~/develop/projects/radv-video/build-res.sh = Mesa bffd919 + NullMoth mesa-macos.patch + radv-nmxmap.patch +
# scripts/radv/radv-nvmtl-surface-list.patch, then install names -> /usr/lib/libz and /Library/GPUBundles/nvmtl libdrm,
# rpaths removed, ad hoc signed. The swap is a rename: processes that mapped the old file keep it until they restart;
# WindowServer picks the new one up at its next start.
set -euo pipefail
G=/Library/GPUBundles/nvmtl; L=$G/libvulkan_radeon.dylib; BK=/Library/NullMoth
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }

if [ "${1:-}" = --undo ]; then
  B=$(ls -d $BK/radv-live-* 2>/dev/null | sort | tail -1)
  [ -n "$B" ] && [ -f "$B/libvulkan_radeon.dylib" ] || { echo "no radv-live-* backup in $BK"; exit 1; }
  cp "$B/libvulkan_radeon.dylib" "$L.new.$$" && mv -f "$L.new.$$" "$L"
  echo "radv restored from $B: $(shasum -a 256 "$L" | cut -c1-16)"; exit 0
fi

NEW=${1:?usage: $0 <libvulkan_radeon.dylib> | --undo}
[ -f "$NEW" ] || { echo "$NEW: no such file"; exit 1; }
# refuse anything that still links outside the system and /Library/GPUBundles/nvmtl
if otool -L "$NEW" | tail -n +2 | awk '{print $1}' | grep -vE '^(/usr/lib/|/System/|/Library/GPUBundles/nvmtl/)'; then
  echo "^ links outside /usr/lib and $G - not installing"; exit 1; fi
otool -l "$NEW" | grep -q LC_RPATH && { echo "has LC_RPATH entries - not installing"; exit 1; }
nm -gU "$NEW" | grep -q ' _vk_icdGetInstanceProcAddr$' || { echo "not a Vulkan ICD - not installing"; exit 1; }
codesign -v "$NEW" || { echo "bad signature"; exit 1; }

TS=$(date -u +%Y%m%dT%H%M%SZ); mkdir -p "$BK/radv-live-$TS"
cp -p "$L" "$BK/radv-live-$TS/libvulkan_radeon.dylib"
install -o 0 -g 0 -m 755 "$NEW" "$L.new.$TS"
mv -f "$L.new.$TS" "$L"
echo "backup $BK/radv-live-$TS ($(shasum -a 256 "$BK/radv-live-$TS/libvulkan_radeon.dylib" | cut -c1-16))"
echo "installed: $(shasum -a 256 "$L" | cut -c1-16); new processes load it now, WindowServer at its next start"
