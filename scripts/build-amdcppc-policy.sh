#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
clang -Wall -Wextra -Werror -O2 -arch x86_64 macos/AmdCppcPolicy/AmdCppcPolicy.c \
  -framework IOKit -framework CoreFoundation -o build/AmdCppcPolicy
codesign --force --sign - build/AmdCppcPolicy
