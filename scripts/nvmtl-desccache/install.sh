#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# NVMTL desc-cache (fork branch desc-cache, d5da629): stage/install helper. Run as root; nothing here reboots or
# restarts WindowServer (it loads the new plugin on its next start).
#
#   sudo scripts/nvmtl-desccache/install.sh install [NVMTLDriver]   # verify sha256, then macos-nvmtl-plugin-install.sh
#   sudo scripts/nvmtl-desccache/install.sh undo                    # newest plugin backup (macos-nvmtl-plugin-install.sh --undo)
#   sudo scripts/nvmtl-desccache/install.sh off | on                # NVMTL_NO_DESCCACHE=1 in nvrm610.conf (next WindowServer start)
#   scripts/nvmtl-desccache/install.sh status                       # what is installed / configured, last stats lines
# Live, no restart: `touch /tmp/nvmtl-desccache-off` (rm it to turn the cache back on; checked every ~2 s).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ART_DEFAULT=$HOME/develop/projects/nmx-plugin-890m/out/plugin-desccache-d5da629/NVMTLDriver
[[ -n ${SUDO_USER:-} ]] && ART_DEFAULT=$(eval echo "~$SUDO_USER")/develop/projects/nmx-plugin-890m/out/plugin-desccache-d5da629/NVMTLDriver
SHA=ff3bc393de139c67e4744fa5dad1ce2647d490b04d6d9f745c1ab8c256e6a85d   # as built + ad-hoc signed
UUID=7927EB9E-CED4-3CCF-9F83-CA9167A2C74D                              # survives the installer's re-sign
CONF=/Library/GPUBundles/nvmtl/nvrm610.conf
BIN=/Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver
need_root() { [[ $EUID == 0 ]] || { echo "run as root"; exit 1; }; }
case ${1:-status} in
install)
    need_root; ART=${2:-$ART_DEFAULT}
    got=$(shasum -a 256 "$ART" | cut -d' ' -f1)
    [[ $got == "$SHA" ]] || { echo "sha256 mismatch: $got (want $SHA)"; exit 1; }
    grep -qa NVMTL_NO_DESCCACHE "$ART" || { echo "$ART has no desc-cache"; exit 1; }
    "$HERE/../macos-nvmtl-plugin-install.sh" "$ART"
    echo "installed uuid: $(otool -l "$BIN" | awk '/uuid/{print $2; exit}') (want $UUID)";;
undo) need_root; "$HERE/../macos-nvmtl-plugin-install.sh" --undo;;
off)
    need_root; touch "$CONF"
    grep -q '^NVMTL_NO_DESCCACHE=' "$CONF" && sed -i '' 's/^NVMTL_NO_DESCCACHE=.*/NVMTL_NO_DESCCACHE=1/' "$CONF" || echo 'NVMTL_NO_DESCCACHE=1' >> "$CONF"
    echo "desc-cache OFF from the next WindowServer start ($CONF)";;
on)
    need_root; [[ -f $CONF ]] && sed -i '' '/^NVMTL_NO_DESCCACHE=/d' "$CONF"
    echo "desc-cache ON from the next WindowServer start ($CONF)";;
status)
    echo "plugin uuid: $(otool -l "$BIN" 2>/dev/null | awk '/uuid/{print $2; exit}') (desc-cache build: $UUID)"
    echo "conf: $(grep '^NVMTL_NO_DESCCACHE=' "$CONF" 2>/dev/null || echo 'NVMTL_NO_DESCCACHE unset (cache on)')"
    [[ -e /tmp/nvmtl-desccache-off ]] && echo "live flag /tmp/nvmtl-desccache-off present (cache off)"
    /usr/bin/log show --last 10m --style compact --predicate 'process == "WindowServer" AND eventMessage CONTAINS "desc-cache"' 2>/dev/null | tail -5;;
*) echo "usage: $0 install [NVMTLDriver] | undo | off | on | status"; exit 1;;
esac
