#!/bin/bash
# Present-path A/B bench for StrixAccel >= 0.1.9. No reboot between configs: each one is a property write.
# Usage: bash scripts/macos-strix-present-bench.sh [seconds-per-config] [full|small]
set -u
SECS="${1:-6}"
SIZE="${2:-full}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${TMPDIR:-/tmp}/strix-present-bench"
mkdir -p "$OUT"
cc -O2 "$ROOT/tools/strix_accel_tune.c" -framework IOKit -framework CoreFoundation -o "$OUT/tune" || exit 1
swiftc -O "$ROOT/tools/strix_present_load.swift" -o "$OUT/load" || exit 1
TUNE="$OUT/tune"

val() { "$TUNE" | awk -v k="$1" '$1==k {print $2}'; }

run() { # name Mode Async SrcCache Block
    "$TUNE" Mode="$2" Async="$3" SrcCache="$4" Block="$5" Reset=1 >/dev/null
    sleep 0.5
    echo "=== $1 (mode=$2 async=$3 srccache=$4 block=$5)"
    "$OUT/load" "$SECS" "$SIZE" | tail -1
    printf "  copy avg %s us max %s us  written avg %s KB  submit avg %s us max %s us  coalesced %s  frames %s\n" \
        "$(val StrixAccel,Copy,AvgUs)" "$(val StrixAccel,Copy,MaxUs)" "$(val StrixAccel,Copy,AvgKB)" \
        "$(val StrixAccel,Present,SubmitUsAvg)" "$(val StrixAccel,Present,SubmitUsMax)" \
        "$(val StrixAccel,Present,Coalesced)" "$(val StrixAccel,Copy,Frames)"
}

"$TUNE" || { echo "StrixAccelerator 0.1.9+ not loaded"; exit 1; }
"$TUNE" Probe=1 >/dev/null
run "sync  full"            0 0 0 128
run "sync  diff"            1 0 0 128
run "async diff"            1 1 0 128
run "async full"            0 1 0 128
run "async diff copyback"   1 1 1 128
run "async diff writethru"  1 1 2 128
run "async diff wc"         1 1 4 128
run "async diff block512"   1 1 0 512
run "async diff block64"    1 1 0 64
echo "=== bandwidth probe"; "$TUNE" Probe=1 >/dev/null; sleep 1
"$OUT/load" 2 "$SIZE" | tail -1
"$TUNE" | grep -i "Probe\|FullFrameUs"
"$TUNE" Mode=1 Async=1 SrcCache=0 Block=128 >/dev/null
echo "restored defaults (mode=1 async=1 srccache=0 block=128)"
