#!/bin/bash
# M2: what does the driver decide for the first submission of each new process?
# Reads debug.nmx_trace (submissions) and debug.nmx_grab (VMID assignments) around each 1-dispatch probe.
#   bash scripts/890m-m2-probe.sh [runs]
# Each probe is killed after 8 s: a hung submission parks the process in an uninterruptible kernel wait.
set -uo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
TRACE=${TRACE:-$REPO/out/890m-trace/m2-b23}
RUNS=${1:-10}
BIN=/tmp/first-job
mkdir -p "$TRACE"
[[ -x $BIN ]] || xcrun swiftc -O -o "$BIN" "$REPO/tools/890m/metal-first-job.swift" || exit 1
sysctl debug.nmx_trace >/dev/null 2>&1 || { echo "debug.nmx_trace missing: the traced kext is not loaded"; exit 2; }

NVMTL_PREFER_VENDOR=0x1002 "$REPO/out/890m-trace/nvmtl-vendor-pref/mtl-device-probe" --require-amd >/dev/null 2>&1 ||
    echo "NOTE: this plugin build does not offer the AMD device to a normal process (install the vendor-pref build first)"

cnt() { sysctl -n "debug.nmx_$1" 2>/dev/null; }
grab() { sysctl -n debug.nmx_grab 2>/dev/null; }
last_grab() { grab | awk 'NR>1{print $1}' | tail -1; }
last_seq() { sysctl -n debug.nmx_trace 2>/dev/null | awk 'NR>1{print $1}' | tail -1; }

: > "$TRACE/runs.txt"
echo "knobs: umap_cache=$(sysctl -n debug.nmx_umap_cache 2>/dev/null) wbinvd=$(sysctl -n debug.nmx_wbinvd 2>/dev/null)"
echo "submission: seq ring hub type vmid pasid pd needs_flush flush pasid_map pipe_sync gpu_reset gds"
echo "vmid grab : seq hub vmid needs_flush vm_ctx owner pd_new pd_old stray"
for i in $(seq "$RUNS"); do
    before_j=$(cnt jobs); before_t=$(cnt timeouts); before_s=$(cnt grab_stray)
    mark=$(last_seq); gmark=$(last_grab)
    NVMTL_PREFER_VENDOR=0x1002 "$BIN" --attempts 1 > "$TRACE/run-$i.txt" 2>&1 &
    pid=$!
    for _ in $(seq 80); do kill -0 $pid 2>/dev/null || break; sleep 0.1; done
    verdict=hang
    if kill -0 $pid 2>/dev/null; then kill -9 $pid 2>/dev/null; else tail -1 "$TRACE/run-$i.txt" | grep -q pass && verdict=pass || verdict=fail; fi
    after_j=$(cnt jobs); after_t=$(cnt timeouts); after_s=$(cnt grab_stray)
    {
        printf "run %-2d pid %-6d %-5s jobs +%s timeouts +%s grab_stray +%s\n" "$i" "$pid" "$verdict" \
               "$((after_j - before_j))" "$((after_t - before_t))" "$((after_s - before_s))"
        sysctl -n debug.nmx_trace | awk -v s="${mark:-0}" 'NR>1 && $1+0 > s+0 {print "   S " $0}'
        grab | awk -v s="${gmark:-0}" 'NR>1 && $1+0 > s+0 {print "   G " $0}'
    } | tee -a "$TRACE/runs.txt"
    [[ $verdict == hang ]] && { echo "stopped: the device hangs after this, a reboot clears it"; break; }
done
echo "S needs_flush = job asked for a flush; flush = this submission emitted one."
echo "G stray = the VMID skipped the flush while it still belonged to another VM (owner != vm_ctx)."
echo "files: $TRACE"
