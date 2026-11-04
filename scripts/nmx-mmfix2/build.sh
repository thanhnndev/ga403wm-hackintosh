#!/bin/bash
# Step100: build the stale-record cave (cave.c) into cave.bin at 0x50a9a0 (kv_dpm_disable, dead KV dpm code;
# 0x50a9a0..0x50abc0, the first relocation in that function is at 0x50abca).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
clang --target=x86_64-unknown-linux-gnu -Os -fno-omit-frame-pointer -ffreestanding -fno-builtin -fno-stack-protector \
  -mno-red-zone -mgeneral-regs-only -fPIE -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-jump-tables \
  -fcf-protection=none -Wall -Wextra -Werror -c cave.c -o cave.o
S=(--sym SNPRINTF=0x8789e --sym PRINTF=0xbc46e --sym FMT_S=0x7001ed --sym CNT=0x926f98
   --sym TID_CALL=0x6d757e --sym PID_CALL=0x6d73fc
   --sym T_FOUND=0x6d75ea --sym T_NEXT=0x6d7539 --sym P_FOUND=0x6d7447 --sym P_NEXT=0x6d73ca)
python3 -I ../nmx-userptr/elflink2.py cave.o cave.bin --base 0x50a9a0 --limit 0x50abc0 "${S[@]}"
python3 -I ../nmx-userptr/elflink2.py cave.o /dev/null --base 0x50a9a0 "${S[@]}" --map | grep -E " (t_entry|p_entry|t_log|p_log)$" > cave.map
rm -f cave.o
shasum -a 256 cave.bin
