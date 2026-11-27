#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Installs the userland half of the speaker-amp driver: strixampctl, the CS35L56 firmware (fw/cs35l56) and a LaunchDaemon that
# keeps the amps up (firmware download, register setup, play) at boot and after wake. Needs the StrixAmp kext (EFI/OC/Kexts).
# Run through osascript with administrator privileges.  --undo removes everything.
#   build first: scripts/build-strixampctl.sh
#   --vol <dB>   amp volume the daemon sets (default -20; the macOS volume slider is separate)
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(id -u)" = 0 ] || { echo 'Use osascript with administrator privileges'; exit 1; }
LABEL=com.itlmt7925.strixamp
BIN=/Library/PrivilegedHelperTools/com.itlmt7925.strixampctl
FW=/usr/local/share/strixamp/fw
CLI=/usr/local/bin/strixampctl
PLIST=/Library/LaunchDaemons/$LABEL.plist
if [ "${1:-}" = --undo ]; then
  launchctl bootout "system/$LABEL" 2>/dev/null || true
  rm -f "$PLIST" "$BIN" "$CLI"; rm -rf /usr/local/share/strixamp
  echo 'strixamp removed (amps stay in their current state until the next reset / reboot).'
  exit 0
fi
VOL=-20
[ "${1:-}" = --vol ] && VOL="${2:?dB}"
[ -x build/strixampctl ] || { echo 'build first: scripts/build-strixampctl.sh'; exit 1; }
launchctl bootout "system/$LABEL" 2>/dev/null || true
mkdir -p /Library/PrivilegedHelperTools "$FW" /usr/local/bin
install -o root -g wheel -m 755 build/strixampctl "$BIN"
install -o root -g wheel -m 755 build/strixampctl "$CLI"
for f in fw/cs35l56/*.wmfw fw/cs35l56/*.bin; do install -o root -g wheel -m 644 "$f" "$FW/"; done
/usr/bin/python3 -I - "$PLIST" "$BIN" "$LABEL" "$FW" "$VOL" "$(stat -f %Su /dev/console)" <<'PY'
import plistlib, sys, pwd, os
settings = os.path.join(pwd.getpwnam(sys.argv[6]).pw_dir, 'Library/Application Support/RogAudio/settings.plist')
plistlib.dump({'Label': sys.argv[3], 'ProgramArguments': [sys.argv[2], 'daemon', '--fw', sys.argv[4], '--vol', sys.argv[5], '--settings', settings],
               'RunAtLoad': True, 'KeepAlive': True, 'ThrottleInterval': 30,
               'StandardOutPath': '/var/log/strixamp.log', 'StandardErrorPath': '/var/log/strixamp.log'}, open(sys.argv[1], 'wb'))
PY
chown root:wheel "$PLIST"; chmod 644 "$PLIST"
plutil -lint "$PLIST"
launchctl bootstrap system "$PLIST"
echo "installed: $CLI, $FW, $PLIST; log /var/log/strixamp.log"
