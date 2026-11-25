#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
#
# Prototype for docs/FRESH-INSTALL.md: compare a manifest with what is on disk. Read-only, no root.
#
#   verify.sh MANIFEST              check every component at its destination (live system, ESP at $ESP or /Volumes/ESP)
#   verify.sh MANIFEST --payload D  check the payload folder D instead (before installing it)
#   verify.sh MANIFEST --drift D    check the payload folder D against the live system: fails when any carried file
#                                   differs from what is installed now (a stale capture, 2026-11-07 lesson)
#   verify.sh MANIFEST --stage S    only components of stage S (efi, le, userland, launchd, system)
#
# Exit 0 = every checked component matches. Uses only stock macOS tools (plutil reads the JSON manifest), so it runs on
# a fresh install before the Command Line Tools exist.
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
M=${1:?usage: verify.sh MANIFEST [--payload DIR | --drift DIR] [--stage S]}
shift
PAYLOAD= STAGE= DRIFT=0
while [ $# -gt 0 ]; do
    case "$1" in
        --payload) PAYLOAD=$2; shift 2 ;;
        --drift) PAYLOAD=$2; DRIFT=1; shift 2 ;;
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

in_payload() {  # <stage> <dest>: where the payload carries it ("" = not carried)
    case "$1" in
        le) echo "$PAYLOAD/le/$(basename "$2")" ;;
        userland) echo "$PAYLOAD/userland${2#"$HOME"}" ;;
        launchd) echo "$PAYLOAD/launchd${2#"$HOME"}" ;;
        *) echo "" ;;   # efi and system rows are built on the target, not carried in the payload
    esac
}
live() { case "$1" in ESP:*) echo "$ESP/EFI/${1#ESP:EFI/}" ;; *) echo "$1" ;; esac; }
hashof() {  # <kind> <path>
    case "$1" in
        kext-exe) local exe
                  exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$2/Contents/Info.plist" 2>/dev/null)
                  sha "$2/Contents/MacOS/$exe" ;;
        kext-tree|tree) treesha "$2" ;;
        *) sha "$2" ;;
    esac
}

n=$(plutil -extract components raw "$M") || { echo "cannot read $M"; exit 2; }
cap=$(plutil -extract captured_utc raw "$M" 2>/dev/null)
build=$(plutil -extract macos.build raw "$M" 2>/dev/null)
if [ -n "$cap" ]; then
    age=$(( ($(date -u +%s) - $(date -j -u -f %Y-%m-%dT%H:%M:%SZ "$cap" +%s 2>/dev/null || date -u +%s)) / 86400 ))
    echo "manifest captured $cap on $build ($age days ago); this Mac runs $(sw_vers -buildVersion)"
fi
ok=0 bad=0 skip=0
for ((i = 0; i < n; i++)); do
    id=$(get $i id) st=$(get $i stage) kind=$(get $i kind) dest=$(get $i dest) want=$(get $i sha256)
    [ -n "$STAGE" ] && [ "$st" != "$STAGE" ] && continue
    [ "$id" = aux-kc ] && { skip=$((skip + 1)); continue; }   # regenerated on every relink: checked by kext UUIDs instead
    if [ -n "$PAYLOAD" ]; then p=$(in_payload "$st" "$dest"); else p=$(live "$dest"); fi
    [ -z "$p" ] && { skip=$((skip + 1)); continue; }
    if [ ! -e "$p" ]; then echo "MISSING  $id  ($p)"; bad=$((bad + 1)); continue; fi
    have=$(hashof "$kind" "$p")
    if [ $DRIFT = 1 ]; then
        l=$(live "$dest")
        if [ ! -e "$l" ]; then echo "GONE     $id  (payload has it, live has no $l)"; bad=$((bad + 1)); continue; fi
        now=$(hashof "$kind" "$l")
        if [ "$have" = "$now" ]; then ok=$((ok + 1)); else echo "DRIFT    $id  payload ${have:0:16} live ${now:0:16}"; bad=$((bad + 1)); fi
        continue
    fi
    if [ "$have" = "$want" ]; then ok=$((ok + 1)); else echo "DIFFERS  $id  have ${have:0:16} want ${want:0:16}"; bad=$((bad + 1)); fi
done
echo "match $ok, differ/missing $bad, skipped $skip"
[ $DRIFT = 1 ] && [ $bad != 0 ] && echo "the payload is stale: capture again (capture-live.sh OUT --copy) before building the stick"
[ $bad = 0 ]
