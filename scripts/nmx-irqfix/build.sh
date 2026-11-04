#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step100 (irqfix): build the irqwatch+irqfix cave (cave.c) into cave.bin at 0x509100 (dead KV legacy dpm code:
# kv_dpm_enable and the kv_populate_{vce,samu,acp}_table it calls; 0x509100..0x50a630 has no relocations).
# Every NMXGPU address the cave uses is looked up by symbol in the given NMXGPU and must equal the address the cave
# was reviewed against.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-/Library/Extensions/NMXGPU.kext/Contents/MacOS/NMXGPU}
BASE=0x509100
LIMIT=0x50a630
cd "$HERE"
clang --target=x86_64-unknown-linux-gnu -Os -fno-omit-frame-pointer -ffreestanding -fno-builtin -fno-stack-protector \
  -mno-red-zone -mgeneral-regs-only -fPIE -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-jump-tables \
  -fcf-protection=none -Wall -Wextra -Werror -c cave.c -o cave.o

NM=$(mktemp); trap 'rm -f "$NM"' EXIT
nm -m "$BIN" | awk '{print $NF, $1}' > "$NM"
want() {   # NAME SYMBOL ADDR
  local a
  a=$(awk -v n="$2" '$1==n {print "0x" $2}' "$NM" | head -1)
  [[ -n $a ]] || { echo "no symbol $2"; exit 1; }
  (( a == $3 )) || { echo "$2 is at $a, not $3: a different NMXGPU build"; exit 1; }
  SYMS+=(--sym "$1=$3")
}
SYMS=()
want FENCE_PROCESS _amdgpu_fence_process 0x6e8840
want IH_PROCESS _amdgpu_ih_process 0x64cf0
want MOD_TIMER _mod_timer 0x6b6bb0
want JIFFIES _nmx_jiffies 0x6d72d0
want RREG _amdgpu_device_rreg 0x18d20
want PCI_READ _pci_read_config 0x6d4b10
want PCI_FIND_CAP _pci_find_cap 0x6d5300
want IRQS _nmx_irq_dispatched 0x9b9950
want HZ _hz 0x925e30
want INTRS _intrs 0x925af0
want ST _ci_init_smc_table.__ratelimited.15 0x927010
# jmp _printf / jmp _snprintf sites (external relocations) and the "%s\n" string, as in the earlier caves
SYMS+=(--sym SNPRINTF=0x8789e --sym PRINTF=0xbc46e)

python3 -I ../nmx-userptr/elflink2.py cave.o cave.bin --base $BASE --limit $LIMIT "${SYMS[@]}"
python3 -I ../nmx-userptr/elflink2.py cave.o /dev/null --base $BASE "${SYMS[@]}" --map \
  | grep -E " (ih_guarded|fb_process|fb_arm|stale_note)$" > cave.map
cat cave.map
shasum -a 256 cave.bin
