#!/bin/bash
# M2: what does the driver think about the first submission of each new process?
# Reads debug.nmx_trace (b21: last 16 submissions of every ring type) around each 1-dispatch probe, instead of the
# system log, which carries no kext messages on this machine.
#   bash scripts/890m-m2-probe.sh [runs]
# Each probe is killed after 8 s: a hung submission parks the process in an uninterruptible kernel wait.
set -uo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
TRACE=${TRACE:-$REPO/out/890m-trace/m2-b21}
RUNS=${1:-10}
BIN=/tmp/first-job
mkdir -p "$TRACE"
[[ -x $BIN ]] || xcrun swiftc -O -o "$BIN" "$REPO/tools/890m/metal-first-job.swift" || exit 1
sysctl debug.nmx_trace >/dev/null 2>&1 || { echo "debug.nmx_trace missing: the b21 kext is not loaded"; exit 2; }

NVMTL_PREFER_VENDOR=0x1002 "$REPO/out/890m-trace/nvmtl-vendor-pref/mtl-device-probe" --require-amd >/dev/null 2>&1 ||
    echo "NOTE: this plugin build does not offer the AMD device to a normal process (install the vendor-pref build first)"

cnt() { sysctl -n "debug.nmx_$1" 2>/dev/null; }
trace() { sysctl -n debug.nmx_trace 2>/dev/null; }
last_seq() { trace | awk 'NR>1{print $1}' | tail -1; }

: > "$TRACE/runs.txt"
echo "columns: seq ring type vmid pasid pd needs_flush flush pasid_map pipe_sync gpu_reset gds"
for i in $(seq "$RUNS"); do
    before_j=$(cnt jobs); before_t=$(cnt timeouts); mark=$(last_seq)
    NVMTL_PREFER_VENDOR=0x1002 "$BIN" --attempts 1 > "$TRACE/run-$i.txt" 2>&1 &
    pid=$!
    for _ in $(seq 80); do kill -0 $pid 2>/dev/null || break; sleep 0.1; done
    verdict=hang
    if kill -0 $pid 2>/dev/null; then kill -9 $pid 2>/dev/null; else tail -1 "$TRACE/run-$i.txt" | grep -q pass && verdict=pass || verdict=fail; fi
    after_j=$(cnt jobs); after_t=$(cnt timeouts)
    {
        printf "run %-2d pid %-6d %-5s jobs +%s timeouts +%s\n" "$i" "$pid" "$verdict" \
               "$((after_j - before_j))" "$((after_t - before_t))"
        trace | awk -v s="${mark:-0}" 'NR>1 && $1+0 > s+0 {print "   " $0}'
    } | tee -a "$TRACE/runs.txt"
    [[ $verdict == hang ]] && { echo "stopped: the device hangs after this, a reboot clears it"; break; }
done
echo "needs_flush = job asked for a flush; flush = this submission actually emitted one."
echo "files: $TRACE"
