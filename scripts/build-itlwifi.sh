#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Builds the ItlWiFi menu bar app into build/ItlWiFi.app (Xcode command line tools, no Xcode project). Ad-hoc signed.
#   scripts/build-itlwifi.sh            build
#   scripts/build-itlwifi.sh --install  build, copy to /Applications, start it at every login (user LaunchAgent), start it now
#                                       (no sudo: /Applications is writable for admins). Turn the login start off in its menu.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/ItlWiFi.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp macos/ItlWiFi/Info.plist "$APP/Contents/Info.plist"
swiftc -O -target x86_64-apple-macos13.0 macos/ItlWiFi/ItlWiFi.swift macos/ItlWiFi/SpeedTest.swift -o "$APP/Contents/MacOS/ItlWiFi" -framework IOKit -framework SwiftUI
codesign --force --sign - "$APP" >/dev/null
echo "built $APP"
if [ "${1:-}" = "--install" ]; then
  pkill -x ItlWiFi 2>/dev/null || true
  rm -rf /Applications/ItlWiFi.app
  cp -R "$APP" /Applications/
  LA="$HOME/Library/LaunchAgents/com.itlmt7925.ItlWiFi.plist"      # same label and keys the app's "Open at Login" writes
  mkdir -p "$(dirname "$LA")"
  /usr/bin/python3 -I - "$LA" <<'PY'
import plistlib, sys
plistlib.dump({"Label": "com.itlmt7925.ItlWiFi", "ProgramArguments": ["/Applications/ItlWiFi.app/Contents/MacOS/ItlWiFi"],
               "RunAtLoad": True, "ProcessType": "Interactive", "LimitLoadToSessionType": "Aqua"}, open(sys.argv[1], "wb"))
PY
  plutil -lint "$LA" >/dev/null
  open /Applications/ItlWiFi.app
  echo "installed /Applications/ItlWiFi.app; starts at login ($LA)"
fi
