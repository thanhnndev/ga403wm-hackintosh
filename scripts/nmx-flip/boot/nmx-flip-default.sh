#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Turns NMXAccel page flips on at boot (mode from /Library/StrixGraphicsFix/nmx-flip.mode, default 2 = VRAM chain).
# Package 1128: also sets the fence table gate debug.nmxaccel_fence_table from /Library/StrixGraphicsFix/nmx-fence-table.mode
# (0 or 1, default 0 = not written; 2 is for own-process tests and is not accepted here). It is written first, before the
# flip, because WindowServer's NVMTL plugin needs it before its first fence call (the plugin re-reads it once a second
# from 1128 on, so a late write is picked up; before that a late write meant properties until WindowServer restarted).
# NMXAccel's sysctls appear when the AuxKC kext loads, which can be after launchd starts this; wait up to 120 s, polling
# every 0.1 s. Both sysctls are registered by the same NMXAccel start, the fence table one first.
MODE=$(cat /Library/StrixGraphicsFix/nmx-flip.mode 2>/dev/null || echo 2)
[[ $MODE =~ ^[0-2]$ ]] || MODE=2
FT=$(cat /Library/StrixGraphicsFix/nmx-fence-table.mode 2>/dev/null || echo 0)
[[ $FT =~ ^[01]$ ]] || FT=0
for i in $(seq 1 1200); do
    if /usr/sbin/sysctl -n debug.nmxaccel_flip >/dev/null 2>&1; then
        if [[ $FT == 1 ]]; then
            if /usr/sbin/sysctl -w debug.nmxaccel_fence_table=1; then
                echo "$(date -u) fence table gate 1 after $((i / 10)).$((i % 10)) s"
            else
                echo "$(date -u) debug.nmxaccel_fence_table not settable (NMXAccel before c19a0a28?)"
            fi
        fi
        /usr/sbin/sysctl -w debug.nmxaccel_flip=$MODE
        echo "$(date -u) flips mode $MODE after $((i / 10)).$((i % 10)) s"
        exit 0
    fi
    /usr/bin/perl -e 'select(undef,undef,undef,0.1)'
done
echo "$(date -u) debug.nmxaccel_flip never appeared"
exit 1
