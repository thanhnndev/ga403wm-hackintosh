#!/usr/bin/env bash
# Apply a reviewed graphics deployment package prepared from the CURRENT ESP
# binaries. The package's config disables their duplicate BootKC injection;
# native kernelmanagerd links them against BootKC + SystemKC in AuxKC.
# Usage: sudo bash scripts/linux-fix-strix-graphics.sh /absolute/package/path
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run this script with sudo.'; exit 1; }
PACKAGE=$(realpath "${1:?prepared package directory}")
DEV=/dev/nvme0n1p4
MP=/mnt/macos-vol0
ESP=/boot
BOOTSTRAP=$(dirname "$(realpath "$0")")/macos-strix-graphics-bootstrap.sh
[[ -f "$BOOTSTRAP" ]] || { echo 'Missing macOS bootstrap script.'; exit 1; }

python3 - "$PACKAGE" "$ESP" "$BOOTSTRAP" <<'PY'
import hashlib,json,pathlib,sys
p,e,b=map(pathlib.Path,sys.argv[1:])
m=json.loads((p/'manifest.json').read_text())
digest=lambda f: hashlib.sha256(f.read_bytes()).hexdigest()
assert digest(e/'EFI/OC/config.plist')==m['original_config_sha256'], 'ESP config changed; regenerate the package'
assert digest(b)==m['bootstrap_sha256'], 'Bootstrap changed; regenerate the package'
for rel,h in m['files'].items():
    f=p/rel
    assert f.resolve().is_relative_to(p), 'Package path escapes directory'
    assert digest(f)==h, f'Package hash mismatch: {rel}'
print('Package and original ESP config hashes verified.')
PY

mkdir -p "$PACKAGE/data-before"
finish() {
    if mountpoint -q "$MP"; then sync; umount "$MP" || return; fi
    mount -t apfs -o "ro,vol=0,uid=${SUDO_UID:-1000},gid=${SUDO_GID:-1000}" "$DEV" "$MP"
}
# linux-apfs-rw requires one mount of the container while writing.
while IFS= read -r target; do umount "$target"; done < <(findmnt -rn -S "$DEV" -o TARGET)
trap finish EXIT
mount -t apfs -o rw,readwrite,vol=0 "$DEV" "$MP"
findmnt -rn -T "$MP" -o OPTIONS | tr ',' '\n' | grep -qx rw
[[ -d "$MP/Library/Extensions" && -d "$MP/private/var/db/diagnostics" ]]

for name in NVRM NVRMEdpBL NVRMFB NVRMAGDC NVAccel StrixAccel StrixGOP; do
    dst="$MP/Library/Extensions/$name.kext"
    [[ ! -e "$dst" ]] || cp -a "$dst" "$PACKAGE/data-before/"
    tmp="$MP/Library/Extensions/.$name.strix-install"
    [[ ! -e "$tmp" ]] || { echo "Unexpected staging directory: $tmp"; exit 1; }
    cp -a "$PACKAGE/Extensions/$name.kext" "$tmp"
    chown -hR 0:0 "$tmp"
    find "$tmp" -type d -exec chmod 755 {} +
    find "$tmp" -type f -exec chmod 644 {} +
    chmod 755 "$tmp/Contents/MacOS/$name"
    # Existing bundles are preserved above; rename the current bundle into place.
    if [[ -e "$dst" ]]; then mv "$dst" "$PACKAGE/data-before/$name.replaced.kext"; fi
    mv "$tmp" "$dst"
done

mkdir -p "$MP/Library/StrixGraphicsFix" "$MP/Library/Logs/StrixGraphicsFix"
install -m 755 "$BOOTSTRAP" "$MP/Library/StrixGraphicsFix/bootstrap.sh"
install -m 644 "$PACKAGE/manifest.json" "$MP/Library/StrixGraphicsFix/manifest.json"
install -m 644 "$PACKAGE/com.itlmt7925.graphics-bootstrap.plist" "$MP/Library/LaunchDaemons/com.itlmt7925.graphics-bootstrap.plist"
chown -R 0:0 "$MP/Library/StrixGraphicsFix" "$MP/Library/Logs/StrixGraphicsFix"
chown 0:0 "$MP/Library/LaunchDaemons/com.itlmt7925.graphics-bootstrap.plist"

kc="$MP/Library/KernelCollections/AuxiliaryKernelExtensions.kc"
if [[ -f "$kc" ]]; then cp -a "$kc" "$PACKAGE/data-before/"; rm "$kc"; fi
# Confirm bytes on the Data volume before touching the live boot configuration.
python3 - "$PACKAGE" "$MP" <<'PY'
import hashlib,json,pathlib,sys
p,r=map(pathlib.Path,sys.argv[1:]);m=json.loads((p/'manifest.json').read_text())
for rel,h in m['files'].items():
    if rel.startswith('Extensions/'):
        f=r/'Library'/rel
        assert hashlib.sha256(f.read_bytes()).hexdigest()==h, f'Installed hash mismatch: {rel}'
print('All installed graphics bundle bytes verified.')
PY
sync
umount "$MP"

cp -a "$ESP/EFI/OC/config.plist" "$PACKAGE/config-before.plist"
cp "$PACKAGE/Extensions/StrixGOP.kext/Contents/Info.plist" "$ESP/EFI/OC/Kexts/StrixGOP.kext/Contents/Info.plist"
cp "$PACKAGE/config.plist" "$ESP/EFI/OC/config.plist.strix-graphics-new"
mv "$ESP/EFI/OC/config.plist.strix-graphics-new" "$ESP/EFI/OC/config.plist"
sync
printf 'APPLIED\n' >"$PACKAGE/applied"
echo 'Applied current graphics versions with the panel profile and HDR enabled.'
echo 'Next macOS boot rebuilds/loads AuxKC; bootstrap evidence is in /Library/Logs/StrixGraphicsFix.'
echo 'If bootstrap reports REBOOT_REQUIRED, restart macOS once more.'
