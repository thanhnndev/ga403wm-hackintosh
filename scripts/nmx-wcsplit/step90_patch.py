#!/usr/bin/env python3
# Step90 patch of NMXGPU (as installed by Step89): split WC/UC multi-range mappings (cave.s).
#   step90_patch.py NMXGPU cave.bin      patch in place (no-op when already patched)
import hashlib
import sys

CAVE_AT = 0x5aac00
CAVE_END = 0x5abe80          # si_initialize_smc_cac_tables ends here
STEP89_CAVE_END = 0x5aab70   # the ibprobe v2 cave (Step89) is below CAVE_AT
SI_TAIL_SHA256 = 'cfa355433429eb6ad05e4f6f8ebe8fe5d1ab0558e4eec5cfa53e71a80d5d3132'


def jmp(frm, to):
    return b'\xe9' + (to - (frm + 5)).to_bytes(4, 'little', signed=True)


# entries of the four replaced functions -> cave entries (+0, +8, +16, +24)
ENTRIES = [
    (0x6e24f0, bytes.fromhex('554889e5'), CAVE_AT + 0),     # nmx_xnu_map_user
    (0x6e2710, bytes.fromhex('4885ff74'), CAVE_AT + 8),     # nmx_xnu_unmap_user
    (0x6e7d50, bytes.fromhex('554889e5'), CAVE_AT + 16),    # nmx_xnu_map_pages
    (0x6e7ea0, bytes.fromhex('554889e5'), CAVE_AT + 24),    # nmx_xnu_unmap
]
# relocated call sites inside the replaced bodies; each gets a ret after it (stub = "call sym; ret")
STUBS = [0x6e2550, 0x6e25d8, 0x6e25e6, 0x6e2644, 0x6e265f, 0x6e26ab, 0x6e2727, 0x6e2737, 0x6e2740]


def patch(path, cave_path):
    d = bytearray(open(path, 'rb').read())
    cave = open(cave_path, 'rb').read()
    if CAVE_AT + len(cave) > CAVE_END:
        sys.exit('cave does not fit')
    if b'NullMoth ibprobe: va=%llx' not in d:
        sys.exit(f'{path}: no Step89 ibprobe v2 -- this is not the Step89 NMXGPU')
    want = []
    for at, old, to in ENTRIES:
        want.append((at, old, jmp(at, to)))
    for s in STUBS:
        if d[s] != 0xe8 or d[s + 1:s + 5] != b'\0\0\0\0':
            sys.exit(f'{path}: {s:#x} is not an unrelocated call -- not the expected build')
        want.append((s + 5, None, b'\xc3'))
    want.append((CAVE_AT, None, cave))
    if all(bytes(d[o:o + len(n)]) == n for o, _, n in want):
        print(f'{path}: Step90 wcsplit already in')
        return
    # the cave area must still be the untouched tail of si_initialize_smc_cac_tables
    if hashlib.sha256(d[CAVE_AT:CAVE_END]).hexdigest() != SI_TAIL_SHA256:
        sys.exit(f'{path}: {CAVE_AT:#x}..{CAVE_END:#x} is not the untouched SI dpm code -- not touching it')
    for at, old, new in want:
        if old is not None and bytes(d[at:at + len(old)]) != old and bytes(d[at:at + len(new)]) != new:
            sys.exit(f'{path}: {at:#x} holds {bytes(d[at:at + 8]).hex()} -- not the expected build')
    for at, _, new in want:
        d[at:at + len(new)] = new
    open(path, 'wb').write(d)
    print(f'{path}: Step90 wcsplit patched; sha256', hashlib.sha256(d).hexdigest())


if __name__ == '__main__':
    patch(sys.argv[1], sys.argv[2])
