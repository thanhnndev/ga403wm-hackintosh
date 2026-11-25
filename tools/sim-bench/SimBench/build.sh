#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# build.sh [debug|release] -> build/SimBench.app (iOS Simulator, x86_64, ad-hoc signed)
set -e; cd "$(dirname "$0")"; M=${1:-debug}
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
O=-Onone; [ "$M" = release ] && O=-O
rm -rf build/SimBench.app; mkdir -p build/SimBench.app
xcrun --sdk iphonesimulator swiftc $O -parse-as-library -sdk "$SDK" -target x86_64-apple-ios17.0-simulator main.swift -o build/SimBench.app/SimBench
cp Info.plist build/SimBench.app/
codesign -s - --force build/SimBench.app >/dev/null 2>&1
echo built build/SimBench.app $M
