#!/bin/bash
# run.sh <plugin NVMTLDriver> [frames=1200] [env...]: own-process submit census (WS-CPU 9.3). Builds the ioctl /
# IOConnect / IOSurfaceSetValue(s) interposer and the CARenderer test, runs the test with the interposer, prints
# per-present counts and CPU for the steady 3/4 of the frames. No root, no system process touched.
# Useful env: IOSURF_FB=1 (IOSurface render targets), NVMTL_NMX_FENCE=2 (fence marks outside WindowServer; debug
# plugin builds), FRAME_GAP_US=12000 (WindowServer-like pacing), IOC_BT=<ioctl hex>|sel<N> (call stacks),
# EXTRA_BOS=<n> (n extra 1 MB buffers held).
set -eu
here=$(cd "$(dirname "$0")" && pwd); plugin=$1; fr=${2:-1200}; shift; if [ $# -gt 0 ]; then shift; fi
out=${TMPDIR:-/tmp}/submit-census; mkdir -p "$out"
xcrun clang -arch x86_64 -dynamiclib -O1 -o "$out/libioccount.dylib" "$here/ioccount.c" -framework IOKit -framework IOSurface
xcrun clang -arch x86_64 -fobjc-arc -O1 -o "$out/carender_ioc" "$here/carender_ioc.m" -framework Foundation -framework Metal \
  -framework IOSurface -framework IOKit -framework CoreVideo -framework QuartzCore -framework CoreGraphics
ln -sf /Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/libnvmtl_translate.dylib "$(dirname "$plugin")/libnvmtl_translate.dylib" 2>/dev/null || true
env DYLD_INSERT_LIBRARIES="$out/libioccount.dylib" NM_TEST_PLUGIN="$plugin" "$@" /usr/bin/perl -e 'alarm 300; exec @ARGV' \
  "$out/carender_ioc" "$fr" ${VIDEO:-0} 6 2>&1 | grep -v "is implemented in both\|^objc"
