# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
"""Link check of a built kext against the kernel collection of this Mac (read-only).

  KC=/System/Library/KernelCollections/BootKernelExtensions.kc \\
      python3 tools/check_kext_links.py build/itlmt7925Native.kext [build/itlmt7925.kext]

Every undefined symbol of the kext's executable (`nm -um`) must be exported (N_EXT) by the kernel or by a bundle of the
collection, and that bundle must be one of the kext's OSBundleLibraries (direct) - otherwise the kext fails to link at load time
(or, with OpenCore, at kernel collection rebuild). Symbols of the kext's own dependencies that are not in the collection (here
`com.itlmt7925.kext`) are reported separately. Exit status 1 if a symbol is nowhere or comes from an undeclared bundle.

The optional second kext is a build known to load: symbols it lacks as well are expected (the SDK's IONetworkController still
declares `_RESERVED2..7` where 24H32 has outputStart & co; kxld patches those vtable entries from the parent's vtable).
"""
import os
import plistlib
import re
import struct
import subprocess
import sys

import kc

if len(sys.argv) not in (2, 3):
    sys.exit(__doc__)
kext = sys.argv[1]


def exe_of(k):
    inf = plistlib.load(open(os.path.join(k, 'Contents', 'Info.plist'), 'rb'))
    return os.path.join(k, 'Contents', 'MacOS', inf['CFBundleExecutable']), inf


def undefined_of(k):
    path, _ = exe_of(k)
    text = subprocess.run(['nm', '-um', path], capture_output=True, text=True, check=True).stdout
    return sorted({m.group(1) for m in re.finditer(r'\(undefined\) external (\S+)', text)})


exe, info = exe_of(kext)
declared = set(info.get('OSBundleLibraries', {}))

# exported symbol -> bundle id; the kernel image itself is the collection's top-level symbol table
provider = {}


def scan(symtab, owner):
    symoff, nsyms, stroff, strsize = symtab
    for i in range(nsyms):
        n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from('<IBBHQ', kc.d, symoff + i * 16)
        if (n_type & 0x0e) == 0x0e and (n_type & 0x01) and n_strx < strsize:     # defined in a section and external
            end = kc.d.index(b'\0', stroff + n_strx)
            provider.setdefault(kc.d[stroff + n_strx:end].decode('latin1'), owner)


for cmd, p, size in kc.parse_header(0):
    if cmd == 0x2:
        scan(struct.unpack_from('<IIII', kc.d, p + 8), 'kernel')
    elif cmd == 0x80000035:
        vmaddr, fileoff, strx, _ = struct.unpack_from('<QQII', kc.d, p + 8)
        name = kc.d[p + strx:kc.d.index(b'\0', p + strx)].decode()
        for c2, p2, s2 in kc.parse_header(fileoff):
            if c2 == 0x2:
                scan(struct.unpack_from('<IIII', kc.d, p2 + 8), name)

undefined = undefined_of(kext)
baseline_missing = set()
if len(sys.argv) == 3:
    baseline_missing = {s for s in undefined_of(sys.argv[2]) if s not in provider}
kernel_like = ('kernel', 'com.apple.kernel')
by_owner = {}
missing = []
for s in undefined:
    o = provider.get(s)
    if o is None:
        missing.append(s)
    else:
        by_owner.setdefault(o, []).append(s)

bad = 0
print('%s: %d undefined symbols' % (kext, len(undefined)))
for o in sorted(by_owner):
    ok = o in kernel_like or o in declared or o.startswith('com.apple.kernel')
    tag = 'ok' if ok else 'NOT IN OSBundleLibraries'
    if not ok:
        bad += 1
    print('  %-44s %4d  %s' % (o, len(by_owner[o]), tag))
own_libs = [lib for lib in declared if not lib.startswith('com.apple.')]
expected = [s for s in missing if s in baseline_missing]
missing = [s for s in missing if s not in baseline_missing]
if expected:
    print('  not exported, but also missing in %s (loads today): %d' % (sys.argv[2], len(expected)))
if missing:
    print('  not exported by the collection (%d):' % len(missing))
    for s in missing:
        print('    ' + s)
    if own_libs:
        print('  (expected from %s: not part of this collection)' % ', '.join(own_libs))
    bad += sum(1 for s in missing if not own_libs)
sys.exit(1 if bad else 0)
