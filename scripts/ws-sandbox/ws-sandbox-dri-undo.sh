#!/bin/bash
# Undo ws-sandbox-dri.sh: boot the last sealed system snapshot again (sudo, then reboot).
set -eu
SNAP=$(mount | awk '$3 == "/" {print $1; exit}'); VOL=$(echo "$SNAP" | sed -E 's/(disk[0-9]+s[0-9]+)s[0-9]+$/\1/')
MNT=/System/Volumes/Update/mnt1; mkdir -p "$MNT"
mount | grep -q " on $MNT " || mount -o nobrowse -t apfs "$VOL" "$MNT"
bless --mount "$MNT" --bootefi --last-sealed-snapshot
echo "last sealed snapshot blessed; reboot"
