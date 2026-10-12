#!/bin/bash
# Installs / removes a locally built NVAccel executable (patches/nullmoth-readback 0002, optionally + 0003) in NullMoth 1.14.2
# and rebuilds the auxiliary kernel collection exactly as scripts/macos-nvrmfb-vramclear-patch.sh does (that one ran here).
#   sudo bash scripts/macos-readback-nvaccel-install.sh --exe /path/NVAccel --sha256 <hash printed by your build>
#   sudo bash scripts/macos-readback-nvaccel-install.sh --undo
# NOT RUN YET (written without a Mac). A reboot loads the result. Only the executable changes; Info.plist and the other
# kexts stay as installed (including the combined NVRMFB). If the collection cannot be rebuilt the stock executable is put back.
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
EXT=/Library/Extensions; KEXE=$EXT/NVAccel.kext/Contents/MacOS/NVAccel
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
K=/System/Library/Kernels/kernel
KB=/System/Library/KernelCollections/BootKernelExtensions.kc
KS=/System/Library/KernelCollections/SystemKernelExtensions.kc
STATE=/Library/NullMoth/nvaccel-readback
KARG=(--allow-missing-kdk); [ -f "$K" ] && KARG+=(--kernel "$K")
die() { echo "STOP: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -c1-64; }
[ "$(id -u)" -eq 0 ] || die "needs root (run through sudo or osascript with administrator privileges)"
[ -f "$KEXE" ] || die "NVAccel.kext is not installed"
rebuild_kc() {
  local new="$KC.nvaccel-readback-new" log; log=$(mktemp /var/tmp/nvaccel-readback.XXXX) || return 1
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
  [ -f "$STATE/NVAccel.stock" ] || die "no backup at $STATE"
  cp -p "$STATE/NVAccel.stock" "$KEXE" && chown root:wheel "$KEXE" && chmod 755 "$KEXE" || die "restore executable"
  rebuild_kc || die "kernel collection rebuild failed; the executable was restored, the old collection is still $KC (restore $STATE/AuxiliaryKernelExtensions.kc.before if needed)"
  rm -f "$STATE/installed.sha256"
  echo "stock NVAccel restored ($(sha "$KEXE")). Reboot to load it."
  exit 0
fi
[ "${1:-}" = --exe ] && [ -n "${2:-}" ] && [ "${3:-}" = --sha256 ] && [ -n "${4:-}" ] || die "usage: --exe PATH --sha256 HASH | --undo"
EXE=$2; WANT=$4
[ "$(cat /Library/NullMoth/driver-version 2>/dev/null)" = 1.14.2 ] || die "NullMoth is not 1.14.2"
[ "$(sha "$EXE")" = "$WANT" ] || die "executable sha256 differs from --sha256"
CUR=$(sha "$KEXE")
mkdir -p "$STATE" || die "state dir"
if [ ! -f "$STATE/NVAccel.stock" ]; then cp -p "$KEXE" "$STATE/NVAccel.stock" || die "backup"; echo "$CUR" > "$STATE/NVAccel.stock.sha256"; fi
[ "$CUR" = "$(cat "$STATE/NVAccel.stock.sha256")" ] || [ "$CUR" = "$(cat "$STATE/installed.sha256" 2>/dev/null)" ] || die "installed NVAccel ($CUR) is neither the recorded stock one nor this script's previous install"
[ -f "$STATE/AuxiliaryKernelExtensions.kc.before" ] || cp -p "$KC" "$STATE/AuxiliaryKernelExtensions.kc.before" 2>/dev/null
cp "$EXE" "$KEXE" && chown root:wheel "$KEXE" && chmod 755 "$KEXE" || die "install executable"
if ! rebuild_kc; then
  cp -p "$STATE/NVAccel.stock" "$KEXE" && chown root:wheel "$KEXE" && chmod 755 "$KEXE"
  die "kernel collection rebuild failed; stock NVAccel put back (collection untouched)"
fi
echo "$WANT" > "$STATE/installed.sha256"
echo "NVAccel installed and the collection rebuilt. Reboot to load it."
echo "Counters afterwards: sysctl -a | grep nvaccel_ss_     Undo: sudo bash $0 --undo"
