#!/bin/bash
# Step95: build the CS trace cave (cave.c) into cave.bin at 0x5ab760 (after the Step93 cave, dead SI dpm code).
# Targets are resolved from sites.txt against NMXGPU's symbols (nm), so a different build fails here, not at boot.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-/Library/Extensions/NMXGPU.kext/Contents/MacOS/NMXGPU}
cd "$HERE"
clang --target=x86_64-unknown-linux-gnu -O2 -fno-omit-frame-pointer -ffreestanding -fno-builtin -fno-stack-protector \
  -mno-red-zone -mgeneral-regs-only -fPIE -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-jump-tables \
  -fcf-protection=none -Wall -Wextra -Werror -c cave.c -o cave.o
NM=$(mktemp); trap 'rm -f "$NM"' EXIT
nm -m "$BIN" | awk '$2=="(__TEXT,__text)" {print $NF, $1}' > "$NM"
SYMS=()
i=0
while read -r site name _; do
  [[ $name == 0x* ]] && { SYMS+=(--sym "T$i=$name"); i=$((i + 1)); continue; }
  addr=$(awk -v n="$name" '$1==n {print "0x" $2}' "$NM" | head -1)
  [[ -n $addr ]] || { echo "no symbol $name"; exit 1; }
  SYMS+=(--sym "T$i=$addr"); i=$((i + 1))
done < sites.txt
python3 -I ../nmx-userptr/elflink2.py cave.o cave.bin --base 0x5ab760 --limit 0x5abe80 "${SYMS[@]}" \
  --sym SNPRINTF=0x8789e --sym PRINTF=0xbc46e --sym FMT_S=0x7001ed \
  --sym BUDGET_EPERM=0x926fe0 --sym BUDGET_OTHER=0x926fe4 --sym IOCTL_RESUME=0x6b5cd6
python3 -I ../nmx-userptr/elflink2.py cave.o /dev/null --base 0x5ab760 "${SYMS[@]}" --sym SNPRINTF=0x8789e --sym PRINTF=0xbc46e --sym FMT_S=0x7001ed --sym BUDGET_EPERM=0x926fe0 --sym BUDGET_OTHER=0x926fe4 --sym IOCTL_RESUME=0x6b5cd6 --map | grep -E " (thunk[0-9]+|ioctl_hook|entry)$" > cave.map
shasum -a 256 cave.bin
