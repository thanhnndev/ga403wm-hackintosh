#!/bin/bash
# One-shot, run as root by com.itlmt7925.nmx-relink at the first boot after the Linux-side install.
# Rebuilds the auxiliary kernel collection so the NMXAccel that is now in /Library/Extensions is the copy that loads
# on the NEXT boot. This boot keeps running the previously collected binary; there is no way to change a loaded kext.
set -u
LABEL=com.itlmt7925.nmx-relink
ROOT=/Library/StrixGraphicsFix
mkdir -p "$ROOT"
exec >>"$ROOT/nmx-relink.log" 2>&1
set -x
cd /
[ -f "$ROOT/nmx-relink.done" ] && { echo already-done; exit 0; }
sleep 20

KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
BK=/Library/NullMoth/nmx-step60-$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$BK" && cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
echo "backup=$BK"

NEW="$KC.relink"
rm -f "$NEW"
/usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
    --repository /Library/Extensions -A "$NEW" -z
rc=$?
echo "kmutil_create_exit=$rc"

/usr/bin/python3 - "$NEW" <<'PY'
import re, subprocess, sys
from pathlib import Path
kc_path = Path(sys.argv[1])
if not kc_path.exists():
    print("no collection written")
    sys.exit(1)
kc = kc_path.read_bytes()
ok = True
for name in ('NMXGPU', 'NMXAccel', 'NMXAGDC'):
    b = f'/Library/Extensions/{name}.kext/Contents/MacOS/{name}'
    out = subprocess.run(['/usr/bin/otool', '-l', b], capture_output=True, text=True).stdout
    m = re.search(r'LC_UUID\s+cmdsize \d+\s+uuid ([0-9A-F-]{36})', out)
    u = m.group(1) if m else None
    present = bool(u) and bytes.fromhex(u.replace('-', '')) in kc
    print(f'{name} uuid={u} present_in_new_collection={present}')
    ok = ok and present
sys.exit(0 if ok else 1)
PY
assert_rc=$?

if [[ $rc == 0 && $assert_rc == 0 ]]; then
    mv -f "$NEW" "$KC"
    rm -rf /Library/NullMoth/kexts/26/NMXAccel.kext
    mkdir -p /Library/NullMoth/kexts/26
    ditto /Library/Extensions/NMXAccel.kext /Library/NullMoth/kexts/26/NMXAccel.kext
    date -u >"$ROOT/nmx-relink.done"
    echo "RELINKED: the next boot loads the NMXAccel from $BK's sibling build" | tee "$ROOT/nmx-relink.status"
    /bin/launchctl bootout "system/$LABEL" 2>/dev/null
    /bin/launchctl disable "system/$LABEL" 2>/dev/null
    /bin/rm -f "/Library/LaunchDaemons/$LABEL.plist"
else
    rm -f "$NEW"
    echo "RELINK_FAILED kmutil=$rc assert=$assert_rc (old collection kept)" | tee "$ROOT/nmx-relink.status"
fi
exit 0
