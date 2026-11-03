#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step91 (macOS, run as root): NMXGPU's nmx_umap_cache default 2 -> 0, then the AuxKC is relinked in place so the
# next boot has it. The running session can get the same value now with "sysctl -w debug.nmx_umap_cache=0" (it
# applies to mappings made after it).
#
#   sudo scripts/macos-patch-nmx-step91.sh          # patch + relink
#   sudo scripts/macos-patch-nmx-step91.sh --undo   # put the backed-up NMXGPU back + relink
#
# nmx_umap_insert (fork xkpi linux_page.c): 0 = the driver's own attribute (pgprot from TTM), 1 = uncached,
# 2 = write-combined. Step88 set 2 believing it meant "follow pgprot", so every user mmap of a GEM BO has been WC since
# then, cached GTT included: CPU reads of any BO ran at ~108 MB/s (a 20 MB getBytes took 190 ms). With 0 a cached
# BO maps write-back (snooped by the GPU since Step88) and a USWC BO maps WC.
set -euo pipefail
[[ $EUID == 0 ]] || { echo "run as root"; exit 1; }
TS=$(date -u +%Y%m%dT%H%M%SZ)
E=/Library/Extensions/NMXGPU.kext
BIN=$E/Contents/MacOS/NMXGPU
KC=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
exec > >(tee -a "/Library/NullMoth/step91-$TS.log") 2>&1

if [[ ${1:-} == --undo ]]; then
    BK=$(ls -d /Library/NullMoth/nmx-step91-* 2>/dev/null | sort | tail -1)
    [[ -n $BK && -f $BK/NMXGPU.kext/Contents/MacOS/NMXGPU ]] || { echo "no step91 backup"; exit 1; }
    rm -rf "$E"; ditto "$BK/NMXGPU.kext" "$E"
    echo "restored NMXGPU from $BK"
else
    BK=/Library/NullMoth/nmx-step91-$TS
    mkdir -p "$BK"
    ditto "$E" "$BK/NMXGPU.kext"
    cp -p "$KC" "$BK/AuxiliaryKernelExtensions.kc"
    echo "backup $BK"
    /usr/bin/python3 -I - "$BIN" <<'PY'
import hashlib, sys
p = sys.argv[1]
d = bytearray(open(p, 'rb').read())
o = 0x9264d0   # _nmx_umap_cache, __DATA (file offset == vmaddr)
cur = bytes(d[o:o + 4])
if cur == b'\0\0\0\0':
    print('nmx_umap_cache already 0'); sys.exit(0)
if cur != b'\x02\0\0\0':
    sys.exit(f'nmx_umap_cache holds {cur.hex()}, not the Step88 value 2 -- not touching it')
d[o:o + 4] = b'\0\0\0\0'
open(p, 'wb').write(d)
print('nmx_umap_cache 2 -> 0; sha256', hashlib.sha256(d).hexdigest())
PY
fi
shasum -a 256 "$BIN"

NEW=$KC.step91
rm -f "$NEW"
/usr/bin/kmutil create -n aux --volume-root / --allow-missing-kdk --kernel /System/Library/Kernels/kernel \
    -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc \
    --repository /Library/Extensions -A "$NEW" -z
# a binary patch keeps the UUID; the value itself is checked after the boot: sysctl debug.nmx_umap_cache reads 0
U=$(otool -l "$BIN" | awk '/LC_UUID/{f=1} f&&/uuid/{print $2; exit}')
/usr/bin/python3 -I -c 'import sys; kc=open(sys.argv[1],"rb").read(); ok=bytes.fromhex(sys.argv[2].replace("-","")) in kc; print("NMXGPU uuid", sys.argv[2], "present" if ok else "MISSING"); sys.exit(0 if ok else 1)' "$NEW" "$U"
mv -f "$NEW" "$KC"
sync
echo "RELINKED $(date -u): reboot to load it"
