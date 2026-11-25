#!/bin/bash
# Add the missing IOPresentment client declaration to the scoped hybrid AGDC.
set -euo pipefail
[[ $EUID == 0 && $(sw_vers -buildVersion) == 25G241 ]]
TRACE=${1:?absolute trace directory}; PY=/usr/bin/python3
[[ $(cat /Library/NullMoth/driver-version) == 2.4.2 ]]
"$PY" - "$TRACE/agdc/NVRMAGDC.kext/Contents/Info.plist" <<'PY'
from pathlib import Path
import plistlib,sys
d=plistlib.loads(Path(sys.argv[1]).read_bytes())
assert d['CFBundleVersion']=='2.4.2'
assert d['IOKitPersonalities']['NVDAGDCLoader']['NMXForeignDisplayEnabled'] is True
PY
BK=$(mktemp -d /Library/NullMoth/agdc-client-step55-XXXXXXXX); chmod 700 "$BK"
printf '%s\n' "$BK" > "$TRACE/backup.txt"
KEXT=/Library/Extensions/NVRMAGDC.kext; KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
NEW="$KC.step55-new"
ditto "$KEXT" "$BK/NVRMAGDC.kext"; cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
rollback() {
    rc=$?
    if [[ $rc != 0 ]]; then
        trap - EXIT; set +e; failed=0
        rm -f "$NEW"
        rm -rf "$KEXT" || failed=1
        ditto "$BK/NVRMAGDC.kext" "$KEXT" || failed=1
        cp -p "$BK/AuxiliaryKernelExtensions.kc" "$KC" || failed=1
        echo "AGDC install rolled back; restoration failure flag=$failed; backup $BK"
        if [[ -f $TRACE/installed-manifest.json ]]; then
            "$PY" - "$TRACE/installed-manifest.json" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]);d=json.loads(p.read_text());d['status']='rolled-back';p.write_text(json.dumps(d,indent=2)+'\n')
PY
        fi
    fi
    exit "$rc"
}
trap rollback EXIT
rm -rf "$KEXT"; ditto "$TRACE/agdc/NVRMAGDC.kext" "$KEXT"
chown -R root:wheel "$KEXT"; chmod -R 755 "$KEXT"
kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
 -B /System/Library/KernelCollections/BootKernelExtensions.kc \
 -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions -A "$NEW" -z
"$PY" - "$NEW" "$TRACE" "$BK" <<'PY'
from pathlib import Path
import hashlib,json,re,subprocess,sys,uuid
kc,t,bk=map(Path,sys.argv[1:]);b=kc.read_bytes()
m=json.loads((t.parent/'step54/installed-manifest.json').read_text());old=m['images']['NVRMAGDC']
for name in ['NVRM','NVAccel','NVRMFB','NVRMAGDC','NMXGPU','NMXAccel']:
 p=Path('/Library/Extensions')/(name+'.kext')/'Contents/MacOS'/name
 h=hashlib.sha256(p.read_bytes()).hexdigest()
 u=re.search(r'UUID: ([0-9A-F-]+)',subprocess.check_output(['/usr/bin/dwarfdump','--uuid',str(p)],text=True))[1]
 assert uuid.UUID(u).bytes in b,name+' absent from AuxKC'
 if name!='NVRMAGDC':assert h==m['images'][name]['sha256'],name+' changed unexpectedly'
 else:assert h==hashlib.sha256((t/'agdc/NVRMAGDC.kext/Contents/MacOS/NVRMAGDC').read_bytes()).hexdigest()
 m['images'][name]={'sha256':h,'uuid':u}
plugin=Path('/Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver')
assert hashlib.sha256(plugin.read_bytes()).hexdigest()==m['images']['NVMTLDriver']['sha256']
m.update({'step':55,'backup':str(bk),'previous_agdc':old,'status':'verified-candidate-KC',
 'change':'accept exact passive AGDC0x2001 client declaration for hybrid IOPresentment'})
(t/'installed-manifest.json').write_text(json.dumps(m,indent=2)+'\n')
PY
mv -f "$NEW" "$KC"
"$PY" - "$TRACE/installed-manifest.json" <<'PY'
from pathlib import Path
import json,sys
p=Path(sys.argv[1]);d=json.loads(p.read_text());d['status']='installed-reboot-pending';p.write_text(json.dumps(d,indent=2)+'\n')
PY
echo "AGDC client declaration installed; six UUIDs in AuxKC; other five binaries/plugin retained; backup $BK; reboot pending"
