#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Keeps the (still incomplete) NullMoth Metal device away from the system UI.
#
# ROOT CAUSE, decoded from NVMTLDriver (0x1e61..0x256a, 2026-10-17):
#   * decision order: process "WindowServer" (hardcoded, no device unless the vendor is NVIDIA and
#     debug.nvaccel_headless says otherwise) -> NVMTL_ENABLE env var -> hardcoded tools (mtlprobe, nvmtltest,
#     nvmtlrender always get one) -> /Library/GPUBundles/nvmtl-allow.txt, else /Library/Extensions/nvmtl-allow.txt.
#   * line grammar of that file:
#       #...       comment
#       -Name      DENY      (hard: sets the deny state and stops reading, so it beats "*")
#       *          allow every process
#       Name       allow only this process
#       !Name / !* "armed-only": allowed only while `sysctl debug.nvaccelfb != 0` (that is what the line
#                  "!WindowServer" in the shipped file does - it is NOT a deny).
#   * so the shipped rung 3 ("*" + "!WindowServer") hands the Metal device to every process, including
#     SecurityAgent. Its RenderBox aborts in RB::Device::make_index_buffer() -> RB::precondition_failure, launchd
#     restarts it every 10 s and the login window crash-loops (23 crashes, 2026-10-17 18:23 boot, uptime 42..270 s).
#
# RUN ON LINUX AS ROOT (macOS is not needed, the Data volume just has to go read-write).
#   sudo bash scripts/linux-nvmtl-allowlist.sh          deny the system UI (backup first)
#   sudo bash scripts/linux-nvmtl-allowlist.sh --undo   restore the newest backup
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run this script with sudo.'; exit 1; }

DEV=/dev/nvme0n1p4
MP=/mnt/macos-data
REL=Library/GPUBundles/nvmtl-allow.txt
BACKUPS=/Library/NullMoth

# The login window first (that is what makes the machine unbootable), then the session UI: a crash-loop in any of
# these makes the desktop unusable, and none of them needs the test driver.
DENY=(SecurityAgent loginwindow Dock Finder SystemUIServer NotificationCenter ControlCenter CoreServicesUIAgent)

UNDO=0
[ "${1:-}" = "--undo" ] && UNDO=1

mkdir -p "$MP"
cleanup() {
    rc=$?
    if mountpoint -q "$MP"; then sync; umount "$MP" || true; fi
    mount -t apfs -o "ro,vol=0,uid=${SUDO_UID:-1000},gid=${SUDO_GID:-1000}" "$DEV" "$MP" 2>/dev/null || true
    exit $rc
}
trap cleanup EXIT

for _ in 1 2 3 4 5 6 7 8; do
    targets=$(findmnt -rn -S "$DEV" -o TARGET 2>/dev/null | sort -u || true)
    [ -n "$targets" ] || break
    while IFS= read -r t; do umount "$t" || true; done <<< "$targets"
done
echo "mounting $DEV rw at $MP ..."
mount -t apfs -o rw,readwrite,vol=0 "$DEV" "$MP"
opts=$(findmnt -rn -T "$MP" -o OPTIONS 2>/dev/null || true)
if ! printf '%s\n' "$opts" | tr ',' '\n' | grep -qx rw; then
    echo "FATAL: $MP came up as '$opts' (need rw). Another mount of the container is probably still there:"
    echo "       findmnt -rn -S $DEV -o TARGET"
    exit 1
fi
[[ -f "$MP/$REL" ]] || { echo "FATAL: $MP/$REL not found"; exit 1; }

if [ $UNDO = 1 ]; then
    LAST=$(ls -1dt "$MP/$BACKUPS"/backup-*/nvmtl-allow.txt 2>/dev/null | head -1 || true)
    [ -n "$LAST" ] || { echo "no nvmtl-allow.txt backup under $BACKUPS/backup-*"; exit 1; }
    echo "restoring from ${LAST#"$MP/"}"
    cp -f "$LAST" "$MP/$REL"
else
    ts=$(date +%Y%m%d-%H%M%S)
    bdir="$MP/$BACKUPS/backup-$ts"
    mkdir -p "$bdir"
    cp "$MP/$REL" "$bdir/nvmtl-allow.txt"
    chown 0:0 "$bdir" "$bdir/nvmtl-allow.txt" 2>/dev/null || true
    echo "backed up -> ${bdir#"$MP/"}/nvmtl-allow.txt"
    echo "--- before ---"; cat "$MP/$REL"
    for name in "${DENY[@]}"; do
        grep -qxF -- "-$name" "$MP/$REL" || echo "-$name" >> "$MP/$REL"
    done
fi

chown 0:0 "$MP/$REL" 2>/dev/null || true
chmod 644 "$MP/$REL"
sync
echo "--- after ---"; cat "$MP/$REL"
echo
echo "Denies are '-' (hard), NOT '!' (that one is armed-only: it lifts while debug.nvaccelfb != 0)."
echo "Next boot: the login window and the session UI fall back to Apple's renderer; the hardcoded tools"
echo "(mtlprobe/nvmtltest/nvmtlrender) and any process you leave allowed still get the nvmtl Metal device."
