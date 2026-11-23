#!/bin/bash
# power-readout.sh [samples] [interval_s]: read-only power snapshot of the 890M under the current (working) load.
# Needs NMXGPU with debug.nmx_gpu_metrics (frame-path-kernel bb730aa, eb14cc4, e6938f9). No root, nothing written to the driver.
# One SMU metrics-table read per sample (the PMFW values are already time-filtered; 2 s apart is plenty).
# Prints: pp_features once, then per sample the power / clock / activity lines, the GFXOFF bookkeeping, and the
# flip / VBL rates and PSR state from the frame-path counters over the same interval.
n=${1:-10}
iv=${2:-2}
if ! sysctl -n debug.nmx_gpu_metrics >/dev/null 2>&1; then
    echo "debug.nmx_gpu_metrics missing: this NMXGPU predates the power readout"
    exit 1
fi
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
