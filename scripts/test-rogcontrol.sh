#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Tests fan-curve decoding without opening the app or writing hardware settings.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
/usr/bin/python3 - "$TEST_DIR/main.swift" <<'PY'
from pathlib import Path
import sys
source = Path('macos/RogControl/RogControl.swift').read_text()
start = source.index('struct FanCurvePoint:')
end = source.index('struct CurveChart:', start)
Path(sys.argv[1]).write_text(source[start:end] + Path('test/rogcontrol_curve_test.swift').read_text())
PY
swiftc "$TEST_DIR/main.swift" -o "$TEST_DIR/curve-tests"
"$TEST_DIR/curve-tests"
