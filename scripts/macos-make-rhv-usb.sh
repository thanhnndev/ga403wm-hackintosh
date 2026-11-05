#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Test USB stick for RyzenHV (Hypervisor.framework on AMD-V, ../ryzen-hypervisor.framework); docs/RYZENHV.md.
# The internal ESP is only READ: its EFI is copied to build/rhv-usb/EFI and only that copy changes, through
# tools/occonfig.py like every ESP edit of this repo (backup config.plist.<tag> before each write, schema + ocvalidate check).
# Booting without the stick boots the internal ESP unchanged; boot-args is in NVRAM/Delete there, so the stick's do not stay.
#
#   scripts/macos-make-rhv-usb.sh [--stage S]                        build RyzenHV, stage the EFI (no disk touched)
#   scripts/macos-make-rhv-usb.sh [--stage S] --write diskN --format ERASE diskN (MBR, FAT32 "RHVEFI"), copy the EFI
#   scripts/macos-make-rhv-usb.sh [--stage S] --write diskN          update a stick made before; its old RyzenHV.kext goes to
#                                                                    EFI/OC/Kexts-backup/RyzenHV.kext.<time>, its old config to
#                                                                    EFI/OC/config.plist.pre-ryzenhv-<stage>-<time>
#   scripts/macos-make-rhv-usb.sh --undo diskN                       put the stick's newest kext and config backups back
#
# Stages: boot-args added to the internal ones (the kill switch is -rhv_off, typed nowhere: boot without the stick instead)
#   native  rhv_enable_svm=1 rhv_selftest=1 rhv_hv=1 rhv_allow_users=1 rhv_loglevel=4    default: one boot answers the probe,
#           the SVM enable on every core, the self-test and the native front end (batch per reboot)
#   svm     rhv_enable_svm=1 rhv_selftest=1 rhv_loglevel=4       fallback if native fails
#   probe   rhv_loglevel=4: the kext only reads CPUID / VM_CR / EFER, SVM stays off   fallback if svm fails
# Kernel/Add: RyzenHV.kext last, Enabled, MinKernel 24.0.0, MaxKernel 25.99.99. Misc/Debug/Target 65: opencore-*.txt on the stick.
# build/rhv-usb holds the real config.plist (serial, MLB, ROM): build/ is ignored by git, never commit it.
set -euo pipefail
cd "$(dirname "$0")/.."
# RyzenHV sits next to the main checkout (also when this runs from a worktree in .claude/worktrees/)
MAIN_REPO=$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd)")
RHV_SRC=${RYZENHV_SRC:-$(dirname "$MAIN_REPO")/ryzen-hypervisor.framework}
ESP_EFI=${ESP_EFI:-/Volumes/ESP/EFI}
OCC="python3 -I tools/occonfig.py"      # the python3 on PATH, as the other scripts of this repo
S=build/rhv-usb
LABEL=RHVEFI
GUID=7C436110-AB2A-4BBB-A880-FE41995C9F82
TS=$(date +%Y%m%d-%H%M%S)
STAGE=native DISK="" FORMAT=0 UNDO=0

while [ $# -gt 0 ]; do
  case "$1" in
    --stage) STAGE="${2:?}"; shift 2 ;;
    --write) DISK="${2:?}"; shift 2 ;;
    --undo) UNDO=1; DISK="${2:?}"; shift 2 ;;
    --format) FORMAT=1; shift ;;
    *) sed -n '4,22p' "$0"; exit 2 ;;
  esac
done
mkdir -p build/rhv-usb-logs
exec > >(tee -a "build/rhv-usb-logs/rhv-usb-$TS.log") 2>&1        # every run logged, like the stepNNN scripts
case "$STAGE" in
  native) RHV_ARGS="-v rhv_enable_svm=1 rhv_selftest=1 rhv_hv=1 rhv_allow_users=1 rhv_loglevel=4" ;;
  svm)    RHV_ARGS="-v rhv_enable_svm=1 rhv_selftest=1 rhv_loglevel=4" ;;
  probe)  RHV_ARGS="-v rhv_loglevel=4" ;;
  *) echo "unknown stage $STAGE (native, svm, probe)"; exit 2 ;;
esac

# ---- the stick: only an external, removable whole disk that is not the system disk
stick_check() {
  DISK=${DISK#/dev/}
  [[ $DISK =~ ^disk[0-9]+$ ]] || { echo "give a whole disk like disk4, not $DISK"; exit 1; }
  local info; info=$(diskutil info -plist "$DISK") || { echo "no $DISK"; exit 1; }
  key() { /usr/bin/python3 -I -c 'import plistlib,sys; print(plistlib.loads(sys.stdin.buffer.read()).get(sys.argv[1], ""))' "$1" <<<"$info"; }
  [ "$(key Internal)" = False ] || { echo "$DISK is an internal disk: refusing"; exit 1; }
  [ "$(key WholeDisk)" = True ] || { echo "$DISK is not a whole disk"; exit 1; }
  [ "$(key RemovableMediaOrExternalDevice)" = True ] || { echo "$DISK is not removable/external: refusing"; exit 1; }
  local size; size=$(key TotalSize)
  [ "$size" -le $((256*1000*1000*1000)) ] || { echo "$DISK is larger than 256 GB, probably not a stick: refusing"; exit 1; }
  [ "$DISK" != "$(diskutil info / | awk -F': *' '/Part of Whole/{print $2}')" ] || { echo "$DISK holds the running system"; exit 1; }
  echo; diskutil list "$DISK"; echo "$DISK: $(key MediaName), $((size/1000/1000)) MB, $(key BusProtocol)"
}
stick_mount() {
  PART=$(diskutil list "$DISK" | awk -v l="$LABEL" '$0 ~ l {print $NF; exit}')
  [ -n "$PART" ] || { echo "no $LABEL partition on $DISK (make it once with --format)"; exit 1; }
  diskutil mount "$PART" >/dev/null 2>&1 || true
  MP=$(diskutil info "$PART" | awk -F': *' '/Mount Point/{print $2}')
  [ -n "$MP" ] && [ -d "$MP/EFI/OC" ] || { echo "$PART did not mount or has no EFI/OC"; exit 1; }
}

if [ $UNDO = 1 ]; then          # same rule as macos-install-kext.sh --undo: the newest backup comes back
  stick_check; stick_mount
  OC="$MP/EFI/OC"
  K=$(ls -1d "$OC/Kexts-backup/RyzenHV.kext."* 2>/dev/null | sort | tail -1 || true)
  C=$(ls -1 "$OC/config.plist.pre-ryzenhv-"* 2>/dev/null | sort -t- -k4 | tail -1 || true)
  [ -n "$K$C" ] || { echo "no RyzenHV backups on $MP"; exit 1; }
  if [ -n "$K" ]; then rm -rf "$OC/Kexts/RyzenHV.kext"; mv "$K" "$OC/Kexts/RyzenHV.kext"; echo "restored $(basename "$K")"; fi
  if [ -n "$C" ]; then cp "$C" "$OC/config.plist"; echo "restored $(basename "$C") -> config.plist"; fi
  $OCC -c "$OC/config.plist" check | tail -2; sync; exit 0
fi

# ---- 1. build RyzenHV with its own Makefile (it checks every imported symbol against the running kernel)
[ -f "$RHV_SRC/kext/Makefile" ] || { echo "RyzenHV sources not found at $RHV_SRC (set RYZENHV_SRC)"; exit 1; }
make -C "$RHV_SRC" kext tools >/dev/null
rm -rf build/RyzenHV.kext; cp -R "$RHV_SRC/build/RyzenHV.kext" build/RyzenHV.kext
RHV_VER=$(plutil -extract CFBundleShortVersionString raw build/RyzenHV.kext/Contents/Info.plist)
RHV_REV=$(git -C "$RHV_SRC" rev-parse --short HEAD)$(git -C "$RHV_SRC" diff --quiet HEAD -- kext include || echo "-dirty")
echo "built build/RyzenHV.kext $RHV_VER ($RHV_REV) $(shasum -a 256 build/RyzenHV.kext/Contents/MacOS/RyzenHV | cut -c1-16)"

# ---- 2. stage: a copy of the internal ESP's EFI (no backups, no other OS loaders), changed only with occonfig.py
[ -f "$ESP_EFI/OC/config.plist" ] || { echo "$ESP_EFI/OC/config.plist not found: mount the ESP (scripts/esp-automount.sh)"; exit 1; }
rm -rf "$S"; mkdir -p "$S"
rsync -a --exclude 'Microsoft/' --exclude 'limine/' --exclude '/*.kext' --exclude 'OC/Kexts-backup/' --exclude 'OC/Backup/' \
  --exclude 'OC/config.plist.*' --exclude 'ITLLOG.BIN' --exclude 'opencore-*.txt' --exclude '.*' "$ESP_EFI/" "$S/EFI/"
nvram boot-args > "$S/nvram-boot-args.txt" 2>/dev/null || true       # what NVRAM had when the stick was made
cp -R build/RyzenHV.kext "$S/EFI/OC/Kexts/"
CFG="$S/EFI/OC/config.plist"
$OCC -c "$CFG" args show | grep -q 'rhv_' && { echo "the internal config already has rhv_* boot-args: stopping"; exit 1; }
$OCC -c "$CFG" add Kernel/Add "$(printf '{"Arch":"x86_64","BundlePath":"RyzenHV.kext","Comment":"RyzenHV %s (%s): Hypervisor.framework on AMD-V, test stick only (docs/RYZENHV.md)","Enabled":true,"ExecutablePath":"Contents/MacOS/RyzenHV","MaxKernel":"25.99.99","MinKernel":"24.0.0","PlistPath":"Contents/Info.plist"}' "$RHV_VER" "$RHV_REV")" --tag "pre-ryzenhv-entry-$TS" >/dev/null
# shellcheck disable=SC2086
$OCC -c "$CFG" args add --tag "pre-ryzenhv-args-$TS" -- $RHV_ARGS >/dev/null
$OCC -c "$CFG" set Misc/Debug/Target 65 --tag "pre-ryzenhv-debug-$TS" >/dev/null
rm -f "$S/EFI/OC/config.plist.pre-ryzenhv-"*                       # staging backups: the ESP's own config is the original
/usr/bin/python3 -I -c 'import plistlib,sys; d=plistlib.load(open(sys.argv[1],"rb")); assert "boot-args" in d["NVRAM"]["Delete"][sys.argv[2]], "boot-args not in NVRAM/Delete: they would stay in NVRAM"' "$CFG" "$GUID"
$OCC -c "$CFG" check | tail -2
$OCC -c "$ESP_EFI/OC/config.plist" diff "$CFG" | grep -v '^$'
printf 'RyzenHV test stick\nstage=%s\nryzenhv=%s (%s)\nboot-args+=%s\nmade=%s\nconfig_sha_internal=%s\nconfig_sha_stick=%s\nkext_sha=%s\n' \
  "$STAGE" "$RHV_VER" "$RHV_REV" "$RHV_ARGS" "$TS" "$(shasum -a 256 "$ESP_EFI/OC/config.plist" | cut -c1-16)" \
  "$(shasum -a 256 "$CFG" | cut -c1-16)" "$(shasum -a 256 build/RyzenHV.kext/Contents/MacOS/RyzenHV | cut -c1-16)" > "$S/RHV-USB.txt"
echo "staged $S/EFI, stage $STAGE ($(du -sh "$S/EFI" | cut -f1))"
[ -n "$DISK" ] || { echo "no disk touched; next: $0 --stage $STAGE --write diskN [--format]"; exit 0; }

# ---- 3. write to the stick, after typing its name
stick_check
if [ $FORMAT = 1 ]; then echo "EVERYTHING on $DISK will be ERASED (MBR, one FAT32 partition $LABEL)."
else echo "the EFI on the $LABEL partition of $DISK is updated (old kext and config kept as backups on the stick)."; fi
read -r -p "type $DISK to go on: " A; [ "$A" = "$DISK" ] || { echo "cancelled"; exit 1; }
[ $FORMAT = 1 ] && diskutil eraseDisk FAT32 "$LABEL" MBRFormat "/dev/$DISK"
if [ $FORMAT = 1 ]; then
  PART=$(diskutil list "$DISK" | awk -v l="$LABEL" '$0 ~ l {print $NF; exit}'); diskutil mount "$PART" >/dev/null 2>&1 || true
  MP=$(diskutil info "$PART" | awk -F': *' '/Mount Point/{print $2}'); mkdir -p "$MP/EFI"
else
  stick_mount
  OC="$MP/EFI/OC"; mkdir -p "$OC/Kexts-backup"
  [ -d "$OC/Kexts/RyzenHV.kext" ] && cp -R "$OC/Kexts/RyzenHV.kext" "$OC/Kexts-backup/RyzenHV.kext.$TS"
  [ -f "$OC/config.plist" ] && cp "$OC/config.plist" "$OC/config.plist.pre-ryzenhv-$STAGE-$TS"
fi
# backups and OpenCore logs on the stick survive the update (--filter protect)
rsync -rt --delete --modify-window=2 --filter='P OC/Kexts-backup/' --filter='P OC/config.plist.*' --filter='P opencore-*.txt' \
  "$S/EFI/" "$MP/EFI/"
cp "$S/RHV-USB.txt" "$MP/"; sync
diff -rq -x Kexts-backup -x 'config.plist.*' "$S/EFI" "$MP/EFI" && echo "written and compared: $MP/EFI (stage $STAGE)"
echo "undo on the stick: $0 --undo $DISK"
