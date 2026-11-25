#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step99: NMXGPU flip API with zero-copy imports (mode 1) and DC brought up with GPU VM. On top of the Step97 build:
#   0x506580  import.bin over kv_dpm_sw_init (dead KV dpm code)           fb_create_vram, flip_import, release
#   0x507190  cave.bin over kv_dpm_sw_fini .. (dead KV dpm code)          dispatch, mode 2 chain, submit, status
#   0x6e3b23  NMXGPUFB::callPlatformFunction: je 0x6e3bf5 -> je entry     flip names reach the cave
#   0x6cd39d  nmx_fb_open: call drm_client_framebuffer_create -> call fb_create_vram   home buffer stays in VRAM
#   0x6ccfcb  nmx_fb_before_attach: movl $0, amdgpu_sg_display -> nop    DC keeps GPU VM (scan-out from GTT)
#   step99_patch.py NMXGPU                 patch in place (refuses anything but the expected bytes)
#   step99_patch.py --check-kc KC NMXGPU   the patched bytes must be in the new AuxKC exactly once
import hashlib, os, struct, sys
HERE = os.path.dirname(os.path.abspath(__file__))
CAVE_AT, CAVE_END = 0x507190, 0x508220
IMP_AT, IMP_END = 0x506580, 0x507180
HOOK, HOOK_ORIG = 0x6e3b23, bytes.fromhex('0f84cc000000')
HOME, HOME_ORIG = 0x6cd39d, bytes.fromhex('e81e3cd2ff')
SGD, SGD_ORIG, SGD_NEW = 0x6ccfcb, bytes.fromhex('c70000000000'), bytes.fromhex('660f1f440000')
CAVE_SHA = open(os.path.join(HERE, 'kv_region.sha256')).read().split()[0]
IMP_SHA = open(os.path.join(HERE, 'kv_import_region.sha256')).read().split()[0]


def amap(name):
    return {n: int(a, 16) for a, n in (l.split() for l in open(os.path.join(HERE, name)))}


def new_bytes():
    cave = open(os.path.join(HERE, 'cave.bin'), 'rb').read()
    imp = open(os.path.join(HERE, 'import.bin'), 'rb').read()
    if len(cave) > CAVE_END - CAVE_AT or len(imp) > IMP_END - IMP_AT:
        sys.exit('cave too large')
    c, i = amap('cave.map'), amap('import.map')
    hook = b'\x0f\x84' + struct.pack('<i', c['entry'] - (HOOK + 6))
    home = b'\xe8' + struct.pack('<i', i['fb_create_vram'] - (HOME + 5))
    return cave, imp, hook, home


def patch(path):
    d = bytearray(open(path, 'rb').read())
    cave, imp, hook, home = new_bytes()
    checks = ((HOOK, HOOK_ORIG, 'callPlatformFunction hook'), (HOME, HOME_ORIG, 'nmx_fb_open call'), (SGD, SGD_ORIG, 'sg_display store'))
    for at, orig, what in checks:
        if bytes(d[at:at + len(orig)]) != orig: sys.exit(f'{what} at {at:#x} is not the expected code')
    if hashlib.sha256(d[CAVE_AT:CAVE_END]).hexdigest() != CAVE_SHA: sys.exit('flip cave region is not the KV dpm code')
    if hashlib.sha256(d[IMP_AT:IMP_END]).hexdigest() != IMP_SHA: sys.exit('import cave region is not kv_dpm_sw_init')
    d[CAVE_AT:CAVE_AT + len(cave)] = cave
    d[IMP_AT:IMP_AT + len(imp)] = imp
    d[HOOK:HOOK + 6] = hook
    d[HOME:HOME + 5] = home
    d[SGD:SGD + 6] = SGD_NEW
    open(path, 'wb').write(d)
    print('NMXGPU patched (Step99 flip API + zero copy); sha256', hashlib.sha256(d).hexdigest())


def check_kc(kc, binary):
    k = open(kc, 'rb').read(); b = open(binary, 'rb').read()
    ok = True
    for name, at, n in (('flip cave', CAVE_AT, 0x100), ('flip cave tail', CAVE_AT + 0xe00, 0x100), ('import cave', IMP_AT, 0x100),
                        ('import cave tail', IMP_AT + 0x800, 0x100), ('callPlatformFunction hook', HOOK - 10, 26),
                        ('nmx_fb_open call', HOME - 10, 25), ('sg_display store', SGD - 7, 20)):
        c = k.count(b[at:at + n])
        print(f'{name}: {"present" if c == 1 else f"found {c} times"} in the new collection')
        ok &= c == 1
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    if sys.argv[1] == '--check-kc':
        check_kc(sys.argv[2], sys.argv[3])
    else:
        patch(sys.argv[1])
