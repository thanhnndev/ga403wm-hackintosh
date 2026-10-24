#!/bin/bash
# Decode ONLY the newest macOS boot(s) from the APFS volume, from Linux, in ~1 minute (not the whole 14 GB archive).
#
#   [EXTRA_PROCS=Terminal,osascript,tccd] scripts/trace-last-boot.sh [boots=1] [persist_files=6]   # asks for pkexec itself
#
# Output (kernel / WindowServer / launchd / loginwindow / anything mentioning NMX, noise dropped):
#   ~/ga403-logs/last-boot.txt        "SECONDS-SINCE-BOOT process message"
# and a one-screen verdict on stdout (did amdgpu init, did NMXGPUFB/AGDC/pipe come up, last line before a freeze).
# uuidtext (600 MB) is cached in ~/.cache/ga403/logarchive and refreshed with rsync, Persist is copied fresh each run.
set -euo pipefail
BOOTS=${1:-1}; NFILES=${2:-6}
DEV=${DEV:-/dev/nvme0n1p4}; MNT=${MNT:-/mnt/macos-vol0}
CACHE=$HOME/.cache/ga403/logarchive; OUT=$HOME/ga403-logs; BIN=$HOME/.cache/ga403/macos-unifiedlogs/examples/target/release/unifiedlog_iterator
HERE=$(cd "$(dirname "$0")" && pwd)
[[ -x $BIN ]] || { echo "build the parser first: bash $HERE/decode-unified-log.sh (see its header)"; exit 1; }
mkdir -p "$CACHE" "$OUT"

if ! findmnt -rn "$MNT" >/dev/null; then
  pkexec bash -c "mkdir -p $MNT && mount -t apfs -o ro,vol=0 $DEV $MNT"
fi
D=$MNT/private/var/db
# the diagnostics tree is root-only: copy the newest Persist files + the small dirs, rsync uuidtext, chown to us
pkexec bash -c "
  set -e
  rm -rf $CACHE/Persist $CACHE/Special $CACHE/HighVolume $CACHE/Signpost $CACHE/timesync $CACHE/dsc; mkdir -p $CACHE/Persist
  for f in \$(ls $D/diagnostics/Persist | sort | tail -$NFILES); do cp $D/diagnostics/Persist/\$f $CACHE/Persist/; done
  cp -r $D/diagnostics/Special $D/diagnostics/HighVolume $D/diagnostics/Signpost $D/diagnostics/timesync $CACHE/ 2>/dev/null || true
  rsync -a --ignore-existing $D/uuidtext/ $CACHE/
  chown -R $(id -u):$(id -g) $CACHE"

F=$(mktemp -u); mkfifo "$F"; trap 'rm -f "$F"' EXIT
python3 -I - "$F" "$BOOTS" "$OUT/last-boot.txt" <<'PY' &
import sys, os, json, re, collections
fifo, nboots, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
noise = re.compile(r'armwatch|Failed to get|getPixelInformation|surf\+|NVRM-xnu|NVMTL|Found class|childPublished|duplicate reports')
keep = {'kernel', 'WindowServer', 'launchd', 'loginwindow', 'kernelmanagerd', 'ReportCrash'} | set(filter(None, os.environ.get('EXTRA_PROCS', '').split(',')))
rows = []
for l in open(fifo):
    try: d = json.loads(l)
    except ValueError: continue
    p = d.get('process', '').split('/')[-1]; m = d.get('message', '').strip().replace('\n', ' | ')[:300]
    if (p in keep or 'NMX' in m) and not (p == 'kernel' and noise.search(m)):
        rows.append((d.get('boot_uuid'), d['time'] / 1e9, p, m))
first = {}
for b, t, *_ in rows: first[b] = min(first.get(b, t), t)
last = sorted(first, key=first.get)[-nboots:]
with open(out, 'w') as o:
    for b, t, p, m in sorted(rows, key=lambda r: r[1]):
        if b in last: o.write('%7.2f %-14s %s\n' % (t - first[b], p[:14], m))
PY
"$BIN" -m log-archive -i "$CACHE" -o "$F" -f jsonl >/dev/null 2>&1 || true
wait
L=$OUT/last-boot.txt
echo "== $(wc -l < "$L") lines -> $L   (boot lasted $(tail -1 "$L" | awk '{print $1}') s)"
g() { grep -m1 -E "$1" "$L" || echo "  (none)"; }
echo "-- amdgpu init:";            g 'SMU is initialized successfully|Fatal error during GPU init'
echo "-- PSP firmware failures:";  grep -c 'failed to load ucode' "$L" || true
echo "-- NMXGPUFB / AGDC / pipe:"; g 'NMXGPUFB published'; g 'AGDC: UP'; g 'newUserClient\(type 4'; g 'iop: K6 transaction'
echo "-- display seen by NVIDIA:"; g 'NVAccel: headless check'
echo "-- last 6 lines (a freeze = the log just stops):"; tail -6 "$L" | cut -c1-200
