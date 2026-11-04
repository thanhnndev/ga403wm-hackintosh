#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# System sleep test on the s0ix path (Step107: NMXGPU s0ix suspend, NMXBacklight 0.3.0 timeline). Asks for the admin
# password once (osascript). Sets pmset for the test (no hibernate image, no dark wakes), takes Wi-Fi (en4, no power
# handling in itlmt7925 yet) down, schedules an RTC wake, stops caffeinate and sleeps; after the wake it collects logs,
# brings Wi-Fi back and restarts caffeinate.
#   scripts/macos-syssleep-test.sh [seconds]     sleep, RTC wake after N s (default 60)
#   scripts/macos-syssleep-test.sh collect "<start time>"   logs only (e.g. after a hard power-off)
#   scripts/macos-syssleep-test.sh restore       put back the pmset values saved by the first run
# If it does not wake: press the power button once; if nothing after 30 s, hold it 10 s, then run `collect`.
set -uo pipefail
SAVE=~/ga403-logs/pmset-before-syssleep.txt
OUT=~/ga403-logs/syssleep-$(date +%Y%m%d-%H%M%S); mkdir -p "$OUT"
root() { osascript -e "do shell script \"$1\" with prompt \"$2\" with administrator privileges" >/dev/null; }
collect() {  # $1 = start time
    /usr/bin/log show --start "$1" --predicate 'senderImagePath CONTAINS "NMXGPU" OR senderImagePath CONTAINS "NMXAccel" OR senderImagePath CONTAINS "NMXBacklight" OR senderImagePath CONTAINS "NVRM" OR eventMessage CONTAINS "amdgpu"' \
        2>/dev/null | cut -c1-260 > "$OUT/kernel.txt"
    /usr/bin/log show --start "$1" --predicate 'process == "WindowServer" AND NOT eventMessage CONTAINS "gamma" AND (eventMessage CONTAINS[c] "timed out" OR eventMessage CONTAINS "displayDidWake" OR eventMessage CONTAINS "displayWillSleep" OR eventMessage CONTAINS "System is awake")' \
        2>/dev/null | cut -c1-240 > "$OUT/windowserver.txt"
    pmset -g log | grep -E "^$(date +%Y-%m-%d).*(Sleep|Wake|DarkWake|Failure|Slow|Timeout)" | tail -15 > "$OUT/pmset.txt"
    ioreg -r -c NMXPowerKeep -d 1 | grep PowerKeep > "$OUT/powerkeep.txt"
    echo "== timeline";  grep -E "NMXPowerKeep: system|NullMoth GPU: (setPowerState|suspend|resume)" "$OUT/kernel.txt" | cut -c1-23,100-260
    echo "== amdgpu s0ix / S3 hints"; grep -iE "s0ix|suspend-to-idle|S3|psp.*load|ring .* timeout|failed" "$OUT/kernel.txt" | cut -c1-23,100-260 | head -12
    echo "== WindowServer"; cut -c1-23,100-240 "$OUT/windowserver.txt" | tail -6
    echo "== pmset";     cat "$OUT/pmset.txt"
    echo "== NMXPowerKeep"; cat "$OUT/powerkeep.txt"
    echo "logs: $OUT"
}
case ${1:-} in
collect) collect "${2:?start time}"; exit ;;
restore)
    [[ -f $SAVE ]] || { echo "no saved pmset values"; exit 1; }
    args=$(awk '$1 ~ /^(hibernatemode|standby|powernap|tcpkeepalive|proximitywake|womp)$/ {printf "%s %s ", $1, $2}' "$SAVE")
    root "/usr/bin/pmset -a $args" "Khôi phục pmset như trước test sleep"; echo "pmset restored: $args"; exit ;;
esac
N=${1:-60}
[[ -f $SAVE ]] || pmset -g > "$SAVE"
T0=$(date "+%Y-%m-%d %H:%M:%S"); echo "$T0" > "$OUT/start"
W=$(date -v+${N}S "+%m/%d/%y %H:%M:%S")
echo "start $T0, RTC wake at $W; the screen goes dark now"
pkill -x caffeinate
root "/usr/bin/pmset -a hibernatemode 0 standby 0 powernap 0 tcpkeepalive 0 proximitywake 0 womp 0; /sbin/ifconfig en4 down; /usr/bin/pmset schedule wake '$W'; /usr/bin/pmset sleepnow" "Test sleep cả máy (s0ix): pmset cho test, tắt Wi-Fi, hẹn giờ wake ${N}s, sleep"
# returns once the machine is awake again
perl -e 'select(undef, undef, undef, 15)'
root "/sbin/ifconfig en4 up" "Bật lại Wi-Fi sau test sleep"
nohup caffeinate -dimsu >/dev/null 2>&1 &
disown
collect "$T0"
