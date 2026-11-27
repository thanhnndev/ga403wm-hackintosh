#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Installs the ROG audio stack built by scripts/build-rogaudio.sh: the AudioServerPlugIn into /Library/Audio/Plug-Ins/HAL
# (coreaudiod is restarted, audio drops for about a second) and rogaudiod.app into /Library/Application Support/RogAudio with a
# LaunchAgent for the logged-in user. Run through osascript with administrator privileges; --undo removes everything.
#   osascript -e 'do shell script "<repo>/scripts/macos-rogaudio-install.sh" with administrator privileges'
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(id -u)" = 0 ] || { echo 'Use osascript with administrator privileges'; exit 1; }
LABEL=com.itlmt7925.rogaudiod
HAL=/Library/Audio/Plug-Ins/HAL/RogAudio.driver
APPDIR="/Library/Application Support/RogAudio"
APP="$APPDIR/RogAudio.app"
USER_NAME=$(stat -f %Su /dev/console)
UID_=$(id -u "$USER_NAME")
LA="/Library/LaunchAgents/$LABEL.plist"
if [ "${1:-}" = --undo ]; then
  launchctl bootout "gui/$UID_/$LABEL" 2>/dev/null || true
  rm -f "$LA"; rm -rf "$HAL" "$APP"
  killall coreaudiod 2>/dev/null || true
  echo 'rogaudio removed'
  exit 0
fi
[ -d build/RogAudio.driver ] && [ -d build/RogAudio.app ] || { echo 'build first: scripts/build-rogaudio.sh'; exit 1; }
launchctl bootout "gui/$UID_/$LABEL" 2>/dev/null || true
mkdir -p /Library/Audio/Plug-Ins/HAL "$APPDIR"
rm -rf "$HAL" "$APP"
cp -R build/RogAudio.driver "$HAL"
cp -R build/RogAudio.app "$APP"
chown -R root:wheel "$HAL" "$APP"
install -o root -g wheel -m 755 build/rogaudio-probe "$APPDIR/rogaudio-probe"
[ -f "$APPDIR/profile" ] || { echo balanced > "$APPDIR/profile"; chmod 644 "$APPDIR/profile"; }
/usr/bin/python3 -I - "$LA" "$APP/Contents/MacOS/rogaudiod" "$LABEL" "$USER_NAME" <<'PY'
import plistlib, sys, pwd, os
settings = os.path.join(pwd.getpwnam(sys.argv[4]).pw_dir, 'Library/Application Support/RogAudio/settings.plist')
plistlib.dump({'Label': sys.argv[3], 'ProgramArguments': [sys.argv[2], '--settings', settings], 'RunAtLoad': True, 'KeepAlive': True,
               'ThrottleInterval': 10, 'LimitLoadToSessionType': 'Aqua', 'ProcessType': 'Interactive',
               'StandardErrorPath': '/tmp/rogaudiod.log', 'StandardOutPath': '/tmp/rogaudiod.log'}, open(sys.argv[1], 'wb'))
PY
chown root:wheel "$LA"; chmod 644 "$LA"
plutil -lint "$LA" >/dev/null
killall coreaudiod 2>/dev/null || true       # reloads the HAL plug-ins
sleep 3
launchctl bootstrap "gui/$UID_" "$LA"
echo "installed $HAL and $APP; log /tmp/rogaudiod.log"
