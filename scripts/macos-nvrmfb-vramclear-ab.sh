#!/bin/bash
# LEGACY (the VRAM-clear patch was dropped 2026-10-13; last build: fork tag ga403wm-with-vramclear).
# NVRMFB VRAM-clear A/B: needs that patched NVRMFB loaded.
# Root (osascript "with administrator privileges"). Prints MB/s of the grant clear for mode 0 (rep stosq) and 1 (movnti).
PATH=/usr/bin:/bin:/usr/sbin:/sbin
sysctl -n debug.nvrmfb_clear_mode >/dev/null 2>&1 || { echo "patched NVRMFB not loaded (no debug.nvrmfb_clear_mode)"; exit 1; }
for mode in 0 1 0 1; do
  sysctl -w debug.nvrmfb_clear_mode=$mode >/dev/null
  b0=$(sysctl -n debug.nvrmfb_clear_bytes); u0=$(sysctl -n debug.nvrmfb_clear_us_sum)
  for i in 1 2 3 4 5 6; do sysctl -w debug.nvrmfb_vramtest=1 >/dev/null; sysctl -w debug.nvrmfb_vramtest=0 >/dev/null; done
  b1=$(sysctl -n debug.nvrmfb_clear_bytes); u1=$(sysctl -n debug.nvrmfb_clear_us_sum)
  du=$((u1-u0)); [ "$du" -gt 0 ] || du=1
  echo "clear_mode=$mode: $(( (b1-b0)/1048576 )) MiB in $((du/1000)) ms  =  $(( (b1-b0)/du )) MB/s"
done
sysctl -w debug.nvrmfb_clear_mode=1 >/dev/null
echo "slowest single clear (us): $(sysctl -n debug.nvrmfb_clear_us_max)"
