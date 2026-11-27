#!/bin/bash
# Read-only snapshot of the audio stack on the GA403WM: HDEF/ALC285, AppleALC state, the Cirrus amp ACPI node and the
# VoodooI2C nub that already sits on it, ACP 7.0 nodes. Plays and records nothing. See docs/AUDIO-ROG.md.
#
#   scripts/macos-audio-collect.sh [outdir]      (default: out/audio-<timestamp>)
set -u

OUT="${1:-out/audio-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"

# ioreg's IOKitDiagnostics line is huge and changes every call; drop it.
ior() { ioreg "$@" 2>/dev/null | grep -v IOKitDiagnostics; }

{
  echo "# $(date '+%F %T') $(sw_vers -productVersion) $(uname -m)"
  echo; echo "## kexts"
  kextstat 2>/dev/null | grep -i -E "lilu|alc|applehda|audio|voodoo|asuswmi" | awk '{print $6, $7}'
} > "$OUT/summary.txt"

system_profiler SPAudioDataType > "$OUT/system_profiler-audio.txt" 2>&1
ior -r -n HDEF -l -w0                 > "$OUT/ioreg-hdef.txt"
ior -r -c IOHDACodecDevice -l -w0     > "$OUT/ioreg-hda-codec.txt"
ior -r -c IOAudioDevice -l -w0        > "$OUT/ioreg-ioaudiodevice.txt"
ior -p IOACPIPlane -l -w0             > "$OUT/ioreg-acpi-plane.txt"
ior -r -c VoodooI2CController -l -w0  > "$OUT/ioreg-voodooi2c.txt"

# the lines that answer the open questions, in one place
{
  echo "## HDEF identity";   grep -E '"(vendor-id|device-id|subsystem-vendor-id|subsystem-id|layout-id|alc-layout-id|PinConfigurations)"' "$OUT/ioreg-hdef.txt"
  echo "## codec";           grep -E 'IOHDACodecVendorID|IOHDACodecFunctionSubsystemID|CodecName|"LayoutID"' "$OUT/ioreg-hda-codec.txt" | cut -c1-240
  echo "## Cirrus amp node (expect name CSC3556, VoodooI2CDeviceNub SPKR)"
  grep -n -B1 -A6 'CSC35' "$OUT/ioreg-acpi-plane.txt" | cut -c1-200
  grep -n 'SPKR' "$OUT/ioreg-voodooi2c.txt" | cut -c1-200
  echo "## ACP 7.0 children (expect !registered, !matched: no driver)"
  grep -n -E 'ACP@5|HDA0@1|I2SC@3|BTSC@4|SDWC@5|SDWS@6|USBS@7' "$OUT/ioreg-acpi-plane.txt" | cut -c1-160
} >> "$OUT/summary.txt"

echo "wrote $OUT/summary.txt"
