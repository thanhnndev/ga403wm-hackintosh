# Version gates: whole macOS 26 / Darwin 25.x

Rule (owner, 2026-11-08): every compatibility check covers the whole major release, never one build.
- Detect features, symbols or layouts at runtime.
- On a mismatch, turn the feature off and log. Never panic.
- Report tests as "26.x (tested on <build>)".

## Audit 2026-11-08 (running 26.7.2 / 25G332)

| Risk | Item | Status |
|---|---|---|
| High | StrixS0ix: `kPMDispatchVersion 0x66` hardcoded. `pmKextRegister` panics on a mismatch, so a 26.x that bumps it would panic every boot. | **Fixed in 0.1.15 (bd3c608).** It reads the version from the running kernel's `cmp edi, imm` and skips the hook on a mismatch. Built (A17EB334), not installed. |
| High | NMXAccel on nmx-source-port / camera-copy-890m still required the exact 25G241 kernel string. Only the side branch `nmxaccel-family-gate` had the layout gate. | **Fixed:** merged into nmx-source-port (7224025, gpu-port unchanged) and camera-copy-890m (2cf8da6, plugin/ unchanged). |
| Med-High | itlmt7925 Native Wi-Fi: IO80211 layouts generated from 25G241, checked only by static_assert. | Sent to the BT/Wi-Fi session: runtime `getClassSize()` gate, fail closed. |
| Medium | NMXAGDC subclasses AppleGraphicsDeviceControl (0x110 bytes, reconstructed vtable) with no runtime check. | Open (main): add a size/slot gate like NMXAccel. |
| Medium | NMXAccel gate checks class sizes only; reordered vtable slots would pass. | Open (main): add vtable sentinels as StrixAccel does. |
| Medium | BtLeDlFix `kAdvOriginal`: unmasked disp32. | Sent to the BT session. |
| Low | StrixAccel ABI profile and StrixHeadroom patterns pinned to one build. | Dormant on Tahoe. Convert or retire. |
| Low | 9 old install scripts check `sw_vers -buildVersion == 25G241`. | Stale. Archive them, or gate on major 26 plus feature checks. |
| Low | Native Wi-Fi recorder `kWorkQueueStatic` static address. | Diagnostics only. |

## Already whole-major

- OpenCore kernel patches: every entry covers 25.0.0-25.99.99 (thread_invoke is split at 25.4.0, and the two parts together cover all of 25.x).
- StrixSbxMap: symbol lookup plus a prologue check, disables itself on a mismatch.
- BtLeDlFix 1.3.0: masked patterns.
- NMXGPU: built from source with no address hooks. The WindowServer plugin checks for the ioctl.
- step130 installer: probes the AuxKC at runtime.
- VCNDec: versioned VT ABI and a kill switch.
- AsusWmi, AmdCppc, StrixGOP, StrixProbe, StrixMetalGate: ACPI, MSR or public KPI only.
