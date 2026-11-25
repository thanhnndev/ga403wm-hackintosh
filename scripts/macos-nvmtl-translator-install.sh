#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Installs a libnvmtl_translate.dylib (AIR -> SPIR-V translator) built from the fork into the NVMTL plugin bundle, as
# root. Same swap as macos-nvmtl-plugin-install.sh: the bundle is copied, the dylib replaced and the bundle ad-hoc
# signed, then renamed into place, so running processes keep the translator they mapped; new processes load the new
# one, WindowServer on its next start. The plugin keys its SPIR-V caches by the dylib's sha256, so old cache entries
# are not reused.
#
#   sudo scripts/macos-nvmtl-translator-install.sh /path/to/libnvmtl_translate.dylib
#   sudo scripts/macos-nvmtl-translator-install.sh --undo      # the newest backup made by this script
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
B=/Library/GPUBundles/NVMTLDriver.bundle
LIB_REL=Contents/MacOS/libnvmtl_translate.dylib
TS=$(date -u +%Y%m%dT%H%M%SZ)
if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/nvmtl-translator-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/NVMTLDriver.bundle ]] || { echo "no backup"; exit 1; }
    T=$B.restore.$TS
    ditto "$BK/NVMTLDriver.bundle" "$T"
    mv "$B" "$B.old.$TS" && mv "$T" "$B" && rm -rf "$B.old.$TS"
    echo "restored $BK: translator $(shasum -a 256 "$B/$LIB_REL" | cut -c1-16)"
    exit 0
fi
NEW=${1:?usage: $0 libnvmtl_translate.dylib | --undo}
[[ $(file -b "$NEW") == *'Mach-O 64-bit dynamically linked shared library x86_64'* ]] || { echo "$NEW is not an x86_64 dylib"; exit 1; }
nm -gU "$NEW" | grep -q ' _nvmtl_translate$' || { echo "$NEW has no nvmtl_translate"; exit 1; }
BK=/Library/NullMoth/nvmtl-translator-$TS
mkdir -p "$BK"
ditto "$B" "$BK/NVMTLDriver.bundle"
echo "backup $BK (translator $(shasum -a 256 "$B/$LIB_REL" | cut -c1-16))"
T=$B.new.$TS
ditto "$B" "$T"
install -o 0 -g 0 -m 755 "$NEW" "$T/$LIB_REL"
codesign -f -s - "$T/$LIB_REL"
codesign -f -s - "$T"
codesign -v "$T"
mv "$B" "$B.old.$TS" && mv "$T" "$B" && rm -rf "$B.old.$TS"
echo "installed translator $(shasum -a 256 "$B/$LIB_REL" | cut -c1-16); new processes load it, WindowServer on its next start"
