#!/bin/bash
# Build the upstream AppleALC diagnostic tool; GPL-2.0 source remains in build/.
set -euo pipefail
cd "$(dirname "$0")/.."
REV=ff01db21749271916d44605503499ceaa61d94b2
SRC=build/AppleALC-reference
if [ ! -d "$SRC/.git" ]; then
  git clone --depth 1 https://github.com/acidanthera/AppleALC.git "$SRC"
fi
if [ "$(git -C "$SRC" rev-parse HEAD)" != "$REV" ]; then
  git -C "$SRC" fetch --depth 1 origin "$REV"
  git -C "$SRC" checkout --detach "$REV"
fi
cc -O2 -Wall -Wno-deprecated-declarations -I "$SRC/AppleALC" -I "$SRC/alc-verb" \
  "$SRC/alc-verb/main.c" -framework IOKit -framework CoreFoundation -o build/alc-verb
echo "built build/alc-verb (AppleALC $REV)"
