#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(id -u)" = 0 ] || { echo 'Run as administrator'; exit 1; }
LABEL=com.itlmt7925.audio-boot-trace
ROOT='/Library/Application Support/RogAudio/TraceTools'
PLIST="/Library/LaunchDaemons/$LABEL.plist"
launchctl bootout "system/$LABEL" 2>/dev/null || true
install -d -o root -g wheel -m 755 "$ROOT/scripts"
for file in macos-audio-boot-trace.sh macos-audio-codec-probe.sh macos-audio-coef-probe.sh; do
  install -o root -g wheel -m 755 "scripts/$file" "$ROOT/scripts/$file"
done
/usr/bin/python3 -I - "$PLIST" "$LABEL" "$ROOT/scripts/macos-audio-boot-trace.sh" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({'Label': sys.argv[2], 'ProgramArguments': ['/bin/bash', sys.argv[3]],
                  'RunAtLoad': True, 'ProcessType': 'Background',
                  'StandardOutPath': '/var/log/rog-audio-trace-launch.log',
                  'StandardErrorPath': '/var/log/rog-audio-trace-launch.log'}, f)
PY
chown root:wheel "$PLIST"
chmod 644 "$PLIST"
plutil -lint "$PLIST"
# Run once now to verify collection; RunAtLoad repeats for the new driver at next boot.
launchctl bootstrap system "$PLIST"
echo 'Boot tracing installed: /var/log/rog-audio-trace/<boot-session-uuid>/'
