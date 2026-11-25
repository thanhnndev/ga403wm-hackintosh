#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# VCNDec install (ROOT): VP9/AV1 VideoToolbox decoder on the 890M VCN. Do not run without reading this.
# Kill switch without reinstalling: touch /Library/NullMoth/vcndec-off (CreateInstance refuses; apps decode in software).
#   sudo ./install.sh --library        copy build/VCNDec.bundle to /Library/Video/Plug-Ins (root:wheel). No reboot.
#                                      Expected: VideoToolbox REJECTS it - /Library/Video/Plug-Ins is scanned with
#                                      FigRegistry option 1 = SecStaticCodeCheckValidity against
#                                      'anchor apple or anchor apple generic and info[CFBundleIdentifier] = "com.apple."* and ...'
#                                      Run it only to confirm that gate live (vtprobe shows no com.ga403wm.vcndec.* decoder).
#   sudo ./install.sh --system         copy into /System/Library/Video/Plug-Ins on the system volume (option 0, no code
#                                      requirement) and bless a new boot snapshot, like scripts/ws-sandbox/ws-sandbox-dri.sh.
#                                      Needs authenticated-root disabled (it is). Takes effect on the NEXT BOOT; this script
#                                      does not reboot.
#   sudo ./install.sh --undo           remove from /Library/Video/Plug-Ins and put back the bundle that install replaced
#                                      (newest backup, see below); with --system too: the same on the system volume, then
#                                      bless again (next boot). --undo --purge: remove only, restore nothing.
# Backups: every install first copies the bundle it replaces to $BK/<date>-<mode>/VCNDec.bundle (outside any Plug-Ins
# directory, so VideoToolbox never scans it). --undo restores the newest one for that mode and renames it
# <date>-<mode>.restored-<date>, so a second --undo goes one version further back.
# Without rebuilding: touch /Library/NullMoth/vcndec-off (no VCN decode) or /Library/NullMoth/vcndec-noalign (0.2.1 with
# the 0.2.0 plane layout); both are read at the next session.
set -euo pipefail
cd "$(dirname "$0")"
SRC=build/VCNDec.bundle
NAME=VCNDec.bundle
LIB=/Library/Video/Plug-Ins
REL=System/Library/Video/Plug-Ins
MNT=/System/Volumes/Update/mnt1
BK=/Library/NullMoth/vcndec-backup
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
MODE=""; UNDO=0; PURGE=0
for a in "$@"; do case "$a" in --library) MODE=library;; --system) MODE=system;; --undo) UNDO=1;; --purge) PURGE=1;; *) echo "bad arg $a"; exit 1;; esac; done
[ -n "$MODE" ] || { [ $UNDO = 1 ] && MODE=library || { echo "need --library or --system"; exit 1; }; }

sysvol_mount() {
  local SNAP VOL; SNAP=$(mount | awk '$3 == "/" {print $1; exit}')
  VOL=$(echo "$SNAP" | sed -E 's/(disk[0-9]+s[0-9]+)s[0-9]+$/\1/')
  [ -b "$VOL" ] || { echo "no system volume device for $SNAP"; exit 1; }
  csrutil authenticated-root status | grep -q disabled || { echo "authenticated-root is enabled; refusing"; exit 1; }
  mkdir -p "$MNT"; mount | grep -q " on $MNT " || /sbin/mount -o nobrowse -t apfs "$VOL" "$MNT"
  echo "system volume $VOL mounted at $MNT"
}
sysvol_bless() {
  /usr/sbin/bless --folder "$MNT/System/Library/CoreServices" --bootefi --create-snapshot
  echo "new boot snapshot blessed: change is live after the next reboot"
}

# backup <dir> <mode>: copy <dir>/VCNDec.bundle aside before it is replaced
backup() {
  [ -d "$1/$NAME" ] || { echo "nothing to back up in $1"; return 0; }
  # reinstalling the same build: keep the older backup as the one --undo restores
  if cmp -s "$1/$NAME/Contents/MacOS/VCNDec" "$SRC/Contents/MacOS/VCNDec"; then echo "$1/$NAME is this build: no backup"; return 0; fi
  local D; D="$BK/$(date +%Y%m%d-%H%M%S)-$2"
  mkdir -p "$D"; ditto "$1/$NAME" "$D/$NAME"
  echo "backed up $1/$NAME ($(defaults read "$1/$NAME/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo '?')) to $D"
}
# restore <dir> <mode>: put the newest backup for <mode> back into <dir>; returns 1 if there is none
restore() {
  local D; D=$(ls -1d "$BK"/*-"$2" 2>/dev/null | sort | tail -1)
  [ -n "$D" ] && [ -d "$D/$NAME" ] || { echo "no backup for $2 in $BK: decoder removed, nothing restored"; return 1; }
  ditto "$D/$NAME" "$1/$NAME"; chown -R root:wheel "$1/$NAME"; chmod -R go-w "$1/$NAME"
  mv "$D" "$D.restored-$(date +%Y%m%d-%H%M%S)"
  echo "restored $1/$NAME ($(defaults read "$1/$NAME/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo '?')) from $D"
}

if [ $UNDO = 1 ]; then
  rm -rf "$LIB/$NAME" && echo "removed $LIB/$NAME (if it was there)"
  [ $PURGE = 1 ] || [ "$MODE" = system ] || restore "$LIB" library || true
  if [ "$MODE" = system ]; then
    sysvol_mount; rm -rf "$MNT/$REL/$NAME"; echo "removed $MNT/$REL/$NAME"
    [ $PURGE = 1 ] || restore "$MNT/$REL" system || true
    sysvol_bless
  fi
  killall VTDecoderXPCService 2>/dev/null || true
  exit 0
fi

[ -d "$SRC" ] || { echo "build first: ./build.sh"; exit 1; }
codesign -v "$SRC" || { echo "bundle signature invalid"; exit 1; }
if [ "$MODE" = library ]; then
  mkdir -p "$LIB"; backup "$LIB" library; rm -rf "$LIB/$NAME"; ditto "$SRC" "$LIB/$NAME"
  chown -R root:wheel "$LIB/$NAME"; chmod -R go-w "$LIB/$NAME"
  echo "installed $LIB/$NAME"; ls -la "$LIB"
else
  sysvol_mount
  backup "$MNT/$REL" system; rm -rf "$MNT/$REL/$NAME"; ditto "$SRC" "$MNT/$REL/$NAME"
  chown -R root:wheel "$MNT/$REL/$NAME"; chmod -R go-w "$MNT/$REL/$NAME"
  echo "installed $MNT/$REL/$NAME"
  sysvol_bless
fi
killall VTDecoderXPCService 2>/dev/null || true   # it caches the registry; respawns on demand
