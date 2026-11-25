#!/bin/bash
# Fetch the blacktop/ipsw release into tools/bin (gitignored). Used to pull system dylibs out of the macOS dyld shared cache.
set -euo pipefail
V=${1:-v3.1.739}
D=$(cd "$(dirname "$0")" && pwd)/bin
mkdir -p "$D"; T=$(mktemp -d)
gh release download "$V" -R blacktop/ipsw -p "ipsw_${V#v}_linux_x86_64.tar.gz" -D "$T"
tar xzf "$T"/ipsw_*.tar.gz -C "$T" ipsw
install -m755 "$T/ipsw" "$D/ipsw"; rm -rf "$T"; "$D/ipsw" version | head -1
