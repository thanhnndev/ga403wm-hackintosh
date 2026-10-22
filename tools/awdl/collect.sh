#!/bin/bash
# Collects everything the AWDL tracing produces in one go, so a round of
# "reboot -> run this -> paste the output" takes one command instead of four.
#
#   bash tools/awdl/collect.sh > /tmp/awdl.txt
#
# The output has three parts:
#   1. the core driver's ring (ioreg "m3-log"): the RX/TX statistics, the AWDL
#      RX forensics (does a buffer carry Apple's OUI / the AWDL action header /
#      AWDL's BSSID) and the near-miss dumps
#   2. the native driver's ring (NVRAM "itlmt-native-trace"): the Family's
#      configure sequence and the sync-frame template
#   3. the interface state (awdl0, the associated AP's channel)
set -u

echo "=== date ==="
date

echo "=== awdl0 ==="
ifconfig awdl0 2>&1 | head -3

echo "=== awdl stat (core ring) ==="
ioreg -l -w0 2>/dev/null | grep -o '"m3-log" = "[^"]*"' | tr ';' '\n' | grep -iE "awdl (stat|rxstat)" | tail -6

echo "=== awdl rx forensics (core ring) ==="
ioreg -l -w0 2>/dev/null | grep -o '"m3-log" = "[^"]*"' | tr ';' '\n' | grep -iE "awdl (rx fx|fx |af near miss|af rx|rx hdr)" | tail -30

echo "=== awdl native trace ==="
nvram -p 2>/dev/null | grep itlmt-native-trace | tr ';' '\n' | grep -iE "awdl:" | tail -40

echo "=== channel ==="
system_profiler SPAirPortDataType 2>/dev/null | grep -E "Channel:" | head -2
