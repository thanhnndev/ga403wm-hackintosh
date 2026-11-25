#!/bin/zsh
# Who keeps the screen redrawing at idle? Run detached (no Claude background task), hands off.
# Per 30 s phase: frames/s from NMXAccel, package power, Tctl, then the top CPU users (5 s sample).
out=${1:-/tmp/idle-attrib.txt}
w() { perl -e "select(undef,undef,undef,$1)"; }
{
date; w 30
for p in 1 2 3 4; do
  f0=$(sysctl -n debug.nmxaccel_pipe_perform); sysctl -n debug.amdcppc.sensors >/dev/null; w 0.3; sysctl -n debug.amdcppc.sensors >/dev/null
  w 25; s=$(sysctl -n debug.amdcppc.sensors | cut -d' ' -f1,2); f1=$(sysctl -n debug.nmxaccel_pipe_perform)
  echo "phase $p: $s frames $(( (f1-f0)/25 ))/s"
  top -l 2 -s 5 -o cpu -n 10 -stats pid,command,cpu,idlew | tail -10 | sed 's/^/   /'
done
date; echo done
} > "$out" 2>&1
