#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step98: NMXGPU page-flip API (see cave.c). Writes cave.bin over dead KV dpm code (0x507190..0x508220) and turns
# the "not nvScanoutInfo" branch of NMXGPUFB::callPlatformFunction (0x6e3b23, je 0x6e3bf5) into je to the cave entry.
#   step98_patch.py NMXGPU                 patch in place (refuses anything but the expected bytes)
#   step98_patch.py --check-kc KC NMXGPU   the patched bytes must be in the new AuxKC exactly once
import hashlib, os, struct, sys
HERE = os.path.dirname(os.path.abspath(__file__))
CAVE_AT, CAVE_END = 0x507190, 0x508220
HOOK, HOOK_ORIG = 0x6e3b23, bytes.fromhex('0f84cc000000')
REGION_SHA = open(os.path.join(HERE, 'kv_region.sha256')).read().split()[0]


def new_bytes():
    cave = open(os.path.join(HERE, 'cave.bin'), 'rb').read()
    m = {n: int(a, 16) for a, n in (l.split() for l in open(os.path.join(HERE, 'cave.map')))}
    if len(cave) > CAVE_END - CAVE_AT:
        sys.exit('cave too large')
    return cave, b'\x0f\x84' + struct.pack('<i', m['entry'] - (HOOK + 6))


def patch(path):
    d = bytearray(open(path, 'rb').read())
    cave, hook = new_bytes()
    if d[HOOK:HOOK + 6] == hook and d[CAVE_AT:CAVE_AT + len(cave)] == cave:
        sys.exit('already has Step98')
    if bytes(d[HOOK:HOOK + 6]) != HOOK_ORIG: sys.exit('hook site 0x6e3b23 is not the expected code')
    if hashlib.sha256(d[CAVE_AT:CAVE_END]).hexdigest() != REGION_SHA: sys.exit('cave region is not the KV dpm code')
    d[CAVE_AT:CAVE_AT + len(cave)] = cave
    d[HOOK:HOOK + 6] = hook
    open(path, 'wb').write(d)
    print('NMXGPU patched (Step98 flip API); sha256', hashlib.sha256(d).hexdigest())


def check_kc(kc, binary):
    k = open(kc, 'rb').read(); b = open(binary, 'rb').read()
    ok = True
    for name, at, n in (('flip cave', CAVE_AT, 0x100), ('flip cave tail', CAVE_AT + 0xd00, 0x100), ('callPlatformFunction hook', HOOK - 10, 26)):
        c = k.count(b[at:at + n])
        print(f'{name}: {"present" if c == 1 else f"found {c} times"} in the new collection')
        ok &= c == 1
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    if sys.argv[1] == '--check-kc':
        check_kc(sys.argv[2], sys.argv[3])
    else:
        patch(sys.argv[1])
