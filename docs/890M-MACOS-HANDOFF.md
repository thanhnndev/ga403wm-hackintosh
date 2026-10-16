# Radeon 890M: macOS handoff

Branch: `research/890m-cobalt64`. Start here when continuing on macOS.
Research rationale: [port research](890M-COBALT64-PORT-RESEARCH.md).
Step-by-step history: [890M trace](890M-TRACE.md).

## Current state


NEWEST (Step19, 2026-10-16, Linux): the "iGPU panic" is not the iGPU. Both `Kernel-2026-10-16-*.panic`
reports are `assertion failed: now >= *pkt_enq_time` (`classq_fq_codel.c:1127`) reached from
`HoRNDIS::outputStart` -> `ifnet_dequeue` -> `fq_codel_dq` (USB tether + AMD TSC skew); no
StrixGOP/StrixAccel/IOAccel/AGDC/amdgpu in any panic. The ESP Kernel/Patch "Strix | fq_codel_dq" was
verified against the exact kernel (`LC_UUID 1291D44A-…B33959` = the panic's Kernel UUID, osrelease
`25.6.0`): `Find`+`Mask` matches uniquely at `0xffffff8000629d1e` (the line-1127 assert), `Replace`
`xor r9,r9; jmp 0x629caa` is safe, and the ESP OpenCore 1.0.8 supports `Mask`. So the patch is correct
and will stop the panic on the next boot; the 16:45 one predated this byte-correct version (config
rewritten after the panic). HoRNDIS needs no patch — the assert is in xnu; disabling the ESP
Kernel/Add `HoRNDIS.kext` entry removes the trigger if tethering is not needed. Full detail and the
0.1.18 boot readback: 890M-TRACE.md "Step19".

Previous (Step18, 2026-10-16, macOS): StrixAccel 0.1.18 staged in `/Library/Extensions` + on-disk AuxKC, reboot pending.
Root cause of the per-frame `Fallback GPU Display Pipe transaction submission failed` (status `0xe00002be`) was the config
value `cfg+0x08 = 0x480000` missing bit 21: `IOAccelResource2::allocMemory` then allocates resources as vidmem and
`StrixVidMemory` has no backing (length 0 -> "failed to alloc GART space ... Needed 0 bytes"). 0.1.18 sets `0x680000`
(bit 21) so resources allocate through `IOAccelSysMemory::withOptions` (UMA). Full disassembly evidence and install
hashes: 890M-TRACE.md "Step18". After the reboot verify: no `failed to alloc GART`, no `failed to allocate GPU virtual
address`, `status(+58)=0` in the `(StrixAccel)` submit lines, no `Fallback ... submission failed` in WindowServer, and
measure WindowServer CPU (`top`/`ps`; was ~124 % idle at ~50k failures per boot). If the OLED stays black, revert: restore
`~/efi-audit/strixaccel-backup/StrixAccel.kext.20261016T171014` and rebuild the AuxKC (Same flow as Step15).

Previous (Step16/17, 2026-10-16, Linux): installed on the Mac volume/ESP, not yet booted:
  * StrixAccel 0.1.17 in /Library/Extensions (AuxKC deleted, bootstrap rebuilds it). After boot: `log show --last boot | grep "(StrixAccel).*submit"` and read `status(+58)` (see Step17 in 890M-TRACE.md).
  * ESP config.plist: new Kernel/Patch "Strix | fq_codel_dq" (stops the HoRNDIS tether panic `now >= *pkt_enq_time`); BtLeDlFix 1.1.0 (Tahoe bluetoothd pattern) in ESP Kexts.
  * Branches: `tahoe/bluetooth` (BtLeDlFix source+CI), `tahoe/wifi` (25G241 IO80211 ABI dump: controller vtable identical, SkywalkInterface changed).

**NEWEST (Step15, 2026-10-16, written on Linux): macOS 26.7.1 (25G241) is installed and the OLED is dead.** Cause found in the
logs of that boot: `StrixAccel: gate FAIL: OS build does not match reviewed profile macos15-24H32...` (no OLED display pipe, so
CoreDisplay logs `Unable to find display pipe`, WindowServer restarts on virtual framebuffers). Fix: StrixAccel 0.1.16 accepts
the 25G241 profile (IOAcceleratorFamily2 487.4.4 regenerates a byte-identical declaration header). Linux already put 0.1.16 into
`/Library/Extensions` and deleted the stale AuxKC; `com.itlmt7925.graphics-bootstrap` rebuilds it with `kmutil load` at boot.
* First boot on Tahoe, please check: `ioreg -rc StrixAccelerator -l | grep StrixAccel` (Gate PASS, ABIProfile
  macos26-25G241-x86_64-ioaccel487.4.4, Pipes>=1), `/Library/Logs/StrixGraphicsFix/<newest>/`, `log show` for
  `(StrixAccel)` and CoreDisplay `display pipe` / `no gamma` lines (must stop). If the gate passes but the OLED is still black,
  the private-slot/offset assumptions of 24H32 (pipe+0x240, transaction layout) are the next suspect: re-derive on Tahoe.
* Other open Tahoe items: `bluetoothd` ExcUserFault loop (BtLeDlFix byte pattern is 24H32), `IONDRVFramebuffer` still present,
  Wi-Fi native capped by MaxKernel 24.99.99, `docs/TAHOE-MIGRATION.md` lives on `main` (this branch has not merged it).
* Do NOT re-run `nullmoth-setup.sh`/`macos-strix-accel-install.sh` casually: either rewrites `/Library/Extensions`; if you do,
  the AuxKC must be rebuilt. Details and evidence: 890M-TRACE.md "Step15".

Previous (Step13, 2026-10-15, written on Linux): performance first.** Owner direction: HDR/colour/display names are
off the table until performance is fixed. Do not touch StrixGOP HDR or EDID for now.
* Added `kexts/StrixHeadroom` (Lilu plugin, CI-built, injected from the ESP after Lilu): NOPs the mutex lock/unlock in
  `CoreDisplay::Display::CurrentHeadroom`, the 98 % hot spot of the 1150-1405 % WindowServer CPU with HDMI + OLED.
  Disassembly, byte patterns and offsets: `docs/890M-TRACE.md` "Step13". NOT yet run on hardware.
* ESP now also has: `StrixHeadroom.kext` (new), backup `EFI/OC/config.plist.pre-strixheadroom`. The 7 graphics kexts stay
  in `/Library/Extensions` + AuxKC (the ESP entries for them are disabled); do not re-enable them (BootKC cannot link
  IOGraphicsFamily/IOAcceleratorFamily2/AGDC, see Step11 boot-fix entry).
* Next on macOS, in this order:
  1. Boot with HDMI + OLED, then `bash scripts/macos-strix-0114-verify.sh` (ID-selected OLED workload). Pass = OLED
     WindowServer CPU far below the old 1100-1400 % with ~119 ticks/s. Also record `kmutil showloaded | grep -i
     strixheadroom` and Lilu's log (`log show --last boot | grep -i -E 'strixheadroom|StrixHeadroom|CoreDisplay'`) to
     confirm both patches applied (no "patch not applied"/"no match" line).
  2. If the patch did not apply (other CoreDisplay build, Lilu missing, wrong process path): the patterns are in
     `kexts/StrixHeadroom/StrixHeadroom.cpp`; re-derive them with the recipe in the Step13 entry and fix there.
  3. If CPU is still high, take `spindump WindowServer 5 10` under load: the next hot function after CurrentHeadroom is
     the next target. Remaining known cost with no HDMI is software compositing (~155 %, CompositorSW).
  4. Disable switch if it misbehaves (display artefacts, WS crash): boot-arg `-strixhroff`.
* Linux side keeps `/mnt/apv1..7` and `/mnt/cryptex` mounted read-only; the extracted CoreDisplay is in the session
  scratchpad only (re-extract with `ipsw dyld extract` from `cryptex1/current/os.dmg` -> `System/Library/dyld`).

**Owner feedback after0.1.11:** OLED HDR toggle is present, but HDR is too bright
and has incorrect colours. Capability exposure succeeded; physical HDR output
failed and remains unimplemented. StrixGOP records HDR mode selection while
retaining the boot XRGB8 scanout, with no DCN colour/HDR signalling transition.
HiDPI is now1440x900 logical /2880x1800 backing at120Hz again (read-only verified).
Mi Monitor really advertises PQ in its valid CTA EDID; its missing HDR toggle
also needs NVIDIA framebuffer/KMS mode and colour handling. Read the final
owner-feedback trace entry before any further patch/reboot. No unchanged-code
benchmark or tracing-only reboot is authorized by the current work direction.


**Latest reboot result,2026-10-15:** GOP0.1.11 is active as AMDStrixGOPFramebuffer.
CoreDisplay now receives256-byte effective/original OLED EDID and NSScreen OLED
EDR potential is4.0, previously1.0. Current EDR remains1.0; physical HDR and the
Settings toggle are not verified. HDMI EDR potential remains1.0.
Accel0.1.15 has one healthy pipe,111 copies and zero validate failures. No
benchmark was run; idle WindowServer1.1% does not prove the loaded CPU issue fixed.
Current OLED mode is2880x1800 logical at120Hz (previously1440x900 HiDPI).
Override still has its HiDPI entry; selected-mode reason/owner preference pending.
Read the final Step12 reboot entry for evidence and limits. The earlier
"reboot pending" installation state below is superseded.


**Latest Step12 follow-up: source-backed StrixGOP0.1.11 patch installed in AuxKC, reboot pending.**
Owner requested source comparison and a real patch before further reboot/testing.
Compared Cobalt64's AMDRDNA4FB and NVIDIA's NVRMNVDAFramebuffer, then confirmed
24H32 CoreDisplay vendor detection uses the framebuffer class name. Existing
StrixGOPFramebuffer is classified unknown. New AMDStrixGOPFramebuffer subclasses
it and supplies the AMD identity; all original framebuffer behaviour is inherited.
Bundle/kmod/runtime versions are0.1.11. Build and422 imports pass. Deployment
retains the installed panel personality and the256-byte EDID override repair.
Backup and exact installation evidence: `out/890m-trace/step12-source-patch/`.
No auto-tracing or benchmark job is armed. No reboot was forced. Verify the new
class/EDID and colour pipeline only after the actual patch activates; reduction
of CurrentHeadroom contention is still unverified. Read the final Step12 entry
in the trace for the source and binary evidence.


**Latest 2026-10-15 Step12: repaired deployment verified live; OLED performance
and HDR remain open.** Read the final Step12 trace before older entries below.
Owner is using HDMI + OLED. Live versions: GOP0.1.10, Accel0.1.15, Gate0.1.1;
one healthy display pipe, increasing copies and zero validation failures.

The old workload selector silently benchmarked HDMI when AppKit called the OLED
`Built-in Retina Display`. Fixed selection uses display ID/built-in identity
and refuses fallback. Correct OLED load:119.1 ticks/s but WindowServer1406% CPU;
fresh spindump confirms CurrentHeadroom mutex contention in CombineLUTs.

Installed override now uses the live256-byte CTA/PQ EDID instead of its stale
128-byte EDID; only the EDID key changed, HiDPI/name preserved, original backed
up with suffix `.pre-live-edid-20261015T062040Z`. Current WindowServer caches the
old EDID. After the next login/reboot run `scripts/macos-strix-0114-verify.sh`:
require effective EDID256 bytes, check HDR/EDR and the real OLED CPU result.
No forced logout/reboot was performed and physical HDR output is unimplemented.

Native ABI1.1 contract and admin bootstrap reads pass (512MiB, discovery2,
PSP0x80000000). Only NVIDIA currently enumerates as Metal; its explicit compute/
render control passes, not an890M pass. Continue verified IP discovery/GPUVM/GFX
bring-up; preserve the working display path and macOS build gate.

The deployment-repair entry immediately below is historical; its "runtime
verification pending" status is superseded by Step12, not a new install request.

**Latest 2026-10-15: boot failure diagnosed; deployment repair applied from Linux,
macOS runtime verification pending.** Read the final Step11 entry in
[890M-TRACE.md](890M-TRACE.md#step11-1238-boot-forensics-and-deployment-repair-applied-2026-10-15)
before following any older installation instructions below.

The 12:38 boot (`F4C323A7-3891-4EFF-B8A9-B780C9A6E71F`) crash-loops in
WindowServer `CGXMappedDisplayStart`: no usable graphics framebuffer/accelerator
was loaded. The graphics kexts injected from ESP need Apple families found only
in SystemKC; the OpenCore BootKC link was reproduced failing at vtable patching.
The raw CI StrixGOP bundle also lost its panel personality (`AdoptBootGOP=false`,
no BootGOPProfile or EDID).

Applied state, confirmed by reading the mounted Data volume and ESP:

- Current seven graphics bundles are in `/Library/Extensions`: NVRM, NVRMEdpBL,
  NVRMFB, NVRMAGDC, NVAccel, StrixAccel **0.1.15**, StrixGOP **0.1.10**.
  All executable hashes equal the ESP binaries from this session; none was
  replaced with an older executable. The corresponding seven Kernel/Add entries
  are disabled. Their ESP bundles remain as update sources.
- StrixGOP's validated panel profile/128-byte synthesized EDID were copied from
  the installed personality retained in the Linux backup. `AdoptBootGOP=true`,
  `HdrModes=true`, and `strixhdr=1` are set. The 0.1.10 executable is unchanged.
- StrixMetalGate **0.1.1** remains enabled on ESP. The stale empty AuxKC was
  preserved and removed so kernelmanagerd can build the current collection.
- A RunAtLoad bootstrap records loaded kexts, GOP/accelerator/gate registry state
  and WindowServer logs under `/Library/Logs/StrixGraphicsFix/`. If drivers are
  missing, it explicitly requests their load/rebuild and writes status to
  `/Library/StrixGraphicsFix/status`. It never reboots the machine.

**Next:** boot macOS and allow 60–90 seconds. If status is `REBOOT_REQUIRED`,
restart macOS once more. Require live versions, a usable OLED framebuffer,
stable WindowServer, and owner verification of OLED/HDR before marking success.
If the logo remains frozen, return to Linux and collect this boot's crash reports
and bootstrap directory from Data; do not diagnose it using the older boot logs.

**Scope concern:** this repairs deployment through AuxKC; it does not implement
the owner's desired ESP-only graphics loading. The owner challenged that choice
after applying the script. Preserve that concern in subsequent work; do not
claim ESP-only support or silently promote this layout as the final architecture.

The following entries describe historical states from 2026-10-13.

**Latest2026-10-13: OLED desktop works in Hybrid without HDMI, owner confirmed.**
Loaded StrixGOP0.1.3 and StrixAccel0.1.0; accelerator runtime gate PASS, one pipe.
CoreGraphics reports one active built-in display:1440x900 logical HiDPI,
2880x1800 backing pixels, nominal120Hz. This is a native display integration
milestone; StrixAccel still has no GPU command submission/GL/CL/Metal backend.
Do not change the working graphics configuration as a blind bisect.

An EDID capability bug is now fixed in source0.1.4: IODisplay asks
kConnectionSupportsHLDDCSense with NULL output; the old framebuffer rejected
that query, preventing EDID acquisition.0.1.4 preserves the exact installed
profile/EDID and is staged in AuxKC, reboot pending. Live remains0.1.3; no driver
unload or reboot performed. Working bundle backup:
`/Library/StrixGOP-backup-013-20261013-2110.kext`.
Baseline and candidate evidence:
`out/890m-trace/step04-live-baseline-20261013T141023.592596Z/`.
Next boot: verify AppleDisplay actually receives EDID, vendor/product/name,
unchanged HiDPI raster and owner-confirmed visible OLED. The EDID is still
synthesized; do not describe its colorimetry as measured panel data.

**Latest: Step03 implemented and staged for its first runtime trial.**
[StrixGOP trial](890M-GOP-TRIAL.md) contains the implementation contract, test
evidence, precise state and recovery.0.1.1 is present in AuxKC, installed at
`/Library/StrixGOPTrial/StrixGOP.kext`; kmutil returned28, reboot required.
Current session still has no StrixGOP framebuffer. Next normal Hybrid boot tests
the actual fixed-mode OLED framebuffer. Run `scripts/macos-strix-gop-collect.sh`
first, and inspect matching/controller state before changing anything.
Active EFI config unchanged; ESP off-config `config.plist.strixgop-off-20261013`
adds `-strixgopoff` to prevent attachment. This trial lives in AuxKC, not EFI.

**Latest2026-10-13: Step02 runtime census PASS on0.1.2.** One physical target,
1002:150e revc1/subsystem1043:3998; BAR config agrees with OS descriptors.
Initial FirstMatch generation3 and three admin refreshes4/5/6 have identical
PCI config/VFCT hashes. Non-admin refresh returns NotPrivileged. No reboot
needed for further probe snapshots while this version remains loaded.
Evidence: `out/890m-trace/step02-20261013T090147.620403Z/runtime-validation.json`.

Owner confirms Hybrid: HDMI has the desktop; internal OLED is still frozen on
the Apple boot logo. Owner attributes this to the NVIDIA patch; probe has not
established that cause. Initial console2880x1800 physical0x880000000 lies in
890M BAR0. Later console1920x1080 is virtual: do not compare its virtual base
to PCI physical BARs. Preserve initial evidence before refreshing.
This is a boot GOP feasibility result, **not** native OLED framebuffer support.
Next work is Step03 fixed boot framebuffer adoption design and IOFramebuffer
contract review; keep Hybrid and the existing external desktop configuration.
No GPU engine initialization, MMIO or scanout writes have been tested.

Latest deep review: [kernel call-chain trace](890M-KERNEL-TRACE.md).
Loaded0.1.1 proved the physical target exists in FirstPublish but its immediate
Matched census still missed it. Actual kernel disassembly and same-session
userspace matching confirm the state-ordering cause. Reviewed0.1.2 is now
staged on ESP, not runtime tested; config unchanged, no reboot performed.
Backup bundle: `EFI/OC/Kexts-backup/StrixProbe.kext.20261013-0855`.
It captures callback device directly, FirstMatch, and offers admin-only refresh.
Read the kernel trace before any further install/reboot or framebuffer work.

After next normal Hybrid boot:

```sh
clang -Wall -Wextra -Werror -framework IOKit -framework CoreFoundation \
  tools/strix_probe_ctl.c -o build/strix-probe-ctl
build/strix-probe-ctl --inspect
bash scripts/macos-strix-probe-collect.sh
```

Require version0.1.2, exactly one physical target, BAR descriptors and a complete
generation. Then test `--refresh` as admin via the documented administrator
wrapper workflow; non-admin call should return NotPrivileged. Collect again
without reboot, check generation increased and source identity remains correct.
Loaded0.1.1 does not support refresh; the helper checks and refuses to send it.

Latest2026-10-13: first runtime0.1.0 captured valid VFCT/VBIOS matching Linux,
but PCI snapshot was too early or otherwise unavailable. Later IORegistry
contains890M; GOP candidate matches its BAR0. Probe0.1.1 now staged with a
PCI publish notification retry; reboot pending. Run collect after reboot,
require ProbeVersion0.1.1 and PCI,MatchCount1 before framebuffer work.
Previous bundle backup: `EFI/OC/Kexts-backup/StrixProbe.kext.20261013-0836`.

Update2026-10-13: macOS link and offline defined-symbol review completed;
StrixProbe staged on ESP with `strix-probe=1`, config backup
`config.plist.pre-strixprobe-20261013-0832`. Reboot pending. Owner reports
Hybrid mode; current hiding properties preserved. See the latest Step02 trace.
After reboot run `bash scripts/macos-strix-probe-collect.sh` first.
The original build instructions and pre-staging state below remain historical.

- Step 01 **PASS** on the real Linux captures: VFCT contains the 21504-byte
  VBIOS for PCI1002:150e at65:00.0, byte-for-byte equal to the debugfs dump.
  AtomBIOS identifies the eDP path; EDID decodes 2880×1800 at60/120Hz.
- Step 02 **object compilation verified**, not yet linked or loaded on macOS.
  `StrixProbe` is a diagnostic IOResources service, enabled only by
  `strix-probe=1`; it does not bind to/open the GPU or initialize any engine.
- Current EFI still hides the iGPU. Leave that configuration intact for the
  first diagnostic census; PCI enumeration does not require graphics matching.
- No GPU register writes, kext installation, EFI changes or GPU power changes
  have been performed for this work.

Raw Linux fixtures and per-run evidence are local under ignored `out/`.
Reference repositories/SDK clones under `ref/` and `build/` are also ignored.
The committed trace includes results, hashes and pinned reference commits;
macOS does not need these Linux fixtures to build Step 02.

## Next action on macOS: build and capture evidence

In the existing repo, with local work saved first:

```sh
git fetch origin
git switch research/890m-cobalt64
git pull --ff-only origin research/890m-cobalt64
bash scripts/macos-strix-probe-build.sh
```

If this is a fresh checkout:

```sh
git clone --branch research/890m-cobalt64 https://github.com/thanhnndev/ga403wm-hackintosh.git
cd ga403wm-hackintosh
bash scripts/macos-strix-probe-build.sh
```

Needs Python3 and Xcode command line tools. The build uses the repo's normal
MacKernelSDK workflow (clones it into `build/MacKernelSDK` if absent); an existing
SDK can be selected with `MACKERNELSDK`. The probe is excluded from a default
`scripts/build.sh` build and built only when explicitly requested.

No sudo is needed. The wrapper does **not** install/load a kext, edit EFI or reboot.
It preserves a timestamped `out/890m-trace/step02-build-*/` directory containing:

- Build stdout/stderr, macOS/kernel/compiler versions and Git state.
- SDK commit, source/binary hashes, bundle plist validation and Mach-O header.
- Unresolved symbols and the exact built bundle archive.
- `manifest.json` with build/validation exit codes and explicit runtime status.

Success means `LINKED-symbol-review-pending`, **not** a hardware pass.
Return the printed status and trace directory. On failure, inspect
`build.stderr.txt` and `build.stdout.txt` there. Keep the failure trace and create
a new attempt after any fix; do not replace old evidence.

## Instructions for the agent continuing this work

1. Read this handoff, the research and trace before modifying code.
2. Review the macOS build trace. Confirm x86_64 KEXT_BUNDLE, the kmod descriptor,
   absence of `__cxa_atexit`/exception-runtime dependencies, and that unresolved
   symbols are provided by the target kernel or declared OSBundleLibraries.
   Successful linking alone does not prove symbol availability at load time.
3. Record every attempt under Step 02: environment, source/build identity,
   commands, observations, status and next gate. Distinguish offline, compile,
   link, load and hardware results. Preserve failed attempts.
4. Prepare a concrete separate test configuration only after symbol review.
   Do not run a generic install script blindly: StrixProbe is not yet listed in
   production Kernel/Add. Keep current iGPU hiding properties and production
   graphics settings unchanged for the initial diagnostic. Do not load Cobalt64.
5. Runtime trial uses `strix-probe=1`. Removing that boot argument disables the
   diagnostic service's matching. Keep a known-working config for recovery.
   This test plan is still pending; no runtime install has been validated.
6. After a successful load, capture the service with:

   ```sh
   bash scripts/macos-strix-probe-collect.sh
   ```

   It saves ioreg, a capture manifest and VFCT.bin when available. Review
   `PCI,MatchCount`/`PCI,Status`, BAR descriptors, hiding properties, console
   dimensions/base/stride and `VFCT,Status`. Require exactly one target.
   `captured-owner-unverified` means the console was read, not proved to belong
   to 890M. VFCT/PCI absent at this boot snapshot may be a publication-timing
   issue; do not infer absence of the hardware/table.
7. Parse any captured VFCT offline with `tools/890m_inspect.py --vfct PATH`.
   Do not equate a Linux firmware allocation/address with macOS ownership.
8. Only after baseline review consider framebuffer adoption or controlled
   indirect register access. IP discovery, MMIO, PSP/SMU/SDMA/GFX init, native
   DCN35/eDP, power management and Metal integration remain later milestones.

Synthetic parser tests can run without Linux fixtures:

```sh
python3 test/890m_inspect_test.py -v
```

The two local-capture checks will skip when fixtures are absent. Do not rerun
`890m_step01.py` with default Linux paths on macOS and call missing fixtures a
port failure. Existing Wi-Fi ABI research is separate under
`abi/native-wifi/24H32/round10/`; retain it while working on this branch.
