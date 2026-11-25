#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step57: what the foreign OLED's display pipe is doing, from the counters that survive the capped log.
#
#   debug.nvaccel_trx_h4    transaction entry calls whose pipe resolved to head 4 (the OLED)
#   debug.nvaccel_iop_ok_h4 frames actually copied into the OLED's scanout
#   debug.nvaccel_iop_fail  transactions this pipe refused
#
# Three outcomes:
#   trx_h4 == 0            WindowServer never sends the OLED's transactions to this pipe -> instrument the pipe
#                          lookup (newUserClient), not the copy path.
#   trx_h4 > 0, ok_h4 == 0 every frame is skipped as "pixels not ready" -> this script turns on the force-copy
#                          diagnostic and says whether the panel lights up.
#   ok_h4 grows            the copy path runs; judge the panel, not the counter.
#
#   sudo tools/890m/oled-trx-check.sh
set -u

c() { sysctl -n "$1" 2>/dev/null || echo -; }

show() {
    printf '%-30s %s\n' "$*" ""
    printf '  %-28s %s\n' trx_h0 "$(c debug.nvaccel_trx_h0)" \
                          trx_h4 "$(c debug.nvaccel_trx_h4)"
    printf '  %-28s %s\n' iop_ok_h0 "$(c debug.nvaccel_iop_ok_h0)" \
                          iop_ok_h4 "$(c debug.nvaccel_iop_ok_h4)"
    printf '  %-28s %s\n' iop_fail "$(c debug.nvaccel_iop_fail)" \
                          copy_skip "$(c debug.nvaccel_iop_copy_skip)"
    printf '  %-28s %s\n' force_copy "$(c debug.nvaccel_iop_force_copy)" \
                          heads_piped "$(c debug.nvaccel_heads_piped)"
    printf '  %-28s %s\n' agdc_fbmap "$(c debug.nvrmfb_agdc_fbmap)" \
                          ws "$(ps -Ao pid,pcpu,comm | awk '/WindowServer$/{print $1"/"$2; exit}')"
}

show "counters"

t4=$(c debug.nvaccel_trx_h4)
o4=$(c debug.nvaccel_iop_ok_h4)

if [ "$t4" = "0" ]; then
    echo
    echo "No head4 transaction reaches NVAccel's pipe: WindowServer is not driving the OLED through it."
    echo "Next: instrument the display-pipe lookup (newUserClient / IOPresentmentCreateForRegistryID), not the copy."
    exit 0
fi

if [ "$o4" != "0" ]; then
    echo
    echo "The copy path runs (iop_ok_h4=$o4). Look at the panel; counters cannot judge it."
    exit 0
fi

echo
echo "head4 transactions arrive but no frame is copied: the readiness rule is stopping every one."
if [ "$(id -u)" != 0 ]; then
    echo "run with sudo to turn on the force-copy diagnostic"
    exit 1
fi
echo "debug.nvaccel_iop_force_copy <- 1"
sysctl -w debug.nvaccel_iop_force_copy=1 >/dev/null
sleep 3
echo "after 3 s:"
printf '  %-28s %s\n' iop_ok_h4 "$(c debug.nvaccel_iop_ok_h4)" \
                      copy_skip "$(c debug.nvaccel_iop_copy_skip)" \
                      iop_fail "$(c debug.nvaccel_iop_fail)"
echo "If iop_ok_h4 now grows, the panel should show frames: the blocker is nvAccelSurfCopyReady, not the pipe."
echo "If it stays 0, the transaction exits before the copy even with the gate open: read the next iop: log lines."
