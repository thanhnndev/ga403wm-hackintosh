#!/bin/zsh
# Local, ad-free video suite runner. Scratch-profile Chrome only (never the owner's profile, never Edge), no root.
#   run.sh <case|core|all|list> [label=build] [rounds=1]
# Writes results/<label>-<yyyymmdd-hhmm>/ : context.txt (machine state), per case <case>.tsv (per second) and
# <case>.json (summary), table.md. With rounds > 1 each round goes to r1, r2, ... and table.md adds the spread.
# On battery it refuses (power limits differ) unless VS_ALLOW_BATTERY=1. See README.md.
set -u
H=${0:a:h}
what=${1:-list}; label=${2:-build}; rounds=${3:-1}
pause() { perl -e "select(undef,undef,undef,$1)"; }
if [ "$what" = list ]; then
  node -e 'import("'$H'/drive.mjs").then(m=>{for(const[k,v]of Object.entries(m.CASES))console.log(k.padEnd(18),v.todo?"TODO: "+v.todo:(v.kind||v.mode)+" "+(v.clip||"")+(m.CORE.includes(k)?"  [core]":""))})'
  exit 0
fi
case $what in core|all) cases=($(node -e 'import("'$H'/drive.mjs").then(m=>console.log(m.CORE.join(" ")))')) ;; *) cases=($what) ;; esac
if pmset -g batt | grep -q "Battery Power" && [ "${VS_ALLOW_BATTERY:-0}" != 1 ]; then
  echo "on battery: power limits differ from AC, results would not compare. Plug in, or VS_ALLOW_BATTERY=1."; exit 3
fi
out=$H/results/$label-$(date +%Y%m%d-%H%M); mkdir -p $out

kx() { kextstat 2>/dev/null | awk -v k="$1" '$6==k{print $7, $8}'; }
{
  echo "label: $label   cases: ${cases[*]}   rounds: $rounds"
  echo "date: $(date '+%F %T')   uptime:$(uptime | sed -E 's/.*up ([^,]*),.*/ \1/')   boot: $(sysctl -n kern.boottime | sed -E 's/.*} //')"
  echo "macOS $(sw_vers -productVersion) ($(sysctl -n kern.osversion)); $("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version 2>/dev/null)"
  echo "NMXGPU: $(kx com.nullmoth.NMXGPU)   NMXAccel: $(kx com.nullmoth.NMXAccel)   StrixAccel: $(kx com.itlmt7925.strixaccel)"
  echo "park_ms: $(sysctl -n debug.nmx_userptr_park_ms 2>/dev/null)   plugin sha1: $(sysctl -n debug.strixsbx.files 2>/dev/null | tr ';' '\n' | grep -E 'NVMTLDriver$|vulkan_radeon' | sed -E 's|^(.{12}).*/|\1 |' | tr '\n' ' ')"
  echo "power: $(pmset -g batt | sed -n 's/^Now drawing from //p' | tr -d "'")   $(pmset -g batt | grep -o '[0-9]*%; [a-z ]*' | head -1)"
  st=$(sysctl -n debug.asuswmi.status 2>/dev/null)
  echo "asus: $(echo " $st" | grep -oE ' (profile|set_profile|dgpu_disable|gpu_mux|cpu_fan|gpu_fan|panel_overdrive)=[0-9]+' | tr -d '\n')"
  echo "dGPU gate: $(ioreg -r -c StrixDgpuGate -d1 2>/dev/null | sed -n 's/.*"gate-state" = "\(.*\)"/\1/p')"
  echo "EPP: $(sysctl -n debug.amdcppc.report 2>/dev/null | grep -oE 'epp [0-9]+' | sort | uniq -c | awk '{printf "%s x%s ", $3, $1}')"
  echo "Docker running: $(pgrep -q com.docker.backend && echo yes || echo no)   owner Chrome running: $(pgrep -f 'Google Chrome.app/Contents/MacOS/Google Chrome$' >/dev/null && echo yes || echo no)"
  echo "memory: $(vm_stat | awk -F: '/wired down/{w=$2} /occupied by compressor/{c=$2} END{printf "wired %.1f GB, compressor %.1f GB", w*4096/2^30, c*4096/2^30}'), swap $(sysctl -n vm.swapusage | awk '{print $6}')"
  echo "display: $(system_profiler SPDisplaysDataType 2>/dev/null | sed -n 's/.*UI Looks like: //p' | head -1)   Tctl now: $(sysctl -n debug.amdcppc.sensors | sed -E 's/.*tctl=([0-9]+).*/\1/' | awk '{print $1/1000}') C"
  echo "top by CPU (1 s):"
  top -l 2 -s 1 -o cpu -n 12 -stats pid,command,cpu,mem 2>/dev/null | awk '/^PID/{n++} n==2' | sed 's/^/  /'
} > $out/context.txt
cat $out/context.txt | grep -v '^  '

# prime the scratch profile (first launch, shader cache, clip in the file cache) so round 1 starts like the others
VS_MEASURE=2 VS_WARM=1 perl -e 'alarm 60; exec @ARGV' node $H/drive.mjs vp9-1080p60-win $out/.prime >/dev/null 2>&1; rm -rf $out/.prime; pause 3

for r in $(seq 1 $rounds); do
  d=$out; [ $rounds -gt 1 ] && d=$out/r$r && mkdir -p $d
  for c in $cases; do
    perl -e 'alarm 260; exec @ARGV' node $H/drive.mjs $c $d 2> >(grep -v 'shader cache' >&2)
    pause 4
  done
done
node $H/table.mjs $out > $out/table.md
echo "results: $out"
