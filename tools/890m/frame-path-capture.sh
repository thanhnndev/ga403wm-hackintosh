#!/bin/bash
# frame-path-capture.sh [seconds=300] [dir]: snapshot both frame-path rings every 4 s (each ring holds ~5-15 s of frames),
# no root needed. Then: for each snapshot pair, tools/890m/frame-path-report.py <dir>/accel-N.txt <dir>/gpu-N.txt
# The owner can note the wall-clock time of a visible stutter; files carry the time in their name.
set -u
secs=${1:-300}; dir=${2:-$HOME/ga403-logs/frame-path-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$dir" || exit 1
sysctl -n debug.nmx_frametrace >/dev/null 2>&1 || { echo "debug.nmx_frametrace missing: the trace build is not loaded"; exit 1; }
end=$(( $(date +%s) + secs ))
while [ "$(date +%s)" -lt "$end" ]; do
    t=$(date +%H%M%S)
    sysctl -n debug.nmxaccel_frametrace > "$dir/accel-$t.txt" 2>/dev/null
    sysctl -n debug.nmx_frametrace > "$dir/gpu-$t.txt" 2>/dev/null
    sysctl -n debug.nmx_gtt > "$dir/gtt-$t.txt" 2>/dev/null   # out-31: GTT/VRAM use per process (absent before out-31)
    perl -e 'select(undef, undef, undef, 4)'
done
for a in "$dir"/accel-*.txt; do
    t=${a##*/accel-}; t=${t%.txt}
    echo "== $t"; python3 "$(dirname "$0")/frame-path-report.py" "$a" "$dir/gpu-$t.txt" | sed -n '4,30p'
done > "$dir/report.txt"
echo "snapshots and report.txt in $dir"
