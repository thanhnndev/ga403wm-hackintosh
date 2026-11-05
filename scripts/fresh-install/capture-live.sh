#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
#
# Prototype for docs/FRESH-INSTALL.md: record what a working GA403WM has installed, as a manifest of sha256 values.
# Read-only on the live system. Runs as the normal user (no root, no writes outside OUT).
#
#   capture-live.sh OUT            write OUT/manifest.live.json (hashes only)
#   capture-live.sh OUT --copy     also copy every non-ESP file into OUT/payload/ (the "golden payload")
#
# OUT must be outside this repository: the payload holds PolyForm NullMoth binaries, which this BSD repo must not carry.
# The ESP itlmt7925*.kext are hashed but never copied (they can hold injected Wi-Fi credentials in plain text), and
# config.plist is not hashed (it holds the serial, MLB, UUID and ROM).
# Needs only stock macOS tools: shasum, plutil, PlistBuddy, otool is optional (LC_UUID column).
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
OUT=${1:?usage: capture-live.sh OUT [--copy]}
COPY=0; [ "${2:-}" = --copy ] && COPY=1
REPO=$(cd "$(dirname "$0")/../.." && pwd)
case "$(cd "$(dirname "$OUT")" 2>/dev/null && pwd)/" in "$REPO"/*) echo "OUT must be outside the repository"; exit 1 ;; esac
mkdir -p "$OUT"
ESP=${ESP:-/Volumes/ESP}
J="$OUT/manifest.live.json"
first=1

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
treesha() {  # <dir>: sha256 over "sha  relative-path" of every regular file, sorted (symlinks recorded by target)
    (cd "$1" && find . \( -type f -o -type l \) | LC_ALL=C sort | while read -r f; do
        if [ -L "$f" ]; then echo "link $(readlink "$f")  $f"; else echo "$(sha "$f")  $f"; fi
    done) | shasum -a 256 | cut -d' ' -f1
}
plistval() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }
lcuuid() { otool -l "$1" 2>/dev/null | awk '/LC_UUID/{f=1} f&&/uuid/{print $2; exit}'; }
jstr() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

row() {  # id stage license kind dest sha [bundle_id version uuid]
    [ $first = 1 ] && first=0 || printf ',\n' >>"$J"
    printf '    {"id": "%s", "stage": "%s", "license": "%s", "kind": "%s", "dest": "%s", "sha256": "%s"' \
        "$(jstr "$1")" "$2" "$3" "$4" "$(jstr "$5")" "$6" >>"$J"
    [ -n "${7:-}" ] && printf ', "bundle_id": "%s", "version": "%s"' "$7" "$8" >>"$J"
    [ -n "${9:-}" ] && printf ', "lc_uuid": "%s"' "$9" >>"$J"
    printf '}' >>"$J"
}
copy_in() {  # <src> <payload-relative-dest>
    [ $COPY = 1 ] || return 0
    mkdir -p "$OUT/payload/$(dirname "$2")"
    # cp -R, not ditto: ditto copies BSD flags, and some NullMoth files carry the SIP "restricted" flag, which a normal
    # user cannot set (Operation not permitted). Content, mode and symlinks are what the manifest checks.
    rm -rf "$OUT/payload/$2"
    cp -R "$1" "$OUT/payload/$2"
}
license_for() {
    case "$1" in
        com.nullmoth.*|com.ga403wm.NMX*) echo "PolyForm-Noncommercial-1.0.0" ;;
        com.itlmt7925.*|com.ga403wm.*) echo "BSD-3-Clause-Clear" ;;
        *) echo "third-party" ;;
    esac
}
kext_row() {  # <stage> <kext dir> <dest>
    local k=$1 d=$2 dest=$3 exe bid ver
    bid=$(plistval "$d/Contents/Info.plist" CFBundleIdentifier)
    ver=$(plistval "$d/Contents/Info.plist" CFBundleShortVersionString)
    exe=$(plistval "$d/Contents/Info.plist" CFBundleExecutable)
    if [ -n "$exe" ] && [ -f "$d/Contents/MacOS/$exe" ]; then
        row "kext-$(basename "$d" .kext)" "$k" "$(license_for "$bid")" kext-exe "$dest" \
            "$(sha "$d/Contents/MacOS/$exe")" "$bid" "$ver" "$(lcuuid "$d/Contents/MacOS/$exe")"
    else
        row "kext-$(basename "$d" .kext)" "$k" "$(license_for "$bid")" kext-tree "$dest" "$(treesha "$d")" "$bid" "$ver"
    fi
}

{
    printf '{\n  "schema": 1,\n  "captured_utc": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "macos": {"version": "%s", "build": "%s"},\n' "$(sw_vers -productVersion)" "$(sw_vers -buildVersion)"
    printf '  "csr_active_config": "%s",\n' "$(nvram csr-active-config 2>/dev/null | cut -f2 | jstr "$(cat)")"
    printf '  "components": [\n'
} >"$J"

# 1. EFI (ESP). Kexts are recorded only when config.plist enables them.
if [ -f "$ESP/EFI/OC/config.plist" ]; then
    C="$ESP/EFI/OC/config.plist"
    row oc-OpenCore.efi efi third-party file "ESP:EFI/OC/OpenCore.efi" "$(sha "$ESP/EFI/OC/OpenCore.efi")"
    for f in "$ESP"/EFI/OC/Drivers/*.efi; do row "oc-driver-$(basename "$f")" efi third-party file "ESP:EFI/OC/Drivers/$(basename "$f")" "$(sha "$f")"; done
    i=0
    while p=$(plistval "$C" "ACPI:Add:$i:Path"); do
        [ "$(plistval "$C" "ACPI:Add:$i:Enabled")" = true ] && \
            row "acpi-$p" efi BSD-3-Clause-Clear-or-1401 file "ESP:EFI/OC/ACPI/$p" "$(sha "$ESP/EFI/OC/ACPI/$p")"
        i=$((i + 1))
    done
    i=0
    while p=$(plistval "$C" "Kernel:Add:$i:BundlePath"); do
        if [ "$(plistval "$C" "Kernel:Add:$i:Enabled")" = true ] && [ "${p%%/*}" = "$p" ]; then
            kext_row efi "$ESP/EFI/OC/Kexts/$p" "ESP:EFI/OC/Kexts/$p"
        fi
        i=$((i + 1))
    done
else
    echo "no ESP at $ESP (mount it first); EFI rows skipped" >&2
fi

# 2. /Library/Extensions (AuxKC). Only this project's and NullMoth's kexts.
for d in /Library/Extensions/*.kext; do
    bid=$(plistval "$d/Contents/Info.plist" CFBundleIdentifier)
    case "$bid" in com.nullmoth.*|com.ga403wm.*|com.itlmt7925.*) ;; *) continue ;; esac
    kext_row le "$d" "$d"
    copy_in "$d" "le/$(basename "$d")"
done
[ -f /Library/KernelCollections/AuxiliaryKernelExtensions.kc ] && \
    row aux-kc le generated file /Library/KernelCollections/AuxiliaryKernelExtensions.kc \
        "$(sha /Library/KernelCollections/AuxiliaryKernelExtensions.kc)"

# 3. Userland: GPU bundles, NullMoth payload dirs, our state dirs.
for d in /Library/GPUBundles/NVMTLDriver.bundle /Library/GPUBundles/NVIDIAShared.bundle /Library/GPUBundles/nvmtl \
         /Library/NullMoth/gpu-userland /Library/NullMoth/firmware /Library/NullMoth/kexts /Library/NullMoth/nvfw; do
    [ -e "$d" ] || continue
    row "tree-$(basename "$d")" userland PolyForm-Noncommercial-1.0.0 tree "$d" "$(treesha "$d")"
    copy_in "$d" "userland${d}"
done
for f in /Library/GPUBundles/nvmtl-allow.txt /Library/StrixGraphicsFix/nmx-flip.mode \
         /Library/StrixGraphicsFix/nmx-flip-default.sh /Library/NullMoth/driver-version; do
    [ -f "$f" ] || continue
    row "file-$(basename "$f")" userland BSD-3-Clause-Clear file "$f" "$(sha "$f")"
    copy_in "$f" "userland${f}"
done

# 3b. Programs the launchd jobs start, the audio HAL driver and the panel display override (BSD, this project).
for d in /Library/PrivilegedHelperTools/com.itlmt7925.* "/Library/Application Support/RogAudio" \
         /Library/Audio/Plug-Ins/HAL/RogAudio.driver /Applications/ItlWiFi.app /Applications/RogControl.app \
         /Applications/TapGuard.app /Library/Displays/Contents/Resources/Overrides/DisplayVendorID-4c83; do
    [ -e "$d" ] || continue
    if [ -d "$d" ]; then
        row "app-$(basename "$d")" userland BSD-3-Clause-Clear tree "$d" "$(treesha "$d")"
    else
        row "app-$(basename "$d")" userland BSD-3-Clause-Clear file "$d" "$(sha "$d")"
    fi
    copy_in "$d" "userland${d}"
done

# 4. launchd jobs of this project and of NullMoth.
for f in /Library/LaunchDaemons/com.{nullmoth,ga403wm,itlmt7925}.*.plist /Library/LaunchAgents/com.{nullmoth,itlmt7925}.*.plist \
         "$HOME"/Library/LaunchAgents/com.itlmt7925.*.plist; do
    [ -f "$f" ] || continue
    row "launchd-$(basename "$f" .plist)" launchd "$(license_for "$(basename "$f")")" file "$f" "$(sha "$f")"
    copy_in "$f" "launchd${f#"$HOME"}"
done

# 5. Sealed-system changes (live in the blessed snapshot; a fresh install has to redo them).
for f in /System/Library/Sandbox/Profiles/com.apple.WindowServer.sb; do
    [ -f "$f" ] && row "system-$(basename "$f")" system Apple-modified file "$f" "$(sha "$f")"
done
for d in /System/Library/Video/Plug-Ins/*VTStub*.bundle; do
    [ -e "$d" ] && row "system-$(basename "$d")" system BSD-3-Clause-Clear tree "$d" "$(treesha "$d")"
done

printf '\n  ]\n}\n' >>"$J"
plutil -convert xml1 -o /dev/null "$J" || { echo "manifest is not valid JSON: $J"; exit 1; }
echo "wrote $J ($(grep -c '"id"' "$J") components)"
[ $COPY = 1 ] && echo "payload in $OUT/payload (PolyForm parts: keep it private, never commit it here)"
exit 0
