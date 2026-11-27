#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Builds every kext of this repo on macOS without an Xcode project. Needs the Xcode command line tools.
# Kernel headers/libs come from acidanthera/MacKernelSDK (cloned into build/ on first use, or set MACKERNELSDK).
#
#   scripts/build.sh              build ItlXhciKick and ItlDiag into build/*.kext
#   scripts/build.sh ItlDiag      build only the named kext(s)
#   scripts/build.sh StrixS0ix    named-only targets: StrixS0ix, StrixSbxMap (clones Lilu), StrixProbe, StrixMetalGate,
#                                 StrixGOP, StrixAccel, StrixHeadroom (clones Lilu)
#
# Moved out: the MT7925 Wi-Fi and Bluetooth kexts to https://github.com/thanhnndev/mt7925-macos, AsusWmi and AmdCppc to
# https://github.com/thanhnndev/rog-control-macos.
set -euo pipefail
cd "$(dirname "$0")/.."

SDK_DIR="${MACKERNELSDK:-build/MacKernelSDK}"
if [ ! -d "$SDK_DIR" ]; then
  mkdir -p build
  git clone --depth 1 https://github.com/acidanthera/MacKernelSDK "$SDK_DIR"
fi

# -nostdlibinc: only MacKernelSDK and clang's own headers (IOHIDDescriptorParser.h pulls <MacTypes.h> if the host SDK has one)
COMMON="-arch x86_64 -mmacosx-version-min=12.0 -O2 -g -fno-omit-frame-pointer -mkernel -fno-builtin -fno-stack-protector -nostdlib -nostdlibinc -ffreestanding -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT -I$SDK_DIR/Headers"
CXXFLAGS="-std=c++17 -fapple-kext -fno-exceptions -fno-rtti"     # -fapple-kext is C++ only
# libkmodc++/libcc_kext come from the installed SDK (MacKernelSDK has only libkmod) and are built for that SDK's macOS.
# Linking with a lower deployment target makes ld warn "built for newer macOS version"; link with the library's own
# minimum instead (the kernel does not check a kext's minos). Compilation stays at 12.0.
LINK_MIN=$(otool -l "$(xcrun --show-sdk-path)/usr/lib/libkmodc++.a" 2>/dev/null | awk '/minos/ {print $2; exit}')
LINK_MIN=${LINK_MIN:-12.0}
OBJ=build/obj
mkdir -p "$OBJ"

# build_kext <name> <source dir> <source files...>
# Bundle layout: build/<name>.kext/Contents/{Info.plist,MacOS/<name>}
build_kext() {
  local name="$1" dir="$2"; shift 2
  local out="build/$name.kext" objs=() extra_cxx=()
  case "$name" in StrixProbe|StrixGOP|StrixMetalGate|StrixS0ix) extra_cxx+=(-fno-c++-static-destructors -Wall -Wextra -Werror -MMD) ;; esac
  # StrixAccel subclasses the IOAcceleratorFamily2 private classes through a generated header: its hidden-overload
  # and tag warnings are noise, everything else stays on.
  case "$name" in StrixAccel) extra_cxx+=(-fno-c++-static-destructors -Wall -Wextra -Wno-unused-parameter -Wno-overloaded-virtual -Wno-mismatched-tags -MMD) ;; esac
  rm -rf "$out"; mkdir -p "$out/Contents/MacOS"
  cp "$dir/Info.plist" "$out/Contents/Info.plist"
  for src in "$@"; do
    local o="$OBJ/${name}_$(basename "${src%.*}").o"
    case "$src" in
      *.cpp) clang++ $COMMON $CXXFLAGS ${extra_cxx[@]+"${extra_cxx[@]}"} -I"$dir" -c "$dir/$src" -o "$o" ;;
      *.c)   clang   $COMMON -I"$dir" -c "$dir/$src" -o "$o" ;;
    esac
    objs+=("$o")
  done
  clang++ -arch x86_64 -mmacosx-version-min="$LINK_MIN" -nostdlib -Xlinker -kext -Xlinker -no_data_const \
    -L"$SDK_DIR/Library/x86_64" -lkmodc++ -lkmod -lcc_kext "${objs[@]}" -o "$out/Contents/MacOS/$name"
  echo "built $out"
  file "$out/Contents/MacOS/$name"
  echo "--- undefined symbols ($name)"
  nm -um "$out/Contents/MacOS/$name" || true
}

want() { local n="$1"; shift; [ $# -eq 0 ] && return 0; for a in "$@"; do [ "$a" = "$n" ] && return 0; done; return 1; }
TARGETS=("$@")

want ItlXhciKick "${TARGETS[@]+"${TARGETS[@]}"}" && build_kext ItlXhciKick kexts/ItlXhciKick kmod_info.c ItlXhciKick.cpp
want ItlDiag "${TARGETS[@]+"${TARGETS[@]}"}" && build_kext ItlDiag kexts/ItlDiag kmod_info.c ItlDiag.cpp
want StrixAmp "${TARGETS[@]+"${TARGETS[@]}"}" && build_kext StrixAmp kexts/StrixAmp kmod_info.c StrixAmp.cpp
# The Strix* kexts are built only when named. StrixS0ix and StrixSbxMap are part of the Tahoe (890M) setup; StrixProbe,
# StrixMetalGate, StrixGOP, StrixAccel and StrixHeadroom are the earlier boot-display research (superseded by NMXGPU).
if [ ${#TARGETS[@]} -gt 0 ] && want StrixProbe "${TARGETS[@]}"; then
  build_kext StrixProbe kexts/StrixProbe kmod_info.c StrixProbe.cpp
fi
if [ ${#TARGETS[@]} -gt 0 ] && want StrixMetalGate "${TARGETS[@]}"; then
  build_kext StrixMetalGate kexts/StrixMetalGate kmod_info.c StrixMetalGate.cpp
fi
if [ ${#TARGETS[@]} -gt 0 ] && want StrixGOP "${TARGETS[@]}"; then
  build_kext StrixGOP kexts/StrixGOP kmod_info.c StrixGOP.cpp
fi
if [ ${#TARGETS[@]} -gt 0 ] && want StrixS0ix "${TARGETS[@]}"; then
  build_kext StrixS0ix kexts/StrixS0ix kmod_info.c StrixS0ix.cpp
fi
if [ ${#TARGETS[@]} -gt 0 ] && want StrixAccel "${TARGETS[@]}"; then
  build_kext StrixAccel kexts/StrixAccel kmod_info.c StrixAccel.cpp
fi
# Lilu plugin: needs the Lilu headers + plugin_start.cpp (cloned like MacKernelSDK); Lilu symbols stay undefined and are
# resolved at load through OSBundleLibraries as.vit9696.Lilu.
if [ ${#TARGETS[@]} -gt 0 ] && want StrixHeadroom "${TARGETS[@]}"; then
  LILU_DIR="${LILU_DIR:-build/Lilu}"
  [ -d "$LILU_DIR" ] || git clone --depth 1 https://github.com/acidanthera/Lilu "$LILU_DIR"
  mkdir -p build/obj
  cp "$LILU_DIR/Lilu/Library/plugin_start.cpp" kexts/StrixHeadroom/plugin_start.cpp
  trap 'rm -f kexts/StrixHeadroom/plugin_start.cpp' EXIT
  COMMON="$COMMON -I$LILU_DIR/Lilu -DPRODUCT_NAME=StrixHeadroom -DMODULE_VERSION=0.1.0 -DLILU_KEXTPATCH=1 -Wno-unknown-warning-option -Wno-vla"
  build_kext StrixHeadroom kexts/StrixHeadroom kmod_info.c StrixHeadroom.cpp plugin_start.cpp
fi
# StrixSbxMap: Lilu plugin with its own IOService (reads the pinned file list from its personality).
if [ ${#TARGETS[@]} -gt 0 ] && want StrixSbxMap "${TARGETS[@]}"; then
  LILU_DIR="${LILU_DIR:-build/Lilu}"
  [ -d "$LILU_DIR" ] || git clone --depth 1 https://github.com/acidanthera/Lilu "$LILU_DIR"
  cp "$LILU_DIR/Lilu/Library/plugin_start.cpp" kexts/StrixSbxMap/plugin_start.cpp
  trap 'rm -f kexts/StrixHeadroom/plugin_start.cpp kexts/StrixSbxMap/plugin_start.cpp' EXIT
  SAVED_COMMON="$COMMON"
  COMMON="$COMMON -I$LILU_DIR/Lilu -DPRODUCT_NAME=StrixSbxMap -DMODULE_VERSION=0.1.0 -DLILU_KEXTPATCH=1 -DLILU_CUSTOM_IOKIT_INIT=1 -Wno-unknown-warning-option -Wno-vla"
  build_kext StrixSbxMap kexts/StrixSbxMap kmod_info.c StrixSbxMap.cpp plugin_start.cpp
  COMMON="$SAVED_COMMON"
fi
exit 0
