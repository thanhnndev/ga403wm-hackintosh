#!/bin/bash
# usage: tools/dsc-extract.sh <ImageName> [dsc-dir]   e.g. CoreDisplay
# Needs the OS cryptex mounted (loop-mount cryptex1/current/os.dmg from the Preboot volume at /mnt/cryptex, read-only apfs).
# Output: ref/macos-<ver>/<ImageName> and <ImageName>.syms.txt
set -euo pipefail
R=$(cd "$(dirname "$0")/.." && pwd)
DSC=${2:-/mnt/cryptex/System/Library/dyld}/dyld_shared_cache_x86_64h
OUT=$R/ref/macos-26.7.1; mkdir -p "$OUT"
"$R/tools/bin/ipsw" dyld extract "$DSC" "$1" -o "$OUT.tmp"
mv "$OUT.tmp/$1" "$OUT/$1"; rmdir "$OUT.tmp"
"$R/tools/bin/ipsw" macho info "$OUT/$1" --symbols --demangle > "$OUT/$1.syms.txt"
