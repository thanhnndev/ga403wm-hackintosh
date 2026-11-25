#!/bin/bash
# Assembles cave.s at 0x5aa5a0 (si_initialize_smc_cac_tables) and the jump that replaces "addq $0x20,%rsp; testq %r13,%r13"
# after the ringdump printf in amdgpu_coredump (0x17a8c). NMXGPU as installed after Step88 (same text as Step84).
# Runs on Linux or macOS: clang emits an ELF object, elflink.py places it (no GNU ld needed).
# cave-step86.bin is the Step86 cave, kept so the Step89 patch can check what it replaces.
set -euo pipefail
cd "$(dirname "$0")"
T=$(mktemp -d)
clang -c -x assembler --target=x86_64-unknown-linux-gnu -o "$T/cave.o" cave.s
python3 -I elflink.py "$T/cave.o" cave.bin --base 0x5aa5a0 \
    --sym JE_TARGET=0x17bd0 --sym CONT=0x17a99 --sym RREG=0x18d20 --sym MTX_LOCK=0x6d8740 --sym MTX_UNLOCK=0x6d8850 \
    --sym XA_LOAD=0x6cb3e0 --sym LOOKUP=0xa70c0 --sym PRINTF=0xbc46e --sym SNPRINTF=0x8789e --sym FMT_S=0x7001ed
rm -rf "$T"
python3 -c "import struct; open('jmp.bin','wb').write(b'\xe9'+struct.pack('<i',0x5aa5a0-(0x17a8c+5))+b'\x90\x90')"
ls -l cave.bin; shasum -a 256 cave.bin jmp.bin
