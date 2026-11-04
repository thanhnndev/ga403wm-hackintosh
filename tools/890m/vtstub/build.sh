#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Build VTStub.bundle (ad-hoc signed) and the vtprobe test host.
set -e
cd "$(dirname "$0")"
B=build/VTStub.bundle
rm -rf build; mkdir -p $B/Contents/MacOS
cp Info.plist $B/Contents/Info.plist
clang -arch x86_64 -bundle -O1 -Wall -Wno-four-char-constants -o $B/Contents/MacOS/VTStub src/vtstub.c \
  -framework CoreFoundation -framework CoreMedia -framework CoreVideo -framework VideoToolbox
codesign -f -s - $B
clang -arch x86_64 -fobjc-arc -O1 -Wall -Wno-four-char-constants -o build/vtprobe src/vtprobe.m \
  -framework Foundation -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework VideoToolbox
codesign -f -s - build/vtprobe
echo built: $B build/vtprobe
