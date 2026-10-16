#!/bin/bash
# Run through osascript with administrator privileges. --undo removes policy service.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(id -u)" = 0 ] || { echo 'Use osascript with administrator privileges'; exit 1; }
LABEL=com.itlmt7925.AmdCppcPolicy
BIN=/Library/PrivilegedHelperTools/com.itlmt7925.AmdCppcPolicy
PLIST=/Library/LaunchDaemons/$LABEL.plist
if [ "${1:-}" = --undo ]; then
  launchctl bootout "system/$LABEL" 2>/dev/null || true
  rm -f "$PLIST" "$BIN"
  echo 'Policy removed. CPPC enable persists until hardware reset; reboot to restore firmware startup state.'
  exit 0
fi
[ -x build/AmdCppcPolicy ] || { echo 'Build AmdCppcPolicy first'; exit 1; }
launchctl bootout "system/$LABEL" 2>/dev/null || true
mkdir -p /Library/PrivilegedHelperTools
if [ -f "$BIN" ]; then cp -p "$BIN" "$BIN.backup-$(date +%Y%m%d-%H%M%S)"; fi
install -o root -g wheel -m 755 build/AmdCppcPolicy "$BIN"
/usr/bin/python3 -I - "$PLIST" "$BIN" "$LABEL" <<'PY'
import plistlib,sys
plistlib.dump({'Label':sys.argv[3],'ProgramArguments':[sys.argv[2]],'RunAtLoad':True,
'KeepAlive':{'SuccessfulExit':False},'ThrottleInterval':60,
'StandardOutPath':'/var/log/amdcppc-policy.log','StandardErrorPath':'/var/log/amdcppc-policy.log'},open(sys.argv[1],'wb'))
PY
chown root:wheel "$PLIST"; chmod 644 "$PLIST"
plutil -lint "$PLIST"
launchctl bootstrap system "$PLIST"
echo 'Installed CPU policy service; log /var/log/amdcppc-policy.log'
