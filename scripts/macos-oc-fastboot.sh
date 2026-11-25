#!/usr/bin/env bash
# OpenCore boot-time edits from docs/BOOT-TIMELINE.md section 3 (items 2 and 3). Two keys in EFI/OC/config.plist:
#
#   Kernel/Quirks/SetApfsTrimTimeout  -1 -> 0      on macOS 12+ only 0 has an effect: it skips the APFS boot trim
#                                                  (3.5-4.4 s on the critical path before launchd). Free space is still
#                                                  trimmed by the OS at runtime; -1 = untouched (Apple default).
#   Misc/Boot/ShowPicker              true -> false skips the 2 s picker Timeout; hold Esc (or Option/Alt, or 0) from
#                                                  power-on to get the picker for Linux/Windows.
#
# Run as your user (the ESP is mounted user-owned at /Volumes/ESP); no sudo. Takes effect at the next reboot.
#
#   scripts/macos-oc-fastboot.sh             back up config.plist, set both keys, validate, print the result
#   scripts/macos-oc-fastboot.sh --trim-only only SetApfsTrimTimeout (keep the picker)
#   scripts/macos-oc-fastboot.sh --status    current values and the newest backup
#   scripts/macos-oc-fastboot.sh --undo      put back the values recorded at apply time (only these two keys)
#   add --dry to print what would change and write nothing.
#
# Picker hotkeys (checked 2026-11-19 from config.plist, the ESP OpenCore logs and the OpenCore docs): KeySupport true
# (AppleInputKit on the firmware ConIn, "AIK: Using 5 (50ms)"), PollAppleHotKeys true, PickerMode Builtin, TakeoffDelay 0,
# KeyForgetThreshold 5. All 19 logged boots initialised hotkeys (OCHK: InitHotKeys), and 4 boots were steered to Limine or
# Windows from the picker, so the built-in keyboard reaches OpenCore. Whether a HELD key is seen with ShowPicker false is
# not proven by any log (every logged boot had the picker on). OpenCore accepts Esc, Option and 0; Esc is the one meant
# for keyboards that do not report a held Option (PS/2-style). If holding does not work, tap Esc repeatedly from power-on.
# Test once right after applying, before relying on it; if it fails, --undo (or raise Misc/Boot/TakeoffDelay to 5000).
set -eu
ESP=/Volumes/ESP
CFG=${OC_CONFIG:-$ESP/EFI/OC/config.plist}       # OC_CONFIG: test on a copy
PB=/usr/libexec/PlistBuddy
OCV=${OCVALIDATE:-$HOME/.cache/ga403/bin/ocvalidate}
MODE=apply DRY=0 TRIM_ONLY=0
for a in "$@"; do
  case $a in
    --status) MODE=status ;; --undo) MODE=undo ;; --dry) DRY=1 ;; --trim-only) TRIM_ONLY=1 ;;
    *) echo "unknown option $a"; exit 2 ;;
  esac
done
[[ -f $CFG ]] || { echo "$CFG not found; ESP not mounted at $ESP (scripts/esp-automount.sh)"; exit 1; }

get() { $PB -c "Print :$1" "$CFG" 2>/dev/null || echo "(missing)"; }
newest_backup() { ls -t "$CFG".pre-fastboot-2* 2>/dev/null | grep -v "\.values$" | head -1 || true; }
show() {
  echo "Kernel/Quirks/SetApfsTrimTimeout = $(get Kernel:Quirks:SetApfsTrimTimeout)"
  echo "Misc/Boot/ShowPicker             = $(get Misc:Boot:ShowPicker)"
  echo "Misc/Boot/Timeout                = $(get Misc:Boot:Timeout)"
  echo "Misc/Boot/TakeoffDelay           = $(get Misc:Boot:TakeoffDelay)"
  echo "UEFI/Input/KeySupport            = $(get UEFI:Input:KeySupport)   KeyForgetThreshold = $(get UEFI:Input:KeyForgetThreshold)"
}
validate() {
  /usr/bin/plutil -lint "$CFG" >/dev/null || { echo "plutil: config.plist is not valid"; return 1; }
  if [[ -x $OCV ]]; then "$OCV" "$CFG" | tail -3; else echo "ocvalidate not built ($OCV); plutil -lint passed"; fi
}
setkey() {   # path type value
  local cur; cur=$(get "$1")
  if [[ $cur == "$3" ]]; then echo "$1 already $3"; return; fi
  echo "$1: $cur -> $3"
  [[ $DRY == 1 ]] && return
  if [[ $cur == "(missing)" ]]; then $PB -c "Add :$1 $2 $3" "$CFG"; else $PB -c "Set :$1 $3" "$CFG"; fi
}

case $MODE in
status)
  show
  b=$(newest_backup); echo "newest backup: ${b:-none}"
  [[ -n $b && -f $b.values ]] && echo "recorded old values: $(tr '\n' ' ' < "$b.values")"
  ;;
apply)
  echo "before:"; show
  TS=$(date +%Y%m%d-%H%M%S); BK=$CFG.pre-fastboot-$TS
  if [[ $DRY == 0 ]]; then
    cp -p "$CFG" "$BK"
    printf 'SetApfsTrimTimeout=%s\nShowPicker=%s\n' "$(get Kernel:Quirks:SetApfsTrimTimeout)" "$(get Misc:Boot:ShowPicker)" > "$BK.values"
    echo "backup: $BK"
  fi
  setkey Kernel:Quirks:SetApfsTrimTimeout integer 0
  [[ $TRIM_ONLY == 1 ]] || setkey Misc:Boot:ShowPicker bool false
  if [[ $DRY == 0 ]]; then
    validate || { cp -p "$BK" "$CFG"; echo "validation failed: restored $BK"; exit 1; }
    echo "after:"; show
    echo "takes effect at the next reboot. Undo: scripts/macos-oc-fastboot.sh --undo (or cp '$BK' '$CFG')"
  fi
  ;;
undo)
  b=$(newest_backup)
  [[ -n $b && -f $b.values ]] || { echo "no recorded apply (no $CFG.pre-fastboot-*.values)"; exit 1; }
  trim=$(sed -n 's/^SetApfsTrimTimeout=//p' "$b.values"); pick=$(sed -n 's/^ShowPicker=//p' "$b.values")
  echo "restoring the values recorded in $b.values (other keys are left as they are now)"
  [[ $DRY == 0 ]] && cp -p "$CFG" "$CFG.pre-fastboot-undo-$(date +%Y%m%d-%H%M%S)"
  [[ $trim == "(missing)" ]] && trim=-1
  setkey Kernel:Quirks:SetApfsTrimTimeout integer "$trim"
  [[ $pick == "(missing)" ]] || setkey Misc:Boot:ShowPicker bool "$pick"
  if [[ $DRY == 0 ]]; then validate; show; fi
  ;;
esac
