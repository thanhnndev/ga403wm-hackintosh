#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Bounded graphics-job stress (Step38): N runs of build/metal-render as a copy named nvmtltest, each under a 30 s perl alarm (macOS has no timeout(1)),
# summary of pass/fail, then the "NullMoth ipdump" lines the kernel printed for every timeout since the start.
# Run it in the background: a failing job holds the run until the kernel's job timeout and GPU reset (~18 s).
#   tools/890m/render-stress.sh [N=6] > /tmp/render-stress.out 2>&1 &
N=${1:-6}; D=$(cd "$(dirname "$0")" && pwd); B=/tmp/nvd/bin
mkdir -p "$B" && cp "$D/build/metal-render" "$B/nvmtltest" || exit 1
START=$(date '+%Y-%m-%d %H:%M:%S'); pass=0; fail=0
for i in $(seq "$N"); do
  out=$(cd "$B" && perl -e 'alarm 30; exec @ARGV' ./nvmtltest 2>&1 | grep -E "^status|^pixel" | tr '\n' ' ')
  case "$out" in *CORRECT*) pass=$((pass+1));; *) fail=$((fail+1));; esac
  echo "run $i: $out"
done
echo "pass $pass fail $fail"
sleep 25   # let the last timeout/reset finish logging
/usr/bin/log show --start "$START" --predicate 'senderImagePath CONTAINS "NMXGPU"' 2>/dev/null \
  | grep -E "ipdump|ring .* timeout|signaled seq|GPU reset|MES failed" | sed -E 's/^[^)]*\) //' | cut -c1-200
