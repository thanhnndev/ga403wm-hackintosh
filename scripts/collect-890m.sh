#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Reads what Linux knows about the Radeon 890M (Strix Point, PCI 1002:150e) and prints it as Markdown: IP versions,
# memory layout, BARs, firmware, connectors, ACPI/VBIOS access. Read-only: nothing is written to the GPU.
#
#   scripts/collect-890m.sh                 > docs/890M-LINUX-DUMP.md    (unprivileged, enough for most of it)
#   sudo scripts/collect-890m.sh            > out/890m-root.md           (adds PCI config space, debugfs, VFCT/VBIOS copies)
#
# Run it twice: once in Ultimate (MUX -> dGPU) and once in Hybrid (MUX -> iGPU), where the eDP panel hangs off the 890M
# and its EDID / link / DSC / PSR state becomes readable. The root run saves binaries into out/ (git-ignored).
set -u
cd "$(dirname "$0")/.."

PCI="${GPU_PCI:-}"
if [ -z "$PCI" ]; then
  PCI=$(lspci -Dnn | awk '/\[1002:150e\]/ {print $1; exit}')
fi
[ -n "$PCI" ] || { echo "no 1002:150e device found; set GPU_PCI=0000:xx:00.0" >&2; exit 1; }
DEV="/sys/bus/pci/devices/$PCI"
CARD=$(basename "$(ls -d "$DEV"/drm/card* 2>/dev/null | head -1)")
CARD_SYS="/sys/class/drm/$CARD"
OUT=${GPU_OUT:-out/890m}
SHORT=${PCI#0000:}

rd() { if [ -r "$1" ]; then tr '\n' ' ' < "$1" | sed 's/ *$//'; else printf 'n/a'; fi; }
sec() { printf '\n## %s\n\n' "$1"; }
fence() { printf '```\n'; cat; printf '```\n'; }

printf '# Radeon 890M on Linux: collected data\n\n'
printf 'Host `%s`, kernel `%s`, BIOS `%s`, collected %s, EUID %s\n' \
  "$(cat /sys/class/dmi/id/product_name)" "$(uname -r)" "$(cat /sys/class/dmi/id/bios_version)" "$(date -u +%FT%TZ)" "$EUID"
printf 'GPU `%s` (`%s`), `%s`\n' "$PCI" "$(rd $DEV/vendor):$(rd $DEV/device) rev $(rd $DEV/revision)" "$CARD"
printf 'ASUS gpu_mux_mode=%s dgpu_disable=%s (0 = Ultimate / dGPU drives the panel)\n' \
  "$(rd /sys/class/firmware-attributes/asus-armoury/attributes/gpu_mux_mode/current_value)" \
  "$(rd /sys/class/firmware-attributes/asus-armoury/attributes/dgpu_disable/current_value)"

sec "PCI function and BARs"
lspci -nn -s "$SHORT" | fence
lspci -vvv -s "$SHORT" 2>/dev/null | grep -E "Region|Expansion ROM|Interrupt|Capabilities|LnkCap|LnkSta|Resizable" | fence
printf 'Sibling functions of the same device (power dependencies; the xHCI at .4 is one of the USB controllers of ItlXhciKick):\n\n'
lspci -nn -s "${SHORT%.*}" | fence

sec "Memory"
for f in mem_info_vram_total mem_info_vis_vram_total mem_info_gtt_total mem_info_vram_used vbios_version vbios_build; do
  printf -- '- %s: %s\n' "$f" "$(rd $DEV/$f)"
done

sec "IP blocks (IP discovery table, sysfs)"
B="$DEV/ip_discovery/die/0"
if [ -d "$B" ]; then
  {
    printf '%-9s %-4s %-6s %-5s %s\n' IP inst hw_id ver base_addr
    for ip in "$B"/*/; do
      n=$(basename "$ip"); case "$n" in [A-Z]*) ;; *) continue ;; esac
      for i in "$ip"*/; do
        [ -f "$i/major" ] || continue
        printf '%-9s %-4s %-6s %-5s %s\n' "$n" "$(basename "$i")" "$(rd $i/hw_id)" "$(rd $i/major).$(rd $i/minor).$(rd $i/revision)" "$(tr '\n' ' ' < "$i/base_addr")"
      done
    done
  } | fence
else
  echo "ip_discovery sysfs not available on this kernel"
fi

sec "Kernel log of the amdgpu probe"
journalctl -k -b --no-pager 2>/dev/null | grep -E "amdgpu $PCI|amdgpu:" | grep -vE "PSR support" | sed 's/^.*kernel: //' | head -80 | fence

sec "Firmware files this ASIC loads (linux-firmware)"
modinfo amdgpu 2>/dev/null | awk '/^firmware:/ {print $2}' \
  | grep -E "gc_11_5_0|sdma_6_1_0|psp_14_0_0|vcn_4_0_5|dcn_3_5_dmcub|smu_14_0_0|mes_11|isp_4_1" | sort | fence

sec "Connectors"
for c in "$CARD_SYS"-*; do
  [ -d "$c" ] || continue
  printf -- '- %s: %s, enabled=%s, edid=%s bytes\n' "$(basename "$c")" "$(rd "$c/status")" "$(rd "$c/enabled")" "$(wc -c < "$c/edid" 2>/dev/null || echo 0)"
done
for c in "$CARD_SYS"-eDP-*; do
  [ -r "$c/edid" ] || continue
  mkdir -p "$OUT"
  cp "$c/edid" "$OUT/$(basename "$c").edid" 2>/dev/null || continue
  [ -s "$OUT/$(basename "$c").edid" ] || continue
  printf '\nEDID of %s:\n\n' "$(basename "$c")"
  edid-decode "$OUT/$(basename "$c").edid" 2>/dev/null | fence
done

sec "Power and clocks"
for f in power_dpm_state power_dpm_force_performance_level pp_dpm_sclk pp_dpm_fclk pp_dpm_socclk power/runtime_status power/control current_link_speed current_link_width; do
  printf -- '- %s: %s\n' "$f" "$(rd $DEV/$f)"
done

sec "Vulkan (RADV)"
vulkaninfo --summary 2>/dev/null | grep -A12 -E "GPU[0-9]" | grep -E "deviceName|driverInfo|apiVersion|deviceID|deviceType" | fence

sec "Privileged data"
if [ "$EUID" -ne 0 ]; then
  echo "Not run as root: PCI config space, amdgpu debugfs and the ACPI VFCT table are skipped. Re-run with sudo."
  exit 0
fi
mkdir -p "$OUT"
printf 'Binaries are saved under %s (git-ignored).\n\n' "$OUT"
lspci -xxxx -s "$SHORT" > "$OUT/pci-config-4k.txt" 2>&1 && echo "- PCI config space (4 KiB): $OUT/pci-config-4k.txt"
cp /sys/firmware/acpi/tables/VFCT "$OUT/VFCT.bin" 2>/dev/null && echo "- ACPI VFCT (VBIOS image): $OUT/VFCT.bin"
DBG=$(ls -d /sys/kernel/debug/dri/*/ 2>/dev/null | while read -r d; do [ -e "$d/amdgpu_firmware_info" ] && grep -q "$SHORT" "$d/name" 2>/dev/null && echo "$d"; done | head -1)
if [ -n "$DBG" ]; then
  printf '\nFirmware versions (%s):\n\n' "$DBG"
  fence < "$DBG/amdgpu_firmware_info"
  [ -e "$DBG/amdgpu_vbios" ] && cp "$DBG/amdgpu_vbios" "$OUT/vbios.bin" && echo "- VBIOS from debugfs: $OUT/vbios.bin"
  for k in amdgpu_gpu_info amdgpu_vram_mm amdgpu_gtt_mm amdgpu_vm_info; do
    [ -r "$DBG/$k" ] && { printf '\n%s:\n\n' "$k"; head -40 "$DBG/$k" | fence; }
  done
  for c in "$DBG"/eDP-*; do
    [ -d "$c" ] || continue
    printf '\n%s debugfs:\n\n' "$(basename "$c")"
    for k in link_settings dsc_clock_en dsc_slice_width psr_capability psr_state output_bpc dp_dsc_fec_support; do
      if [ -r "$c/$k" ]; then
        printf '%s: ' "$k"
        tr -d '\000' < "$c/$k" | tr '\n' ' '
        printf '\n'
      fi
    done | fence
  done
else
  echo "amdgpu debugfs not found (mount -t debugfs none /sys/kernel/debug?)"
fi
