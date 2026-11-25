#!/bin/bash
# Step81: when WindowServer dies the screen drops to the verbose console and the machine usually gets powered off within
# seconds, before logd persists the last ~10 s; the reason for the death was never on disk. Poll WindowServer every second
# and, the moment its pid goes away, copy the last 3 minutes of WindowServer/kernel/loginwindow log to disk and sync.
PATH=/usr/bin:/bin:/usr/sbin:/sbin
D=/Library/NullMoth/wsdeath; mkdir -p "$D"; chmod 755 "$D"
ls -t "$D"/*.log 2>/dev/null | tail -n +21 | xargs rm -f
BOOT=$(sysctl -n kern.boottime | sed -E 's/.*sec = ([0-9]+),.*/\1/')
WS=""
while :; do
  w=$(pgrep -x WindowServer | head -1)
  if [ -n "$WS" ] && [ "$w" != "$WS" ]; then
    f="$D/$(date -u +%Y%m%dT%H%M%SZ)-ws$WS.log"
    { echo "WindowServer $WS gone (now ${w:-none}) at up=$(($(date +%s) - BOOT))s"
      log show --last 3m --style compact --info \
        --predicate 'process == "WindowServer" OR process == "kernel" OR process == "loginwindow" OR process == "ReportCrash" OR process == "watchdogd"' 2>&1 \
        | grep -av 'NullMoth ibprep'
    } > "$f" 2>&1
    sync
  fi
  WS=$w
  sleep 1
done
