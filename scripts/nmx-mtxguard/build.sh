#!/bin/bash
# Assembles cave.s at 0x156ef0 and the 5-byte jump at nmx_mtx_unlock (NMXGPU with the Step77 rcu patch, sha 02a336b4...).
set -euo pipefail
cd "$(dirname "$0")"
as --64 -o /tmp/nmx-mtxguard.o cave.s
ld -o /tmp/nmx-mtxguard.elf -Ttext=0x156ef0 -e _start --defsym COLD=0x6d88a6 --defsym MTX_TAIL=0x6d8898 \
    --defsym SPIN_CALL=0x6d8886 --defsym PRINTF_TAIL=0xbc46e /tmp/nmx-mtxguard.o
objcopy -O binary -j .text /tmp/nmx-mtxguard.elf cave.bin
python3 -c "import struct; open('jmp.bin','wb').write(b'\xe9'+struct.pack('<i',0x156ef0-(0x6d8850+5)))"
sha256sum cave.bin jmp.bin
