#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Build/review evidence only; every attempt is preserved. No installation.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(uname -s)" = Darwin ] || { echo 'Run on macOS.' >&2; exit 1; }
D=$(python3 - <<'PY'
from pathlib import Path
from datetime import datetime, timezone
p = Path('out/890m-trace') / ('step05-native-build-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ'))
p.mkdir(parents=True)
print(p)
PY
)
sw_vers > "$D/os.txt"
uname -v > "$D/kernel.txt"
git status --short --branch > "$D/git-status.txt"
git rev-parse HEAD > "$D/git-head.txt"
BUILD=0
bash scripts/build.sh StrixAccel > "$D/build.stdout.txt" 2> "$D/build.stderr.txt" || BUILD=$?
if [ "$BUILD" -eq 0 ]; then
  cp -R build/StrixAccel.kext "$D/"
  LIBRARIES=0
  kmutil libraries -p "$D/StrixAccel.kext" --all-symbols > "$D/libraries.stdout.txt" 2> "$D/libraries.stderr.txt" || LIBRARIES=$?
else LIBRARIES=1; fi
python3 - "$D" "$BUILD" "$LIBRARIES" <<'PY'
import hashlib, json, pathlib, plistlib, re, subprocess, sys
p = pathlib.Path(sys.argv[1]); build, libraries = map(int, sys.argv[2:])
m = {'step': '890M-native-ABI', 'status': 'BUILD-FAILED', 'build_exit': build,
     'libraries_exit': libraries, 'installed': False, 'runtime_tested': False}
sources = list(pathlib.Path('kexts/StrixAccel').glob('*')) + [pathlib.Path('include/StrixNativeABI.h'),
          pathlib.Path('scripts/build.sh'), pathlib.Path('tools/strix_native_probe.c')]
m['source_hashes'] = {str(f): hashlib.sha256(f.read_bytes()).hexdigest() for f in sources if f.is_file()}
if not build:
    bundle = p / 'StrixAccel.kext'; binary = bundle / 'Contents/MacOS/StrixAccel'
    plist = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
    imports = set(subprocess.check_output(['nm', '-uj', str(binary)], text=True).splitlines())
    exports = set(subprocess.check_output(['nm', '-gUj', str(binary)], text=True).splitlines())
    header = subprocess.check_output(['otool', '-hv', str(binary)], text=True)
    (p / 'imports.txt').write_text('\n'.join(sorted(imports)) + '\n')
    (p / 'macho-header.txt').write_text(header)
    owners = re.findall(r'^\s*(_\S+) in .*?: (com\.[^ ]+) \(', (p / 'libraries.stdout.txt').read_text(), re.M)
    providers = {owner for _, owner in owners}; missing = sorted(imports - {symbol for symbol, _ in owners})
    undeclared = sorted(providers - set(plist['OSBundleLibraries']))
    structural = '_kmod_info' in exports and 'X86_64' in header and bool(re.search(r'\bKEXT_?BUNDLE\b', header))
    forbidden = any(re.search(r'___cxa_atexit|___cxa_throw|___gxx_personality', symbol) for symbol in imports)
    m.update({'imports': len(imports), 'missing_library_symbols': missing, 'undeclared_providers': undeclared,
              'providers': sorted(providers), 'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
              'version': plist['CFBundleVersion'], 'macho_valid': structural, 'forbidden_cpp_runtime': forbidden})
    m['status'] = 'LINKED-reviewed-runtime-pending' if not libraries and structural and not forbidden and not missing and not undeclared else 'VALIDATION-FAILED'
(p / 'manifest.json').write_text(json.dumps(m, indent=2) + '\n')
print(m['status'] + ': ' + str(p))
raise SystemExit(0 if m['status'] == 'LINKED-reviewed-runtime-pending' else 1)
PY
