#!/bin/bash
# Assembles cave.s at 0x5aa5a0 (si_initialize_smc_cac_tables) and the jump that replaces "addq $0x20,%rsp; testq %r13,%r13"
# after the ringdump printf in amdgpu_coredump (0x17a8c). NMXGPU as installed after Step84 (zeroflush).
set -euo pipefail
cd "$(dirname "$0")"
as --64 -o /tmp/nmx-ibprobe.o cave.s
ld -o /tmp/nmx-ibprobe.elf -Ttext=0x5aa5a0 -e _start --defsym JE_TARGET=0x17bd0 --defsym CONT=0x17a99 \
    --defsym RREG=0x18d20 --defsym MTX_LOCK=0x6d8740 --defsym MTX_UNLOCK=0x6d8850 --defsym XA_LOAD=0x6cb3e0 \
    --defsym LOOKUP=0xa70c0 --defsym PRINTF=0xbc46e /tmp/nmx-ibprobe.o
objcopy -O binary -j .text /tmp/nmx-ibprobe.elf cave.bin
python3 -c "import struct; open('jmp.bin','wb').write(b'\xe9'+struct.pack('<i',0x5aa5a0-(0x17a8c+5))+b'\x90\x90')"
ls -l cave.bin; sha256sum cave.bin jmp.bin
