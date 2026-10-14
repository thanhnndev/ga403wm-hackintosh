#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Builds the RogControl menu bar app (ROG Control Center for macOS) into build/RogControl.app (Xcode command line tools, no Xcode project). Ad-hoc signed.
#   scripts/build-rogcontrol.sh            build
#   scripts/build-rogcontrol.sh --install  build, copy to /Applications, start it at every login (user LaunchAgent), start it now
#                                       (no sudo: /Applications is writable for admins). Turn the login start off in its menu.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/RogControl.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp macos/RogControl/Info.plist "$APP/Contents/Info.plist"
swiftc -O -target x86_64-apple-macos15.0 -swift-version 6 -parse-as-library $(find macos/RogControl/Sources -name "*.swift") -o "$APP/Contents/MacOS/RogControl" -framework IOKit -framework SwiftUI -framework AVFoundation -framework CoreAudio -framework Charts
# speaker test set (tools/gen-audio-test.py): generated once, then bundled
[ -f build/audio-test/index.json ] || python3 -I tools/gen-audio-test.py build/audio-test
mkdir -p "$APP/Contents/Resources/AudioTest"
cp build/audio-test/*.wav build/audio-test/index.json "$APP/Contents/Resources/AudioTest/"
codesign --force --sign - "$APP" >/dev/null
echo "built $APP"
if [ "${1:-}" = "--install" ]; then
  pkill -x RogControl 2>/dev/null || true
  rm -rf /Applications/RogControl.app
  cp -R "$APP" /Applications/
  LA="$HOME/Library/LaunchAgents/com.itlmt7925.RogControl.plist"      # same label and keys the app's "Open at Login" writes
  mkdir -p "$(dirname "$LA")"
  /usr/bin/python3 -I - "$LA" <<'PY'
import plistlib, sys
plistlib.dump({"Label": "com.itlmt7925.RogControl", "ProgramArguments": ["/Applications/RogControl.app/Contents/MacOS/RogControl", "--background"],
               "RunAtLoad": True, "ProcessType": "Interactive", "LimitLoadToSessionType": "Aqua"}, open(sys.argv[1], "wb"))
PY
  plutil -lint "$LA" >/dev/null
  open /Applications/RogControl.app
  echo "installed /Applications/RogControl.app; starts at login ($LA)"
fi
