#!/bin/zsh
# clean idle A/B: run while nobody touches the machine and no chat is streaming
out=${1:-/tmp/cpu-idle-ab.txt}; SET=$(cd "$(dirname "$0")/.." && pwd)/build/s0ix-set
w() { perl -e "select(undef,undef,undef,$1)"; }
{
date; w 25
for m in 0 1 0 1 0 1; do
  $SET idle $m >/dev/null; w 3; $SET idlestats reset >/dev/null
  f0=$(sysctl -n debug.nmxaccel_pipe_perform); sysctl -n debug.amdcppc.sensors >/dev/null; w 0.3; sysctl -n debug.amdcppc.sensors >/dev/null
  cpu=$(iostat -w 25 -c 2 | tail -1 | awk '{print "us "$(NF-2)" sy "$(NF-1)" id "$NF}')
  s=$(sysctl -n debug.amdcppc.sensors | cut -d' ' -f1,2); f1=$(sysctl -n debug.nmxaccel_pipe_perform)
  $SET idlestats show >/dev/null; st=$(ioreg -r -c StrixS0ix -d1 | grep IdleStats | cut -d'"' -f4 | cut -d, -f1,2)
  ws=$(ps -p $(pgrep -x WindowServer) -o %cpu=)
  echo "mode=$m $s | frames $(( (f1-f0)/25 ))/s | $cpu | WS $ws% | $st"
done
$SET idle 1 >/dev/null; echo "left in idle mode 1"; date
} > $out 2>&1
