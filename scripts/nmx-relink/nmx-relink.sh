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

# Step100 boot: kernelmanagerd rewrote the AuxKC 7 s after the installer's relink (a new kext, NMXBacklight, had
# appeared in /Library/Extensions) from its own list (/private/var/db/KernelExtensionManagement/AuxKC/CurrentAuxKC/
# com.apple.kcgen.instructions.plist), which never holds NMXGPU or NMXAGDC; that boot ran without NMXGPU. So the
# collection is checked again on disk after kernelmanagerd has had time to act, and built again if it was replaced.
check_kc() {
/usr/bin/python3 - "$1" <<'PY'
import re, subprocess, sys
from pathlib import Path
kc_path = Path(sys.argv[1])
if not kc_path.exists():
    print("no collection written")
    sys.exit(1)
kc = kc_path.read_bytes()
ok = True
for name in ('NMXGPU', 'NMXAccel', 'NMXAGDC', 'NMXBacklight'):
    b = f'/Library/Extensions/{name}.kext/Contents/MacOS/{name}'
    if name == 'NMXBacklight' and not Path(b).exists():
        continue
    out = subprocess.run(['/usr/bin/otool', '-l', b], capture_output=True, text=True).stdout
    m = re.search(r'LC_UUID\s+cmdsize \d+\s+uuid ([0-9A-F-]{36})', out)
    u = m.group(1) if m else None
    present = bool(u) and bytes.fromhex(u.replace('-', '')) in kc
    print(f'{sys.argv[1]}: {name} uuid={u} present={present}')
    ok = ok and present
# A binary patch keeps the UUID: byte windows of the installed NMXGPU that the collection must hold exactly once
# (lines "offset length", written by the Linux-side install; Step100c).
pr = Path('/Library/StrixGraphicsFix/nmx-relink.probes')
if pr.exists():
    g = Path('/Library/Extensions/NMXGPU.kext/Contents/MacOS/NMXGPU').read_bytes()
    for l in pr.read_text().split('\n'):
        if not l.strip():
            continue
        o, n = (int(x, 0) for x in l.split())
        c = kc.count(g[o:o + n])
        print(f'{sys.argv[1]}: NMXGPU bytes {o:#x}+{n:#x} found {c}x')
        ok = ok and c == 1
sys.exit(0 if ok else 1)
PY
}

NEW="$KC.relink"
rc=1; assert_rc=1
for attempt in 1 2 3; do
    rm -f "$NEW"
    /usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
        -B /System/Library/KernelCollections/BootKernelExtensions.kc \
        -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
        --repository /Library/Extensions -A "$NEW" -z
    rc=$?
    echo "attempt=$attempt kmutil_create_exit=$rc"
    check_kc "$NEW"; assert_rc=$?
    [[ $rc == 0 && $assert_rc == 0 ]] || break
    mv -f "$NEW" "$KC"; sync
    sleep 45
    ls -l /private/var/db/KernelExtensionManagement/AuxKC/CurrentAuxKC/ 2>/dev/null
    check_kc "$KC"; assert_rc=$?
    [[ $assert_rc == 0 ]] && break
    echo "attempt=$attempt: the collection on disk was replaced after the relink; building it again"
done

if [[ $rc == 0 && $assert_rc == 0 ]]; then
    rm -rf /Library/NullMoth/kexts/26/NMXAccel.kext
    mkdir -p /Library/NullMoth/kexts/26
    ditto /Library/Extensions/NMXAccel.kext /Library/NullMoth/kexts/26/NMXAccel.kext
    date -u >"$ROOT/nmx-relink.done"
    echo "RELINKED: the next boot loads the NMXAccel from $BK's sibling build" | tee "$ROOT/nmx-relink.status"
    # no "launchctl disable": launchd keeps that in disabled.plist and skips the next install's plist (Step78).
    /bin/rm -f "/Library/LaunchDaemons/$LABEL.plist"
    # Armed from Linux when this boot's WindowServer cannot come up (no desktop to reboot from): load the new
    # collection without hands. Before the bootout: booting out our own job kills this script (2026-11-02, the reboot
    # never ran and the flag stayed).
    if [ -f "$ROOT/nmx-relink.reboot" ]; then
        rm -f "$ROOT/nmx-relink.reboot"; sync; /sbin/reboot
    fi
    /bin/launchctl bootout "system/$LABEL" 2>/dev/null
else
    rm -f "$NEW"
    echo "RELINK_FAILED kmutil=$rc assert=$assert_rc (old collection kept)" | tee "$ROOT/nmx-relink.status"
fi
exit 0
