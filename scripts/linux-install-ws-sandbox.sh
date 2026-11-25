#!/bin/bash
# Arm the one-shot com.itlmt7925.ws-sandbox-dri daemon on the macOS Data volume from Linux (pkexec). The next macOS boot
# adds /dev/dri to WindowServer's sandbox profile, blesses a new system snapshot and reboots by itself.
# Linux apfs (linux-apfs-rw) needs "readwrite": plain "rw" mounts read-only ("experimental writes disabled").
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); DEV=${DEV:-/dev/nvme0n1p4}; MNT=${MNT:-/mnt/macos-vol0}
mkdir -p "$MNT"; mountpoint -q "$MNT" && umount "$MNT"
mount -t apfs -o readwrite,uid=0,gid=0,vol=0 "$DEV" "$MNT"
install -o 0 -g 0 -m 755 "$HERE/ws-sandbox/ws-sandbox-dri.sh" "$HERE/ws-sandbox/ws-sandbox-dri-undo.sh" "$MNT/Library/StrixGraphicsFix/"
install -o 0 -g 0 -m 644 "$HERE/ws-sandbox/com.itlmt7925.ws-sandbox-dri.plist" "$MNT/Library/LaunchDaemons/"
rm -f "$MNT/Library/StrixGraphicsFix/ws-sandbox-dri.done" "$MNT/Library/StrixGraphicsFix/ws-sandbox-dri.status"
sync; umount "$MNT"; echo "armed: boot macOS once; it patches, snapshots and reboots by itself"
