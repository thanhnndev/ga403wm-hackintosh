#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
#
# RADV (NullMoth gpu-userland, /Library/GPUBundles/nvmtl/libvulkan_radeon.dylib) for the own-build NMXGPU
# (docs/890M-TRACE.md Step33d). Run as root.
#   macos-nvmtl-radv-nmxmap-patch.sh            back up the stock dylib, patch, re-sign ad hoc
#   macos-nvmtl-radv-nmxmap-patch.sh --undo     put the stock dylib back
#
# RADV maps a buffer with a plain mmap(2) on the DRM fd (radv_amdgpu_winsys_bo_map) and unmaps it with munmap(2).
# macOS cannot mmap a kext's character device (xnu answers ENODEV), so the kernel offers an ioctl instead and libdrm
# wraps it: drmNmxMmap(size, prot, flags, fd, offset) / drmNmxMunmap(addr, size). The stock dylib never calls them,
# so vkCreateComputePipelines died when the shader arena could not be CPU mapped. Both are bound here by re-using the
# lazy-bind slots of two display-only imports that a headless compute device never calls:
#   _drmCrtcQueueSequence -> _drmNmxMmap, _drmSetMaster -> _drmNmxMunmap
# and the call sites are redirected: the mmap in radv_amdgpu_winsys_bo_map (arguments re-ordered in place) and the
# munmap in radv_amdgpu_winsys_bo_unmap. (A fixed-address map is not supported by drmNmxMmap and lands anywhere.)
set -euo pipefail
L=/Library/GPUBundles/nvmtl/libvulkan_radeon.dylib; BK=/Library/NullMoth/radv-backup
STOCK=2e0705f4a8d17bd594fe07201d136d17c13e85bda1c0d79d7b9d5ef33c07c5a8

if [ "${1:-}" = --undo ]; then
  [ -f "$BK/libvulkan_radeon.dylib" ] || { echo "no backup in $BK"; exit 1; }
  ditto "$BK/libvulkan_radeon.dylib" "$L"; echo "radv restored: $(shasum -a 256 "$L" | cut -c1-16)"; exit 0
fi

SRC=$L; [ -f "$BK/libvulkan_radeon.dylib" ] && SRC=$BK/libvulkan_radeon.dylib
[ "$(shasum -a 256 "$SRC" | cut -d' ' -f1)" = $STOCK ] || { echo "$SRC is not the stock build - not patching"; exit 1; }
mkdir -p "$BK"; [ "$SRC" = "$L" ] && ditto "$L" "$BK/libvulkan_radeon.dylib"
T=$(mktemp); cp "$SRC" "$T"
python3 -I - "$T" <<'PY'
import struct, sys
p = sys.argv[1]; d = bytearray(open(p, 'rb').read())
def rel(at, target): return struct.pack('<i', target - (at + 5))
MAP_STUB, UNMAP_STUB = 0x75f1ee, 0x75f2f6          # _drmCrtcQueueSequence, _drmSetMaster stubs
# radv_amdgpu_winsys_bo_map 0x17ef7b..0x17efa1: mmap(addr, len, 3, flags, fd, off) -> drmNmxMmap(len, 3, flags, fd, off)
old = bytes.fromhex('488b7308410fb6ccc1e104ffc1458b87780100004c8b4dd0488b7dc8ba03000000e8') + d[0x17ef9d:0x17efa1]
assert d[0x17ef7b:0x17efa1] == old, 'bo_map bytes differ'
new = (bytes.fromhex('0f1f4000')                       # nop
       + bytes.fromhex('488b7b08')                     # mov 0x8(%rbx),%rdi
       + bytes.fromhex('410fb6d4') + bytes.fromhex('c1e204') + bytes.fromhex('ffc2')   # movzbl %r12b,%edx; shl $4; inc
       + bytes.fromhex('418b8f78010000')               # mov 0x178(%r15),%ecx
       + bytes.fromhex('4c8b45d0')                     # mov -0x30(%rbp),%r8
       + bytes.fromhex('be03000000')                   # mov $3,%esi
       + b'\xe8' + rel(0x17ef9c, MAP_STUB))
assert len(new) == 0x17efa1 - 0x17ef7b
d[0x17ef7b:0x17efa1] = new
# radv_amdgpu_winsys_bo_unmap: munmap(addr, len) -> drmNmxMunmap(addr, len)
assert d[0x17effa] == 0xe8 and d[0x17effb:0x17efff] == bytes.fromhex('cb045e00')
d[0x17effb:0x17efff] = rel(0x17effa, UNMAP_STUB)
# lazy-bind symbol names (bind opcode stream and string table)
for a, b in ((b'_drmCrtcQueueSequence\0', b'_drmNmxMmap\0'), (b'_drmSetMaster\0', b'_drmNmxMunmap\0')):
    n = bytes(d).count(a); assert n == 2, (a, n)
    s = bytes(d).replace(a, b + b'\0' * (len(a) - len(b))); d[:] = s
open(p, 'wb').write(d)
PY
codesign -f -s - "$T" 2>/dev/null
chown root:wheel "$T"; chmod 755 "$T"; mv -f "$T" "$L"
echo "radv patched: $(shasum -a 256 "$L" | cut -c1-16)"
