#!/bin/bash
# Scoped GA403/25G241: hand the OLED's display pipe to the accelerator on the GPU that owns the panel.
#
# The hybrid route publishes the panel as NVAccel's foreign head 4 on the NVIDIA card. CoreDisplay refuses that
# arrangement at presentation time ("Fallback GPU Display Pipe transaction submission failed", after "plane with no
# gamma"), so the pipe moves to NMXAccel, the accelerator of the AMD GPU the panel is wired to: the display GPU and
# the accelerator are then the same GPU, which is the only arrangement macOS supports long term.
#
#   NMXGPU personality:  NMXNvidiaDisplayBridge -> gone, NMXOwnsDisplay -> true  (framebuffer becomes head 0)
#   NMXAccel personality: NMXDisplayPipeEnabled -> true                        (nmxArm registers it and its pipe)
#
# Both installs replace only those two kexts; NVRM/NVAccel/NVRMFB/NVRMAGDC/NMXAccel binaries are untouched.
#   sudo scripts/macos-nmx-owns-oled-install.sh <absolute trace dir>
set -euo pipefail
[[ $EUID == 0 && $(sw_vers -buildVersion) == 25G241 ]]
TRACE=${1:?absolute trace directory}; PY=/usr/bin/python3

"$PY" - "$TRACE" <<'PY'
import plistlib, sys
from pathlib import Path
t = Path(sys.argv[1])
g = plistlib.loads((t / 'gpu/NMXGPU.kext/Contents/Info.plist').read_bytes())
a = plistlib.loads((t / 'accel/NMXAccel.kext/Contents/Info.plist').read_bytes())
p = g['IOKitPersonalities']['NMXGPUAMD']
assert p.get('NMXOwnsDisplay') is True, 'staged NMXGPU does not carry NMXOwnsDisplay'
assert 'NMXNvidiaDisplayBridge' not in p, 'staged NMXGPU still carries the NVIDIA bridge'
assert a['IOKitPersonalities']['NVAccel'].get('NMXDisplayPipeEnabled') is True, 'staged NMXAccel does not enable its pipe'
PY

BK=$(mktemp -d /Library/NullMoth/nmx-owns-oled-XXXXXXXX); chmod 700 "$BK"
printf '%s\n' "$BK" > "$TRACE/backup.txt"
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc; NEW="$KC.step58-new"
PATHS=(/Library/Extensions/NMXGPU.kext /Library/Extensions/NMXAccel.kext "$KC")
for p in "${PATHS[@]}"; do mkdir -p "$BK$(dirname "$p")"; ditto "$p" "$BK$p"; done

rollback() {
    rc=$?
    if [[ $rc != 0 ]]; then
        trap - EXIT; set +e; failed=0
        rm -f "$NEW"
        for p in "${PATHS[@]}"; do
            rm -rf "$p" || failed=1
            ditto "$BK$p" "$p" || failed=1
        done
        echo "nmx-owns install rolled back; restoration failure flag=$failed; backup $BK"
    fi
    exit "$rc"
}
trap rollback EXIT

for spec in NMXGPU:gpu NMXAccel:accel; do
    k=${spec%%:*}; dir=${spec#*:}
    rm -rf "/Library/Extensions/$k.kext"
    ditto "$TRACE/$dir/$k.kext" "/Library/Extensions/$k.kext"
    chown -R root:wheel "/Library/Extensions/$k.kext"
    chmod -R 755 "/Library/Extensions/$k.kext"
done

kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
 -B /System/Library/KernelCollections/BootKernelExtensions.kc \
 -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions -A "$NEW" -z

"$PY" - "$NEW" <<'PY'
import re, subprocess, sys
from pathlib import Path
kc = Path(sys.argv[1]).read_bytes()
def uuid(path):
    out = subprocess.run(['/usr/bin/otool', '-l', path], capture_output=True, text=True).stdout
    m = re.search(r'LC_UUID\s+cmdsize \d+\s+uuid ([0-9A-F-]{36})', out)
    return m.group(1) if m else None
for name in ('NMXGPU', 'NMXAccel'):
    b = f'/Library/Extensions/{name}.kext/Contents/MacOS/{name}'
    u = uuid(b)
    assert u, f'no LC_UUID in {b}'
    assert bytes.fromhex(u.replace('-', '')) in kc, f'{name} {u} absent from the new collection'
    print(f'  {name} {u} present in the new collection')
PY

mv -f "$NEW" "$KC"
rm -rf /Library/NullMoth/kexts/26/NMXAccel.kext
ditto /Library/Extensions/NMXAccel.kext /Library/NullMoth/kexts/26/NMXAccel.kext
trap - EXIT
echo "NMX now owns the OLED display pipe (head 0), NMXAccel pipe enabled; NVIDIA bridge property removed;"
echo "NVRM/NVAccel/NVRMFB/NVRMAGDC untouched; backup $BK; reboot pending"
