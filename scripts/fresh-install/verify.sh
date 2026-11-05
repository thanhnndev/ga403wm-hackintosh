#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
#
# Prototype for docs/FRESH-INSTALL.md: compare a manifest with what is on disk. Read-only, no root.
#
#   verify.sh MANIFEST              check every component at its destination (live system, ESP at $ESP or /Volumes/ESP)
#   verify.sh MANIFEST --payload D  check the payload folder D instead (before installing it)
#   verify.sh MANIFEST --stage S    only components of stage S (efi, le, userland, launchd, system)
#
# Exit 0 = every checked component matches. Uses only stock macOS tools (plutil reads the JSON manifest), so it runs on
# a fresh install before the Command Line Tools exist.
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
M=${1:?usage: verify.sh MANIFEST [--payload DIR] [--stage S]}
shift
PAYLOAD= STAGE=
while [ $# -gt 0 ]; do
    case "$1" in
        --payload) PAYLOAD=$2; shift 2 ;;
        --stage) STAGE=$2; shift 2 ;;
        *) echo "unknown argument $1"; exit 2 ;;
    esac
done
ESP=${ESP:-/Volumes/ESP}

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
treesha() {
    (cd "$1" && find . \( -type f -o -type l \) | LC_ALL=C sort | while read -r f; do
        if [ -L "$f" ]; then echo "link $(readlink "$f")  $f"; else echo "$(sha "$f")  $f"; fi
    done) | shasum -a 256 | cut -d' ' -f1
}
get() { plutil -extract "components.$1.$2" raw "$M" 2>/dev/null; }

where() {  # <stage> <dest>: the path to look at
    local st=$1 d=$2
    if [ -n "$PAYLOAD" ]; then
        case "$st" in
            le) echo "$PAYLOAD/le/$(basename "$d")" ;;
            userland) echo "$PAYLOAD/userland$d" ;;
            launchd) echo "$PAYLOAD/launchd${d#"$HOME"}" ;;
            *) echo "" ;;   # efi and system rows are built on the target, not carried in the payload
        esac
    else
        case "$d" in ESP:*) echo "$ESP/EFI/${d#ESP:EFI/}" ;; *) echo "$d" ;; esac
    fi
}

n=$(plutil -extract components raw "$M") || { echo "cannot read $M"; exit 2; }
ok=0 bad=0 skip=0
for ((i = 0; i < n; i++)); do
    id=$(get $i id) st=$(get $i stage) kind=$(get $i kind) dest=$(get $i dest) want=$(get $i sha256)
    [ -n "$STAGE" ] && [ "$st" != "$STAGE" ] && continue
    [ "$id" = aux-kc ] && { skip=$((skip + 1)); continue; }   # regenerated on every relink: checked by kext UUIDs instead
    p=$(where "$st" "$dest")
    [ -z "$p" ] && { skip=$((skip + 1)); continue; }
    if [ ! -e "$p" ]; then echo "MISSING  $id  ($p)"; bad=$((bad + 1)); continue; fi
    case "$kind" in
        kext-exe) exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$p/Contents/Info.plist" 2>/dev/null)
                  have=$(sha "$p/Contents/MacOS/$exe") ;;
        kext-tree|tree) have=$(treesha "$p") ;;
        *) have=$(sha "$p") ;;
    esac
    if [ "$have" = "$want" ]; then ok=$((ok + 1)); else echo "DIFFERS  $id  have ${have:0:16} want ${want:0:16}"; bad=$((bad + 1)); fi
done
echo "match $ok, differ/missing $bad, skipped $skip"
[ $bad = 0 ]
