#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Read-only post-reboot collection for the StrixGOP 0.1.5 AUX brightness. Never installs, never writes DPCD.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(uname -s)" = Darwin ] || { echo 'Run on macOS.' >&2; exit 1; }
D="out/890m-trace/step05-brightness-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$D"
ioreg -r -c StrixGOPFramebuffer -l > "$D/gop.txt" || true
ioreg -r -c IODisplayParameterHandler -l > "$D/handler.txt" || true
ioreg -r -c AppleBacklightDisplay -l > "$D/backlight-display.txt" || true
ioreg -r -c AppleDisplay -l > "$D/apple-display.txt" || true
/usr/bin/log show --last 20m --style compact \
  --predicate 'process == "kernel" AND eventMessage CONTAINS[c] "StrixGOP"' > "$D/kernel-log.txt" 2>/dev/null || true
echo "== StrixGOP version / aux / backlight properties"
grep -E '"(StrixGOPVersion|Aux,|Backlight,)' "$D/gop.txt" | sed 's/^[ |]*//' || true
echo "== kernel log"
grep -E "StrixGOP: (aux|eDP|backlight)" "$D/kernel-log.txt" | cut -c1-240 | head -40 || true
echo "== display class"
if [ -s "$D/backlight-display.txt" ]; then echo "AppleBacklightDisplay present"; else echo "no AppleBacklightDisplay (plain AppleDisplay: $(grep -c AppleDisplay "$D/apple-display.txt" || true))"; fi
grep -E 'IODisplayParameters|brightness' "$D/backlight-display.txt" | head -8 | sed 's/^[ |]*//' || true
echo "saved: $D"
