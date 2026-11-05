#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
"""Step112c (s0ix): NMXGPU reads the FADT again right before its system-sleep suspend.

xkpi copies the FADT once, in its nmx_acpica_init SYSINIT at NMXGPU start, from the first "ACPI Tables" registry
dictionary. StrixS0ix adds FACP to that dictionary (0.1.2) but both kexts start within ~50 ms of each other: the Step111
boot won the race, the Step112 boot lost it ("no FADT; ACPI power flags read as zero"), so amdgpu saw LOW_POWER_S0
clear, logged "BIOS has not been configured for suspend-to-idle" and skipped suspend (0 ms).

The patch: in nmx_port_power's suspend half, `mov %rdi,%rbx; mov %rax,%rdi` (0x6de446, 6 bytes) becomes
`call cave; nop`. The cave (over dead amdgpu_kv_dpm_get_enable_mask, 0x50ac10) redoes those two moves around a call
to nmx_acpica_init, which re-reads FACP (bzero + "no FADT" only when it is still missing). Both caller-live registers
(rax = the "power_suspend_early" literal, rdi) are kept; the stack stays 16-byte aligned. The Step107 s0ix bytes
(0x6de44c/0x6de45d) are not touched, so patch_s0ix.py still reports 'patched'.

  patch_fadt.py NMXGPU                 patch in place (only from the live Step100c+s0ix build 2a1bb264...)
  patch_fadt.py --check NMXGPU         report the state, write nothing
  patch_fadt.py --undo NMXGPU          back to 2a1bb264 (byte-exact, sha checked)
  patch_fadt.py --check-kc KC NMXGPU   the patched site and the cave must be in the AuxKC exactly once
"""
import hashlib, struct, sys
BASE_SHA = '2a1bb26463164e9a67675b661aa6b94728d456bc244260e708408fad5d1d1ee0'
SITE, SITE_OLD = 0x6de446, bytes.fromhex('4889fb4889c7')
CAVE, CAVE_OLD = 0x50ac10, bytes.fromhex('554889e54157415653504889f34989fe')
ACPICA_INIT = 0x6d2220
FUNC_AT, FUNC_END = 0x6de43f, 0x6de47c


def sha(b): return hashlib.sha256(b).hexdigest()


def cave_bytes():
    c = bytes.fromhex('4889fb') + b'\x50'                       # mov %rdi,%rbx; push %rax
    at = CAVE + len(c) + 5
    c += b'\xe8' + struct.pack('<i', ACPICA_INIT - at)          # call nmx_acpica_init
    c += b'\x58' + bytes.fromhex('4889c7') + b'\xc3'            # pop %rax; mov %rax,%rdi; ret
    return c.ljust(len(CAVE_OLD), b'\xcc')


def site_bytes():
    return b'\xe8' + struct.pack('<i', CAVE - (SITE + 5)) + b'\x90'


def state(d):
    s, c = d[SITE:SITE + 6], d[CAVE:CAVE + len(CAVE_OLD)]
    if s == SITE_OLD and c == CAVE_OLD: return 'base'
    if s == site_bytes() and c == cave_bytes(): return 'patched'
    return 'unknown'


def apply(d, to_patched):
    d = bytearray(d)
    d[SITE:SITE + 6] = site_bytes() if to_patched else SITE_OLD
    d[CAVE:CAVE + len(CAVE_OLD)] = cave_bytes() if to_patched else CAVE_OLD
    return bytes(d)


def main(a):
    if len(a) == 3 and a[0] == '--check-kc':
        kc, d = open(a[1], 'rb').read(), open(a[2], 'rb').read()
        if state(d) != 'patched': sys.exit('NMXGPU is not FADT-patched')
        for name, blob in (('FADT re-read site', d[FUNC_AT:FUNC_END]), ('FADT re-read cave', d[CAVE - 0x10:CAVE + 0x20])):
            n = kc.count(blob)
            if n != 1: sys.exit(f'{name} found {n} times in the collection')
        print('fadt: re-read site and cave are in the collection'); return
    mode = a[0] if a[0] in ('--check', '--undo') else None
    p = a[-1]; d = open(p, 'rb').read(); st = state(d)
    if mode == '--check':
        print(f'fadt: {st} (sha {sha(d)[:16]})'); sys.exit(0 if st in ('base', 'patched') else 1)
    if mode == '--undo':
        if st == 'base': print('fadt: already base'); return
        if st != 'patched': sys.exit('unknown state, not touching it')
        out = apply(d, False)
        if sha(out) != BASE_SHA: sys.exit('undo would not give the base build, not writing')
        open(p, 'wb').write(out); print('fadt: undone, sha', sha(out)[:16]); return
    if st == 'patched': print('fadt: already patched'); return
    if sha(d) != BASE_SHA: sys.exit(f'{p} is not the live build {BASE_SHA[:16]}, not patching')
    out = apply(d, True)
    open(p, 'wb').write(out); print('fadt: patched, sha', sha(out)[:16])


if __name__ == '__main__':
    if len(sys.argv) < 2: sys.exit(__doc__)
    main(sys.argv[1:])
