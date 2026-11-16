#!/bin/zsh
# Daily health probe: one comparable summary per boot/state. No root needed; with sudo it adds IPIs/interrupts.
#   tools/health-probe.sh [label] [seconds=60] [out-dir]
set -u
label=${1:-probe}; T=${2:-60}; out=${3:-/var/tmp/health-$(date +%m%d)}; mkdir -p "$out"
f=$out/$(date +%H%M%S)-$label.txt
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
rapl() { sysctl -n debug.amdcppc.sensors | sed -E 's/.*rapl=([0-9a-f]+)\/([0-9a-f]+).*/\1 \2/'; }
tctl() { sysctl -n debug.amdcppc.sensors | sed -E 's/.*tctl=([0-9]+).*/\1/'; }
bat() { ioreg -r -c AppleSmartBattery -d1 | awk -F' = ' '/"AppleRawCurrentCapacity"/{c=$2} /"Voltage" =/{v=$2} /"ExternalConnected"/{e=$2} END{print c, v, e}'; }
vm() { vm_stat | awk -F: '/wired down/{w=$2} /occupied by compressor/{c=$2} /stored in compressor/{s=$2} END{printf "wired %.1f GB, compressor %.1f GB (holds %.1f GB)", w*4096/2^30, c*4096/2^30, s*4096/2^30}'; }
{
echo "== health probe '$label'  $(date '+%F %T')  boot $(sysctl -n kern.boottime | sed -E 's/.*} //')  ${T}s"
echo "macOS $(sw_vers -productVersion) ($(sysctl -n kern.osversion)); NMXGPU $(kextstat 2>/dev/null | grep -o 'com.nullmoth.NMXGPU ([^)]*) [0-9A-F]\{8\}' | awk '{print $NF}'); Chrome running: $(pgrep -x 'Google Chrome' >/dev/null && echo yes || echo no); video decoders: $(pgrep -c VTDecoderXPCService 2>/dev/null || pgrep VTDecoderXPCService | wc -l | tr -d ' ')"
set -- $(rapl); u=$1; e0=$((16#$2)); t0=$(now); set -- $(bat); c0=$1; volt=$2; ac=$3
ints0=$(sysctl -n debug.nmx_irq_count 2>/dev/null || echo)
if [ "$(id -u)" = 0 ]; then ktrace dump -T 3s -b 64 -f S0x0140,S0x0105 $f.ktrace >/dev/null 2>&1 & fi
# Tctl sampled every 5 s while top averages over the whole window
( n=$((T/5)); for i in $(seq 1 $n); do perl -e 'select(undef,undef,undef,5)'; tctl; done ) > $f.tctl &
top -l 2 -s $T -o cpu -stats pid,command,cpu,mem -n 15 > $f.top 2>/dev/null
wait
set -- $(rapl); e1=$((16#$2)); t1=$(now); set -- $(bat); c1=$1
esu=$(( (16#$u >> 8) & 31 )); pw=$(perl -e "printf '%.1f', (($e1-$e0)&0xffffffff)/(2**$esu)/($t1-$t0)")
read tmin tavg tmax <<< "$(awk '{v=$1/1000; s+=v; if(!n||v<mn)mn=v; if(v>mx)mx=v; n++} END{printf "%.0f %.0f %.0f", mn, s/n, mx}' $f.tctl)"
st=$(sysctl -n debug.asuswmi.status 2>/dev/null)
fan=$(echo $st | grep -oE 'cpu_fan=[0-9]+|gpu_fan=[0-9]+' | tr '\n' ' ')
prof=$(echo " $st" | grep -oE ' (profile|dgpu_disable|gpu_mux)=[0-9]+' | tr -d '\n')
epp=$(sysctl -n debug.amdcppc.report 2>/dev/null | grep -oE 'epp [0-9]+' | sort | uniq -c | awk '{printf "%s x%s ", $3, $1}')
echo
echo "| metric | value |"
echo "|---|---|"
echo "| package power (RAPL, ${T}s avg) | $pw W |"
echo "| Tctl min/avg/max | $tmin / $tavg / $tmax °C |"
echo "| fans (asuswmi raw) | $fan |"
echo "| profile / GPU | $prof|"
echo "| EPP (value x CPUs listed) | $epp(0 = max performance, 255 = max saving) |"
echo "| idle mode / stats | $(ioreg -r -c StrixS0ix -d1 | sed -nE 's/.*"S0ix,IdleMode" = ([0-9]+).*/mode \1/p') $(ioreg -r -c StrixS0ix -d1 | grep '"S0ix,IdleStats"' | cut -d'"' -f4) |"
echo "| memory | $(vm), swap $(sysctl -n vm.swapusage | awk '{print $6}') |"
echo "| NMX pinned user pages | $(sysctl -n debug.nmx_userwire_pages 2>/dev/null) ($(( $(sysctl -n debug.nmx_userwire_pages 2>/dev/null || echo 0) * 4096 / 1048576 )) MB), userrec live $(sysctl -n debug.nmx_userrec_live 2>/dev/null), pages_live $(sysctl -n debug.nmx_pages_live 2>/dev/null) |"
echo "| NMX frames / fence timeouts | $(sysctl -n debug.nmxaccel_pipe_perform 2>/dev/null) / $(sysctl -n debug.nmxaccel_fence_timeouts 2>/dev/null) |"
if [ "$ac" = "No" ]; then
  echo "| battery discharge (capacity, ${T}s) | $(perl -e "printf '%.1f W (%d mAh)', ($c0-$c1)*$volt/1e6*3600/($t1-$t0), $c0-$c1") |"
else echo "| battery | on AC, $c1 mAh |"; fi
if [ -f $f.ktrace ]; then
  ktrace trace -R $f.ktrace --csv 2>/dev/null | awk -F, 'NR>1 && $3 ~ /REMOTE_AST/ {a++} NR>1 && $3 ~ /^"?INTERRUPT"?$/ && ($4 % 4) == 1 {i++}
    END{printf "| IPIs / interrupts (3 s ktrace) | %d/s / %d/s |\n", a/3, i/3}'
else echo "| IPIs / interrupts | (run with sudo) |"; fi
echo
echo "top 15 by CPU (${T}s average):"
awk '/^PID/{n++} n==2' $f.top
} 2>&1 | tee $f
rm -f $f.tctl; chmod -R a+r "$out" 2>/dev/null; echo "saved: $f"
