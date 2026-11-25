#!/usr/bin/env python3
# Step95 helper: NMXGPU CS trace (see cave.c). Every call site in sites.txt is redirected to its thunk in cave.bin
# (addresses from cave.map), and linux_file_ioctl's return (0x6b5ccc, 10 bytes) jumps to the cave's ioctl hook.
#   step95_patch.py NMXGPU            patch in place (refuses an unexpected build)
#   step95_patch.py --check-kc KC NMXGPU
import hashlib, os, struct, sys
HERE = os.path.dirname(os.path.abspath(__file__))
CAVE_AT, CAVE_END = 0x5ab760, 0x5abe80
CAVE_ORIG_SHA = 'd322efee330829218014829c345985cb590174090ae674a4095307c4c578b1f7'   # 0x5ab760..0x5abe80 of the Step93 build: dead SI dpm code
HOOK = 0x6b5ccc


def rel32(src_next, dst):
    return struct.pack('<i', dst - src_next)


def load():
    cave = open(os.path.join(HERE, 'cave.bin'), 'rb').read()
    m = {}
    for l in open(os.path.join(HERE, 'cave.map')):
        a, n = l.split(); m[n] = int(a, 16)
    sites = [l.split() for l in open(os.path.join(HERE, 'sites.txt'))]
    return cave, m, sites


def plan(d):
    cave, m, sites = load()
    ps = []
    for i, (a, tgt, name) in enumerate(sites):
        a = int(a, 16)
        if d[a] != 0xe8:
            sys.exit(f'{name}: no call at {a:#x}')
        old = bytes(d[a:a + 5])
        orig_t = a + 5 + struct.unpack_from('<i', d, a + 1)[0]
        ps.append((a, old, b'\xe8' + rel32(a + 5, m[f'thunk{i}']), orig_t, name))
    ps.append((HOOK, bytes.fromhex('4189c64d89a780000000'), b'\xe9' + rel32(HOOK + 5, m['entry']) + b'\x90' * 5, None, 'ioctl'))
    return cave, ps


def patch(path):
    d = bytearray(open(path, 'rb').read())
    cave, ps = plan(d)
    if bytes(d[CAVE_AT:CAVE_AT + len(cave)]) == cave and all(bytes(d[a:a + len(n)]) == n for a, _, n, _, _ in ps):
        print('NMXGPU already has Step95'); return
    if hashlib.sha256(d[CAVE_AT:CAVE_END]).hexdigest() != CAVE_ORIG_SHA:
        sys.exit('cave area is not the expected dead code -- not touching it')
    _, m, sites = load()
    nm = {}
    for i, (a, tgt, name) in enumerate(sites):
        nm[int(a, 16)] = tgt
    for a, old, new, orig_t, name in ps:
        if orig_t is None:
            if bytes(d[a:a + len(old)]) != old: sys.exit(f'{name}: bytes at {a:#x} are not the expected build')
    if len(cave) > CAVE_END - CAVE_AT: sys.exit('cave too large')
    for a, _, new, _, _ in ps:
        d[a:a + len(new)] = new
    d[CAVE_AT:CAVE_AT + len(cave)] = cave
    open(path, 'wb').write(d)
    print(f'NMXGPU patched (Step95 CS trace, {len(ps) - 1} sites); sha256', hashlib.sha256(d).hexdigest())


def check_kc(kc_path, gpu):
    kc = open(kc_path, 'rb').read(); b = open(gpu, 'rb').read()
    probes = {'cave': b[CAVE_AT:CAVE_AT + 0x100], 'ioctl hook': b[HOOK - 0x10:HOOK + 0x10], 'parser_bos site': b[0x136a0:0x136c0],
              'userptr tail site': b[0x5ab320:0x5ab340]}
    ok = True
    for k, v in probes.items():
        hit = kc.count(v) == 1
        print(f'{k}: {"present" if hit else "MISSING"} in the new collection'); ok = ok and hit
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    if sys.argv[1] == '--check-kc': check_kc(sys.argv[2], sys.argv[3])
    else: patch(sys.argv[1])
