#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# run.sh [debug] (the simulator runs debug builds only) [SECONDS] - build FlutterBench, run it on the booted sim, report frame timings, CPU,
# and (debug) 5 hot reloads timed from the tool's "Reloaded ... in N ms" lines.
set -u
MODE=${1:-debug}; S=${2:-20}; HERE=$(cd "$(dirname "$0")" && pwd); APP=${FLUTTERBENCH_DIR:-$HOME/develop/sim-bench/flutterbench}
UDID=$(xcrun simctl list devices booted | awk -F'[()]' '/Booted/{print $2; exit}')
[ -n "$UDID" ] || { echo "no booted simulator"; exit 1; }
[ -d "$APP" ] || flutter create --platforms=ios --org dev.ga403 --project-name flutterbench "$APP" >/dev/null
cp "$HERE/main.dart" "$APP/lib/main.dart"; cd "$APP"
OUT=$HERE/out-$MODE.txt; FIFO=$(mktemp -u); mkfifo "$FIFO"
t0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
( exec 3>"$FIFO"; perl -e 'select undef,undef,undef,shift' 900 ) & HOLD=$!
flutter run --$MODE -d "$UDID" < "$FIFO" > "$OUT" 2>&1 & RUN=$!
until grep -q 'FLUTTERBENCH t=1 ' "$OUT" 2>/dev/null || ! kill -0 $RUN 2>/dev/null; do perl -e 'select undef,undef,undef,0.2'; done
t1=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
echo "== $MODE: flutter run -> first FLUTTERBENCH line $(echo "$t1 - $t0" | bc) s"
( cd "$HERE/.." && ./cpu.sh $((S-4)) "flutter-$MODE" > /dev/null ) & CPU=$!
perl -e 'select undef,undef,undef,shift' "$S"; wait $CPU
if [ "$MODE" = debug ]; then
  for i in 1 2 3 4 5; do
    sed -i '' "s/^const marker = '.*';/const marker = 'r$i';/" lib/main.dart
    n=$(grep -c 'Reloaded' "$OUT"); echo r > "$FIFO"
    until [ "$(grep -c 'Reloaded' "$OUT")" -gt "$n" ] || ! kill -0 $RUN 2>/dev/null; do perl -e 'select undef,undef,undef,0.1'; done
    perl -e 'select undef,undef,undef,2'
  done
  echo "hot reloads:"; grep 'Reloaded' "$OUT"
  echo "frames from the first reload on:"; awk '/Performing hot reload/{on=1} on && /FLUTTERBENCH/' "$OUT" | sed 's/.*FLUTTERBENCH //' | head -14
fi
echo q > "$FIFO"; perl -e 'select undef,undef,undef,3'; kill $HOLD $RUN 2>/dev/null; rm -f "$FIFO"
echo "frames (after the first 3 s):"
awk '/Performing hot reload/{exit} /FLUTTERBENCH/' "$OUT" | awk 'NR>3' | sed 's/.*FLUTTERBENCH //' | head -20
head -12 "$HERE/../cpu-flutter-$MODE.txt"
