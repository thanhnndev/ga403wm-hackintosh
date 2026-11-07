#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Minimal static libavcodec for VCNDec: vp9 + av1 through Vulkan video only (LGPL 2.1+ build, no GPL parts).
# usage: ff-build.sh <ffmpeg-8.0 source dir (fresh, in-tree)> <prefix>
# The source gets one patch: the live Vulkan loader /Library/GPUBundles/nvmtl/libvulkan.1.dylib is tried first,
# because the VideoToolbox XPC service has no DYLD_LIBRARY_PATH.
set -e
SRC=$1; PREFIX=$2; VKH=${VKH:-$HOME/develop/projects/radv-video/Vulkan-Headers-1.4.330/include}
[ -d "$SRC" ] && [ -n "$PREFIX" ] || { echo "usage: $0 <ffmpeg src> <prefix>"; exit 1; }
cd "$SRC"
grep -q 'GPUBundles/nvmtl/libvulkan' libavutil/hwcontext_vulkan.c || \
  sed -i '' 's#^        "libvulkan.dylib",#        "/Library/GPUBundles/nvmtl/libvulkan.1.dylib", /* ga403wm: live loader next to RADV */\n        "libvulkan.dylib",#' libavutil/hwcontext_vulkan.c
./configure --prefix="$PREFIX" --disable-everything --disable-programs --disable-doc --disable-debug \
  --disable-x86asm --disable-autodetect --enable-pic --enable-static --disable-shared \
  --enable-vulkan --enable-decoder=vp9,av1 --enable-hwaccel=vp9_vulkan,av1_vulkan --enable-parser=vp9,av1 \
  --enable-bsf=vp9_superframe_split \
  --disable-avformat --disable-avdevice --disable-avfilter --disable-swresample --disable-swscale \
  --extra-cflags="-I$VKH -fvisibility=hidden -mmacosx-version-min=14.0"
make -j12
make install
