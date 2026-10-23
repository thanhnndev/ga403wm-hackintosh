#!/bin/bash
# Install a CI-built NVMTLDriver plugin (the Metal-over-Vulkan bundle both accelerators point MetalPluginName at)
# into the macOS Data volume from Linux. No kext relink is needed: /Library/GPUBundles is a plain userspace bundle.
#
#   pkexec scripts/linux-install-nvmtl.sh /path/to/NVMTLDriver
#
# The artifact comes from the "plugin" job of build-nmxaccel.yml (nvmtl-ci), which ad-hoc signs it on a macOS 26
# runner. Keep the current binary: it is copied to /Library/NullMoth/nvmtl-backup-<stamp>/ first, and copying that
# back is the rollback. The destination bundle must already exist (the driver payload ships it).
set -euo pipefail

SRC=${1:-}
[ -n "$SRC" ] && [ -f "$SRC" ] || { echo "usage: $0 /path/to/NVMTLDriver" >&2; exit 2; }
file "$SRC" | grep -q 'Mach-O 64-bit x86_64 bundle' || { echo "not an x86_64 Mach-O bundle: $SRC" >&2; exit 3; }

DEV=${DEV:-/dev/nvme0n1p4}
MNT=${MNT:-/mnt/macos-vol0}
DST=$MNT/Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver

mkdir -p "$MNT"
if ! mountpoint -q "$MNT"; then
    mount -t apfs -o rw,uid=0,gid=0,vol=0 "$DEV" "$MNT"
fi
mount | grep -q " $MNT .* rw" || mount -o remount,rw "$MNT"
[ -f "$DST" ] || { echo "no bundle at $DST -- install the driver payload first" >&2; exit 4; }

STAMP=$(date +%Y%m%dT%H%M%SZ)
BACKUP=$MNT/Library/NullMoth/nvmtl-backup-$STAMP
mkdir -p "$BACKUP"
cp -a "$DST" "$BACKUP/NVMTLDriver"
OLD=$(sha256sum "$BACKUP/NVMTLDriver" | cut -d' ' -f1)

install -m 755 "$SRC" "$DST"
NEW=$(sha256sum "$DST" | cut -d' ' -f1)
echo "backup  $BACKUP/NVMTLDriver  $OLD"
echo "install $DST  $NEW"
[ "$OLD" != "$NEW" ] || echo "WARNING: the installed binary is byte-identical to the backup"

sync
echo "done -- reboot macOS; the plugin loads with WindowServer, so nothing else is needed"
