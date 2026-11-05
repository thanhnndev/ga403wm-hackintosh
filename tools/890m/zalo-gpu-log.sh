#!/bin/bash
# Relaunch Zalo (same profile, nothing changed on disk) with Chromium/ANGLE GPU logging,
# so a display glitch can be tied to the GPU path. Read-only for the installed binaries.
#   zalo-gpu-log.sh gl     - Zalo's default path: ANGLE on OpenGL (CGL -> AppleMetalOpenGLRenderer -> NVMTL)
#   zalo-gpu-log.sh metal  - A/B: ANGLE on Metal (no Apple GL layer; same NVMTL plugin underneath)
#   zalo-gpu-log.sh soft   - control: --disable-gpu, CPU drawing only
#   zalo-gpu-log.sh normal - plain relaunch, no logging (back to normal)
set -u
mode=${1:-gl}
out=${ZALO_LOG_DIR:-$HOME/ga403-logs/zalo}
mkdir -p "$out"
stamp=$(date +%Y%m%d-%H%M%S)
app=/Applications/Zalo.app/Contents/MacOS/Zalo

osascript -e 'tell application "Zalo" to quit' 2>/dev/null
for _ in $(seq 1 50); do pgrep -xq Zalo || break; perl -e 'select(undef,undef,undef,0.2)'; done
pgrep -xq Zalo && { echo "Zalo is still running; quit it first"; exit 1; }

case "$mode" in
  normal) open -a Zalo; echo "Zalo relaunched normally"; exit 0 ;;
  gl)    angle=() ;;
  metal) angle=(--use-angle=metal) ;;
  soft)  angle=(--disable-gpu --disable-gpu-compositing) ;;   # control: no GPU at all
  *) echo "usage: $0 gl|metal|soft|normal"; exit 2 ;;
esac

# NVMTL log of this run only (the sandboxed GPU process can write under TMPDIR).
export NVMTL_LOG_PATH="${TMPDIR%/}/nvmtl-zalo-$mode-$stamp.log"
log="$out/zalo-$mode-$stamp.stderr.log"
nohup "$app" --enable-logging=stderr --v=1 \
  --vmodule='*/gpu/*=2,*/angle/*=2,*/viz/*=1,*/cc/*=1' \
  ${angle[@]+"${angle[@]}"} >"$log" 2>&1 &
echo "pid $! mode $mode"
echo "chromium log: $log"
echo "nvmtl log:    $NVMTL_LOG_PATH"
