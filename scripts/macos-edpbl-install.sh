#!/bin/bash
# Installs the AUX-brightness kext (NVRMEdpBL) and the NVRMFB that asks it first, on top of an installed upstream NullMoth
# driver (1.14.2 .. 1.15.0; both kexts are built from the fork branch ga403wm of thanhnndev/nvidia-macos-driver).
#   scripts/macos-edpbl-install.sh          install
#   scripts/macos-edpbl-install.sh --undo   restore the NVRMFB / NVRM plist that were there, remove the kext, rebuild the collection
# Root (run through osascript "with administrator privileges", see docs/OLED-BRIGHTNESS-DPCD.md). Reboot loads it.
# Runtime off switch: boot-arg nvrmedpbl=0. NVRMFB accepted as "before": the NVRMFB of the upstream package you point
# UPSTREAM_NVRMFB at (the pkgroot of the NullMoth release you installed), the 1.14.2 VRAM-clear-only build (f3e7bff4...,
# legacy: the VRAM-clear patch was dropped 2026-10-13), or this build. Another overlay build: run --undo first.
# Paths (root has no useful $HOME under osascript, so the console user's home is the default):
#   BRIGHT_DIR        where macos-build-nullmoth-local.sh staged the build   (default <home>/efi-audit/brightness)
#   UPSTREAM_NVRMFB   the pristine NVRMFB of the installed release, for the "before" check (optional)
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
NMH=${NM_HOME:-$(eval echo "~$(stat -f %Su /dev/console)")}
BASE=${BRIGHT_DIR:-$NMH/efi-audit/brightness}/stage
UP=${UPSTREAM_NVRMFB:-$NMH/efi-audit/upgrade-1.14.2/pkg/pkgroot/Library/Extensions/NVRMFB.kext/Contents/MacOS/NVRMFB}
FB_SHA=$(awk '$2=="NVRMFB"{print $1}' "$BASE/SHA256SUMS" 2>/dev/null)   # written by macos-build-nullmoth-local.sh
EDP_SHA=$(awk '$2=="NVRMEdpBL"{print $1}' "$BASE/SHA256SUMS" 2>/dev/null)
EXT=/Library/Extensions; KEXE=$EXT/NVRMFB.kext/Contents/MacOS/NVRMFB; NVRMPL=$EXT/NVRM.kext/Contents/Info.plist
EDPK=$EXT/NVRMEdpBL.kext
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
K=/System/Library/Kernels/kernel
KB=/System/Library/KernelCollections/BootKernelExtensions.kc
KS=/System/Library/KernelCollections/SystemKernelExtensions.kc
STATE=/Library/NullMoth/edpbl-patch
KARG=(--allow-missing-kdk); [ -f "$K" ] && KARG+=(--kernel "$K")
die() { echo "STOP: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -c1-64; }
[ "$(id -u)" -eq 0 ] || die "needs root"
[ -n "$FB_SHA" ] && [ -n "$EDP_SHA" ] || die "no $BASE/SHA256SUMS: run scripts/macos-build-nullmoth-local.sh first"
[ -f "$KEXE" ] && [ -f "$NVRMPL" ] || die "NVRM / NVRMFB are not installed"

rebuild_kc() {
  local new="$KC.edpbl-new" log; log=$(mktemp /var/tmp/edpbl.XXXX) || return 1
  rm -f "$new"
  kmutil create -n aux --volume-root / "${KARG[@]}" -B $KB -S $KS --repository "$EXT" -A "$new" -z >"$log" 2>&1 \
    || { tail -20 "$log"; rm -f "$new"; return 1; }
  [ -s "$new" ] || { echo "kernel collection build produced no output"; rm -f "$new"; return 1; }
  local ins; ins=$(kmutil inspect -a x86_64 -A "$new" 2>/dev/null) || { rm -f "$new"; return 1; }
  for k in "$@"; do
    printf '%s\n' "$ins" | grep -oE 'com\.nullmoth\.[A-Za-z0-9]+' | grep -Fxq "com.nullmoth.$k" || { echo "com.nullmoth.$k missing"; rm -f "$new"; return 1; }
  done
  mv -f "$new" "$KC" || return 1
  rm -f "$log"
}

if [ "${1:-}" = --undo ]; then
  [ -d "$STATE" ] || die "no state at $STATE"
  [ -f "$STATE/NVRMFB.before" ] && cp -p "$STATE/NVRMFB.before" "$KEXE" && chown root:wheel "$KEXE" && chmod 755 "$KEXE"
  [ -f "$STATE/NVRM.Info.plist.before" ] && cp -p "$STATE/NVRM.Info.plist.before" "$NVRMPL"
  rm -rf "$EDPK"
  rebuild_kc NVRM NVRMFB NVRMAGDC NVAccel || die "kernel collection rebuild failed; files were restored, the old collection is still $KC"
  rm -f "$STATE/installed"
  echo "restored (NVRMFB $(sha "$KEXE")). Reboot to load it."
  exit 0
fi

CUR=$(sha "$KEXE")
[ "$CUR" = "$FB_SHA" ] || { [ -f "$UP" ] && [ "$CUR" = "$(sha "$UP")" ]; } || [ "$CUR" = f3e7bff458de1abb29888e559915d25d7afe84f514bbd0a4b45740566edb7c25 ] \
  || die "installed NVRMFB ($CUR) is neither the upstream NVRMFB (set UPSTREAM_NVRMFB), the 1.14.2 VRAM patch, nor this build"
[ "$(sha "$BASE/NVRMFB")" = "$FB_SHA" ] || die "staged NVRMFB hash differs from the reviewed build"
[ "$(sha "$BASE/NVRMEdpBL.kext/Contents/MacOS/NVRMEdpBL")" = "$EDP_SHA" ] || die "staged NVRMEdpBL hash differs from the reviewed build"
mkdir -p "$STATE" || die "state dir"
# "before" = what upstream's install.sh left. Keep it on a re-run of this script (installed == this build), refresh it when
# the installed NVRMFB is not this build (a newer upstream release was installed since), or undo would bring back old files.
FRESH=0; [ "$CUR" = "$FB_SHA" ] || FRESH=1
if [ "$FRESH" = 1 ]; then rm -f "$STATE/NVRMFB.before" "$STATE/NVRM.Info.plist.before" "$STATE/AuxiliaryKernelExtensions.kc.before"; fi
[ -f "$STATE/NVRMFB.before" ] || cp -p "$KEXE" "$STATE/NVRMFB.before"
[ -f "$STATE/NVRM.Info.plist.before" ] || cp -p "$NVRMPL" "$STATE/NVRM.Info.plist.before"
[ -f "$STATE/AuxiliaryKernelExtensions.kc.before" ] || cp -p "$KC" "$STATE/AuxiliaryKernelExtensions.kc.before" 2>/dev/null

rollback() {
  [ -f "$STATE/NVRMFB.before" ] && cp -p "$STATE/NVRMFB.before" "$KEXE"
  [ -f "$STATE/NVRM.Info.plist.before" ] && cp -p "$STATE/NVRM.Info.plist.before" "$NVRMPL"
  rm -rf "$EDPK"
}
cp "$BASE/NVRMFB" "$KEXE" && chown root:wheel "$KEXE" && chmod 755 "$KEXE" || { rollback; die "install NVRMFB"; }
# a kext can only link against NVRM when NVRM declares a compatible version
plutil -replace OSBundleCompatibleVersion -string 0.1 "$NVRMPL" || { rollback; die "NVRM plist"; }
rm -rf "$EDPK"; cp -R "$BASE/NVRMEdpBL.kext" "$EDPK" && chown -R root:wheel "$EDPK" && chmod -R go-w "$EDPK" && chmod 755 "$EDPK/Contents/MacOS/NVRMEdpBL" \
  || { rollback; die "install NVRMEdpBL.kext"; }
if ! rebuild_kc NVRM NVRMFB NVRMEdpBL NVRMAGDC NVAccel; then rollback; die "kernel collection rebuild failed; everything put back (collection untouched)"; fi
{ echo "installed $(date)"; echo "NVRMFB sha256 $FB_SHA"; echo "NVRMEdpBL sha256 $EDP_SHA"; echo "fork thanhnndev/nvidia-macos-driver branch ga403wm @ $(cat "$BASE/FORK_HEAD" 2>/dev/null || echo unknown)"; } > "$STATE/installed"
echo "installed. Reboot to load it. Off switch: boot-arg nvrmedpbl=0. Undo: sudo bash $0 --undo"
