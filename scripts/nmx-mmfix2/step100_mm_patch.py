#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step100: NMXGPU stale xkpi record fix (see cave.c). Writes cave.bin over kv_dpm_disable (0x50a9a0..0x50abc0, dead KV
# dpm code, only reachable through kv_dpm_funcs) and patches four sites:
#   0x6d7530 (9)  nmx_thread_get key match  -> jmp t_entry; nops
#   0x6d73c0 (10) nmx_proc_for key match    -> jmp p_entry; nops
#   0x6d7551 (5)  nmx_thread_get slow path movl $0xf0,%edi -> call t_log
#   0x6d73df (5)  nmx_proc_for slow path movl $0x48,%edi   -> call p_log
# Independent of the other steps (own region and sites); Step97b's bypass and mm_dtor ret stay as a safety net.
#   step100_mm_patch.py NMXGPU                 patch in place (refuses anything but the expected bytes)
#   step100_mm_patch.py --check NMXGPU         exit 0 if already patched
#   step100_mm_patch.py --check-kc KC NMXGPU   the patched bytes must be in the new AuxKC exactly once
import hashlib, os, re, struct, sys
HERE = os.path.dirname(os.path.abspath(__file__))
CAVE_AT, CAVE_END = 0x50a9a0, 0x50abc0
REGION_SHA = 'b033d27fce70da121dd06b64d5f59f3a44ed169772280b67f8bda452fb278d5a'
CAVE_SHA = '7604d1e64b7ccaf095edaa7844aae49bb97867c3ae18822dcc5a07ff8bede614'
SITES = {  # addr: (original bytes, map entry, kind)
    0x6d7530: (bytes.fromhex('4d393e0f84b1000000'), 't_entry', 'jmp'),
    0x6d73c0: (bytes.fromhex('4c3973380f847d000000'), 'p_entry', 'jmp'),
    0x6d7551: (bytes.fromhex('bff0000000'), 't_log', 'call'),
    0x6d73df: (bytes.fromhex('bf48000000'), 'p_log', 'call'),
}


def new_bytes():
    cave = open(os.path.join(HERE, 'cave.bin'), 'rb').read()
    if hashlib.sha256(cave).hexdigest() != CAVE_SHA:
        sys.exit('cave.bin is not the reviewed build')
    if len(cave) > CAVE_END - CAVE_AT:
        sys.exit('cave too large')
    m = {n: int(a, 16) for a, n in (l.split() for l in open(os.path.join(HERE, 'cave.map')))}
    out = {}
    for at, (orig, ent, kind) in SITES.items():
        op = b'\xe9' if kind == 'jmp' else b'\xe8'
        b = op + struct.pack('<i', m[ent] - (at + 5))
        out[at] = b + (b'\x0f\x1f\x40\x00' if len(orig) == 9 else b'\x0f\x1f\x44\x00\x00' if len(orig) == 10 else b'')
        assert len(out[at]) == len(orig)
    return cave, out


def is_patched(d):
    cave, s = new_bytes()
    return d[CAVE_AT:CAVE_AT + len(cave)] == cave and all(d[a:a + len(b)] == b for a, b in s.items())


def patch(path):
    d = bytearray(open(path, 'rb').read())
    cave, s = new_bytes()
    if is_patched(d):
        sys.exit('already has Step100 mm fix')
    for at, (orig, _, _) in SITES.items():
        if bytes(d[at:at + len(orig)]) != orig:
            sys.exit(f'site {at:#x} is not the expected code')
    if hashlib.sha256(d[CAVE_AT:CAVE_END]).hexdigest() != REGION_SHA:
        sys.exit('cave region is not kv_dpm_disable')
    # the two linked calls the cave reads at run time must be where it expects them
    if d[0x6d757b:0x6d757f] != b'\x4c\x89\xff\xe8' or d[0x6d73f9:0x6d73fd] != b'\x4c\x89\xf7\xe8':
        sys.exit('thread_tid / proc_pid call sites moved')
    d[CAVE_AT:CAVE_AT + len(cave)] = cave
    for at, b in s.items():
        d[at:at + len(b)] = b
    open(path, 'wb').write(d)
    print('NMXGPU patched (Step100 stale record fix); sha256', hashlib.sha256(d).hexdigest())


def check_kc(kc, binary):
    k = open(kc, 'rb').read(); b = open(binary, 'rb').read()
    ok = True
    # windows avoid relocated bytes (the calls around the two slow-path sites are linked by kmutil)
    probes = [('record cave', CAVE_AT, 0x100), ('thread_get site', 0x6d7530 - 4, 17), ('proc_for site', 0x6d73c0 - 4, 18),
              ('thread_get log', 0x6d7551, 6), ('proc_for log', 0x6d73df, 6)]
    for name, at, n in probes:
        c = k.count(b[at:at + n])
        print(f'{name}: {"present" if c == 1 else f"found {c} times"} in the new collection')
        ok &= c == 1
    for name, pat in (('thread_tid call', rb'\x4c\x89\xff\xe8(....)\x25\xff\xff\xff\x7f\x41\x89\x46\x18'),
                      ('proc_pid call', rb'\x4c\x89\xf7\xe8(....)\x89\x03\x48\x89\xde')):
        m = list(re.finditer(pat, k, re.S))
        good = len(m) == 1 and m[0].group(1) != b'\0\0\0\0'
        print(f'{name}: {"linked" if good else f"{len(m)} matches"}')
        ok &= good
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    if sys.argv[1] == '--check-kc':
        check_kc(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == '--check':
        sys.exit(0 if is_patched(open(sys.argv[2], 'rb').read()) else 1)
    else:
        patch(sys.argv[1])
