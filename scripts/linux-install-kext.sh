#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Installs a kext that was built on macOS into the ESP from Linux. RUN ON LINUX, no sudo (after setup-linux-access.sh).
# Needed because macOS cannot mount the ESP while ItlDiag holds it open for ITLLOG.BIN.
#   bash scripts/linux-install-kext.sh itlmt7925           install <repo on the macOS volume>/build/itlmt7925.kext
#   bash scripts/linux-install-kext.sh --undo itlmt7925    put the newest backup back
# The source is read from the macOS Data volume (mount /mnt/macos-vol0, read-only). Backups go to /boot/EFI/OC/Kexts-backup/.
# For itlmt7925 the Wi-Fi credentials (itl_ssid*/itl_psk*) of the installed kext are carried over; they are never printed.
set -euo pipefail
UNDO=0; [ "${1:-}" = "--undo" ] && { UNDO=1; shift; }
NAME="${1:?kext name, e.g. itlmt7925}"
ESP=${ESP:-/boot}
K="$ESP/EFI/OC/Kexts"; B="$ESP/EFI/OC/Kexts-backup"
[ -d "$K" ] && [ -w "$K" ] || { echo "$K missing or not writable (run scripts/setup-linux-access.sh once)"; exit 1; }

if [ $UNDO = 1 ]; then
  LAST=$(ls -1d "$B/$NAME.kext."* 2>/dev/null | sort | tail -1)
  [ -n "$LAST" ] || { echo "no backup of $NAME in $B"; exit 1; }
  rm -rf "$K/$NAME.kext"; mv "$LAST" "$K/$NAME.kext"; sync
  echo "restored $(basename "$LAST")"; exit 0
fi

MV=${MV:-/mnt/macos-vol0}
# The Data volume may already be mounted somewhere else (the mount points have moved between sessions); reuse it instead of
# trying to mount it a second time, which fails with "already mounted" (and used to abort the install under set -e).
if ! mountpoint -q "$MV"; then
  MV_ALT=$(findmnt -rn -S /dev/nvme0n1p4 -o TARGET 2>/dev/null | head -1 || true)
  if [ -n "$MV_ALT" ]; then MV=$MV_ALT; else mount "$MV"; fi
fi
SRC=${SRC:-$(ls -d "$MV"/Users/*/develop/projects/ga403wm-hackintosh/build/"$NAME".kext 2>/dev/null | head -1)}
[ -n "$SRC" ] && [ -f "$SRC/Contents/MacOS/$NAME" ] || { echo "no built $NAME.kext on the macOS volume (set SRC=...)"; exit 1; }
echo "source: $SRC ($(stat -c %y "$SRC/Contents/MacOS/$NAME" | cut -d. -f1))"
grep -q "<string>$NAME.kext</string>" "$ESP/EFI/OC/config.plist" || echo "WARNING: $NAME.kext is not in config.plist Kernel/Add"

STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
cp -r "$SRC" "$STAGE/"
if [ "$NAME" = itlmt7925 ] && [ -f "$K/$NAME.kext/Contents/Info.plist" ]; then
  n=$(python3 -I - "$K/$NAME.kext/Contents/Info.plist" "$STAGE/$NAME.kext/Contents/Info.plist" <<'PY'
import plistlib, sys
old = plistlib.load(open(sys.argv[1], "rb"))["IOKitPersonalities"]["itlmt7925"]
with open(sys.argv[2], "rb") as f: new = plistlib.load(f)
per = new["IOKitPersonalities"]["itlmt7925"]; n = 0
for k in ("itl_ssid", "itl_psk", "itl_ssid2", "itl_psk2", "itl_ssid3", "itl_psk3", "itl_ssid4", "itl_psk4"):
    if isinstance(old.get(k), str) and old[k]: per[k] = old[k]; n += 1
with open(sys.argv[2], "wb") as f: plistlib.dump(new, f)
print(n)
PY
)
  echo "credentials carried over: $n key(s)"
fi
mkdir -p "$B"
TS=$(date +%Y%m%d-%H%M%S)
[ -d "$K/$NAME.kext" ] && mv "$K/$NAME.kext" "$B/$NAME.kext.$TS"
cp -r "$STAGE/$NAME.kext" "$K/"
sync
echo "installed $K/$NAME.kext (old one: $B/$NAME.kext.$TS). Undo: bash $0 --undo $NAME"
