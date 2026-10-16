#!/bin/bash
# One post-reboot round: confirm the actual per-CPU PAT, (clear A/B if the driver has the counters), then desktop CPU.
# Use osascript administrator privileges. Stops before the rest if the expected PAT is not loaded.
# The clear A/B needs the VRAM-clear NVRMFB (dropped 2026-10-13); without debug.nvrmfb_clear_mode it is skipped.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(id -u)" = 0 ] || { echo 'Use osascript with administrator privileges'; exit 1; }
OUT="build/ws-pat-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
sysctl -n debug.amdcppc.cache > "$OUT/pat.txt"
/usr/bin/python3 -I - "$OUT/pat.txt" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
rows=re.findall(r'cpu(\d+) PAT=([0-9a-f]+) PA6=(\d+) MTRRdef=([0-9a-f]+) valid=(\d+)',s)
if len(rows)!=24 or {int(r[0]) for r in rows}!=set(range(24)):
 raise SystemExit('STOP: incomplete PAT audit; load AmdCppc 0.2.1 first')
if any(int(pat,16)!=0x0001010600070106 or pa6!='1' or valid!='1' for cpu,pat,pa6,mtrr,valid in rows):
 raise SystemExit('STOP: PA6 WC table not active on every CPU; do not interpret a benchmark as a patched result')
print('PASS: PAT=0001010600070106, PA6=WC on all 24 CPUs')
PY
if OLD_MODE=$(sysctl -n debug.nvrmfb_clear_mode 2>/dev/null); then
  trap 'sysctl -w debug.nvrmfb_clear_mode="$OLD_MODE" >/dev/null' EXIT
  bash scripts/macos-nvrmfb-vramclear-ab.sh > "$OUT/clear-ab.txt"
  cat "$OUT/clear-ab.txt"
else
  echo 'clear A/B skipped: no debug.nvrmfb_clear_mode (upstream clear; use scripts/macos-vramtest.sh for the grant time)'
fi
/usr/bin/python3 scripts/macos-ws-cpu.py --seconds 10 --label pat-wc-post-reboot > "$OUT/windowserver.txt"
cat "$OUT/windowserver.txt"
echo "Saved: $OUT"
