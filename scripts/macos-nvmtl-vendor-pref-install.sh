#!/bin/bash
# Install the NVMTL vendor-preference build: WindowServer asks for the panel's GPU (AMD/RADV, M3c) instead of NVIDIA
# whenever NMXAccel owns a display pipe, and a probe can force the choice with NVMTL_PREFER_VENDOR.
#
# Safety: the deployed plugin is backed up first, the new build has to pass two probes (AMD device runs a clear, NVIDIA
# device still enumerates), and any failure restores the backup. WindowServer keeps running the plugin it already
# loaded, so nothing changes for the live session until the next WindowServer start.
#   bash scripts/macos-nvmtl-vendor-pref-install.sh
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'run with administrator privileges (sudo)'; exit 1; }
REPO=$(cd "$(dirname "$0")/.." && pwd)
# This runs as root (osascript/sudo), so $HOME is /var/root: the sources and the Vulkan headers belong to the
# console account, not to root.
OWNER_HOME=$(dscl . -read "/Users/$(stat -f %Su /dev/console)" NFSHomeDirectory | awk '{print $2}')
PLUGIN_SRC=${PLUGIN_SRC:-$OWNER_HOME/develop/projects/890m-ws-plugin}
VULKAN_INC=${VULKAN_INC:-$OWNER_HOME/Vulkan-Headers/include}
OUT=${OUT:-$REPO/out/890m-trace/nvmtl-vendor-pref}
BUNDLE=/Library/GPUBundles/NVMTLDriver.bundle
BIN=$BUNDLE/Contents/MacOS/NVMTLDriver
OWNER=$(stat -f %Su /dev/console)
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP=/Library/NullMoth/nvmtl-vendor-pref-$STAMP
mkdir -p "$OUT" "$BACKUP"

echo "== build plugin from $PLUGIN_SRC"
(cd "$PLUGIN_SRC/plugin" && xcrun clang -arch x86_64 -bundle -fobjc-arc -O1 -DNVMTL_RELEASE=1 \
    -Wno-protocol -Wno-incomplete-implementation -I"$VULKAN_INC" \
    -o "$OUT/NVMTLDriver" NVMTLDevice.m -framework Foundation -framework Metal -framework IOSurface -framework IOKit) 2>&1 | tail -3
# grep -q closes the pipe early, and pipefail then reports strings' SIGPIPE as a failure: check a file, not a pipe.
strings -a "$OUT/NVMTLDriver" > "$OUT/strings.txt"
grep -q NVMTL_PREFER_VENDOR "$OUT/strings.txt" || { echo 'build is missing the vendor preference'; exit 1; }

echo "== build probe"
xcrun swiftc -O -o "$OUT/mtl-device-probe" "$REPO/tools/890m/mtl-device-probe.swift"

echo "== back up the deployed plugin to $BACKUP"
ditto "$BUNDLE" "$BACKUP/NVMTLDriver.bundle"
"$OUT/mtl-device-probe" > "$OUT/probe-before.txt" 2>&1 || true
sudo -u "$OWNER" "$OUT/mtl-device-probe" >> "$OUT/probe-before.txt" 2>&1 || true
tail -4 "$OUT/probe-before.txt"

rollback() {
    echo "!! restoring $BACKUP/NVMTLDriver.bundle"
    rm -rf "$BUNDLE"; ditto "$BACKUP/NVMTLDriver.bundle" "$BUNDLE"
    chown -R root:wheel "$BUNDLE"
    codesign --verify "$BUNDLE" && echo "rollback verified"
}
trap rollback ERR

echo "== install"
cp "$OUT/NVMTLDriver" "$BIN"
codesign -f -s - --preserve-metadata=identifier,entitlements,flags,runtime "$BUNDLE"
codesign --verify "$BUNDLE"

echo "== probe: forced AMD (the M3c gate)"
sudo -u "$OWNER" /usr/bin/env NVMTL_PREFER_VENDOR=1002 "$OUT/mtl-device-probe" --require-amd | tee "$OUT/probe-amd.txt"

echo "== probe: default process (NVIDIA must still be the device)"
sudo -u "$OWNER" "$OUT/mtl-device-probe" | tee "$OUT/probe-default.txt"
grep -q "NVIDIA" "$OUT/probe-default.txt" || { echo 'the default device is no longer NVIDIA'; false; }

trap - ERR
echo "== installed $(shasum -a 256 "$BIN" | cut -c1-16)"
echo "backup: $BACKUP   (restore: ditto $BACKUP/NVMTLDriver.bundle $BUNDLE)"
echo "WindowServer still runs the previous plugin until it restarts."
