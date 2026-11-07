#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# after.sh LABEL - full re-measure: reboot the sim, wait 60 s, idle-home CPU, crash count, SimBench cold launch + fps/CPU
L=${1:-after}; cd "$(dirname "$0")"; U=9A81E3CB-7F85-44EF-BC3F-E79B48501803
xcrun simctl shutdown all 2>/dev/null; perl -e 'select(undef,undef,undef,3)'
c0=$(ls ~/Library/Logs/DiagnosticReports | grep -c Mercury)
xcrun simctl boot $U 2>/dev/null; open -a Simulator; perl -e 'select(undef,undef,undef,60)'
./cpu.sh 15 "$L-idle" | head -10
c1=$(ls ~/Library/Logs/DiagnosticReports | grep -c Mercury)
echo "MercuryPosterExtension crashes in the 78 s after boot: $((c1-c0))"
./run.sh "$L-app" 14 | head -8
