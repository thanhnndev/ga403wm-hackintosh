#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Build VCNDec.bundle (VideoToolbox decoder, ad-hoc signed) and vcndec_test.
# Needs the minimal static libavcodec from ff-build.sh (FF=prefix, default ~/develop/projects/radv-video/ff-vcn/inst).
set -e
cd "$(dirname "$0")"
FF=${FF:-$HOME/develop/projects/radv-video/ff-vcn/inst}
VKH=${VKH:-$HOME/develop/projects/radv-video/Vulkan-Headers-1.4.330/include}
CF="-arch x86_64 -O2 -Wall -Wno-four-char-constants -mmacosx-version-min=14.0 -I$FF/include -I$VKH"
LIBS="$FF/lib/libavcodec.a $FF/lib/libavutil.a -framework CoreFoundation -framework CoreMedia -framework CoreVideo \
  -framework VideoToolbox -framework IOSurface -lm"
B=build/VCNDec.bundle
rm -rf build; mkdir -p $B/Contents/MacOS
cp Info.plist $B/Contents/Info.plist
clang $CF -bundle -fvisibility=hidden -o $B/Contents/MacOS/VCNDec src/vcnvt.c src/vcndec.c $LIBS
codesign -f -s - $B
clang $CF -o build/vcndec_test src/vcndec_test.c src/vcndec.c $LIBS
codesign -f -s - build/vcndec_test
echo built: $B build/vcndec_test
clang -arch x86_64 -O2 -Wall -Wno-four-char-constants -mmacosx-version-min=14.0 -o build/vt_test src/vt_test.c \
  -framework CoreFoundation -framework CoreMedia -framework CoreVideo -framework VideoToolbox
codesign -f -s - build/vt_test
echo built: build/vt_test
