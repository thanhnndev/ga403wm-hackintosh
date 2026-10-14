#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# After a boot that hung on the Apple logo (e.g. OLED only, no HDMI) and a later successful boot, collect everything the
# unified log kept about the hung boot: which Strix/AGDC/NVRM/IOGraphics lines were written and when the boot stopped
# making progress, what WindowServer/loginwindow said, shutdown cause, panic/hang reports, loaded kext versions.
# Read-only. No root needed for most of it (DiagnosticReports may need it; the script says so).
#
#   bash scripts/macos-hang-forensics.sh [hours]        default 8 h
#
# Output: out/890m-trace/hang-<UTC>/ with SUMMARY.txt first. Send that directory (or SUMMARY.txt + kernel-gpu.txt).
set -uo pipefail
cd "$(dirname "$0")/.."
H="${1:-8}"
D="out/890m-trace/hang-$(date -u +%Y%m%dT%H%M%SZ)"; mkdir -p "$D"
LOG=/usr/bin/log

{ date; echo "kern.boottime: $(sysctl -n kern.boottime)"; echo; echo "last reboot:"; last reboot | head -10; } > "$D/boots.txt" 2>&1
sysctl -n kern.bootargs > "$D/bootargs.txt" 2>&1
kmutil showloaded --list-only 2>/dev/null | grep -iE "strix|itlmt|nvrm|nvaccel|nullmoth|asuswmi|amdcppc|applealc" > "$D/loaded-kexts.txt" 2>&1
ls -l /Library/Extensions 2>/dev/null | grep -i strix > "$D/installed-strix.txt"
ioreg -c AppleGPUWrangler -l -w0 > "$D/gpuwrangler.txt" 2>&1
ioreg -r -c IOFramebuffer -l -w0 > "$D/framebuffers.txt" 2>&1
ioreg -r -c StrixAccelerator -l -w0 > "$D/strixaccel.txt" 2>&1
# the ESP-injected gate logs nothing the unified log can decode (no uuidtext); its state lives in the registry
ioreg -r -c StrixMetalGate -l -w0 > "$D/strixmetalgate.txt" 2>&1
ioreg -r -c NVAccel -l -w0 | grep -aE 'MetalPluginName|StrixMetalGate' >> "$D/strixmetalgate.txt" 2>&1

KP='process == "kernel" AND (eventMessage CONTAINS[c] "strix" OR eventMessage CONTAINS[c] "AGDC" OR eventMessage CONTAINS[c] "NVRM" OR eventMessage CONTAINS[c] "NVAccel" OR eventMessage CONTAINS[c] "IOGraphics" OR eventMessage CONTAINS[c] "IOFramebuffer" OR eventMessage CONTAINS[c] "backlight" OR eventMessage CONTAINS[c] "Darwin Kernel Version" OR eventMessage CONTAINS[c] "shutdown cause" OR eventMessage CONTAINS[c] "panic")'
$LOG show --last "${H}h" --style compact --predicate "$KP" > "$D/kernel-gpu.txt" 2>"$D/kernel-gpu.err"

$LOG show --last "${H}h" --style compact --predicate 'process == "WindowServer" OR process == "loginwindow"' > "$D/ws-all.txt" 2>"$D/ws.err"
# the flood of repeated lines (e.g. "Unable to find display pipe") hides everything else: keep a ranked digest too
sed -E 's/^[0-9-]+ [0-9:.]+ +[A-Za-z]+ +[0-9a-fx]+ +[0-9a-fx]+ +//; s/0x[0-9a-f]+/0x…/g; s/[0-9]{3,}/N/g' "$D/ws-all.txt" | sort | uniq -c | sort -rn | head -60 > "$D/ws-digest.txt"

$LOG show --last "${H}h" --style compact --predicate 'eventMessage CONTAINS[c] "shutdown cause" OR eventMessage CONTAINS[c] "Previous shutdown" OR eventMessage CONTAINS[c] "GPUWranglerWaitForPublish"' > "$D/shutdown-and-wrangler.txt" 2>&1

mkdir -p "$D/reports"
find /Library/Logs/DiagnosticReports /private/var/db/PanicReporter ~/Library/Logs/DiagnosticReports -type f -mtime -2 \( -name "*.panic" -o -name "*.hang" -o -name "*.spin" -o -name "*WindowServer*" -o -name "*kernel*" \) 2>/dev/null \
  | head -20 | while read -r f; do cp "$f" "$D/reports/" 2>/dev/null; done

/usr/bin/python3 -I - "$D" <<'PY'
import pathlib, re, sys
d = pathlib.Path(sys.argv[1])
k = (d/'kernel-gpu.txt').read_text(errors='replace').splitlines()
ts = re.compile(r'^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)')
boots, cur = [], None
for line in k:
    m = ts.match(line)
    if not m: continue
    if 'Darwin Kernel Version' in line:
        cur = {'start': m.group(1), 'lines': []}; boots.append(cur)
    elif cur is not None:
        cur['lines'].append(line)
out = ['boots found in the kernel dump: %d' % len(boots), '']
for i, b in enumerate(boots):
    L = b['lines']
    first = ts.match(L[0]).group(1) if L else b['start']
    last = ts.match(L[-1]).group(1) if L else b['start']
    out.append('== boot %d: kernel start %s, GPU/display lines %d, first %s, LAST %s' % (i, b['start'], len(L), first, last))
    for key in ('StrixGOP', 'StrixAccel', 'AGDC', 'NVRM', 'NVAccel', 'strix'):
        n = sum(1 for x in L if key.lower() in x.lower())
        if n: out.append('   %-10s %d lines' % (key, n))
    out.append('   last 12 lines:')
    out += ['     ' + x[:230] for x in L[-12:]]
    out.append('')
ws = (d/'ws-all.txt').read_text(errors='replace').splitlines()
out.append('WindowServer/loginwindow lines in window: %d' % len(ws))
if ws:
    out.append('  first: ' + ws[0][:200]); out.append('  last:  ' + ws[-1][:200])
(d/'SUMMARY.txt').write_text('\n'.join(out) + '\n')
print('\n'.join(out))
PY
echo; echo "saved: $D   (kernel-gpu.err / ws.err hold log(1) errors; reports/ may be empty without root)"
