#!/bin/zsh
# Daily health probe: one comparable summary per boot/state. No root needed; with sudo it adds IPIs/interrupts.
#   tools/health-probe.sh [label] [seconds=60] [out-dir]
# Every run also records the load that was present and gives a STEADY / LOADED verdict (docs/POWER-FLOOR.md,
# "Measuring protocol"). A number from a LOADED run describes that load, not the idle floor.
#   env LOGRATE=0 skips the 10 s log-volume sample.
set -u
label=${1:-probe}; T=${2:-60}; out=${3:-/var/tmp/health-$(date +%m%d)}; mkdir -p "$out"
f=$out/$(date +%H%M%S)-$label.txt
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
rapl() { sysctl -n debug.amdcppc.sensors | sed -E 's/.*rapl=([0-9a-f]+)\/([0-9a-f]+).*/\1 \2/'; }
tctl() { sysctl -n debug.amdcppc.sensors | sed -E 's/.*tctl=([0-9]+).*/\1/'; }
bat() { ioreg -r -c AppleSmartBattery -d1 | awk -F' = ' '/"AppleRawCurrentCapacity"/{c=$2} /"Voltage" =/{v=$2} /"ExternalConnected"/{e=$2} END{print c, v, e}'; }
vm() { vm_stat | awk -F: '/wired down/{w=$2} /occupied by compressor/{c=$2} /stored in compressor/{s=$2} END{printf "wired %.1f GB, compressor %.1f GB (holds %.1f GB)", w*4096/2^30, c*4096/2^30, s*4096/2^30}'; }
frames() { sysctl -n debug.nmxaccel_pipe_perform 2>/dev/null || echo 0; }
{
boot=$(sysctl -n kern.boottime | sed -E "s/^\{ sec = ([0-9]+),.*/\1/"); upmin=$(( ($(date +%s) - boot) / 60 ))
echo "== health probe '$label'  $(date '+%F %T')  boot $(sysctl -n kern.boottime | sed -E 's/.*} //')  up ${upmin} min  ${T}s"
echo "macOS $(sw_vers -productVersion) ($(sysctl -n kern.osversion)); NMXGPU $(kextstat 2>/dev/null | grep -o 'com.nullmoth.NMXGPU ([^)]*) [0-9A-F]\{8\}' | awk '{print $NF}'); Chrome running: $(pgrep -x 'Google Chrome' >/dev/null && echo yes || echo no); video decoders: $(pgrep VTDecoderXPCService | wc -l | tr -d ' ')"
set -- $(rapl); u=$1; e0=$((16#$2)); t0=$(now); set -- $(bat); c0=$1; volt=$2; ac=$3
fr0=$(frames)
if [ "$(id -u)" = 0 ]; then ktrace dump -T 3s -b 64 -f S0x0140,S0x0105 $f.ktrace >/dev/null 2>&1 & fi
# log volume: lines in 10 s, by process (bounded with perl alarm; no timeout(1) on macOS)
if [ "${LOGRATE:-1}" = 1 ]; then
  ( perl -e 'alarm 10; exec @ARGV' /usr/bin/log stream --style ndjson --level info > $f.log 2>/dev/null ) &
fi
# Tctl sampled every 5 s while top averages over the whole window
( n=$((T/5)); for i in $(seq 1 $n); do perl -e 'select(undef,undef,undef,5)'; tctl; done ) > $f.tctl &
top -l 2 -s $T -o cpu -stats pid,command,cpu,mem -n 40 > $f.top 2>/dev/null
wait
set -- $(rapl); e1=$((16#$2)); t1=$(now); set -- $(bat); c1=$1
fr1=$(frames)
esu=$(( (16#$u >> 8) & 31 )); pw=$(perl -e "printf '%.1f', (($e1-$e0)&0xffffffff)/(2**$esu)/($t1-$t0)")
fps=$(perl -e "printf '%.0f', ($fr1-$fr0)/($t1-$t0)")
read tmin tavg tmax <<< "$(awk '{v=$1/1000; s+=v; if(!n||v<mn)mn=v; if(v>mx)mx=v; n++} END{printf "%.0f %.0f %.0f", mn, s/n, mx}' $f.tctl)"
st=$(sysctl -n debug.asuswmi.status 2>/dev/null)
fan=$(echo $st | grep -oE 'cpu_fan=[0-9]+|gpu_fan=[0-9]+' | tr '\n' ' ')
prof=$(echo " $st" | grep -oE ' (profile|dgpu_disable|gpu_mux)=[0-9]+' | tr -d '\n')
epp=$(sysctl -n debug.amdcppc.report 2>/dev/null | grep -oE 'epp [0-9]+' | sort | uniq -c | awk '{printf "%s x%s ", $3, $1}')
mode=$(ioreg -r -c StrixS0ix -d1 | sed -nE 's/.*"S0ix,IdleMode" = ([0-9]+).*/\1/p')

# ---- steady-state record (from the same top window) ----
pct() { awk -v re="$1" '/^PID/{n++; next} n==2 && $0 ~ re {s+=$(NF-1)} END{printf "%.0f", s}' $f.top; }
build=$(pct 'swift-frontend|clang|xcodebuild|ld64|swift-build|cc1|rustc|cargo|go-build|node .*(tsc|webpack|next build)')
docker=$(pct 'com.docker|hyperkit|qemu|vfkit')
spot=$(pct 'mds|mdworker|mds_stores|corespotlight')
uvfs=$(pct 'UVFSService|fskitd')
diag=$(pct 'diagnosticd')
media=$(pct 'VTEncoder|VTDecoder|genmp4|ffmpeg|AVConference')
ws=$(pct 'WindowServer')
claude=$(pct 'Claude|claude')
kt=$(awk '/^PID/{n++; next} n==2 && $1==0 {print $(NF-1)}' $f.top)
sim=$(pgrep -f launchd_sim >/dev/null && echo yes || echo no)
browsers=$(pgrep -x 'Google Chrome' >/dev/null && echo -n 'Chrome '; pgrep -f 'Microsoft Edge.app/Contents/MacOS' >/dev/null && echo -n 'Edge'; echo)
caff=$(pgrep -x caffeinate >/dev/null && echo yes || echo no)
logs=-; logtop=-
if [ -s $f.log ]; then
  logs=$(( $(wc -l < $f.log) / 10 ))
  logtop=$(sed -nE 's/.*"processImagePath":"[^"]*\/([^"\/]*)".*/\1/p' $f.log | sort | uniq -c | sort -nr | head -4 | awk '{printf "%s %d/s, ", $2, $1/10}')
fi
why=""
[ $upmin -lt 30 ] && why="$why uptime<30min;"
[ ${build:-0} -gt 5 ] && why="$why build ${build}%;"
[ ${docker:-0} -gt 5 ] && why="$why docker ${docker}%;"
[ ${spot:-0} -gt 5 ] && why="$why spotlight ${spot}%;"
[ ${uvfs:-0} -gt 5 ] && why="$why FSKit ${uvfs}%;"
[ ${diag:-0} -gt 3 ] && why="$why diagnosticd ${diag}%;"
[ ${media:-0} -gt 5 ] && why="$why media encode/decode ${media}%;"
[ $sim = yes ] && why="$why simulator;"
[ "$(pgrep VTDecoderXPCService | wc -l | tr -d ' ')" != 0 ] && why="$why video decoder;"
[ ${fps:-0} -gt 10 ] && why="$why screen ${fps} frames/s;"
[ ${ws:-0} -gt 5 ] && why="$why WindowServer ${ws}%;"
verdict=${why:+LOADED:$why}; verdict=${verdict:-STEADY}

echo
echo "| metric | value |"
echo "|---|---|"
echo "| verdict | $verdict |"
echo "| package power (RAPL, ${T}s avg) | $pw W |"
echo "| Tctl min/avg/max | $tmin / $tavg / $tmax °C |"
echo "| fans (asuswmi raw) | $fan |"
echo "| profile / GPU | $prof |"
echo "| EPP (value x CPUs listed) | $epp(0 = max performance, 255 = max saving) |"
echo "| idle mode / stats | mode ${mode:-?} $(ioreg -r -c StrixS0ix -d1 | grep '"S0ix,IdleStats"' | cut -d'"' -f4) |"
echo "| screen frames/s (NMXAccel perform) | $fps |"
echo "| load: build / docker / spotlight / FSKit / diagnosticd / media | ${build}% / ${docker}% / ${spot}% / ${uvfs}% / ${diag}% / ${media}% |"
echo "| load: WindowServer / Claude (all) / kernel_task | ${ws}% / ${claude}% / ${kt}% |"
echo "| simulator / browsers / caffeinate | $sim / ${browsers:-none} / $caff |"
echo "| log lines/s (10 s, info) | $logs: $logtop |"
echo "| load average | $(sysctl -n vm.loadavg | tr -d '{}') |"
echo "| memory | $(vm), swap $(sysctl -n vm.swapusage | awk '{print $6}') |"
echo "| NMX pinned user pages | $(sysctl -n debug.nmx_userwire_pages 2>/dev/null) ($(( $(sysctl -n debug.nmx_userwire_pages 2>/dev/null || echo 0) * 4096 / 1048576 )) MB), userrec live $(sysctl -n debug.nmx_userrec_live 2>/dev/null), pages_live $(sysctl -n debug.nmx_pages_live 2>/dev/null) |"
echo "| NMX frames total / fence timeouts | $fr1 / $(sysctl -n debug.nmxaccel_fence_timeouts 2>/dev/null) |"
if [ "$ac" = "No" ]; then
  echo "| battery discharge (capacity method, coarse below 120 s; ${T}s) | $(perl -e "printf '%.1f W (%d mAh)', ($c0-$c1)*$volt/1e6*3600/($t1-$t0), $c0-$c1") |"
else echo "| battery | on AC, $c1 mAh |"; fi
if [ -f $f.ktrace ]; then
  ktrace trace -R $f.ktrace --csv 2>/dev/null | awk -F, 'NR>1 && $3 ~ /REMOTE_AST/ {a++} NR>1 && $3 ~ /^"?INTERRUPT"?$/ && ($4 % 4) == 1 {i++}
    END{printf "| IPIs / interrupts (3 s ktrace) | %d/s / %d/s |\n", a/3, i/3}'
else echo "| IPIs / interrupts | (run with sudo) |"; fi
echo
echo "top 40 by CPU (${T}s average):"
awk '/^PID/{n++} n==2' $f.top
} 2>&1 | tee $f
rm -f $f.tctl $f.log; chmod -R a+r "$out" 2>/dev/null; echo "saved: $f"
