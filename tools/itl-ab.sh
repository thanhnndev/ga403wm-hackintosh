#!/bin/bash
# itl-ab.sh - A/B matrix of the itlmt7925 data path inside ONE boot (run as root, after the Wi-Fi link is up and WARP/VPN is off).
#
#   cc -o /tmp/itlctl tools/itlctl.c -framework IOKit -framework CoreFoundation
#   sudo /bin/bash tools/itl-ab.sh /tmp/itlctl /tmp/itl-ab.txt [wifi-interface, default: the itlmt7925 interface from ioreg]
#
# Every configuration is applied with itlctl (reconnect at a level, 160 MHz on/off, power tables, reorder timeout), then measured:
# 1400 B and 56 B pings to the gateway and to 1.1.1.1, a 10 s download, and the driver's own counters before and after.
# Boot with itlmt_nopwr=1 itlmt_stat=1 (no CLC/SAR tables at join, stat-log every second) so that the tables can be compared too.
# All traffic is bound to the Wi-Fi interface (ping -b / curl --interface): the default route may be a phone tether, and the first
# version of this script measured that instead (round 26, 2026-10-14).
CTL=${1:?itlctl path}
OUT=${2:?output file}
IF=${3:-}
if [ -z "$IF" ]; then
  IF=$(ioreg -l -w0 -r -c itlmt7925 | grep -o 'IOSkywalkLegacyEthernet/en[0-9]*' | head -1 | sed 's|.*/||')
fi
[ -n "$IF" ] || { echo "no Wi-Fi interface found" >&2; exit 2; }
: > "$OUT"
GW=$(ipconfig getoption "$IF" router 2>/dev/null)
if [ -z "$GW" ]; then
  echo "itl-ab: $IF has no router (not joined?) - nothing to measure" | tee -a "$OUT"
  exit 3
fi

prop() { ioreg -l -w0 | grep -E "\"$1\" = " | sed -e 's/^[ |]*//' | head -1 | cut -c1-${2:-1500}; }
say() { echo "$@" | tee -a "$OUT" >/dev/null; }

wait_link() {   # $1 = level expected in rx-log; the new link is the one whose stat-log "up=" counter restarted
  local i up
  sleep 3
  for i in $(seq 1 60); do
    up=$(prop stat-log | sed -n 's/.*up=\([0-9]*\)s.*/\1/p')
    GW=$(ipconfig getoption "$IF" router 2>/dev/null)
    if [ -n "$up" ] && [ "$up" -lt 40 ] && prop rx-log 1500 | grep -q " lvl=$1 " && [ -n "$GW" ] && ping -b "$IF" -c1 -t1 "$GW" >/dev/null 2>&1; then
      sleep 4
      return 0
    fi
    sleep 2
  done
  return 1
}

measure() {   # $1 = tag
  say ""
  say "=================== $1  ($(date +%H:%M:%S))  if=$IF gw=$GW"
  say "before: $(prop stat-log)"
  say "before: $(prop rx-log)"
  say "ping gw   1400B: $(ping -b "$IF" -c 100 -i 0.05 -s 1400 "$GW" 2>&1 | grep -E 'packet loss|round-trip' | tr '\n' ' ')"
  say "ping wan  1400B: $(ping -b "$IF" -c 100 -i 0.05 -s 1400 1.1.1.1 2>&1 | grep -E 'packet loss|round-trip' | tr '\n' ' ')"
  say "ping wan    56B: $(ping -b "$IF" -c 100 -i 0.05 1.1.1.1 2>&1 | grep -E 'packet loss' | tr '\n' ' ')"
  say "download 10 s : $(curl -4 --interface "$IF" -s -o /dev/null -m 10 -w 'ttfb=%{time_starttransfer}s bytes=%{size_download} speed=%{speed_download} B/s' 'https://mensura.cdn-apple.com/api/v1/gm/large' 2>&1)"
  say "after : $(prop stat-log)"
  say "after : $(prop rx-log)"
  say "ts-log (eth,ring,tx,fwretry,noslot,old,timeout per s, last 14): $(prop ts-log 4000 | sed -e 's/.*= "//' -e 's/"$//' | tr ';' '\n' | tail -14 | tr '\n' ' ')"
  say "events: $(prop wifi-events 600)"
}

apply() {   # $1 = tag, then itlctl arguments, last word of the tag line = expected level
  local tag=$1 lvl=$2
  shift 2
  say ""
  say "--- apply: $* ($tag)"
  "$CTL" "$@" 2>&1 | tee -a "$OUT" >/dev/null
  if ! wait_link "$lvl"; then say "!!! link did not come back at level $lvl in 120 s"; fi
  measure "$tag"
}

say "itl-ab start $(date) if=$IF gateway=$GW"
say "m3-log (power / efuse): $(prop m3-log 2400 | grep -oE 'sar:[^;]*;|clc[^;]*;|txpower[^;]*;|efuse[^;]*;|power tables[^;]*;' | tr '\n' ' ')"
measure "A  L6 HE 160 MHz, A-MSDU off (boot state), no tables"
apply "B  L6 HE 80 MHz, A-MSDU off"                    6 itl_no160=1 itl_lvl=6
apply "C  L5 VHT 160 MHz (no HE), A-MSDU off"          5 itl_no160=0 itl_lvl=5
apply "D  L4 VHT 80 MHz, A-MSDU off"                   4 itl_no160=1 itl_lvl=4
apply "E  L3 VHT 80 MHz, TX pool, A-MSDU off"          3 itl_lvl=3
apply "F  L6 HE 160 MHz, A-MSDU ON (diagnosis)"        6 itl_no160=0 itl_amsdu=1 itl_lvl=6
apply "G  L4 VHT 80 MHz, A-MSDU ON"                    4 itl_no160=1 itl_lvl=4
apply "H  L6 HE 160 MHz, A-MSDU off again"             6 itl_no160=0 itl_amsdu=0 itl_lvl=6
say ""
say "--- apply: itl_pwr=40 (CLC + SKU tables, 20 dBm ceiling), same link"
"$CTL" itl_pwr=40 2>&1 | tee -a "$OUT" >/dev/null
sleep 6
measure "I  L6 HE 160 MHz + power tables (20 dBm ceiling), A-MSDU off"
apply "J  L6 HE 160 MHz, reorder 10 ms"                6 itl_reo=10 itl_lvl=6
apply "K  L6 HE 160 MHz, reorder 100 ms"               6 itl_reo=100 itl_lvl=6
say ""
say "itl-ab done $(date)"
