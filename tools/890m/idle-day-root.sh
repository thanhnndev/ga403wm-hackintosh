#!/bin/bash
# idle-day-root.sh: the root steps of the idle-day list (docs/IDLE-DAY-TESTS.md, WS-CPU/video area), in one run so the
# owner types the password once. Run as ROOT right after the owner leaves, while the display is still on: it refuses
# to run with the display asleep and never wakes it. Changes no setting, writes no sysctl, installs nothing.
#   1. ws-cpu-profile.sh none 10: WindowServer-only spindump (1 ms) + per-thread CPU + presents, static desktop
#   2. spindump of ALL processes for 10 s (10 ms): which clients commit Core Animation transactions (who dirties)
#   3. the same pair again <gap> s later (default 300; the first Aerial lock-screen burst may land in either)
# Usage: sudo idle-day-root.sh [gap seconds]. Display sleep is 10 min (pmset displaysleep) and counts from the last
# input (typing the password): round 1 takes ~1.5-2 min, so the default gap puts round 2 at ~7 min and the end at ~9 min,
# before the display sleeps. A longer gap skips round 2 (it refuses with the display asleep).
# Output: ~<console user>/ga403-logs/idle-day-<time>/ (plus ws-cpu-<time>/ from step 1). About 9-10 min in all.
set -u
gap=${1:-300}
[ "$(id -u)" = 0 ] || { echo "run as root (spindump)"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
cu=$(stat -f %Su /dev/console); home=$(dscl . -read /Users/"$cu" NFSHomeDirectory | awk '{print $2}')
out=$home/ga403-logs/idle-day-$(date +%Y%m%d-%H%M%S); mkdir -p "$out"
k=debug.nmxaccel_flip_submitted
on() { a=$(sysctl -n $k); /usr/bin/perl -e 'select(undef,undef,undef,2)'; b=$(sysctl -n $k); echo $((b - a)); }
for round in 1 2; do
    p=$(on)
    if [ "$p" -le 0 ]; then echo "round $round: no presents in 2 s (display asleep?) - skipped, nothing woken" | tee -a "$out/log.txt"; break; fi
    echo "round $round $(date +%T): $p presents in 2 s" | tee -a "$out/log.txt"
    ioreg -c IOHIDSystem -d 4 | grep -m1 HIDIdleTime >> "$out/log.txt"
    "$here/ws-cpu-profile.sh" none 10 2>&1 | tee -a "$out/log.txt"
    spindump -noTarget 10 10 -noProcessingWhileSampling -file "$out/all-$round.spin.txt" > /dev/null 2>&1
    ps -axo pid,pcpu,time,comm > "$out/ps-$round.txt"
    echo "round $round all-process spindump: $out/all-$round.spin.txt" | tee -a "$out/log.txt"
    [ $round = 1 ] && /usr/bin/perl -e "select(undef,undef,undef,$gap)"
done
chown -R "$cu" "$out"
echo "done: $out"
