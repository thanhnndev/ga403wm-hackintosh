#!/bin/bash
# Step97b: build the mm-fix cave (cave.c) into cave.bin at 0x50a730 (kv_enable_didt, dead KV dpm code).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
clang --target=x86_64-unknown-linux-gnu -O2 -fno-omit-frame-pointer -ffreestanding -fno-builtin -fno-stack-protector \
  -mno-red-zone -mgeneral-regs-only -fPIE -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-jump-tables \
  -fcf-protection=none -Wall -Wextra -Werror -c cave.c -o cave.o
S=(--sym SNPRINTF=0x8789e --sym PRINTF=0xbc46e --sym FMT_S=0x7001ed --sym BUDGET=0x926ff8
   --sym LKPI_CURRENT=0x6b3f90 --sym NMX_CURTHREAD=0x6d74b0)
python3 -I ../nmx-userptr/elflink2.py cave.o cave.bin --base 0x50a730 --limit 0x50a9a0 "${S[@]}"
python3 -I ../nmx-userptr/elflink2.py cave.o /dev/null --base 0x50a730 "${S[@]}" --map | grep -E " (entry|mm_check)$" > cave.map
rm -f cave.o
shasum -a 256 cave.bin
