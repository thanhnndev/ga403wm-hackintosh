#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Compile + record target-specific Metal evidence. Never install a GPU plugin.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(uname -s)" = Darwin ] || { echo 'Run on macOS.' >&2; exit 1; }
D=$(python3 - <<'PY'
from pathlib import Path
from datetime import datetime, timezone
p = Path('out/890m-trace') / ('step05-metal-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ'))
p.mkdir(parents=True)
print(p)
PY
)
clang -arch x86_64 -mmacosx-version-min=12.0 -fobjc-arc -Wall -Wextra -Werror \
  -framework Foundation -framework Metal -framework IOKit tools/strix_metal_probe.m -o "$D/strix-metal-probe"
clang -std=c11 -Wall -Wextra -Werror -framework IOKit -framework CoreFoundation \
  tools/strix_native_probe.c -o "$D/strix-native-probe"
sw_vers > "$D/os.txt"
uname -v > "$D/kernel.txt"
git status --short --branch > "$D/git-status.txt"
git rev-parse HEAD > "$D/git-head.txt"
METAL=0; NATIVE=0
"$D/strix-metal-probe" > "$D/metal-target.json" 2> "$D/metal.stderr.txt" || METAL=$?
"$D/strix-native-probe" > "$D/native-target.json" 2> "$D/native.stderr.txt" || NATIVE=$?
python3 - "$D" "$METAL" "$NATIVE" <<'PY'
import hashlib, json, pathlib, sys
p = pathlib.Path(sys.argv[1]); metal_exit, native_exit = map(int, sys.argv[2:])
try: report = json.loads((p / 'metal-target.json').read_text())
except ValueError: report = {}
passed = report.get('hardware_890m_pass') is True and report.get('status') == 'PASS-890m-compute-render'
m = {'step': '890M-Metal', 'status': 'PASS-890m-hardware' if passed else 'PENDING-890m-Metal-backend',
     'metal_exit': metal_exit, 'native_exit': native_exit, 'metal_report_status': report.get('status'),
     '890m_hardware_pass': passed, 'installed': False,
     'source_hashes': {name: hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest()
                       for name in ['tools/strix_metal_probe.m', 'tools/strix_native_probe.c', 'include/StrixNativeABI.h']}}
(p / 'manifest.json').write_text(json.dumps(m, indent=2) + '\n')
print(m['status'] + ': ' + str(p))
PY
