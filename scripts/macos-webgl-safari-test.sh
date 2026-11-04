#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
#
# Safari / WKWebView WebGL on the 890M: test for StrixSbxMap (Step105). Plan: docs/890M-ROADMAP.md,
# "Safari WebGL: Sandbox mmap exception". Each run does ONE bounded GPU job per probe (no loops on the desktop).
#
#   scripts/macos-webgl-safari-test.sh sim [--safari]   before the reboot: tools/890m/sbx-sim.m applies the WebKit GPU
#                                                       process profile (+ exactly the file-map-executable pins staged on
#                                                       the ESP, i.e. what the kext will grant) in-process and runs one
#                                                       Metal render job. Shows whether the plugin itself still needs
#                                                       anything else from the sandbox. --safari = the cryptex profile.
#   scripts/macos-webgl-safari-test.sh live [--ab]      after the reboot: kext state, build/webgl-probe (WKWebView,
#                                                       UseGPUProcessForWebGLEnabled on, strings unmasked), counters,
#                                                       sandbox denies, verdict. --ab also runs with the exception off
#                                                       (sysctl debug.strixsbx.enable=0, admin prompt) and back on.
# Output: ~/ga403-logs/webgl-safari-<time>/
set -uo pipefail
cd "$(dirname "$0")/.."
MODE=${1:-}; shift || true
SAFARI=0 AB=0
for a in "$@"; do case "$a" in --safari) SAFARI=1 ;; --ab) AB=1 ;; *) echo "unknown argument $a"; exit 2 ;; esac; done
OUT=$HOME/ga403-logs/webgl-safari-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT" build
ESPKEXT=/Volumes/ESP/EFI/OC/Kexts/StrixSbxMap.kext/Contents/Info.plist
PROF_SYS=/System/Library/Frameworks/WebKit.framework/Versions/A/Resources/com.apple.WebKit.GPUProcess.sb
PROF_SAF=/System/Volumes/Preboot/Cryptexes/App/System/Library/StagedFrameworks/Safari/WebKit.framework/Versions/A/Resources/com.apple.WebKit.GPUProcess.sb
bounded() { perl -e 'alarm shift; exec @ARGV' "$@"; }   # no timeout(1) on macOS
denies() {  # $1 = start time, $2 = process name
  /usr/bin/log show --start "$1" --predicate "sender == \"Sandbox\" AND eventMessage CONTAINS \"$2\" AND eventMessage CONTAINS \"deny\"" 2>/dev/null |
    sed -E 's/.*Sandbox: //; s/\([0-9]+\)//' | grep -v '^Timestamp' | sort | uniq -c | sort -rn
}

case $MODE in
sim)
  [[ -f build/sbx-sim && build/sbx-sim -nt tools/890m/sbx-sim.m ]] ||
    clang -fobjc-arc -O1 -framework Foundation -framework Metal -o build/sbx-sim tools/890m/sbx-sim.m || exit 1
  [[ -f $ESPKEXT ]] || { echo "StrixSbxMap not staged on the ESP (scripts/macos-install-strixsbxmap.sh)"; exit 1; }
  BASE=$PROF_SYS; [[ $SAFARI == 1 ]] && BASE=$PROF_SAF
  { cat "$BASE"; echo ';; sbx-sim: exactly the file-map-executable pins StrixSbxMap grants'
    /usr/bin/python3 -c 'import plistlib,sys
for f in plistlib.load(open(sys.argv[1],"rb"))["IOKitPersonalities"]["StrixSbxMap"]["AllowedFiles"]:
    print("(allow file-map-executable (literal \"%s\"))" % f["Path"])' "$ESPKEXT"; } > "$OUT/profile.sb"
  TD=$(realpath "$(getconf DARWIN_USER_TEMP_DIR)"); CD=$(realpath "$(getconf DARWIN_USER_CACHE_DIR)")
  rm -f "$TD/nvmtl.log"
  T0=$(date "+%Y-%m-%d %H:%M:%S")
  # ENABLE_SANDBOX_MESSAGE_FILTER=NO: the IOKit message filter needs WebKit's entitlement; the NMDR selectors (0, 1, 2)
  # are on its allowed list anyway.
  NVMTL_DRM_XNU_TRACE=1 bounded 25 build/sbx-sim "$OUT/profile.sb" CPU=x86_64 ENABLE_SANDBOX_MESSAGE_FILTER=NO \
    WEBKIT2_FRAMEWORK_DIR=/System/Library/Frameworks/WebKit.framework DARWIN_USER_CACHE_DIR="$CD" DARWIN_USER_TEMP_DIR="$TD" \
    HOME_DIR="$HOME" HOME_LIBRARY_PREFERENCES_DIR="$HOME/Library/Preferences" > "$OUT/sim.out" 2>&1
  RC=$?
  cp "$TD/nvmtl.log" "$OUT/nvmtl.log" 2>/dev/null
  denies "$T0" sbx-sim > "$OUT/denies.txt"
  grep -E '^(sandbox|device|library|pipeline|job)' "$OUT/sim.out"
  grep -E 'drm-xnu: sandbox|vk: UP|zero physical|not rebound|nvk-reason|FAILED' "$OUT/nvmtl.log" 2>/dev/null | cut -c1-200 | head -8
  echo "sandbox denies (count, op):"; grep -v -E 'diagnosticd|lsd\.|/build|/develop' "$OUT/denies.txt" | head -15
  [[ $RC == 0 ]] && echo "SIM PASS: the plugin renders inside the WebKit GPU profile with only the pinned mmaps" ||
    echo "SIM FAIL (exit $RC): see the denies above; the plugin still needs more than the mmap exception"
  echo "logs: $OUT"; exit $RC
  ;;
live)
  [[ -f build/webgl-probe && build/webgl-probe -nt tools/890m/webgl-probe.swift ]] ||
    swiftc -O -o build/webgl-probe tools/890m/webgl-probe.swift || exit 1
  if ! sysctl -n debug.strixsbx.status >/dev/null 2>&1; then echo "StrixSbxMap not loaded (reboot pending? -strixsbxoff?)"; fi
  probe() {  # $1 = label
    local t0 s0 s1; t0=$(date "+%Y-%m-%d %H:%M:%S"); s0=$(sysctl -n debug.strixsbx.status 2>/dev/null)
    bounded 40 build/webgl-probe --gpu-process on --mask off > "$OUT/probe-$1.json" 2>"$OUT/probe-$1.err"; local rc=$?
    s1=$(sysctl -n debug.strixsbx.status 2>/dev/null)
    denies "$t0" com.apple.WebKit.GPU > "$OUT/denies-$1.txt"
    /usr/bin/log show --start "$t0" --predicate 'eventMessage CONTAINS "sbxmap" OR (process == "com.apple.WebKit.GPU" AND (eventMessage CONTAINS "GPUBundles" OR eventMessage CONTAINS "vk: UP"))' \
      2>/dev/null | cut -c1-260 > "$OUT/log-$1.txt"
    echo "== $1 (exit $rc)"; cat "$OUT/probe-$1.json"
    echo "kext before: $s0"; echo "kext after:  $s1"
    echo "GPU process denies:"; grep -v -E 'apple-coprocessor-version' "$OUT/denies-$1.txt" | head -10
    # WebKit reports "Apple GPU" even with the mask off, so the device comes from the GPU process NVMTL log
    grep -q '"ok":true' "$OUT/probe-$1.json" && { grep -q -E '"unmasked_renderer":"[^"]*(890M|RADV)' "$OUT/probe-$1.json" ||
      grep -q -E 'vk: UP .*890M' "$OUT/log-$1.txt"; }
  }
  probe on; R=$?
  [[ $R == 0 ]] && echo "LIVE PASS: WKWebView WebGL renders on the 890M through the WebKit GPU process" ||
    echo "LIVE FAIL: see $OUT (run 'sim' to see which sandbox op the plugin still hits)"
  if [[ $AB == 1 ]]; then
    osascript -e 'do shell script "/usr/sbin/sysctl -w debug.strixsbx.enable=0" with prompt "StrixSbxMap A/B: exception off" with administrator privileges' >/dev/null
    probe off; echo "(expected: renderer not the 890M, deny file-map-executable back)"
    osascript -e 'do shell script "/usr/sbin/sysctl -w debug.strixsbx.enable=1" with prompt "StrixSbxMap A/B: exception back on" with administrator privileges' >/dev/null
  fi
  echo "Manual Safari check: open Safari (new window), https://webglreport.com/?v=1 -> Unmasked Renderer; Safari masks"
  echo "it by default, so the GPU process log + 'sysctl debug.strixsbx.status' allowed=N is the proof there."
  echo "logs: $OUT"; exit $R
  ;;
*) sed -n '2,18p' "$0"; exit 2 ;;
esac
