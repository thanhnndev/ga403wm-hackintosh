#!/usr/bin/env bash
# Remove the 120 Hz display override that scripts/install-display-override.sh put on the macOS Data volume. Run with sudo.
#
#   sudo bash scripts/remove-display-override.sh
#
# Why: NullMoth driver 1.10.0 offers DisplayID-only modes (120 Hz) itself (docs/NULLMOTH.md), so the override is no longer
# wanted. It was the only thing the old installer added to macOS, apart from deleting the pinned WindowServer prefs
# (those were backed up to ~/ga403-macos-backup-*; WindowServer rebuilds them, do not restore them).
#
# What it changes (APFS volume 0, mounted read-write for the duration):
#   - /Library/Displays/Contents/Resources/Overrides/DisplayVendorID-4c83   (only this directory)
# Write support is linux-apfs-rw (experimental, needs the "readwrite" mount option). The script refuses to continue if the
# volume does not mount read-write, runs a read-only apfsck afterwards and remounts the volume read-only.
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
APFS_DEV=${APFS_DEV:-/dev/nvme0n1p4}
MP=/mnt/macos-vol0
OVR_REL="Library/Displays/Contents/Resources/Overrides/DisplayVendorID-4c83"
modprobe apfs || { echo "modprobe apfs failed"; exit 1; }

echo "== 1. unmount every APFS mount of $APFS_DEV =="
for m in /mnt/macos-vol[0-9]*; do mountpoint -q "$m" && umount "$m" && echo "umount $m"; done
mountpoint -q "$MP" && { echo "could not unmount $MP (cd out of it?)"; exit 1; }

echo "== 2. mount the Data volume read-write =="
mkdir -p "$MP"
if ! mount -t apfs -o readwrite,readwrite,vol=0 "$APFS_DEV" "$MP"; then
  echo "rw mount failed (volume not cleanly unmounted, or no write support). dmesg:"; dmesg | tail -5
  mount -t apfs -o ro,vol=0,uid="${SUDO_UID:-1000}",gid="${SUDO_GID:-1000}" "$APFS_DEV" "$MP"
  echo "NOTHING was changed. Boot macOS once and shut it down cleanly, then retry."
  exit 1
fi
grep -q " $MP .*[ ,(]rw[ ,)]" /proc/mounts || { echo "mounted, but not rw"; umount "$MP"; exit 1; }
[ -d "$MP/Library/Preferences" ] || { echo "$MP does not look like the macOS Data volume"; umount "$MP"; exit 1; }

echo "== 3. remove the override =="
if [ -d "$MP/$OVR_REL" ]; then rm -rfv "$MP/$OVR_REL"; else echo "not present, nothing to remove"; fi

echo "== 4. flush, unmount, read-only consistency check =="
sync
umount "$MP" || { echo "umount failed"; exit 1; }
if command -v apfsck >/dev/null; then
  apfsck "$APFS_DEV" && echo "apfsck: clean" || echo "apfsck reported problems (see above); do NOT boot macOS before looking at it"
else
  echo "apfsck not installed (apfsprogs), skipped"
fi
mount -t apfs -o ro,vol=0,uid="${SUDO_UID:-1000}",gid="${SUDO_GID:-1000}" "$APFS_DEV" "$MP" && echo "remounted $MP read-only"
echo "== done =="
