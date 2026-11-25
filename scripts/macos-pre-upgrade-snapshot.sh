#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Snapshot of the running macOS state before a major upgrade (here 15.8.1 24H32 -> Tahoe 26), so every machine-specific
# ABI/offset/config can be compared and re-derived afterwards.
#   bash scripts/macos-pre-upgrade-snapshot.sh [label]
# Raw data (serials, MACs, UUIDs, full config.plist) stays local in ~/efi-audit/pre-upgrade-<label>-<ts>/.
# A sanitized copy for the (public) repo goes to out/pre-upgrade-<label>/.
set -uo pipefail
cd "$(dirname "$0")/.."
LABEL=${1:-$(sw_vers -buildVersion)}
TS=$(date +%Y%m%dT%H%M%S)
RAW="$HOME/efi-audit/pre-upgrade-$LABEL-$TS"
PUB="out/pre-upgrade-$LABEL"
mkdir -p "$RAW" "$PUB"

sw_vers > "$RAW/sw_vers.txt"; uname -a >> "$RAW/sw_vers.txt"
sysctl kern.bootargs kern.osversion kern.version hw.model machdep.cpu.brand_string > "$RAW/sysctl.txt" 2>&1
kmutil showloaded --list-only 2>/dev/null > "$RAW/kmutil-loaded.txt" || kextstat > "$RAW/kmutil-loaded.txt"
ioreg -l -w0 > "$RAW/ioreg-full.txt" 2>&1
for c in StrixAccelerator AMDStrixGOPFramebuffer StrixProbe StrixMetalGate StrixHeadroom StrixAmp AsusWmi IOPCIDevice; do
  ioreg -r -c "$c" -l -w0 > "$RAW/ioreg-$c.txt" 2>&1
done
system_profiler SPDisplaysDataType SPHardwareDataType SPAudioDataType SPNetworkDataType SPBluetoothDataType \
  SPUSBDataType SPPowerDataType > "$RAW/system_profiler.txt" 2>&1
pmset -g > "$RAW/pmset.txt" 2>&1; pmset -g batt >> "$RAW/pmset.txt" 2>&1
sysctl -a 2>/dev/null | /usr/bin/grep -E '^debug\.(amdcppc|asuswmi|itlmt|nvrm|nvaccel|strix)' > "$RAW/sysctl-debug.txt"
ifconfig -a > "$RAW/ifconfig.txt" 2>&1; networksetup -listallhardwareports > "$RAW/hwports.txt" 2>&1
ls -la ~/Library/LaunchAgents /Library/LaunchAgents /Library/LaunchDaemons > "$RAW/launchd-jobs.txt" 2>&1
launchctl list 2>/dev/null | /usr/bin/grep -i -E 'thanhnndev|itl|strix|nullmoth|rog|tapguard' > "$RAW/launchctl-ours.txt"

# Installed third-party kexts: versions + executable hashes (/Library/Extensions and the ESP).
{
  for k in /Library/Extensions/*.kext /Volumes/ESP/EFI/OC/Kexts/*.kext; do
    [ -d "$k" ] || continue
    v=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$k/Contents/Info.plist" 2>/dev/null)
    id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$k/Contents/Info.plist" 2>/dev/null)
    ex=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$k/Contents/Info.plist" 2>/dev/null)
    h=$([ -n "$ex" ] && [ -f "$k/Contents/MacOS/$ex" ] && shasum -a 256 "$k/Contents/MacOS/$ex" | cut -c1-16)
    echo "$k | $id | $v | ${h:-no-exec}"
  done
} > "$RAW/kexts-installed.txt"
[ -f /Volumes/ESP/EFI/OC/config.plist ] && cp /Volumes/ESP/EFI/OC/config.plist "$RAW/config.plist"
if [ -f "$RAW/config.plist" ]; then
  python3 -I - "$RAW/config.plist" > "$RAW/config-summary.txt" <<'PY'
import plistlib,sys
c=plistlib.load(open(sys.argv[1],'rb'))
print('NVRAM boot-args:', c.get('NVRAM',{}).get('Add',{}).get('7C436110-AB2A-4BBB-A880-FE41995C9F82',{}).get('boot-args'))
for e in c.get('Kernel',{}).get('Add',[]): print('Kernel/Add', 'on ' if e.get('Enabled') else 'off', e.get('BundlePath'), e.get('MinKernel',''), e.get('MaxKernel',''))
for e in c.get('Kernel',{}).get('Patch',[]): print('Kernel/Patch', 'on ' if e.get('Enabled') else 'off', e.get('Identifier'), e.get('Comment'), e.get('MinKernel',''), e.get('MaxKernel',''))
for e in c.get('ACPI',{}).get('Add',[]): print('ACPI/Add', 'on ' if e.get('Enabled') else 'off', e.get('Path'))
for p,v in c.get('DeviceProperties',{}).get('Add',{}).items(): print('DevProps', p, sorted(v.keys()))
print('SecureBootModel:', c.get('Misc',{}).get('Security',{}).get('SecureBootModel'))
print('csr-active-config:', c.get('NVRAM',{}).get('Add',{}).get('7C436110-AB2A-4BBB-A880-FE41995C9F82',{}).get('csr-active-config'))
PY
fi

# Machine-specific offsets this repo depends on (dyld shared cache, this build).
MAP=/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_x86_64h.map
for lib in CoreDisplay.framework/Versions/A/CoreDisplay SkyLight.framework/Versions/A/SkyLight \
           IOSurface.framework/Versions/A/IOSurface IOKit.framework/Versions/A/IOKit Metal.framework/Versions/A/Metal \
           QuartzCore.framework/Versions/A/QuartzCore IO80211.framework/Versions/A/IO80211; do
  /usr/bin/grep -A2 "$lib\$" "$MAP" 2>/dev/null | head -3
done > "$RAW/sharedcache-ranges.txt"
shasum -a 256 "$MAP" >> "$RAW/sharedcache-ranges.txt" 2>/dev/null
cp "$RAW/sharedcache-ranges.txt" "$PUB/"

# Sanitized public copy: drop serials, UUIDs, MACs, ROM/MLB.
san() { sed -E \
  -e 's/("(IOPlatformSerialNumber|IOPlatformUUID|serial-number|SystemSerialNumber|MLB|ROM|SystemUUID|IOMACAddress|board-serial|IOPlatformSerialNumberString|kern.uuid|USB Serial Number)" = )[^,}]*/\1<redacted>/g' \
  -e 's/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/xx:xx:xx:xx:xx:xx/g' \
  -e 's/[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/<uuid>/g' \
  -e 's/(Serial Number[^:]*: ).*/\1<redacted>/' -e 's/(Hardware UUID: ).*/\1<redacted>/' -e 's/(Provisioning UDID: ).*/\1<redacted>/' \
  -e 's/(Address: ).*/\1<redacted>/' -e 's/(ether ).*/\1<redacted>/'; }
for f in sw_vers.txt sysctl.txt kmutil-loaded.txt kexts-installed.txt config-summary.txt pmset.txt sysctl-debug.txt \
         launchctl-ours.txt hwports.txt system_profiler.txt ioreg-StrixAccelerator.txt ioreg-AMDStrixGOPFramebuffer.txt \
         ioreg-StrixProbe.txt ioreg-StrixMetalGate.txt ioreg-AsusWmi.txt; do
  [ -f "$RAW/$f" ] && san < "$RAW/$f" > "$PUB/$f"
done
gzip -c "$RAW/ioreg-full.txt" > "$RAW/ioreg-full.txt.gz" && rm -f "$RAW/ioreg-full.txt"
echo "raw (local only): $RAW"
echo "public (sanitized): $PUB"
