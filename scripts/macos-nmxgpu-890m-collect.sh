#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
#
# After the NMXGPU boot test (macos-nmxgpu-890m-test.sh): collect what amdgpu did on the 890M. Run as root.
#   macos-nmxgpu-890m-collect.sh <out-dir>
# Writes kernel log of this boot (NMXGPU / NMXAccel / amdgpu / [drm]), ioreg of the 890M, /dev/dri, loaded kexts, panics.
set -u
OUT=${1:?out dir}; mkdir -p "$OUT"
log show --last boot --style compact --predicate 'sender == "NMXGPU" OR sender == "NMXAccel" OR eventMessage CONTAINS[c] "amdgpu" OR eventMessage CONTAINS "[drm]" OR eventMessage CONTAINS[c] "nmx" OR eventMessage CONTAINS[c] "xkpi"' > "$OUT/nmx-kernel.txt" 2>&1
log show --last boot --style compact --predicate 'process == "WindowServer" AND messageType == error' > "$OUT/ws-errors.txt" 2>&1
ioreg -l -w0 -r -c IOPCIDevice -n 'pci1002,150e' > "$OUT/ioreg-890m.txt" 2>&1
ioreg -l -w0 -r -c NMXGPU > "$OUT/ioreg-nmxgpu.txt" 2>&1
ioreg -l -w0 -r -c IOFramebuffer > "$OUT/ioreg-fb.txt" 2>&1
ls -la /dev/dri > "$OUT/dev-dri.txt" 2>&1
kmutil showloaded 2>/dev/null | grep -iE 'nmx|strix|nullmoth' > "$OUT/loaded.txt"
sysctl kern.bootargs > "$OUT/bootargs.txt"
system_profiler SPDisplaysDataType > "$OUT/displays.txt" 2>&1
ls -t /Library/Logs/DiagnosticReports | head -5 > "$OUT/reports.txt"
chown -R 501 "$OUT"
echo "collected into $OUT"
