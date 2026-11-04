#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Display sleep test for NMXGPU with NMXPowerKeep (NMXBacklight 0.2.0). No root needed. Stage 1 of the sleep plan
# (docs/890M-TRACE.md Step106): display sleep only, the system stays awake.
#   scripts/macos-displaysleep-test.sh [seconds]    sleep the display, wake it after N s (default 20), collect logs
# Pass = NMXPowerKeep held state 1, NMXGPU logged no setPowerState(0), the panel came back, WindowServer did not time out.
# If the machine hangs: hold power 10 s; next boot run this script's collect step (`... collect <start time>`).
set -uo pipefail
OUT=~/ga403-logs/displaysleep-$(date +%Y%m%d-%H%M%S); mkdir -p "$OUT"
collect() {  # $1 = start time
    /usr/bin/log show --start "$1" --predicate 'senderImagePath CONTAINS "NMXGPU" OR senderImagePath CONTAINS "NMXAccel" OR senderImagePath CONTAINS "NMXBacklight" OR eventMessage CONTAINS "amdgpu"' \
        2>/dev/null | cut -c1-240 > "$OUT/kernel.txt"
    /usr/bin/log show --start "$1" --predicate 'process == "WindowServer" AND NOT eventMessage CONTAINS "gamma" AND (eventMessage CONTAINS[c] "timed out" OR eventMessage CONTAINS[c] "timeout" OR eventMessage CONTAINS "displayDidWake" OR eventMessage CONTAINS "displayWillSleep")' \
        2>/dev/null | cut -c1-240 > "$OUT/windowserver.txt"
    pmset -g log | grep -E "Display is turned|Slow|SetState|Failure|Timeout|NMXGPU" | tail -20 > "$OUT/pmset.txt"
    ioreg -r -c NMXPowerKeep -d 1 | grep -E "PowerKeep" > "$OUT/powerkeep.txt"
    echo "== NMXPowerKeep";   cat "$OUT/powerkeep.txt"
    echo "== kernel (power lines)"; grep -E "setPowerState|suspend|resume|NMXPowerKeep|enableAccelerator|displayMode" "$OUT/kernel.txt" | tail -15
    echo "== WindowServer";   tail -8 "$OUT/windowserver.txt"
    echo "== pmset";          cat "$OUT/pmset.txt"
    local bad=0
    grep -q "setPowerState(0)" "$OUT/kernel.txt" && { echo "FAIL: NMXGPU went to state 0 (suspend) on display sleep"; bad=1; }
    # a single CoreAnimation "timed out fence" while the panel is off is a frame that waited on the dark pipe (Step106c);
    # the Step33 failure was a WindowServer display timeout (30000 ms) followed by a hang
    grep -iE "timed out|timeout" "$OUT/windowserver.txt" | grep -qv "timed out fence" && { echo "FAIL: WindowServer timeout"; bad=1; }
    grep -c "timed out fence" "$OUT/windowserver.txt" | awk '$1>0{print "note: "$1" CoreAnimation fence timeout(s) while dark"}'
    grep -q displayDidWake "$OUT/windowserver.txt" || { echo "FAIL: no displayDidWake from WindowServer"; bad=1; }
    grep -q "PowerKeep,State\" = 1" "$OUT/powerkeep.txt" || { echo "FAIL: NMXPowerKeep not loaded or not at state 1"; bad=1; }
    [[ $bad == 0 ]] && echo "PASS: display slept and woke with NMXGPU held on"
    echo "logs: $OUT"; return $bad
}
if [[ ${1:-} == collect ]]; then collect "${2:?start time, e.g. \"2026-11-04 17:00:00\"}"; exit; fi
N=${1:-20}
ioreg -r -c NMXPowerKeep -d 1 | grep -q PowerKeep || { echo "NMXPowerKeep is not loaded (reboot pending? -nmxkeepoff?)"; exit 1; }
T0=$(date "+%Y-%m-%d %H:%M:%S"); echo "$T0" > "$OUT/start"
echo "display off now, back in $N s (start $T0)"
pmset displaysleepnow
perl -e 'select(undef, undef, undef, $ARGV[0])' "$N"
caffeinate -u -t 2
perl -e 'select(undef, undef, undef, 8)'
collect "$T0"
