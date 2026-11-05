#!/bin/bash
# Root step of scripts/macos-syssleep-test.sh: run as root after the password. $1 = seconds asleep, rest = optional
# pre command (e.g. build/s0ix-set d3 3). The RTC wake is computed here, after the password, so a slow password
# no longer lands the alarm before the machine is asleep.
N=$1; shift
[[ $# -gt 0 ]] && "$@"
/usr/bin/pkill -x caffeinate
/bin/bash "$(dirname "$0")/cancel-pmset-wakes.sh"
/usr/bin/pmset -a hibernatemode 0 standby 0 powernap 0 tcpkeepalive 0 proximitywake 0 womp 0
/usr/bin/pmset schedule wake "$(/bin/date -v+$((N+3))S '+%m/%d/%y %H:%M:%S')"
/usr/bin/perl -e 'select(undef,undef,undef,3)'
/usr/bin/pmset sleepnow
