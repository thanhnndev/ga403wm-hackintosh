#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
"""Step100 (irqfix): H2 fix for the live NMXGPU (sha256 1907d9f9..., the Step99 build).

Root cause of H2 ("GPU interrupts stop early in boot"):
  The IH ring has one consumer, the IOWorkLoop thread of the MSI vector (xkpi nmx_pci.cpp irq_action ->
  bus intr_trampoline -> lkpi_irq_handler -> amdgpu_irq_handler -> amdgpu_ih_process). The fence-read-flush diag
  (patches/amdgpu-fence-read-flush.patch) put a kernel printf into amdgpu_fence_read, which is inlined into
  amdgpu_fence_process (call at 0x6e88b3) and so runs on that thread for every SDMA trap / EOP IV whose fence word was
  stale in the CPU cache. On the loss boots the printf did not return: the thread is inside amdgpu_irq_dispatch
  (rptr already advanced past the IV), amdgpu_ih_set_rptr is never reached, and with IH_RB_CNTL.RPTR_REARM=1 the IH
  sends no further MSI until rptr is written. Everything after that completes only through the 0.5 s fallback.
  Why printf blocks then: boot-args has -v, so kernel printf also draws on the video console, and that console
  stalled for 1-3 s (once 13 s) during the first display commit of the NMX bridge (nmx_fb_open). An NMXAccel thread
  logging at the same instant stalled for the same time (00:13 boot: cfg+0x50 at 07.839391, cfg+0x58 at 10.522032).

This patch, on top of 1907d9f9:
  1. replaces the Step97 irqwatch cave (0x509100..0x50a630, KV dpm dead code) with cave.bin from cave.c here
     (irqwatch + stale_note + handler in-flight tracking + "cause" lines), and moves the 5 Step97 call sites to the
     new entry addresses;
  2. rewrites the 19 bytes 0x6e88a0..0x6e88b2 of amdgpu_fence_process (stale_logged++ / printf argument set-up) to
       mov %rbx,%rdi ; mov %r15d,%esi ; call stale_note ; jmp 0x6e88c4
     edx already holds the cached value. The relocated `call _printf` at 0x6e88b3 (extern reloc at 0x6e88b4) is left
     byte-for-byte as it is and is now unreachable, so no relocation entry changes.

  patch_irqfix.py NMXGPU                 patch in place (only from 1907d9f9; refuses anything else)
  patch_irqfix.py --check NMXGPU         report the state, write nothing (exit 0 = patched or patchable)
  patch_irqfix.py --undo NMXGPU          back to 1907d9f9 (byte-exact, sha checked)
  patch_irqfix.py --check-kc KC NMXGPU   the patched bytes must be in the new AuxKC exactly once
"""
import hashlib, os, struct, sys
HERE = os.path.dirname(os.path.abspath(__file__))
BASE_SHA = '1907d9f993e920b5695038bcf8b2b4cf73b04a265f825738527ab24f14955e6d'   # Step99 build (live 2026-11-04)
CAVE_AT, CAVE_END = 0x509100, 0x50a630
REGION_SHA = 'f9c8c5b9c8d40d791303c1e9bcd3151ec64e0836f3cc8a8028cfc4149291fa8e'  # Step97 cave + KV tail in 1907d9f9
# call rel32 sites that the Step97 cave owns: (site, Step97 target, entry name)
SITES = [
    (0x652f5, 0x509100, 'ih_guarded'),     # amdgpu_irq_handler -> amdgpu_ih_process
    (0x6e898c, 0x5091d0, 'fb_process'),    # amdgpu_fence_fallback -> amdgpu_fence_process
    (0x586b7, 0x509190, 'fb_arm'),         # amdgpu_fence_enable_signaling -> mod_timer
    (0x58791, 0x509190, 'fb_arm'),         # amdgpu_job_fence_enable_signaling -> mod_timer
    (0x6e8905, 0x509190, 'fb_arm'),        # amdgpu_fence_process re-arm -> mod_timer
]
STALE_AT, STALE_END, STALE_RESUME = 0x6e88a0, 0x6e88b3, 0x6e88c4
STALE_ORIG = bytes.fromhex('ffc08905c0e323004c89ef4c89e64489f931c0')   # inc eax; mov stale_logged; printf args
PRINTF_CALL = (0x6e88b3, bytes.fromhex('e800000000'))                    # extern reloc, must stay untouched


def call(at, dst):
    return b'\xe8' + struct.pack('<i', dst - (at + 5))


def load():
    cave = open(os.path.join(HERE, 'cave.bin'), 'rb').read()
    m = {}
    for l in open(os.path.join(HERE, 'cave.map')):
        a, n = l.split()
        m[n] = int(a, 16)
    if len(cave) > CAVE_END - CAVE_AT:
        sys.exit('cave too large')
    for n in ('ih_guarded', 'fb_process', 'fb_arm', 'stale_note'):
        if n not in m:
            sys.exit(f'cave.map has no {n}')
    orig = open(os.path.join(HERE, 'region-1907d9f9.bin'), 'rb').read()
    if hashlib.sha256(orig).hexdigest() != REGION_SHA:
        sys.exit('region-1907d9f9.bin is not the saved 1907d9f9 region')
    return cave, m, orig


def stale_block(m):
    b = bytes.fromhex('4889df') + bytes.fromhex('4489fe')          # mov %rbx,%rdi ; mov %r15d,%esi
    b += call(STALE_AT + len(b), m['stale_note'])
    jat = STALE_AT + len(b)
    b += bytes([0xeb, STALE_RESUME - (jat + 2)])                     # jmp 0x6e88c4 (rel8)
    b += b'\xcc' * (STALE_END - STALE_AT - len(b))
    assert len(b) == STALE_END - STALE_AT
    return b


def build(d, cave, m, orig):
    d = bytearray(d)
    d[CAVE_AT:CAVE_END] = orig                                       # deterministic: tail stays the 1907d9f9 bytes
    d[CAVE_AT:CAVE_AT + len(cave)] = cave
    for a, _, n in SITES:
        d[a:a + 5] = call(a, m[n])
    d[STALE_AT:STALE_END] = stale_block(m)
    return bytes(d)


def state(d, cave, m, orig):
    sha = hashlib.sha256(d).hexdigest()
    if sha == BASE_SHA:
        return 'base'
    ok = (d[CAVE_AT:CAVE_AT + len(cave)] == cave and d[STALE_AT:STALE_END] == stale_block(m)
          and all(d[a:a + 5] == call(a, m[n]) for a, _, n in SITES)
          and d[PRINTF_CALL[0]:PRINTF_CALL[0] + 5] == PRINTF_CALL[1])
    return 'patched' if ok else 'unknown'


def main():
    a = sys.argv[1:]
    if len(a) == 3 and a[0] == '--check-kc':
        return check_kc(a[1], a[2])
    mode = a[0] if a and a[0].startswith('--') else 'patch'
    if (mode == 'patch' and len(a) != 1) or (mode != 'patch' and len(a) != 2) or mode not in ('patch', '--check', '--undo'):
        sys.exit(__doc__)
    path = a[-1]
    cave, m, orig = load()
    d = open(path, 'rb').read()
    st = state(d, cave, m, orig)
    if mode == '--check':
        if st == 'base':
            out = build(d, cave, m, orig)
            print(f'NMXGPU is 1907d9f9 (Step99): patchable; result would be {hashlib.sha256(out).hexdigest()}')
        elif st == 'patched':
            print(f'NMXGPU already has Step100 irqfix: {hashlib.sha256(d).hexdigest()}')
        else:
            sys.exit(f'NMXGPU {hashlib.sha256(d).hexdigest()} is neither 1907d9f9 nor 1907d9f9+irqfix -- not touching it')
        return
    if mode == '--undo':
        if st == 'base':
            print('NMXGPU is already 1907d9f9'); return
        if st != 'patched':
            sys.exit('NMXGPU does not carry exactly this irqfix -- not touching it')
        u = bytearray(d)
        u[CAVE_AT:CAVE_END] = orig
        for at, t, _ in SITES:
            u[at:at + 5] = call(at, t)
        u[STALE_AT:STALE_END] = STALE_ORIG
        if hashlib.sha256(u).hexdigest() != BASE_SHA:
            sys.exit('undo did not give 1907d9f9 -- not writing')
        open(path, 'wb').write(u)
        print('NMXGPU restored to 1907d9f9'); return
    if st == 'patched':
        print('NMXGPU already has Step100 irqfix'); return
    if st != 'base':
        sys.exit(f'NMXGPU {hashlib.sha256(d).hexdigest()} is not 1907d9f9 -- not touching it')
    # belt and braces on the base: the bytes this patch replaces are what it was reviewed against
    if hashlib.sha256(d[CAVE_AT:CAVE_END]).hexdigest() != REGION_SHA or d[STALE_AT:STALE_END] != STALE_ORIG:
        sys.exit('unexpected bytes in the cave region or at 0x6e88a0')
    for at, t, n in SITES:
        if d[at:at + 5] != call(at, t):
            sys.exit(f'{n} site {at:#x} is not a call to {t:#x}')
    out = build(d, cave, m, orig)
    open(path, 'wb').write(out)
    print('NMXGPU patched (Step100 irqfix: cave + 5 sites + stale block); sha256', hashlib.sha256(out).hexdigest())


def check_kc(kc_path, gpu):
    kc = open(kc_path, 'rb').read()
    b = open(gpu, 'rb').read()
    probes = {'cave': b[CAVE_AT:CAVE_AT + 0x100], 'cave tail': b[CAVE_AT + 0x1300:CAVE_AT + 0x1400],
              'stale block': b[STALE_AT - 0x10:STALE_END]}
    for at, _, n in SITES:
        probes[f'{n} site {at:#x}'] = b[at - 0x10:at + 0x10]
    ok = True
    for k, v in probes.items():
        hit = kc.count(v) == 1
        print(f'{k}: {"present" if hit else "MISSING"} in the new collection')
        ok = ok and hit
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
