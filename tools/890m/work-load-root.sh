#!/bin/bash
# work-load-root.sh: one root sample of the owner's live working load (WS-CPU 9.4), one password, ~1 min. Run as ROOT
# while the owner works (video + Claude + whatever is open); it changes nothing, writes no sysctl, installs nothing,
# opens no window and wakes nothing.
#   1. ws-cpu-profile.sh none 15: WindowServer-only spindump at 1 ms + per-thread CPU + presents (our share per present:
#      tools/890m/ws-spin-buckets.py none.spin.txt <presents>)
#   2. spindump of ALL processes for 10 s at 10 ms: who commits the frames WindowServer composites
#   3. vmmap -summary of WindowServer and the wired-memory sources root can read (memory question)
# Output: ~<console user>/ga403-logs/work-load-<time>/ plus ws-cpu-<time>/ from step 1.
set -u
[ "$(id -u)" = 0 ] || { echo "run as root (spindump, vmmap of WindowServer)"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
cu=$(stat -f %Su /dev/console); home=$(dscl . -read /Users/"$cu" NFSHomeDirectory | awk '{print $2}')
out=$home/ga403-logs/work-load-$(date +%Y%m%d-%H%M%S); mkdir -p "$out"
ws=$(pgrep -x WindowServer)
echo "$(date +%T) start; flips $(sysctl -n debug.nmxaccel_flip_submitted)" | tee "$out/log.txt"
"$here/ws-cpu-profile.sh" none 15 2>&1 | tee -a "$out/log.txt"
spindump -noTarget 10 10 -noProcessingWhileSampling -file "$out/all.spin.txt" > /dev/null 2>&1
ps -axo pid,pcpu,rss,time,comm > "$out/ps.txt"
vmmap -summary "$ws" > "$out/ws-vmmap-summary.txt" 2>&1
vm_stat > "$out/vm_stat.txt"
sysctl -n debug.nmx_gtt > "$out/nmx_gtt.txt" 2>&1
sysctl -n debug.nmx_userwire_by_kind > "$out/userwire.txt" 2>&1
# WindowServer is sandboxed: confstr(_CS_DARWIN_USER_CACHE_DIR) gives .../C/WindowServer/ (its Mesa line names
# .../C/WindowServer/nvmtl-mesa), so the plugin's aircache/spvcache land under .../C/WindowServer/nvmtl (or T/WindowServer)
for d in /private/var/folders/zz/zyxvpxvq6csfxvn_n00000b000002r/[CT]/WindowServer/nvmtl/spvcache /private/var/folders/zz/zyxvpxvq6csfxvn_n00000b000002r/[CT]/nvmtl/spvcache; do
    [ -d "$d" ] && echo "$d: low2 $(ls "$d" | grep -c '\.low2\.') fc2 $(ls "$d" | grep -c '\.fc2\.') all $(ls "$d" | wc -l)" || echo "$d: missing"
done > "$out/ws-spvcache.txt" 2>&1
# login cost: does RADV's disk cache (Mesa euid patch, WS-CPU 8.5) fill and get used in WindowServer? files, size, newest
m=/private/var/folders/zz/zyxvpxvq6csfxvn_n00000b000002r/C/WindowServer/nvmtl-mesa
{ ls -ld "$m" "$m"/* 2>&1; echo "files $(find "$m" -type f 2>/dev/null | wc -l) bytes $(du -sk "$m" 2>/dev/null | cut -f1) KB";
  echo "newest:"; find "$m" -type f -exec stat -f '%Sm %z %N' -t '%F %T' {} + 2>/dev/null | sort | tail -5;
  echo "oldest:"; find "$m" -type f -exec stat -f '%Sm %z %N' -t '%F %T' {} + 2>/dev/null | sort | head -3; } > "$out/ws-mesa-cache.txt" 2>&1
echo "$(date +%T) end; flips $(sysctl -n debug.nmxaccel_flip_submitted)" | tee -a "$out/log.txt"
chown -R "$cu" "$out"
echo "done: $out"
