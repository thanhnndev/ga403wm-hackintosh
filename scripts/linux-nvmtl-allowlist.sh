#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
#
# Keep the (still incomplete) NullMoth Metal device away from processes whose RenderBox aborts.
#
# DECODED FROM NVMTLDriver (`-[NVMTLDevice initWithAcceleratorPort:]`, 2026-10-17) - the whole
# decision, in order:
#   1. name == "WindowServer"                  -> "headless GPU: no device" unless the display owner is NVIDIA.
#   2. getenv("NVMTL_ENABLE") != NULL          -> give the device, skip the allow list entirely.
#   3. name in {mtlprobe, nvmtltest, nvmtlrender} -> give the device (hardcoded, allow list is not consulted).
#   4. open /Library/GPUBundles/nvmtl-allow.txt, else /Library/Extensions/nvmtl-allow.txt.
#      Unreadable -> "no allow-list readable ... no device".
#   5. line grammar (first char switch table at 0x25ec, handlers 0x23c4/0x23cc/0x23da/0x2438):
#        #...        comment                 -> keep scanning
#        <blank>     blank                   -> keep scanning
#        -Name       DENY (hard)             -> stop scanning, no device
#        *           allow every process     -> stop scanning, device
#        Name        allow this process only -> stop scanning, device
#        !Name / !*  "armed-only"            -> stop scanning; device only while
#                                               `sysctl debug.nvaccelfb != 0`, else no device
#   6. **THE SCAN STOPS AT THE FIRST LINE THAT DECIDES** (0x2360: `cmp ebx,2 ; jne 0x254d`).
#      Therefore every `-Name` line must sit ABOVE the `*` line - a `-Name` below `*` is dead code,
#      which is exactly why the shipped file (`*` on line 2, `!WindowServer` below) handed the device
#      to SecurityAgent: its RenderBox aborts in RB::Device::make_index_buffer() (RB::precondition_failure),
#      launchd restarts it every 10 s and the login window crash-loops (2026-10-17 18:23 + 20:17 boots).
#
# RUN ON LINUX AS ROOT (no macOS needed, the Data volume only has to go read-write):
#   sudo bash scripts/linux-nvmtl-allowlist.sh            rung 1: only the hardcoded tools get the device
#   sudo bash scripts/linux-nvmtl-allowlist.sh --rung3    rung 3: everyone except the system UI below
#   sudo bash scripts/linux-nvmtl-allowlist.sh --undo     restore the newest backup
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run this script with sudo.'; exit 1; }

DEV=/dev/nvme0n1p4
MP=/mnt/macos-data
REL=Library/GPUBundles/nvmtl-allow.txt
BACKUPS=/Library/NullMoth

MODE=rung1
case "${1:-}" in
    --rung3) MODE=rung3 ;;
    --undo)  MODE=undo ;;
    '')      ;;
    *) echo "usage: $0 [--rung3|--undo]"; exit 2 ;;
esac

# rung 3 only: system UI that must NOT see the device (login window first, then the session UI).
DENY=(SecurityAgent loginwindow Dock Finder SystemUIServer NotificationCenter ControlCenter CoreServicesUIAgent)

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
    while IFS= read -r t; do [ -n "$t" ] && umount "$t" || true; done <<< "$targets"
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

if [ "$MODE" = undo ]; then
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
    if [ "$MODE" = rung3 ]; then
        # Denies MUST come before '*': the scan stops at the first line that decides.
        {
            echo '# rung 3: everyone; -Name lines MUST stay above the * line (scan stops at the first decision)'
            for name in "${DENY[@]}"; do echo "-$name"; done
            echo '*'
        } > "$MP/$REL"
    else
        # Rung 1: no '*' at all -> every process that is not the hardcoded tool is denied.
        {
            echo '# rung 1: only the driver-hardcoded tools (mtlprobe, nvmtltest, nvmtlrender) get the device.'
            echo '# Add a bare process name below to let that one app test the device (it will abort until'
            echo '# the driver passes RB::Device::make_index_buffer()). Never add a * line: it would kill'
            echo '# every -Name deny below it and hand the device to the login window again.'
        } > "$MP/$REL"
    fi
fi

chown 0:0 "$MP/$REL" 2>/dev/null || true
chmod 644 "$MP/$REL"
sync
echo "--- after ---"; cat "$MP/$REL"
echo
if grep -q '^\*' "$MP/$REL"; then
    star=$(grep -n '^\*' "$MP/$REL" | head -1 | cut -d: -f1)
    if awk -v s="$star" 'NR>s && /^-/' "$MP/$REL" | grep -q .; then
        echo "WARNING: there is a -Name deny BELOW the '*' line at line $star - dead code, move it up." >&2
    fi
else
    echo "Nobody but the hardcoded tools gets the nvmtl Metal device (login window + all apps use Apple's renderer)."
fi
echo "Note: '!Name' is NOT a deny - it is 'armed-only' (device only while debug.nvaccelfb != 0). Use '-Name'."
