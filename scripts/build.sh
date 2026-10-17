#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Builds every kext of this repo on macOS without an Xcode project. Needs the Xcode command line tools.
# Kernel headers/libs come from acidanthera/MacKernelSDK (cloned into build/ on first use, or set MACKERNELSDK).
#
#   scripts/build.sh            build itlmt7925, ItlXhciKick, ItlDiag into build/*.kext
#   scripts/build.sh itlmt7925  build only the named kext(s)
#
# The MediaTek firmware in fw/ is embedded into itlmt7925 with .incbin (kexts/itlmt7925/fw_blob.c), so this script must
# run with the repo root as working directory (it does: it cd's there).
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
  local out="build/$name.kext" objs=()
  rm -rf "$out"; mkdir -p "$out/Contents/MacOS"
  cp "$dir/Info.plist" "$out/Contents/Info.plist"
  for src in "$@"; do
    local o="$OBJ/${name}_$(basename "${src%.*}").o"
    case "$src" in
      *.cpp) clang++ $COMMON $CXXFLAGS -I"$dir" -c "$dir/$src" -o "$o" ;;
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

# io80211check: compile-only (not part of the default set, never linked): the generated IO80211 headers must build with
# the kext flags and keep Apple's instance sizes (static_assert).
for t in "${TARGETS[@]+"${TARGETS[@]}"}"; do
  if [ "$t" = io80211check ]; then
    clang++ $COMMON $CXXFLAGS -Ikexts/itlmt7925 -fsyntax-only kexts/itlmt7925/io80211_compile_check.cpp
    echo "io80211check: ok"
  fi
done

want itlmt7925 "${TARGETS[@]+"${TARGETS[@]}"}" && build_kext itlmt7925 kexts/itlmt7925 \
  kmod_info.c itlmt7925.cpp itlmt7925_m1.cpp itlmt7925_m2.cpp itlmt7925_m3.cpp itlmt7925_pwr.cpp itlmt7925_ctl.cpp itlmt7925_eth.cpp itlmt7925_ba.cpp itlmt7925_uc.cpp itl_wpa.cpp itl_caps.cpp itl_ba.cpp fw_blob.c
# Native IO80211 front end (stage 1 controller + stage 2 interface; idle unless boot-arg itlmt_native=1, interface only with itlmt_native_if=1). Needs com.itlmt7925.kext loaded first.
want itlmt7925Native "${TARGETS[@]+"${TARGETS[@]}"}" && build_kext itlmt7925Native kexts/itlmt7925Native kmod_info.c itlmt7925_wifi.cpp itlmt7925_iface.cpp itlmt7925_awdl.cpp
want ItlXhciKick "${TARGETS[@]+"${TARGETS[@]}"}" && build_kext ItlXhciKick kexts/ItlXhciKick kmod_info.c ItlXhciKick.cpp
want ItlDiag "${TARGETS[@]+"${TARGETS[@]}"}" && build_kext ItlDiag kexts/ItlDiag kmod_info.c ItlDiag.cpp
want AmdCppc "${TARGETS[@]+"${TARGETS[@]}"}" && build_kext AmdCppc kexts/AmdCppc kmod_info.c AmdCppc.cpp
want MtkBtFw "${TARGETS[@]+"${TARGETS[@]}"}" && build_kext MtkBtFw kexts/MtkBtFw kmod_info.c MtkBtFw.cpp fw_blob.c
want AsusWmi "${TARGETS[@]+"${TARGETS[@]}"}" && build_kext AsusWmi kexts/AsusWmi kmod_info.c AsusWmi.cpp
# BtLeDlFix is a Lilu plugin: Lilu headers + plugin_start.cpp come from acidanthera/Lilu (cloned into build/Lilu).
if want BtLeDlFix "${TARGETS[@]+"${TARGETS[@]}"}"; then
  LILU_DIR="${LILU:-build/Lilu}"
  [ -d "$LILU_DIR" ] || git clone --depth 1 https://github.com/acidanthera/Lilu "$LILU_DIR"
  mkdir -p build/BtLeDlFix.kext/Contents/MacOS
  cp kexts/BtLeDlFix/Info.plist build/BtLeDlFix.kext/Contents/Info.plist
  LILU_DEFS="-DPRODUCT_NAME=BtLeDlFix -DMODULE_VERSION=1.0.0 -DLILU_KEXT"
  clang++ $COMMON $CXXFLAGS $LILU_DEFS -I"$LILU_DIR/Lilu" -c kexts/BtLeDlFix/BtLeDlFix.cpp -o "$OBJ/BtLeDlFix_main.o"
  clang++ $COMMON $CXXFLAGS $LILU_DEFS -I"$LILU_DIR/Lilu" -c "$LILU_DIR/Lilu/Library/plugin_start.cpp" -o "$OBJ/BtLeDlFix_start.o"
  clang   $COMMON -c kexts/BtLeDlFix/kmod_info.c -o "$OBJ/BtLeDlFix_kmod.o"
  clang++ -arch x86_64 -mmacosx-version-min="$LINK_MIN" -nostdlib -Xlinker -kext -Xlinker -no_data_const \
    -L"$SDK_DIR/Library/x86_64" -lkmodc++ -lkmod -lcc_kext "$OBJ/BtLeDlFix_main.o" "$OBJ/BtLeDlFix_start.o" "$OBJ/BtLeDlFix_kmod.o" \
    -o build/BtLeDlFix.kext/Contents/MacOS/BtLeDlFix
  echo "built build/BtLeDlFix.kext"
  echo "--- undefined symbols (BtLeDlFix)"
  nm -um build/BtLeDlFix.kext/Contents/MacOS/BtLeDlFix | head -40 || true
fi
exit 0
