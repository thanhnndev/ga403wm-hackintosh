#!/bin/bash
# Step77: WindowServer hung right after the login password, because synchronize_rcu in NMXGPU never returned.
#
#   pkexec scripts/linux-patch-nmx-rcu.sh
#
# linux_rcu_read_lock took the epoch record of the CPU it ran on and linux_rcu_read_unlock the record of the CPU it
# ran on then. FreeBSD pins the reader in between; on xnu sched_pin only counts, so a reader that migrated ended its
# section on another CPU's record and left its own active forever. The first drm ioctl that called synchronize_rcu
# after login (nvmtl.execution, RADV) spun in ck_epoch_synchronize_wait with WindowServer's main thread waiting on it,
# and the userspace watchdog killed WindowServer 40 s later (boots C562F754 and 26592254, 2026-11-02).
#  - NMXGPU (no CI build): both functions rewritten in place (nmx-rcu/rcu.s, 416 bytes): every reader uses the CPU-0
#    record of its type, and a spinlock in that record's padding serializes the updates across CPUs.
set -euo pipefail
DEV=${DEV:-/dev/nvme0n1p4}
MNT=${MNT:-/mnt/macos-rw}
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
[[ $EUID == 0 ]] || { echo "run with pkexec or sudo"; exit 1; }
[[ -f $HERE/nmx-rcu/rcu.bin ]] || { echo "no $HERE/nmx-rcu/rcu.bin"; exit 1; }

for t in $(findmnt -rn -S "$DEV" -o TARGET | tac); do umount "$t"; echo "unmounted $t"; done
mkdir -p "$MNT"
mount -t apfs -o readwrite,uid=0,gid=0,vol=0 "$DEV" "$MNT"
findmnt -rn -T "$MNT" -o OPTIONS | tr ',' '\n' | grep -qx rw || { echo "not rw: $(findmnt -rn -T "$MNT" -o OPTIONS)"; exit 1; }

E="$MNT/Library/Extensions"
BK="$MNT/Library/NullMoth/nmx-rcu-$TS"
mkdir -p "$BK/Library/KernelCollections"
cp -a "$E/NMXGPU.kext" "$BK/"
cp -a "$MNT/Library/KernelCollections/AuxiliaryKernelExtensions.kc" "$BK/Library/KernelCollections/"
echo "backup $BK"

python3 -I - "$E/NMXGPU.kext/Contents/MacOS/NMXGPU" "$HERE/nmx-rcu/rcu.bin" <<'PY'
import hashlib, sys
p, b = sys.argv[1], sys.argv[2]
d = open(p, 'rb').read()
new = open(b, 'rb').read()
OFF, N = 0x6c4e00, 0x1a0
assert len(new) == N
cur = d[OFF:OFF + N]
h = hashlib.sha256(cur).hexdigest()
if cur == new:
    print(f'{p}: rcu read lock already patched'); sys.exit(0)
if h != '22c20438ec3ffd059dfdd2c0923209942b437d7aaf3125b59b9d8d51ae6af2e4':
    sys.exit(f'{p}: linux_rcu_read_lock/unlock at {OFF:#x} is not the expected build ({h[:16]}) -- not touching it')
open(p, 'r+b').write(d[:OFF] + new + d[OFF + N:])
print(f'{p}: rcu read lock/unlock rewritten at {OFF:#x}')
PY
sha256sum "$E/NMXGPU.kext/Contents/MacOS/NMXGPU"

S="$MNT/Library/StrixGraphicsFix"
install -o 0 -g 0 -m 755 "$HERE/nmx-relink/nmx-relink.sh" "$S/nmx-relink.sh"
install -o 0 -g 0 -m 644 "$HERE/nmx-relink/com.itlmt7925.nmx-relink.plist" "$MNT/Library/LaunchDaemons/com.itlmt7925.nmx-relink.plist"
rm -f "$S/nmx-relink.done" "$S/nmx-relink.status" "$S/nmx-relink.log"
date -u >"$S/nmx-relink.reboot"
sync
umount "$MNT"
echo "armed: boot macOS once (it relinks the AuxKC, ~1-2 min, then reboots by itself); log in on the boot after that"
