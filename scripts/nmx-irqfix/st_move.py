#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
"""Step100c: move the irqfix state words (ST[]) off the Step99 flip state.

Step100's irqfix cave keeps 23 u64 state words at 0x927010..0x9270c8 (NSTATE = 23; Step97 had 16, ending at 0x927090).
The Step99 flip/import caves keep their struct st at 0x9270a0 (common.h), lock first. ST[18] (H_MAXJ, the longest
handler run, non-zero after the first interrupt) is that lock, so the first flip spun forever in lock() inside the
display-pipe gate: WindowServer blocked behind it, userspace watchdog panic (docs/890M-TRACE.md Step100c).

This rewrites, in the installed irqfix cave only, the 69 rip-relative displacements that point into 0x927010..0x9270c8
(listed with their current targets in st_sites-d4830f51.txt) by +0x1f8, so ST[] moves to 0x927208..0x9272c0:
ci_populate_bapm_vddc_vid_sidd.__ratelimited.79 .. ci_set_mc_special_registers.__ratelimited.97 (CI dpm only, never
runs on Strix; 0x927208..0x927370 is free, the flip state ends at 0x927200). Every other byte stays the same.

  st_move.py NMXGPU            patch in place (only from d4830f51)
  st_move.py --check NMXGPU    report the state
  st_move.py --undo NMXGPU     back to d4830f51
"""
import hashlib, os, struct, sys
HERE = os.path.dirname(os.path.abspath(__file__))
BASE_SHA = 'd4830f51a1f71664a9ed8e38d33b2327b818f84f75a0d2ce6807f4b729b17848'   # Step100 as installed
LO, HI, SHIFT = 0x927010, 0x9270c8, 0x1f8
CODE_LO, CODE_HI = 0x509100, 0x50a024                                           # cave code (strings follow)
FLIP_END = 0x9270a0 + 352


def sites():
    out = []
    for l in open(os.path.join(HERE, 'st_sites-d4830f51.txt')):
        p, t = (int(x, 16) for x in l.split())
        assert CODE_LO <= p < CODE_HI and LO <= t < HI
        out.append((p, t))
    assert len(out) == 69
    return out


def disp(d, p):
    return struct.unpack('<i', d[p:p + 4])[0]


def apply(d, sign):
    d = bytearray(d)
    for p, t in sites():
        d[p:p + 4] = struct.pack('<i', disp(d, p) + sign * SHIFT)
    return bytes(d)


def main():
    a = sys.argv[1:]
    mode = a[0] if a and a[0].startswith('--') else 'patch'
    path = a[-1]
    d = open(path, 'rb').read()
    sha = hashlib.sha256(d).hexdigest()
    new = apply(d, +1) if sha == BASE_SHA else None
    if new is not None:
        assert LO + SHIFT >= FLIP_END and HI + SHIFT <= 0x927370
    patched = sha != BASE_SHA and hashlib.sha256(apply(d, -1)).hexdigest() == BASE_SHA
    if mode == '--check':
        if new is not None:
            print(f'NMXGPU is d4830f51 (Step100): patchable; result {hashlib.sha256(new).hexdigest()}')
        elif patched:
            print(f'NMXGPU already has the Step100c ST move: {sha}')
        else:
            sys.exit(f'NMXGPU {sha} is neither d4830f51 nor d4830f51+ST move')
        return
    if mode == '--undo':
        if not patched:
            sys.exit('NMXGPU does not carry the ST move -- not touching it')
        open(path, 'wb').write(apply(d, -1)); print('NMXGPU restored to d4830f51'); return
    if patched:
        print(f'NMXGPU already has the Step100c ST move: {sha}'); return
    if new is None:
        sys.exit(f'NMXGPU {sha} is not d4830f51 -- not touching it')
    for p, t in sites():   # the displacement must end its instruction or be followed by at most a 4-byte immediate
        end = t - disp(d, p)
        if not p + 4 <= end <= p + 8:
            sys.exit(f'site {p:#x}: displacement does not give {t:#x} -- not touching it')
    open(path, 'wb').write(new)
    print('NMXGPU patched (Step100c: irqfix ST 0x927010 -> 0x927208); sha256', hashlib.sha256(new).hexdigest())


if __name__ == '__main__':
    main()
