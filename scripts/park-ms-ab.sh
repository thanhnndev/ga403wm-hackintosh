#!/bin/bash
# park-ms-ab.sh - A/B of NMXGPU's IOSurface userptr park age (debug.nmx_userptr_park_ms, Step142) under the daily load.
#
#   scripts/park-ms-ab.sh [arm_seconds=600] [arms="60000 30000 20000"] [outdir=~/ga403-logs/park-ms-ab-<stamp>]
#
# One password: the whole run executes as root behind a single osascript "administrator privileges" dialog, because
# the sysctl writes need root. A trap restores the value read at the start (60000 if unreadable) on exit, error,
# Ctrl-C or kill, and the restored value is read back and logged. Nothing else is written. No app is started or stopped.
# Video drops are not measured: yt-probe needs a scratch Chrome launch. Instead the log has the flips/vblanks from
# debug.nmx_frametrace and WindowServer CPU.
#
# Per arm: first 60 s settle (not counted), then a sample every 5 s of:
#   parks, unparks, userwire pages, parked pages, WindowServer surface wire (debug.nmx_userwire_by_kind), pages_live,
#   kernel_task and WindowServer CPU time, display flips.
# Output: samples.tsv, arms.txt (the value set and read back per arm), summary.txt.
set -u
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")

if [ "${1:-}" != "--root" ]; then
    ARM=${1:-600}; ARMS=${2:-"60000 30000 20000"}
    OUT=${3:-$HOME/ga403-logs/park-ms-ab-$(date +%Y%m%d-%H%M%S)}
    mkdir -p "$OUT" || exit 1
    case "$ARM" in ''|*[!0-9]*) echo "arm_seconds must be a number" >&2; exit 1;; esac
    for v in $ARMS; do case "$v" in ''|*[!0-9]*) echo "arm value $v is not a number" >&2; exit 1;; esac; done
    sysctl -n debug.nmx_userptr_park_ms >/dev/null 2>&1 || { echo "debug.nmx_userptr_park_ms not present (NMXGPU without Step142?)" >&2; exit 1; }
    n=$(echo $ARMS | wc -w | tr -d ' ')
    echo "park-ms A/B: arms [$ARMS], ${ARM}s each (~$(( (ARM * n) / 60 )) min), output $OUT"
    echo "One administrator password dialog follows. The original value is restored when the run ends, however it ends."
    osascript -e "do shell script \"/bin/bash '$SELF' --root '$OUT' $ARM '$ARMS' $(id -u)\" with administrator privileges" || {
        echo "root run failed or was cancelled; check $OUT/arms.txt for the restore line" >&2; }
    cat "$OUT/summary.txt" 2>/dev/null
    exit 0
fi

# ---- root part ----
OUT=$2; ARM=$3; ARMS=$4; OWNER=$5
SETTLE=60; INT=5
K=debug.nmx_userptr_park_ms
ORIG=$(sysctl -n $K 2>/dev/null); case "$ORIG" in ''|*[!0-9]*) ORIG=60000;; esac
log() { echo "$(date '+%T') $*" >> "$OUT/arms.txt"; }
restore() {
    sysctl -w $K=$ORIG >/dev/null 2>&1
    log "restore $K=$ORIG, read back $(sysctl -n $K 2>/dev/null)"
    chown -R "$OWNER" "$OUT" 2>/dev/null
}
trap 'restore; exit 1' INT TERM HUP
trap 'restore' EXIT
log "start, $K was $ORIG, arms [$ARMS], ${ARM}s each, settle ${SETTLE}s"

pause() { perl -e "select(undef,undef,undef,$1)"; }
secs() { perl -ne 'chomp; my @p=split /:/; my $s=0; $s=$s*60+$_ for @p; print "$s\n"'; }   # ps/top TIME -> seconds
WS=$(pgrep -x WindowServer | head -1)
ktime() { top -l 1 -pid 0 -stats pid,time | awk '$1=="0"{print $2}' | secs; }
wstime() { ps -o cputime= -p "$WS" 2>/dev/null | tr -d ' ' | secs; }
wswire() { sysctl -n debug.nmx_userwire_by_kind 2>/dev/null | awk '$1=="WindowServer"{print $2; f=1} END{if(!f) print 0}'; }
flips() { sysctl -n debug.nmx_frametrace 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="flips") {print $(i+1); exit}}'; }
c() { sysctl -n "$1" 2>/dev/null || echo 0; }

printf "t\tarm\tcounted\tparks\tunparks\tuserwire\tparked\twswire\tlive\tktime\twstime\tflips\n" > "$OUT/samples.tsv"
for v in $ARMS; do
    sysctl -w $K=$v >/dev/null 2>&1
    rb=$(sysctl -n $K 2>/dev/null)
    log "arm $v: set, read back $rb"
    [ "$rb" = "$v" ] || { log "arm $v: read-back mismatch, stopping"; exit 1; }
    t0=$(date +%s)
    while [ $(( $(date +%s) - t0 )) -lt "$ARM" ]; do
        el=$(( $(date +%s) - t0 ))
        cnt=0; [ "$el" -ge "$SETTLE" ] && cnt=1
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$(date +%s)" "$v" "$cnt" \
            "$(c debug.nmx_userwire_parks)" "$(c debug.nmx_userwire_unparks)" "$(c debug.nmx_userwire_pages)" \
            "$(c debug.nmx_userwire_parked_pages)" "$(wswire)" "$(c debug.nmx_pages_live)" "$(ktime)" "$(wstime)" "$(flips)" \
            >> "$OUT/samples.tsv"
        pause $INT
    done
done

perl - "$OUT/samples.tsv" > "$OUT/summary.txt" <<'PERL'
my $f=shift; open my $h,'<',$f or die; <$h>; my (%a,@order);
while(<$h>){ chomp; my @v=split /\t/; next unless $v[2]; push @order,$v[1] unless $a{$v[1]}; push @{$a{$v[1]}},\@v; }
my $gb=4096/2**30;
printf "%-8s %6s | %8s %8s %6s | %9s %9s %9s %9s | %7s %7s %7s\n","park_ms","s","parks/s","unpark/s","ratio","userwire","parked","WS wire","live","kt cores","WS cores","flips/s";
for my $arm (@order){ my $r=$a{$arm}; next if @$r<2; my ($x,$y)=($r->[0],$r->[-1]); my $dt=$y->[0]-$x->[0] or next;
  my $avg=sub{my $i=shift; my $s=0; $s+=$_->[$i] for @$r; $s/@$r};
  my ($dp,$du)=($y->[3]-$x->[3],$y->[4]-$x->[4]);
  printf "%-8s %6d | %8.2f %8.2f %5.1f%% | %7.2fGB %7.2fGB %7.2fGB %7.2fGB | %7.3f %7.3f %7.1f\n",$arm,$dt,$dp/$dt,$du/$dt,$dp?100*$du/$dp:0,
    $avg->(5)*$gb,$avg->(6)*$gb,$avg->(7)*$gb,$avg->(8)*$gb,($y->[9]-$x->[9])/$dt,($y->[10]-$x->[10])/$dt,($y->[11]-$x->[11])/$dt; }
print "\nRead: a shorter park age should lower userwire and WS wire. Keep it if unpark/s and the unpark ratio stay low, kt/WS cores\n";
print "do not rise, and flips/s holds for the same content. Video drops are not measured here (see header).\n";
PERL
log "done"
