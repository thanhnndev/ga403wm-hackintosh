#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Installs build/StrixGOP.kext into /Library/Extensions and rebuilds the AuxKC (kmutil code 28 = reboot required). RUN AS ROOT.
#   sudo bash scripts/macos-strix-gop-install.sh            install build/StrixGOP.kext
#   sudo bash scripts/macos-strix-gop-install.sh --undo     put the previous copy back
#   sudo bash scripts/macos-strix-gop-install.sh --hdr      install and publish the HDR10 mode twins (0.1.8, personality HdrModes=true)
#   sudo bash scripts/macos-strix-gop-install.sh --nohdr    install with the twins off (the carried-over value is replaced)
# Boot-arg overrides: strixhdr=1 forces them on, -strixhdroff forces them off.
# The machine-specific personality values (BootGOPProfile, AdoptBootGOP, PanelEDID, PanelEDIDSource) are carried over
# from the copy that is installed now, so a rebuilt binary keeps adopting the boot GOP without re-running the trial tool.
# The previous copy is kept in ~/efi-audit/strixgop-backup (outside /Library/Extensions so kmutil never sees it).
# Recovery without this script: boot-arg -strixgopoff (framebuffer inert) or -strixauxoff (only the brightness part).
set -euo pipefail
cd "$(dirname "$0")/.."
HDRFLAG=keep
case "${1:-}" in --hdr) HDRFLAG=on; set -- ;; --nohdr) HDRFLAG=off; set -- ;; esac
OWNER=$(stat -f %Su .)
BK="/Users/$OWNER/efi-audit/strixgop-backup"
DST=/Library/Extensions/StrixGOP.kext
if [ "${1:-}" = "--undo" ]; then
  LAST=$(ls -1d "$BK"/StrixGOP.kext.* | sort | tail -1)
  rm -rf "$DST"; cp -R "$LAST" "$DST"
else
  [ -d build/StrixGOP.kext ] || { echo "no build/StrixGOP.kext"; exit 1; }
  [ -d "$DST" ] || { echo "no installed $DST to take the personality from"; exit 1; }
  mkdir -p "$BK"
  STAGE=$(mktemp -d)
  cp -R build/StrixGOP.kext "$STAGE/StrixGOP.kext"
  python3 -I - "$DST/Contents/Info.plist" "$STAGE/StrixGOP.kext/Contents/Info.plist" "$HDRFLAG" <<'PY'
import plistlib, sys
old = plistlib.load(open(sys.argv[1], 'rb'))['IOKitPersonalities']['StrixGOP']
path = sys.argv[2]
new = plistlib.load(open(path, 'rb'))
p = new['IOKitPersonalities']['StrixGOP']
for k in ('BootGOPProfile', 'AdoptBootGOP', 'PanelEDID', 'PanelEDIDSource'):
    if k in old: p[k] = old[k]
if 'HdrModes' in old: p['HdrModes'] = old['HdrModes']
if sys.argv[3] == 'on': p['HdrModes'] = True
elif sys.argv[3] == 'off': p['HdrModes'] = False
assert p.get('AdoptBootGOP') is True and 'BootGOPProfile' in p, 'installed personality lacks the boot profile'
plistlib.dump(new, open(path, 'wb'))
PY
  cp -R "$DST" "$BK/StrixGOP.kext.$(date +%Y%m%dT%H%M%S)"
  rm -rf "$DST"; cp -R "$STAGE/StrixGOP.kext" "$DST"; rm -rf "$STAGE"
fi
chown -R root:wheel "$DST"; chmod -R go-w "$DST"
echo "installed: $(/usr/bin/plutil -extract CFBundleShortVersionString raw "$DST/Contents/Info.plist")"
set +e
kmutil load --no-authorization -p "$DST"
rc=$?
echo "kmutil load rc=$rc (28 = AuxKC rebuilt, reboot required)"
exit 0
