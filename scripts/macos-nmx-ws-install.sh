#!/bin/bash
# Root-only transactional install of a reviewed NMX display batch.
# Takes a private candidate-manifest.json and a compiled metal-iosurface probe.
# Does not restart WindowServer, clear the attach guard, or reboot.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'run with administrator privileges'; exit 1; }
MANIFEST=${1:?candidate manifest}; PROBE=${2:?metal-iosurface probe}; TRACE=$(cd "$(dirname "$MANIFEST")" && pwd)
OWNER=${3:?console account}
[[ $(sw_vers -buildVersion) == 25G241 ]] || { echo 'unreviewed OS profile'; exit 1; }
if nvram nullmoth-gpu-attaching >/dev/null 2>&1; then echo 'attach guard exists; preserve and investigate it'; exit 1; fi
python3 - "$MANIFEST" <<'PY'
import hashlib,json,sys
from pathlib import Path
m=json.loads(Path(sys.argv[1]).read_text())
for image in m['images'].values():
    assert hashlib.sha256(Path(image['path']).read_bytes()).hexdigest()==image['sha256']
PY
image_path() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["images"][sys.argv[2]]["path"])' "$MANIFEST" "$1"; }
GPU=$(image_path NMXGPU); ACCEL=$(image_path NMXAccel); PLUGIN=$(image_path NVMTLDriver)
BK="/Library/NullMoth/nmx-ws-$(date -u +%Y%m%dT%H%M%SZ)"; mkdir -p "$BK"
ditto /Library/Extensions/NMXGPU.kext "$BK/NMXGPU.kext"
ditto /Library/Extensions/NMXAccel.kext "$BK/NMXAccel.kext"
ditto /Library/GPUBundles/NVMTLDriver.bundle "$BK/NVMTLDriver.bundle"
cp -p /Library/GPUBundles/nvmtl-allow.txt "$BK/nvmtl-allow.txt"
cp -p /Library/KernelCollections/AuxiliaryKernelExtensions.kc "$BK/AuxiliaryKernelExtensions.kc"
printf '%s\n' "$BK" > "$TRACE/backup.txt"
rollback() {
    result=$?
    if [[ $result != 0 ]]; then
        echo "install failed ($result), restoring batch from $BK"
        for k in NMXGPU NMXAccel; do rm -rf "/Library/Extensions/$k.kext"; ditto "$BK/$k.kext" "/Library/Extensions/$k.kext"; done
        rm -rf /Library/GPUBundles/NVMTLDriver.bundle
        ditto "$BK/NVMTLDriver.bundle" /Library/GPUBundles/NVMTLDriver.bundle
        cp -p "$BK/nvmtl-allow.txt" /Library/GPUBundles/nvmtl-allow.txt
        cp -p "$BK/AuxiliaryKernelExtensions.kc" /Library/KernelCollections/AuxiliaryKernelExtensions.kc
    fi
    exit "$result"
}
trap rollback EXIT
cp "$PLUGIN" /Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver
codesign -f -s - --preserve-metadata=identifier,entitlements,flags,runtime /Library/GPUBundles/NVMTLDriver.bundle
codesign --verify /Library/GPUBundles/NVMTLDriver.bundle
# A fresh unprivileged process loads the deployed plugin on the still-running build15.
TESTDIR="$TRACE/probe"; mkdir -p "$TESTDIR"; cp "$PROBE" "$TESTDIR/nvmtltest"; chmod 755 "$TESTDIR/nvmtltest" "$TESTDIR"
sudo -u "$OWNER" /usr/bin/perl -e 'alarm 30; exec @ARGV' "$TESTDIR/nvmtltest" > "$TRACE/iosurface-deployed.txt" 2>&1
python3 - "$TRACE/iosurface-deployed.txt" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
assert 'RADV STRIX1' in s and s.count('CORRECT')==2 and 'WRONG' not in s, s
PY
for spec in "NMXGPU:$GPU" "NMXAccel:$ACCEL"; do
    name=${spec%%:*}; executable=${spec#*:}; bundle=$(dirname "$(dirname "$(dirname "$executable")")")
    rm -rf "/Library/Extensions/$name.kext"; ditto "$bundle" "/Library/Extensions/$name.kext"
    chown -R root:wheel "/Library/Extensions/$name.kext"; chmod -R 755 "/Library/Extensions/$name.kext"
done
python3 - /Library/GPUBundles/nvmtl-allow.txt <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);lines=p.read_text().splitlines()
# Preserve all other process policy; refuse an unexpected broad wildcard.
assert not any(x.strip()=='*' for x in lines), 'broad allow list requires reconciliation'
lines=[x for x in lines if x.strip().lstrip('!-').strip()!='WindowServer']
p.write_text('\n'.join(lines)+'\n# WindowServer additionally requires the selected GPU owned display-pipe gate.\n!WindowServer\n')
PY
chown root:wheel /Library/GPUBundles/nvmtl-allow.txt; chmod 644 /Library/GPUBundles/nvmtl-allow.txt
kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions \
    -A /Library/KernelCollections/AuxiliaryKernelExtensions.kc -z
python3 - "$MANIFEST" "$TRACE" <<'PY'
from pathlib import Path
import hashlib,json,sys,uuid
m=json.loads(Path(sys.argv[1]).read_text());kc=Path('/Library/KernelCollections/AuxiliaryKernelExtensions.kc').read_bytes()
for name in ['NMXGPU','NMXAccel']:
    p=Path('/Library/Extensions')/(name+'.kext')/'Contents/MacOS'/name
    assert hashlib.sha256(p.read_bytes()).hexdigest()==m['images'][name]['sha256']
    assert uuid.UUID(m['images'][name]['uuid']).bytes in kc
plugin=Path('/Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver')
m['deployed_plugin_sha256']=hashlib.sha256(plugin.read_bytes()).hexdigest()
m['status']='INSTALLED-AuxKC-reboot-pending'
(Path(sys.argv[2])/'installed-manifest.json').write_text(json.dumps(m,indent=2)+'\n')
PY
echo "batch installed; both new UUIDs verified in AuxKC; backup $BK; reboot pending"
