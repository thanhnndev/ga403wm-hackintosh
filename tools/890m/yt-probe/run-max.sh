#!/bin/zsh
# One maximised scratch-Chrome YouTube run (the trace parts 32-35 A/B): probe.mjs for N seconds while sampling, every
# second, NMXGPU's page-record and userwire counters plus WindowServer CPU time. Never touches the owner's profile.
#
# usage: run-max.sh outdir [seconds=60] [extra chrome flags...]
# writes outdir/{probe,rec,gpu-log}.txt and prints the summary, the measured window and the averages over it.
# rec.txt columns: time userrec_made ws_cputime userwire_pages userrec_live pages_live page_chunks page_free chunks_freed
# (the last three are NMXGPU Step141, out-23; "-" when the running kext has no such sysctl)
D=${1:?outdir}; N=${2:-60}; shift 2 2>/dev/null; EXTRA=("$@")
mkdir -p $D; P=$D/chrome-prof; R=${0:a:h}/probe.mjs; L=$TMPDIR/nvmtl.log; WS=$(pgrep -x WindowServer)
c() { local v=$(sysctl -n $1 2>/dev/null); printf '%s' "${v:--}"; }   # zsh's echo drops a lone "-"
kill_scratch() { pkill -f "user-data-dir=$P"; }
kill_scratch; perl -e 'select(undef,undef,undef,2)'
mark=$(wc -l < $L 2>/dev/null || echo 0)
( while :; do echo "$(date +%T) $(sysctl -n debug.nmx_userrec_made) $(ps -o cputime= -p $WS) $(sysctl -n debug.nmx_userwire_pages) $(sysctl -n debug.nmx_userrec_live) $(c debug.nmx_pages_live) $(c debug.nmx_page_chunks) $(c debug.nmx_page_free) $(c debug.nmx_page_chunks_freed)"
  perl -e 'select(undef,undef,undef,1)'; done ) > $D/rec.txt &
smp=$!
open -na "Google Chrome" --args --user-data-dir=$P --remote-debugging-port=9333 --no-first-run --no-default-browser-check \
  --autoplay-policy=no-user-gesture-required --disable-gpu-sandbox --start-maximized $EXTRA about:blank
for i in {1..30}; do curl -s 127.0.0.1:9333/json >/dev/null && break; perl -e 'select(undef,undef,undef,0.5)'; done
perl -e 'alarm 260; exec @ARGV' node $R 9333 LXb3EKWsInQ hd1080 $N > $D/probe.txt 2>&1
kill_scratch; perl -e 'select(undef,undef,undef,4)'; kill $smp 2>/dev/null
tail -n +$((mark+1)) $L > $D/gpu-log.txt
grep -E 'skipped|measure start|summary' $D/probe.txt | cut -c1-200
a=$(grep 'measure start' $D/probe.txt | cut -c1-8); b=$(grep summary $D/probe.txt | cut -c1-8)
echo "window $a-$b"
grep -E '^[0-9:]+ [0-9]+ ' $D/rec.txt | awk -v a=$a -v b=$b '{split($3,x,":"); t=x[1]*60+x[2]; if(NR>1 && $1>=a && $1<=b){n++; s+=$2-p; w+=t-pt; wp+=$4; rl+=$5} p=$2; pt=t}
  END{if(n) printf "userrec_made %.0f/s, WS %.1f ms/frame (%.0f ms/s), userwire avg %.2f GB, userrec_live avg %.0f\n", s/n, w/n*1000/60, w/n*1000, wp/n*4096/2^30, rl/n}'
# Step141 page chunks: first sample (before), min/max inside the window, last sample (after), chunks freed per phase
grep -E '^[0-9:]+ [0-9]+ ' $D/rec.txt | awk -v a=$a -v b=$b '$7!="-"{
  if(!f){f=1; printf "before: pages_live %d chunks %d free %d chunks_freed %d\n",$6,$7,$8,$9; cf0=$9}
  if($1>=a && $1<=b){ if(!w){w=1; cw=$9; mn=mx=$7; fm=fx=$8} if($7<mn)mn=$7; if($7>mx)mx=$7; if($8<fm)fm=$8; if($8>fx)fx=$8; ce=$9 }
  l6=$6; l7=$7; l8=$8; l9=$9 }
  END{ if(f){ printf "during: chunks %d-%d, free %d-%d pages, chunks freed in window %d (before window %d)\n", mn,mx,fm,fx, ce-cw, cw-cf0;
       printf "after:  pages_live %d chunks %d free %d chunks_freed %d (%d after the window)\n", l6,l7,l8,l9, l9-ce } }'
