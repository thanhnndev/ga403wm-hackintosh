#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# A/B of NMXGPU's GTT cache mode in one boot (root: nmx-tune set needs it). Runs render-stress.sh N for nmx_wc=1 then 0.
#   osascript -e 'do shell script "bash <repo>/tools/890m/wc-ab.sh 6 > /tmp/wc-ab.out 2>&1" with administrator privileges'
N=${1:-6}; D=$(cd "$(dirname "$0")" && pwd)
for m in 1 0; do
  "$D/build/nmx-tune" set$m
  echo "=== nmx_wc=$m ==="
  "$D/render-stress.sh" "$N" 2>&1 | grep -E "^run|^pass|ringdump" | cut -c1-200
done
"$D/build/nmx-tune" set1
