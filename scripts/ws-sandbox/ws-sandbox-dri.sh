#!/bin/bash
# One-shot, run as root by com.itlmt7925.ws-sandbox-dri at the first macOS boot after the Linux-side install.
# WindowServer's sandbox (com.apple.WindowServer.sb) denies file-write-data and file-ioctl on /dev/dri, so NullMoth's RADV
# (libdrm opens /dev/dri/renderD128) finds zero GPUs in WindowServer, the plugin refuses to be its Metal device and
# CoreDisplay asserts "Failed to create MetalDevice" (2026-10-29 boots B3DB718A/6D70212A). This adds one rule for /dev/dri
# to that profile on the system volume and blesses a new boot snapshot, as OpenCore Legacy Patcher does
# (csr-active-config 0x0A43 carries CSR_ALLOW_UNAUTHENTICATED_ROOT). The running system keeps the old snapshot, so the
# script reboots once when the snapshot is made. Undo: ws-sandbox-dri-undo.sh (boots the last sealed snapshot again).
set -u
LABEL=com.itlmt7925.ws-sandbox-dri
ROOT=/Library/StrixGraphicsFix
MARK=';; NMX GA403WM: RADV reaches the Radeon 890M through the DRM nodes'
RULE='(allow file-read* file-write* file-ioctl (subpath "/dev/dri"))'
REL=System/Library/Sandbox/Profiles/com.apple.WindowServer.sb
MNT=/System/Volumes/Update/mnt1
mkdir -p "$ROOT"
exec >>"$ROOT/ws-sandbox-dri.log" 2>&1
echo "== $(date '+%F %T')"
set -x
cd /
finish() {   # $1 = status line; the daemon removes itself whatever happened, so a failure never loops
    echo "$1" | tee "$ROOT/ws-sandbox-dri.status"
    /bin/launchctl disable "system/$LABEL" 2>/dev/null
    /bin/rm -f "/Library/LaunchDaemons/$LABEL.plist"
}
[ -f "$ROOT/ws-sandbox-dri.done" ] && { finish "already done"; exit 0; }
if grep -qF "$MARK" "/$REL"; then date -u >"$ROOT/ws-sandbox-dri.done"; finish "PATCHED (already in the booted snapshot)"; exit 0; fi
sleep 5
csrutil status
csrutil authenticated-root status

# / is a snapshot of the system volume (diskNsMsK); the writable volume is its parent diskNsM
SNAP=$(mount | awk '$3 == "/" {print $1; exit}')
VOL=$(echo "$SNAP" | sed -E 's/(disk[0-9]+s[0-9]+)s[0-9]+$/\1/')
echo "root snapshot $SNAP, system volume $VOL"
[ -b "$VOL" ] || { finish "FAILED: no system volume device ($SNAP)"; exit 0; }
mkdir -p "$MNT"
mount | grep -q " on $MNT " || /sbin/mount -o nobrowse -t apfs "$VOL" "$MNT" || { finish "FAILED: mount $VOL"; exit 0; }
P="$MNT/$REL"
[ -f "$P" ] || { finish "FAILED: no $P"; exit 0; }
BK=/Library/NullMoth/ws-sandbox-$(date -u +%Y%m%dT%H%M%SZ); mkdir -p "$BK"; cp -p "$P" "$BK/"
echo "backup=$BK"

if ! grep -qF "$MARK" "$P"; then
    T=$(mktemp /private/tmp/ws.sb.XXXX)
    { cat "$P"; printf '\n%s\n%s\n' "$MARK" "$RULE"; } >"$T"
    # the patched profile must compile exactly as well as the original (same sandbox-exec result with the same params)
    D="-D HOME=/var/empty -D TMPDIR=/private/tmp -D DARWIN_CACHE_DIR=/private/tmp"
    /usr/bin/sandbox-exec $D -f "$P" /usr/bin/true; r0=$?
    /usr/bin/sandbox-exec $D -f "$T" /usr/bin/true; r1=$?
    echo "sandbox-exec original=$r0 patched=$r1"
    [ "$r0" = "$r1" ] || { rm -f "$T"; /sbin/umount "$MNT"; finish "FAILED: patched profile does not compile like the original"; exit 0; }
    cat "$T" >"$P"; rm -f "$T"
fi
tail -3 "$P"

/usr/sbin/bless --folder "$MNT/System/Library/CoreServices" --bootefi --create-snapshot; rb=$?
echo "bless_exit=$rb"
if [ $rb != 0 ]; then finish "FAILED: bless --create-snapshot $rb (boot snapshot unchanged)"; exit 0; fi
date -u >"$ROOT/ws-sandbox-dri.done"
finish "SNAPSHOT MADE: WindowServer may open /dev/dri from the next boot; rebooting"
sync; /sbin/shutdown -r now
exit 0
