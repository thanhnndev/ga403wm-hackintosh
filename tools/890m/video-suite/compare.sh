#!/bin/zsh
# Per-case diff of two video-suite results directories: drops, skipped, late, interval p95, watts, CPU.
# usage: compare.sh results/A results/B
[ $# -eq 2 ] || { echo "usage: compare.sh <resultsA> <resultsB>"; exit 2; }
exec node ${0:a:h}/compare.mjs "$1" "$2"
