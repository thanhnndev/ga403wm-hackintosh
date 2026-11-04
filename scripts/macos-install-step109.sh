#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step109 (macOS, run as root): S0 (Modern Standby) system sleep through Apple's own deep idle path.
# - efi/OC/ACPI/SSDT-S0IDLE.aml (acpi/SSDT-S0IDLE.dsl): \_SB.LPS0 = 1 on Darwin, so AppleACPIPlatform keeps the S0
#   sleep state (no _S3 on this firmware) and sleeps through acpi_idle_kernel.
# - StrixS0ix.kext 0.1.0: pmCPUHalt for that path (MWAITX idle until a wake event), PEP Modern Standby _DSM 3/7/5, 6/8/4.
# Both load at the next boot. The ESP must be mounted at /Volumes/ESP (EFI/OC/config.plist).
#
#   sudo scripts/macos-install-step109.sh
#   sudo scripts/macos-install-step109.sh --undo   # kext out, SSDT entry disabled, relink
# Without undo: boot-arg -s0ixoff keeps the kext inert and blocks system sleep (no hang); -s0ixnodsm skips the _DSMs;
# s0ix_maxsec=N wakes after N s without a wake event (default 300, 0 = no limit).
# If the kext is missing while the SSDT is on, system sleep enters S0 with the stock halt and never wakes: the
# script checks the kext is in the new collection before it touches the ESP.
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
K=/Library/Extensions/StrixS0ix.kext
G=/Library/Extensions/NMXGPU.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
OC=/Volumes/ESP/EFI/OC
SSDT=SSDT-S0IDLE.aml
mkdir -p /Library/NullMoth
exec > >(tee -a "/Library/NullMoth/step109-$TS.log") 2>&1
[[ -f $OC/config.plist ]] || { echo "ESP not mounted at /Volumes/ESP (no $OC/config.plist)"; exit 1; }

config() {  # $1 = on|off: add/enable or disable the ACPI Add entry for the SSDT
    /usr/bin/python3 -I - "$OC/config.plist" "$SSDT" "$1" <<'EOF'
import plistlib, sys
path, name, mode = sys.argv[1:]
with open(path, 'rb') as f:
    c = plistlib.load(f)
add = c['ACPI']['Add']
hit = [e for e in add if e.get('Path') == name]
if mode == 'on':
    if hit:
        hit[0]['Enabled'] = True
    else:
        add.append({'Comment': name + ': \\_SB.LPS0 = 1 on Darwin, S0 deep idle sleep (StrixS0ix, Step109)',
                    'Enabled': True, 'Path': name})
else:
    for e in hit:
        e['Enabled'] = False
with open(path, 'wb') as f:
    plistlib.dump(c, f)
print('config.plist ACPI Add', name, 'enabled' if mode == 'on' else 'disabled')
EOF
}

relink() {
    local new=$KC.step109
    rm -f "$new"
    /usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
        -B /System/Library/KernelCollections/BootKernelExtensions.kc \
        -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
        --repository /Library/Extensions -A "$new" -z
    # the NMXGPU caves must survive the relink
    /usr/bin/python3 -I "$HERE/nmx-mmfix/step97b_patch.py" --check-kc "$new" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-flip/step99_patch.py" --check-kc "$new" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-irqfix/patch_irqfix.py" --check-kc "$new" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-mmfix2/step100_mm_patch.py" --check-kc "$new" "$G/Contents/MacOS/NMXGPU"
    /usr/bin/python3 -I "$HERE/nmx-s0ix/patch_s0ix.py" --check-kc "$new" "$G/Contents/MacOS/NMXGPU"
    grep -qa 'sleep/wake interest' "$new" || { echo "NMXBacklight 0.3.0 is not in the new collection"; exit 1; }
    if [[ ${1:-} == with-s0ix ]]; then
        grep -qa 'StrixS0ix: pmCPUHalt registered' "$new" || { echo "StrixS0ix is not in the new collection"; exit 1; }
    fi
    mv -f "$new" "$KC"; sync
}

if [[ ${1:-} == --undo ]]; then
    cp -p "$OC/config.plist" "/Library/NullMoth/config.plist.step109-undo-$TS"
    config off
    rm -rf "$K"
    relink
    echo "StrixS0ix removed, SSDT-S0IDLE disabled; reboot to apply"
    exit 0
fi

B=$REPO/build/StrixS0ix.kext
grep -qa 'StrixS0ix: pmCPUHalt registered' "$B/Contents/MacOS/StrixS0ix" || { echo "$B missing: scripts/build.sh StrixS0ix"; exit 1; }
[[ -f $REPO/efi/OC/ACPI/$SSDT ]] || { echo "efi/OC/ACPI/$SSDT missing: tools/mk_ssdt_s0idle.py"; exit 1; }
BK=/Library/NullMoth/step109-bk-$TS
mkdir -p "$BK"
cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
cp -p "$OC/config.plist" "$BK/config.plist"
cp -p "$OC/config.plist" "$OC/config.plist.pre-step109"
[[ -d $K ]] && ditto "$K" "$BK/StrixS0ix.kext"
echo "backup $BK (and $OC/config.plist.pre-step109)"
rm -rf "$K"; ditto "$B" "$K"; chown -R 0:0 "$K"; chmod -R go-w "$K"
echo "StrixS0ix $(shasum -a 256 "$K/Contents/MacOS/StrixS0ix" | cut -c1-16) installed"
relink with-s0ix
cp "$REPO/efi/OC/ACPI/$SSDT" "$OC/ACPI/$SSDT"
config on
/usr/bin/plutil -lint "$OC/config.plist"
# kernelmanagerd once replaced a fresh collection with its own list (Step100b): check again after it had time to act
/usr/bin/perl -e 'select(undef, undef, undef, 45)'
grep -qa 'StrixS0ix: pmCPUHalt registered' "$KC" || { echo "AuxKC lost StrixS0ix after 45 s: run this script again before rebooting"; exit 1; }
grep -qa 'sleep/wake interest' "$KC" || { echo "AuxKC lost NMXBacklight after 45 s: run this script again before rebooting"; exit 1; }
echo "Step109 installed: StrixS0ix in AuxKC, $SSDT on the ESP; reboot to load both"
