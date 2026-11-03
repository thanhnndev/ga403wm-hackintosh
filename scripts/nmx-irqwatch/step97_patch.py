#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Step97 helper: NMXGPU lost-interrupt watch (see cave.c). Writes cave.bin over dead KV dpm code (0x509100..0x50a630)
# and retargets five internal calls (all `call rel32`, 5 bytes, no relocations near them) to the cave:
#   0x652f5  amdgpu_irq_handler -> amdgpu_ih_process          => ih_guarded
#   0x6e898c amdgpu_fence_fallback -> amdgpu_fence_process    => fb_process
#   0x586b7  amdgpu_fence_enable_signaling -> mod_timer       => fb_arm
#   0x58791  amdgpu_job_fence_enable_signaling -> mod_timer   => fb_arm
#   0x6e8905 amdgpu_fence_process -> mod_timer                => fb_arm
#   step97_patch.py NMXGPU                 patch in place (refuses anything but the expected bytes)
#   step97_patch.py --check-kc KC NMXGPU   the patched bytes must be in the new AuxKC exactly once
import hashlib, os, struct, sys
HERE = os.path.dirname(os.path.abspath(__file__))
CAVE_AT, CAVE_END = 0x509100, 0x50a630
CAVE_ORIG_SHA = '405a5f93e72aac82be231d8556d537d09e952d1027d7f3765d91585d0c951f7a'   # kv_dpm_enable + kv_populate_*
SITES = [  # site, original callee, cave entry
    (0x652f5, 0x64cf0, 'ih_guarded'),
    (0x6e898c, 0x6e8840, 'fb_process'),
    (0x586b7, 0x6b6bb0, 'fb_arm'),
    (0x58791, 0x6b6bb0, 'fb_arm'),
    (0x6e8905, 0x6b6bb0, 'fb_arm'),
]


def call(at, dst):
    return b'\xe8' + struct.pack('<i', dst - (at + 5))


def load():
    cave = open(os.path.join(HERE, 'cave.bin'), 'rb').read()
    m = {}
    for l in open(os.path.join(HERE, 'cave.map')):
        a, n = l.split(); m[n] = int(a, 16)
    if len(cave) > CAVE_END - CAVE_AT:
        sys.exit('cave too large')
    return cave, m


def patch(path):
    d = bytearray(open(path, 'rb').read())
    cave, m = load()
    new = [(a, call(a, m[n])) for a, _, n in SITES]
    if bytes(d[CAVE_AT:CAVE_AT + len(cave)]) == cave and all(bytes(d[a:a + 5]) == b for a, b in new):
        print('NMXGPU already has Step97'); return
    if hashlib.sha256(d[CAVE_AT:CAVE_END]).hexdigest() != CAVE_ORIG_SHA:
        sys.exit('cave area is not the expected dead KV dpm code -- not touching it')
    for a, t, n in SITES:
        if bytes(d[a:a + 5]) != call(a, t):
            sys.exit(f'{n} site {a:#x}: not a call to {t:#x} -- not the expected build')
    d[CAVE_AT:CAVE_AT + len(cave)] = cave
    for a, b in new:
        d[a:a + 5] = b
    open(path, 'wb').write(d)
    print(f'NMXGPU patched (Step97 irq watch, {len(SITES)} sites); sha256', hashlib.sha256(d).hexdigest())


def check_kc(kc_path, gpu):
    kc = open(kc_path, 'rb').read(); b = open(gpu, 'rb').read()
    probes = {'cave': b[CAVE_AT:CAVE_AT + 0x100], 'cave tail': b[CAVE_AT + 0x1200:CAVE_AT + 0x1300]}
    for a, _, n in SITES:
        probes[f'{n} site {a:#x}'] = b[a - 0x10:a + 0x10]
    ok = True
    for k, v in probes.items():
        hit = kc.count(v) == 1
        print(f'{k}: {"present" if hit else "MISSING"} in the new collection'); ok = ok and hit
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == '--check-kc': check_kc(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 2: patch(sys.argv[1])
    else: sys.exit(__doc__ or 'usage: step97_patch.py NMXGPU | --check-kc KC NMXGPU')
