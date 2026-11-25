#!/bin/bash
# Build the native-framebuffer display adapter and the matching v2.3.1 Metal gate.
# NMX_SRC is the ga403wm-nmx fork; PLUGIN_SRC is its v2.3.1 display-gate worktree.
# No fetches, package installation, kernel installation, or reboot.
set -euo pipefail
NMX_SRC=${NMX_SRC:-$HOME/develop/projects/nmx-src-2.0.4}
PLUGIN_SRC=${PLUGIN_SRC:-$HOME/develop/projects/890m-ws-plugin}
GPU_SRC=${GPU_SRC:-$HOME/develop/projects/gpu-src}
export GPU_SRC
REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:?output directory}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
[[ $(sw_vers -buildVersion) == 25G241 ]] || { echo 'unreviewed OS profile'; exit 1; }
[[ $(cd "$GPU_SRC/xkpi" && pwd -P) == "$NMX_SRC/gpu-port/xkpi" ]] || { echo 'wrong xkpi source'; exit 1; }
NM_TAHOE=1 bash "$NMX_SRC/build/nmxaccel_build.sh" "$NMX_SRC/kexts/NVRM" "$OUT/accel"
(cd "$GPU_SRC/xkpi" && bash ccxx.sh xnu/nmx_fb.cpp && AMD_ONLY=1 bash kext/build.sh "$OUT/gpu")
(cd "$PLUGIN_SRC/plugin" && xcrun clang -arch x86_64 -bundle -fobjc-arc -O1 -DNVMTL_RELEASE=1 \
    -Wno-protocol -Wno-incomplete-implementation -I"$HOME/Vulkan-Headers/include" \
    -o "$OUT/NVMTLDriver" NVMTLDevice.m -framework Foundation -framework Metal -framework IOSurface -framework IOKit)
codesign -f -s - "$OUT/NVMTLDriver"
python3 "$REPO/tools/890m/nmx-ws-manifest.py" --gpu-kext "$OUT/gpu/NMXGPU.kext" \
    --accel-kext "$OUT/accel/NMXAccel.kext" --plugin "$OUT/NVMTLDriver" --output "$OUT/candidate-manifest.json"
