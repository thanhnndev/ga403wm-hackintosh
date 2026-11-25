#!/bin/bash
# resolve.sh <nvmtl log with "flip census" lines> [pid of the logging process, default WindowServer's]
# Maps the last flip-census window's surfaces (IOSurface ids) to the processes that hold them, with /usr/bin/IOSDebug
# (unprivileged, read-only: the IOSurfaceRoot client list per process), and sums "changed in N presents" per process.
# Run it while the surfaces are alive (within a minute of the report). A surface held by several processes is
# attributed to the first one that is not the logging process and listed as shared.
set -eu
log=$1; me=${2:-$(pgrep -x WindowServer | head -1)}
dbg=$(mktemp -t iosdebug); trap 'rm -f "$dbg"' EXIT
/usr/bin/perl -e 'alarm 20; exec @ARGV' /usr/bin/IOSDebug > "$dbg" 2>/dev/null || true
/usr/bin/perl -e '
  my ($log, $dbg, $me) = @ARGV; my (%own, @win);
  open my $d, "<", $dbg or die; my ($pn, $pid);
  while (<$d>) {
    if (/^User Client (.*) \(pid (\d+)\) Surfaces/) { ($pn, $pid) = ($1, $2); next }
    if (/^Kernel Surfaces/) { ($pn, $pid) = ("kernel", 0); next }
    if (defined $pid && /^sid: ([0-9a-f]+)/) { push @{$own{hex $1}}, "$pn($pid)" if $pid && $pid != $me }
  }
  open my $l, "<", $log or die; my @cur;
  while (<$l>) {
    if (/flip census \d+ s: (\d+) presents/) { @win = @cur if @cur; @cur = ($_); next }
    push @cur, $_ if @cur && /flip census surface /;
  }
  @win = @cur if @cur;
  die "no flip census window in $log\n" unless @win;
  print "window: ", ($win[0] =~ /(flip census .*?presents \([^)]*\): \d+ sampled a changed client surface, \d+ only[^,]*, \d+ no changed surface)/)[0], "\n";
  my (%sum, %n);
  for (@win[1..$#win]) {
    next unless /surface 0x([0-9a-f]+) (\d+x\d+) (\S+) <([^>]*)> (\w+): changed in (\d+) presents/;
    my ($sid, $dim, $cls, $name, $kind, $chg) = (hex $1, $2, $3, $4, $5, $6);
    my @o = @{$own{$sid} || []}; my $who = @o ? $o[0] : ($kind eq "own" ? "this process" : "gone/unknown");
    printf "  0x%x %-10s %-11s <%s> %s: %d presents -> %s%s\n", $sid, $dim, $cls, $name, $kind, $chg, $who, @o > 1 ? " (shared: @o[1..$#o])" : "";
    $sum{$who} += $chg; $n{$who}++;
  }
  print "per process (sum of changed-surface presents; one present can count for several surfaces):\n";
  printf "  %6d  %2d surfaces  %s\n", $sum{$_}, $n{$_}, $_ for sort { $sum{$b} <=> $sum{$a} } keys %sum;
' "$log" "$dbg" "$me"
