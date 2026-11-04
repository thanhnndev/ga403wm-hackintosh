#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# ccS.sh <probe.c>: compile an offset probe with the fork's xkpi cc.sh flags, as assembly to stdout (or $OUT).
# The cc.sh command is taken from the fork at run time (not copied here); only its "-c src -o obj" tail is swapped.
set -euo pipefail
CC=${GPU_SRC:-$HOME/develop/projects/gpu-src}/xkpi/cc.sh
sed -e 's|-c "\$src" -o \$X/obj/\$(basename "\${src%.c}").o|-S "$src" -o "${OUT:-/dev/stdout}"|' "$CC" | bash -s -- "$@"
