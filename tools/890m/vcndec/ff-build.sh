#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Minimal static libavcodec for VCNDec: vp9, av1, h264, hevc through Vulkan video only (LGPL 2.1+ build, no GPL parts).
# usage: ff-build.sh <ffmpeg-8.0 source dir (fresh, in-tree)> <prefix>
# The source gets one patch: the live Vulkan loader /Library/GPUBundles/nvmtl/libvulkan.1.dylib is tried first,
# because the VideoToolbox XPC service has no DYLD_LIBRARY_PATH.
# Two more patches give H.264 / HEVC decode-order output when the caller sets AV_CODEC_FLAG_LOW_DELAY: a VideoToolbox
# decoder emits each sample's own picture from its DecodeFrame call and the client (Chrome, VT temporal processing)
# reorders by pts, like Apple's hardware decoders. Without them libavcodec holds pictures back for display order.
set -e
SRC=$1; PREFIX=$2; VKH=${VKH:-$HOME/develop/projects/radv-video/Vulkan-Headers-1.4.330/include}
[ -d "$SRC" ] && [ -n "$PREFIX" ] || { echo "usage: $0 <ffmpeg src> <prefix>"; exit 1; }
cd "$SRC"
grep -q 'GPUBundles/nvmtl/libvulkan' libavutil/hwcontext_vulkan.c || \
  sed -i '' 's#^        "libvulkan.dylib",#        "/Library/GPUBundles/nvmtl/libvulkan.1.dylib", /* ga403wm: live loader next to RADV */\n        "libvulkan.dylib",#' libavutil/hwcontext_vulkan.c
grep -q 'ga403wm: decode-order' libavcodec/h264_slice.c || perl -0pi -e 's/(    cur->mmco_reset = h->mmco_reset;\n    h->mmco_reset = 0;\n)/$1\n    if (h->avctx->flags & AV_CODEC_FLAG_LOW_DELAY) { \/\* ga403wm: decode-order output, the VideoToolbox client reorders \*\/\n        h->frame_recovered |= cur->recovered;\n        cur->recovered |= h->frame_recovered & FRAME_RECOVERED_SEI;\n        h->next_output_pic = (cur->recovered || (h->avctx->flags \& AV_CODEC_FLAG_OUTPUT_CORRUPT)) ? cur : NULL;\n        return 0;\n    }\n/' libavcodec/h264_slice.c
grep -q 'ga403wm: decode-order' libavcodec/hevc/hevcdec.c || perl -0pi -e 's/(    s->sei\.picture_hash\.is_md5 = 0;\n)/    if (s->avctx->flags & AV_CODEC_FLAG_LOW_DELAY) { \/\* ga403wm: decode-order output, the VideoToolbox client reorders \*\/\n        ret = ff_hevc_output_frames(s, s->layers_active_decode, s->layers_active_output, 0, HEVC_MAX_DPB_SIZE, 0);\n        if (ret < 0)\n            return ret;\n    }\n$1/' libavcodec/hevc/hevcdec.c
grep -q 'ga403wm: decode-order' libavcodec/h264_slice.c && grep -q 'ga403wm: decode-order' libavcodec/hevc/hevcdec.c || { echo "decode-order patches did not apply"; exit 1; }
./configure --prefix="$PREFIX" --disable-everything --disable-programs --disable-doc --disable-debug \
  --disable-x86asm --disable-autodetect --enable-pic --enable-static --disable-shared \
  --enable-vulkan --enable-decoder=vp9,av1,h264,hevc \
  --enable-hwaccel=vp9_vulkan,av1_vulkan,h264_vulkan,hevc_vulkan --enable-parser=vp9,av1,h264,hevc \
  --enable-bsf=vp9_superframe_split \
  --disable-avformat --disable-avdevice --disable-avfilter --disable-swresample --disable-swscale \
  --extra-cflags="-I$VKH -fvisibility=hidden -mmacosx-version-min=14.0"
make -j12
make install
