#!/bin/zsh
# Step142 (out-24) idle-park probe: samples the IOSurface park counters every second and collects NMXGPU fault and
# timeout lines from the kernel log during the run. Read-only: changes no sysctl, launches nothing.
#
# usage: park-probe.sh outdir [seconds=120]
# writes outdir/{rec,faults,by-kind-start,by-kind-end}.txt and prints a pass/fail summary.
# rec.txt columns: time userwire_pages surfwire_pages parked_pages parks unparks unpark_fail restore_fail
#                  destroy_rec skip_busy park_fail timeouts
D=${1:?outdir}; N=${2:-120}
mkdir -p $D
c() { local v=$(sysctl -n $1 2>/dev/null); printf '%s' "${v:--}"; }
if [[ $(c debug.nmx_userwire_parks) == - ]]; then echo "running NMXGPU has no Step142 sysctls (not out-24?)"; exit 1; fi
sysctl -n debug.nmx_userwire_by_kind > $D/by-kind-start.txt
# kernel log: GPU VM faults (gmc11 + the Step135 romap line), ring timeouts/resets, Step142 failures
log stream --style compact --predicate 'sender == "NMXGPU"' 2>/dev/null \
  | grep --line-buffered -E 'fault|FAULT|timeout|reset|NMX: address|restore|unpark' > $D/faults.txt &
lg=$!
for ((i = 0; i < N; i++)); do
  echo "$(date +%T) $(c debug.nmx_userwire_pages) $(c debug.nmx_surfwire_pages) $(c debug.nmx_userwire_parked_pages)" \
       "$(c debug.nmx_userwire_parks) $(c debug.nmx_userwire_unparks) $(c debug.nmx_userwire_unpark_fail)" \
       "$(c debug.nmx_upin_restore_fail) $(c debug.nmx_upin_destroy_rec) $(c debug.nmx_park_skip_busy)" \
       "$(c debug.nmx_park_fail) $(c debug.nmx_timeouts)"
  perl -e 'select(undef,undef,undef,1)'
done > $D/rec.txt
kill $lg 2>/dev/null; pkill -P $lg 2>/dev/null
sysctl -n debug.nmx_userwire_by_kind > $D/by-kind-end.txt
awk 'NR==1{f=$0; split($0,a)} {l=$0; split($0,b); if($4>mx)mx=$4; if(mn==""||$4<mn)mn=$4}
  END{
    printf "userwire %.0f -> %.0f MB, surfwire %.0f -> %.0f MB, parked %.0f -> %.0f MB (min %.0f, max %.0f)\n",
      a[2]*4/1024, b[2]*4/1024, a[3]*4/1024, b[3]*4/1024, a[4]*4/1024, b[4]*4/1024, mn*4/1024, mx*4/1024;
    printf "parks +%d unparks +%d skip_busy +%d | unpark_fail %d restore_fail %d park_fail %d destroy_rec %d timeouts +%d\n",
      b[5]-a[5], b[6]-a[6], b[10]-a[10], b[7], b[8], b[11], b[9], b[12]-a[12];
    bad = (b[7] != 0 || b[8] != 0 || b[12] != a[12]);
    print (bad ? "FAIL: unpark/restore failures or new ring timeouts" : "counters OK") }' $D/rec.txt
nf=$(grep -cE 'fault|FAULT|NMX: address' $D/faults.txt)
echo "kernel log: $nf fault lines, $(grep -cE 'timeout|reset' $D/faults.txt) timeout/reset lines (see $D/faults.txt)"
echo "--- by_kind at end"; cat $D/by-kind-end.txt
