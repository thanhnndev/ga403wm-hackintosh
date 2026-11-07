#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# exp.sh LABEL - with SimBench already running (bench-live.txt growing), sample 2x10 s: sim process CPU + fps
L=$1; cd "$(dirname "$0")"
for r in 1 2; do
  n0=$(wc -l < bench-live.txt)
  top -l 2 -s 10 -n 60 -o cpu -stats pid,command,cpu 2>/dev/null | awk '/^PID/{n++} n==2 && !/^PID/ && NF' > "cpu-$L-$r.txt"
  fps=$(tail -n +$((n0+1)) bench-live.txt | awk -F'fps=' '/fps=/{split($2,a," "); s+=a[1]; k++} /slow=/{split($0,b,"slow="); split(b[2],c," "); sl+=c[1]} END{printf "fps %.1f slow %d", s/k, sl}')
  awk -v L="$L" -v r=$r -v f="$fps" '
    /SimMetalHost/{smh+=$NF} /WindowServer/{ws+=$NF} /^ *[0-9]+ +Simulator /{sim+=$NF} /ReportCrash/{rc+=$NF}
    /backboardd/{bb+=$NF} /SimBench/{app+=$NF} /SimRenderServer/{srs+=$NF}
    END{printf "%-14s #%d  %s | SimMetalHost %5.1f  WS %5.1f  Simulator %4.1f  SimRender %4.1f  backboardd %4.1f  app %4.1f  ReportCrash %4.1f\n", L, r, f, smh, ws, sim, srs, bb, app, rc}' "cpu-$L-$r.txt"
done
