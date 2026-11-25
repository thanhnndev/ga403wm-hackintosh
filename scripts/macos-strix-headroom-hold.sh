#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Install / remove the StrixHeadroomHold user LaunchAgent (tools/strix_headroom_hold.swift).
# It keeps one EDR headroom request open so CoreDisplay caches CurrentHeadroom: WindowServer drops from 1400-1650 %
# to ~150 % CPU with the OLED on the display pipe. No root, no reboot; takes effect within a few seconds.
#   bash scripts/macos-strix-headroom-hold.sh install | uninstall | status
set -euo pipefail
cd "$(dirname "$0")/.."
LABEL=com.thanhnndev.strix.headroomhold
DIR="$HOME/Library/Application Support/StrixHeadroomHold"
BIN="$DIR/strix-headroom-hold"
PL="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_=$(id -u)
case "${1:-status}" in
install)
  mkdir -p "$DIR" "$HOME/Library/LaunchAgents"
  swiftc -O tools/strix_headroom_hold.swift -o "$BIN.new"
  mv -f "$BIN.new" "$BIN"
  cat > "$PL" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$DIR/hold.log</string>
  <key>StandardErrorPath</key><string>$DIR/hold.log</string>
</dict></plist>
PLIST
  launchctl bootout "gui/$UID_/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$UID_" "$PL"
  echo "installed: $PL"
  ;;
uninstall)
  launchctl bootout "gui/$UID_/$LABEL" 2>/dev/null || true
  rm -f "$PL"
  echo "removed (binary left in $DIR)"
  ;;
status)
  launchctl print "gui/$UID_/$LABEL" 2>/dev/null | /usr/bin/grep -E "state =|pid =" || echo "not loaded"
  ;;
*) echo "usage: $0 install|uninstall|status"; exit 2 ;;
esac
