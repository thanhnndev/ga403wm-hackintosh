#!/bin/zsh
# StrixS0ix idle mode A/B (0 = stock HLT, 1 = + _CST C2/CC6, 2 = + C3 when no bus master) at true idle.
# The owner starts it and keeps hands off for ~4.5 min: no build, no simulator, no video, no chat streaming.
#   sudo tools/idle-ab.sh [out-dir]          (root: idle mode switch, IdleStats, ktrace)
# Per phase (35 s): package power from the RAPL energy counter over the whole phase, Tctl at the end,
# remote ASTs (IPIs) and hardware interrupts (= CPU wakeups, any idle mode) from a 3 s ktrace (top's IDLEW is always 0
# on this machine, and IdleStats counts nothing in mode 0),
# kernel_task / WindowServer %CPU, frames/s, and the hook's per-state entries and time (S0ix,IdleStats).
# The idle mode is put back to what it was at the start, also on Ctrl-C.
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
here=$(cd "$(dirname "$0")/.." && pwd); SET=$here/build/s0ix-set; [ -x $SET ] || SET=$HOME/develop/projects/ga403wm-hackintosh/build/s0ix-set; [ -n "${SUDO_USER:-}" ] && [ ! -x $SET ] && SET=/Users/$SUDO_USER/develop/projects/ga403wm-hackintosh/build/s0ix-set
out=${1:-/var/tmp/idle-ab-$(date +%m%d-%H%M)}; mkdir -p "$out"; log=$out/idle-ab.txt
w() { perl -e "select(undef,undef,undef,$1)"; }
mode0=$(ioreg -r -c StrixS0ix -d1 | sed -nE 's/.*"S0ix,IdleMode" = ([0-9]+).*/\1/p' | head -1); mode0=${mode0:-0}
trap '$SET idle $mode0 >/dev/null; echo "idle mode back to $mode0 (interrupted)" >>$log; exit 130' INT TERM
rapl() { sysctl -n debug.amdcppc.sensors | sed -E 's/.*rapl=([0-9a-f]+)\/([0-9a-f]+).*/\1 \2/'; }   # unit, energy
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
{
echo "idle A/B $(date)  mode at start: $mode0  $(sysctl -n kern.osversion)"
echo "settling 20 s (hands off)"; w 20
p=0
for m in 0 1 2 0 1 2; do
  p=$((p+1))
  $SET idle $m >/dev/null; w 3; $SET idlestats reset >/dev/null
  set -- $(rapl); u=$1; e0=$((16#$2)); t0=$(now); f0=$(sysctl -n debug.nmxaccel_pipe_perform 2>/dev/null || echo 0)
  ktrace dump -T 3s -b 64 -f S0x0140,S0x0105 $out/ipi-$p-m$m.ktrace >/dev/null 2>&1 &
  top -l 2 -s 30 -stats pid,command,cpu -n 400 > $out/top-$p-m$m.txt 2>/dev/null
  wait
  set -- $(rapl); e1=$((16#$2)); t1=$(now); f1=$(sysctl -n debug.nmxaccel_pipe_perform 2>/dev/null || echo 0)
  s=$(sysctl -n debug.amdcppc.sensors | cut -d' ' -f1)
  $SET idlestats show >/dev/null; st=$(ioreg -r -c StrixS0ix -d1 | grep '"S0ix,IdleStats"' | cut -d'"' -f4)
  # RAPL energy unit: 2^-ESU J, ESU = bits 12:8 of the unit register (AMD MSR C001_0299)
  esu=$(( (16#$u >> 8) & 31 )); de=$(( (e1 - e0) & 0xffffffff ))
  pw=$(perl -e "printf '%.2f', $de / (2**$esu) / ($t1 - $t0)")
  awk '/^PID/{n++; next} n==2 && $1 ~ /^[0-9]+$/ {if ($1==0) k=$(NF); if ($2=="WindowServer") ws=$(NF)}
       END{printf "kernel_task %s%%  WS %s%%", k, ws}' $out/top-$p-m$m.txt > $out/.t
  echo "phase $p mode $m: pkg $pw W  $s  frames $(( (f1-f0)*10/ (${t1%.*}-${t0%.*}) / 10 ))/s  $(cat $out/.t)  stats: $st"
done
$SET idle $mode0 >/dev/null; echo "idle mode back to $mode0  $(date)"
echo "per phase, from the 3 s ktrace: IPIs (remote ASTs) and interrupts (CPU wakeups) per second"
for f in $out/ipi-*.ktrace; do
  ktrace trace -R $f --csv 2>/dev/null > ${f%.ktrace}.csv
  awk -F, 'NR>1 && $3 ~ /REMOTE_AST/ {a++} NR>1 && $3 ~ /^"?INTERRUPT"?$/ && ($4 % 4) == 1 {i++}
           END{printf "  %s: IPIs %d/s  interrupts %d/s\n", FILENAME, a/3, i/3}' ${f%.ktrace}.csv
done
} 2>&1 | tee $log
chmod -R a+r "$out"; echo "results: $log"
