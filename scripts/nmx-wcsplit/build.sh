#!/bin/bash
# Assembles the Step90 cave at 0x5aac00 (inside si_initialize_smc_cac_tables, after the Step89 ibprobe cave which ends
# at 0x5aab70; SI dpm only, no relocations in the function). NMXGPU as installed by Step89.
# Stub sites: external call sites in the replaced nmx_xnu_map_user / nmx_xnu_unmap_user bodies (each keeps its
# relocation; the patch puts a ret after it).
set -euo pipefail
cd "$(dirname "$0")"
T=$(mktemp -d)
clang -c -x assembler --target=x86_64-unknown-linux-gnu -o "$T/cave.o" cave.s
python3 -I ../nmx-ibprobe/elflink.py "$T/cave.o" cave.bin --base 0x5aac00 \
    --sym S_IOMALLOC=0x6e2550 --sym S_WITHRANGES=0x6e25d8 --sym S_IOFREE=0x6e25e6 --sym S_CURTASK=0x6e2644 \
    --sym S_CREATEMAP=0x6e265f --sym S_TASKREF=0x6e26ab --sym S_GETTASKMAP=0x6e2727 --sym S_VMDEALLOC=0x6e2737 \
    --sym S_TASKDEALLOC=0x6e2740 --sym KVA_TO_PHYS=0x6e7c40 --sym CACHETAB=0x899694 --sym GOT_KTASK=0x89a0e8
rm -rf "$T"
ls -l cave.bin; sha256sum cave.bin 2>/dev/null || shasum -a 256 cave.bin
