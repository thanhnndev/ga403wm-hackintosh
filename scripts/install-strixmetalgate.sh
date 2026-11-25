#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# macOS: builds StrixMetalGate, injects it from the ESP (EFI/OC/Kexts, no /Library/Extensions write, no AuxKC rebuild),
# adds its Kernel/Add entry and drops -strixaccoff from boot-args, so the next boot takes the Metal compositor path with
# a Metal device for WindowServer. Run from a boot that has a desktop (e.g. with -strixaccoff). Rollback: the config
# backup this prints, or `occonfig.py args add -- -strixaccoff`.
#
#   ESP=/Volumes/EFI bash scripts/install-strixmetalgate.sh     (ESP defaults to the mounted volume holding EFI/OC)
set -euo pipefail
cd "$(dirname "$0")/.."

bash scripts/build.sh StrixMetalGate
[ -d build/StrixMetalGate.kext ] || { echo "build/StrixMetalGate.kext missing"; exit 1; }

find_esp() {
  local v
  for v in /Volumes/*; do [ -f "$v/EFI/OC/config.plist" ] && { echo "$v"; return 0; }; done
  # not mounted: try every EFI system partition
  local d
  for d in $(diskutil list | awk '/EFI/ {print $NF}'); do
    sudo diskutil mount "$d" >/dev/null 2>&1 || true
  done
  for v in /Volumes/*; do [ -f "$v/EFI/OC/config.plist" ] && { echo "$v"; return 0; }; done
  return 1
}
ESP="${ESP:-$(find_esp)}" || { echo "no ESP with EFI/OC/config.plist found; set ESP=/Volumes/<name>"; exit 1; }
CFG="$ESP/EFI/OC/config.plist"
echo "ESP: $ESP"

sudo rm -rf "$ESP/EFI/OC/Kexts/StrixMetalGate.kext"
sudo ditto build/StrixMetalGate.kext "$ESP/EFI/OC/Kexts/StrixMetalGate.kext"

TAG="pre-metalgate-$(date +%Y%m%d-%H%M%S)"
ENTRY='{"Arch":"x86_64","BundlePath":"StrixMetalGate.kext","Comment":"gives WindowServer the NVIDIA Metal device when no NVIDIA display head exists (docs/890M-TRACE.md)","Enabled":true,"ExecutablePath":"Contents/MacOS/StrixMetalGate","MaxKernel":"","MinKernel":"24.0.0","PlistPath":"Contents/Info.plist"}'
OCC=(sudo python3 -I tools/occonfig.py -c "$CFG")
if "${OCC[@]}" get 'Kernel/Add/[BundlePath=StrixMetalGate.kext]' >/dev/null 2>&1; then
  echo "Kernel/Add already has StrixMetalGate.kext"
else
  "${OCC[@]}" add --tag "$TAG" Kernel/Add "$ENTRY"
fi
"${OCC[@]}" args del --tag "$TAG-args" -- -strixaccoff || true
"${OCC[@]}" check | tail -2
echo "boot-args now:"; "${OCC[@]}" args show
echo "backup: $ESP/EFI/OC/config.plist.$TAG"
echo "reboot; then: ioreg -l -w0 | grep -E 'GateState|StrixMetalGate|MetalPluginName'"
