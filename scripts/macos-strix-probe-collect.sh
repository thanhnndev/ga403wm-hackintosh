#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Capture the already-loaded Step02 service. Never install a kext or change EFI.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(uname -s)" = Darwin ] || { echo 'Run on macOS after loading StrixProbe with strix-probe=1.' >&2; exit 1; }
TRACE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/strix-probe.XXXXXX")
trap 'rm -rf "$TRACE_DIR"' EXIT
ioreg -a -r -c StrixProbe > "$TRACE_DIR/ioreg.plist"
ioreg -a -r -c IOPCIDevice > "$TRACE_DIR/pci-live.plist"
sw_vers > "$TRACE_DIR/sw-vers.txt"
uname -v > "$TRACE_DIR/kernel.txt"
python3 - "$TRACE_DIR/ioreg.plist" <<'PY'
from datetime import datetime, timezone
import hashlib, json, pathlib, plistlib, shutil, sys
source = pathlib.Path(sys.argv[1])
entries = plistlib.loads(source.read_bytes())
if len(entries) != 1 or entries[0].get('TraceStep') != '890M-02':
    raise SystemExit('Expected one Step02 StrixProbe snapshot; no output capture created.')
out = pathlib.Path('out/890m-trace') / ('step02-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ'))
out.mkdir(parents=True)
shutil.copyfile(source, out / 'ioreg.plist')
for name in ('pci-live.plist', 'sw-vers.txt', 'kernel.txt'):
    shutil.copyfile(source.parent / name, out / name)
entry = entries[0]
vfct = entry.get('VFCT,Raw')
if isinstance(vfct, bytes):
    (out / 'VFCT.bin').write_bytes(vfct)
manifest = {'step': '890M-02', 'captured_utc': datetime.now(timezone.utc).isoformat(),
            'ioreg_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'status': 'CAPTURED-runtime-validation-pending',
            'pci_status': entry.get('PCI,Status'), 'console_status': entry.get('Console,Status'),
            'vfct_status': entry.get('VFCT,Status'), 'probe_version': entry.get('ProbeVersion'),
            'snapshot_generation': entry.get('Snapshot,Generation'),
            'snapshot_in_progress': entry.get('Snapshot,InProgress'),
            'pci_acquisition': entry.get('PCI,Acquisition'),
            'refresh_supported': entry.get('Refresh,Supported', False)}
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(out)
PY
