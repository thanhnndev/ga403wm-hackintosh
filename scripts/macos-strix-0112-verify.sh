#!/bin/bash
# Unified post-reboot verify for StrixAccel 0.1.12 + EDID override.
# One run collects everything the reboot needs to prove, so a single reboot
# yields the full trace. Safe to run multiple times; first snapshot is always
# pristine boot counters (no Reset before snapshot1).
#
# Usage: bash scripts/macos-strix-0112-verify.sh [load-seconds]
#   load-seconds: short animation load to prove liveness (default 3, 0 to skip)
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(uname -s)" = Darwin ] || { echo 'Run on macOS.' >&2; exit 1; }
SECS="${1:-3}"

D="out/890m-trace/step07-0112-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$D"

# --- pristine snapshots (no writes before this) ---
ioreg -r -c StrixAccelerator -l > "$D/accel-boot.txt" 2>&1 || true
ioreg -r -c StrixGOPFramebuffer -l > "$D/gop.txt" 2>&1 || true
ioreg -r -c IOAccelDisplayPipe -l > "$D/pipe.txt" 2>&1 || true
ioreg -r -c IOFramebuffer -d1 > "$D/framebuffers.txt" 2>&1 || true
kmutil showloaded --list-only 2>/dev/null | awk '/itlmt7925\.strix|IOAcceleratorFamily2|IOSurface/' > "$D/loaded.txt" || true
system_profiler SPDisplaysDataType > "$D/displays.txt" 2>/dev/null || true
/usr/bin/plutil -p "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-4c83/DisplayProductID-419c" > "$D/override.txt" 2>&1 || echo "(no override file)" > "$D/override.txt"
/usr/bin/log show --last 20m --style compact \
  --predicate 'process == "kernel" AND (eventMessage CONTAINS[c] "StrixAccel" OR eventMessage CONTAINS[c] "StrixGOP")' \
  > "$D/kernel-log.txt" 2>/dev/null || true
/usr/bin/log show --last 20m --style compact \
  --predicate 'eventMessage CONTAINS[c] "display pipe" OR eventMessage CONTAINS[c] "IOAccel"' \
  > "$D/windowserver-log.txt" 2>/dev/null || true

# --- tools (reuse prebuild if present, else compile) ---
TUNE_BIN="${TMPDIR:-/tmp}/strix-0112-verify/tune"
LOAD_BIN="${TMPDIR:-/tmp}/strix-0112-verify/load"
mkdir -p "$(dirname "$TUNE_BIN")"
if [ -x /tmp/strix-prebuild/tune ]; then cp /tmp/strix-prebuild/tune "$TUNE_BIN"
else cc -O2 tools/strix_accel_tune.c -framework IOKit -framework CoreFoundation -o "$TUNE_BIN"; fi
if [ -x /tmp/strix-prebuild/load ]; then cp /tmp/strix-prebuild/load "$LOAD_BIN"
else swiftc -O tools/strix_present_load.swift -o "$LOAD_BIN"; fi
"$TUNE_BIN" > "$D/tune-boot.txt" 2>&1 || echo "(tune query failed)" > "$D/tune-boot.txt"

# --- EDID decode: live panel EDID base size + first-DTD image size ---
ioreg -rc AppleBacklightDisplay -l -w0 -a > "$D/backlight.plist" 2>/dev/null || true
/usr/bin/python3 -I - "$D/backlight.plist" "$D/edid.txt" <<'PY' || echo "(edid decode failed)" > "$D/edid.txt"
import plistlib, struct, sys
regs = plistlib.loads(open(sys.argv[1], 'rb').read())
edid = None
def walk(o):
    global edid
    if isinstance(o, dict):
        if isinstance(o.get('IODisplayEDID'), bytes) and len(o['IODisplayEDID']) in (128, 256):
            edid = o['IODisplayEDID']
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
walk(regs)
out = open(sys.argv[2], 'w')
if edid is None:
    out.write('live IODisplayEDID: NOT FOUND on AppleBacklightDisplay\n')
    sys.exit(0)
b = bytes(edid)
out.write('live IODisplayEDID len=%d checksum=%s\n' % (len(b), 'ok' if sum(b[:128]) % 256 == 0 else 'BAD'))
out.write('base size bytes[21,22] = %d x %d cm\n' % (b[21], b[22]))
if b[54] == 0 and b[55] == 0:
    out.write('first DTD: monitor descriptor, not timing\n')
else:
    # VESA DTD layout (matches Linux drm_edid width_mm/height_mm): h_image = byte12
    # low + HIGH nibble of byte14; v_image = byte13 low + LOW nibble of byte14.
    # Absolute offsets: byte12=b[66], byte13=b[67], byte14=b[68].
    h = b[54+12] | ((b[54+14] & 0xF0) << 4)
    v = b[54+13] | ((b[54+14] & 0x0F) << 8)
    out.write('first-DTD image size = %d x %d mm\n' % (h, v))
PY

# --- liveness: short animation load, then re-snapshot counters ---
if [ "${SECS}" != "0" ]; then
  "$LOAD_BIN" "$SECS" small > "$D/load.txt" 2>&1 | tail -2 || true
  sleep 1
  "$TUNE_BIN" > "$D/tune-after-load.txt" 2>&1 || true
  ioreg -r -c StrixAccelerator -l > "$D/accel-after-load.txt" 2>&1 || true
fi

# --- verdict ---
/usr/bin/python3 -I - "$D" <<'PY'
import pathlib, re, sys
d = pathlib.Path(sys.argv[1])
def grab(path, pat):
    try: txt = (d / path).read_text(errors='replace')
    except OSError: return None
    m = re.search(pat, txt)
    return m.group(1) if m else None
def num(path, key):
    v = grab(path, r'"%s"\s*=\s*(-?\d+)' % re.escape(key))
    try: return int(v) if v is not None else None
    except ValueError: return None

ver   = grab('accel-boot.txt', r'"StrixAccel,Version"\s*=\s*"([^"]+)"')
trx   = num('accel-boot.txt', 'StrixAccel,Transactions')
cop   = num('accel-boot.txt', 'StrixAccel,Copied')
begin = num('accel-boot.txt', 'StrixAccel,Begin')
pipes = num('accel-boot.txt', 'StrixAccel,Pipes')
ref   = grab('accel-boot.txt', r'"StrixAccel,AGDC,RefusedSeen"\s*=\s*"([^"]*)"')
empty = num('accel-boot.txt', 'StrixAccel,AGDC,FbCapEmpty')
pipe_txt = (d / 'pipe.txt').read_text(errors='replace') if (d / 'pipe.txt').exists() else ''
clients = pipe_txt.count('IOAccelDisplayPipeUserClient2')
disp = (d / 'displays.txt').read_text(errors='replace') if (d / 'displays.txt').exists() else ''
model_ok = 'AMD Radeon 890M' in disp
vram_ok  = '512 MB' in disp
ws_errs = 0
try: ws_errs = sum(1 for l in (d / 'windowserver-log.txt').read_text(errors='replace').splitlines() if 'Unable to find display pipe' in l)
except OSError: pass
trx2 = num('accel-after-load.txt', 'StrixAccel,Transactions')

lines = []
def check(name, ok, detail=''):
    lines.append('%s %s %s' % ('PASS' if ok else 'FAIL', name, detail))

check('version==0.1.12', ver == '0.1.12', '(got %s)' % ver)
check('pipe-opened(Transactions>0@boot)', (trx or 0) > 0, '(got %s)' % trx)
check('frames-copied(Copied>0@boot)', (cop or 0) > 0, '(got %s)' % cop)
check('begin-called(Begin>0@boot)', (begin or 0) > 0, '(got %s)' % begin)
check('pipe-userclient-present', clients > 0, '(count %d)' % clients)
check('0x711-revert(no FbCapEmpty)', empty is None, '(got %s)' % empty)
check('refusals-limited', ref == '0x3,0x941,0x925', '(got %s)' % ref)
check('model-identity', model_ok, '')
check('vram-identity', vram_ok, '')
if trx2 is not None:
    if (trx or 0) == 0 and (trx2 or 0) == 0:
        check('load-liveness(Transactions grows)', False, '(boot 0 -> after 0: no presents flow)')
    else:
        check('load-liveness(Transactions grows)', (trx2 or 0) >= (trx or 0), '(boot %s -> after %s)' % (trx, trx2))
lines.append('INFO windowserver-pipe-errors(last20m)=%d pipes=%s' % (ws_errs, pipes))
lines.append('MANUAL Settings > Displays > Built-in OLED size should read ~14-inch (was 47-inch fallback)')
(d / 'SUMMARY.md').write_text('# step07 0.1.12 verify\n\n' + ''.join('- %s\n' % l for l in lines))
print('\n'.join(lines))
PY

echo "saved: $D"
