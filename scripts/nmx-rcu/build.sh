#!/bin/bash
# Assembles rcu.s at NMXGPU's linux_rcu_read_lock (0x6c4e00, NMXGPU sha 401c4e4c...) into rcu.bin (416 bytes).
set -euo pipefail
cd "$(dirname "$0")"
as --64 -o /tmp/nmx-rcu.o rcu.s
ld -o /tmp/nmx-rcu.elf -Ttext=0x6c4e00 -e _start \
    --defsym LKPI_CURRENT=0x6b3f90 --defsym SCHED_PIN=0x6d7980 --defsym SCHED_UNPIN=0x6d79b0 \
    --defsym CRIT_ENTER=0x6d7870 --defsym CRIT_EXIT=0x6d78c0 --defsym CK_ADDREF=0x6b2e40 --defsym CK_DELREF=0x6b2e00 \
    --defsym EPOCH_RECORD=0x95f100 --defsym RCU_LOCK=0x95f1f8 /tmp/nmx-rcu.o
objcopy -O binary -j .text /tmp/nmx-rcu.elf rcu.bin
sha256sum rcu.bin
