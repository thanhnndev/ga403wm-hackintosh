#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
#
# Step105: StrixSbxMap, the Sandbox mmap exception that lets Safari's WebKit GPU process map the NVMTL plugin binaries
# (WebGL on the 890M). Design: docs/890M-ROADMAP.md, "Safari WebGL: Sandbox mmap exception".
# The kext is a Lilu plugin injected by OpenCore, so it takes effect at the next reboot. Run as your user (the ESP is
# mounted user-owned at /Volumes/ESP); only the live sysctl writes ask for the admin password (osascript).
#
#   scripts/macos-install-strixsbxmap.sh            build, pin the cdhashes of the installed files, stage on the ESP
#   scripts/macos-install-strixsbxmap.sh --refresh  re-pin after a plugin/RADV rebuild: ESP Info.plist + live sysctl
#   scripts/macos-install-strixsbxmap.sh --status   pins on the ESP, live sysctl state, recent kernel log lines
#   scripts/macos-install-strixsbxmap.sh --undo     live: enable=0 now; ESP: remove the Kernel/Add entry and the kext
#   add --dry to install/--refresh/--undo to print what would change and write nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
ESP=/Volumes/ESP
OC=$ESP/EFI/OC
CFG=$OC/config.plist
DST=$OC/Kexts/StrixSbxMap.kext
KC=/System/Library/KernelCollections/BootKernelExtensions.kc
LOGDIR=$HOME/ga403-logs/strixsbxmap
TS=$(date +%Y%m%d-%H%M%S)
B=/Library/GPUBundles
# Exactly the files the WebKit GPU process maps for the 890M Metal device (symlinks resolve to these). libzstd is
# loaded by libLLVM when a shader is translated (found with tools/890m/sbx-sim.m, see the roadmap).
FILES=(
  "$B/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver"
  "$B/NVMTLDriver.bundle/Contents/MacOS/libnvmtl_translate.dylib"
  "$B/NVMTLDriver.bundle/Contents/MacOS/air-runtime/libLLVM.dylib"
  "$B/NVMTLDriver.bundle/Contents/MacOS/air-runtime/libzstd.1.dylib"
  "$B/nvmtl/libvulkan.1.4.362.dylib"
  "$B/nvmtl/libvulkan_radeon.dylib"
  "$B/nvmtl/libdrm.2.dylib"
  "$B/nvmtl/libdrm_amdgpu.1.dylib"
)
MODE=install DRY=0
for a in "$@"; do
  case "$a" in
    --refresh) MODE=refresh ;; --status) MODE=status ;; --undo) MODE=undo ;; --dry) DRY=1 ;;
    *) echo "unknown argument $a"; exit 2 ;;
  esac
done
run() { if [[ $DRY == 1 ]]; then echo "dry: $*"; else "$@"; fi; }
need_esp() { [[ -f $CFG ]] || { echo "ESP not mounted at $ESP (scripts/esp-automount.sh)"; exit 1; }; }
live() { sysctl -n debug.strixsbx.status >/dev/null 2>&1; }
as_root() {   # one admin prompt; the command goes through a file so quoting stays simple
  local f; f=$(mktemp "${TMPDIR:-/tmp}/strixsbx.XXXXXX"); printf '%s\n' "$1" > "$f"
  osascript -e "do shell script \"/bin/bash $f\" with prompt \"StrixSbxMap: $2\" with administrator privileges"
  rm -f "$f"
}

# "cdhash:/path;..." of the files as installed now. Fails if one is missing or unsigned.
pins() {
  local out="" f cd
  for f in "${FILES[@]}"; do
    [[ -f $f && ! -L $f ]] || { echo "missing or symlink: $f" >&2; return 1; }
    cd=$(codesign -dvvv "$f" 2>&1 | sed -n 's/^CDHash=//p' | head -1)
    [[ $cd =~ ^[0-9a-f]{40}$ ]] || { echo "no CDHash for $f (sign it: codesign -s - -f)" >&2; return 1; }
    out+="${out:+;}$cd:$f"
  done
  printf '%s' "$out"
}

# Sandbox build check against the KC on disk: same prologue test as the kext (test cl,4 + call fg_get_vnode).
preflight() {
  /usr/bin/python3 - "$KC" <<'EOF'
import sys, struct
sys.path.insert(0, 'tools'); sys.argv = [sys.argv[0], sys.argv[1]]
import kc
inv = {n: a for a, n in kc.syms.items()}
h, fg = inv.get('_hook_file_check_mmap'), inv.get('_fg_get_vnode')
for n in ('_hook_file_check_mmap', '_fg_get_vnode', '_ubc_cs_blob_get', '_csblob_get_cdhash'):
    if n not in inv: sys.exit('preflight: %s not in the KC symbols' % n)
b = kc.d[kc.va2off(h):kc.va2off(h) + 0x40]
test = b.find(b'\xf6\xc1\x04') >= 0
call = any(b[i] == 0xe8 and h + i + 5 + struct.unpack_from('<i', b, i + 1)[0] == fg for i in range(0x40 - 4))
if not (test and call): sys.exit('preflight: hook_file_check_mmap prologue differs (test=%s call=%s), not staging' % (test, call))
print('preflight: Sandbox hook_file_check_mmap %#x matches (test cl,4; call fg_get_vnode)' % h)
EOF
}

write_pins() {   # $1 = kext Info.plist, $2 = pins string
  local pl=$1 i=0 e cd p
  /usr/libexec/PlistBuddy -c "Delete :IOKitPersonalities:StrixSbxMap:AllowedFiles" "$pl" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :IOKitPersonalities:StrixSbxMap:AllowedFiles array" "$pl"
  IFS=';' read -ra ents <<< "$2"
  for e in "${ents[@]}"; do
    cd=${e%%:*}; p=${e#*:}
    /usr/libexec/PlistBuddy -c "Add :IOKitPersonalities:StrixSbxMap:AllowedFiles:$i dict" \
      -c "Add :IOKitPersonalities:StrixSbxMap:AllowedFiles:$i:Path string $p" \
      -c "Add :IOKitPersonalities:StrixSbxMap:AllowedFiles:$i:CDHash string $cd" "$pl"
    i=$((i + 1))
  done
  plutil -lint "$pl" >/dev/null
}

show_pins() { tr ';' '\n' <<< "$1" | sed 's/^/  /'; }

case $MODE in
status)
  if [[ -f $DST/Contents/Info.plist ]]; then
    echo "ESP kext: $DST"
    /usr/bin/python3 -c 'import plistlib,sys; d=plistlib.load(open(sys.argv[1],"rb"))["IOKitPersonalities"]["StrixSbxMap"]
for f in d.get("AllowedFiles",[]): print("  pinned", f["CDHash"], f["Path"])
print("  processes", ",".join(d.get("AllowedProcesses",[])))' "$DST/Contents/Info.plist"
  else echo "ESP kext: not staged"; fi
  [[ -f $CFG ]] && /usr/bin/python3 tools/occonfig.py -c "$CFG" get "Kernel/Add/[BundlePath=StrixSbxMap.kext]/Enabled" 2>/dev/null | sed 's/^/  OC Enabled: /' || true
  if live; then
    echo "live: $(sysctl -n debug.strixsbx.status)"
    echo "live procs: $(sysctl -n debug.strixsbx.procs)"
    sysctl -n debug.strixsbx.files | tr ';' '\n' | sed 's/^/  live pin /'
    now=$(pins 2>/dev/null || true)
    [[ $now == "$(sysctl -n debug.strixsbx.files)" ]] && echo "live pins match the files on disk" || echo "live pins differ from the files on disk: run --refresh"
  else echo "live: not loaded (reboot pending, or -strixsbxoff)"; fi
  log show --last 30m --style compact --predicate 'eventMessage CONTAINS "sbxmap"' 2>/dev/null | tail -20 || true
  ;;
install)
  need_esp
  preflight
  P=$(pins)
  echo "pins:"; show_pins "$P"
  bash scripts/build.sh StrixSbxMap >"${TMPDIR:-/tmp}/strixsbxmap-build.log" 2>&1 || { echo "build failed: ${TMPDIR:-/tmp}/strixsbxmap-build.log"; exit 1; }
  STAGE=$(mktemp -d "${TMPDIR:-/tmp}/strixsbx.XXXXXX")
  cp -R build/StrixSbxMap.kext "$STAGE/"
  write_pins "$STAGE/StrixSbxMap.kext/Contents/Info.plist" "$P"
  mkdir -p "$LOGDIR"
  if [[ -d $DST ]]; then run cp -R "$DST" "$LOGDIR/StrixSbxMap.kext.esp-$TS"; run rm -rf "$DST"; fi
  run cp -R "$STAGE/StrixSbxMap.kext" "$DST"
  if /usr/bin/python3 tools/occonfig.py -c "$CFG" get "Kernel/Add/[BundlePath=StrixSbxMap.kext]" >/dev/null 2>&1; then
    run /usr/bin/python3 tools/occonfig.py -c "$CFG" set --tag "strixsbxmap-$TS" "Kernel/Add/[BundlePath=StrixSbxMap.kext]/Enabled" true
  else
    run /usr/bin/python3 tools/occonfig.py -c "$CFG" add --tag "strixsbxmap-$TS" Kernel/Add '{"Arch": "x86_64", "BundlePath": "StrixSbxMap.kext", "Comment": "Sandbox mmap exception: WebKit GPU process may map the pinned NVMTL plugin files (docs/890M-ROADMAP.md)", "Enabled": true, "ExecutablePath": "Contents/MacOS/StrixSbxMap", "MaxKernel": "25.99.99", "MinKernel": "25.0.0", "PlistPath": "Contents/Info.plist"}'
  fi
  /usr/bin/python3 tools/occonfig.py -c "$CFG" check 2>&1 | head -3
  [[ $DRY == 1 ]] || printf '%s\n' "$P" > "$LOGDIR/pins-$TS.txt"
  rm -rf "$STAGE"
  echo "staged: $DST (loads at the next reboot; Lilu boot-arg -strixsbxoff disables it, --undo removes it)"
  ;;
refresh)
  P=$(pins)
  echo "pins:"; show_pins "$P"
  if [[ -f $DST/Contents/Info.plist ]]; then
    if [[ $DRY == 1 ]]; then echo "dry: rewrite AllowedFiles in $DST/Contents/Info.plist"
    else mkdir -p "$LOGDIR"; cp "$DST/Contents/Info.plist" "$LOGDIR/Info.plist.esp-$TS"; write_pins "$DST/Contents/Info.plist" "$P"; echo "ESP pins updated"; fi
  else echo "ESP kext not staged (run without --refresh first)"; fi
  if live; then
    if [[ $DRY == 1 ]]; then echo "dry: sysctl -w debug.strixsbx.files=..."
    else as_root "/usr/sbin/sysctl -w debug.strixsbx.files='$P'" "replace the pinned plugin files (live)"; fi
    sysctl -n debug.strixsbx.status
  else echo "not loaded now: the ESP pins apply at the next boot"; fi
  ;;
undo)
  if live; then
    if [[ $DRY == 1 ]]; then echo "dry: sysctl -w debug.strixsbx.enable=0"
    else as_root "/usr/sbin/sysctl -w debug.strixsbx.enable=0" "turn the exception off now"; fi
  fi
  if [[ -f $CFG ]]; then
    if /usr/bin/python3 tools/occonfig.py -c "$CFG" get "Kernel/Add/[BundlePath=StrixSbxMap.kext]" >/dev/null 2>&1; then
      run /usr/bin/python3 tools/occonfig.py -c "$CFG" del --tag "strixsbxmap-undo-$TS" "Kernel/Add/[BundlePath=StrixSbxMap.kext]"
    fi
    if [[ -d $DST ]]; then mkdir -p "$LOGDIR"; run cp -R "$DST" "$LOGDIR/StrixSbxMap.kext.undo-$TS"; run rm -rf "$DST"; fi
    /usr/bin/python3 tools/occonfig.py -c "$CFG" check 2>&1 | head -3
    echo "removed from the ESP (backup in $LOGDIR); gone after the next reboot"
  else echo "ESP not mounted: OC entry left as is (mount it and rerun --undo)"; fi
  ;;
esac
