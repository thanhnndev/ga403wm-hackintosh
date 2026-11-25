#!/usr/bin/env python3
# Step92 helper: patch NMXGPU (as installed after Step91) for userptr, or check a relinked collection.
#   step92_patch.py NMXGPU <dir with cave.bin>     patch in place (refuses an unexpected build)
#   step92_patch.py --check-kc KC NMXGPU           the collection holds the patched bytes
import hashlib
import struct
import sys

CAVE_AT = 0x5ab300
CAVE_ORIG_SHA = '952b4c84d0afcdb82ecafaf38729c8720116568f5123cbcee3dc31066172d11e'   # 1080 bytes of dead SI dpm code
E_PRO, E_TAIL, E_RELEASE = CAVE_AT, CAVE_AT + 8, CAVE_AT + 16


def rel32(src_next, dst):
    return struct.pack('<i', dst - src_next)


def sites():
    unpop = b'\x48\x89\xdf' + b'\xe8' + rel32(0x943ec + 5, E_RELEASE) + b'\xeb' + bytes([0x94416 - 0x943f3])
    unpop += b'\xcc' * (45 - len(unpop))
    nop6 = bytes.fromhex('660f1f440000')
    return [
        # amdgpu_gem_userptr_ioctl: "mov r14,rsi; add rdi,-0x10" -> detour that also keeps filp at [rbp-0x60]
        (0x5a7c8, bytes.fromhex('4989f64883c7f0'), b'\xe9' + rel32(0x5a7cd, E_PRO) + b'\x90\x90'),
        # ... after amdgpu_ttm_tt_set_userptr: the inlined amdgpu_hmm_register stub (-ENODEV) -> the cave's tail
        (0x5a86b, bytes.fromhex('b8edffffff'), b'\xe9' + rel32(0x5a870, E_TAIL)),
        # amdgpu_cs_parser_bos: userptr entries no longer fail the submit (cold.1 = the -EPERM page fetch stub)
        (0x1390c, bytes.fromhex('0f856e050000'), nop6),
        # ... and the usermm != current->mm check (pages are pinned for the BO's life, per process)
        (0x13bb4, bytes.fromhex('0f858f000000'), nop6),
        # amdgpu_cs_submit: !get_user_pages_done() stub -> -EAGAIN for every userptr submit
        (0x14842, bytes.fromhex('0f85de000000'), nop6),
        # amdgpu_ttm_tt_unpopulate: amdgpu_ttm_tt_set_user_pages(ttm, NULL) -> put the pinned pages, then NULL
        (0x943e9, bytes.fromhex('837b1400742731c06666666666662e0f1f840000000000488b0b48c704c10000000048ffc08b4b144839c872ea'),
         unpop),
    ]


def patch(path, cavedir):
    d = bytearray(open(path, 'rb').read())
    cave = open(cavedir + '/cave.bin', 'rb').read()
    if len(cave) > 0x5abe80 - CAVE_AT:
        sys.exit('cave too large')
    ps = sites() + [(CAVE_AT, None, cave)]
    if all(bytes(d[o:o + len(n)]) == n for o, _, n in ps):
        print('NMXGPU already has Step92')
        return
    if hashlib.sha256(d[CAVE_AT:CAVE_AT + len(cave)]).hexdigest() != CAVE_ORIG_SHA:
        sys.exit('cave area is not the expected dead code -- not touching it')
    for o, old, new in ps:
        if old is not None and bytes(d[o:o + len(old)]) != old:
            sys.exit(f'bytes at {o:#x} are not the expected build -- not touching it')
    for o, _, new in ps:
        d[o:o + len(new)] = new
    open(path, 'wb').write(d)
    print('NMXGPU patched (Step92 userptr); sha256', hashlib.sha256(d).hexdigest())


def check_kc(kc_path, gpu):
    kc = open(kc_path, 'rb').read()
    b = open(gpu, 'rb').read()
    probes = {'userptr cave': b[CAVE_AT:CAVE_AT + 0x100], 'ioctl detour': b[0x5a7b0:0x5a7e0],
              'unpopulate': b[0x943d0:0x94420]}
    ok = True
    for k, v in probes.items():
        hit = kc.count(v) == 1
        print(f'{k}: {"present" if hit else "MISSING"} in the new collection')
        ok = ok and hit
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    if sys.argv[1] == '--check-kc':
        check_kc(sys.argv[2], sys.argv[3])
    else:
        patch(sys.argv[1], sys.argv[2])
