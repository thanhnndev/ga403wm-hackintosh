#!/bin/bash
# Step98/99: build the two flip caves.
#   import.c -> import.bin at 0x506580 (kv_dpm_sw_init, dead KV dpm code; its only relocation is at 0x507187)
#   cave.c   -> cave.bin   at 0x507190 (kv_dpm_sw_fini .. kv_dpm_post_set_power_state; relocations at 0x507187 and
#               0x50822b, so it stays in 0x507190..0x508220). cave.c calls into import.c by the addresses of import.map.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
CF=(--target=x86_64-unknown-linux-gnu -Os -fno-omit-frame-pointer -ffreestanding -fno-builtin -fno-stack-protector
  -mno-red-zone -mgeneral-regs-only -fPIE -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-jump-tables
  -fcf-protection=none -Wall -Wextra -Werror)
source ./syms.sh
L=../nmx-userptr/elflink2.py
clang "${CF[@]}" -c import.c -o import.o
python3 -I $L import.o import.bin --base 0x506580 --limit 0x507180 "${ISYMS[@]}"
python3 -I $L import.o /dev/null --base 0x506580 "${ISYMS[@]}" --map | grep -E " (fb_create_vram|flip_import|flip_release_import)$" > import.map
I(){ awk -v n=$1 '$2==n{print $1}' import.map; }
clang "${CF[@]}" -c cave.c -o cave.o
python3 -I $L cave.o cave.bin --base 0x507190 --limit 0x508220 "${SYMS[@]}" \
  --sym FB_CREATE_VRAM=$(I fb_create_vram) --sym FLIP_IMPORT=$(I flip_import) --sym FLIP_RELEASE_IMPORT=$(I flip_release_import)
python3 -I $L cave.o /dev/null --base 0x507190 "${SYMS[@]}" --map \
  --sym FB_CREATE_VRAM=$(I fb_create_vram) --sym FLIP_IMPORT=$(I flip_import) --sym FLIP_RELEASE_IMPORT=$(I flip_release_import) \
  | grep -E " (entry|flip_dispatch)$" > cave.map
rm -f cave.o import.o
shasum -a 256 import.bin cave.bin
