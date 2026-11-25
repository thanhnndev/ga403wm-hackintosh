#!/bin/bash
# ips-static-read.sh [settle=30] [seconds=90] [out]: FRAME-PATH 11.7 / WS-CPU item 3. Read-only, no root.
# Waits <settle> s (the person who started it walks away, every Claude session idle), then logs once a second for
# <seconds> s: presents, vblank IRQs, what holds the vblank (WindowServer's VBL wish, our hold, the CRTC's IRQ refcount),
# whether DC allows idle optimizations, PSR allow, and the DMUB IPS entry/exit counters. Prints a verdict at the end.
set -u
settle=${1:-30}; secs=${2:-90}; out=${3:-$HOME/ga403-logs/ips-static-$(date +%Y%m%d-%H%M%S).txt}
mkdir -p "$(dirname "$out")"
sysctl -n debug.nmx_frametrace >/dev/null 2>&1 || { echo "debug.nmx_frametrace missing"; exit 1; }
snap() {   # one line: t flips vblank_irqs rcg ips1 ips2 idle_allowed allow_active active_vblank_irq_count vbl_held vbl_wanted
    sysctl -n debug.nmx_frametrace 2>/dev/null | /usr/bin/perl -ne '
        $f=$1, $v=$2 if /^flips (\d+) vblank_irqs (\d+)/;
        if (/^ips rcg (\S+) ips1 (\S+) ips2 (\S+) idle_allowed (\d+)/) { ($r,$i1,$i2,$ia)=($1,$2,$3,$4) }
        if (/^psr .*allow_active (\d+) .*active_vblank_irq_count (\d+)/) { ($pa,$ac)=($1,$2) }
        if (/^out31 .*vbl_held (\d+) vbl_wanted (\d+)/) { ($vh,$vw)=($1,$2) }
        END { print "$f $v $r $i1 $i2 $ia $pa $ac $vh $vw\n" }'
}
echo "ips-static-read: settle ${settle}s, then ${secs}s; writing $out"
/usr/bin/perl -e "select(undef,undef,undef,$settle)"
{
echo "# $(date '+%F %T') settle ${settle}s; columns: s presents/s vblank_irqs/s ips(rcg ips1 ips2 entry/exit) idle_allowed psr_allow_active active_vblank_irq_count vbl_held vbl_wanted"
first=$(snap); prev=$first
for ((i = 1; i <= secs; i++)); do
    /usr/bin/perl -e 'select(undef,undef,undef,1)'
    cur=$(snap)
    echo "$prev $cur" | awk -v s=$i '{printf "%3d %4d %4d  %s %s %s  %s %s %s %s %s\n", s, $11-$1, $12-$2, $13, $14, $15, $16, $17, $18, $19, $20}'
    prev=$cur
done
echo "$first $prev" | awk -v n=$secs '{
    pres=$11-$1; vbl=$12-$2;
    printf "# total: %d presents in %d s, %d vblank IRQs; IPS counters %s %s %s -> %s %s %s\n", pres, n, vbl, $3, $4, $5, $13, $14, $15 }'
} | tee "$out"
/usr/bin/awk '
    /^#/ {next}
    { n++; if ($2 == 0) q++; if ($2 == 0 && $9 == 0) quietoff++; if ($7 == 1) ia++; if ($11 == 1) vw++; if ($9 == 0) vo++
      if (!s0) s0 = $4" "$5" "$6; s1 = $4" "$5" "$6 }
    END {
      printf "# seconds with 0 presents: %d of %d; with the vblank IRQ off: %d; idle allowed: %d; WindowServer wanted VBL: %d\n", q, n, vo, ia, vw
      if (q < n / 2)            print "# VERDICT: not static (presents in most seconds). Find what draws (video, wallpaper, caret, a streaming app) and rerun."
      else if (s0 != s1)        print "# VERDICT: IPS/RCG entries moved: the firmware enters idle on a static screen (FRAME-PATH 11.7 cause 1)."
      else if (vw > n / 2)      print "# VERDICT: static, but WindowServer kept VBL enabled, so our hold keeps the vblank IRQ on and DC never allows idle. Next: when Apple drivers drop VBL, and whether the hold must follow setInterruptState only."
      else if (ia > n / 2)      print "# VERDICT: static, idle allowed, IPS counters did not move: the firmware does not enter IPS or does not count it (11.7 cause 2): compare the DM IPS mode with Linux on DCN 3.5.1."
      else                      print "# VERDICT: static and VBL not wanted, but DC did not allow idle: read what else holds a vblank reference."
    }' "$out" | tee -a "$out"
