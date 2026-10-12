#!/bin/bash
# Builds NVAccel (kexts/NVRM/accel/nvrm-accel.cpp) from a checkout that had patches/nullmoth-readback applied, and stages it.
#   bash scripts/macos-build-nvaccel-local.sh [checkout]      (default ~/nvmtl-readback)
# Output: ~/efi-audit/readback/stage/NVAccel (+ SHA256SUMS). Install: scripts/macos-readback-nvaccel-install.sh.
# NOT RUN YET (written without a Mac). Flags follow upstream build/accel_build.sh; the -D list comes from the RM build's
# compile_cmds.sh when ~/ogkm610 has one, otherwise from the explicit list macos-build-nullmoth-local.sh uses for NVRMEdpBL.
set -euo pipefail
WT=${1:-$HOME/nvmtl-readback}
OUT=$HOME/efi-audit/readback/build; ST=$HOME/efi-audit/readback/stage
O=${OGKM:-$HOME/ogkm610}; KMS=$O/src/nvidia-modeset; NV=$O/src/nvidia
SRC=$WT/kexts/NVRM; RE=$SRC/accel/re
SDK=$(xcrun --show-sdk-path); KHDR="$SDK/System/Library/Frameworks/Kernel.framework/Headers"
grep -q nvaccel_ss_dirty_ok "$SRC/accel/nvrm-accel.cpp" 2>/dev/null || { echo "STOP: $WT has no readback patch applied (run patches/nullmoth-readback/apply.sh)"; exit 1; }
[ -d "$NV" ] || { echo "STOP: no $NV (extract the open-gpu-kernel-modules 610.57.04 tarball to $O)"; exit 1; }
mkdir -p "$OUT/NVAccel.kext/Contents/MacOS" "$ST"
RMINC=( -I"$NV/arch/nvalloc/unix/include" -I"$NV/arch/nvalloc/common/inc" -I"$NV/arch/nvalloc/common/inc/gsp"
  -I"$O/src/common/sdk/nvidia/inc" -I"$O/src/common/sdk/nvidia/inc/hw" -I"$O/src/common/inc"
  -I"$O/src/common/shared/inc" -I"$NV/inc" -I"$NV/inc/os" -I"$NV/inc/kernel" -I"$NV/kernel/inc" -I"$NV/interface"
  -I"$O/src/common/nvlink/interface" -I"$O/src/common/inc/swref" -I"$O/src/common/inc/swref/published"
  -I"$NV/inc/libraries" -I"$NV/src/libraries" -I"$NV/generated" -I"$NV/src/mm/uvm/interface"
  -I"$O/src/common/uproc/os/libos-v2.0.0/include" -I"$O/src/common/uproc/os/common/include"
  -I"$O/src/common/inc/displayport" -I"$O/src/common/nvlink/inband/interface" )
KMSINC=( -I"$KMS/os-interface/include" -I"$KMS/kapi/interface" -I"$KMS/kapi/include" -I"$O/src/common/unix/nvidia-push/interface" -I"$KMS/interface" -I"$KMS/include"
         -I"$O/src/common/unix/common/inc" -I"$O/src/common/modeset" -I"$O/src/common/unix/common/utils/interface" )
RMDEFS=()
if [ -f "$NV/_out/Darwin_x86_64/compile_cmds.sh" ]; then
  while read -r d; do RMDEFS+=("$d"); done < <(head -1 "$NV/_out/Darwin_x86_64/compile_cmds.sh" | tr ' ' '\n' | grep -E '^-D' | sed -e 's/"//g' | grep -v -E '^-D(NVRM|_LANGUAGE_C)$')
  echo "using $((${#RMDEFS[@]})) -D flags from compile_cmds.sh"
else
  for m in atomic core memory sync util string crypto thread safe debug cpu time; do RMDEFS+=(-DPORT_MODULE_$m=1); done
  RMDEFS+=(-DNV_KERNEL_INTERFACE_LAYER)
  echo "no compile_cmds.sh: using the explicit PORT_MODULE list (unproven for NVAccel)"
fi
CFLAGS=( -arch x86_64 -fapple-kext -mkernel -nostdinc -I"$KHDR" -I"$SRC" "${RMINC[@]}" "${KMSINC[@]}"
  -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT "${RMDEFS[@]}"
  -std=c++17 -fno-rtti -fno-exceptions -fno-builtin -fno-common
  -Wall -Wno-unused-parameter -Wno-inconsistent-missing-override -Wno-unused-function -O2 )
cd "$WT"; echo "tree: $(git rev-parse --short HEAD) $(git status --short | wc -l | tr -d ' ') changed file(s)"
xcrun clang++ "${CFLAGS[@]}" -I"$SRC/accel" -I"$SRC/accel/iofam" -I"$RE" -c "$SRC/accel/nvrm-accel.cpp" -o "$OUT/nvrm-accel.o" 2>"$OUT/accel.err" \
  || { grep -E 'error' "$OUT/accel.err" | head -20; echo "STOP: compile failed (full log $OUT/accel.err)"; exit 1; }
echo "warnings: $(grep -c 'warning:' "$OUT/accel.err" || true)"
xcrun clang++ -arch x86_64 -fapple-kext -nostdlib -Xlinker -kext -lkmodc++ -lkmod -lcc_kext "$OUT/nvrm-accel.o" -o "$OUT/NVAccel.kext/Contents/MacOS/NVAccel" 2>"$OUT/accelld.err" \
  || { head -20 "$OUT/accelld.err"; echo "STOP: link failed"; exit 1; }
cp "$OUT/NVAccel.kext/Contents/MacOS/NVAccel" "$ST/NVAccel"
( cd "$ST"; shasum -a 256 NVAccel | tee SHA256SUMS )
echo "staged in $ST. Compare the symbol set with the installed one before installing:"
echo "  nm -gU $ST/NVAccel | wc -l ; nm -gU /Library/Extensions/NVAccel.kext/Contents/MacOS/NVAccel | wc -l"
