#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Installs build/StrixAccel.kext into /Library/Extensions and rebuilds the AuxKC (kmutil code 28 = reboot required). RUN AS ROOT.
#   sudo bash scripts/macos-strix-accel-install.sh            install build/StrixAccel.kext
#   sudo bash scripts/macos-strix-accel-install.sh --undo     put the previous copy back
# The previous copy is kept in ~/efi-audit/strixaccel-backup (outside /Library/Extensions so kmutil never sees it).
# Recovery without this script: boot-arg -strixaccoff (the kext then stays inert).
set -euo pipefail
cd "$(dirname "$0")/.."
OWNER=$(stat -f %Su .)
BK="/Users/$OWNER/efi-audit/strixaccel-backup"
DST=/Library/Extensions/StrixAccel.kext
if [ "${1:-}" = "--undo" ]; then
  LAST=$(ls -1d "$BK"/StrixAccel.kext.* | sort | tail -1)
  rm -rf "$DST"; cp -R "$LAST" "$DST"
else
  [ -d build/StrixAccel.kext ] || { echo "no build/StrixAccel.kext"; exit 1; }
  mkdir -p "$BK"
  [ -d "$DST" ] && cp -R "$DST" "$BK/StrixAccel.kext.$(date +%Y%m%dT%H%M%S)"
  rm -rf "$DST"; cp -R build/StrixAccel.kext "$DST"
fi
chown -R root:wheel "$DST"; chmod -R go-w "$DST"
echo "installed: $(/usr/bin/plutil -extract CFBundleShortVersionString raw "$DST/Contents/Info.plist")"
set +e
kmutil load --no-authorization -p "$DST"
rc=$?
echo "kmutil load rc=$rc (28 = AuxKC rebuilt, reboot required)"
exit 0
