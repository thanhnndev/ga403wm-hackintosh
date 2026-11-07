#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# run.sh LABEL [SECONDS] - cold-launch SimBench on the booted sim, collect its SIMBENCH lines + per-process CPU
L=${1:-run}; S=${2:-12}; cd "$(dirname "$0")"
xcrun simctl terminate booted dev.ga403.simbench >/dev/null 2>&1
xcrun simctl install booted SimBench/build/SimBench.app 2>/dev/null
( ./cpu.sh $((S-3)) "$L" > /dev/null ) &
t0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
perl -e 'alarm shift; exec @ARGV' "$S" xcrun simctl launch --console-pty --terminate-running-process booted dev.ga403.simbench 2>/dev/null | grep --line-buffered SIMBENCH > "bench-$L.txt"
wait
echo "== $L"; cat "bench-$L.txt" | head -3
awk -F'fps=' '/fps=/{split($2,a," "); if (NR>3){s+=a[1]; n++}} /slow=/{split($0,b,"slow="); split(b[2],c," "); sl+=c[1]} END{printf "avg fps (after warm-up) %.1f, slow frames total %d\n", s/n, sl}' "bench-$L.txt"
head -12 "cpu-$L.txt"
