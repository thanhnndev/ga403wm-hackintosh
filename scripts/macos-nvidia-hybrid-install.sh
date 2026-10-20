#!/bin/bash
# Install the verified upstream payload, retaining the working NMX userland.
# No live kext replacement, WindowServer restart, EFI edit or reboot.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'administrator privileges required'; exit 1; }
PAYLOAD=${1:?extracted upstream pkgroot}; PLUGIN=${2:?hybrid plugin binary}
ACCEL=${3:?NMXAccel bundle}; PROBE=${4:?compiled IOSurface probe}
OWNER=${5:?console account}; TRACE=${6:?absolute trace directory}
HERE=$(cd "$(dirname "$0")/.." && pwd)
[[ $(sw_vers -buildVersion) == 25G241 && $(cat "$PAYLOAD/VERSION") == 2.4.2 ]]
[[ ! -e /Library/NullMoth/install.lock ]]
if nvram nullmoth-gpu-attaching >/dev/null 2>&1; then echo 'NMX attach guard exists; investigate before installing'; exit 1; fi
PY=/usr/bin/python3
"$PY" - "$ACCEL" <<'PY'
import plistlib,sys
from pathlib import Path
p=Path(sys.argv[1])/'Contents/Info.plist'
d=plistlib.loads(p.read_bytes())
assert d['IOKitPersonalities']['NVAccel']['NMXDisplayPipeEnabled'] is False
PY
BK=$(mktemp -d /Library/NullMoth/hybrid-2.4.2-XXXXXXXX)
chmod 700 "$BK"
printf '%s\n' "$BK" > "$TRACE/backup.txt"
PATHS=(Library/Extensions/NMXGPU.kext Library/Extensions/NVRM.kext Library/Extensions/NVAccel.kext Library/Extensions/NVRMEdpBL.kext
 Library/Extensions/NVRMFB.kext Library/Extensions/NVRMAGDC.kext Library/Extensions/NMXAccel.kext
 Library/GPUBundles/NVMTLDriver.bundle Library/GPUBundles/NVIDIAShared.bundle
 Library/GPUBundles/nvmtl Library/GPUBundles/nvmtl-allow.txt
 Library/NullMoth/gpu-userland Library/NullMoth/kexts
 Library/NullMoth/nvfw Users/Shared/nvfw Library/NullMoth/os-major Library/NullMoth/driver-version
 Library/NullMoth/lastgood.sh Library/NullMoth/bootguard.sh
 Library/LaunchDaemons/com.nullmoth.lastgood.plist Library/LaunchDaemons/com.nullmoth.bootguard.plist
 Library/KernelCollections/AuxiliaryKernelExtensions.kc)
for p in "${PATHS[@]}"; do
    if [[ -e /$p ]]; then mkdir -p "$BK/$(dirname "$p")"; ditto "/$p" "$BK/$p"; fi
done
nvram -x -p > "$BK/nvram-before.plist"
"$PY" - "$BK" <<'PY'
import hashlib,json,sys
from pathlib import Path
base=Path('/Library/GPUBundles/nvmtl'); saved=Path('/Library/NullMoth/gpu-userland')
hashes={str(p.relative_to(saved)):hashlib.sha256((base/p.relative_to(saved)).read_bytes()).hexdigest()
        for p in saved.rglob('*') if p.is_file()}
Path(sys.argv[1],'amd-userland.json').write_text(json.dumps(hashes,indent=2))
PY
rollback() {
    rc=$?
    if [[ $rc != 0 ]]; then
        echo "FAILED ($rc); restoring hybrid transaction from $BK"
        trap - EXIT
        set +e
        failed=0
        launchctl bootout system/com.nullmoth.lastgood 2>/dev/null
        launchctl bootout system/com.nullmoth.bootguard 2>/dev/null
        for p in "${PATHS[@]}"; do
            rm -rf "/$p" || failed=1
            if [[ -e $BK/$p ]]; then ditto "$BK/$p" "/$p" || failed=1; fi
        done
        "$PY" - "$BK/nvram-before.plist" <<'PY'
import plistlib,subprocess,sys
d=plistlib.load(open(sys.argv[1],'rb'))
prefix='7C436110-AB2A-4BBB-A880-FE41995C9F82:'
for key in ['nullmoth-remove','nullmoth-nv-starts','nullmoth-nv-ok']:
    v=d.get(key,d.get(prefix+key))
    if v is None: subprocess.run(['/usr/sbin/nvram','-d',prefix+key],capture_output=True)
    else:
        if isinstance(v,bytes): v=''.join('%%%02x'%b for b in v)
        subprocess.run(['/usr/sbin/nvram',prefix+key+'='+v],check=True)
PY
        [[ $? == 0 ]] || failed=1
        echo "restoration failure flag=$failed; recovery jobs restored on disk, not launched"
        if [[ -f $TRACE/installed-manifest.json ]]; then
            "$PY" - "$TRACE/installed-manifest.json" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]);d=json.loads(p.read_text());d['status']='rolled-back-after-failure';p.write_text(json.dumps(d,indent=2)+'\n')
PY
        fi
    fi
    exit "$rc"
}
trap rollback EXIT
# The saved overlay contained stock libraries: refresh from the known working active copies.
while IFS= read -r rel; do
    ditto "/Library/GPUBundles/nvmtl/$rel" "/Library/NullMoth/gpu-userland/$rel"
done < <("$PY" - "$BK/amd-userland.json" <<'PY'
import json,sys
print('\n'.join(json.load(open(sys.argv[1]))))
PY
)
chown -R root:wheel /Library/NullMoth/gpu-userland
chmod -R go-w /Library/NullMoth/gpu-userland
# The official collection preflight and final build must include the opted-out NMX personality.
rm -rf /Library/Extensions/NMXAccel.kext
ditto "$ACCEL" /Library/Extensions/NMXAccel.kext
chown -R root:wheel /Library/Extensions/NMXAccel.kext
chmod -R 755 /Library/Extensions/NMXAccel.kext
# The old GA403 NVIDIA-eDP companion requires NVRM 0.1 and the custom NVRMFB AUX
# caller. Upstream 2.4.2 provides neither that dependency contract nor the caller.
# OLED is AMD-owned in hybrid: park this unused companion in the full backup,
# rather than relabel an unreviewed private nv_state_t ABI as compatible.
rm -rf /Library/Extensions/NVRMEdpBL.kext
/bin/bash "$PAYLOAD/install.sh" > "$TRACE/upstream-install.log" 2>&1
# The upstream job restores only its own four kexts; restore our companion and
# NMX bundle as well so its saved AuxKC never describes different disk images.
"$PY" "$HERE/tools/890m/nvidia-hybrid-fallback.py" "$BK"
cp "$PLUGIN" /Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver
codesign -f -s - --preserve-metadata=identifier,entitlements,flags,runtime /Library/GPUBundles/NVMTLDriver.bundle
codesign --verify /Library/GPUBundles/NVMTLDriver.bundle
cat > /Library/GPUBundles/nvmtl-allow.txt <<'POLICY'
# Hybrid work profile: deny the retired stress helper before any wildcard.
-strix-headroom-hold
# WindowServer additionally requires the NVIDIA display/headless and armed gates.
!WindowServer
*
POLICY
chown root:wheel /Library/GPUBundles/nvmtl-allow.txt
chmod 644 /Library/GPUBundles/nvmtl-allow.txt
"$PY" - "$BK" "$PAYLOAD" "$TRACE" <<'PY'
import hashlib,json,plistlib,re,subprocess,sys,uuid
from pathlib import Path
bk,payload,trace=map(Path,sys.argv[1:])
for rel,h in json.loads((bk/'amd-userland.json').read_text()).items():
    for base in ['/Library/GPUBundles/nvmtl','/Library/NullMoth/gpu-userland']:
        assert hashlib.sha256((Path(base)/rel).read_bytes()).hexdigest()==h, (base,rel)
kc=Path('/Library/KernelCollections/AuxiliaryKernelExtensions.kc').read_bytes()
images={}
for name in ['NVRM','NVAccel','NVRMFB','NVRMAGDC','NMXGPU','NMXAccel']:
    binary=Path('/Library/Extensions')/(name+'.kext')/'Contents/MacOS'/name
    h=hashlib.sha256(binary.read_bytes()).hexdigest()
    u=re.search(r'UUID: ([0-9A-F-]+)',subprocess.check_output(['/usr/bin/dwarfdump','--uuid',str(binary)],text=True))[1]
    assert uuid.UUID(u).bytes in kc, name+' absent from AuxKC'
    if name.startswith('NV'):
        original=payload/('Library/NullMoth/kexts/26' if name=='NVAccel' else 'Library/Extensions')/(name+'.kext')/'Contents/MacOS'/name
        assert hashlib.sha256(original.read_bytes()).hexdigest()==h, name+' changed from upstream'
    images[name]={'sha256':h,'uuid':u}
assert images['NMXGPU']['sha256']=='0456558e65a8109f020d9945c137280378a327ccf17129f5657082316c440edb'
d=plistlib.loads(Path('/Library/Extensions/NMXAccel.kext/Contents/Info.plist').read_bytes())
assert d['IOKitPersonalities']['NVAccel']['NMXDisplayPipeEnabled'] is False
plugin=Path('/Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver')
images['NVMTLDriver']={'sha256':hashlib.sha256(plugin.read_bytes()).hexdigest()}
(trace/'installed-manifest.json').write_text(json.dumps({'version':'2.4.2','backup':str(bk),'status':'files-verified-probe-pending','images':images},indent=2)+'\n')
PY
mkdir -p "$TRACE/probe"; cp "$PROBE" "$TRACE/probe/nvmtltest"; chmod 755 "$TRACE/probe/nvmtltest" "$TRACE/probe"
sudo -u "$OWNER" env NVMTL_TEST_GPU=amd /usr/bin/perl -e 'alarm 30; exec @ARGV' "$TRACE/probe/nvmtltest" > "$TRACE/amd-iosurface-deployed.txt" 2>&1
"$PY" - "$TRACE/amd-iosurface-deployed.txt" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
assert 'RADV STRIX1' in s and s.count('CORRECT')==2 and 'WRONG' not in s, s
PY
"$PY" - "$TRACE/installed-manifest.json" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]);d=json.loads(p.read_text());d['status']='installed-reboot-pending';p.write_text(json.dumps(d,indent=2)+'\n')
PY
echo "NVIDIA 2.4.2 + hybrid policy installed; all six kext UUIDs verified in AuxKC; AMD pixels correct; reboot pending; backup $BK"
