#!/bin/bash
# LEGACY (1.14.2 only, patch dropped 2026-10-13; macos-edpbl-install.sh installs the AUX-brightness overlay from fork branch ga403wm).
# Applies the local NVRMFB patch (fork thanhnndev/nvidia-macos-driver, branch nvrmfb-vram-clear-nontemporal) on top of an
# installed upstream NullMoth 1.14.2, then rebuilds the auxiliary kernel collection the way upstream's install.sh does.
#   apply-nvrmfb-patch.sh          install the patched NVRMFB executable
#   apply-nvrmfb-patch.sh --undo   put the upstream 1.14.2 NVRMFB back
# Needs root (run through osascript "with administrator privileges"). A reboot loads the result.
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
BASE=${NM_HOME:-/Users/thanhnndev}/efi-audit/upgrade-1.14.2
PRISTINE=$BASE/pkg/pkgroot/Library/Extensions/NVRMFB.kext/Contents/MacOS/NVRMFB
PATCHED=$BASE/patched/NVRMFB
PATCHED_SHA=f3e7bff458de1abb29888e559915d25d7afe84f514bbd0a4b45740566edb7c25
EXT=/Library/Extensions; KEXE=$EXT/NVRMFB.kext/Contents/MacOS/NVRMFB
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
K=/System/Library/Kernels/kernel
KB=/System/Library/KernelCollections/BootKernelExtensions.kc
KS=/System/Library/KernelCollections/SystemKernelExtensions.kc
STATE=/Library/NullMoth/nvrmfb-patch
KARG=(--allow-missing-kdk); [ -f "$K" ] && KARG+=(--kernel "$K")
die() { echo "STOP: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -c1-64; }
[ "$(id -u)" -eq 0 ] || die "needs root"
[ -f "$KEXE" ] || die "NVRMFB.kext is not installed"
PRIST_SHA=$(sha "$PRISTINE")

rebuild_kc() {
  local new="$KC.nvrmfb-patch-new" log; log=$(mktemp /var/tmp/nvrmfb-patch.XXXX) || return 1
  rm -f "$new"
  kmutil create -n aux --volume-root / "${KARG[@]}" -B $KB -S $KS --repository "$EXT" -A "$new" -z >"$log" 2>&1 \
    || { tail -20 "$log"; rm -f "$new"; return 1; }
  [ -s "$new" ] || { echo "kernel collection build produced no output"; rm -f "$new"; return 1; }
  local ins; ins=$(kmutil inspect -a x86_64 -A "$new" 2>/dev/null) || { rm -f "$new"; return 1; }
  for k in NVRM NVAccel NVRMFB NVRMAGDC; do
    printf '%s\n' "$ins" | grep -oE 'com\.nullmoth\.[A-Za-z0-9]+' | grep -Fxq "com.nullmoth.$k" || { echo "com.nullmoth.$k missing"; rm -f "$new"; return 1; }
  done
  mv -f "$new" "$KC" || return 1
  rm -f "$log"
}

if [ "${1:-}" = --undo ]; then
  [ -d "$STATE" ] || die "no patch state at $STATE"
  cp -p "$PRISTINE" "$KEXE" && chown root:wheel "$KEXE" && chmod 755 "$KEXE" || die "restore executable"
  rebuild_kc || die "kernel collection rebuild failed; the executable was restored, the old collection is still $KC"
  rm -f "$STATE/installed.sha256"
  echo "upstream NVRMFB restored ($(sha "$KEXE")). Reboot to load it."
  exit 0
fi

[ "$(sha "$PATCHED")" = "$PATCHED_SHA" ] || die "patched executable hash differs from the reviewed build"
# upstream first: the installed NVRMFB must be exactly the 1.14.2 one (or an earlier run of this patch)
CUR=$(sha "$KEXE")
if [ "$CUR" != "$PRIST_SHA" ] && [ "$CUR" != "$PATCHED_SHA" ]; then
  die "installed NVRMFB ($CUR) is neither upstream 1.14.2 ($PRIST_SHA) nor this patch; install upstream 1.14.2 first"
fi
mkdir -p "$STATE" || die "state dir"
[ -f "$STATE/NVRMFB.upstream-1.14.2" ] || cp -p "$PRISTINE" "$STATE/NVRMFB.upstream-1.14.2"
[ -f "$STATE/AuxiliaryKernelExtensions.kc.before" ] || cp -p "$KC" "$STATE/AuxiliaryKernelExtensions.kc.before" 2>/dev/null
cp "$PATCHED" "$KEXE" && chown root:wheel "$KEXE" && chmod 755 "$KEXE" || die "install patched executable"
if ! rebuild_kc; then
  cp -p "$PRISTINE" "$KEXE" && chown root:wheel "$KEXE" && chmod 755 "$KEXE"
  die "kernel collection rebuild failed; upstream NVRMFB put back (collection untouched)"
fi
{ echo "installed $(date)"; echo "fork branch nvrmfb-vram-clear-nontemporal commit 49633c9"; echo "executable sha256 $PATCHED_SHA"; } > "$STATE/installed.sha256"
echo "patched NVRMFB installed and the collection rebuilt. Reboot to load it."
echo "A/B in one boot: sysctl debug.nvrmfb_clear_mode (1 = non-temporal, 0 = rep stosq); counters debug.nvrmfb_clear_us_sum / _bytes / _us_max."
echo "Undo: sudo bash $0 --undo"
