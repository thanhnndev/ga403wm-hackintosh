#!/bin/bash
# Builds the machine-local NullMoth pieces from the fork worktree and stages them with SHA256SUMS:
#   NVRMFB          kexts/NVRMFB/fb/nvrm-fb.cpp  (upstream + the NVRMEdpBL hook, from the checked-out tree)
#   NVRMEdpBL.kext  kexts/NVRM/nvrm_edpbl.cpp + kexts/NVRMEdpBL/NVRMEdpBL.cpp
# Usage: bash scripts/macos-build-nullmoth-local.sh [worktree]   (default ~/develop/projects/nvidia-macos-driver-ws-ga403 =
#        a checkout of https://github.com/thanhnndev/nvidia-macos-driver branch ga403wm; headers from ~/ogkm610 =
#        open-gpu-kernel-modules 610.57.04, see docs/NULLMOTH.md)
# Output: $BRIGHT_DIR/stage (default ~/efi-audit/brightness/stage). Then: scripts/macos-aux-kc-dryrun.sh (root), scripts/macos-edpbl-install.sh (root).
set -euo pipefail
WT=${1:-$HOME/develop/projects/nvidia-macos-driver-ws-ga403}   # worktree of fork branch ga403wm
BR=${BRIGHT_DIR:-$HOME/efi-audit/brightness}
OUT=$BR/build; ST=$BR/stage
O=$HOME/ogkm610; KMS=$O/src/nvidia-modeset; NV=$O/src/nvidia
SDK=$(xcrun --show-sdk-path); KHDR="$SDK/System/Library/Frameworks/Kernel.framework/Headers"
[ -d "$WT/kexts/NVRMEdpBL" ] || { echo "STOP: $WT has no kexts/NVRMEdpBL (wrong branch?)"; exit 1; }
[ -d "$O/src/nvidia" ] || { echo "STOP: no $O (extract ~/ogkm610-dl/ogkm-610.57.04.tar.gz)"; exit 1; }
mkdir -p "$OUT/NVRMEdpBL.kext/Contents/MacOS" "$ST"
cd "$WT"; echo "tree: $(git rev-parse --short HEAD) $(git status --short | wc -l | tr -d ' ') changed file(s)"
LINK=(-arch x86_64 -fapple-kext -nostdlib -Xlinker -kext -lkmodc++ -lkmod -lcc_kext)
# NVRMFB: same recipe as the shipped one (kexts/NVRMFB needs only the modeset/common headers)
xcrun clang++ -arch x86_64 -fapple-kext -mkernel -nostdinc -I"$KHDR" -Ikexts/NVRMFB -Ikexts/NVRMFB/fb \
  -I"$KMS/os-interface/include" -I"$KMS/kapi/interface" -I"$KMS/kapi/include" -I"$KMS/interface" -I"$KMS/include" \
  -I"$O/src/common/sdk/nvidia/inc" -I"$O/src/common/sdk/nvidia/inc/hw" -I"$O/src/common/inc" -I"$O/src/common/unix/common/inc" \
  -I"$O/src/common/unix/nvidia-push/interface" -I"$O/src/common/modeset" -I"$O/src/common/unix/common/utils/interface" \
  -I"$O/kernel-open/common/inc" -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT -std=c++17 -fno-rtti -fno-exceptions \
  -fno-builtin -fno-common -Wall -Wno-unused-parameter -Wno-inconsistent-missing-override -Wno-unused-function -O2 \
  -c kexts/NVRMFB/fb/nvrm-fb.cpp -o "$OUT/nvrm-fb.o"
xcrun clang++ "${LINK[@]}" "$OUT/nvrm-fb.o" -o "$OUT/NVRMFB" 2>/dev/null
# NVRMEdpBL: RM-internal headers (nv-xnu.h), links against NVRM at kmutil time
RMINC=(-I"$NV/arch/nvalloc/unix/include" -I"$NV/arch/nvalloc/common/inc" -I"$NV/arch/nvalloc/common/inc/gsp"
  -I"$O/src/common/sdk/nvidia/inc" -I"$O/src/common/sdk/nvidia/inc/hw" -I"$O/src/common/inc" -I"$O/src/common/shared/inc"
  -I"$NV/inc" -I"$NV/inc/os" -I"$NV/inc/kernel" -I"$NV/kernel/inc" -I"$NV/interface" -I"$O/src/common/nvlink/interface"
  -I"$O/src/common/inc/swref" -I"$O/src/common/inc/swref/published" -I"$NV/inc/libraries" -I"$NV/src/libraries"
  -I"$NV/generated" -I"$O/src/common/inc/displayport")
KMSINC=(-I"$KMS/os-interface/include" -I"$KMS/kapi/interface" -I"$KMS/kapi/include" -I"$KMS/interface" -I"$KMS/include"
  -I"$O/src/common/unix/common/inc" -I"$O/src/common/modeset")
DEFS=(); for m in atomic core memory sync util string crypto thread safe debug cpu time; do DEFS+=(-DPORT_MODULE_$m=1); done
CF=(-arch x86_64 -fapple-kext -mkernel -nostdinc -I"$KHDR" -I"$WT/kexts/NVRM" "${RMINC[@]}" "${KMSINC[@]}" "${DEFS[@]}"
  -DNV_KERNEL_INTERFACE_LAYER -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT -std=c++17 -fno-rtti -fno-exceptions
  -fno-builtin -fno-common -Wno-unused-parameter -Wno-deprecated-declarations -Wno-inconsistent-missing-override -Wno-macro-redefined -O2)
xcrun clang++ "${CF[@]}" -c kexts/NVRM/nvrm_edpbl.cpp -o "$OUT/nvrm_edpbl.o"
xcrun clang++ "${CF[@]}" -c kexts/NVRMEdpBL/NVRMEdpBL.cpp -o "$OUT/NVRMEdpBL.o"
xcrun clang++ "${LINK[@]}" "$OUT/nvrm_edpbl.o" "$OUT/NVRMEdpBL.o" -o "$OUT/NVRMEdpBL.kext/Contents/MacOS/NVRMEdpBL" 2>/dev/null
cp kexts/NVRMEdpBL/Info.plist "$OUT/NVRMEdpBL.kext/Contents/Info.plist"
rm -rf "$ST/NVRMEdpBL.kext"; cp "$OUT/NVRMFB" "$ST/NVRMFB"; cp -R "$OUT/NVRMEdpBL.kext" "$ST/"
( cd "$ST"; { shasum -a 256 NVRMFB | awk '{print $1"  NVRMFB"}'
              shasum -a 256 NVRMEdpBL.kext/Contents/MacOS/NVRMEdpBL | awk '{print $1"  NVRMEdpBL"}'; } > SHA256SUMS; cat SHA256SUMS )
git -C "$WT" rev-parse --short HEAD > "$ST/FORK_HEAD" 2>/dev/null || true   # which fork commit this was built from
echo "staged in $ST"
