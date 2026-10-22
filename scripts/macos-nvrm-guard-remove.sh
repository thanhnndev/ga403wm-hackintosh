#!/bin/bash
# Remove NullMoth's NVRAM boot guard from the prebuilt NVRM kernel extension.
#
# NVRM counts its own starts in the NVRAM variable "nullmoth-nv-starts" and, once the counter reaches 2,
# nvrm_driver_off() answers "off" and the driver refuses to attach for that whole boot. That mechanism exists to
# keep a crashing driver from looping the machine, but on this laptop it parks a driver that has to come up (the
# NVIDIA GPU is the only Metal device WindowServer can use) and it made a parked boot look like a driver bug.
#
# The check is the only reader of the counter:
#
#   7e7f:  80 38 02                 cmpb   $0x2,(%rax)        ; starts >= 2 ?
#   7e82:  41 0f 93 c7              setae  %r15b              ; -> nvrm_driver_off() returns true
#
# It is replaced with "xor %r15d,%r15d" plus a four-byte nop, so the counter can no longer park the driver while the
# "nullmoth-remove" NVRAM switch keeps working. The counter itself is still maintained; nothing reads it afterwards.
#
# NVRM is a prebuilt binary (the 610.57.04 core has no source in this tree), so this is a byte patch, not a rebuild.
# Re-run with --undo to restore the backed-up kext.
set -euo pipefail

KEXT=/Library/Extensions/NVRM.kext
BIN="$KEXT/Contents/MacOS/NVRM"
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
NEW="$KC.guard-new"
OFF=32383                     # 0x7e7f, file offset equals the __TEXT address here (vmaddr 0, fileoff 0)
ORIG=80:38:02:41:0f:93:c7
PATCH=45:31:ff:0f:1f:40:00

[[ $(id -u) == 0 ]] || { echo "run as root" >&2; exit 1; }
[[ -f "$BIN" ]] || { echo "no $BIN" >&2; exit 1; }

if [[ ${1:-} == --undo ]]; then
    B=$(ls -dt /Library/NullMoth/nvrm-guard-* 2>/dev/null | head -1)
    [[ -n "$B" ]] || { echo "no backup under /Library/NullMoth/nvrm-guard-*" >&2; exit 1; }
    rm -rf "$KEXT"
    ditto "$B/NVRM.kext" "$KEXT"
    codesign --force --sign - --timestamp=none "$KEXT" >/dev/null
    echo "restored NVRM from $B; rebuild the kernel collection with macos-nmx-owns-oled-install.sh or:"
    echo "  kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \\"
    echo "   -B /System/Library/KernelCollections/BootKernelExtensions.kc \\"
    echo "   -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions -A $NEW -z"
    exit 0
fi

have=$(xxd -p -l 7 -s "$OFF" "$BIN" | tr -d '\n' | sed 's/\(..\)/\1:/g; s/:$//')
if [[ $have == "$PATCH" ]]; then
    echo "NVRM guard already removed ($have)"
    exit 0
fi
[[ $have == "$ORIG" ]] || { echo "unexpected bytes at 0x$(printf %x "$OFF"): $have (want $ORIG)" >&2; exit 1; }

BK=$(mktemp -d /Library/NullMoth/nvrm-guard-XXXXXXXX)
chmod 700 "$BK"
ditto "$KEXT" "$BK/NVRM.kext"
echo "backup $BK"

python3 - "$BIN" "$OFF" "$PATCH" <<'PY'
import sys
path, off, patch = sys.argv[1], int(sys.argv[2]), bytes(int(b, 16) for b in sys.argv[3].split(':'))
with open(path, 'r+b') as f:
    f.seek(off)
    f.write(patch)
print("patched %d bytes at 0x%x" % (len(patch), off))
PY

codesign --force --sign - --timestamp=none "$KEXT" >/dev/null
echo "re-signed ad-hoc"

kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions -A "$NEW" -z

python3 - "$NEW" <<'PY'
import re, subprocess, sys
from pathlib import Path
kc = Path(sys.argv[1]).read_bytes()
bin = '/Library/Extensions/NVRM.kext/Contents/MacOS/NVRM'
out = subprocess.run(['/usr/bin/otool', '-l', bin], capture_output=True, text=True).stdout
m = re.search(r'LC_UUID\s+cmdsize \d+\s+uuid ([0-9A-F-]{36})', out)
assert m, 'no LC_UUID in NVRM'
u = m.group(1)
assert bytes.fromhex(u.replace('-', '')) in kc, 'NVRM %s absent from the new collection' % u
print('  NVRM %s present in the new collection' % u)
PY

mv -f "$NEW" "$KC"
echo "NullMoth NVRAM boot guard removed from NVRM; reboot pending"
