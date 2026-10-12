#!/bin/bash
# Applies the readback diagnostics / fix to a checkout of nullmoth/nvidia-macos-driver at tag v1.14.2.
#   apply.sh <checkout>                 0001 (plugin statistics) + 0002 (NVAccel counters)
#   apply.sh <checkout> --with-fix      ... + 0003 (pending-table release; apply only if the counters call for it)
#   apply.sh <checkout> --check [--with-fix]   dry run: nothing is changed
# New files come from files/ (single source of truth, also what test/readback/ compiles); the patches only modify upstream files.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
UPSTREAM_COMMIT=1083a98db33a0bb824290556de255f9a95ca5403     # tag v1.14.2 "Driver and Mac app 1.14.2"
REPO=${1:?usage: apply.sh <checkout of nullmoth/nvidia-macos-driver at v1.14.2> [--check] [--with-fix]}; shift || true
CHECK=0; FIX=0
for a in "$@"; do case $a in --check) CHECK=1;; --with-fix) FIX=1;; *) echo "unknown option $a" >&2; exit 2;; esac; done
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "STOP: $REPO is not a git checkout" >&2; exit 1; }
[ "$(git -C "$REPO" rev-parse HEAD)" = "$UPSTREAM_COMMIT" ] || { echo "STOP: $REPO is not at v1.14.2 ($UPSTREAM_COMMIT); this patch set is written against that tag" >&2; exit 1; }
[ -z "$(git -C "$REPO" status --porcelain)" ] || { echo "STOP: $REPO has uncommitted changes" >&2; exit 1; }
PATCHES=(0001-plugin-surfstat.patch 0002-nvaccel-diagnostics.patch); [ $FIX = 1 ] && PATCHES+=(0003-nvaccel-pend-release-on-free.patch)
# dry run on a throw-away index so the patches are also checked against each other
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
git -C "$REPO" worktree add -q --detach "$TMP/wt" HEAD
cp -R "$HERE/files/." "$TMP/wt/"
for p in "${PATCHES[@]}"; do git -C "$TMP/wt" apply --whitespace=nowarn "$HERE/$p" || { git -C "$REPO" worktree remove --force "$TMP/wt"; echo "STOP: $p does not apply" >&2; exit 1; }; done
git -C "$REPO" worktree remove --force "$TMP/wt"
echo "patches apply cleanly: ${PATCHES[*]}"
[ $CHECK = 1 ] && exit 0
cp -R "$HERE/files/." "$REPO/"
for p in "${PATCHES[@]}"; do git -C "$REPO" apply --whitespace=nowarn "$HERE/$p"; done
echo "applied to $REPO. New files:"; git -C "$REPO" status --short | sed 's/^/  /'
