#!/usr/bin/env python3
# Step93 helper: make NMXGPU's per-submit GFX IB prepare (b15 nmx_cs_prepare_ibs, inlined in amdgpu_cs_patch_jobs)
# opt-in, behind bit 1 of debug.nmx_wbinvd (nmx_wbinvd_before_submit). Bit 0 keeps its old meaning (whole-cache
# invalidate after the patch loop); before this patch any non-zero value did that.
#   step93_patch.py NMXGPU             patch in place (refuses an unexpected build)
#   step93_patch.py --check-kc KC NMXGPU
import hashlib
import struct
import sys

CAVE_AT = 0x5ab740                 # after the Step92 cave (0x5ab300..0x5ab738), still dead SI dpm code
CAVE_LEN = 0x20
FLAG = 0x9ba204                    # _nmx_wbinvd_before_submit (__common), sysctl debug.nmx_wbinvd
RESUME = 0x13f80                   # upstream path: ring->funcs->parse_cs / patch_cs_in_place
PREP = 0x14140                     # the b15 prepare loop (kmap + clflush + snapshot + printf per GFX IB)
SITE = 0x13f7a                     # "je PREP" after cmp ring->funcs->type, GFX
WB_TEST = 0x14357                  # "cmp dword [rax],0" on the wbinvd flag


def rel32(src_next, dst):
    return struct.pack('<i', dst - src_next)


def cave():
    c = b'\x0f\x85' + rel32(CAVE_AT + 6, RESUME)                       # not GFX: as before
    c += b'\xf6\x05' + rel32(CAVE_AT + 13, FLAG) + b'\x02'             # test byte [rip+flag], 2
    c += b'\x0f\x84' + rel32(CAVE_AT + 19, RESUME)                     # bit 1 clear: skip the prepare
    c += b'\xe9' + rel32(CAVE_AT + 24, PREP)
    return c + b'\xcc' * (CAVE_LEN - len(c))


def sites():
    return [
        (SITE, bytes.fromhex('0f84c0010000'), b'\xe9' + rel32(SITE + 5, CAVE_AT) + b'\x90'),
        (WB_TEST, bytes.fromhex('833800'), bytes.fromhex('f60001')),   # test byte [rax], 1
        (CAVE_AT, None, cave()),
    ]


ORIG_CAVE = bytes.fromhex('c1e02049f7e94901cb4889d048c1e83f48c1fa194801c2c1ee1fb93e00000090')


def patch(path):
    d = bytearray(open(path, 'rb').read())
    ps = sites()
    if all(bytes(d[o:o + len(n)]) == n for o, _, n in ps):
        print('NMXGPU already has Step93')
        return
    if bytes(d[CAVE_AT:CAVE_AT + CAVE_LEN]) != ORIG_CAVE:
        sys.exit('cave area is not the expected dead code -- not touching it')
    for o, old, _ in ps:
        if old is not None and bytes(d[o:o + len(old)]) != old:
            sys.exit(f'bytes at {o:#x} are not the expected build -- not touching it')
    for o, _, new in ps:
        d[o:o + len(new)] = new
    open(path, 'wb').write(d)
    print('NMXGPU patched (Step93 IB prepare opt-in); sha256', hashlib.sha256(d).hexdigest())


def check_kc(kc_path, gpu):
    kc = open(kc_path, 'rb').read()
    b = open(gpu, 'rb').read()
    probes = {'patch_jobs site': b[0x13f60:0x13f90], 'wbinvd test': b[0x14340:0x14360],
              'cave': b[CAVE_AT - 8:CAVE_AT + CAVE_LEN]}
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
        patch(sys.argv[1])
