#!/bin/bash
# docker-heat-probe.sh - read-only heat/power probe for the daily load (Docker + video + Claude). No root, no writes
# outside the output directory, starts and stops nothing.
#
#   scripts/docker-heat-probe.sh [seconds=600] [interval=5] [outdir=~/ga403-logs/docker-heat-<stamp>]
#
# Every `interval` seconds: package power and Tctl (debug.amdcppc.sensors), every RyzenHV counter (rhv-info stats), wired and
# compressor pages (vm_stat). At start and end: kernel_task cumulative TIME (top), per-process CPU and idle wake-ups averaged over
# the whole run (top -l 2 -s <seconds>), RyzenHV lazy/reclaim settings. Writes samples.csv, rhv-start.txt, rhv-end.txt,
# top.txt and summary.txt.
set -u
DUR=${1:-600}; INT=${2:-5}
STAMP=$(date +%Y%m%d-%H%M%S)
OUT=${3:-$HOME/ga403-logs/docker-heat-$STAMP}
RHV=${RHV_INFO:-$HOME/develop/projects/rhv-wt-cache/build/rhv-info}
mkdir -p "$OUT" || exit 1
pause() { perl -e "select(undef,undef,undef,$1)"; }

ktime() {   # kernel_task cumulative CPU seconds; top prints MM:SS.hh or HH:MM:SS
    top -l 1 -pid 0 -stats pid,time | awk '$1=="0"{print $2}' | perl -ne 'chomp; my @p=split /:/; my $s=0; $s=$s*60+$_ for @p; print "$s\n"'
}
# counters only ("  name : integer"); the summary lines (per trap, lazy RAM...) carry text and commas
rhvline() { "$RHV" stats 2>/dev/null | awk -F: '/^  [a-zA-Z]/{gsub(/ /,"",$1); gsub(/ /,"",$2); if ($2 ~ /^[0-9]+$/) printf "%s=%s ",$1,$2}'; }
vmline()  { vm_stat | awk '/wired down/{w=$4} /occupied by compressor/{c=$5} /^Compressions/{k=$2} /^Decompressions/{d=$2} /^Swapins/{si=$2} /^Swapouts/{so=$2}
                       END{gsub(/\./,"",w); gsub(/\./,"",c); gsub(/\./,"",k); gsub(/\./,"",d); gsub(/\./,"",si); gsub(/\./,"",so);
                           printf "wired=%s cmpocc=%s compr=%s decompr=%s swapin=%s swapout=%s",w,c,k,d,si,so}'; }
sens()    { sysctl -n debug.amdcppc.sensors 2>/dev/null | perl -ne 'print "tctl=$1 " if /tctl=(\d+)/; print "pkg_mw=$1" if /pkg_mw=(\d+)/'; }

{
    echo "start $(date '+%F %T')  duration ${DUR}s  interval ${INT}s"
    sw_vers -productVersion; uname -v
    sysctl -n debug.amdcppc.report 2>/dev/null | tr '|' '\n' | head -1
    "$RHV" hv status 2>&1; "$RHV" hv reclaim 2>&1
    pgrep -lf 'hyperkit|com.docker.virtualization|com.docker.backend|qemu-system' || echo "no Docker/HyperKit/QEMU VM process"
} > "$OUT/rhv-start.txt"
"$RHV" stats > "$OUT/rhv-stats-start.txt" 2>&1
K0=$(ktime)

# Per-process CPU over the whole run, in the background (top's second sample is the average since the first).
top -l 2 -s "$DUR" -o cpu -n 25 -stats pid,command,cpu,time,idlew,power,mem > "$OUT/top.txt" 2>&1 &
TOPPID=$!

T0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
END=$(perl -e "print $T0 + $DUR")
echo "t $(sens | sed 's/=[0-9]*/ /g; s/  */ /g') $(rhvline | sed 's/=[^ ]*//g') $(vmline | sed 's/=[^ ]*//g')" | tr -s ' ' ',' > "$OUT/samples.csv"
while :; do
    NOW=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
    perl -e "exit !($NOW < $END)" || break
    echo "$NOW $(sens) $(rhvline) $(vmline)" | sed 's/[a-zA-Z_]*=//g' | tr -s ' ' ',' >> "$OUT/samples.csv"
    pause "$INT"
done
K1=$(ktime)
wait "$TOPPID"
"$RHV" stats > "$OUT/rhv-stats-end.txt" 2>&1

perl - "$OUT/samples.csv" "$K0" "$K1" > "$OUT/summary.txt" <<'PERL'
my ($f,$k0,$k1)=@ARGV; open my $h,'<',$f or die; my $hdr=<$h>; chomp $hdr; my @n=split /,/,$hdr;
my @rows; while(<$h>){chomp; my @v=split /,/; push @rows,\@v if @v==@n}
die "no samples\n" if @rows<2;
my %i; @i{@n}=0..$#n; my ($a,$b)=($rows[0],$rows[-1]); my $dt=$b->[0]-$a->[0];
my @mw=map{$_->[$i{pkg_mw}]}@rows; my @tc=map{$_->[$i{tctl}]}@rows;
my $avg=sub{my $s=0;$s+=$_ for @_; $s/@_}; my $max=sub{my $m=$_[0]; $_>$m and $m=$_ for @_; $m};
printf "samples %d over %.0f s\n", scalar @rows, $dt;
printf "package power  avg %.1f W, max %.1f W\n", $avg->(@mw)/1000, $max->(@mw)/1000;
printf "Tctl           avg %.1f C, max %.1f C\n", $avg->(@tc)/1000, $max->(@tc)/1000;
printf "kernel_task    %.3f cores (TIME %.1f -> %.1f s)\n", ($k1-$k0)/$dt, $k0, $k1;
my $d=sub{($b->[$i{$_[0]}]-$a->[$i{$_[0]}])/$dt};
printf "wired          %.2f GB at end (%.2f at start); compressor holds %.2f GB\n", $b->[$i{wired}]*4096/2**30, $a->[$i{wired}]*4096/2**30, $b->[$i{cmpocc}]*4096/2**30;
printf "compressions   %.0f pages/s, decompressions %.0f pages/s, swapouts %.0f pages/s\n", $d->('compr'), $d->('decompr'), $d->('swapout');
if (exists $i{vmExits}) {
  my $tsc=1.996e9; my $runs=$d->('vmRuns')||1; my $traps=$d->('vmTraps')||1;
  printf "RyzenHV exits/s %.0f, VMRUNs/s %.0f, traps to the client/s %.0f, NPT faults/s %.0f\n", $d->('vmExits'), $d->('vmRuns'), $d->('vmTraps'), $d->('vmNptFaults');
  printf "  in-kernel re-entries/s %.0f (exits - traps)\n", $d->('vmExits')-$d->('vmTraps');
  printf "  TLB flushes/s %.0f (%.1f %% of VMRUNs), new ASIDs/s %.0f\n", $d->('vmTlbFlushes'), 100*$d->('vmTlbFlushes')/$runs, $d->('vmAsidNew');
  printf "  cores: guest+switch %.2f, kernel pre %.3f post %.3f, front end in %.3f out %.3f\n",
     map { $d->($_)/$tsc } qw(vmCycGuest vmCycPre vmCycPost vmCycFeIn vmCycFeOut);
  printf "  lazy faults/s %.1f, re-faults/s %.1f, reclaim scans %d evicted %d, pages mapped %.2f GB\n", $d->('vmLazyFaults'), $d->('vmLazyRefaults'),
     $b->[$i{vmReclaimScans}]-$a->[$i{vmReclaimScans}], $b->[$i{vmReclaimEvicted}]-$a->[$i{vmReclaimEvicted}], $b->[$i{vmPagesMapped}]*4096/2**30;
}
PERL
{ echo; echo "top, averaged over the run:"; awk '/^PID/{n++} n==2' "$OUT/top.txt"; } >> "$OUT/summary.txt"
cat "$OUT/summary.txt"
echo "files in $OUT"
