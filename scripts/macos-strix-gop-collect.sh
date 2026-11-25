#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Read-only collection, including failed matching/open attempts. Never install.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(uname -s)" = Darwin ] || { echo 'Run on macOS.' >&2; exit 1; }
TRACE_DIR=$(python3 - <<'PY'
from datetime import datetime, timezone
from pathlib import Path
p = Path('out/890m-trace') / ('step03-runtime-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ'))
p.mkdir(parents=True, exist_ok=False)
print(p)
PY
)
ioreg -a -r -c StrixGOPFramebuffer > "$TRACE_DIR/gop.plist"
ioreg -a -r -c IOFramebuffer > "$TRACE_DIR/framebuffers.plist"
ioreg -a -r -c StrixProbe > "$TRACE_DIR/probe.plist"
sw_vers > "$TRACE_DIR/os.txt"
uname -v > "$TRACE_DIR/kernel.txt"
log show --last 10m --style compact --predicate 'process == "kernel" AND eventMessage CONTAINS[c] "StrixGOP"' \
  > "$TRACE_DIR/gop-kernel-log.txt" 2> "$TRACE_DIR/log.stderr.txt" || true
kmutil showloaded --list-only 2> "$TRACE_DIR/kmutil.stderr.txt" |
  awk '/com\.itlmt7925\.strixgop|com\.apple\.iokit\.IOGraphicsFamily/' > "$TRACE_DIR/loaded.txt"
python3 - "$TRACE_DIR" <<'PY'
import hashlib, json, pathlib, plistlib, sys
p = pathlib.Path(sys.argv[1]); raw = (p / 'gop.plist').read_bytes()
# ioreg emits an empty file when no instance of this class exists.
entries = plistlib.loads(raw) if raw.strip() else []
m = {'step': '890M-03', 'status': 'CAPTURED-display-validation-pending', 'services': len(entries),
     'framebuffer_opened': len(entries) == 1 and entries[0].get('Controller,Enabled') is True,
     'gop_version': entries[0].get('StrixGOPVersion') if len(entries) == 1 else None,
     'files_sha256': {f.name: hashlib.sha256(f.read_bytes()).hexdigest() for f in p.iterdir() if f.is_file()},
     'visible_oled_unverified': True, 'acceleration_tested': False}
if len(entries) != 1: m['status'] = 'ACQUISITION-FAILED-no-unique-framebuffer'
(p / 'manifest.json').write_text(json.dumps(m, indent=2) + '\n')
print(m['status'] + ': ' + str(p))
PY
