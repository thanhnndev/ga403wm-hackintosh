#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
"""Offline symbol check of native-kext objects (no kernel collection needed): every undefined symbol that names an Apple
Family class (IO80211*, IOSkywalk*, CC*) must appear in the method/vtable dumps under abi/native-wifi for the build the
kext is built for. What is not in the dumps is listed so that `tools/check_kext_links.py` (needs the KC, run on the Mac) can
settle it.

  python3 tools/check_native_symbols.py build/obj/itlmt7925Native_*.o [--dumps abi/native-wifi/25G241]
"""
import glob
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAMILY = re.compile(r'^__Z[NK]*\d+(IO80211|IOSkywalk|CC)\w*')
DUMPS = sys.argv[sys.argv.index('--dumps') + 1] if '--dumps' in sys.argv else 'abi/native-wifi/25G241'
if '--dumps' in sys.argv:
    del sys.argv[sys.argv.index('--dumps'):sys.argv.index('--dumps') + 2]


def known():
    root = DUMPS if os.path.isabs(DUMPS) else os.path.join(ROOT, DUMPS)
    out = set()
    for p in glob.glob(os.path.join(root, '**/*.methods.txt'), recursive=True) + \
            glob.glob(os.path.join(root, '**/*.vtable.txt'), recursive=True):
        for line in open(p):
            f = line.rstrip('\n').split('\t')
            if f and f[-1].startswith('__Z'):
                out.add(f[-1])
    for p in glob.glob(os.path.join(root, '**/*.asm.txt'), recursive=True):
        out.update(re.findall(r'; (__Z\w+)', open(p).read()))      # call targets named in the disassembly
    return out


def main():
    k = known()
    bad = []
    nm_tool = 'llvm-nm' if subprocess.run(['which', 'llvm-nm'], capture_output=True).returncode == 0 else 'nm'
    for obj in sys.argv[1:]:
        nm = subprocess.run([nm_tool, '-u', '-j', obj], capture_output=True, text=True).stdout.split()
        for s in nm:
            if FAMILY.match(s) and s not in k:
                bad.append((obj, s))
    for obj, s in bad:
        print('not in the dumps: %s  (%s)' % (s, os.path.basename(obj)))
    print('%d family symbols outside the dumps' % len(bad))
    return 0


if __name__ == '__main__':
    sys.exit(main())
