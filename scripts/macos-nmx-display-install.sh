#!/bin/bash
# Add real connector identity/HiRes to the pending hybrid batch; never restart WS.
set -euo pipefail
[[ $EUID == 0 && $(sw_vers -buildVersion) == 25G241 ]]
GPU=${1:?candidate NMXGPU bundle}; TRACE=${2:?absolute trace directory}; OWNER=${3:?console account}
ROOT=$(cd "$(dirname "$0")/.." && pwd); PY=/usr/bin/python3
HOME_DIR=$(dscl . -read "/Users/$OWNER" NFSHomeDirectory | cut -d' ' -f2-)
AGENT="$HOME_DIR/Library/LaunchAgents/dev.thanhnndev.890m-display-restore.plist"
OVERRIDE=/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-4c83/DisplayProductID-419c
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
[[ $(cat /Library/NullMoth/driver-version) == 2.4.2 ]]
if nvram nullmoth-gpu-attaching >/dev/null 2>&1; then echo 'NMX attach guard present; unchanged'; exit 1; fi
[[ $(plutil -extract IOKitPersonalities.NVAccel.NMXDisplayPipeEnabled raw /Library/Extensions/NMXAccel.kext/Contents/Info.plist) == false ]]
"$PY" - "$TRACE" "$OVERRIDE" <<'PY'
from pathlib import Path
import plistlib,sys
t=Path(sys.argv[1]);edid=(t/'connector-93.edid').read_bytes()
assert len(edid)==256 and edid[:8]==bytes.fromhex('00ffffffffffff00')
assert edid[8:12]==bytes.fromhex('4c839c41') and edid[126]==1
assert all(sum(edid[i:i+128])%256==0 for i in (0,128))
assert b'ATNA40CU05-0' in edid
old=plistlib.loads(Path(sys.argv[2]).read_bytes())
new=plistlib.loads((t/'display-override.plist').read_bytes())
assert new['DisplayVendorID']==0x4c83 and new['DisplayProductID']==0x419c
assert new['scale-resolutions']==old['scale-resolutions'] and 'IODisplayEDID' not in new
PY
BK=$(mktemp -d /Library/NullMoth/display-step52-XXXXXXXX); chmod 700 "$BK"
printf '%s\n' "$BK" > "$TRACE/backup.txt"
PATHS=(/Library/Extensions/NMXGPU.kext "$KC" "$OVERRIDE" /Library/NullMoth/lastgood.sh
 /Library/NullMoth/890m-display "$AGENT")
for p in "${PATHS[@]}"; do
    if [[ -e $p ]]; then mkdir -p "$BK$(dirname "$p")"; ditto "$p" "$BK$p"; fi
done
rollback() {
    rc=$?
    if [[ $rc != 0 ]]; then
        trap - EXIT; set +e; failed=0
        for p in "${PATHS[@]}"; do
            rm -rf "$p" || failed=1
            if [[ -e $BK$p ]]; then ditto "$BK$p" "$p" || failed=1; fi
        done
        echo "display batch rolled back; restoration failure flag=$failed; backup $BK"
    fi
    exit "$rc"
}
trap rollback EXIT
# Upstream fallback's old AuxKC includes the previous NMXGPU. Save and restore it too.
HYBRID_BK=$(sed -n 's/^HYBRID_BACKUP=//p' /Library/NullMoth/lastgood.sh)
[[ $HYBRID_BK == /Library/NullMoth/hybrid-2.4.2-* && -d $HYBRID_BK ]]
if [[ ! -d $HYBRID_BK/Library/Extensions/NMXGPU.kext ]]; then
    ditto /Library/Extensions/NMXGPU.kext "$HYBRID_BK/Library/Extensions/NMXGPU.kext"
fi
"$PY" "$ROOT/tools/890m/nvidia-hybrid-fallback.py" "$HYBRID_BK"
bash -n /Library/NullMoth/lastgood.sh
rm -rf /Library/Extensions/NMXGPU.kext
ditto "$GPU" /Library/Extensions/NMXGPU.kext
chown -R root:wheel /Library/Extensions/NMXGPU.kext; chmod -R 755 /Library/Extensions/NMXGPU.kext
cp "$TRACE/display-override.plist" "$OVERRIDE"; chown root:wheel "$OVERRIDE"; chmod 644 "$OVERRIDE"
mkdir -p /Library/NullMoth/890m-display
cp "$TRACE/display-restore" /Library/NullMoth/890m-display/display-restore
chown -R root:wheel /Library/NullMoth/890m-display; chmod -R 755 /Library/NullMoth/890m-display
mkdir -p "$HOME_DIR/Library/LaunchAgents" "$HOME_DIR/Library/Logs"
chown "$OWNER:$(id -gn "$OWNER")" "$HOME_DIR/Library/LaunchAgents" "$HOME_DIR/Library/Logs"
"$PY" - "$AGENT" "$HOME_DIR" <<'PY'
from pathlib import Path
import plistlib,sys
p=Path(sys.argv[1]);log=str(Path(sys.argv[2])/'Library/Logs/890m-display-restore.log')
p.write_bytes(plistlib.dumps({'Label':'dev.thanhnndev.890m-display-restore',
 'ProgramArguments':['/Library/NullMoth/890m-display/display-restore'],'RunAtLoad':True,
 'StandardOutPath':log,'StandardErrorPath':log}))
PY
chown "$OWNER:$(id -gn "$OWNER")" "$AGENT"; chmod 644 "$AGENT"
# RunAtLoad applies on next login; deliberately do not bootstrap into this session.
NEW="$KC.step52-new"
kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
 -B /System/Library/KernelCollections/BootKernelExtensions.kc \
 -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions -A "$NEW" -z
"$PY" - "$NEW" "$TRACE" "$BK" "$GPU" <<'PY'
from pathlib import Path
import hashlib,json,re,subprocess,sys,uuid
kc,trace,bk,gpu=map(Path,sys.argv[1:]);b=kc.read_bytes()
m=json.loads((trace.parent/'step51/installed-manifest.json').read_text());old=m['images']['NMXGPU']
for name in ['NVRM','NVAccel','NVRMFB','NVRMAGDC','NMXGPU','NMXAccel']:
 p=Path('/Library/Extensions')/(name+'.kext')/'Contents/MacOS'/name
 h=hashlib.sha256(p.read_bytes()).hexdigest()
 u=re.search(r'UUID: ([0-9A-F-]+)',subprocess.check_output(['/usr/bin/dwarfdump','--uuid',str(p)],text=True))[1]
 assert uuid.UUID(u).bytes in b,name
 if name!='NMXGPU':assert h==m['images'][name]['sha256'],name+' changed unexpectedly'
 else:assert h==hashlib.sha256((gpu/'Contents/MacOS/NMXGPU').read_bytes()).hexdigest()
 m['images'][name]={'sha256':h,'uuid':u}
m.update({'step':52,'backup':str(bk),'previous_gpu':old,'status':'installed-reboot-pending',
 'display':'Samsung ATNA40CU05-0, real connector EDID, next-login HiDPI restore'})
(trace/'installed-manifest.json').write_text(json.dumps(m,indent=2)+'\n')
PY
mv -f "$NEW" "$KC"
echo "real-EDID/HiRes GPU installed; all six UUIDs in AuxKC; OLED-only next-login helper staged; backup $BK; reboot pending"
