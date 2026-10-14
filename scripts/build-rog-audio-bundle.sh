#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-strixampctl.sh
bash scripts/build-alc-verb.sh
bash scripts/build-rogaudio.sh
bash scripts/build-rogcontrol.sh
bash scripts/build.sh StrixAmp
R=build/StrixAmp.kext/Contents/Resources
mkdir -p "$R/firmware" "$R/tools" "$R/scripts"
cp -R fw/cs35l56/. "$R/firmware/"
cp build/strixampctl build/alc-verb build/rogaudio-probe "$R/tools/"
cp -R build/RogControl.app build/RogAudio.driver build/RogAudio.app "$R/"
cp build/ROG-Speaker-Test.wav "$R/"
cp scripts/macos-audio-boot-trace.sh scripts/macos-audio-codec-probe.sh scripts/macos-audio-coef-probe.sh "$R/scripts/"
find "$R" -type f -exec shasum -a 256 {} + > build/StrixAmp-bundle.sha256
echo 'Audio bundle: build/StrixAmp.kext (hardware driver + userspace resources; userspace payload is installed separately)'
