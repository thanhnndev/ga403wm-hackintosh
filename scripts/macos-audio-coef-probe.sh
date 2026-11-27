#!/bin/bash
# Read vendor coefficients without changing their values; restore the index selector.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-out/audio-coef-$(date +%Y%m%d-%H%M%S)}"
VERB=/usr/local/bin/alc-verb
[ -x "$VERB" ] || VERB=build/alc-verb
[ -x "$VERB" ] || { echo 'Missing alc-verb'; exit 1; }
if ! ioreg -r -c ALCUserClientProvider -l | /usr/bin/grep -q 'class ALCUserClientProvider'; then
  echo 'ALCUserClientProvider unavailable; boot with alcverbs=1.'
  exit 1
fi
value() {
  local result
  result=$("$VERB" "$@")
  printf '%s\n' "$result" | awk '/^0x[0-9a-fA-F]+$/ { print; found=1 } END { if (!found) exit 1 }'
}
original=$(value 0x20 GET_COEF_INDEX 0)
restore() { "$VERB" 0x20 SET_COEF_INDEX "$original" >/dev/null; }
trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$OUT"
printf 'Original index: %s\n' "$original" > "$OUT/coef-metadata.txt"
printf 'index,value\n' > "$OUT/coefficients.csv"
for ((index=0; index<256; index++)); do
  hex=$(printf '0x%02x' "$index")
  "$VERB" 0x20 SET_COEF_INDEX "$hex" >/dev/null
  coefficient=$(value 0x20 GET_PROC_COEF 0)
  printf '%s,%s\n' "$hex" "$coefficient" >> "$OUT/coefficients.csv"
done
restore
current=$(value 0x20 GET_COEF_INDEX 0)
printf 'Restored index: %s\n' "$current" >> "$OUT/coef-metadata.txt"
[[ "$current" == "$original" ]] || { echo 'Coefficient index restore failed'; exit 1; }
echo "wrote $OUT/coefficients.csv (index restored)"
