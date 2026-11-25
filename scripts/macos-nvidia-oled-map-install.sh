#!/bin/bash
# Scoped GA403/25G241: publish the foreign OLED in AGDC, with actual DRM timing and rendering owner.
set -euo pipefail
[[ $EUID == 0 && $(sw_vers -buildVersion) == 25G241 ]]
TRACE=${1:?absolute trace directory}; PY=/usr/bin/python3
[[ $(cat /Library/NullMoth/driver-version) == 2.4.2 ]]
[[ $(plutil -extract IOKitPersonalities.NVAccel.NMXDisplayPipeEnabled raw /Library/Extensions/NMXAccel.kext/Contents/Info.plist) == false ]]
if nvram nullmoth-gpu-attaching >/dev/null 2>&1; then echo 'attach guard present; unchanged'; exit 1; fi
"$PY" - "$TRACE" <<'PY'
import plistlib,sys
from pathlib import Path
t=Path(sys.argv[1])
g=plistlib.loads((t/'gpu/NMXGPU.kext/Contents/Info.plist').read_bytes())
a=plistlib.loads((t/'accel/NVAccel.kext/Contents/Info.plist').read_bytes())
assert g['IOKitPersonalities']['NMXGPUAMD']['NMXNvidiaDisplayBridge'] is True
assert a['IOKitPersonalities']['NVAccel']['NMXForeignDisplayEnabled'] is True
assert a['CFBundleVersion']=='2.4.2'
c=plistlib.loads((t/'agdc/NVRMAGDC.kext/Contents/Info.plist').read_bytes())
assert c['CFBundleVersion']=='2.4.2'
assert c['IOKitPersonalities']['NVDAGDCLoader']['NMXForeignDisplayEnabled'] is True
PY
BK=$(mktemp -d /Library/NullMoth/oled-map-step54-XXXXXXXX); chmod 700 "$BK"
printf '%s\n' "$BK" > "$TRACE/backup.txt"
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc; NEW="$KC.step54-new"
PATHS=(/Library/Extensions/NMXGPU.kext /Library/Extensions/NVAccel.kext /Library/Extensions/NVRMAGDC.kext /Library/NullMoth/kexts/26 "$KC")
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
        echo "bridge install rolled back; restoration failure flag=$failed; backup $BK"
    fi
    exit "$rc"
}
trap rollback EXIT
for spec in NMXGPU:gpu NVAccel:accel NVRMAGDC:agdc; do
    k=${spec%%:*}; dir=${spec#*:}
    rm -rf "/Library/Extensions/$k.kext"
    ditto "$TRACE/$dir/$k.kext" "/Library/Extensions/$k.kext"
    chown -R root:wheel "/Library/Extensions/$k.kext"; chmod -R 755 "/Library/Extensions/$k.kext"
done
rm -rf /Library/NullMoth/kexts/26/NVAccel.kext
ditto /Library/Extensions/NVAccel.kext /Library/Extensions/NVRMAGDC.kext /Library/NullMoth/kexts/26/NVAccel.kext
(cd /Library/NullMoth/kexts/26 && find NVAccel.kext -type f -exec shasum -a 256 '{}' \;) > /Library/NullMoth/kexts/26/SHA256SUMS
chown -R root:wheel /Library/NullMoth/kexts/26; chmod -R go-w /Library/NullMoth/kexts/26
kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
 -B /System/Library/KernelCollections/BootKernelExtensions.kc \
 -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions -A "$NEW" -z
"$PY" - "$NEW" "$TRACE" "$BK" <<'PY'
from pathlib import Path
import hashlib,json,re,subprocess,sys,uuid
kc,t,bk=map(Path,sys.argv[1:]);b=kc.read_bytes()
m=json.loads((t.parent/'step53/installed-manifest.json').read_text())
previous={k:m['images'][k] for k in ['NMXGPU','NVAccel','NVRMAGDC']}
for name in ['NVRM','NVAccel','NVRMFB','NVRMAGDC','NMXGPU','NMXAccel']:
 p=Path('/Library/Extensions')/(name+'.kext')/'Contents/MacOS'/name
 h=hashlib.sha256(p.read_bytes()).hexdigest()
 u=re.search(r'UUID: ([0-9A-F-]+)',subprocess.check_output(['/usr/bin/dwarfdump','--uuid',str(p)],text=True))[1]
 assert uuid.UUID(u).bytes in b,name+' absent from AuxKC'
 if name not in previous: assert h==m['images'][name]['sha256'],name+' unexpectedly changed'
 else:
  candidate=t/({'NMXGPU':'gpu','NVAccel':'accel','NVRMAGDC':'agdc'}[name])/(name+'.kext')/'Contents/MacOS'/name
  assert hashlib.sha256(candidate.read_bytes()).hexdigest()==h
 m['images'][name]={'sha256':h,'uuid':u}
cache=Path('/Library/NullMoth/kexts/26/NVAccel.kext/Contents/MacOS/NVAccel')
assert hashlib.sha256(cache.read_bytes()).hexdigest()==m['images']['NVAccel']['sha256']
m.update({'step':54,'backup':str(bk),'previous_images':previous,'status':'verified-candidate-KC',
 'presentation':'AGDC slot1 -> NVAccel pipe1 -> physical OLED head4; timing from DRM'})
(t/'installed-manifest.json').write_text(json.dumps(m,indent=2)+'\n')
PY
mv -f "$NEW" "$KC"
"$PY" - "$TRACE/installed-manifest.json" <<'PY'
from pathlib import Path
import json,sys
p=Path(sys.argv[1]);m=json.loads(p.read_text());m['status']='installed-reboot-pending';p.write_text(json.dumps(m,indent=2)+'\n')
PY
echo "foreign OLED AGDC map installed, three changed and three retained UUIDs in AuxKC; live HDMI/session untouched; backup $BK; reboot pending"
