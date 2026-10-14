#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# One-run post-reboot collector for StrixAccel 0.1.14 (colour-stage claims on by default, Caps=7).
# Everything the reboot can prove lands in out/890m-trace/step11-*/ : who asked 0x711 and what was answered, whether
# the OLED melt is gone (fps + WindowServer CPU per display), what colour tables arrive on transactions, new refusals.
# Usage: bash scripts/macos-strix-0114-verify.sh [load-seconds]   (no root needed)
set -uo pipefail
cd "$(dirname "$0")/.."
SECS="${1:-8}"
D="out/890m-trace/step11-0114-$(date -u +%Y%m%dT%H%M%SZ)"; mkdir -p "$D"
T="${TMPDIR:-/tmp}/strix-0114"; mkdir -p "$T"
cc -O2 tools/strix_accel_tune.c -framework IOKit -framework CoreFoundation -o "$T/tune" 2>/dev/null
swiftc -O tools/strix_present_load.swift -o "$T/load" 2>/dev/null

ioreg -l -w0 > "$D/ioreg-boot.txt" 2>&1
ioreg -r -c StrixAccelerator -l > "$D/accel-boot.txt" 2>&1
ps -o pid,lstart,command -p "$(pgrep -x WindowServer)" > "$D/windowserver.txt" 2>&1
/usr/bin/log show --boot --style compact --predicate 'process == "kernel" AND eventMessage CONTAINS[c] "StrixAccel"' > "$D/kernel-log.txt" 2>/dev/null
/usr/bin/grep -E "0x711|served|gamma|txn [0-9]+ (pipe-only|validate-noplane)" "$D/kernel-log.txt" > "$D/caps-and-tables.txt"
"$T/tune" > "$D/tune-boot.txt" 2>&1
system_profiler SPDisplaysDataType > "$D/displays.txt" 2>/dev/null

# CPU/fps per display: WindowServer CPU sampled while the present load runs
: > "$D/perf.txt"
for scr in "Built-in Retina Display" "Mi Monitor"; do
  "$T/load" "$SECS" full "$scr" > "$D/load-$(echo "$scr" | tr ' ' _).txt" 2>&1 &
  sleep 3
  cpu=$(top -l 3 -s 1 -pid "$(pgrep -x WindowServer)" -stats cpu | /usr/bin/grep -E '^[0-9]' | tail -1)
  wait
  echo "== $scr WindowServer_cpu=${cpu}%  $(tail -1 "$D/load-$(echo "$scr" | tr ' ' _).txt")" | tee -a "$D/perf.txt"
done
ioreg -r -c StrixAccelerator -l > "$D/accel-after-load.txt" 2>&1
/usr/bin/log show --last 10m --style compact --predicate 'process == "kernel" AND eventMessage CONTAINS[c] "StrixAccel"' > "$D/kernel-log-after.txt" 2>/dev/null
/usr/bin/grep -E "gamma|pipe-only|noplane" "$D/kernel-log-after.txt" | head -60 > "$D/tables-after.txt"

/usr/bin/python3 -I - "$D" <<'PY'
import pathlib, re, sys
d = pathlib.Path(sys.argv[1])
a = (d/'accel-after-load.txt').read_text(errors='replace')
def g(k, s=a):
    m = re.search(r'"%s"\s*=\s*("[^"]*"|-?\d+)' % re.escape(k), s); return m.group(1).strip('"') if m else None
out = []
for k in ('Version','Gate','Tune,Caps','AGDC,CapServed','AGDC,CapFromWS','AGDC,CapFromOther','AGDC,CapLastClient',
          'AGDC,CapSeq','AGDC,FbCap','AGDC,Refused','AGDC,RefusedSeen','Txn,GammaSeen','Txn,PipeOnlySeen',
          'Transactions','Copied','Skipped','ValidateFail','Copy,Frames'):
    out.append('%-22s %s' % (k, g('StrixAccel,'+k)))
perf = (d/'perf.txt').read_text()
out += ['', perf.strip()]
cpus = re.findall(r'Built-in.*?cpu=([\d.]+)%', perf)
if cpus:
    c = float(cpus[0])
    out.append('VERDICT oled-melt: %s (WindowServer %.0f%%, baseline 1150%%)' % ('GONE' if c < 300 else 'PARTIAL' if c < 900 else 'STILL MELTING', c))
served = int(g('AGDC,CapServed') or 0)
out.append('VERDICT claims served: %s' % ('yes' if served else 'NO - descriptor rejected or nobody asked, see caps-and-tables.txt'))
gs = int(g('Txn,GammaSeen') or 0)
out.append('VERDICT tables on transactions: %s' % ('none seen (stages claimed, nothing delivered / identity)' if gs == 0 else '%d seen, bytes in tables-after.txt - check identity' % gs))
(d/'SUMMARY.txt').write_text('\n'.join(out)+'\n'); print('\n'.join(out))
PY
echo "saved: $D"
