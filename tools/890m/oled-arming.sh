#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step56: arm the hybrid display machine and report what it did.
#
# The OLED's display pipe is created (debug.nvaccel_heads_piped bit 4) but WindowServer's transactions come back
# kIOReturnNotReady ("Failed to submit transaction: IOPRESENTMENT_METHOD_FAILURE: IOReturn: 0x2d8") and the panel
# keeps the boot console. luuumi-dev's phxboot arms the same NullMoth accelerator in a different order than we did:
#
#     debug.nvaccelfb=1  ->  debug.nvaccel_iop=1  ->  debug.nvaccelfb=3  ->  killall WindowServer
#
# This runs that order (or ours, with --fb4) and prints the counters that decide it.
#
#   sudo tools/890m/oled-arming.sh           luuumi order, then restart WindowServer
#   sudo tools/890m/oled-arming.sh --fb4     nvaccelfb=1 -> iop=1 -> nvaccelfb=4, no WindowServer restart
#   tools/890m/oled-arming.sh --status       counters only, change nothing
set -u

MODE=${1:---arm}
LOG=${OLED_ARMING_LOG:-/tmp/oled-arming.txt}

status() {
    {
        echo "== $1 $(date '+%F %T')"
        for k in debug.nvaccelfb debug.nvaccel_iop debug.nvaccel_headless \
                 debug.nvaccel_heads_published debug.nvaccel_heads_registered debug.nvaccel_heads_piped \
                 debug.nvaccel_iop_ok_h0 debug.nvaccel_iop_ok_h4 debug.nvaccel_iop_fail \
                 debug.nvaccel_iop_copy_skip debug.nvaccel_iop_blank debug.nvaccel_iop_src_surf \
                 debug.nvrmfb_agdc_client_set debug.nvrmfb_agdc_refused debug.nvrmfb_agdc_fbmap \
                 debug.nvrmfb_agdc_k5 debug.nvrmfb_agdc_k5_link debug.nvrmfb_agdc_k5_why; do
            printf '  %-34s %s\n' "$k" "$(sysctl -n "$k" 2>/dev/null || echo -)"
        done
        printf '  %-34s %s\n' "WindowServer pid/cpu" \
               "$(ps -Ao pid,pcpu,comm | awk '/WindowServer$/{print $1"/"$2}' | head -1)"
    } | tee -a "$LOG"
}

set_sysctl() {
    if [ "$(sysctl -n "$1" 2>/dev/null)" = "$2" ]; then
        echo "  $1 already $2"
        return 0
    fi
    if [ "$(id -u)" != 0 ]; then echo "  $1 needs root (run with sudo)"; return 1; fi
    echo "  $1 <- $2"
    sysctl -w "$1=$2" >/dev/null || return 1
}

case "$MODE" in
--status)
    status "status"
    ;;
--fb4)
    status "before (--fb4)"
    set_sysctl debug.nvaccelfb 1 && sleep 1
    set_sysctl debug.nvaccel_iop 1 && sleep 1
    set_sysctl debug.nvaccelfb 4 && sleep 2
    status "after (--fb4)"
    ;;
--arm|*)
    status "before"
    set_sysctl debug.nvaccelfb 1 && sleep 1
    set_sysctl debug.nvaccel_iop 1 && sleep 1
    set_sysctl debug.nvaccelfb 3 && sleep 1
    if [ "$(id -u)" != 0 ]; then
        echo "  restart WindowServer needs root: sudo killall WindowServer"
    else
        echo "  restarting WindowServer so it rebuilds its display pipes"
        killall WindowServer 2>/dev/null || true
        sleep 6
    fi
    status "after"
    ;;
esac

echo "log: $LOG"
