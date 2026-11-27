#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Builds the ROG audio stack (docs/AUDIO-ROG.md) into build/: RogAudio.driver (AudioServerPlugIn: "ROG Clear Mic", "ROG Speakers")
# and RogAudio.app (rogaudiod: RNNoise microphone path + speaker sound chain). Ad-hoc signed, x86_64.
# RNNoise is built with AVX2/FMA (this machine: Zen 5).
# RNNoise 0.2 (BSD-3-Clause, Xiph.Org) is downloaded once into build/rnnoise/ and checked against a pinned SHA-256; it is not
# vendored (the model weights alone are 4.9 MB of C source).
set -euo pipefail
cd "$(dirname "$0")/.."
VER=0.2
SHA=90fce4b00b9ff24c08dbfe31b82ffd43bae383d85c5535676d28b0a2b11c0d37
URL=https://github.com/xiph/rnnoise/releases/download/v$VER/rnnoise-$VER.tar.gz
R=build/rnnoise
mkdir -p "$R"
if [ ! -d "$R/rnnoise-$VER" ]; then
  T="$R/rnnoise-$VER.tar.gz"
  for try in 1 2 3 4 5; do
    curl -fsSL -C - --max-time 120 -o "$T" "$URL" && break || sleep 2
  done
  [ "$(shasum -a 256 "$T" | cut -d' ' -f1)" = "$SHA" ] || { echo "rnnoise tarball checksum mismatch"; rm -f "$T"; exit 1; }
  tar -xzf "$T" -C "$R"
fi
S="$R/rnnoise-$VER"
if [ ! -f "$R/librnnoise.a" ]; then
  rm -rf "$R/obj"; mkdir -p "$R/obj"
  for f in denoise rnn pitch kiss_fft celt_lpc nnet nnet_default parse_lpcnet_weights rnnoise_data rnnoise_tables; do
    cc -O3 -mavx2 -mfma -target x86_64-apple-macos13.0 -DNDEBUG -I "$S/include" -I "$S/src" -c "$S/src/$f.c" -o "$R/obj/$f.o"
  done
  ar rcs "$R/librnnoise.a" "$R"/obj/*.o
fi

D=build/RogAudio.driver
rm -rf "$D"; mkdir -p "$D/Contents/MacOS"
cp macos/RogAudio/Driver-Info.plist "$D/Contents/Info.plist"
cc -O2 -Wall -Wextra -target x86_64-apple-macos13.0 -bundle -o "$D/Contents/MacOS/RogAudio" macos/RogAudio/RogAudioDriver.c \
   -framework CoreAudio -framework CoreFoundation
codesign --force --sign - "$D" >/dev/null

A=build/RogAudio.app
rm -rf "$A"; mkdir -p "$A/Contents/MacOS"
cp macos/RogAudio/App-Info.plist "$A/Contents/Info.plist"
cc -O2 -Wall -Wextra -target x86_64-apple-macos13.0 -I "$S/include" -o "$A/Contents/MacOS/rogaudiod" macos/RogAudio/rogaudiod.c \
   "$R/librnnoise.a" -lm -framework AudioToolbox -framework CoreAudio -framework CoreFoundation
# Deliberately NOT codesigned: macOS TCC silently feeds zeros to the microphone of an ad-hoc codesigned client that has no
# prompt-able bundle identity (tested: same binary reads the mic unsigned, returns pure silence after codesign -f -s -).
codesign --remove-signature "$A/Contents/MacOS/rogaudiod" 2>/dev/null || true
cc -O2 -Wall -Wextra -target x86_64-apple-macos13.0 -I "$S/include" -o build/rogaudio-probe macos/RogAudio/rogaudio-probe.c \
   "$R/librnnoise.a" -lm -framework AudioToolbox -framework CoreAudio -framework CoreFoundation
codesign --remove-signature build/rogaudio-probe 2>/dev/null || true
build/rogaudio-probe render-test build/ROG-Speaker-Test.wav
echo "built $D and $A"
