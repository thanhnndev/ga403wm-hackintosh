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
#   sudo ./install.sh --undo           remove from /Library/Video/Plug-Ins; with --system too: remove from the system
#                                      volume and bless again (next boot).
set -euo pipefail
cd "$(dirname "$0")"
SRC=build/VCNDec.bundle
NAME=VCNDec.bundle
LIB=/Library/Video/Plug-Ins
REL=System/Library/Video/Plug-Ins
MNT=/System/Volumes/Update/mnt1
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
MODE=""; UNDO=0
for a in "$@"; do case "$a" in --library) MODE=library;; --system) MODE=system;; --undo) UNDO=1;; *) echo "bad arg $a"; exit 1;; esac; done
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

if [ $UNDO = 1 ]; then
  rm -rf "$LIB/$NAME" && echo "removed $LIB/$NAME (if it was there)"
  if [ "$MODE" = system ]; then sysvol_mount; rm -rf "$MNT/$REL/$NAME"; echo "removed $MNT/$REL/$NAME"; sysvol_bless; fi
  killall VTDecoderXPCService 2>/dev/null || true
  exit 0
fi

[ -d "$SRC" ] || { echo "build first: ./build.sh"; exit 1; }
codesign -v "$SRC" || { echo "bundle signature invalid"; exit 1; }
if [ "$MODE" = library ]; then
  mkdir -p "$LIB"; rm -rf "$LIB/$NAME"; ditto "$SRC" "$LIB/$NAME"
  chown -R root:wheel "$LIB/$NAME"; chmod -R go-w "$LIB/$NAME"
  echo "installed $LIB/$NAME"; ls -la "$LIB"
else
  sysvol_mount
  rm -rf "$MNT/$REL/$NAME"; ditto "$SRC" "$MNT/$REL/$NAME"
  chown -R root:wheel "$MNT/$REL/$NAME"; chmod -R go-w "$MNT/$REL/$NAME"
  echo "installed $MNT/$REL/$NAME"
  sysvol_bless
fi
killall VTDecoderXPCService 2>/dev/null || true   # it caches the registry; respawns on demand
