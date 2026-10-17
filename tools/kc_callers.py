#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
#
# Find direct callers (E8 rel32) of a kernel function inside the kernel collection. Companion to tools/kc.py, which has no
# working xref scanner (xrefs_to() is an empty stub). Direct calls only: virtual / vtable calls are not found by this tool.
#
# Usage:
#   KC=/System/Library/KernelCollections/BootKernelExtensions.kc python3 tools/kc_callers.py 0xffffff80023308c2
#   KC=... python3 tools/kc_callers.py 0xffffff80023308c2 --max 20
import argparse
import struct
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import kc  # noqa: E402


def callers_of(target, max_hits=50):
    out = []
    for name, vm, sz, fo, fs, pr in kc.segs:
        if not (pr & 4) and 'TEXT' not in name:
            continue
        seg = kc.d[fo:fo + fs]
        i = 0
        while len(out) < max_hits:
            i = seg.find(b'\xe8', i)
            if i < 0 or i + 5 > len(seg):
                break
            rel = struct.unpack_from('<i', seg, i + 1)[0]
            dst = (vm + i + 5 + rel) & 0xffffffffffffffff
            if dst == target:
                out.append(vm + i)
            i += 1
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('target', help='function VA, e.g. 0xffffff80023308c2')
    ap.add_argument('--max', type=int, default=50)
    ap.add_argument('--context', action='store_true', help='also print the 8 instructions before each hit')
    args = ap.parse_args()

    kc.load()
    target = int(args.target, 0)
    hits = callers_of(target, args.max)
    print('%d direct callers of %#x (%s)' % (len(hits), target, kc.symname(target) or '?'))
    for h in hits:
        fn = kc.find_func_start(h) if hasattr(kc, 'find_func_start') else None
        print('  call at %#x  in %s' % (h, kc.symname(fn) if fn else '?'))
        if args.context:
            kc.disasm(h - 0x20, h + 0x10, comment_strings=True)


if __name__ == '__main__':
    main()
