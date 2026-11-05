#!/bin/bash
# Lid close/open test (no root): stops caffeinate (its -s assertion can keep the machine awake on AC with the lid
# closed), waits for the lid to close and open again, then restarts caffeinate and prints the sleep/wake trace.
# Output ends with "logs: <file>". Uses the D3 mode already set (s0ix-set d3 N).
OUT=~/ga403-logs/lid-$(date +%Y%m%d-%H%M%S).txt
lid() { ioreg -r -k AppleClamshellState -d1 | awk '/AppleClamshellState/{print $3; exit}'; }
wait1() { perl -e 'select(undef,undef,undef,1)'; }
T0=$(date "+%Y-%m-%d %H:%M:%S")
pkill -x caffeinate
echo "start $T0: close the lid now, keep it closed about 1 minute, then open it"
n=0; until [[ $(lid) == Yes ]]; do wait1; ((n++ > 600)) && { echo "lid never closed"; break; }; done
TC=$(date "+%H:%M:%S"); echo "lid closed $TC"
n=0; until [[ $(lid) == No ]]; do wait1; ((n++ > 3600)) && break; done
TO=$(date "+%H:%M:%S"); echo "lid open seen $TO"
for i in $(seq 20); do wait1; done
nohup caffeinate -dimsu >/dev/null 2>&1 &
{
  echo "start $T0, closed $TC, open seen $TO"
  /usr/bin/log show --start "$T0" --style compact --predicate 'process == "kernel" AND (eventMessage CONTAINS "StrixS0ix" OR eventMessage CONTAINS "Wake reason" OR eventMessage CONTAINS "Clamshell" OR eventMessage CONTAINS "clamshell" OR eventMessage CONTAINS "System Sleep" OR eventMessage CONTAINS "will power on")' 2>&1 | cut -c1-23,60-600 | grep -vE "^Timestamp|LidOpen, ACPower"
  pmset -g log | grep -E "^$(date +%Y-%m-%d).*(Sleep  |Wake  |DarkWake|Clamshell)" | tail -8
} > "$OUT"
echo "logs: $OUT"
