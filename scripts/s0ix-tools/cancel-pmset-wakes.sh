#!/bin/bash
# Run as root: cancel every wake that an earlier test scheduled with `pmset schedule wake` (owner 'pmset').
# A leftover alarm firing in the next test turned a dark wake into a full wake (18:54:58, 18:59:39 on 2026-11-05).
/usr/bin/pmset -g sched | /usr/bin/sed -n "s/.*wake at \([0-9/]* [0-9:]*\) by 'pmset'.*/\1/p" |
  while read -r d; do /usr/bin/pmset schedule cancel wake "$d" && echo "cancelled leftover wake $d"; done
