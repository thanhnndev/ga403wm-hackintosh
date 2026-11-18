#!/bin/bash
# SPDX-License-Identifier: MIT
# RADV for the live stack (macOS port): Mesa bffd919 + NullMoth mesa-macos.patch + radv-nmxmap.patch +
# radv-nvmtl-surface-list.patch, already applied in $R/mesa (the tree build-res.sh uses).
#
# Same options as ~/develop/projects/radv-video/build-res.sh (the build behind the live RADV 90402a4b) plus
# -Dvideo-codecs=all. Without it Mesa defaults to "all_free": the device then exposes VK_KHR_video_decode_av1/vp9 only,
# libavcodec fails with "Device does not support decoding h264/hevc", VCNDec cannot decode H.264/HEVC, and VideoToolbox
# has no hardware H.264/HEVC decoder (Chrome falls back to FFmpeg, Safari/QuickTime to Apple's software decoders).
#
# usage: scripts/radv/build-radv.sh [build-dir=$R/mesa/build-codecs]   (out of tree: the mesa source is only read)
# result: <build-dir>/src/amd/vulkan/libvulkan_radeon.dylib; install it with scripts/macos-nvmtl-radv-install.sh.
# check:  VK_DRIVER_FILES=<dir with an icd json naming it> vkq -> the VIDEO_DECODE queue family has videoOps 0xf
#         (H.264 0x1, H.265 0x2, AV1 0x4, VP9 0x8); the live all_free build shows 0xc.
set -euo pipefail
R=${R:-$HOME/develop/projects/radv-video}
B=${1:-$R/mesa/build-codecs}
export PATH=$(cd "$(dirname "$0")" && pwd):$R/glslang-inst/bin:$R/venv/bin:/opt/local/bin:/usr/bin:/bin PKG_CONFIG_LIBDIR=$R/drm-inst/lib/pkgconfig PKG_CONFIG_PATH=
# ninja: PATH, else $NINJA, else the Android SDK's (MacPorts ninja/pkg-config were removed; ./pkg-config replaces the latter)
command -v ninja >/dev/null || { export NINJA=${NINJA:-$(ls -d $HOME/Library/Android/sdk/cmake/*/bin/ninja 2>/dev/null | tail -1)}; [ -x "$NINJA" ] || { echo "no ninja"; exit 1; }; ninja() { "$NINJA" "$@"; }; }
[ -d "$B" ] || meson setup "$B" $R/mesa --prefix="$B/inst" --buildtype=release -Dvulkan-drivers=amd -Dvideo-codecs=all \
  -Dgallium-drivers= -Dplatforms= -Dllvm=disabled -Dglx=disabled -Degl=disabled -Dgles1=disabled -Dgles2=disabled \
  -Dopengl=false -Dzstd=disabled -Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled -Dbuild-tests=false
meson configure "$B" -Dvideo-codecs=all >/dev/null
ninja -C "$B" src/amd/vulkan/libvulkan_radeon.dylib
# installable copy: the live stack's install names (libdrm with the NullMoth patch lives in /Library/GPUBundles/nvmtl),
# no rpath, ad hoc signed; scripts/macos-nvmtl-radv-install.sh refuses anything else
G=/Library/GPUBundles/nvmtl; O="$B/libvulkan_radeon.dylib"
cp -f "$B/src/amd/vulkan/libvulkan_radeon.dylib" "$O"
install_name_tool -id $G/libvulkan_radeon.dylib "$O"
for l in $(otool -L "$O" | tail -n +2 | awk '{print $1}' | grep -E 'libdrm(_amdgpu)?\.[0-9]+\.dylib$'); do
  install_name_tool -change "$l" "$G/$(basename "$l")" "$O"; done
for r in $(otool -l "$O" | awk '/LC_RPATH/{getline; getline; print $2}'); do install_name_tool -delete_rpath "$r" "$O"; done
codesign -f -s - "$O" 2>/dev/null
if otool -L "$O" | tail -n +2 | awk '{print $1}' | grep -vE "^(/usr/lib/|/System/|$G/)"; then echo "^ links outside the system: not installable"; exit 1; fi
echo "installable: $O"; shasum -a 256 "$O"
