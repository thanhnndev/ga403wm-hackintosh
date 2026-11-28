#!/bin/bash
# vz-probe.sh - stage 0 of the in-kernel APIC plan (docs/DOCKER-HEAT-PLAN.md (c)): what does Virtualization.framework (VZ) call on
# RyzenHV once hv_vm_create(0x400) is accepted? Needs RyzenHV 0.7.28+ (branch research/vz-probe) and its build/rhv-info.
#
#   scripts/vz-probe.sh [seconds=240] [outdir=~/ga403-logs/vz-probe-<stamp>]
#
# One password: the root part runs behind a single osascript "administrator privileges" dialog. It:
#   1. turns the probe on: `rhv-info hv vzprobe 1` (flag 0x400 accepted as a plain VM, stub traps answer success and log their first 400
#      calls, kern.hv_support shows 1);
#   2. follows the RyzenHV log into rhv-log.txt for `seconds`, or until the file STOP appears in the output directory;
#   3. turns the probe off again, from a trap on EXIT/INT/TERM/HUP, however it ends, and logs the read-back.
# While it waits, start Docker ONCE with UseVirtualizationFramework=true (the owner's or main's step, Docker quit first). The VM is
# expected NOT to boot: there is no in-kernel APIC yet, so the guest gets no interrupts. Quit Docker, put the setting back, then
# `touch <outdir>/STOP` (or wait for the timeout).
# Afterwards, without root: the Virtualization/Docker side of the story goes to vz-unified.txt (log show, last 15 min).
set -u
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
RHV=${RHV_INFO:-$HOME/develop/projects/rhv-wt-cpl/build/rhv-info}

if [ "${1:-}" != "--root" ]; then
    SECS=${1:-240}
    OUT=${2:-$HOME/ga403-logs/vz-probe-$(date +%Y%m%d-%H%M%S)}
    case "$SECS" in ''|*[!0-9]*) echo "seconds must be a number" >&2; exit 1;; esac
    mkdir -p "$OUT" || exit 1
    "$RHV" hv vzprobe >/dev/null 2>&1 || { echo "this RyzenHV does not know vzprobe (needs 0.7.28, research/vz-probe)" >&2; exit 1; }
    echo "VZ probe: up to ${SECS}s, output $OUT"
    echo "After the password: start Docker once with UseVirtualizationFramework=true, then quit it and touch $OUT/STOP."
    osascript -e "do shell script \"/bin/bash '$SELF' --root '$OUT' $SECS '$RHV' $(id -u)\" with administrator privileges" || \
        echo "root part failed or was cancelled; see $OUT/probe.txt" >&2
    log show --last 15m --style compact \
        --predicate 'process CONTAINS[c] "Virtualization" OR process CONTAINS[c] "com.docker" OR subsystem CONTAINS[c] "Virtualization"' \
        > "$OUT/vz-unified.txt" 2>&1
    echo "--- what VZ called (trap lines) ---"
    grep -E "VZ probe|trap (task|thread)" "$OUT/rhv-log.txt" 2>/dev/null | grep -v "pid 0 " | sort | uniq -c | sort -rn | head -60
    echo "files in $OUT"
    exit 0
fi

# ---- root part ----
OUT=$2; SECS=$3; RHV=$4; OWNER=$5
p() { echo "$(date '+%T') $*" >> "$OUT/probe.txt"; }
FOLLOW=
off() {
    "$RHV" hv vzprobe 0 >> "$OUT/probe.txt" 2>&1
    p "probe off, read back: $("$RHV" hv vzprobe 2>&1)"
    [ -n "$FOLLOW" ] && kill "$FOLLOW" 2>/dev/null
    "$RHV" hv status >> "$OUT/probe.txt" 2>&1
    chown -R "$OWNER" "$OUT" 2>/dev/null
}
trap 'off; exit 1' INT TERM HUP
trap 'off' EXIT
p "before: $("$RHV" hv status 2>&1 | tr '\n' ' ')"
"$RHV" log -f > "$OUT/rhv-log.txt" 2>&1 &
FOLLOW=$!
"$RHV" hv vzprobe 1 >> "$OUT/probe.txt" 2>&1 || { p "vzprobe 1 failed"; exit 1; }
p "probe on: $("$RHV" hv vzprobe 2>&1); kern.hv_support=$(sysctl -n kern.hv_support)"
t0=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt "$SECS" ] && [ ! -e "$OUT/STOP" ]; do
    perl -e 'select(undef,undef,undef,2)'
done
p "window over after $(( $(date +%s) - t0 ))s ($( [ -e "$OUT/STOP" ] && echo STOP file || echo timeout ))"
