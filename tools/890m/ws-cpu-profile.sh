#!/bin/bash
# ws-cpu-profile.sh [modes] [seconds]: WS-CPU.md profile run. Run as ROOT (spindump needs it); the redraw load runs as the
# console user. For each mode (default "none ca color bitmap"): start tools/890m/ws-redraw-load.swift <mode> (none = the
# owner's own load only), let it settle 3 s, then for <seconds> (default 10) record at the same time
#   - spindump of WindowServer only (1 ms interval; a kernel stackshot, WindowServer is not suspended or attached)
#   - WindowServer per-thread user/system CPU (ps -M) and process CPU, and NMXAccel presents (sysctl, read only)
# Output: ~<user>/ga403-logs/ws-cpu-<time>/<mode>.{spin,cpu}.txt. Total about 20 s per mode plus symbolication.
# Changes no setting, writes no sysctl, installs nothing. The load window is 600 pt and closes itself.
set -u
[ "$(id -u)" = 0 ] || { echo "run as root (spindump)"; exit 1; }
modes=${1:-"none ca color bitmap"}; secs=${2:-10}
here=$(cd "$(dirname "$0")" && pwd)
cu=$(stat -f %Su /dev/console); cuid=$(id -u "$cu"); home=$(dscl . -read /Users/"$cu" NFSHomeDirectory | awk '{print $2}')
out=$home/ga403-logs/ws-cpu-$(date +%Y%m%d-%H%M%S); mkdir -p "$out"; chown "$cu" "$out" "$home/ga403-logs"
bin=$out/ws-redraw-load
sudo -u "$cu" swiftc -O "$here/ws-redraw-load.swift" -o "$bin" || { echo "swiftc failed"; exit 1; }
ws=$(pgrep -x WindowServer)
cpu() {   # cpu <seconds> <file>
    k=debug.nmxaccel_flip_submitted
    a=$(ps -M -p "$ws" | tail -n +2); f0=$(sysctl -n $k); c0=$(ps -o utime=,stime= -p "$ws")
    /usr/bin/perl -e "select(undef,undef,undef,$1)"
    b=$(ps -M -p "$ws" | tail -n +2); f1=$(sysctl -n $k); c1=$(ps -o utime=,stime= -p "$ws")
    { echo "presents $((f1-f0)) in $1 s"; echo "proc0 $c0"; echo "proc1 $c1"; echo "== threads before"; echo "$a"; echo "== threads after"; echo "$b"; } > "$2"
}
for m in $modes; do
    lp=""
    if [ "$m" != none ]; then
        launchctl asuser "$cuid" sudo -u "$cu" "$bin" "$m" $((secs + 8)) > "$out/$m.load.txt" 2>&1 &
        lp=$!
        /usr/bin/perl -e 'select(undef,undef,undef,3)'
    fi
    spindump "$ws" "$secs" 1 -onlyTarget -noProcessingWhileSampling -file "$out/$m.spin.txt" > /dev/null 2>&1 &
    sp=$!
    cpu "$secs" "$out/$m.cpu.txt"
    wait $sp
    [ -n "$lp" ] && wait "$lp"
    echo "$m: $(head -1 "$out/$m.cpu.txt")"
done
chown -R "$cu" "$out"
echo "done: $out"
