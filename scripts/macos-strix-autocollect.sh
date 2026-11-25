#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# One-shot post-login collector: arms a user LaunchAgent that, ~90 s after the next login, runs
# scripts/macos-strix-0114-verify.sh and then removes itself. No root. One reboot = one full data set.
#   bash scripts/macos-strix-autocollect.sh arm      (before the reboot)
#   bash scripts/macos-strix-autocollect.sh disarm
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=$(pwd)
LABEL=com.thanhnndev.strix.autocollect
PL="$HOME/Library/LaunchAgents/$LABEL.plist"
case "${1:-arm}" in
  arm)
    mkdir -p "$HOME/Library/LaunchAgents" "$REPO/out/890m-trace"
    cat > "$PL" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>RunAtLoad</key><true/>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>-c</string>
    <string>sleep 90; /bin/bash "$REPO/scripts/macos-strix-0114-verify.sh" 8 &gt; "$REPO/out/890m-trace/autocollect.log" 2&gt;&amp;1; rm -f "$PL"; /bin/launchctl bootout gui/\$(id -u)/$LABEL</string>
  </array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin:/opt/local/bin</string></dict>
  <key>StandardErrorPath</key><string>$REPO/out/890m-trace/autocollect.err</string>
</dict></plist>
PLIST
    plutil -lint "$PL"
    echo "armed: runs once ~90 s after the next login; log out/890m-trace/autocollect.log"
    ;;
  disarm)
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$PL"; echo "disarmed"
    ;;
  *) echo "usage: $0 arm|disarm"; exit 2 ;;
esac
