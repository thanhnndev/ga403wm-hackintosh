#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Builds tools/strixampctl.c (userland controller of the StrixAmp kext, docs/AUDIO-ROG.md) into build/strixampctl.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
cc -O2 -Wall -Wextra -target x86_64-apple-macos13.0 -o build/strixampctl tools/strixampctl.c -framework IOKit -framework CoreFoundation
echo "built build/strixampctl"
