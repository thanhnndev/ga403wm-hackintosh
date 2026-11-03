#!/bin/bash
# Step92: builds the userptr cave at 0x5ab300 (inside si_initialize_smc_cac_tables, SI dpm only, after the Step90 cave
# that ends at 0x5ab2e4) for NMXGPU as installed after Step91. Runs on Linux or macOS (clang ELF + elflink2.py).
set -euo pipefail
cd "$(dirname "$0")"
T=$(mktemp -d)
clang --target=x86_64-unknown-linux-gnu -O2 -fno-omit-frame-pointer -ffreestanding -fno-builtin -fno-stack-protector -mno-red-zone \
    -mgeneral-regs-only -fPIE -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-jump-tables -fcf-protection=none \
    -Wall -Wextra -Werror -c -o "$T/cave.o" cave.c
python3 -I elflink2.py "$T/cave.o" cave.bin --base 0x5ab300 --limit 0x5abe80 --map \
    --sym AMDGPU_BO_RESERVE=0x596a0 --sym AMDGPU_BO_UNRESERVE=0x59740 --sym PLACEMENT_FROM_DOMAIN=0x6f270 \
    --sym TTM_BO_VALIDATE=0x5faaf0 --sym DRM_GEM_HANDLE_CREATE=0x41d100 --sym LKPI_GET_USER_PAGES=0x6bf2b0 \
    --sym RELEASE_PAGES=0x6bf150 --sym SNPRINTF=0x8789e --sym PRINTF=0xbc46e --sym FMT_S=0x7001ed \
    --sym LOG_BUDGET=0x926c73 --sym IOCTL_RESUME=0x5a7cf --sym IOCTL_RELEASE=0x5a893
rm -rf "$T"
shasum -a 256 cave.bin
