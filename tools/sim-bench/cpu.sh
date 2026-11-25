#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# cpu.sh SECONDS LABEL - average %CPU per process over a window (top, 2 samples; the second is the window average)
S=${1:-15}; L=${2:-run}
top -l 2 -s "$S" -n 40 -o cpu -stats pid,command,cpu,threads 2>/dev/null | awk '/^PID/{n++} n==2 && !/^PID/ && NF' > "cpu-$L.txt"
printf '%s\n' "== $L (${S}s window)"; head -22 "cpu-$L.txt"
awk '{s+=$(NF-1)} END{printf "sum of top-40: %.1f %%\n", s}' "cpu-$L.txt"
