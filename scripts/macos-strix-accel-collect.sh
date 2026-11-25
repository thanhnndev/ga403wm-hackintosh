#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Read-only post-reboot collection for StrixAccel (native display-only accelerator). Never installs, never loads.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(uname -s)" = Darwin ] || { echo 'Run on macOS.' >&2; exit 1; }
D="out/890m-trace/step04-accel-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$D"
ioreg -r -c StrixAccelerator -l > "$D/accel.txt" || true
ioreg -r -c StrixGOPFramebuffer -l > "$D/gop.txt" || true
ioreg -r -c IOAccelDisplayPipe -l > "$D/pipe.txt" || true
ioreg -r -c IOFramebuffer -d1 > "$D/framebuffers.txt" || true
/usr/bin/log show --last 15m --style compact \
  --predicate 'process == "kernel" AND (eventMessage CONTAINS[c] "StrixAccel" OR eventMessage CONTAINS[c] "StrixGOP")' \
  > "$D/kernel-log.txt" 2>/dev/null || true
/usr/bin/log show --last 15m --style compact \
  --predicate 'eventMessage CONTAINS[c] "display pipe" OR eventMessage CONTAINS[c] "IOAccel"' \
  > "$D/windowserver-log.txt" 2>/dev/null || true
kmutil showloaded --list-only 2>/dev/null | awk '/itlmt7925\.strix|IOAcceleratorFamily2|IOSurface/' > "$D/loaded.txt" || true
system_profiler SPDisplaysDataType > "$D/displays.txt" 2>/dev/null || true
echo "== StrixAccel counters"; grep -E '"StrixAccel,' "$D/accel.txt" | sed 's/^[ |]*//' || echo "(no StrixAccelerator instance)"
echo "== StrixGOP sample"; grep -E 'Sample,' "$D/gop.txt" | sed 's/^[ |]*//' || true
echo "== StrixAccel log lines"; grep -c "StrixAccel:" "$D/kernel-log.txt" || true
grep "StrixAccel:" "$D/kernel-log.txt" | head -40 | cut -c1-230
echo "== WindowServer pipe errors in last 15m: $(grep -c 'Unable to find display pipe' "$D/windowserver-log.txt" || true)"
echo "saved: $D"
