#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# System sleep test on the s0ix path (Step107: NMXGPU s0ix suspend, NMXBacklight 0.3.0 timeline, 0.4.0 paging wake). Asks for the admin
# password once (osascript). Sets pmset for the test (no hibernate image, no dark wakes), schedules an RTC wake, stops
# caffeinate, waits 10 s and sleeps; after the wake it collects logs and restarts caffeinate. Wi-Fi is left alone.
# Do not touch the keyboard, touchpad or a Bluetooth mouse after the password: input during the 10 s turns the sleep into a
# dark wake, and any HID event right after it wakes the machine fully (first Step107 run: a BLE mouse event 1.6 s in).
#   scripts/macos-syssleep-test.sh [seconds]     sleep, RTC wake after N s (default 60)
#   scripts/macos-syssleep-test.sh collect "<start time>"   logs only (e.g. after a hard power-off)
#   scripts/macos-syssleep-test.sh restore       put back the pmset values saved by the first run
# If it does not wake: press the power button once; if nothing after 30 s, hold it 10 s, then run `collect`.
set -uo pipefail
SAVE=~/ga403-logs/pmset-before-syssleep.txt
OUT=~/ga403-logs/syssleep-$(date +%Y%m%d-%H%M%S); mkdir -p "$OUT"
root() { osascript -e "do shell script \"$1\" with prompt \"$2\" with administrator privileges" >/dev/null; }  # rc != 0: cancelled / wrong password
collect() {  # $1 = start time
    /usr/bin/log show --start "$1" --predicate 'senderImagePath CONTAINS "NMXGPU" OR senderImagePath CONTAINS "NMXAccel" OR senderImagePath CONTAINS "NMXBacklight" OR senderImagePath CONTAINS "NVRM" OR senderImagePath CONTAINS "StrixS0ix" OR eventMessage CONTAINS "amdgpu"' \
        2>/dev/null | cut -c1-260 > "$OUT/kernel.txt"
    /usr/bin/log show --start "$1" --predicate 'process == "WindowServer" AND NOT eventMessage CONTAINS "gamma" AND (eventMessage CONTAINS[c] "timed out" OR eventMessage CONTAINS "displayDidWake" OR eventMessage CONTAINS "displayWillSleep" OR eventMessage CONTAINS "System is awake")' \
        2>/dev/null | cut -c1-240 > "$OUT/windowserver.txt"
    /usr/bin/log show --start "$1" --predicate 'eventMessage CONTAINS "PMRD" AND (eventMessage CONTAINS "START" OR eventMessage CONTAINS "prevented" OR eventMessage CONTAINS "full wake" OR eventMessage CONTAINS "userActivityAtSleep")' \
        2>/dev/null | cut -c1-23,80-220 > "$OUT/pmrd.txt"
    pmset -g log | grep -E "^$(date +%Y-%m-%d).*(Sleep|Wake|DarkWake|Failure|Slow|Timeout)" | tail -15 > "$OUT/pmset.txt"
    ioreg -r -c NMXPowerKeep -d 1 | grep PowerKeep > "$OUT/powerkeep.txt"
    ioreg -r -c StrixS0ix -d 1 | grep 'S0ix,' > "$OUT/s0ix.txt"
    echo "== timeline";  grep -E "StrixS0ix|NMXPowerKeep: system|NullMoth GPU: (setPowerState|suspend|resume)|NMXBacklight: (paging|.*paging wake|framebuffer power)" "$OUT/kernel.txt" | cut -c1-23,100-260
    # Step110: WindowServer waits in IOFramebuffer::_extEntry until NMXAMDFB's pagingState is set again after a sleep
    echo "== NMXAMDFB after wake (PagingWake,Slot >= 0 = wake work armed)"; ioreg -r -c NMXBacklight -d 1 | grep -E 'PagingWake|Backlight,Slot'
    pgrep -x WindowServer >/dev/null && echo "WindowServer pid $(pgrep -x WindowServer)" || echo "WindowServer NOT running"
    echo "== amdgpu s0ix / S3 hints"; grep -iE "s0ix|suspend-to-idle|S3|psp.*load|ring .* timeout|failed" "$OUT/kernel.txt" | cut -c1-23,100-260 | head -12
    echo "== WindowServer"; cut -c1-23,100-240 "$OUT/windowserver.txt" | tail -6
    echo "== root domain (SLEEP_STATE = slept; f->9 then 9->f = dark wake only)"; cat "$OUT/pmrd.txt"
    echo "== pmset";     cat "$OUT/pmset.txt"
    echo "== NMXPowerKeep"; cat "$OUT/powerkeep.txt"
    echo "== StrixS0ix (LastWakeEvent: 0x400 RTC, 0x100 power button, 0x10000+n GPE n, 0x40000000 safety timeout)"; cat "$OUT/s0ix.txt"
    echo "logs: $OUT"
}
case ${1:-} in
collect) collect "${2:?start time}"; exit ;;
restore)
    [[ -f $SAVE ]] || { echo "no saved pmset values"; exit 1; }
    args=$(awk '$1 ~ /^(hibernatemode|standby|powernap|tcpkeepalive|proximitywake|womp)$/ {printf "%s %s ", $1, $2}' "$SAVE")
    root "/usr/bin/pmset -a $args" "Khôi phục pmset như trước test sleep"; echo "pmset restored: $args"; exit ;;
esac
# S0IX_PRE: optional root command run in the same password step, e.g. S0IX_PRE="$PWD/build/s0ix-set d3 3"
HERE=$(cd "$(dirname "$0")" && pwd)
N=${1:-60}
[[ -f $SAVE ]] || pmset -g > "$SAVE"
T0=$(date "+%Y-%m-%d %H:%M:%S"); echo "$T0" > "$OUT/start"
echo "start $T0, sleep 3 s after the password, RTC wake $((N+3)) s after the password. Hands off the keyboard, touchpad and mouse."
# caffeinate is stopped inside the root step, so a cancelled password leaves everything as it was
root "/bin/bash '$HERE/s0ix-tools/syssleep-root.sh' $N ${S0IX_PRE:-}" "Test sleep cả máy (s0ix): pmset cho test, hẹn giờ wake, sleep sau 10 s. Đừng chạm phím/chuột sau khi nhập mật khẩu" \
    || { echo "admin step cancelled or the password was wrong: nothing changed, no sleep"; exit 1; }
# pmset sleepnow returns at once; caffeinate -u declares the user active, so restarting it while the machine is still in
# dark wake wakes it fully (second Step107 run). Wait past the RTC wake (sleep 10 s + N s + margin) before restarting it.
perl -e 'select(undef, undef, undef, $ARGV[0])' $((N+8))
nohup caffeinate -dimsu >/dev/null 2>&1 &
disown
collect "$T0"
