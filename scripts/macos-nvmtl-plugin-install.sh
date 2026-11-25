#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Installs an NVMTLDriver binary built from the fork (branch ci/amd-plugin-890m) into /Library/GPUBundles, as root.
# The bundle is copied, the binary replaced and ad-hoc signed, then swapped in by rename (never written in place), so a
# running WindowServer keeps the driver it mapped; new processes load the new one, WindowServer on its next start.
#
#   sudo scripts/macos-nvmtl-plugin-install.sh /path/to/NVMTLDriver
#   sudo scripts/macos-nvmtl-plugin-install.sh --undo      # the newest backup made by this script
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
B=/Library/GPUBundles/NVMTLDriver.bundle
BIN_REL=Contents/MacOS/NVMTLDriver
TS=$(date -u +%Y%m%dT%H%M%SZ)
if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/nvmtl-plugin-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/NVMTLDriver.bundle ]] || { echo "no backup"; exit 1; }
    T=$B.restore.$TS
    ditto "$BK/NVMTLDriver.bundle" "$T"
    mv "$B" "$B.old.$TS" && mv "$T" "$B" && rm -rf "$B.old.$TS"
    echo "restored $BK: $(shasum -a 256 "$B/$BIN_REL" | cut -c1-16)"
    exit 0
fi
NEW=${1:?usage: $0 NVMTLDriver | --undo}
[[ $(file -b "$NEW") == *'Mach-O 64-bit bundle x86_64'* ]] || { echo "$NEW is not an x86_64 bundle"; exit 1; }
grep -qa 'does not claim this process' "$NEW" || { echo "$NEW does not look like NVMTLDriver"; exit 1; }
BK=/Library/NullMoth/nvmtl-plugin-$TS
mkdir -p "$BK"
ditto "$B" "$BK/NVMTLDriver.bundle"
echo "backup $BK ($(shasum -a 256 "$B/$BIN_REL" | cut -c1-16))"
T=$B.new.$TS
ditto "$B" "$T"
install -o 0 -g 0 -m 755 "$NEW" "$T/$BIN_REL"
codesign -f -s - "$T"
codesign -v "$T"
mv "$B" "$B.old.$TS" && mv "$T" "$B" && rm -rf "$B.old.$TS"
echo "installed: $(shasum -a 256 "$B/$BIN_REL" | cut -c1-16); WindowServer loads it on its next start"
