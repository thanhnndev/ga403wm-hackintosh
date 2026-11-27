#!/bin/sh
# kt-probe.sh [seconds=30] [outdir=/var/tmp/kt]: who is kernel_task, per thread and per kext. Needs root. Read-only.
#   spindump of kernel_task (10 ms samples): per-thread stacks with kext names -> CPU share per poller
#   powermetrics tasks+interrupts over the same window: interrupt rate per vector / CPU, wakeups per process
#   ps -M -p 0 before/after: per-thread CPU time of kernel_task
# Nothing is changed. Output is chowned to the console user so it can be read without root.
T=${1:-30}; O=${2:-/var/tmp/kt}; mkdir -p "$O"; ts=$(date +%m%d-%H%M%S)
ps -M -p 0 > "$O/$ts-ps0.txt" 2>&1
powermetrics --samplers tasks,interrupts -i $((T * 1000)) -n 1 > "$O/$ts-pm.txt" 2>&1 &
pm=$!
spindump 0 "$T" 10 -onlyTarget -o "$O/$ts-spindump.txt" > "$O/$ts-spindump.err" 2>&1
wait $pm
ps -M -p 0 > "$O/$ts-ps1.txt" 2>&1
chown -R "$(stat -f %u /dev/console)" "$O"
echo "$O/$ts-*"
