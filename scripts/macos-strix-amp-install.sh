#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Stages build/StrixAmp.kext (read-only CS35L56 probe, docs/AUDIO-ROG.md) as an OpenCore-injected kext on the mounted ESP.
# No root needed (ESP mounted user-owned). It must be OC-injected, not put in /Library/Extensions: it links against
# VoodooI2C, which OpenCore injects into the boot collection, so kmutil cannot build an AuxKC containing it (code 31).
#   scripts/macos-strix-amp-install.sh            install: copy the kext, add Kernel>Add entry after the others
#   scripts/macos-strix-amp-install.sh --undo     remove the entry and the kext (config.plist backup is kept)
# Takes effect at the next boot. Read the result with:
#   ioreg -r -c StrixAmp -l -w0 | grep -E "ProbeStatus|DEVID|REVID"       (or scripts/macos-audio-collect.sh)
#   DEVID 0x00035a56 = a CS35L56 answered at I2C 0x30; ProbeStatus != 0 = NAK/timeout (amp in reset or unpowered).
# The kext only reads two registers and never writes.
set -euo pipefail
cd "$(dirname "$0")/.."
OC="${OC:-/Volumes/ESP/EFI/OC}"
[ -f "$OC/config.plist" ] || { echo "no $OC/config.plist (mount the ESP)"; exit 1; }
BK="$HOME/efi-audit"; mkdir -p "$BK"
cp "$OC/config.plist" "$BK/config.plist.pre-strixamp-$(date +%Y%m%dT%H%M%S)"
python3 -I - "$OC/config.plist" "${1:-}" <<'PY'
import sys
p, mode = sys.argv[1], sys.argv[2]
s = open(p, encoding='utf-8').read()
marker = '<string>StrixAmp.kext</string>'
def block_bounds(i):
    a = s.rfind('<dict>', 0, i); b = s.index('</dict>', i) + len('</dict>')
    ls = s.rfind('\n', 0, a) + 1
    return ls, b
if mode == '--undo':
    if marker in s:
        ls, b = block_bounds(s.index(marker))
        s = s[:ls] + s[b:].lstrip('\n')
else:
    if marker in s:
        print('entry already present'); sys.exit(0)
    # template: the AsusWmi entry (same Arch / MinKernel conventions), placed after the last Kernel>Add entry
    i = s.index('<string>AsusWmi.kext</string>')
    a = s.rfind('<dict>', 0, i); b = s.index('</dict>', i) + len('</dict>')
    blk = s[a:b]
    ls = s.rfind('\n', 0, a) + 1; indent = s[ls:a]
    new = (blk.replace('AsusWmi.kext', 'StrixAmp.kext').replace('Contents/MacOS/AsusWmi', 'Contents/MacOS/StrixAmp')
              .replace('ASUS ATK WMI: profile, power limits, charge limit (asusctl platform part)',
                       'CS35L56 speaker amp read-only probe (docs/AUDIO-ROG.md)'))
    end_add = s.index('</array>', s.index('<key>Add</key>', s.index('<key>Kernel</key>')))
    # insert before the closing </array> of Kernel>Add, after the last entry's newline
    ins = s.rfind('\n', 0, end_add) + 1
    s = s[:ins] + indent + new + '\n' + s[ins:]
open(p, 'w', encoding='utf-8').write(s)
PY
python3 -I -c "import plistlib,sys; c=plistlib.load(open('$OC/config.plist','rb')); print('Kernel>Add entries:', len(c['Kernel']['Add']), 'last:', c['Kernel']['Add'][-1]['BundlePath'])"
if [ "${1:-}" = "--undo" ]; then
  rm -rf "$OC/Kexts/StrixAmp.kext"; echo "removed; reboot to apply"
else
  [ -d build/StrixAmp.kext ] || { echo "no build/StrixAmp.kext (run: scripts/build.sh StrixAmp)"; exit 1; }
  rm -rf "$OC/Kexts/StrixAmp.kext"; cp -R build/StrixAmp.kext "$OC/Kexts/StrixAmp.kext"
  echo "staged; reboot to apply"
fi
