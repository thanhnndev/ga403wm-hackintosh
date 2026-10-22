#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
#
# StrixVFCT: hand the firmware's ACPI VFCT table (the 890M VBIOS image) to NullMoth NMXGPU on macOS 26 (Step26).
#
# NMXGPU's xkpi AcpiGetTable() reads tables from an IORegistry property "ACPI Tables" = {"<SIG>": OSData}, which
# AppleACPIPlatformExpert no longer publishes on Tahoe ("no FADT"), so amdgpu_get_bios() ends in "Unable to locate a
# BIOS ROM" and GPU init fails. StrixVFCT is a codeless kext whose IOResources personality carries exactly that
# property with the VFCT bytes; OpenCore injects it so the node exists before NMXGPU attaches.
#
# The VFCT holds the board VBIOS (vendor firmware): it is read from a local dump (Linux /sys/firmware/acpi/tables/VFCT)
# and the kext is built under build/ only - never commit it.
#   macos-strixvfct-install.sh <VFCT.bin> <esp-mount>     build + copy to EFI/OC/Kexts + config.plist Kernel/Add
#   macos-strixvfct-install.sh --undo <esp-mount>
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [ "${1:-}" = --undo ]; then VFCT=; ESP=$2; else VFCT=$1; ESP=$2; fi
CFG=$ESP/EFI/OC/config.plist
[ -f "$CFG" ] || { echo "no $CFG"; exit 1; }

if [ -n "$VFCT" ]; then
  K=$ROOT/build/StrixVFCT.kext
  rm -rf "$K"; mkdir -p "$K/Contents"
  /usr/bin/python3 -I - "$VFCT" "$K/Contents/Info.plist" <<'EOF'
import plistlib, struct, sys
raw = open(sys.argv[1], 'rb').read()
sig, length = raw[:4], struct.unpack_from('<I', raw, 4)[0]
assert sig == b'VFCT' and length == len(raw), 'not a whole VFCT table'
assert sum(raw) & 0xff == 0, 'VFCT checksum'
# check there is an image for the 890M (1002:150e) - amdgpu matches bus/dev/fn/vendor/device against the pdev
p = struct.unpack_from("<I", raw, 0x34)[0]  # VBIOSImageOffset (after header 36 + TableUUID 16)
found = []
while p + 28 <= len(raw):
    bus, dev, fn, ven, did, ssv, ssid, rev, ilen = struct.unpack_from('<IIIHHHHII', raw, p)
    if ilen == 0: break
    found.append((bus, dev, fn, ven, did, ilen))
    p += 28 + ilen
assert any(v == 0x1002 and d == 0x150e for _, _, _, v, d, _ in found), found
info = {
    'CFBundleIdentifier': 'com.ga403wm.StrixVFCT', 'CFBundleName': 'StrixVFCT',
    'CFBundleInfoDictionaryVersion': '6.0', 'CFBundlePackageType': 'KEXT',
    'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '0.1.0', 'OSBundleRequired': 'Root',
    'IOKitPersonalities': {'StrixVFCT': {
        'CFBundleIdentifier': 'com.ga403wm.StrixVFCT', 'IOClass': 'IOService',
        'IOProviderClass': 'IOResources', 'IOMatchCategory': 'StrixVFCT',
        'ACPI Tables': {'VFCT': raw},
    }},
}
plistlib.dump(info, open(sys.argv[2], 'wb'))
print('VFCT', len(raw), 'bytes; images', [(b, d, f, '%04x:%04x' % (v, i), n) for b, d, f, v, i, n in found])
EOF
  [ -f "$CFG.pre-strixvfct" ] || cp "$CFG" "$CFG.pre-strixvfct"
  rm -rf "$ESP/EFI/OC/Kexts/StrixVFCT.kext"; cp -R "$K" "$ESP/EFI/OC/Kexts/"
fi

/usr/bin/python3 -I - "$CFG" "${VFCT:+add}" <<'EOF'
import plistlib, sys
p, add = sys.argv[1], sys.argv[2] == 'add'
d = plistlib.load(open(p, 'rb'))
ka = [k for k in d['Kernel']['Add'] if k.get('BundlePath') != 'StrixVFCT.kext']
if add:
    ka.append({'Arch': 'x86_64', 'BundlePath': 'StrixVFCT.kext', 'Comment': 'VFCT (890M VBIOS) for NMXGPU',
               'Enabled': True, 'ExecutablePath': '', 'MaxKernel': '', 'MinKernel': '25.0.0',
               'PlistPath': 'Contents/Info.plist'})
d['Kernel']['Add'] = ka
plistlib.dump(d, open(p, 'wb'))
print('Kernel/Add StrixVFCT:', 'enabled' if add else 'removed')
EOF
[ -z "$VFCT" ] && rm -rf "$ESP/EFI/OC/Kexts/StrixVFCT.kext"
echo done
