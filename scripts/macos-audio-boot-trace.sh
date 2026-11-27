#!/bin/bash
# Persistent boot timeline and low-level speaker source. No mic capture or gain changes.
set -u
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin
BOOT=$(/usr/sbin/sysctl -n kern.bootsessionuuid)
OUT="/var/log/rog-audio-trace/$BOOT"
umask 077
mkdir -p "$OUT"
exec >"$OUT/collector.log" 2>&1
echo "boot=$BOOT collector-start=$(date -u +%FT%TZ)"
/usr/sbin/sysctl kern.boottime kern.bootargs > "$OUT/boot.txt"
/usr/sbin/kextstat > "$OUT/kexts.txt" 2>&1
/usr/sbin/ioreg -a -l -r -n SPKR > "$OUT/acpi-spkr.plist"
/usr/sbin/ioreg -a -l -r -n GPIO > "$OUT/gpio.plist"
/usr/bin/log stream --level debug --style compact --predicate 'process == "kernel" AND (eventMessage CONTAINS[c] "StrixAmp" OR eventMessage CONTAINS[c] "AppleHDA" OR eventMessage CONTAINS[c] "AppleALC")' > "$OUT/kernel-live.log" 2>&1 &
STREAM=$!
trap 'kill "$STREAM" 2>/dev/null || true' EXIT
snapshot() {
  local stage="$1"
  echo "snapshot=$stage time=$(date -u +%FT%TZ)"
  /usr/sbin/ioreg -a -l -r -c StrixAmp > "$OUT/$stage-amp.plist"
  /usr/sbin/ioreg -a -l -r -c IOHDACodecDevice > "$OUT/$stage-codec.plist"
  /usr/sbin/ioreg -a -l -r -c AppleHDAController > "$OUT/$stage-hda.plist"
  /usr/local/bin/strixampctl diag > "$OUT/$stage-amp.txt" 2>&1
  /usr/local/bin/strixampctl fwdiag /usr/local/share/strixamp/fw/CS35L56_Rev3.11.16.wmfw > "$OUT/$stage-dsp.txt" 2>&1
  bash "$(dirname "$0")/macos-audio-codec-probe.sh" "$OUT/$stage-codec" > "$OUT/$stage-codec-probe.log" 2>&1
}
snapshot start
sleep 2
snapshot after-2s
sleep 8
snapshot after-10s
sleep 20
snapshot after-30s
if /usr/sbin/ioreg -r -c StrixAmp -l | /usr/bin/grep -q '"TraceEnabled" = Yes'; then
  '/Library/Application Support/RogAudio/rogaudio-probe' speakers 'AppleHDAEngineOutput:0,6,0,1,1:0' 20 > "$OUT/speaker-source.txt" 2>&1 &
  SOURCE=$!
  sleep 2
  snapshot playing-2s
  sleep 4
  snapshot playing-6s
  sleep 4
  snapshot playing-10s
  sleep 4
  snapshot playing-14s
  wait "$SOURCE"
  echo "speaker-source-exit=$?"
else
  echo 'Speaker source skipped: trace kext not active yet.'
  sleep 20
fi
sleep 40
snapshot after-90s
/usr/bin/pmset -g log > "$OUT/power-history.txt" 2>&1
bash "$(dirname "$0")/macos-audio-coef-probe.sh" "$OUT/after-90s-coef"
cp /var/log/strixamp.log "$OUT/strixamp.log"
/usr/bin/log show --last 10m --style compact --predicate 'process == "kernel" AND (eventMessage CONTAINS[c] "StrixAmp" OR eventMessage CONTAINS[c] "AppleHDA" OR eventMessage CONTAINS[c] "AppleALC")' > "$OUT/kernel-history.log" 2>&1
kill "$STREAM" 2>/dev/null || true
wait "$STREAM" 2>/dev/null || true
trap - EXIT
echo "complete=$(date -u +%FT%TZ)"
