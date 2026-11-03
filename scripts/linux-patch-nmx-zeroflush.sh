#!/bin/bash
# Step84: after minutes of desktop the GFX ring hung (PFP stopped on a packet header of 0x00000000), MES could not reset
# the queue, the MODE2 reset left no working GPU, and WindowServer died. Step82's TCP page fault is the same class.
#
#   pkexec scripts/linux-patch-nmx-zeroflush.sh
#
# Every GTT page is write-combined (amdgpu-ttm-force-wc) and the GPU reads it without snooping. When such a page goes
# back to the TTM pool, ttm_pool_type_give (inlined in ttm_pool_free_range, call at 0x5fe42b) clears it with
# pmap_zero_page, which is bzero through the kernel's write-back view (nmx_kva): the zeros stay in the CPU cache as
# dirty lines over a WC page. The page is handed to the next buffer from the pool without any flush, so those lines
# are later written back over what RADV or the GPU put there (IBs, descriptors), or they hold the CPU's writes away
# from the GPU. Linux does not have the alias: set_pages_array_wc makes the direct map WC too.
#  - NMXGPU (no CI build): pmap_zero_page (0x6dda90, 32 bytes) zeroes with rep stosb and tail-jumps to
#    pmap_invalidate_cache_range (0x6dd980: clflush the page, mfence). The bzero jmp at 0x6dda9e keeps its bytes,
#    because its external relocation is still applied when the AuxKC is linked; the new code jumps around it.
set -euo pipefail
DEV=${DEV:-/dev/nvme0n1p4}
MNT=${MNT:-/mnt/macos-rw}
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date -u +%Y%m%dT%H%M%SZ)
[[ $EUID == 0 ]] || { echo "run with pkexec or sudo"; exit 1; }

for t in $(findmnt -rn -S "$DEV" -o TARGET | tac); do umount "$t"; echo "unmounted $t"; done
mkdir -p "$MNT"
mount -t apfs -o readwrite,uid=0,gid=0,vol=0 "$DEV" "$MNT"
findmnt -rn -T "$MNT" -o OPTIONS | tr ',' '\n' | grep -qx rw || { echo "not rw: $(findmnt -rn -T "$MNT" -o OPTIONS)"; exit 1; }

E="$MNT/Library/Extensions"
BK="$MNT/Library/NullMoth/nmx-zeroflush-$TS"
mkdir -p "$BK/Library/KernelCollections"
cp -a "$E/NMXGPU.kext" "$BK/"
cp -a "$MNT/Library/KernelCollections/AuxiliaryKernelExtensions.kc" "$BK/Library/KernelCollections/"
echo "backup $BK"

python3 -I - "$E/NMXGPU.kext/Contents/MacOS/NMXGPU" <<'PY'
import sys
p = sys.argv[1]
d = bytearray(open(p, 'rb').read())
OFF = 0x6dda90
# push rbp; mov rbp,rsp; mov rdi,[rdi+8]; mov esi,0x1000; pop rbp; jmp _bzero (reloc at +0xf); padding
OLD = bytes.fromhex('554889e5488b7f08be001000005de900000000666666662e0f1f840000000000')
NEW = bytes.fromhex('488b7f08'      # mov rdi,[rdi+8]      page's kernel address
                    '4889fe'        # mov rsi,rdi
                    '31c9' 'b510'   # ecx = 0x1000
                    'eb06' 'cc'     # jump over the relocated bzero jmp
                    'e900000000'    # (bzero jmp, never executed, bytes kept for its relocation)
                    '31c0' 'f3aa'   # rep stosb: zero the page, rdi = end
                    '4887f7'        # xchg rsi,rdi         rdi = start, rsi = end
                    'e9d1feffff'    # jmp pmap_invalidate_cache_range (0x6dd980)
                    'cc')
CALL = (0x5fe42b, bytes.fromhex('e860f60d00'))   # ttm_pool_free_range -> pmap_zero_page
INV = (0x6dd980, bytes.fromhex('554889e54883e7c04839f7'))
assert len(OLD) == len(NEW) == 32 and NEW[0x0e:0x13] == OLD[0x0e:0x13]
cur = bytes(d[OFF:OFF + 32])
if cur == NEW:
    print(f'{p}: pmap_zero_page already flushes'); sys.exit(0)
for off, want in ((OFF, OLD), CALL, INV):
    got = bytes(d[off:off + len(want)])
    if got != want:
        sys.exit(f'{p}: {off:#x} is {got.hex()}, expected {want.hex()} -- not the expected build, not touching it')
d[OFF:OFF + 32] = NEW
open(p, 'wb').write(d)
print(f'{p}: pmap_zero_page now writes the zeroed page out of the CPU caches')
PY
sha256sum "$E/NMXGPU.kext/Contents/MacOS/NMXGPU"

S="$MNT/Library/StrixGraphicsFix"
install -o 0 -g 0 -m 755 "$HERE/nmx-relink/nmx-relink.sh" "$S/nmx-relink.sh"
install -o 0 -g 0 -m 644 "$HERE/nmx-relink/com.itlmt7925.nmx-relink.plist" "$MNT/Library/LaunchDaemons/com.itlmt7925.nmx-relink.plist"
rm -f "$S/nmx-relink.done" "$S/nmx-relink.status" "$S/nmx-relink.log"
# An earlier relink ran "launchctl disable", and launchd skips a disabled label even with its plist back (Step78).
python3 -I - "$MNT/private/var/db/com.apple.xpc.launchd/disabled.plist" <<'PY2'
import plistlib, sys
p = sys.argv[1]
d = plistlib.load(open(p, 'rb'))
if d.pop('com.itlmt7925.nmx-relink', None) is not None:
    plistlib.dump(d, open(p, 'wb')); print('nmx-relink: enabled again in launchd')
PY2
date -u >"$S/nmx-relink.reboot"
sync
umount "$MNT"
echo "armed: boot macOS once (it relinks the AuxKC, ~1-2 min, then reboots by itself); log in on the boot after that"
