#!/bin/bash
# Read-only codec routing snapshot. Requires alcverbs=1 at boot and build/alc-verb.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-out/audio-codec-$(date +%Y%m%d-%H%M%S)}"
VERB=/usr/local/bin/alc-verb
[ -x "$VERB" ] || VERB=build/alc-verb
[ -x "$VERB" ] || { echo 'Missing alc-verb; run scripts/build-alc-verb.sh'; exit 1; }
if ! ioreg -r -c ALCUserClientProvider -l | /usr/bin/grep -q ALCUserClientProvider; then
  echo 'ALCUserClientProvider unavailable: reboot with alcverbs=1 before running this probe.'
  exit 1
fi
mkdir -p "$OUT"
{
  for nid in 0x02 0x03 0x14 0x17 0x21; do
    for verb in GET_POWER_STATE GET_CONNECT_SEL GET_PIN_WIDGET_CONTROL GET_CONV GET_STREAM_FORMAT; do
      "$VERB" "$nid" "$verb" 0
    done
    "$VERB" "$nid" GET_CONNECT_LIST 0
    "$VERB" "$nid" GET_AMP_GAIN_MUTE 0xa000
    "$VERB" "$nid" GET_AMP_GAIN_MUTE 0x8000
  done
} > "$OUT/codec-routing.txt" 2>&1
echo "wrote $OUT/codec-routing.txt"
