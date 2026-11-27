#!/bin/bash
# One administrator installation of RogControl, RogAudio, StrixAmp userland and alc-verb.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(id -u)" = 0 ] || { echo 'Run through osascript with administrator privileges'; exit 1; }
for f in build/rogaudio-probe build/strixampctl build/alc-verb build/RogControl.app/Contents/MacOS/RogControl; do
  [ -x "$f" ] || { echo "Missing $f; build all audio components first"; exit 1; }
done
codesign --verify --deep --strict build/RogControl.app
USER_NAME=$(stat -f %Su /dev/console)
UID_=$(id -u "$USER_NAME")
BACKUP="/Library/Application Support/RogAudio/backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
for f in /Applications/RogControl.app /Library/Audio/Plug-Ins/HAL/RogAudio.driver \
  '/Library/Application Support/RogAudio/RogAudio.app' /Library/LaunchDaemons/com.itlmt7925.strixamp.plist \
  /Library/LaunchAgents/com.itlmt7925.rogaudiod.plist; do
  [ ! -e "$f" ] || cp -R "$f" "$BACKUP/"
done
bash scripts/macos-rogaudio-install.sh
bash scripts/macos-strixamp-install.sh
mkdir -p /usr/local/bin '/Library/Application Support/RogAudio'
install -o root -g wheel -m 755 build/alc-verb /usr/local/bin/alc-verb
launchctl bootout "gui/$UID_/com.itlmt7925.RogControl" 2>/dev/null || true
pkill -x RogControl 2>/dev/null || true
rm -rf /Applications/RogControl.app
cp -R build/RogControl.app /Applications/
chown -R "$USER_NAME":staff /Applications/RogControl.app
launchctl asuser "$UID_" sudo -u "$USER_NAME" open /Applications/RogControl.app
bash scripts/macos-audio-trace-install.sh
echo "installed audio stack and /usr/local/bin/alc-verb; backups: $BACKUP"
