#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Backup / install / restore helper for the first load of itlmt7925Native (docs/TEST-NATIVE-WIFI.md). macOS only.
#   scripts/native-wifi-test.sh backup            copy ESP:/EFI to ~/itlmt-backup/EFI-<time> (+ tar.gz) and print the path
#   scripts/native-wifi-test.sh install <kext> [--stage a|b] [--exclusive]
#                                                 backup first, then copy the kext to OC/Kexts and add the Kernel/Add entry + boot-args.
#                                                 --stage a (default) = controller only (itlmt_native=1); b = + interface (itlmt_native_if=1).
#                                                 --exclusive = switch the old Wi-Fi off for this test: removes itlmt_m2/itlmt_m3/itlmt_fast
#                                                 Core remains the chip backend. With itlmt_native_dp=1 it scans/joins for native,
#                                                 suppresses legacy Ethernet and legacy user clients; otherwise it only loads firmware.
#                                                 restore undoes the EFI/boot-args changes.
#   scripts/native-wifi-test.sh restore [dir]     put the newest (or given) backup back, replacing ESP:/EFI
#   scripts/native-wifi-test.sh logs              collect kextstat/ioreg/log of the last boot into ~/itlmt-backup/logs-<time>
# ESP is taken from /Volumes/ESP (scripts/esp-automount.sh) or from ESP=/path.
set -eu
ESP=${ESP:-/Volumes/ESP}
BK=$HOME/itlmt-backup
TS=$(date +%Y%m%d-%H%M%S)
[ -d "$ESP/EFI/OC" ] || { echo "no $ESP/EFI/OC: mount the ESP first (scripts/esp-automount.sh or diskutil mount)"; exit 1; }
mkdir -p "$BK"

backup() {
  d=$BK/EFI-$TS
  cp -Rp "$ESP/EFI" "$d"
  tar -czf "$d.tar.gz" -C "$BK" "EFI-$TS"
  # NVRAM boot-args as well: it overrides config.plist when set
  nvram boot-args > "$d.nvram-boot-args.txt" 2>&1 || true
  echo "$d"
}

case "${1:-}" in
backup) backup;;
install)
  k=${2:?path to itlmt7925Native.kext}
  shift 2
  stage=a; excl=0
  while [ $# -gt 0 ]; do
    case "$1" in
    --stage) stage=${2:?--stage a|b}; shift 2;;
    --exclusive) excl=1; shift;;
    *) echo "unknown option $1"; exit 2;;
    esac
  done
  case "$stage" in a|b) ;; *) echo "--stage must be a or b"; exit 2;; esac
  [ -f "$k/Contents/Info.plist" ] || { echo "not a kext: $k"; exit 1; }
  d=$(backup); echo "backup: $d"
  # The core kext must be a library kext (OSBundleCompatibleVersion) or the native kext fails with 0xdc00800e. Patch the ESP copy
  # in place (keeps the injected Wi-Fi credentials; the binary is unchanged).
  /usr/bin/python3 -I - "$ESP/EFI/OC/Kexts/itlmt7925.kext/Contents/Info.plist" <<'PY'
import plistlib, sys
p = sys.argv[1]
c = plistlib.load(open(p, 'rb'))
if 'OSBundleCompatibleVersion' not in c:
    c['OSBundleCompatibleVersion'] = c['CFBundleVersion']
    plistlib.dump(c, open(p, 'wb'))
    print('core Info.plist: added OSBundleCompatibleVersion', c['CFBundleVersion'])
PY
  rm -rf "$ESP/EFI/OC/Kexts/itlmt7925Native.kext"
  cp -Rp "$k" "$ESP/EFI/OC/Kexts/"
  /usr/bin/python3 -I - "$ESP/EFI/OC/config.plist" "$stage" "$excl" <<'PY'
import plistlib, sys
p, stage, excl = sys.argv[1], sys.argv[2], sys.argv[3] == '1'
c = plistlib.load(open(p, 'rb'))
add = c['Kernel']['Add']
names = [a['BundlePath'] for a in add]
if 'itlmt7925Native.kext' not in names:
    core = next(i for i, a in enumerate(add) if a['BundlePath'] == 'itlmt7925.kext')
    e = {'Arch': 'Any', 'BundlePath': 'itlmt7925Native.kext', 'Comment': 'native Wi-Fi test', 'Enabled': True,
         'ExecutablePath': 'Contents/MacOS/itlmt7925Native', 'MaxKernel': '', 'MinKernel': '', 'PlistPath': 'Contents/Info.plist'}
    add.insert(core + 1, e)       # must come after the core kext it depends on
a = c['NVRAM']['Add']['7C436110-AB2A-4BBB-A880-FE41995C9F82']
toks = a.get('boot-args', '').split()
want = ['itlmt_native=1'] + (['itlmt_native_if=1'] if stage == 'b' else [])
drop = ['itlmt_native_if=1'] if stage == 'a' else []
if excl:
    drop += [t for t in toks if t.split('=')[0] in ('itlmt_m2', 'itlmt_m3', 'itlmt_fast')]
toks = [t for t in toks if t not in drop] + [t for t in want if t not in toks]
a['boot-args'] = ' '.join(toks)
plistlib.dump(c, open(p, 'wb'))
print('config.plist: Add entry after itlmt7925.kext, boot-args =', a['boot-args'])
PY
  echo "NVRAM boot-args (wins over config.plist if set; clear it or reset NVRAM from the picker if it differs):"
  nvram boot-args 2>&1 || true
  echo "done. Reboot. To go back: scripts/native-wifi-test.sh restore";;
restore)
  d=${2:-$(ls -d "$BK"/EFI-* 2>/dev/null | grep -v '\.' | tail -1)}
  [ -d "$d" ] || { echo "no backup directory"; exit 1; }
  rm -rf "$ESP/EFI"; cp -Rp "$d" "$ESP/EFI"
  /usr/bin/python3 -I - "$d.nvram-boot-args.txt" <<'PY'
import os, pathlib, shlex, subprocess, sys
p = pathlib.Path(sys.argv[1])
if not p.exists():
    print('No boot-args snapshot; EFI restored, NVRAM unchanged. Check NVRAM before reboot.')
    sys.exit(0)
snapshot = p.read_text().strip()
if snapshot.startswith('boot-args\t'):
    args = snapshot.split('\t', 1)[1]
    command = ['/usr/sbin/nvram', 'boot-args=' + args]
    current = subprocess.run(['/usr/sbin/nvram', 'boot-args'], capture_output=True, text=True)
    if current.returncode == 0 and current.stdout.strip() == snapshot:
        print('NVRAM boot-args already matches backup')
        sys.exit(0)
elif snapshot.startswith('nvram:') and 'not found' in snapshot:
    current = subprocess.run(['/usr/sbin/nvram', 'boot-args'], capture_output=True)
    if current.returncode != 0:
        print('Backup and current NVRAM both have no boot-args')
        sys.exit(0)
    command = ['/usr/sbin/nvram', '-d', 'boot-args']
else:
    sys.exit('Unrecognised boot-args snapshot; EFI restored, NVRAM unchanged. Check before reboot.')
if os.geteuid() == 0:
    subprocess.run(command, check=True)
else:
    shell = ' '.join(shlex.quote(x) for x in command)
    source = 'do shell script "' + shell.replace('\\', '\\\\').replace('"', '\\"') + '" with administrator privileges'
    subprocess.run(['osascript', '-e', source], check=True)
print('NVRAM boot-args restored from backup')
PY
  echo "restored $d -> $ESP/EFI and its saved boot-args; reboot.";;
logs)
  o=$BK/logs-$TS; mkdir -p "$o"
  kextstat 2>/dev/null | grep -i itlmt > "$o/kextstat.txt" || true
  ioreg -l -w0 | grep -i -B2 -A12 'itlmt7925' > "$o/ioreg.txt" || true
  log show --last boot --predicate 'eventMessage CONTAINS[c] "itlmt" OR process == "kernel"' --style compact > "$o/log.txt" 2>&1 || true
  dmesg | grep -i itlmt > "$o/dmesg.txt" || true
  ioreg -l -w0 | grep -E 'itlmt_native_|itlmt_datapath_|itlmt_radio_|itlmt_tx_|itlmt_rx_|itlmt_ioctl_|IOInterfaceNamePrefix|IOInterfaceUnit|IO80211InterfaceRole' > "$o/native-trace.txt" || true
  ioreg -r -c itlmt7925WifiInterface -l -w0 > "$o/native-interface-full.txt" 2>&1 || true
  ioreg -r -c itlmt7925Wifi -d1 -l -w0 | grep -v -i 'mac' > "$o/native-controller.txt" 2>&1 || true
  nvram boot-args > "$o/boot-args.txt" || true
  sysctl kern.bootargs > "$o/kern-bootargs.txt" || true
  ifconfig en9 > "$o/ifconfig-en9.txt" 2>&1 || true
  ioreg -r -c itlmt7925 -l -w0 > "$o/core-full-private.txt" 2>&1 || true
  /usr/bin/python3 -I - "$o" <<'PY'
import pathlib, plistlib, subprocess
p = pathlib.Path(__import__('sys').argv[1])
r = subprocess.run(['nvram', '-xp'], capture_output=True)
try:
    variables = plistlib.loads(r.stdout)
    for key, value in variables.items():
        leaf = key.split(':')[-1]
        if leaf in ('itlmt-native-trace', 'itlmt-native-last') or leaf.startswith('AAPL,PanicInfo'):
            raw = value if isinstance(value, bytes) else str(value).encode()
            (p / (leaf.replace(',', '-') + '.bin')).write_bytes(raw)
            if leaf == 'itlmt-native-trace':
                (p / 'native-nvram-trace.txt').write_text(raw.decode('utf-8', errors='replace'))
            elif leaf == 'itlmt-native-last':
                (p / 'native-nvram-last.txt').write_text(raw.decode('utf-8', errors='replace'))
except Exception as error:
    (p / 'nvram-collection-error.txt').write_text(str(error))
PY
  ifconfig -a | grep -E '^[a-z]+[0-9]+:' > "$o/interfaces.txt"
  # userland side of the same boot: who binds the interface and what they say about it (may hold MACs: check before sharing)
  networksetup -listallhardwareports > "$o/hardwareports.txt" 2>&1 || true
  system_profiler SPAirPortDataType > "$o/airport-profile.txt" 2>&1 || true
  log show --last boot --style compact --predicate 'process == "airportd" OR process == "wifid" OR process == "wifivelocityd" OR process == "WiFiAgent" OR process == "configd" OR process == "WirelessRadioManagerd" OR subsystem CONTAINS[c] "wifi" OR subsystem CONTAINS[c] "corewlan"' > "$o/userland-wifi.log" 2>&1 || true
  echo "$o (check for SSIDs/MACs before sharing)";;
*) echo "usage: $0 backup | install <kext> [--stage a|b] [--exclusive] | restore [dir] | logs"; exit 2;;
esac
