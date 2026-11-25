# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
"""Dump vtables, and compare overrides, of classes in BootKernelExtensions.kc (uses tools/kc.py).

  KC=/path/BootKernelExtensions.kc python3 tools/kc_vtable.py vtable IO80211SkywalkInterface
  KC=... python3 tools/kc_vtable.py compare IO80211Controller AppleBCMWLANCore     # slot-by-slot, which slots the child overrides
  KC=... python3 tools/kc_vtable.py find Skywalk                                    # symbols containing a substring (first 200)
  KC=... python3 tools/kc_vtable.py methods AppleBCMWLANCore getSCAN                # symbols of a class containing a substring

Layout is per macOS build: run it on the build you target and keep the output next to the date and Darwin version.
Only symbol names and pointer tables are read; no function body is disassembled.
"""
import os, re, struct, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kc  # noqa: E402  (reads $KC or argv[1]; see kc.py)

BASE = 0xffffff8000100000      # chained-fixup pointer: low 30 bits = offset from the KC base


def vtable(cls):
    name = '__ZTV%d%s' % (len(cls), cls)
    va = next((a for a, n in kc.syms.items() if n == name), None)
    if va is None:
        sys.exit('no vtable symbol %s (class not in this collection?)' % name)
    nxt = next(a for a in kc.sorted_addrs if a > va)
    out = []
    for i in range((nxt - va) // 8):
        v = struct.unpack_from('<Q', kc.d, kc.va2off(va) + i * 8)[0]
        t = BASE + (v & 0x3fffffff) if v else 0
        out.append(kc.syms.get(t) or ('-' if not t else '%#x' % t))
    return out


def cmd_vtable(cls):
    vt = vtable(cls)
    print('# %s: %d slots (%#x bytes)' % (cls, len(vt), len(vt) * 8))
    for i, s in enumerate(vt):
        print('%d\t%#x\t%s' % (i, i * 8, s))


def cmd_compare(base, child):
    a, b = vtable(base), vtable(child)
    print('# slot offset base-symbol -> child-symbol (only slots where they differ; base %d slots, child %d)' % (len(a), len(b)))
    for i in range(max(len(a), len(b))):
        x = a[i] if i < len(a) else '(none)'
        y = b[i] if i < len(b) else '(none)'
        if x != y:
            print('%d\t%#x\t%s -> %s' % (i, i * 8, x, y))


def cmd_find(sub):
    n = 0
    for a in kc.sorted_addrs:
        if sub in kc.syms[a]:
            print('%#x\t%s' % (a, kc.syms[a]))
            n += 1
            if n >= 200:
                print('# truncated at 200')
                break


def cmd_methods(cls, sub=''):
    tag = re.compile(r'^__ZNK?%d%s(?=\d)' % (len(cls), re.escape(cls)))
    for a in kc.sorted_addrs:
        s = kc.syms[a]
        if tag.match(s) and sub in s:
            print('%#x\t%s' % (a, s))


if __name__ == '__main__':
    args = [x for x in sys.argv[1:] if not os.path.isfile(x)]
    if not args:
        sys.exit(__doc__)
    {'vtable': cmd_vtable, 'compare': cmd_compare, 'find': cmd_find, 'methods': cmd_methods}[args[0]](*args[1:])
