#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step97b: NMXGPU mm fix (see cave.c). Writes cave.bin over kv_enable_didt (0x50a730..0x50a9a0, dead KV dpm code:
# called only from kv_dpm_enable/kv_dpm_disable) and patches two sites:
#   0xeb04 (15 bytes) amdgpu_bo_list_create's usermm check -> call cave entry; jmp 0xeb13; nops (no -EPERM)
#   0x6b8def (5 bytes) linux_mm_dtor's tail call to uma_zfree_arg -> ret (the mm is never freed)
# Independent of Step97 (scripts/nmx-irqwatch): different regions; either order works.
#   step97b_patch.py NMXGPU                 patch in place (refuses anything but the expected bytes)
#   step97b_patch.py --check-kc KC NMXGPU   the patched bytes must be in the new AuxKC exactly once
import hashlib, os, struct, sys
HERE = os.path.dirname(os.path.abspath(__file__))
CAVE_AT, CAVE_END = 0x50a730, 0x50a9a0
CAVE_ORIG_SHA = None   # filled below from the reviewed input
SITE1, SITE1_ORIG = 0xeb04, bytes.fromhex('e887546a004c3b70080f852c010000')
SITE2, SITE2_ORIG = 0x6b8def, bytes.fromhex('e93c160200')
CAVE_ORIG_SHA = open(os.path.join(HERE, 'kv_enable_didt.sha256')).read().split()[0]


def new_bytes():
    cave = open(os.path.join(HERE, 'cave.bin'), 'rb').read()
    m = {n: int(a, 16) for a, n in (l.split() for l in open(os.path.join(HERE, 'cave.map')))}
    if len(cave) > CAVE_END - CAVE_AT:
        sys.exit('cave too large')
    s1 = b'\xe8' + struct.pack('<i', m['entry'] - (SITE1 + 5)) + b'\xeb\x08' + b'\x90' * 8
    assert len(s1) == 15 and SITE1 + 7 + 8 == 0xeb13
    return cave, s1, b'\xc3\xcc\xcc\xcc\xcc'


def patch(path):
    d = bytearray(open(path, 'rb').read())
    cave, s1, s2 = new_bytes()
    if d[SITE1:SITE1 + 15] == s1 and d[SITE2:SITE2 + 5] == s2 and d[CAVE_AT:CAVE_AT + len(cave)] == cave:
        sys.exit('already has Step97b')
    if bytes(d[SITE1:SITE1 + 15]) != SITE1_ORIG: sys.exit('site 0xeb04 is not the expected code')
    if bytes(d[SITE2:SITE2 + 5]) != SITE2_ORIG: sys.exit('site 0x6b8def is not the expected code')
    if hashlib.sha256(d[CAVE_AT:CAVE_END]).hexdigest() != CAVE_ORIG_SHA: sys.exit('cave region is not kv_enable_didt')
    d[CAVE_AT:CAVE_AT + len(cave)] = cave
    d[SITE1:SITE1 + 15] = s1
    d[SITE2:SITE2 + 5] = s2
    open(path, 'wb').write(d)
    print('NMXGPU patched (Step97b mm fix); sha256', hashlib.sha256(d).hexdigest())


def check_kc(kc, binary):
    k = open(kc, 'rb').read(); b = open(binary, 'rb').read()
    ok = True
    for name, at, n in (('mm cave', CAVE_AT, 0x100), ('bo_list check', SITE1 - 8, 31), ('mm_dtor tail', SITE2 - 11, 21)):
        c = k.count(b[at:at + n])
        print(f'{name}: {"present" if c == 1 else f"found {c} times"} in the new collection')
        ok &= c == 1
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    if sys.argv[1] == '--check-kc':
        check_kc(sys.argv[2], sys.argv[3])
    else:
        patch(sys.argv[1])
