#!/bin/bash
# M2: what does the driver think about the first submission of each new process?
# Reads debug.nmx_* (b20) around each 1-dispatch probe instead of the system log, which carries no kext messages here.
#   bash scripts/890m-m2-probe.sh [runs]
# Each probe is killed after 8 s: a hung submission parks the process in an uninterruptible kernel wait.
set -uo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
TRACE=${TRACE:-$REPO/out/890m-trace/m2-b20}
RUNS=${1:-10}
BIN=/tmp/first-job
mkdir -p "$TRACE"
[[ -x $BIN ]] || xcrun swiftc -O -o "$BIN" "$REPO/tools/890m/metal-first-job.swift" || exit 1
command -v sysctl >/dev/null && sysctl debug.nmx_jobs >/dev/null 2>&1 || { echo "debug.nmx_jobs missing: the b20 kext is not loaded"; exit 2; }

# The plugin must serve the AMD device on request; the deployed one may not read NVMTL_PREFER_VENDOR (only the
# probe build does), so say so instead of reporting a device that was never offered.
NVMTL_PREFER_VENDOR=0x1002 "$REPO/out/890m-trace/nvmtl-vendor-pref/mtl-device-probe" --require-amd >/dev/null 2>&1 ||
    echo "NOTE: this plugin build does not offer the AMD device to a normal process (install the vendor-pref build first)"

cnt() { sysctl -n "debug.nmx_$1" 2>/dev/null; }
snapshot() { printf "%s %s %s %s %s %s %s %s" "$(cnt jobs)" "$(cnt jobs_flushed)" "$(cnt jobs_no_flush)" "$(cnt timeouts)" \
                    "$(cnt last_vmid)" "$(cnt last_pasid)" "$(cnt last_flags)" "$(cnt last_pd)"; }

printf "%-4s %-6s %-8s %-6s %-6s %-7s %-5s %-5s %-6s %s\n" run pid verdict dJobs dFlush dNoFlush timeouts vmid flags pd
: > "$TRACE/runs.txt"
for i in $(seq "$RUNS"); do
    before=$(snapshot)
    NVMTL_PREFER_VENDOR=0x1002 "$BIN" --attempts 1 > "$TRACE/run-$i.txt" 2>&1 &
    pid=$!
    for _ in $(seq 80); do kill -0 $pid 2>/dev/null || break; sleep 0.1; done
    verdict=hang
    if kill -0 $pid 2>/dev/null; then kill -9 $pid 2>/dev/null; else tail -1 "$TRACE/run-$i.txt" | grep -q pass && verdict=pass || verdict=fail; fi
    after=$(snapshot)
    set -- $before; bj=$1; bf=$2; bn=$3; bt=$4
    set -- $after;  aj=$1; af=$2; an=$3; at=$4; av=$5; ap=$6; al=$7; ad=$8
    printf "%-4d %-6d %-8s %-6s %-6s %-7s %-5s %-5s %-6s %s\n" "$i" "$pid" "$verdict" \
        "$((aj-bj))" "$((af-bf))" "$((an-bn))" "$((at-bt))" "$av" "$ap" "$al" "$ad" | tee -a "$TRACE/runs.txt"
    [[ $verdict == hang ]] && { echo "stopped: the device hangs after this, a reboot clears it"; break; }
done
echo "flags: 1 vm_flush 2 pasid_map 4 pipe_sync 8 gpu_reset; -2 timed out"
echo "files: $TRACE"
