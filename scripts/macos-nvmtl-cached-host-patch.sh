#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step91: NVMTL gives every host-visible buffer a CACHED memory type (GTT write-back, snooped since Step88).
#
#   sudo scripts/macos-nvmtl-cached-host-patch.sh            # back up, patch, re-sign ad hoc, swap the bundle in
#   sudo scripts/macos-nvmtl-cached-host-patch.sh --undo     # put the backed-up bundle back
#   scripts/macos-nvmtl-cached-host-patch.sh --file BIN      # patch one NVMTLDriver binary in place (no install)
#
# NVMTL picks a buffer's memory type with want = host_visible * 5 + 1 and an exact match on
# (flags & (want ^ DEVICE_LOCAL)) == want. For host-visible buffers want = 0x6 (HOST_VISIBLE | HOST_COHERENT), CACHED
# is not compared, so the first match is RADV's write-combined GTT type ("buffers (host_visible=1) take memory type 2
# flags 0x6"). Since Step90 a WC mapping really is WC, and every readback (getBytes, the "copied out" half of
# NVMTL's private surface images) memmoves out of uncached memory: 20 MB in ~190 ms (108 MB/s), ~78% of a WindowServer
# thread. With want = host_visible * 13 + 1 = 0xE the exact match is HOST_VISIBLE | HOST_COHERENT | HOST_CACHED.
# The superset fallback is unchanged. Two sites use the formula:
#   nvmtl_vk_buffer_create 0x3dd5: leal (%r15,%r15,4),%eax  43 8d 04 bf -> imull $0xd,%r15d,%eax  41 6b c7 0d
#   nvmtl_vk_heap_create  0x1fc89: leal (%rax,%rax,4),%eax  8d 04 80    -> imull $0xd,%eax,%eax   6b c0 0d
# Both are followed by "incl %eax". The bundle is swapped by rename (never written in place), so a running
# WindowServer keeps the pages it mapped; new processes load the patched driver, and WindowServer does on its next
# start.
set -euo pipefail
B=/Library/GPUBundles/NVMTLDriver.bundle
BIN_REL=Contents/MacOS/NVMTLDriver

patch_bin() {
    /usr/bin/python3 -I - "$1" <<'PY'
import hashlib, sys
p = sys.argv[1]
d = bytearray(open(p, 'rb').read())
sites = [(0x3dd5, bytes.fromhex('438d04bfffc0'), bytes.fromhex('416bc70dffc0')),
         (0x1fc89, bytes.fromhex('8d0480ffc0'), bytes.fromhex('6bc00dffc0'))]
if all(d[o:o + len(n)] == n for o, _, n in sites):
    print('NVMTLDriver already patched'); sys.exit(0)
for o, old, new in sites:
    if d[o:o + len(old)] not in (old, new):
        sys.exit(f'bytes at {o:#x} are not the expected NVMTLDriver build -- not touching it')
for o, _, new in sites:
    d[o:o + len(new)] = new
open(p, 'wb').write(d)
print('NVMTLDriver patched (host-visible buffers ask HOST_CACHED); sha256', hashlib.sha256(d).hexdigest())
PY
}

if [[ ${1:-} == --file ]]; then
    patch_bin "$2"
    codesign -f -s - "$2"
    exit 0
fi
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
TS=$(date -u +%Y%m%dT%H%M%SZ)
if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/nvmtl-cachedhost-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -d $BK/NVMTLDriver.bundle ]] || { echo "no backup"; exit 1; }
    T=$B.restore.$TS
    ditto "$BK/NVMTLDriver.bundle" "$T"
    mv "$B" "$B.old.$TS" && mv "$T" "$B" && rm -rf "$B.old.$TS"
    echo "restored $BK: $(shasum -a 256 "$B/$BIN_REL" | cut -c1-16)"
    exit 0
fi
BK=/Library/NullMoth/nvmtl-cachedhost-$TS
mkdir -p "$BK"
ditto "$B" "$BK/NVMTLDriver.bundle"
echo "backup $BK"
T=$B.new.$TS
ditto "$B" "$T"
patch_bin "$T/$BIN_REL"
codesign -f -s - "$T"
codesign -v "$T"
mv "$B" "$B.old.$TS" && mv "$T" "$B" && rm -rf "$B.old.$TS"
echo "installed: $(shasum -a 256 "$B/$BIN_REL" | cut -c1-16); WindowServer loads it on its next start"
