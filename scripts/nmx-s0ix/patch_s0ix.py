#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause-Clear
"""Step107 (s0ix): NMXGPU suspends amdgpu through its s0ix path instead of S3 (live NMXGPU sha256 3e1b6619..., Step100c).

GA403WM is Modern Standby only: DSDT renames _S3 to XS3, macOS logs "ACPI: sleep states S4 S5", the PEP device
(AMDI000A/PNP0D80, SSDT-28) implements the Modern Standby _DSMs. The platform keeps the GPU powered through "sleep".
nmx_port_power (xkpi nmx_port.c) invokes power_suspend_early/power_suspend with POWER_STYPE_FW_SUSPEND (2), which
linux_handle_power_suspend_event maps to pm_suspend_target_state = PM_SUSPEND_MEM (3): amdgpu takes the S3 path
(full PSP/GFX/SDMA teardown, SMU PrepareMp1ForUnload, then a cold re-init over powered hardware on resume).
POWER_STYPE_SUSPEND_TO_IDLE (3) maps to PM_SUSPEND_TO_IDLE (1), so amdgpu_acpi_is_s0ix_active() is true (APU, gfxoff,
FADT LOW_POWER_S0; this build has CONFIG_AMD_PMC) and amdgpu_device_suspend takes the s0ix path (in_s0ix: PSP/GFX/
MES/SDMA kept, SMU D3Entry state change; resume without firmware reload). If the FADT bit were clear, amdgpu logs
"BIOS has not been configured for suspend-to-idle" and falls back to the S3 path, i.e. today's behaviour.

The patch: the two `mov $0x2,%esi` before the power_suspend_early / power_suspend invokes become `mov $0x3,%esi`
(one immediate byte each, no relocation nearby). Only NMXGPU's system-sleep suspend changes: display sleep no longer
suspends NMXGPU (NMXPowerKeep, Step106).

  patch_s0ix.py NMXGPU                 patch in place (only from 3e1b6619; refuses anything else)
  patch_s0ix.py --check NMXGPU         report the state, write nothing (exit 0 = patched or patchable)
  patch_s0ix.py --undo NMXGPU          back to 3e1b6619 (byte-exact, sha checked)
  patch_s0ix.py --check-kc KC NMXGPU   the patched function must be in the AuxKC exactly once
"""
import hashlib, sys
BASE_SHA = '3e1b661990d08e35ad129fceafb2c62b3d53c72eb6278abe6b8f7481f5edfbe1'   # Step100c build (live 2026-11-04)
SITES = (0x6de44c, 0x6de45d)                       # nmx_port_power: mov $stype,%esi before each invoke
OLD, NEW = bytes.fromhex('be02000000'), bytes.fromhex('be03000000')
# nmx_port_power's suspend half, 0x6de43f..0x6de47c, used to find it in the collection
FUNC_AT, FUNC_END = 0x6de43f, 0x6de47c


def sha(b): return hashlib.sha256(b).hexdigest()


def state(d):
    got = [d[a:a + 5] for a in SITES]
    if all(g == OLD for g in got): return 'base'
    if all(g == NEW for g in got): return 'patched'
    return 'unknown'


def apply(d, frm, to):
    d = bytearray(d)
    for a in SITES:
        assert d[a:a + 5] == frm
        d[a:a + 5] = to
    return bytes(d)


def main(a):
    if len(a) == 3 and a[0] == '--check-kc':
        kc, d = open(a[1], 'rb').read(), open(a[2], 'rb').read()
        if state(d) != 'patched': sys.exit('NMXGPU is not patched')
        n = kc.count(d[FUNC_AT:FUNC_END])
        if n != 1: sys.exit(f'patched nmx_port_power found {n} times in the collection')
        print('s0ix: patched nmx_port_power is in the collection'); return
    mode = a[0] if a[0] in ('--check', '--undo') else None
    p = a[-1]; d = open(p, 'rb').read(); st = state(d)
    if mode == '--check':
        print(f's0ix: {st} (sha {sha(d)[:16]})'); sys.exit(0 if st in ('base', 'patched') else 1)
    if mode == '--undo':
        if st == 'base': print('s0ix: already base'); return
        if st != 'patched': sys.exit('unknown state, not touching it')
        out = apply(d, NEW, OLD)
        if sha(out) != BASE_SHA: sys.exit('undo would not give the base build, not writing')
        open(p, 'wb').write(out); print('s0ix: undone, sha', sha(out)[:16]); return
    if st == 'patched': print('s0ix: already patched'); return
    if sha(d) != BASE_SHA: sys.exit(f'{p} is not the Step100c build {BASE_SHA[:16]}, not patching')
    out = apply(d, OLD, NEW)
    open(p, 'wb').write(out); print('s0ix: patched, sha', sha(out)[:16])


if __name__ == '__main__':
    if len(sys.argv) < 2: sys.exit(__doc__)
    main(sys.argv[1:])
