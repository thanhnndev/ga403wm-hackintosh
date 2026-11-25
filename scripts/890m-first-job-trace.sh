#!/bin/bash
# M2: which first job of a new process fails, and what did the driver think its VMID/PD/TLB state was?
# The installed NMXGPU already carries the vmflush trace and the b15 IB snapshot (strings: "NullMoth vmflush",
# "ibprep b15"), so this needs no rebuild: run the ladder a few times and join the per-process results with the
# kernel lines for the same time window.
#   bash scripts/890m-first-job-trace.sh [runs]
# Each ladder is killed after 8 s: a job that hangs parks the process in an uninterruptible kernel wait, so a plain
# `wait` would never return (that is how the last two runs of this investigation ended).
set -uo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
TRACE=${TRACE:-$REPO/out/890m-trace/m2-first-job}
RUNS=${1:-10}
BIN=${BIN:-/tmp/compute-ladder}
[[ -x $BIN ]] || { echo "missing $BIN (xcrun swiftc -O tools/890m/metal-compute-ladder.swift -o $BIN)"; exit 1; }
mkdir -p "$TRACE"
START=$(date '+%Y-%m-%d %H:%M:%S')
: > "$TRACE/runs.txt"
echo "start $START, $RUNS runs"

for i in $(seq "$RUNS"); do
    ts=$(date '+%H:%M:%S.%N' | cut -c1-12)
    NVMTL_PREFER_VENDOR=0x1002 "$BIN" > "$TRACE/run-$i.txt" 2>&1 &
    pid=$!
    for _ in $(seq 80); do kill -0 $pid 2>/dev/null || break; sleep 0.1; done
    if kill -0 $pid 2>/dev/null; then
        printf "%s run %2d pid %-6d HANG (killed, uninterruptible)\n" "$ts" "$i" "$pid" | tee -a "$TRACE/runs.txt"
        kill -9 $pid 2>/dev/null
        break
    fi
    wait $pid; rc=$?
    verdict=$(grep -E "^RESULT" "$TRACE/run-$i.txt" | tail -1)
    first=$(grep -E "^n=256" "$TRACE/run-$i.txt" | tail -1)
    printf "%s run %2d pid %-6d rc %d %s | %s\n" "$ts" "$i" "$pid" "$rc" "${verdict:-no result}" "${first:-no n=256 line}" | tee -a "$TRACE/runs.txt"
done

END=$(date '+%Y-%m-%d %H:%M:%S')
echo "end $END"
log show --start "$START" --end "$END" --style compact 2>/dev/null > "$TRACE/kernel-window.txt"
grep -E "NullMoth vmflush|ibprep|ibsnapshot|GPU reset|ring .*timeout|GCVM" "$TRACE/kernel-window.txt" | head -80 > "$TRACE/kernel-trace.txt"
echo "== runs"; cat "$TRACE/runs.txt"
echo "== kernel trace ($(wc -l < "$TRACE/kernel-trace.txt") lines)"; head -40 "$TRACE/kernel-trace.txt"
echo "files: $TRACE"
