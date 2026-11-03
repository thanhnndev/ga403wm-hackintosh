#!/bin/bash
# Step98: build the flip API cave (cave.c) into cave.bin at 0x507190: kv_dpm_sw_fini .. kv_dpm_post_set_power_state, dead KV
# dpm code (Kaveri only). Relocations around it are at 0x507187 and 0x50822b, so it stays in 0x507190..0x508220.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
clang --target=x86_64-unknown-linux-gnu -Os -fno-omit-frame-pointer -ffreestanding -fno-builtin -fno-stack-protector \
  -mno-red-zone -mgeneral-regs-only -fPIE -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-jump-tables \
  -fcf-protection=none -Wall -Wextra -Werror -c cave.c -o cave.o
source ./syms.sh
python3 -I ../nmx-userptr/elflink2.py cave.o cave.bin --base 0x507190 --limit 0x508220 "${SYMS[@]}"
python3 -I ../nmx-userptr/elflink2.py cave.o /dev/null --base 0x507190 "${SYMS[@]}" --map | grep -E " (entry|flip_dispatch)$" > cave.map
rm -f cave.o
shasum -a 256 cave.bin
