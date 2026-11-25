#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Turns NMXAccel page flips on at boot (mode from /Library/StrixGraphicsFix/nmx-flip.mode, default 2 = VRAM chain).
# NMXAccel's sysctls appear when the AuxKC kext loads, which can be after launchd starts this; wait up to 120 s.
MODE=$(cat /Library/StrixGraphicsFix/nmx-flip.mode 2>/dev/null || echo 2)
[[ $MODE =~ ^[0-2]$ ]] || MODE=2
for i in $(seq 1 240); do
    if /usr/sbin/sysctl -n debug.nmxaccel_flip >/dev/null 2>&1; then
        /usr/sbin/sysctl -w debug.nmxaccel_flip=$MODE
        echo "$(date -u) flips mode $MODE after $((i / 2)) s"
        exit 0
    fi
    /usr/bin/perl -e 'select(undef,undef,undef,0.5)'
done
echo "$(date -u) debug.nmxaccel_flip never appeared"
exit 1
