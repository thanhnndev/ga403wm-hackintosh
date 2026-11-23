#!/bin/bash
# power-readout.sh [samples] [interval_s]: read-only power snapshot of the 890M under the current (working) load.
# Needs NMXGPU with debug.nmx_gpu_metrics (frame-path-kernel bb730aa..e6938f9 + the review fix). No root, nothing written to the driver.
# One SMU metrics-table read per sample (the PMFW values are already time-filtered; 2 s apart is plenty).
# Prints: pp_features once, then per sample the power / clock / activity lines, the GFXOFF bookkeeping, and the
# flip / VBL rates and PSR state from the frame-path counters over the same interval.
#
# power-readout.sh wake [quiet_s]: does reading the metrics itself wake the GFX island (TransferTableSmu2Dram served by
# the PMFW)? Best at a static screen (flips/s near 0). Prints:
#   1. two reads back to back: the gfxoff_ctrl counters printed by read 2 minus read 1 cover read 1's transfer
#      (driver side: hold/exit must not move; the readout takes no gfx_off_ctrl reference);
#   2. quiet: no read for quiet_s (default 60 s, several filter windows), then one read = the unpolled level;
#   3. a 1 Hz poll for quiet_s, last read = the polled level;
#   4. quiet again, one read (brackets load drift).
# If 3 shows gfx mW / gfxclk / gfx activity above 2 and 4 while flips/s stayed the same, the poll wakes GFX: use
# single reads only.
if ! sysctl -n debug.nmx_gpu_metrics >/dev/null 2>&1; then
    echo "debug.nmx_gpu_metrics missing: this NMXGPU predates the power readout"
    exit 1
fi
pick() {  # one-line summary of a gpu_metrics read
    awk '/^gfxoff_ctrl/{c=$3" "$5" "$7} /^power_mw/{p="socket "$3" gfx "$7" soc_rest "$NF} /^clk_mhz/{k="gfxclk "$3" fclk "$7" uclk "$9}
         /^activity_pct/{a="gfx% "$3" vcn% "$5} /^skipped/{p=$0} END{print "ctrl(allow exit hold) " c " | " p " | " k " | " a}'
}
flips() { sysctl -n debug.nmx_flip_notified; }
if [ "${1:-}" = wake ]; then
    q=${2:-60}
    echo "== $(date '+%F %T') wake test, quiet ${q}s"
    r1=$(sysctl -n debug.nmx_gpu_metrics); r2=$(sysctl -n debug.nmx_gpu_metrics)
    echo "back-to-back 1: $(echo "$r1" | pick)"
    echo "back-to-back 2: $(echo "$r2" | pick)"
    f0=$(flips); perl -e "select(undef,undef,undef,$q)"; f1=$(flips)
    echo "after ${q}s quiet (flips/s $(( (f1 - f0) / q ))): $(sysctl -n debug.nmx_gpu_metrics | pick)"
    f0=$(flips)
    for ((i = 1; i < q; i++)); do sysctl -n debug.nmx_gpu_metrics >/dev/null; perl -e 'select(undef,undef,undef,1)'; done
    f1=$(flips)
    echo "after ${q}s at 1 Hz (flips/s $(( (f1 - f0) / q ))): $(sysctl -n debug.nmx_gpu_metrics | pick)"
    f0=$(flips); perl -e "select(undef,undef,undef,$q)"; f1=$(flips)
    echo "after ${q}s quiet (flips/s $(( (f1 - f0) / q ))): $(sysctl -n debug.nmx_gpu_metrics | pick)"
    exit 0
fi
n=${1:-10}
iv=${2:-2}
echo "== $(date '+%F %T') $(sysctl -n kern.osversion) samples $n every ${iv}s"
echo "== pp_features"
sysctl -n debug.nmx_pp_features
r() { sysctl -n debug.nmx_flip_notified debug.nmx_vbl_delivered | tr '\n' ' '; }
prev=$(r)
for ((i = 1; i <= n; i++)); do
    perl -e "select(undef,undef,undef,$iv)"
    cur=$(r)
    echo "== sample $i $(date +%T)"
    sysctl -n debug.nmx_gpu_metrics | grep -vE '^(dpm_enabled|smu workload|ipu_pct|core_clk_mhz|temp_cC)'
    echo "$prev $cur" | awk -v t="$iv" '{printf "frame flips/s %.1f vbl/s %.1f\n", ($3-$1)/t, ($4-$2)/t}'
    sysctl -n debug.nmx_frametrace | grep -m1 '^psr'
    prev=$cur
done
echo "== last full sample"
sysctl -n debug.nmx_gpu_metrics
echo "== top CPU"
ps -Ao pcpu,comm | sort -rn | head -8 | cut -c1-100
