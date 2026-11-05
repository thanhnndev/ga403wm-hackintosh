#!/bin/bash
# Lid test with an RTC alarm: tells "clamshell sleep entry hangs" apart from "lid-open wake hangs".
# One password: the RTC alarm is set N s (default 150) after it. Close the lid right after the password and keep it
# closed until well past the alarm. When the machine wakes (dark wake, lid still closed) this script dumps the kernel
# trace and syncs it to disk at once, so it survives a hang on the later lid open. Ends with "logs: <file>".
N=${1:-150}
# S0IX_PRE: optional root command in the same password step, e.g. S0IX_PRE="$PWD/build/s0ix-set ecwake 2"
OUT=~/ga403-logs/lidrtc-$(date +%Y%m%d-%H%M%S).txt
lid() { ioreg -r -k AppleClamshellState -d1 | awk '/AppleClamshellState/{print $3; exit}'; }
idle() { ioreg -r -c StrixS0ix -d1 | awk '/S0ix,LastIdleMs/{print $3; exit}'; }
wait1() { perl -e 'select(undef,undef,undef,1)'; }
dump() {
  { echo "== $1 $(date '+%H:%M:%S')"; ioreg -r -c StrixS0ix -d1 -w0 | grep -E "SeenGpe0Sts|SeenPm1Sts|EcWake\""
    /usr/bin/log show --start "$T0" --style compact --predicate 'process == "kernel" AND (eventMessage CONTAINS "StrixS0ix" OR eventMessage CONTAINS "Wake reason" OR eventMessage CONTAINS[c] "clamshell" OR eventMessage CONTAINS "will power on" OR eventMessage CONTAINS "sleep #" OR eventMessage CONTAINS "wake #")' 2>&1 | cut -c1-23,60-600 | grep -vE "^Timestamp|LidOpen, ACPower|type 7"
    pmset -g log | grep -E "^$(date +%Y-%m-%d).*(Sleep  |Wake  |DarkWake)" | tail -6; } >> "$OUT"; sync
}
T0=$(date "+%Y-%m-%d %H:%M:%S"); I0=$(idle)
osascript -e "do shell script \"${S0IX_PRE:+$S0IX_PRE; }/usr/bin/pmset schedule wake \\\"\$(/bin/date -v+${N}S '+%m/%d/%y %H:%M:%S')\\\"\" with prompt \"Hẹn RTC wake sau $N s cho test gập nắp\" with administrator privileges" >/dev/null || { echo "cancelled"; exit 1; }
echo "RTC alarm in $N s ($(date -v+${N}S '+%H:%M:%S')). Close the lid now; keep it closed about 4 minutes, then open it."
pkill -x caffeinate
n=0; until [[ $(lid) == Yes ]]; do wait1; ((n++ > 300)) && { echo "lid never closed"; nohup caffeinate -dimsu >/dev/null 2>&1 & exit 1; }; done
echo "lid closed $(date '+%H:%M:%S')"
# the first wake after this point (RTC in dark wake, or a lid open) changes LastIdleMs
until [[ $(idle) != "$I0" ]]; do wait1; done
echo "woke $(date '+%H:%M:%S'), lid $(lid)"; dump "first wake"
until [[ $(lid) == No ]]; do wait1; done
echo "lid open seen $(date '+%H:%M:%S')"
for i in $(seq 15); do wait1; done
nohup caffeinate -dimsu >/dev/null 2>&1 &
dump "after lid open"
echo "logs: $OUT"
