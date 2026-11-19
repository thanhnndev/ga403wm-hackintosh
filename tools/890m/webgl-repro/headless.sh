#!/bin/zsh
# headless.sh <profile-dir> <cdp-port> [chrome flags...] : start a headless scratch Chrome (no window, no focus change)
# with remote debugging; prints its pid. Default 1280x900 at device scale 2 (the owner's Retina case).
P=$1; PORT=$2; shift 2
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --user-data-dir=$P --remote-debugging-port=$PORT \
  --no-first-run --no-default-browser-check --disable-gpu-sandbox --enable-gpu --window-size=1280,900 --force-device-scale-factor=2 "$@" about:blank >$P.out 2>&1 &
echo $!
