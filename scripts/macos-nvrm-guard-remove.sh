#!/bin/bash
# Remove NullMoth's NVRAM boot guard from the prebuilt NVRM kernel extension.
#
# NVRM counts its own starts in the NVRAM variable "nullmoth-nv-starts" and, once the counter reaches 2,
# nvrm_driver_off() answers "off" and the driver refuses to attach for that whole boot. That mechanism exists to keep a
# crashing driver from looping the machine, but on this laptop it parked the only Metal device WindowServer can use and
# made a parked boot look like a driver bug. Its companion LaunchDaemon (com.nullmoth.bootguard) is what writes the
# counter back, so both halves go.
#
# The check is the only reader of the counter (610 core at 0x7e7f, 615 core at 0x6f8f):
#
#   80 38 02              cmpb   $0x2,(%rax)        ; starts >= 2 ?
#   41 0f 93 c7           setae  %r15b              ; -> nvrm_driver_off() returns true
#
# It is replaced with "xor %r15d,%r15d" plus a four-byte nop, so the counter can no longer park the driver while the
# "nullmoth-remove" NVRAM switch keeps working. The pattern is located by content, not by a fixed offset, so this works
# across NullMoth releases that keep the shape.
#
# NVRM is a prebuilt binary (the 610/615 cores have no source in this tree), so this is a byte patch, not a rebuild.
# Re-run with --undo to restore the backed-up kext and collection.
set -euo pipefail

KEXT=/Library/Extensions/NVRM.kext
BIN="$KEXT/Contents/MacOS/NVRM"
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
NEW="$KC.guard-new"
BG=/Library/NullMoth/bootguard.sh
BGP=/Library/LaunchDaemons/com.nullmoth.bootguard.plist

[[ $(id -u) == 0 ]] || { echo "run as root" >&2; exit 1; }
[[ -f "$BIN" ]] || { echo "no $BIN" >&2; exit 1; }

rebuild_collection() {
    kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
        -B /System/Library/KernelCollections/BootKernelExtensions.kc \
        -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions -A "$NEW" -z
    python3 - "$NEW" <<'PY'
import re, subprocess, sys
from pathlib import Path
kc = Path(sys.argv[1]).read_bytes()
b = '/Library/Extensions/NVRM.kext/Contents/MacOS/NVRM'
out = subprocess.run(['/usr/bin/otool', '-l', b], capture_output=True, text=True).stdout
m = re.search(r'LC_UUID\s+cmdsize \d+\s+uuid ([0-9A-F-]{36})', out)
assert m, 'no LC_UUID in NVRM'
u = m.group(1)
assert bytes.fromhex(u.replace('-', '')) in kc, 'NVRM %s absent from the new collection' % u
print('  NVRM %s present in the new collection' % u)
PY
    mv -f "$NEW" "$KC"
}

remove_bootguard_job() {
    launchctl bootout system/com.nullmoth.bootguard 2>/dev/null || true
    rm -f "$BGP" "$BG"
    echo "removed the boot-guard LaunchDaemon (com.nullmoth.bootguard)"
}

if [[ ${1:-} == --undo ]]; then
    B=$(ls -dt /Library/NullMoth/nvrm-guard-* 2>/dev/null | head -1)
    [[ -n "$B" ]] || { echo "no backup under /Library/NullMoth/nvrm-guard-*" >&2; exit 1; }
    rm -rf "$KEXT"
    ditto "$B/NVRM.kext" "$KEXT"
    codesign --force --sign - --timestamp=none "$KEXT" >/dev/null
    rebuild_collection
    echo "restored NVRM from $B"
    exit 0
fi

BK=$(mktemp -d /Library/NullMoth/nvrm-guard-XXXXXXXX)
chmod 700 "$BK"
ditto "$KEXT" "$BK/NVRM.kext"
echo "backup $BK"

python3 - "$BIN" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
d = p.read_bytes()
orig = bytes.fromhex('803802410f93c7')      # cmpb $0x2,(%rax) ; setae %r15b
done = bytes.fromhex('4531ff0f1f4000')      # xor %r15d,%r15d ; nop4
hits = [i for i in range(len(d)) if d.startswith(orig, i)]
if not hits and any(d.startswith(done, i) for i in range(len(d))):
    print('already patched'); sys.exit(0)
assert len(hits) == 1, 'expected one guard compare, found %d' % len(hits)
off = hits[0]
print('guard compare at 0x%x' % off)
d = d[:off] + done + d[off + len(orig):]
p.write_bytes(d)
PY

codesign --force --sign - --timestamp=none "$KEXT" >/dev/null
echo "re-signed ad-hoc"
rebuild_collection
remove_bootguard_job
echo "NullMoth NVRAM boot guard removed from NVRM; reboot pending"
