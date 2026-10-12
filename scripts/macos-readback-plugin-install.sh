#!/bin/bash
# Installs / removes the instrumented NVMTLDriver executable (patches/nullmoth-readback 0001) in the NullMoth 1.14.2 bundle.
#   sudo bash scripts/macos-readback-plugin-install.sh --candidate /path/NVMTLDriver --sha256 <hash printed by your build>
#   sudo bash scripts/macos-readback-plugin-install.sh --undo
#   bash scripts/macos-readback-plugin-install.sh --status
# NOT RUN YET (written without a Mac); modelled on scripts/macos-ws-upload-install.sh, which did run here.
# The bundle is exchanged atomically on the Data volume; processes that already mapped the old executable keep it. The
# instrumented plugin is loaded by WindowServer at its next start (reboot). The statistics are off until you create the
# request file (see docs/WINDOWSERVER-READBACK.md), so installing it changes no behaviour by itself.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
BUNDLE=/Library/GPUBundles/NVMTLDriver.bundle
BIN=Contents/MacOS/NVMTLDriver
STATE=/Library/NullMoth/readback-plugin
STAGE=/Library/GPUBundles/NVMTLDriver.readback-stage.bundle
EXPECT_VERSION=1.14.2
sha() { shasum -a 256 "$1" | awk '{print $1}'; }
die() { echo "STOP: $*" >&2; exit 1; }
swap() {
  /usr/bin/python3 -I - "$1" "$2" <<'PY'
import ctypes, os, sys
lib = ctypes.CDLL(None, use_errno=True)
rename = lib.renamex_np
rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
rename.restype = ctypes.c_int
if rename(os.fsencode(sys.argv[1]), os.fsencode(sys.argv[2]), 2):      # RENAME_SWAP
    error = ctypes.get_errno()
    raise OSError(error, os.strerror(error))
PY
}
MODE=install; CAND=; WANT=
while [ $# -gt 0 ]; do
  case $1 in
    --undo) MODE=undo;; --status) MODE=status;;
    --candidate) CAND=${2:?}; shift;; --sha256) WANT=${2:?}; shift;;
    *) die "unknown argument $1";;
  esac; shift
done
CURRENT=$(sha "$BUNDLE/$BIN")
if [ "$MODE" = status ]; then
  echo "installed executable sha256: $CURRENT"
  if [ -f "$STATE/installed.sha256" ]; then echo "readback plugin installed (recorded $(cat "$STATE/installed.sha256")); original kept in $STATE/previous.bundle (sha256 $(cat "$STATE/original.sha256"))"
  else echo "no readback plugin recorded; this is the stock executable unless something else replaced it"; fi
  exit 0
fi
[ "$EUID" = 0 ] || die "run with sudo"
if [ "$MODE" = undo ]; then
  [ -f "$STATE/installed.sha256" ] || die "nothing recorded at $STATE"
  [ "$CURRENT" = "$(cat "$STATE/installed.sha256")" ] || die "the installed executable is not the one this script installed; refusing to touch it"
  [ "$(sha "$STATE/previous.bundle/$BIN")" = "$(cat "$STATE/original.sha256")" ] || die "backup hash mismatch"
  swap "$BUNDLE" "$STATE/previous.bundle"
  mv "$STATE/previous.bundle" "$STATE/instrumented.bundle.$(date +%Y%m%d-%H%M%S)"
  rm -f "$STATE/installed.sha256"
  echo "stock bundle restored. Reboot (or at least restart WindowServer by logging out) to load it."
  exit 0
fi
[ -n "$CAND" ] && [ -n "$WANT" ] || die "give --candidate PATH and --sha256 HASH"
[ "$(cat /Library/NullMoth/driver-version 2>/dev/null)" = "$EXPECT_VERSION" ] || die "NullMoth is not $EXPECT_VERSION; the patch is written against that version"
[ ! -f "$STATE/installed.sha256" ] && [ ! -e "$STATE/previous.bundle" ] && [ ! -e "$STAGE" ] || die "a previous readback install exists; run --undo first"
[ "$(sha "$CAND")" = "$WANT" ] || die "candidate sha256 differs from --sha256"
codesign --verify --strict "$CAND" || die "candidate is not validly signed (build_plugin.sh signs ad hoc: codesign -f -s -)"
/usr/bin/lipo -archs "$CAND" | grep -qw x86_64 || die "candidate has no x86_64 slice"
mkdir -p "$STATE"
trap 'rm -rf "$STAGE"' EXIT
ditto "$BUNDLE" "$STAGE"
cp "$CAND" "$STAGE/$BIN"
[ "$(sha "$STAGE/$BIN")" = "$WANT" ] || die "staged executable hash mismatch"
chown -R root:wheel "$STAGE"; chmod 755 "$STAGE/$BIN"
sha "$BUNDLE/$BIN" > "$STATE/original.sha256"
swap "$BUNDLE" "$STAGE"            # $STAGE now holds the stock bundle with its original signature
trap - EXIT
mv "$STAGE" "$STATE/previous.bundle"
echo "$WANT" > "$STATE/installed.sha256"
[ "$(sha "$BUNDLE/$BIN")" = "$WANT" ] || die "post-install hash check failed (stock bundle is in $STATE/previous.bundle)"
echo "DONE: instrumented plugin on disk. Running processes keep the old one; reboot to load it into WindowServer."
echo "Statistics stay off until:  echo WindowServer | sudo tee /Library/NullMoth/surfstat-request"
echo "Undo: sudo bash $0 --undo"
