#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Step02 build evidence only. Does not install, load, edit EFI or reboot.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(uname -s)" = Darwin ] || { echo 'Run this build on macOS with Xcode command line tools.' >&2; exit 1; }
TRACE_DIR=$(python3 - <<'PY'
from datetime import datetime, timezone
from pathlib import Path
p = Path('out/890m-trace') / ('step02-build-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ'))
p.mkdir(parents=True, exist_ok=False)
print(p)
PY
)
git status --short --branch > "$TRACE_DIR/git-status.txt"
git rev-parse HEAD > "$TRACE_DIR/git-head.txt"
uname -a > "$TRACE_DIR/uname.txt"
sw_vers > "$TRACE_DIR/sw-vers.txt"
clang --version > "$TRACE_DIR/clang.txt"
BUILD_EXIT=0
bash scripts/build.sh StrixProbe > "$TRACE_DIR/build.stdout.txt" 2> "$TRACE_DIR/build.stderr.txt" || BUILD_EXIT=$?
VALIDATE_EXIT=0
if [ "$BUILD_EXIT" -eq 0 ]; then
  plutil -lint build/StrixProbe.kext/Contents/Info.plist > "$TRACE_DIR/plist.txt" 2>&1 || VALIDATE_EXIT=$?
  file build/StrixProbe.kext/Contents/MacOS/StrixProbe > "$TRACE_DIR/file.txt"
  otool -hv build/StrixProbe.kext/Contents/MacOS/StrixProbe > "$TRACE_DIR/macho-header.txt"
  nm -um build/StrixProbe.kext/Contents/MacOS/StrixProbe > "$TRACE_DIR/undefined-symbols.txt"
  # Preserve this exact bundle, even if a later build overwrites build/StrixProbe.kext.
  tar -czf "$TRACE_DIR/StrixProbe.kext.tar.gz" -C build StrixProbe.kext
fi
python3 - "$TRACE_DIR" "$BUILD_EXIT" "$VALIDATE_EXIT" <<'PY'
import hashlib, json, pathlib, re, shlex, subprocess, sys
out = pathlib.Path(sys.argv[1]); build_exit = int(sys.argv[2]); validate_exit = int(sys.argv[3])
sources = ['scripts/build.sh', 'scripts/macos-strix-probe-build.sh',
           'kexts/StrixProbe/StrixProbe.cpp', 'kexts/StrixProbe/kmod_info.c', 'kexts/StrixProbe/Info.plist']
hashes = {p: hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest() for p in sources}
status = 'BUILD-FAILED' if build_exit else 'VALIDATION-FAILED' if validate_exit else 'LINKED-symbol-review-pending'
if not build_exit:
    symbols = (out / 'undefined-symbols.txt').read_text()
    headers = (out / 'macho-header.txt').read_text()
    if not re.search(r'\bKEXT_?BUNDLE\b', headers) or re.search(r'___cxa_atexit|___cxa_throw|___gxx_personality', symbols):
        status = 'VALIDATION-FAILED'; validate_exit = 1
    hashes['build/StrixProbe.kext/Contents/MacOS/StrixProbe'] = hashlib.sha256(
        pathlib.Path('build/StrixProbe.kext/Contents/MacOS/StrixProbe').read_bytes()).hexdigest()
    defined = subprocess.run(['nm', '-gUj', 'build/StrixProbe.kext/Contents/MacOS/StrixProbe'],
                             capture_output=True, text=True, check=True).stdout.splitlines()
    if '_kmod_info' not in defined or 'X86_64' not in headers:
        status = 'VALIDATION-FAILED'; validate_exit = 1
deps = pathlib.Path('build/obj/StrixProbe_StrixProbe.d')
dependency_hashes = {}
if not build_exit and deps.exists():
    (out / 'compiler-dependencies.txt').write_bytes(deps.read_bytes())
    for name in shlex.split(deps.read_text().replace('\\\n', '').split(':', 1)[1]):
        path = pathlib.Path(name)
        dependency_hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
sdk = pathlib.Path(__import__('os').environ.get('MACKERNELSDK', 'build/MacKernelSDK'))
sdk_rev = subprocess.run(['git', '-C', str(sdk), 'rev-parse', 'HEAD'], capture_output=True, text=True)
manifest = {'step': '890M-02', 'status': status, 'build_exit': build_exit,
            'validation_exit': validate_exit, 'sdk_commit': sdk_rev.stdout.strip(),
            'source_and_binary_hashes': hashes, 'installed': False, 'runtime_tested': False,
            'compiler_dependency_hashes': dependency_hashes,
            'build_command': ['bash', 'scripts/build.sh', 'StrixProbe']}
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(status + ': ' + str(out))
raise SystemExit(1 if build_exit or validate_exit else 0)
PY
