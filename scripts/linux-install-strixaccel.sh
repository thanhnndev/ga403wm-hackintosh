#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Installs StrixAccel.kext into /Library/Extensions from Linux and drops the stale AuxKC.
#
# Why this exists: the AuxKC is a Mach-O fileset kernel collection that only kmutil/kernelmanagerd can build, so it
# cannot be produced from Linux. It does not have to be: kernelmanagerd links /Library/Extensions against
# BootKC+SystemKC itself, so dropping the old collection is enough to make the next macOS boot rebuild it.
#   boot 1  kernelmanagerd rebuilds AuxKC; the graphics bootstrap agent logs REBOOT_REQUIRED while the bundle is
#           still absent from `kmutil showloaded`,
#   boot 2  the kernel maps the fresh AuxKC and the new kext runs.
# Mount/chown/copy block mirrors the proven flow in scripts/linux-fix-strix-graphics.sh (that one is package driven
# and also rewrites config.plist; this one touches only the StrixAccel bundle and the AuxKC).
#
# RUN ON LINUX AS ROOT.
#   sudo bash scripts/linux-install-strixaccel.sh                        install /boot/EFI/StrixAccel-0.1.20.kext
#   sudo bash scripts/linux-install-strixaccel.sh /path/StrixAccel.kext  install a specific bundle
#   sudo bash scripts/linux-install-strixaccel.sh --undo                 put the newest backup back
#
# The Data volume is mounted rw *without* uid=/gid= on purpose: the driver then keeps real owners, so chown 0:0
# writes root:wheel into the catalog (with uid= set every inode reports that uid, and the write path stores it back).
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run this script with sudo.'; exit 1; }

NAME=StrixAccel
DEV=/dev/nvme0n1p4
MP=/mnt/macos-data
ESP=${ESP:-/boot}
BK="$ESP/EFI/OC/Kexts-backup"
REL="Library/Extensions/$NAME.kext"

UNDO=0
if [ "${1:-}" = "--undo" ]; then UNDO=1; shift; fi
SRC=${1:-$ESP/EFI/$NAME-0.1.20.kext}

mkdir -p "$BK" "$MP"

# linux-apfs-rw allows only one mount of the container while writing: peel every stacked mount first.
for _ in 1 2 3 4 5 6 7 8; do
    # findmnt exits 1 when nothing matches, so the substitution has to tolerate that under set -e/pipefail.
    targets=$(findmnt -rn -S "$DEV" -o TARGET 2>/dev/null | sort -u || true)
    [ -n "$targets" ] || break
    while IFS= read -r t; do umount "$t" || true; done <<< "$targets"
done
echo "mounting $DEV rw at $MP ..."
mount -t apfs -o rw,readwrite,vol=0 "$DEV" "$MP"
opts=$(findmnt -rn -T "$MP" -o OPTIONS 2>/dev/null || true)
if ! printf '%s\n' "$opts" | tr ',' '\n' | grep -qx rw; then
    echo "FATAL: $MP came up as '$opts' (need rw). Another mount of the container is probably still there:"
    echo "       findmnt -rn -S $DEV -o TARGET"
    exit 1
fi
if [[ ! -d "$MP/Library/Extensions" || ! -d "$MP/Library/KernelCollections" ]]; then
    echo "FATAL: $MP does not look like the macOS Data volume (Library/Extensions or Library/KernelCollections missing)"
    exit 1
fi

version_of() {
    python3 -I - "$1" <<'PY'
import plistlib, sys
try:
    print(plistlib.load(open(sys.argv[1], 'rb')).get('CFBundleShortVersionString', '?'))
except Exception:
    print('?')
PY
}

if [ $UNDO = 1 ]; then
    LAST=$(ls -1d "$BK/$NAME.kext."* 2>/dev/null | sort | tail -1 || true)
    [ -n "$LAST" ] || { echo "no $NAME backups in $BK"; exit 1; }
    echo "restoring $(basename "$LAST") (version $(version_of "$LAST/Contents/Info.plist"))"
    rm -rf "$MP/$REL"
    cp -a "$LAST" "$MP/$REL"
else
    [ -f "$SRC/Contents/MacOS/$NAME" ] || { echo "no bundle at $SRC (pass one as the first argument)"; exit 1; }
    want=$(sha256sum "$SRC/Contents/MacOS/$NAME" | awk '{print $1}')
    echo "source: $SRC  version $(version_of "$SRC/Contents/Info.plist")  sha256 ${want:0:12}…"
    if [ -e "$MP/$REL" ]; then
        ts=$(date +%Y%m%dT%H%M%S)
        cp -a "$MP/$REL" "$BK/$NAME.kext.$ts"
        echo "backed up installed copy -> $BK/$NAME.kext.$ts (version $(version_of "$MP/$REL/Contents/Info.plist"))"
    fi
    tmp="$MP/Library/Extensions/.$NAME.strix-install"
    rm -rf "$tmp"
    cp -a "$SRC" "$tmp"
    rm -rf "$MP/$REL"
    mv "$tmp" "$MP/$REL"
fi

# macOS only links kexts that are root:wheel and not group/world writable.
chown -hR 0:0 "$MP/$REL"
find "$MP/$REL" -type d -exec chmod 755 {} +
find "$MP/$REL" -type f -exec chmod 644 {} +
chmod 755 "$MP/$REL/Contents/MacOS/$NAME"

got=$(sha256sum "$MP/$REL/Contents/MacOS/$NAME" | awk '{print $1}')
if [ $UNDO = 0 ] && [ "$got" != "$want" ]; then
    echo "FATAL: installed bytes differ (${got:0:12}… != ${want:0:12}…)"
    exit 1
fi
echo "installed: $NAME version $(version_of "$MP/$REL/Contents/Info.plist") as 0:0 (root:wheel), sha256 ${got:0:12}…"

# Drop the stale collection so kernelmanagerd relinks it from /Library/Extensions on the next boot.
kc="$MP/Library/KernelCollections/AuxiliaryKernelExtensions.kc"
if [ -f "$kc" ]; then
    cp -a "$kc" "$BK/AuxiliaryKernelExtensions.kc.$(date +%Y%m%dT%H%M%S)"
    rm -f "$kc"
    echo "AuxKC moved aside (backup kept in $BK) - macOS rebuilds it on the next boot"
fi

sync
umount "$MP"
mount -t apfs -o "ro,vol=0,uid=${SUDO_UID:-1000},gid=${SUDO_GID:-1000}" "$DEV" "$MP" 2>/dev/null || true
echo
echo "OK. Boot macOS: boot 1 relinks the AuxKC (bootstrap logs REBOOT_REQUIRED), boot 2 runs the new kext."
echo "Verify on macOS:  ioreg -rc StrixAccelerator -l | grep -E 'StrixAccel,(Version|Res,Forced|Txn,BadStatus|AGDC,Cfg)'"
