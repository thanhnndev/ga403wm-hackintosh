#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# HiDPI ("200 %") for the built-in OLED on macOS: adds a display override with scale-resolutions only. RUN ON macOS (sudo).
#   scripts/macos-install-hidpi.sh          install; reboot, then switch with tools/hidpi-try.swift
#   scripts/macos-install-hidpi.sh --undo   remove it again
# Unlike the Linux installer (install-display-override.sh) this does NOT replace the EDID and does NOT delete the
# WindowServer prefs: the panel keeps the timing it boots with (2880x1800 @ 120 Hz), so picking a HiDPI size is a scaling
# change inside WindowServer, not a new mode for NVKMS.
# Entry format (IOGraphicsLib IOFBInstallScaledModes): width, height, install flags, mode flags to set.
# History on this machine (docs/HANDOFF.md item 7):
#   "w h 1 0x200000"   0x200000 = kDisplayModeValidForMirroringFlag alone: mirror-only, CoreGraphics drops the modes.
#   "w h 9 0xa00000"   Apple's own format for the 2880x1800 MacBook Pro panel (DisplayProductID-a013): still mirror-only, and
#                      the 2880x1800 entry is dropped as a duplicate of the native mode. WindowServer then builds "1440 x 900"
#                      HiDPI on the native mode itself but marks it unusable (flag 0x80000000; CoreDisplay: "Mode 65792 not
#                      available"), because NVRMFB never sets kDisplayModeValidForHiResFlag on its own modes.
#   now: "2880 1800 1 0x800000"  kScaleInstallAlways, valid for HiRes, NOT mirror-only: IOGraphicsLib installs a scaled mode
#                      whose desktop equals the raster (2880x1800 on 2880x1800, so NVRMFB's mode set needs no scaling) and
#                      that carries the HiRes flag; WindowServer can offer "looks like 1440 x 900" on it.
#   Only this one: 1680x1050 / 1280x800 HiDPI would need a real scaled NVKMS commit, which goes black on NullMoth (item 7),
#   and System Settings would offer them without a revert timer.
set -euo pipefail
VID=4c83; PID=419c
DIR=/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-$VID
F=$DIR/DisplayProductID-$PID
if [ "${1:-}" = "--undo" ]; then
  sudo rm -f "$F"; echo "removed $F; reboot (or log out) to drop the HiDPI sizes"; exit 0
fi
cur=$(ioreg -l -w0 2>/dev/null | grep -E '"DisplayVendorID" = |"DisplayProductID" = ' | sort -u | tr -d ' "|' | tr '\n' ' ')
case "$cur" in *DisplayProductID=16796*DisplayVendorID=19587*) ;; *) echo "built-in panel is not 4c83:419c ($cur): not installing"; exit 1;; esac
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# The override carries the live panel EDID (like Apple's own overrides): without IODisplayEDID in the
# override path, Settings derives no physical size and falls back to 72 DPI (built-in shows "47 inch").
# The EDID comes from the running driver, so this stays in sync with PanelEDID.
/usr/bin/python3 -I - "$T/o.plist" <<'PY'
import plistlib, struct, subprocess, sys
out = subprocess.run(['ioreg', '-rc', 'AppleBacklightDisplay', '-l', '-w0', '-a'],
                     capture_output=True, check=True).stdout
regs = plistlib.loads(out)
edid = None
def walk(o):
    global edid
    if isinstance(o, dict):
        if isinstance(o.get('IODisplayEDID'), bytes) and len(o['IODisplayEDID']) in (128, 256):
            edid = o['IODisplayEDID']
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
walk(regs)
if edid is None:
    sys.exit('live IODisplayEDID not found on AppleBacklightDisplay')
def ent(w, h): return struct.pack(">IIII", w, h, 1, 0x00800000)   # always; valid for HiRes, not mirror-only
plistlib.dump({"DisplayVendorID": 0x4c83, "DisplayProductID": 0x419c, "DisplayProductName": "Built-in OLED",
               "IODisplayEDID": edid,
               "scale-resolutions": [ent(2880, 1800)]}, open(sys.argv[1], "wb"))
print('embedded EDID bytes: %d' % len(edid))
PY
plutil -lint "$T/o.plist" >/dev/null
sudo mkdir -p "$DIR"
[ -f "$F" ] && sudo cp -p "$F" "$F.bak-$(date +%Y%m%d-%H%M%S)"
sudo cp "$T/o.plist" "$F"; sudo chown root:wheel "$F"; sudo chmod 644 "$F"
echo "installed $F. Reboot, then switch ONLY with tools/hidpi-try.swift (not System Settings: its 1440 x 900 can be the low-resolution mode that goes black)."
