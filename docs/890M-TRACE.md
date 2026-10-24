# Radeon 890M bring-up trace

Branch: `research/890m-cobalt64`. Research: [port assessment](890M-COBALT64-PORT-RESEARCH.md).
Each step records changes, commands, evidence, status and the next gate. A compile
or synthetic test is never recorded as a hardware pass. Raw captures stay in `out/`.

## Step 01 — offline VFCT / AtomBIOS / EDID (2026-10-13)

**Status: PASS — real VFCT/VBIOS/EDID validated at 2026-10-13T07:48:40Z.**

Changes: `tools/890m_inspect.py`, `test/890m_inspect_test.py`, `tools/890m_step01.py`.
Independent bounded Python parser; does not use a GPU/device API. VFCT validates
ACPI signature/checksum/length, image bounds, PCI BDF and unique target selection;
AtomBIOS validates image checksum and all traversed table/record bounds. Supports
Atom displayobjectinfo1.4/1.5 and eDP object0x14. EDID1.4 base DTD and DisplayID2.0
type7 timings are decoded, with both outer EDID and inner DisplayID checksums.
Unsupported timing/layouts fail explicitly; unknown blocks remain marked undecoded.
IP discovery is not required to parse AtomBIOS and is not claimed acquired.

Reference layouts: Linux commit `24a19b953e2a3d0ea5a8c4951a0ab8f32720c907`,
`drivers/gpu/drm/amd/include/{atombios.h,atomfirmware.h}`,
`drivers/gpu/drm/{drm_edid.c,drm_displayid_internal.h}`; RDNA4FB commit
`5ff69aade9a7feb18bb665040661de33ccfe68ba`, `src/atombios.cpp`.

Commands run:

```sh
python3 test/890m_inspect_test.py -v
python3 tools/890m_inspect.py --vbios out/890m/vbios.bin --edid out/890m-user/card2-eDP-2.edid
python3 tools/890m_step01.py
sudo -n python3 tools/890m_step01.py
```

Results: 14 tests PASS, including real VBIOS/panel captures, all fixture truncations,
600 seeded random inputs, invalid pointers/checksums/counts, duplicate PCI identity,
and VFCT image overflow. Real VBIOS: 21504 bytes, 5 paths, first path decoded eDP.
Real panel: ATNA40CU05-0; htotal2980, vtotal3648 at60Hz and1824 at120Hz;
clocks652270/652264kHz. Both timings match edid-decode.

Evidence: `out/890m-step01.json` and
`out/890m-trace/step01-20261013T074329.853808Z/` (source/input hashes,
command argv, exit codes, stdout/stderr, report and explicit partial status).
Noninteractive sudo failed with `a password is required`; no real VFCT parse
has been counted as passing. No binaries extracted or fixtures overwritten.

Completion evidence: user root run
`out/890m-trace/step01-20261013T074840.210619Z/manifest.json` reports PASS;
`report.json` has `vfct.matches_vbios=true`. Selected image BDF65:00.0,
vendor/device1002:150e, offset104, length21504; byte-for-byte equal to debugfs VBIOS.
Input hashes:

- VFCT: `ef51fc491ad64e2825d0808af279cac2fe10a7eea95527864457b2a6ee2f08f2`
- VBIOS: `7375149330e753a4f5903cb9087a79fdab008d02856ca72366a40e6dcfde1777`
- EDID: `c018efb7498d1f643af2f0eaea4113806de42635c899da98c655793561af1749`

VFCT SSVID/SSID fields are zero, so subsystem matching must not assume1043:3998
is recorded in this table. The final zero-length VFCT entry is not a second GPU.
Manifest source hashes still match the parser/runner/tests inspected after this run.
**Next gate:** Step02 macOS link and symbol/dependency review. Each runner attempt
creates a new trace directory; earlier partial results remain preserved.

## Step 02 — StrixProbe baseline census (2026-10-13)

**Status: COMPILE VERIFIED — not linked/loaded/runtime tested.**

Changes: `kexts/StrixProbe/`, explicit-only `scripts/build.sh StrixProbe` target,
and `scripts/macos-strix-probe-collect.sh`. Opt-in boot argument `strix-probe=1`.
IOResources diagnostic service enumerates PCI1002:150e without opening the GPU;
records config256/BAR descriptors, existing hiding properties, console GOP metadata,
and VFCT via IOACPIPlatformDevice table getter if published. No MMIO maps, indirect
MM_INDEX writes, mailbox calls, AML evaluation, bus-master/power changes or GPU init.
Does not claim ownership of the console surface. IP discovery explicitly unacquired.

SDK: MacKernelSDK `3f750085caa17ec3a7880f11c11bf4f48cd6a164`.
C++ and C compiled with clang targeting x86_64-apple-macos12, -mkernel,
-fno-builtin, -nostdinc, -ffreestanding, kernel defines, MacKernelSDK headers,
-Wall -Wextra -Werror; C++ additionally -std=c++17 -fapple-kext -fno-exceptions
-fno-rtti -fno-c++-static-destructors. Output objects are Mach-O x86_64.
Info.plist parsed successfully. Shell syntax checked.
Evidence: `out/890m-trace/step02-compile-20261013/manifest.json`.

Source inspection corrected kernel getMatchingServices dictionary ownership:
kernel IOService borrows it, so caller releases it (unlike user-space API).
Verified against Apple xnu `iokit/Kernel/IOService.cpp`, getMatchingServices.

**Next gate:** Step01 is now complete. On macOS run
`bash scripts/macos-strix-probe-build.sh` to link the explicit-only target,
archive its exact bundle and capture build logs, SDK commit, source/binary hashes,
Mach-O header and unresolved symbols. The script rejects C++ runtime destructor/
exception symbols and requires KEXT_BUNDLE; success is LINKED-symbol-review-pending,
not a runtime pass. Validate dependencies on the actual macOS build,
and test a separate opt-in configuration. No EFI changes or install performed.
Initial PCI census can keep existing GPU hiding properties. Unhiding is a later
framebuffer/driver matching experiment, not a prerequisite for this diagnostic.
After loading, `scripts/macos-strix-probe-collect.sh` preserves ioreg plus manifest
and VFCT.bin when available. Boot-time snapshot may find no device/table yet;
that result is a failed acquisition, not proof that hardware or VFCT is absent.

### Step02 build preparation follow-up (2026-10-13)

Added `scripts/macos-strix-probe-build.sh`; per-probe compilation now disables
C++ static destructors, preventing __cxa_atexit imports. The default build still
excludes the research probe. Linux checks: shell syntax PASS; all14 parser tests
PASS; C++/C object compilation previously PASS. macOS link/load and VFCT getter
availability remain unverified. Build script deliberately does not install or
modify EFI. Review the returned trace before deciding the runtime trial.

### Step02 macOS link and ESP staging (2026-10-13)

Host: macOS15.8.1, 24H32, x86_64; owner reports Hybrid mode.
First attempt `out/890m-trace/step02-build-20261013T082821.661548Z/`
linked but validation falsely rejected Apple's `KEXTBUNDLE` spelling.
Preserved that trace; accept both header spellings and explicitly cast BAR
register offsets to UInt8 to remove the compiler warning.

Second attempt `out/890m-trace/step02-build-20261013T082905.536427Z/`:
LINKED-symbol-review-pending, plist valid, x86_64 KEXTBUNDLE, `_kmod_info`
present, no forbidden destructor/exception imports. All306 imports occur in
BootKernelExtensions.kc **defined external** symbols (`nm -gUj`), zero missing.
This is an offline symbol check, not load-time dependency validation.
`kextutil -n -t` redirects to kmutil and rejects -n; `kextlibs` cannot find
standalone libraries on this installation. Neither is counted as a pass.
Parser suite:12 PASS,2 local Linux capture tests skipped.

Separate local config passed OpenCore1.0.9 ocvalidate. Installed exact probe
bundle to the mounted ESP through an administrator wrapper, then applied that
config: one Kernel/Add entry and `strix-probe=1`; DeviceProperties preserved.
Backup: `/Volumes/ESP/EFI/OC/config.plist.pre-strixprobe-20261013-0832`.
Binary hash and staged/live config equality verified after installation.
Local test config contains private machine settings and remains ignored under out/.

**Status: STAGED — reboot pending, no runtime/hardware pass.**
Next: reboot macOS in Hybrid, run `bash scripts/macos-strix-probe-collect.sh`,
review unique PCI target, console ownership candidates and VFCT offline.
Recovery: restore the named config backup; removing `strix-probe=1` disables
service matching. No Cobalt64 load, GPU MMIO or power changes performed.

### Step02 first macOS runtime and notification retry (2026-10-13)

Capture: `out/890m-trace/step02-20261013T083428.872962Z/`.
Probe0.1.0 loaded and published its service. VFCT21636 bytes and selected
VBIOS21504 bytes parse successfully, hashes exactly match Step01 Linux inputs.
Five Atom display paths include eDP. PCI snapshot reports zero targets; this
is an acquisition failure, not hardware absence. A later user-space PCI census
finds one registry entry with vendor1002/device150e and hiding properties intact.
Publication timing is suspected; physical config identity remains unverified.

Console2880x1800, depth32, rowBytes11520, raw base0x880000001, aligned candidate
0x880000000; PE length0. Registry assigned-addresses decode as BAR0 base
0x880000000/length0x10000000, BAR2 base0x890800000/length0x200000,
I/O BAR4 base0xe000/length0x100, BAR5 base0xdc300000/length0x80000.
Console candidate matches the iGPU BAR0 and its20736000-byte raster fits.
This is evidence for GOP feasibility, not proof of surface ownership/pixel
format, cache policy, safe writes or framebuffer adoption.

Probe0.1.1 adds persistent gIOFirstPublishNotification for PCI, recapturing on
physical1002:150e publication; initial snapshot retained as fallback. Notifier
is removed synchronously in stop. API checked against Apple kernel docs and
the pinned SDK. No provider open or GPU writes added.
Build trace: `out/890m-trace/step02-build-20261013T083535.102099Z/`;
307 imports, zero missing from Boot KC defined external symbols; link PASS.
Parser tests12 PASS/2 skipped. Updated bundle staged on ESP; previous bundle
at `EFI/OC/Kexts-backup/StrixProbe.kext.20261013-0836`; config unchanged.
**Next gate: reboot and capture0.1.1; require one physical PCI target.**
No runtime success claimed for0.1.1, no GPU initialization or framebuffer writes.

### Step02 second runtime and deep kernel review (2026-10-13)

Runtime0.1.1 capture `out/890m-trace/step02-20261013T083948.414944Z/`:
notification installed, target-publish-notification observed, PCI count still0.
VFCT valid, same hashes; GOP unchanged. This proves the callback config identity
test passed, while its nested Matched census omitted the callback target.
XNU source and actual kernel disassembly establish FirstPublish/Matched ordering;
later same-session userspace API matching finds exactly one registry target.

Owner requested deeper review before more reboots. Followed relevant SDK/XNU/PCI
call chains, lifetime, locking, privilege dispatch, descriptors and console flags.
Full findings, pinned references and limitations: [kernel trace](890M-KERNEL-TRACE.md).
No claim of manually reading every unrelated SDK header.

Final0.1.2 build `out/890m-trace/step02-build-20261013T085331.994874Z/`:
263 compiler dependency hashes; Wall/Wextra/Werror compilation; valid x86_64
KEXTBUNDLE/kmod descriptor;316 imports, zero missing among Boot KC definitions.
Direct callback census plus FirstMatch, serialized generations, admin-only
refresh, explicit physical console flags, and resource getter side-effect avoidance.
Collector now retains live PCI and OS/kernel evidence. Helper inspect works on
loaded0.1.1; refresh refuses unsupported endpoint without sending a request.
Parser12 PASS/2 fixture skips, helper strict compile, shell syntax/diff checks PASS.

Reviewed0.1.2 staged through an administrator wrapper; backup previous bundle
`EFI/OC/Kexts-backup/StrixProbe.kext.20261013-0855`; config unchanged.
**Status: reboot pending;0.1.2 runtime/refresh authorization unverified.**
No hot-unload, GPU republish, device power/link calls, MMIO, modesetting or
framebuffer writes attempted. Next trial includes initial capture and repeated
admin refresh in one session instead of rebooting for each diagnostic snapshot.

### Step02 runtime validation completed (2026-10-13)

**PASS: diagnostic census, not framebuffer/acceleration.** Probe0.1.2 captures
one physical1002:150e revc1, subsystem1043:3998 at FirstMatch, ServiceState0x1e.
BAR0/2/5 config decoding agrees with descriptors:0x880000000/256MiB,
0x890800000/2MiB,0xdc300000/512KiB. BAR4 is I/O0xe000/256B.
PCIConfig256 and VFCT identities validated offline.

Trace `out/890m-trace/step02-20261013T090147.620403Z/`: initial generation3,
non-admin refresh returns0xe00002c1 (NotPrivileged); administrator wrapper
performs three refreshes successfully, generations4/5/6. PCI config and VFCT
hashes identical across all four snapshots. VFCT parser PASS with Linux hashes.
`runtime-validation.json` records assertions/results. Final independent capture:
`out/890m-trace/step02-20261013T090433.432071Z/`.

Initial console: physical flag set,2880x1800/stride11520/depth32/scale2,
rotation0, offset0, physical base0x880000000, raster20736000 bytes within BAR0.
After desktop comes up, refresh reports1920x1080/stride7680/depth32/scale0,
physical flag clear and virtual base. Do not treat a virtual base as a physical
ownership failure. The first validation attempt incorrectly required every
console snapshot to remain physical and stopped on an assertion; corrected
review separates boot GOP from live console and retains all raw snapshots.

Owner observation: machine in Hybrid; HDMI runs the desktop; internal OLED
still frozen at Apple logo. Owner reports NVIDIA patch failure, but the probe
does not identify its root cause. Do not claim laptop display is working or
that console metadata alone proves native890M scanout ownership.

**Next gate:** Step03 fixed boot framebuffer adoption feasibility and complete
IOFramebuffer API/lifetime review. Preserve boot evidence, maintain current
Hybrid/external desktop, use refresh for further census instead of rebooting.
No firmware init, GPU MMIO, display register or framebuffer writes performed.

## Step03 — fixed boot GOP framebuffer implementation (2026-10-13)

Implemented `StrixGOPFramebuffer`, explicit-only build, checked geometry contract,
snapshot-derived profile runner, collector and tests. Full contract/runtime state:
[GOP trial](890M-GOP-TRIAL.md). Cobalt64 init ladder remains separate.

Real boot snapshot accepted; live virtual HDMI snapshot rejected.13 geometry
boundary cases pass ASan/UBSan;6 profile tests pass (including malformed PCI/BAR,
incomplete/ambiguous snapshot, bounds and real fixtures). Strict kernel build,
x86_64 KEXTBUNDLE/kmod/plist checks pass. Final370 imports resolve through
kmutil to declared KPI/IOPCI/IOGraphics providers, not merely a flat symbol list.

First0.1.0 build trace `out/890m-trace/step03-build-20261013T091355.770833Z/`.
Runtime load attempt normal exit27, no-authorization exit28 (requires reboot).
Added opt-out before attachment and rebuilt0.1.1; final trace
`out/890m-trace/step03-build-20261013T091914.471933Z/`. Installed hash verified;
AuxKC inspection confirms0.1.1. No native framebuffer service currently loaded.
Off-config saved on ESP and validated; active config unchanged. Previous trial
package retained at `/Library/StrixGOPTrial-pre-011-20261013` for evidence.

Pre-reboot collector first failed on ioreg's empty output for a missing class;
preserved that attempt, fixed empty handling. Re-run correctly records
ACQUISITION-FAILED-no-unique-framebuffer at
`out/890m-trace/step03-runtime-20261013T092321.661092Z/`.

**Status: IMPLEMENTED/BUILT/STAGED — actual framebuffer runtime pending.**
Next reboot is the fixed-mode OLED trial. It permits IOGraphics/WindowServer
writes to the bounded boot raster; it is not a read-only probe. No hardware
modeset, MMIO, GPU allocator or engine initialization implemented. Require live
service/controller checks and owner verification of visible OLED/colors/cursor.

### Step03 live diagnosis on 0.1.1 and 0.1.2 rebuild (2026-10-13)

0.1.1 attached and published `StrixGOPFramebuffer` (OpenGLIndex 1,
`Controller,Enabled=Yes`, raster 20738048 B at BAR0 `0x880000000`) alongside
`NVRMFramebuffer` (OpenGLIndex 0). CoreGraphics lists two active online
displays: HDMI 1920x1080@60 main plus OLED 2880x1800 built-in at origin
1920,0. Per-display `screencapture -D1/-D2` both succeed and the OLED shadow
shows the desktop wallpaper plus menu bar, so WindowServer composition to the
Strix framebuffer works. The physical OLED stays frozen on the Apple boot
logo: scanout presentation, not matching/composition, is the broken path.

Root cause in the 0.1.1 contract: `getInformationForDisplayMode` reported
refresh 0 (`IOFB0Hz=Yes`, CG 0.0 Hz) with no timing info, and the single mode
lacked `HiResFlag`. WindowServer/CoreDisplay floods
`Unable to find display pipe for IOFB service 0x100000f3b` (~48k lines in
5 min); the single `IOAccelDisplayMachine/Pipe` belongs to NVAccel, and with
no usable timing CoreDisplay never schedules presentation to the Strix
aperture. EFI `disable-gpu`/class-code spoof remains live on `VGA@0` but does
not block Strix (probe reads real PCI config `1002:150e` rev `c1`); NVIDIA
hooks (`-nvrmnobootscreen`, 4 heads, `NVRMEdpBL`) explain the frozen logo
retention, not the missing pipe. Evidence (screenshots, census, pipe-error
sample): `out/890m-trace/step03-runtime-20261013T094047.427864Z/`.

0.1.2 (this change, no MMIO/modeset/allocator): two modes sharing the boot
raster — mode 1 at 60 Hz (base DTD 652.270 MHz, 2980x3648), mode 2 at
120 Hz (DisplayID 652.264 MHz, 2980x1824, the boot scanout, default) — with
`refreshRate`, `FixedRateLCD` detailed timing and `HiResFlag` so WindowServer
can build both a usable pipe schedule and real 1440x900 HiDPI on the native
2880x1800 backing. `setDisplayMode` accepts either with no hardware change.
Build trace `out/890m-trace/step03-build-20261013T101935.211038Z/`:
PROFILED-LINKED, 369 imports, zero missing, clean `-Wall -Wextra -Werror`.

**Status: STAGED — install plus reboot pending, no 0.1.2 runtime pass.**
Next: back up `/Library/StrixGOPTrial`, install the 0.1.2 bundle, rebuild
AuxKC, reboot Hybrid, then `bash scripts/macos-strix-gop-collect.sh` and
require pipe-error silence, CG 60/120 Hz (not 0 Hz), HiDPI 1440x900 offered,
and owner confirmation of live OLED updates. Recovery via `-strixgopoff`
off-config on ESP.

### Step03 0.1.2 runtime findings and 0.1.3 (2026-10-13)

0.1.2 runtime (after reboot): AuxKC contained `com.itlmt7925.strixgop` 0.1.2 but
no instance existed and no `StrixGOP` log line appeared. kernelmanagerd logged
"Validate approval" only for `/Library/Extensions` kexts and "unstaged bundle path"
for `/Library/StrixGOPTrial`; KextPolicy already had `allowed=1`, so the bundle
location, not approval, is the suspect. Forced `kmutil load -b` attached the kext
(fb0 registered with GPUWrangler, Controller,Enabled, pixel clock 652264000, 120/60
Hz + HiDPI modes visible) but the OLED stayed on the boot logo and CoreGraphics
reported the panel as vendor `0x756e6b6e` ("unkn"): no EDID, so unknown color
profile. IOFramebuffer power state read 0/flags 0.

0.1.3 (no MMIO/modeset): EDID over `hasDDCConnect`/`getDDCBlock` +
`kConnectionSupportsHLDDCSense` (validated header/checksum, from `PanelEDID` in the
personality); explicit acks for power/capture/connection attributes with a bounded
log of every attribute IOGraphics sends; read-only 32x32 sparse sampler of the
boot raster published as `Sample,*` properties (hash, non-black count, changed since
enable) to show whether WindowServer writes the scanned aperture. Runner gains
`--edid <file>` (real, preferred) and `--synthesize-edid` (identity 0x4c83/0x419c
+ Step01 timing only; sRGB primaries/gamma/size are NOT measured). Build trace
`out/890m-trace/step03-build-20261013T103926.816163Z/` (synthesized EDID, 368
imports, 0 missing). Installed to `/Library/Extensions/StrixGOP.kext` and AuxKC
rebuilt via `kmutil load --no-authorization` (code 28, reboot required); old trial
dir kept at `/Library/StrixGOPTrial-pre-013-20261013-174021`.

**Status: STAGED — reboot pending.** After reboot: confirm auto-attach (no manual
load), then read `Sample,ChangedSinceEnable` and the `StrixGOP: ...attr=` log lines.
Replace the synthesized EDID by copying the Linux
`/sys/class/drm/card2-eDP-2/edid` and re-running the runner with `--edid`.

### Step04 — root cause confirmed on 0.1.3 and the native StrixAccel (2026-10-13)

0.1.3 after reboot: auto-attaches, 120/60 Hz + HiDPI offered, EDID served
(`PanelEDID` synthesized, 1 block), but `Sample,ChangedSinceEnable = 0` (WindowServer
never wrote the scanned aperture) and WindowServer logs, per refresh,
`(CoreDisplay) Unable to find display pipe for IOFB service / regID: ...`. The
framebuffer is healthy; it has **no IOAccelerator / IOAccelDisplayPipe**. NVAccel
owns the only pipe (HDMI), so the OLED is never presented to. AppleDisplay still keys
the panel as vendor `0x756e6b6e` ("unkn"): the "unknown" colour profile is a
separate item, expected to follow once the pipe exists and the display is brought up
by WindowServer.

Architecture decision (native, not the NVIDIA/NullMoth route): `kexts/StrixAccel`
is a display-only accelerator on IOAcceleratorFamily2 itself:

- `StrixAccelerator : IOGraphicsAccelerator2`, matched on `IOPCIDevice 1002:150e`
  in its own match category (`IOAccelerator`, next to StrixGOP's `StrixGOP`), no GPU
  access at all (`configureDevice` only records the provider).
- Family classes subclassed from a header **generated from this machine's kernel
  collection** (`tools/ioaccel_gen_header.py`, `tools/ioaccel_layout.py`, 24H32,
  IOAcceleratorFamily2 485.2): exact vtable slot order, mangled names, instance
  sizes. Slots the family does not export are forwarded through the family's own
  vtable by naked tail-jumps. A runtime gate compares family class sizes and checks
  our vtables for unfilled pure slots; it fails closed (`StrixAccel,Gate = FAIL`).
- Display flow: CoreDisplay opens the pipe user client, each transaction carries the
  plane-0 IOSurface; `StrixDisplayPipe::submitTransaction` copies it into the GOP
  raster (2880x1800, stride 11520, XRGB8888; `l10r` converted, tiled / other formats
  counted and skipped) and completes synchronously. `StrixDisplayMachine` is kept by
  the accelerator and fed framebuffers by (a) a scan at start, (b) a publish
  notification, (c) a bounded poll, because the family only walks existing children.
- Kill switch `-strixaccoff` (probe + start). ESP recovery config
  `EFI/OC/config.plist.strix-off-20261013` has `-strixgopoff -strixaccoff`.
- Evidence counters on the accelerator in ioreg: `StrixAccel,Gate`, `,Pipes`,
  `,Transactions`, `,Copied`, `,Skipped`, `,Tiled`, `,UnsupportedFormat`,
  `,Raster,Width/Height/Stride`, plus `StrixAccel:` log lines (first 16 transactions
  with surface id/size/stride/fourcc).

Build/link: `bash scripts/build.sh StrixAccel`; 669 imports, 0 missing; one import
(`thread_call_cancel_wait`) was rejected by kmutil as private KPI and removed.
`kmutil libraries -p build/StrixAccel.kext --arch x86_64` is the offline check for
this (every import must resolve to a declared library, not `kpi.private`).
Installed to `/Library/Extensions/StrixAccel.kext`; AuxKC rebuilt (code 28, reboot
required); AuxKC lists strixgop, strixaccel, pataudit.

**Status: STAGED — reboot pending.** After reboot read, in this order:
`ioreg -rc StrixAccelerator -l | grep StrixAccel` (Gate PASS, Pipes>=1,
Transactions rising, Copied rising), `Sample,ChangedSinceEnable` on
StrixGOPFramebuffer, `log show --last 5m --predicate 'eventMessage CONTAINS
"StrixAccel"'`. If Skipped/Tiled/UnsupportedFormat rise, the logged fourcc/stride
tells which IOSurface layout WindowServer uses for this pipe and the copy is extended
from that, not guessed.

### Step04 owner-confirmed OLED desktop and EDID capability correction (2026-10-13)

Owner reports successful Hybrid boot with OLED desktop, HDMI disconnected.
Live readback: StrixGOP0.1.3, StrixAccel0.1.0, Gate PASS, Pipes1;
CoreGraphics one active built-in display,1440x900 logical /2880x1800 backing,
nominal120Hz. Sparse raster sample has1024 changed pixels versus enable baseline.
Preserved native implementation supplied by the owner's Sonnet session.

Counters snapshot: Transactions41, Skipped41, ValidateFail41, Copied0. These
published counters are not proof that the native copySurface path presents the
visible desktop. No GFX command submission/Metal backend exists in this code;
GL/CL/2D/video context factories are stubs. Actual presentation/render performance
must be traced rather than attributed to successful copy transactions.

Found a concrete display identity defect: public IOGraphics IODisplay.cpp calls
getAttributeForConnection(kConnectionSupportsHLDDCSense, NULL) before reading
EDID. StrixGOP rejected NULL before handling that capability. The driver had
EDID,Blocks1, but AppleDisplay contained no EDID/vendor/product properties.
Moved capability handling before the NULL output rejection; other getters still
require an output pointer. Built0.1.4 with strict warnings,368 imports/no missing
defined symbols. Exact installed BootGOPProfile and synthesized PanelEDID retained.

Evidence: `out/890m-trace/step04-live-baseline-20261013T141023.592596Z/`, including
live snapshots, display census, working-tree diff and candidate validation.
Backed up working0.1.3 package and AuxKC before staging0.1.4. kmutil result28;
AuxKC inspection confirms0.1.4, while loaded driver remains0.1.3. No hot unload,
live graphics change, EFI change or forced reboot. Naming fix runtime pending.

### Step04 transaction failure root cause analysis and StrixAccel 0.1.2 diagnostics (2026-10-13)

Evidence `out/890m-trace/step04-accel-20261013T154304Z/` (StrixAccel 0.1.1, boot 22:38):
Transactions 24 = Skipped 24 = ValidateFail 24 = Begin 24, Copied 0; the family logs
`set_transaction_args ... returning error 0xe00002bc` every ~17 ms. Static trace of
`IOAccelDisplayPipeTransaction2::set_transaction_args` (family 485.2, 24H32):

- The error is **not** a family exit. The family exits 0xe00002c2 (IOSurface ID lookup
  failed) and 0xe00002bd (deviceCacheForIOSurface NULL) never occur; the 0xe00002bc is the
  return value of `pipe->vtable[276]` (`validateTransaction`), i.e. our own check
  (identical to `AppleParavirtDisplayPipe::validateTransaction`): `getPlaneIOSurface(0,0)==NULL`.
- Plane state lives at txn+0x38, 0x70 bytes per plane: +0x10 deviceCache[2], +0x20 IOSurface[2],
  +0x30 resource[2], +0x40 gamma, +0x48..0x78 geometry. `getPlaneIOSurface(p,i)` reads +0x20.
- The plane loop only runs for planes whose bit is set in the accumulated txn flags (+0x48);
  other planes are copied from the pipe's current state (pipe+0x240). Per-plane arg type
  1 = IOSurface IDs (fills +0x20 via deviceCacheForIOSurface), 2 = IOAccelSurface ID (fills only
  the resource slots), 0 = clear. So plane 0 has no IOSurface because WindowServer either does not
  include plane 0 or sends a type-2/0 plane; which of these is unknown until observed.
- "Unable to find display pipe for IOFB service / regID 0x14803 / 0x1000004a6" (0x1000004a6 is
  StrixGOPFramebuffer) is logged once, ~2 s before the transactions start; transactions do reach
  our pipe afterwards, so it is not the failing step.

StrixAccel 0.1.2 (installed, kmutil 28, reboot pending): `validateTransaction`/`submitTransaction`
choose the first full-size (>=1024x600) IOSurface among planes 0/1, idx 0/1; failures stay failures
(keeps the safe CoreDisplay CPU fallback); the first 12 failing transactions (and every 600th)
log flags, both planes' raw slots for the txn and the pipe's current state, the surface geometry
and the resource class (`StrixAccel: txn N validate-FAIL ...`). Next: read these lines
(`bash scripts/macos-strix-accel-collect.sh`), then make the resource-backed (type 2) or
carry-over case presentable.

### Step04 StrixAccel 0.1.2 runtime result: CoreDisplay never finds a pipe because the capability is not advertised (2026-10-13)

Evidence `out/890m-trace/step04-accel-20261013T160604Z/` (StrixAccel 0.1.2, Gate PASS, Pipes 1,
Transactions 89 = ValidateFail 89 = Skipped 89, Copied 0):

- Every transaction is `flags 0x80` (bit 7 = pipe-level postgamma update): plane bits 0/1 are
  never set and both the transaction's and the pipe's current plane state are entirely zero
  (no IOSurface, no resource). WindowServer never sent a plane to this pipe; the ~17 ms
  cadence is a failing gamma update being retried, not frame presents.
- WindowServer keeps logging `[CoreDisplay] Unable to find display pipe for IOFB service /
  regID 0x15003 / <StrixGOPFramebuffer id>`, so presents go through the CPU path to the aperture
  (the lag).
- Cause: working accelerators publish `IOAccelDisplayPipeCapabilities = {DisplayPipeSupported=1,
  TransactionsSupported=1}` (AppleParavirtGPU `AcceleratorProperties`, AppleIntelKBLGraphics /
  ICLGraphics personalities). StrixAccelerator did not, so CoreDisplay does not consider it a
  display-pipe accelerator.

StrixAccel 0.1.3 (installed, kmutil 28, reboot pending): publishes the capability dict (personality
and `setProperty` in start); `validateTransaction` accepts transactions with no plane bit (gamma/CSC
only; counted as `StrixAccel,NoPlane`) and rejects planes copySurface cannot present (tiled /
non-BGRA-l10r) so the caller keeps its CPU path. Expected next: `Unable to find display pipe` gone,
`txn N validate-ok` / `surface ... fmt` lines, Copied rising.

### Step05 Native OLED brightness over DCN35 DPAUX (StrixGOP 0.1.5, 2026-10-13)

Why the NVIDIA path is not enough: `NVRMEdpBL` writes DPCD through RM's AUX channel, which belongs
to the dGPU. In Hybrid mode the mux routes the eDP panel to the 890M, so those writes never reach
it. Panel facts (DPCD 0x700: `05 9b 86`): eDP 1.4b, adjustable TCON, **no PWM pin**
(0x702 bit 0 clear), AUX level supported (bit 1), 16-bit level (bit 2), PWMGEN 11 bits (max 2047).
Only `0x721 = 2` and `0x722/0x723 = level` can dim it.

macOS side (port of the NVRMFB recipe, own implementation):
- `StrixBacklightHandler : IODisplayParameterHandler`, named `backlight`, attached to the
  framebuffer **before** `IOFramebuffer::start` (IOFramebuffer::open looks for it,
  `gIOFBHaveBacklight`). The framebuffer also answers `getAppleSense` with `kGenericLCD`
  (connection flags were already `kIOConnectionBuiltIn`) so IOGraphics builds an
  `AppleBacklightDisplay` instead of a plain `AppleDisplay`: slider, Fn keys, dim/sleep.
- `doIntegerSet` runs the DPCD writes from a thread call (IODisplay holds the framebuffer lock);
  percent clamped to >= 5, level = pct * max / 100, **level first, then mode** (same order NVRMEdpBL
  proved on 2026-10-12).

Hardware side (`kexts/StrixGOP/DcnAux.h`, no new family dependency):
- BAR5 (0xdc300000, 512 KiB) mapped read/write with `mapDeviceMemoryWithRegister`; memory space
  must already be enabled (config command bit 1), nothing is enabled or powered by us.
- DP_AUX0..4 registers from amdgpu `dcn_3_5_0_offset.h`: DMU segment 2 base 0x34C0 dwords (IP
  discovery of this unit) + AUX_CONTROL 0x1f50, stride 0x1c per instance; sequence from
  `dce_aux.c` (acquire incl. DMCU arbitration status, SW_DATA header/address/length/payload with
  autoincrement quirk, GO, poll DONE, reply byte count, read reply, release; retries 7 defer / 2
  invalid / 3 timeout). Native action nibbles 0x80 write / 0x90 read.
- Discovery in `start()` is **read-only**: per channel DPCD 0x000 (must be DP 1.0..1.4) then
  0x700; pass 0 = channels the firmware left enabled, pass 1 = the others with AUX_CONTROL restored.
  Published as `Aux,Ch0..4` (`pass ctl arb rc sw dpcd edp`), `Aux,Channel`, `Aux,EdpCaps`,
  `Aux,Status`. The handler (and so the slider) only exists when an AUX-only panel was found.
- Counters: `Backlight,Writes/Failures/LastRc/Percent/Level/Max`; log lines `StrixGOP: aux ...`,
  `StrixGOP: backlight N% = level L of M` (first 8 writes).

Kill switches: `-strixauxoff` (whole brightness part, framebuffer unchanged), `-strixgopoff`
(framebuffer inert, ESP `EFI/OC/config.plist.strix-off-20261013` has it).
Install `scripts/macos-strix-gop-install.sh` (keeps the installed personality: BootGOPProfile, EDID;
backup `~/efi-audit/strixgop-backup`, `--undo`). Installed, kmutil 28, **reboot pending**
together with StrixAccel 0.1.3.

Open until a reboot: which DP_AUX instance is the eDP; whether DMCUB holds the arbitration (status 2
is skipped and reported, not forced); whether BAR5 reads are sane before the display clocks settle.
Verify: `bash scripts/macos-strix-brightness-collect.sh`.

### Step06 Boot verification of 0.1.5/0.1.3 and the AGDC root cause (StrixAccel 0.1.4, 2026-10-14)

Verified after the reboot (StrixGOP 0.1.5 + StrixAccel 0.1.3):
- Native brightness works at driver level: `Aux,Ch0` is the eDP channel, `Backlight,Writes=9`,
  `Failures=0`, max level 2047. (Slider/Fn behaviour is for the owner to confirm visually.)
- StrixAccel: `Pipes=1`, `Transactions=91`, `NoPlane=91`, `Copied=0`, `ValidateFail=0`. WindowServer
  opens `IOAccelDisplayPipeUserClient2` but every transaction is gamma-only (no plane) -> CPU
  composition, which is the remaining lag; About This Mac graphics stays "unknown".

Root cause of "no plane ever sent" (traced in CoreDisplay/IOPresentment with lldb on a helper
process, plus `iop-getmap`):
- `CoreDisplay::FindDisplayPipeForService` keys `gDisplayPipes` by IOFB registry ID and builds the
  pipe lazily with `IOPresentmentCreateForRegistryID(0, regID)` + `IOPresentmentInitialize`.
- IOPresentment's association map (`ioPresentmentCreateAssociationMap` / `IOPresentmentGetMap`)
  requires an `AppleGraphicsDeviceControl` (AGDC) service per GPU. None exists for the Strix:
  WindowServer logs "Unable to get AGDC information, 0x10000003", "Unable to locate service
  dependencies", "Unable to acquire map"; `IOPresentmentGetMap()` returns NULL.
- AGDC user-client protocol seen (type 2): cmd 1 vendor info (0x2c bytes; vendorClass must be 1 or
  2), 0x980 GPU capability (0xdc bytes; framebuffer slot table), 0x921 link config (0xb0 bytes,
  id = slot), 0x711 framebuffer extended capability (0x196c bytes; type 0x10 = plane scaler, polled
  once per feature), 0x925 / 0x988 / 0x3fc link capability queries (unknown, refused + counted).

StrixAccel 0.1.4 (`kexts/StrixAccel/StrixAgdc.h`, `AppleGraphicsDeviceControl_decl.h`):
- `StrixDeviceControl : AppleGraphicsDeviceControl` (0x110-byte base from kext 8.1.10), created
  from the accelerator's scan thread call, attached/started on the Strix IOPCIDevice, terminated in
  `stop()`. New dependency `com.apple.AppleGraphicsDeviceControl` 1.0.0.
- Answers cmd 1 (AMD 0x1002, class 2), 0x980 (slot 0 = the StrixGOP framebuffer), 0x921 (timing
  from the framebuffer's current mode, 2880x1800 @ 60/120), 0x711 type 0x10; everything else
  -> `kIOReturnUnsupported` with the command remembered.
- Accelerator properties: `StrixAccel,AGDC,Up/Commands/VendorInfo/GpuCap/LinkConfig/FbCap/Refused/
  RefusedSeen/BadSize/NoFramebuffer`.
- Build note: `strnstr` is not exported to kexts (kmutil bind failure, rc 31); `kmutil libraries`
  does not catch that, only the real `kmutil load` does.

Installed with `scripts/macos-strix-accel-install.sh` (kmutil rc 28 = AuxKC rebuilt), **reboot pending**.
Verify next: `iop-getmap` -> MAP PRESENT, WindowServer log free of IOPresentment/AGDC errors,
`StrixAccel,AGDC,*` counters, then `Copied > 0` and `NoPlane` no longer equal to `Transactions`.

Known low-priority bug (note only): About This Mac -> Displays shows the built-in panel as
"47 inch" (wrong; the panel is a 2880x1800 14-class OLED). Likely from the display size derived by
IOKit/Display from the EDID/physical size path; revisit after the pipe works.

### Step06 result of StrixAccel 0.1.4 and 0.1.5 (2026-10-14)

0.1.4 booted: `StrixDeviceControl` is up under the Strix VGA node (`StrixAccel,AGDC,Up=Yes`), the
AGDC user client reaches it (34 commands: VendorInfo 15, GpuCap 8), `Pipes=2`. But CoreDisplay
still logs "Unable to find display pipe for IOFB service / regID 0x10503 / 0x100000443" and
IOPresentment still logs "Unable to get AGDC information, 0x10000003"; LinkConfig=0, FbCap=0 (never
asked), Copied=0, NoPlane=93.

Unknown commands that reached the vendor method (all refused with Unsupported):
- 0x3 (in 0 / out 4) and 0x941 (in 48 / out 48), once at 08:45:02 from a boot-time client;
- **0x2001 (in 4 / out 0)**, issued 7x by WindowServer's thread immediately before every
  "Unable to get AGDC information" line — this is the call that makes IOPresentment give up, so it
  never reaches 0x921/0x711.
- AGDC itself blocks unauthorised clients (`PerfPowerServices` blocked), unrelated.

From the AGDC kext (`filtered_doDeviceAttribute`, otool on a carved Mach-O of the KC entry): 0x2001
falls through the size-checked switch and is forwarded as-is; 0x941 requires a 0x30-byte buffer.

0.1.5: command 0x2001 is accepted (value logged, `StrixAccel,AGDC,ClientSet/ClientSetValue`),
refused commands log a hex dump of their input, `LinkIndex/CapIndex/CapType` published. Installed
(kmutil 28), reboot pending. Expect: no more "Unable to get AGDC information", LinkConfig/FbCap > 0,
then a DisplayPipe for regID 0x100000443 and plane transactions.

### Step06 result of StrixAccel 0.1.5 and the class-code root cause (2026-10-14)

0.1.5 booted. AGDC works end to end: `StrixAccel,AGDC,Up=Yes`, VendorInfo 12, GpuCap 6, ClientSet 4
(value 1, the `0x2001` WindowServer sends), only 0x3 and 0x941 still refused (boot-time client).
`IOAccelDisplayPipeUserClient2` is now a child of the accelerator, so a client really opens the pipe.
Yet CoreDisplay still said "Unable to find display pipe" and LinkConfig/FbCap stayed 0.

Entitled probe (`iop-getmap`, ad-hoc signed with `com.apple.private.gpuwrangler`; AMFI is off): the
IOPresentment map is PRESENT but `IOAccelerator = 0`, while IOFramebuffer = 0x100000475 and AGDC =
0x100000500 are found.  AGDC itself needs `com.apple.private.applegraphicsdevicecontrol...` /
`gpuwrangler` or `agdc_entitle`; unentitled clients never get a connection.

Disassembly of `IOPresentment` (lldb on the helper): `ioPresentmentFindIOServiceMatch` runs
`IOServiceMatching(class)`, reads `IOAccelIndex` (running counter when absent) and calls
`ioPresentmentGetNodeMap`, which walks the IOService **parents** (iterator flags 3) of every entry,
reads each parent's own `class-code` and keeps only parents whose code is a display class
(0x30000, 0x30001, 0x00100, 0x30100, 0x38000, 0x30200).  Those PCI registry IDs form the node
that ioPresentmentMatch later compares across accelerator/framebuffer/AGDC.

Root cause: our PCI node `VGA@0` carries the EFI hide spoof `class-code = FFFFFFFF` (+ `disable-gpu`,
`name #display`), so StrixAccelerator, StrixGOPFramebuffer and the AGDC service all get an empty node
and never associate.  The NVIDIA side is fine (`PEGP class-code 0x30000`).  Checked with a parents
walker (`parents.c`): VGA = 0xffffffff, GPPA = 0x60400.

0.1.6 (StrixAccel): `restoreClassCode()` publishes the hardware class code read from config space
(0x030000) on the PCI node before the accelerator registers and puts the spoof back in stop().
Properties `StrixAccel,ClassCodeHW` / `StrixAccel,ClassCodeSpoof`.  The spoof still keeps the stock
AMD/Apple drivers from matching at boot (they match at publication, before our start).
Verify: `./parents 0x<fb id>` shows VGA class-code 0x30000, `iop-getmap` IOAccelerator != 0,
`LinkConfig/FbCap > 0`, no "Unable to find display pipe", `Copied > 0`.

### Step06 brightness check (StrixGOP 0.1.5, 2026-10-14)

Driver path works: `IODisplaySetFloatParameter(brightness, 0.3)` -> handler -> `Backlight,Percent=30`,
level 614/2047, LastRc 0; restored to 1.0.  All earlier logged writes were 100 % (the first 8 are
logged only).  Physical dimming is NOT verified, and the Fn-key path is untested.
0.1.6 (StrixGOP) adds evidence: `Aux,Dpcd700/720/300..350` dumps (eDP caps, display control, sink
extension block), post-write readback of DPCD 0x720..0x723 (`Backlight,Readback`), logs of the raw
`doIntegerSet` key/value (first 40) and 40 write lines.
Next: if readback shows the level accepted but the panel does not dim, the OLED needs the
luminance/nits path (DPCD 0x32F region) instead of the 0x722 level; the dump decides.

### Step06 result of StrixAccel 0.1.6 / StrixGOP 0.1.6 (2026-10-14)

Booted with the class-code fix (hardware class code is **0x038000**, not 0x030000): `LinkConfig=13`,
`FbCap=13`, `NoPlane=0`, `Copied == Transactions` (plane transactions now flow, CPU copy into the
GOP aperture); user confirms OLED + HDMI both work and **brightness works** (DPCD readback
`0002027b` = level 635 after a 31 % write).  Display is still choppy.
Remaining refusals: 0x3, 0x941 (boot client, zero input), 0x925 (in 12: `01 00 00 00`), and 0x711
for fb-capability types 0x1,0x2,0x4,0x8,0x20,0x40,0x80,0x100..0x8000 (only 0x10 is answered).
DPCD dumps: 0x700=`059b8614`, 0x720=`000100000b0b0b00000002a300ffff03`, 0x310..=`1e0000170`,
0x340=`01770100` (luminance block, unused so far).

0.1.7 (StrixAccel): the present path copied the full 20.7 MB frame to the write-combined aperture on
every transaction.  Now a shadow of the aperture is kept and only 128-byte blocks that changed are
written (full refresh on mode change and every 1800 frames).  Timing/dirty counters:
`StrixAccel,Copy,AvgUs/MaxUs/AvgKB/Frames/FullFrames` and log `txn N: copy diff X us, wrote Y KB`.
Installed, kmutil 28, reboot pending.  If lag stays, measured copy time tells whether the cost is
the copy (then threaded/async copy) or pacing (no vblank source / flip completion).

### Step06 result of StrixAccel 0.1.7 (2026-10-14)

Both displays up (OLED via iGPU, Mi Monitor 1080p144 via NVIDIA, main display).  600 transactions,
Copy avg **12.6 ms**, max 25.4 ms, avg written only 260 KB/frame, 2 full frames.  So the time is not the
write volume: it is reading/comparing 2 x 20.7 MB (xnu `bcmp` is a `repe cmps` loop) and/or a slow source
or aperture mapping.  At 144 Hz the budget is 6.9 ms, and the copy runs on WindowServer's thread, so it
also stalls the HDMI display.
0.1.8: 64-bit unrolled compare, per-phase timers (`Copy,DiffCompareUsAvg`, `DiffWriteUsAvg`,
`FullFrameUs`) and a one-off probe at txn 3/300 (`Probe,SrcReadUs`, `ShadowReadUs`, `ApertureWriteUs`).
Decision after reboot: if source read is slow -> source is uncached/VRAM (need cached remap or GPU copy
elsewhere); if aperture write is slow -> aperture mapping/cache attr; otherwise async present worker.

## Step06 StrixAccel 0.1.9 — one-reboot batch, live-tunable present path

Why: 0.1.7 measured avg 12.6 ms / max 25 ms per present while writing only ~260 KB, i.e. the cost is source
read/compare/mapping, and the copy ran synchronously on WindowServer's thread (it also stalls the HDMI display at
144 Hz, budget 6.9 ms).  Instead of one probe per reboot, 0.1.9 ships every known candidate behind runtime tunables.

- Async present: `submitTransaction` retains the newest surface, parks it in `pending` (older un-started frame is
  coalesced), `thread_call_enter(worker)` and returns.  The worker copies under the pipe lock.  `free()` cancels the
  call and waits on `workerBusy`.  WindowServer no longer waits for the copy: slow copy => dropped OLED frames, never
  an HDMI stall.
- Tunables (properties written on `StrixAccelerator`, `tools/strix_accel_tune.c`):
  `Mode` 0 full / 1 diff-vs-shadow, `Async` 0/1, `SrcCache` 0 default / 1 copyback / 2 write-through / 3 inhibit /
  4 write-combine (mapping flushed via generation counter, falls back if refused), `Block` 32..4096,
  `Probe=1` runs the bandwidth probe on the next frame, `Reset=1` zeroes the copy counters.
- New counters: `StrixAccel,Present,Submits/SubmitUsAvg/SubmitUsMax/Coalesced`, `StrixAccel,Tune,*`.
- Tooling: `tools/strix_present_load.swift` (animated load on the Built-in screen, prints fps/p95/p99),
  `scripts/macos-strix-present-bench.sh` (cycles 9 configs live, prints per-config counters, restores defaults).
- Defaults after boot: Mode=1, Async=1, SrcCache=0, Block=128.
- Recovery: boot-arg `-strixaccoff`, or `Async=0 Mode=0` live.
- Installed 2026-10-14 (kmutil rc=28), reboot pending.  After reboot: `bash scripts/macos-strix-present-bench.sh`.

### Step06 result of StrixAccel 0.1.9 bench and the write-combine footgun (2026-10-14)

Reboot done, 0.1.9 live (Gate PASS, Pipes 1, Transactions=Copied, NoPlane 0, ValidateFail 0).
`bash scripts/macos-strix-present-bench.sh 6 full`, healthy configs first (each 6 s animated load on Built-in):

- sync full (0/0/0/128): copy avg 1954 us, submit avg 1959 us, 20250 KB, 119.0 fps.
- sync diff (1/0/0/128): copy 1560 us, submit 1565 us, 2988 KB, 120.0 fps.
- async diff (1/1/0/128, the default): copy 1384 us, submit **1 us**, 2008 KB, 118.8 fps.
- async full (0/1/0/128): copy 1864 us, submit 1 us, 20250 KB, 119.0 fps.
- async diff copyback (1/1/1/128): copy 1625 us, submit 1 us, 2734 KB, 119.2 fps.
- async diff writethru (1/1/2/128): copy 1536 us, submit 1 us, 2175 KB, 118.2 fps.
- Healthy bandwidth probe: SrcRead 642 us, ShadowRead 513 us, ApertureWrite 1540 us for the
  20.7 MB frame (~32 GB/s src, ~13 GB/s aperture). Async submit (1-2 us) meets the design goal:
  WindowServer no longer waits for the copy.

Then `async diff wc` (SrcCache=4) wedged the pipe: source reads over a write-combining mapping run
uncached (~50 MB/s), copy avg exploded to **390-465 ms** (probe SrcRead 188039 us vs 642 us healthy,
ApertureWrite 140819 us), display-link collapsed to ~11-13 fps (p50 still 8.3 ms, p95 ~460 ms),
and later configs (block512/64) measured stale counters because no new plane presents arrived to
refresh them. Restoring SrcCache=0 live did not recover speed because the WC mapping stays cached
until the next plane present remaps it, and presents had nearly stopped. No "Unable to find display
pipe" / IOPresentment errors: the association is healthy, the cost is purely mapping cache mode.
Conclusion: **SrcCache=4 (and 3) is never valid for source reads**; WC belongs only on the write
(aperture) side. Evidence: `out/890m-trace/step06-bench-20261014T110500Z/` (wedged tune/ioreg,
kernel txn log showing 367940 us diff writing 0 KB).

0.1.10 (built, offline symbol check pass, no forbidden imports): `SrcCache` 3/4 are accepted but aliased to
the default cached mapping in `mapSurface` (only 1/2 set a cache flag now); version 0.1.10;
bench script drops the wc config (8 configs) and warns when a config yields zero plane presents
instead of printing stale counters. Defaults unchanged (Mode=1, Async=1, SrcCache=0, Block=128):
async diff won the healthy bench and stays default.
Installed 2026-10-14 via admin dialog (`installed: 0.1.10`, kmutil rc=28, AuxKC confirms 0.1.10,
live stays 0.1.9 until reboot), **reboot pending — not done this turn**.
Next after reboot: re-run the safe bench to re-test block64/512 and confirm the winner.

### Step06 final: 0.1.10 safe bench confirms the defaults (2026-10-14)

0.1.10 live after reboot (Gate PASS, Version 0.1.10, Pipes 1, Transactions=Copied, NoPlane 0,
ValidateFail 0). Full safe bench, 8 configs x 6 s full load, display-link ~119 fps on every
config (no stall), probe healthy (SrcRead 629 us, ShadowRead 602 us, ApertureWrite 2101 us):

- sync full: copy 1954 us / submit 1957 us / 20250 KB.
- sync diff: copy 1586 us / submit 1589 us / 2687 KB.
- **async diff (default 1/1/0/128): copy 1444 us / submit 1 us / 2307 KB — winner.**
- async full: copy 1917 us / submit 1 us / 20250 KB.
- async diff copyback: copy 1615 us / submit 2 us / 2484 KB.
- async diff writethru: copy 1665 us / submit 2 us / 2400 KB.
- async diff block512: copy 1795 us / submit 2 us / 3839 KB (coarse blocks over-write).
- async diff block64: copy 1774 us / submit 2 us / 2175 KB (less written, more compare overhead).

Coalesced=0 on every async config: the worker (1.4-1.9 ms/frame) keeps up, no dropped frames.
Block=128 is the sweet spot; default SrcCache beats copyback/writethru. No code change: the
0.1.10 defaults (Mode=1, Async=1, SrcCache=0, Block=128) are confirmed final for this path.
Evidence: `out/890m-trace/step06-bench-0110-20261014T113000Z/`.
Remaining choppiness (if any) is now a pacing question (no vblank source / flip completion),
not copy cost: present async already decouples WindowServer (submit 1 us).

### Step07 identity and size root causes (StrixAccel 0.1.11, 2026-10-14)

Three "unfinished driver" symptoms, all identity data — no hardware access:

1. **Chipset Model "#display" / graphics "unknown".** `system_profiler` falls back to the EFI hide
   name (`IOName=#display`) because no `model` property exists anywhere. Fix: `model="AMD Radeon
   890M"` on the accelerator and the PCI node (informational only; matching uses vendor/device/class).
2. **VRAM 19 MB.** That is `IOFBMemorySize` = the 20.7 MB raster, not memory. Fix: `VRAM,totalMB=512`
   (WhateverGreen convention, 512 MiB UMA from Linux) on both nodes; the raster mapping is untouched.
3. **Built-in shows "47 inch".** Proven NOT the EDID bytes: the synthesized DTD decodes (VESA
   low/low/high-nibble layout, cross-checked against the live Mi Monitor EDID which yields exactly
   527x296 mm = 23.8") to 302x189 mm = 14.0", and base bytes 21,22 give 30x19 cm = 13.98". 47.17" is
   exactly sqrt((2880/72)^2+(1800/72)^2): the 72-DPI fallback when size is unknown. Cause: the HiDPI
   override (`/Library/Displays/.../DisplayVendorID-4c83/DisplayProductID-419c`) carries only
   scale-resolutions, shadowing the EDID size on the override path — Apple's own overrides all embed
   `IODisplayEDID`. Fix: `scripts/macos-install-hidpi.sh` now embeds the live 128-byte
   `IODisplayEDID` (read from ioreg at install time, stays in sync with PanelEDID).
   Context7 was tried for the DTD layout question but has no EDID/hardware-spec coverage; the
   cross-check against the live monitor EDID settled it instead.
4. **AGDC 0x711 non-0x10 refusals.** Safe improvement, zero entries invented: answer success with
   `count=0` (echo fbIndex/type), counted as `StrixAccel,AGDC,FbCapEmpty`. 0x3/0x941/0x925 stay
   refused (boot-time/discovery only; fabricating link state risks poisoning negotiation).

0.1.11 built (offline symbol check clean), installed via admin dialog (kmutil rc=28, AuxKC 0.1.11,
live 0.1.10), override reinstalled with embedded EDID. **Reboot pending.**
After reboot verify: Chipset Model "AMD Radeon 890M", VRAM 512 MB, built-in 14-inch, `FbCapEmpty`
rising with `Refused` limited to 0x3/0x941/0x925, unchanged present performance.

### Step07 result: 0.1.11 broke the pipe — the 0x711 empty-success was the cause (2026-10-14)

Yes, my change broke it — owning it. After the 0.1.11 reboot: OLED recognised in Settings,
brightness adjustable, but frozen on the Apple logo; `Pipes=1`, AGDC up, `LinkConfig=13`,
`FbCap=13`, `VendorInfo=16`, `GpuCap=7`, yet `Transactions=0`, `Copied=0`, `Begin=0`,
`ChangedSinceEnable=0`, and **no `IOAccelDisplayPipeUserClient2` under the accelerator**:
WindowServer built the IOPresentment map (~12 builds: 195 empty 0x711 answers + 13 scaler answers)
but never opened the pipe. Evidence: `out/890m-trace/step04-accel-20261014T050026Z/`.
Identity fixes verified working in the same boot (Chipset Model "AMD Radeon 890M", VRAM 512 MB),
and the EDID override is innocent (display recognised, brightness fine) — kept.
Root cause: answering 0x711 non-0x10 with success+count=0. The poller completes every query but
the resulting map never yields a pipe; with `Unsupported` (0.1.10 and earlier) the pipe opens.
The review subagent's "caller skips the feature" assumption was wrong — lesson: never change AGDC
success/refusal shape without a reboot test, no matter how safe it reads.
0.1.12 = 0.1.10 AGDC behaviour exactly (refusal restored, `FbCapEmpty` removed) + model/VRAM kept;
installed (kmutil rc=28, AuxKC 0.1.12), **reboot pending**. If OLED returns, cause is confirmed.

### Step07 verify bundle (pre-reboot prep, 2026-10-14)

To make the pending reboot yield everything in one boot: `scripts/macos-strix-0112-verify.sh [secs]`
(pristine boot-counter snapshot, pipe/userclient check, displays identity, override check, live EDID
decode, short animation liveness + re-snapshot, kernel/WindowServer logs, PASS/FAIL verdict +
`SUMMARY.md`, all under one `out/890m-trace/step07-0112-<ts>/`). All user tools prebuilt to
`/tmp/strix-prebuild/` (script recompiles from source if `/tmp` was cleared by the reboot).
Pre-reboot dry run on broken 0.1.11 discriminates correctly: pipe checks FAIL (Transactions=0,
no userclient, FbCapEmpty=195), identity PASS (890M/512MB live), refusals limited PASS.
Post-reboot runbook: (1) `bash scripts/macos-strix-0112-verify.sh 3` → all PASS + Settings size
~14-inch by eye; (2) `bash scripts/macos-strix-present-bench.sh 6 small` → perf unchanged vs 0.1.10;
(3) `bash scripts/macos-strix-brightness-collect.sh` → AUX brightness regression check;
(4) OLED-as-main pacing comparison for the judder hypothesis.
EDID nibble-order correction: VESA DTD byte14 carries H-image high in the HIGH nibble and V-image
high in the LOW nibble (matches Linux `drm_edid` width_mm/height_mm). Live bytes
`2e bd 10` decode to 302x189 mm = 14.0"; the first verify draft had the nibbles swapped (gave
46x445) and is fixed. EDID bytes confirmed correct — 47-inch is purely the override-shadow
fallback, which the embedded-EDID override addresses.

### Step07 post-reboot result: 0.1.12 pipe healthy, cause confirmed (2026-10-14)

Reboot → live 0.1.12. `scripts/macos-strix-0112-verify.sh` **9/9 automated PASS**:
version 0.1.12, Transactions 172→264 (liveness, load grows), Copied=Begin=172,
`IOAccelDisplayPipeUserClient2` present, no FbCapEmpty, refusals back to the 0.1.10 baseline
`0x3,0x941,0x925,0x711`, model 890M + VRAM 512MB, 0 WindowServer pipe errors.
Two script bugs found and fixed during the run: pipe class query must be `StrixDisplayPipe`
(`-c IOAccelDisplayPipe` matches nothing) with the userclient counted from the accelerator's
children, and 0x711 belongs in the refused set (0.1.10 evidence confirms). Brightness healthy
(AppleBacklightDisplay, AUX 100%). Full 8-config bench (`step06-bench-0112-20261014T054943Z`)
matches 0.1.10: async-diff default copy ~1220us submit 1us ~119fps, probe SrcRead ~660us —
perf unchanged. **Root cause confirmed: 0.1.11's 0x711 empty-success broke pipe open; the
Unsupported refusal is load-bearing.** Remaining manual checks for owner eyes: OLED shows desktop
(not frozen logo), Settings size ~14-inch (was 47"), OLED-as-main pacing comparison.

### Step08 display sleep broken — kConnectionPower ACKed but no-op'd (StrixGOP 0.1.7, pre-reboot)

`pmset displaysleepnow`: HDMI (NVIDIA) sleeps, OLED stays lit — worked in the pre-brightness era.
Evidence: WindowServer ran full sleep/wake cycles for BOTH displays (`displayWillSleepWithImages` x2,
`displayDidWake` for both IDs), no blocking assertions, yet zero StrixGOP sleep calls and the panel
stayed on. Root cause, two layers: (1) `setAttributeForConnection` ACKed `kConnectionPower`/
`kConnectionPostWake` as pure bookkeeping so the power state machine completes while the panel is
never touched (no sleepDisplay/gamma/link control exists on a GOP-inherited raster — and none ever
did); (2) the 0.1.6 backlight path clamped every set below 5% (`kMinPercent`), so even a brightness-0
sleep would have parked at a visible 5%. Backlight,Writes grew 25->44 across the window, confirming
brightness traffic flows.
0.1.7 fix: `displayPower(on)` — power-OFF saves `blPercent`, parks panel at level 0 via the same
deferred apply as slider sets; power-ON/post-wake restores; `SleepCount`/`WakeCount` properties +
always-on IOLog prove the path in traces. The 5% floor is removed (level 0 is a real off; real Macs
go fully dark at slider 0). Risk noted: if this panel power-gates at level 0 and wake-restore fails
to relight, reboot re-inits (firmware) — owner tests sleep first after reboot.
Side findings: override sleep/wake does NOT re-read the override file (TEST-name canary never went
live, size unchanged) — `IOGFlags=4` stays in the file, auto-tested by the pending reboot. SDK
settled DDC blockNumber as 1-based — our getDDCBlock was already correct, no change.
Pending reboot batch tests: (1) display sleep off + wake relight, (2) inch size with IOGFlags=4,
(3) 60Hz mode judder comparison (both 2880x1800 modes offered; same raster, scheduler hint only).

### Step09 judder root cause: EDR full-pipe on CPU melts WindowServer (measured, no reboot)

60Hz still judders (user-tested) → not a 120Hz cadence issue. Measured per-display with the load tool
(now takes a screen-name arg): OLED animation → WindowServer **~1100% CPU (11 cores)**, link p99
22ms/max 44ms; same animation on HDMI/NVIDIA → WS **65-86%**, link 144fps clean. Same compositor,
same work size — cost is per-pipe. Effective OLED rate collapses to ~15 presents/s (Transactions
+120/8s at 60 ticks/s): each frame's composite takes ~66ms wall → slideshow judder at any refresh.
`sample` of WindowServer during OLED animation (`efi-audit/ws-system-20261014-133059`, root-owned):
main thread 36% in `CGXUpdateDisplay → Present → Commit → RunFullDisplayPipe → dispatch_apply →
CombineLUTs → CurrentHeadroom → mutexwait` — the FULL display pipe runs per frame on CPU, its tile
workers serializing on one headroom mutex. HDMI/NVIDIA takes the cheap path. Working theory: with an
internal backlight-class panel, CoreDisplay uses an EDR (FP16) working space and tone-maps every
frame on CPU; the external SDR monitor stays 8-bit. Our EDID/AGDC/DPCD declare no HDR anywhere, so
if EDR is keyed purely on internal class, the lever is the Settings HDR toggle (test queued) or an
SDR declaration to find. Tearing/vblank is secondary until this melt is fixed: 15fps dominates.
`tools/strix_present_load.swift` screen-arg change committed with this step.

### Step09 correction: no HDR toggle — EDR theory weakened, HDR must be fixed properly (2026-10-14)

Owner: Settings shows **no "High Dynamic Range" checkbox** for the built-in OLED. That cuts against
"EDR working space" as the full-pipe trigger (an EDR-treated panel would offer the toggle), so the
per-frame `RunFullDisplayPipe` cause is back to TBD among: FP16 working space anyway (toggle hidden
for another reason), pixel-format conversion, per-pixel color-match to the panel profile, scaler
engagement. What stands proven regardless: full CPU pipe per frame on OUR pipe only (1100% vs 75%),
~15 presents/s effective, judder at any refresh. Owner directive: fix the HDR/color path properly —
no SDR-downgrade workaround. Next discriminators (post-reboot): per-display factory profiles exist
(`/Library/ColorSync/Profiles/Displays/Built-in OLED*.icc` 3.3KB, `Mi Monitor*.icc` 520B — small
curve profiles, nothing EDR-shaped, both framebuffers ARGB8888); surface pixel format in flight
(log it in the present path); whether `CurrentHeadroom` returns >1.0. Staged for this reboot:
GOP 0.1.7 (sleep) + IOGFlags=4 (size). Reboot in progress by owner.
Choppiness note: copy max 6.6 ms is inside the 8.3 ms budget and full-frame 8 ms hits once per
~15 s — the remaining judder suspect is WindowServer pacing to the main HDMI 144 Hz display while
the OLED runs 120 Hz. Test: make OLED main (or match rates) and compare; needs owner eyes.

### Step10 why the OLED pipe melts WindowServer: CoreDisplay does the whole colour pipe itself (2026-10-14)

Reverse-engineered from CoreDisplay / IOPresentment in the dyld shared cache (lldb on a helper process,
raw byte searches; WindowServer itself is not attachable, which is left alone).

- `DisplayPipe::RunGPUDisplayPipe` decides per stage (linearization, CSC, EOTF, gamma, ...) whether the
  display hardware can do it (`IOPCapabilities::SupportsLinearization / SupportsCSC / IsLinearizationTableBased`,
  `DisplayPipe::IsEOTFSupportedInHW`).  Stages the pipe does not claim go through `RunFullDisplayPipe`
  (GPU pipe, `CombineLUTs`), which rebuilds the LUT whenever `pipe+0x291` is dirty.  Dirty writers found:
  Commit +2843/+2942/+2948/+3030/+5838/+6118, RunGPUDisplayPipe +648/+1206/+1272/+1364,
  UpdateTargetStateColorProcessing +638, MPSelectMode +2442, RefreshCapabilities +39.
- Commit +6118 compares `Display` vfunc 0x1d8 (headroom) with the cached `pipe+0x724` (copied from `+0x84c`
  in `CommitState`); it is a plain per-commit compare and is NOT the cause here: `NSScreen`
  current/potential EDR is 1.0/1.0 on both displays (`scratchpad/edr.swift`).
- IOPCapabilities for plane N come from AGDC cmd 0x711 (`__GatherAGDCDisplayPipelineCapabilities`,
  request `{fbIndex, type, count=8}`, reply 0x196c = 12 + 8 * 0x32c).  Types polled: 0x10 plane scaler
  (answered), 0x8 pipeline scaler, **0x4 linearization, 0x2 gamma, 0x1 CSC**, 0x40 inline buffer, 0x20
  rotation, 0x200 mirror, 0x80/0x100 queue, 0x400 format convert, 0x800 HDR scaler, **0x1000 plane CSC**,
  0x2000 3D LUT, 0x4000 pixel processing, 0x8000 cursor.  All except 0x10 are refused today, so
  `SupportsLinearization/SupportsCSC` are false and CoreDisplay runs every colour stage on the CPU/GPU pipe
  for every frame on the OLED.  The NVIDIA HDMI pipe claims them in hardware, hence 143 fps at 65-86 % CPU.
- Entry layout (from `IOPresentmentCapabilitiesDisplayPipe::IOPresentmentCreate{Linearization,Gamma,CSC}Dictionary`),
  stride 0x32c: +0 flags (`& 0x803fffff`, bit 2 = supported; the scaler is accepted with 0x80004),
  +4 plane mask (u64), +0xc update period (float), +0x10 type, +0x14 fixed format, +0x18 configuration id,
  linearization/gamma: +0x20 min (float), +0x24 max (float), +0x28 max table size; CSC: +0x20 pixel format,
  +0x24 min, +0x28 max.  `IsLinearizationTableBased` = type & 0x3fcc.
- Per-type "gather succeeded" flags in the IOPresentment object: 0x434 plane scaler, 0x433 pipeline scaler,
  0x432 linearization, 0x431 gamma, 0x430 CSC.

StrixAccel 0.1.13 (built, NOT installed): `StrixAccel,Caps` bitmask (1 CSC, 2 gamma, 4 linearization) makes the AGDC
0x711 handler claim those stages with the layout above (plane 0, flags 0x80004, table size
`CapTableSize`, type bits `CapLinType/CapGammaType/CapCscType`, `CapFixedFmt`).  Default 0 = old behaviour.
CoreDisplay asks once at pipe creation, so a change takes effect on the next WindowServer start (logout/login,
no reboot).  Open question the experiment answers: with the stages claimed, does WindowServer stop running
RunFullDisplayPipe (CPU) and which tables (identity or not) arrive on the transaction?  If they are non-identity
the present path has to apply them (CPU LUT apply) or HDR/colour will be wrong.

### Step11 OLED-only boot: WindowServer has no MetalDevice → StrixMetalGate 0.1.0 (2026-10-14)

Symptom: with StrixAccel ≥ 0.1.9 and no HDMI the boot stops on the Apple logo (input still works, no panic).
WindowServer crash-loops on `Assertion failed: (Failed to create MetalDevice (non-null)), Display.cpp line 3226`.
The same build boots fine with HDMI.  `-strixaccoff` boots OLED-only but takes the old software path, which the
owner rejected ("tắt nó thì đi về đường cũ" — fix the root cause, keep the Metal compositor).

Root cause chain (kernel log of the 14:27Z OLED-only boot + NullMoth 1.14.0 sources):

1. StrixAccel makes the display pipe discoverable, so CoreDisplay selects the Metal compositor and needs a
   `MTLDevice` in WindowServer.  The only Metal device is NullMoth's `NVMTLDriver`.
2. NVAccel (AuxKC, `/Library/Extensions`) withholds its `MetalPluginName` property until an NVIDIA display head
   registers.  NVRMFB refuses to start with no connected NVIDIA display ("only 0 display(s) connected --
   nothing to drive, not starting", kapiInit failed), so no head ever registers.
3. The NVRM auto-go releases the boot hold at ~+34 s; NVAccel's headless check at +60 s sees `fFB` null and no
   plugin name, restores the name and sets `debug.nvaccel_headless=1`.
4. `NVMTLDevice.m` `nvmtl_process_is_allowed` hard-refuses a device to WindowServer when `nvaccel_headless=1`
   (compute-only mode).  The allow-list `/Library/GPUBundles/nvmtl-allow.txt` (`*`, `!WindowServer`) cannot
   override it, `*` matches first.  Result: no MetalDevice in WindowServer → assert → loop.
5. Dead ends read from source and dropped: NMIntelFB (head 4) alone does not arm `fFB` (only a head-0
   NVRMNVDAFramebuffer / NMIntelFB with IOFBDependentIndex 0 does); VRAM allocation goes through `fFB`.
6. OpenCore cannot patch AuxKC kexts and Linux cannot link kexts (macOS SDK needed), hence an ESP-injected kext
   built by CI.

Fix: `kexts/StrixMetalGate` (ESP `EFI/OC/Kexts`, Kernel/Add, MinKernel 24.0.0, IOResources/IOKit matched).
A 2 s `thread_call` poll finds NVAccel; once it has been seen for 40 s with no `MetalPluginName` and no
`NVRMNVDAFramebuffer` head, it sets `MetalPluginName = ../../../Library/GPUBundles/NVMTLDriver` (before the +60 s
headless check) plus `StrixMetalGate=true` on NVAccel.  The headless branch then never runs,
`nvaccel_headless` stays 0 and WindowServer gets the NVIDIA Metal device exactly as on HDMI boots.  Frames reach
the OLED through StrixAccel's StrixDisplayPipe ("Fallback GPU Display Pipe", CPU-heavy WindowServer per
`docs/WINDOWSERVER-CPU.md`).  Boot-arg `-strixmetalgateoff` disables it.  Own IORegistry properties: `GateState`
(`plugin-name-present` / `nvidia-head-waiting` / `plugin-name-restored`), `RestoredAtSeconds`.  Kernel log
prefix `StrixMetalGate:`.

Build / install (no macOS needed for the build): `gh workflow run build.yml --ref research/890m-cobalt64`
(workflow_dispatch, job `build-kexts` on macos-14, step "Build StrixMetalGate") then `gh run download <id>` and copy
`StrixMetalGate.kext` to `/boot/EFI/OC/Kexts/`; macOS-side equivalent `scripts/install-strixmetalgate.sh`.
Run 38585619555 produced the installed 0.1.0.  config.plist: Kernel/Add entry #34, `-strixaccoff` removed.

Rollback: restore `EFI/OC/config.plist.pre-metalgate-20261014` (has `-strixaccoff`, the software path), or add
boot-arg `-strixmetalgateoff`.

Owner result: OLED-only boot reaches the desktop with the gate installed (2026-10-14).  Log verification
(GateState, `nvaccel_headless`, WindowServer stability, CPU) is the next step below.

### Step11 result: 0.1.0 boot read from the unified log (boot 0F08D008, 15:05Z, 2026-10-14)

Owner boot reached the login window and a session OLED-only.  From the decoded archive
(`~/ga403-logs/metalgate-boot-20261014/dec`, whole archive 116 GB of jsonl, filter with `rg` on `"boot_uuid":"…"`):

- Gate worked: NVAccel logged `headless check: not headless (the plugin name is already back) -- nothing to do`
  at +61 s (all earlier OLED-only boots logged `no NVIDIA display head after 60 s -- MetalPluginName restored
  WITHOUT arming`).  One WindowServer (pid 1544) then ran 15:06:05 → 15:07:13 until the owner's shutdown,
  `Metal compositor activated.` at 15:06:06, NVMTLDriver/NullMoth Vulkan lines from WindowServer, no
  `Display.cpp` assertion, no crash loop.
- The gate itself logs nothing decodable: an ESP-injected kext has no uuidtext in `/var/db/uuidtext`, so every
  `IOLog` of it is dropped from the offline decode (only kernelmanagerd's `Received kext load notification:
  com.itlmt7925.strixmetalgate` shows).  Its state is in the registry: `ioreg -c StrixMetalGate` (GateState,
  RestoredAtSeconds) and `StrixMetalGate=true` on NVAccel; `scripts/macos-hang-forensics.sh` now dumps both.
- Timeline of the OLED-only boot with NullMoth 1.14.0: NVAccel +0 s; NVRM go(2) done +4 s and NVRMFB
  `ENUMERATED: 0 connected display(s)` → `not starting`; NVRM then waits for `nvfbheads`=4 heads for 20 s and
  retries `debug.nvaccelfb=1` 10 s ("NEVER took", no head) and releases the boot hold at +34 s (`display PARTIAL`);
  with an HDMI monitor the head is published at +4 s and the hold is released at +4 s (`display armed`).
- NullMoth's `com.nullmoth.wsreset` daemon (a one-shot "flicker stopgap", `/Library/NullMoth/nullmoth-wsreset.sh`)
  SIGKILLs the first WindowServer once it is up at the login window.  Here the respawned WindowServer (pid 1188)
  came up 15:05:54, before the 0.1.0 gate restored the name (+40 s hold, ~15:06:02), and SIGABRTed after 564 ms
  (`Unable to get AGDC information`, mode 0x0 on the framebuffer, assertion 129; the crash report was not written,
  the old Display.cpp:3226 one is in `ws.txt` of the 11:4x boots); launchd's 10 s respawn throttle then delayed the
  good WindowServer to 15:06:05.  Net effect: ~10 s slower login, not a hang.
- Noise already present on HDMI boots and not new: `Unsupported sw composite destination.` (tens of thousands per
  minute, in every boot since 10-10), `set_device_transfer: can't set device gamma (0xe00002c7)`, `Invalid display`.
- The shutdown wrote a `shutdown_stall` report (22:07 local) — still to look at.

StrixMetalGate 0.1.1 (this commit): hold 12 s instead of 40 s, poll 1 s, so the name is back at ~+13 s, well
before the +34 s release and any WindowServer start that needs the device.  HDMI boots are unaffected: heads > 0
at the check keeps the gate passive (`nvidia-head-waiting`).
Installed on the ESP from CI run 38590219003 (0.1.1; the 0.1.0 kext kept in `EFI/OC/Kexts-backup/StrixMetalGate-0.1.0.kext`).
To check after the reboot (macOS): `ioreg -c StrixMetalGate | grep -E 'GateState|RestoredAtSeconds|GateVersion'` expects
`plugin-name-restored` at ~12-14 s; offline: first WindowServer after the wsreset should not abort and the login
window should come ~10 s earlier than the 70 s of boot 0F08D008.

### Step11 StrixAccel 0.1.14 (Caps=7 default) measurements, two boots (2026-10-14)

HDMI + OLED boot (WindowServer 883, 0.1.14 live): WindowServer only, `StrixAccel,AGDC,CapSeq=ws:0x4,ws:0x2,ws:0x1` x4,
`CapServed=39`, `CapFromOther=0`, Gate PASS, 640 transactions copied, 0 validate fail.  Claims were served (type 0x4 with
3 entries, 0x2, 0x1) but the OLED still melted: 118.6 fps, WindowServer 1295 % (baseline 1150 %), Mi Monitor 143.5 fps /
56 %.  No `GammaSeen`/`PipeOnlySeen`: CoreDisplay never delivered a table, so the claims were not honoured.
Refused in the same query set: 0x8 pipeline scaler, 0x40, 0x20, 0x200, 0x80, 0x100, 0x400, 0x800, 0x1000, 0x2000,
0x4000, 0x8000 (the previous pass served only 0x10 plane scaler).

spindump of WindowServer under OLED load (`out/890m-trace/step11-0114-*/ws-spindump-load.txt`): 7794 of 7916 samples in
`RunFullDisplayPipe` block -> `CombineLUTs` -> `Display::CurrentHeadroom` -> `std::mutex::lock` (`__psynch_mutexwait`,
about 24 dispatch_apply workers contending on one mutex, "blocked by turnstile ... pthread mutex owned by WindowServer").
So the melt is lock contention in CurrentHeadroom called per LUT element, not LUT arithmetic, and RunGPUDisplayPipe still
chooses the full pipe (NVMTL commandBuffer commitAndWait) with 0x4/0x2/0x1 claimed: another stage or condition keeps
RunFullDisplayPipe selected (pipeline scaler 0x8 and 3D LUT 0x2000 are the untested refusals).

OLED-only boot (gate 0.1.1, `GateState=plugin-name-restored` at 21 s, WindowServer 1150): `Transactions=0`, `Pipes=1`,
no `IOPresentment` traffic; WindowServer composites with `CompositorSW::CompositeLayersToDestination` straight to the
framebuffer, NVMTL used for rendering and fence waits only.  Load tool: 119.7 fps, p99 8.37 ms, WindowServer about 155 %
of one CPU (versus 1150 % through the pipe).  `scripts/macos-strix-0114-verify.sh` now skips displays that are absent.

StrixAccel 0.1.15 (installed, reboot pending): claim mask is now the 0x711 type bits themselves, default 0x340f
(CSC 0x1, gamma 0x2, linearization 0x4, pipeline scaler 0x8, format convert 0x400, plane CSC 0x1000, 3D LUT 0x2000).
Boot-arg `strixcaps=N` overrides, `strixcaps=7` is the 0.1.14 behaviour, `-strixaccoff` disables.  Test on a boot WITH
HDMI (the OLED-only boot never opens the pipe): `bash scripts/macos-strix-0114-verify.sh`; the verdict line
"oled-melt" must drop well below 1100 %.  If it does not, the spindump recipe above (`spindump WindowServer 5 10`) shows
the next stage to claim.

### Step11 — who switches headroom caching on, and why the OLED is not offered HDR (CoreDisplay disassembly, 2026-10-14)

Source: lldb `disassemble` of the dyld-cache CoreDisplay (macOS 15.8.1 24H32), symbol table dumped with `image dump symtab`.

**Headroom cache (the melt).** `Display::CurrentHeadroom(0)` only caches its result (Display+0x224=1) when the
`EDRDisplay` hanging off Display+0x60 has byte +0x11 ("headroom requested") set. That byte is written in exactly two
places:
- `Display::InitializeBrightnessControl()` copies the process global `gHeadroomRequested` into it when the EDRDisplay is
  created (and `gEnableEDR` into +0x10);
- `CoreDisplay_XRPresent(bool)` (name is historical) sets `gHeadroomRequested`, then for every WS device with
  device->+0x128==1 and +0x129==1 writes EDRDisplay+0x11, derives +0x12 = (+0x10 ? requested : 0) and runs
  `EDRDisplay::UpdateEDR()`, `Display::SetLinearBacklightBrightness()` and a CGXDisplayDevice update.
Nothing inside CoreDisplay calls `CoreDisplay_XRPresent`; it is an exported entry point for WindowServer/SkyLight. With
nobody calling it, `gHeadroomRequested` stays 0 and every `CombineLUTs` element takes the mutex and recomputes. A client
process cannot fix it (the global lives in WindowServer's CoreDisplay copy); `CoreDisplay_Display_RequestHeadroom` only
calls `EDRDisplay::SetMinEDRScaleFactor` and does not touch +0x11.

**HDR/EDR gate.** `gEnableEDR` is set only by `CoreDisplay::EnableEDR(bool)`, called from `_CGXEnableHDR`,
`WSUpdateHDRState` and `CGXDisplayDriverInitialize` with `gCGXDisplayHDREnabled && CGXIsHDRSupported()`.
`CGXIsHDRSupported()` (AMD machine path) asks every WS device `vtable+0x148`. `Display::SupportsHDRMode()` and
`IsHDR10()` end in `FindIOModeIDForIODynamicRange(fb, modeID, 2)`: the framebuffer must publish a *second* IOFB display
mode with a detailed timing equal to the current one (`DetailedTimingsEqual`, mask 0x80000080) whose
`IODetailedTimingInformationV2.dynamicRange` (offset 0x8e from the struct start in the cache build) is
`kIODynamicRangeHDR10` (2). StrixGOP 0.1.7 published two modes (60/120 Hz SDR) with dynamicRange 0 and
the panel EDID is a synthesized 128-byte base block without a CTA-861 extension, so `NSScreen.maximumPotentialEDR` is
1.0 on the OLED (`tools/strix_edr_probe.swift`).

**Experiment (StrixGOP 0.1.8, default off):** HDR twins as mode IDs 3/4, same timing as 1/2 with `dynamicRange=2`
(SDR twins get 1). Enabled by personality key `HdrModes` (`macos-strix-gop-install.sh --hdr`), boot-arg `strixhdr=1`,
disabled by `-strixhdroff`. Published `Hdr,Modes`. Purely informational for the hardware: the scanout stays the boot
GOP raster, so selecting the HDR twin in System Settings only changes what WindowServer renders (PQ into an 8-bit
XRGB buffer), not the DCN output. Expected observable: `edr_potential` > 1.0 and a "High Dynamic Range" toggle for the
OLED; whether this flips `gEnableEDR`/EDRDisplay creation timing and removes the CurrentHeadroom contention is the
open question for the next boot. Real HDR (10-bit surface + PQ + SDP metadata) needs DCN programming that StrixGOP does
not do.

One-shot collection: `scripts/macos-strix-autocollect.sh arm` before the reboot; ~90 s after the next login it runs
`scripts/macos-strix-0114-verify.sh` (now also dumps EDR potential, GOP version/Hdr,Modes, IOFBModes count, boot-args)
and removes itself.

### Step11 result of the 0.1.15 + StrixGOP 0.1.8 boot (OLED-only, 2026-10-15) and the second HDR gate

Autocollect ran by itself (`out/890m-trace/step11-0114-20261015T013806Z`). The boot had no HDMI, so `Transactions=0`,
`Pipes=1`: the OLED-only CompositorSW path again (WindowServer 197 %, 118.6 fps, p99 8.46 ms). The "oled-melt GONE"
verdict is therefore **not** a measurement of 0.1.15; it needs a boot with HDMI. Served claims: `CapSeq` now shows
0x4,0x2,0x1,0x400,0x1000,0x2000 (CapServed=14), WindowServer is still the only client.

HDR twins alone did nothing: `IOFBModes` has 4 entries (IDs 3/4 carry dynamicRange 2, SDR twins 1; CG hides them from
`CGDisplayCopyAllDisplayModes`) but `edr_potential` stays 1.0. Disassembly of `Display::SupportsHDRMode()` shows three
more conditions, all on `IOFBConnect` (the `gConnectRefDict` entry):
1. `connect+0x128` is a `0x138`-byte copy of the framebuffer's **`IOFBTimingRange`** registry property
   (`IODisplayInstallTimings`, needs >= 0xf0 bytes). Byte `+0xea` is `IODisplayTimingRangeV2.supportedDynamicRangeModes`
   (struct offset 0xea): bit1 = HDR10 must be set (`+0xe8` supportedColorimetryModes bit8 = BT.2020 for
   `drive_display_2020`). StrixGOP published no `IOFBTimingRange`, so the pointer was NULL.
2. `connect+0x200 == 1` and `connect+0x1e4 & 4`: written by `InstallCEA861EXTColor` from the CEA-861 **HDR static
   metadata data block** (extended tag 6, EOTF byte bit2 = ST 2084). Our synthesized EDID is one 128-byte block.
3. The HDR twin mode ID must differ from the current mode ID (done in 0.1.8).
StrixGOP 0.1.9 (only with `HdrModes`): appends a CEA-861 extension block (colorimetry BT.2020, HDR static metadata
SDR+PQ, ~500/400/0.0007 cd/m2, base block byte 126 = 1, both checksums fixed; `PanelEDIDSource=synthesized+cta-hdr`,
`EDID,Blocks=2`) and publishes `IOFBTimingRange` (V2, pixel clocks pinned to the two panel clocks so no extra timings
are installed, 8/10 bpc, SDR|HDR10, BT.709/2020/2100). Checks next boot: `edr_potential`, `IODisplayEDID` length 256,
`Hdr,TimingRangeBytes`.

### Step11 OLED-only WindowServer profile (spindump, 10 s under the present load tool, 2026-10-15)

`out/890m-trace/step11-oledonly-profile/` (`load.txt`, `top-under-load.txt`, `spindump-ws.txt`). Load: 119.3 fps,
avg 8.38 ms, p99 8.57 ms, max 177 ms. WindowServer 201 % CPU, 31 threads (136 % again a minute later with the load
tool stopped, so the compositor is not idle-cheap either).

Where the CPU goes (25 `com.apple.root.default-qos` workers, 9.6 s CPU in 10 s; ws_main_thread only 1.26 s):
* 1102 of 1459 worker samples: `layer_blit_entry_block` (SkyLight) -> `CGLayerKitFetch` -> `CARenderOGLRender` ->
  `CA::OGL::Renderer::render` -> nested `render_layers`/`LayerNode::apply` -> `render_contents_background` ->
  `fill_rect_tex` -> `CA::OGL::SWContext::draw_elements` -> `CA::OGL::SW::draw_polygon` -> `dispatch_apply` ->
  `scan_convert`/`scanline` -> `sample_texture` -> `image_sampler<ARGB8_Host,...>`.
* Remaining user leaf work: `clip_vertices`, `layer_blit_byte_ARGB8_ARGB8_RGB8`, `bzero`, `memmove`, `circle_sampler`.
* The `kernel+2425475 (running)` leaf under every user frame is the stackshot IPI, not a fault: the thread was on-CPU
  in user code.

So the "CompositorSW" path is Core Animation's **software OpenGL rasteriser** (`CA::OGL::SWContext`) shading every
layer of the 2880x1800 ARGB8 surface across all cores. Nothing in the display kexts is on that path: it is chosen
because no accelerator (our StrixAccel is display-only, no 3D/Metal context) is offered to CA. The only way to make
it cheap is a real accelerated renderer (iGPU 3D, i.e. the PM4/GFX bring-up) or a lighter workload (fewer / smaller
damaged layers); no tunable in StrixGOP/StrixAccel changes it. Reducing damage (e.g. 60 Hz instead of 120 Hz mode,
`reduce motion/transparency` in Accessibility) is the cheap mitigation and is user-side only.

### Step11 smoothness measurements (OLED-only, 0.1.15 live, 2026-10-15, on battery with Low Power Mode on)

Tool: `tools/framepace.swift move|anim <s> shadow|noshadow titled|borderless <w> <h>` (CADisplayLink app ticks; "move" =
`setFrameOrigin` every tick = window drag), `tools/strix_setmode.swift` (CG config transaction; `CGDisplaySetDisplayMode`
returns 0 but is ignored).
* 120 Hz, anim (layer rotation): 117-120 ticks/s, p99 8.4 ms. Presentation of a simple animation is fine.
* 120 Hz, move 600x400 titled+shadow: 55-110 ticks/s, p90 12-39 ms, p99 26-130 ms, max up to 244 ms; one run 23 ticks/s.
  Borderless 200x150: 114/s, p99 21 ms. 1400x800: 98/s, max 157 ms. Large run-to-run variance.
* 60 Hz (mode 1): anim 60/s perfect, but move 600x400 only 30-44/s and 1400x800 14/s (p90 168 ms). The cost of a
  window move is not a function of refresh rate: each move is a software re-composite of old+new damage plus shadow,
  so 60 Hz does not help and 120 Hz is better. Keep 120 Hz.
* So the choppiness is CPU-bound software compositing latency (fork-join over ~25 default-qos threads, so it is
  sensitive to any busy core). CPU clocks: big Zen 5 cores sit at 2.0 GHz, Zen 5c 1.4-3.0 GHz (`debug.amdcppc.freq`),
  Tctl 77 C, package 16.6 W while the machine was on battery, `pmset lowpowermode 1`, AsusWmi `set_profile=2` (silent).
  Next: re-measure on AC with Low Power Mode off and the Performance/Turbo profile to see how much of the jitter is the
  platform power limit rather than the renderer.

### Step11 WindowServer SIGFPE crash loop after StrixGOP 0.1.9 (HdrModes=true), 2026-10-15

* Symptom (user-visible "panic"): WindowServer restarts every ~10 s (launchd throttle), uptime 42-47 s at each crash, boots
  5728534F and C18067AF; the boot before the 0.1.9 install (E74F30A9) was clean. No kernel panic.
* Crash report (`WindowServer-2026-10-15-085713.ips`, `-091013.ips`): EXC_ARITHMETIC / SIGFPE in CoreDisplay
  `IOCheckTimingWithDisplay` (+0x1EBDD) under `IOFBRebuild` -> `InstallFromEDIDDesc`, at WindowServer init.
* Cause: 0.1.9 `publishTimingRange()` published an IODisplayTimingRangeV2 with only clocks, encoding and range bits set;
  the rest (charSize* , min/max active/blanking/sync clocks, frame/line rates, totals) were 0, and CoreDisplay divides by them
  once kIOFBTimingRangeKey exists. Before 0.1.9 the key was absent so that path was skipped.
* Fix (0.1.10): fully populated range (char sizes 1, frame 24-144 Hz, line 30-400 kHz, totals 4096x2400, active/blanking/
  sync min/max covering 2880x1800, links 1, link0 clock kHz). Not yet booted; unverified which exact field was the divisor.
* Immediate recovery if it still loops: boot-arg `-strixhdroff`, or `sudo bash scripts/macos-strix-gop-install.sh --nohdr`
  (drops the timing range and the HDR twins, back to the 0.1.8-less behaviour that booted fine).
* Installed from Linux (no rollback): CI run 38670567919 builds StrixGOP 0.1.10 (workflow now has an explicit StrixGOP
  step); kext copied to `/boot/EFI/OC/Kexts/StrixGOP.kext`, Kernel/Add entry added after StrixMetalGate, boot-arg
  `strixhdr=1` appended (HDR twins + CTA block + timing range stay ON). Config backup: `config.plist.pre-strixgop010`.
  Caveat to check in the next boot: `/Library/Extensions/StrixGOP.kext` (0.1.9, AuxKC) has the same bundle ID; see
  `ioreg -l | grep StrixGOPVersion` (must say 0.1.10) and the unified log for duplicate-kext messages.

### Step11 all custom kexts moved out of /Library/Extensions into ESP Kernel/Add (2026-10-15)

Why: AuxKC copies cannot be updated from Linux, cannot be overridden by OC, and duplicate bundle IDs once the ESP copy exists.
* Injected (order matters, validated by a dependency/order check on Info.plist OSBundleLibraries, 0 problems):
  `NVRM, NVRMEdpBL, NVRMFB, NVRMAGDC, NVAccel` (NullMoth 1.15.0 files copied byte-for-byte from the installed, already
  patched `/Library/Extensions`), then `StrixAccel` 0.1.15, `StrixGOP` 0.1.10 (CI run 38670864517), `StrixMetalGate` last
  (it polls for NVAccel). HighPointIOP/HighPointRR (RAID kexts, unrelated hardware) are dropped, not injected.
* Left in macOS on purpose (not kexts): `/Library/GPUBundles` (Metal user-space driver), `/Library/NullMoth`, wsreset daemon.
* Must be removed from macOS before the boot, else same bundle IDs exist in AuxKC and BootKC:
  `/Library/Extensions/{HighPointIOP,HighPointRR,NVAccel,NVRM,NVRMAGDC,NVRMEdpBL,NVRMFB,StrixAccel,StrixGOP}.kext`
  and the stale `/Library/KernelCollections/AuxiliaryKernelExtensions.kc`.
* Note: re-running `nullmoth-setup.sh` would reinstall NV* into /Library/Extensions; do not, or remove again.

### Step11 /Library/Extensions cleaned (done from Linux, rw mount), 2026-10-15 — HANDOFF TO THE macOS SIDE

State now:
* `/Library/Extensions` is EMPTY and `/Library/KernelCollections/AuxiliaryKernelExtensions.kc` is deleted (copies in
  `~/ga403-logs/lib-ext-removed-20261015/` on the Linux side). All custom kexts load from the ESP (OC Kernel/Add, BootKC):
  NVRM, NVRMEdpBL, NVRMFB, NVRMAGDC, NVAccel, StrixAccel 0.1.15, StrixGOP 0.1.10, StrixMetalGate 0.1.1. Boot-arg `strixhdr=1`
  added (HDR twins/CTA block/timing range on). ESP config backup: `EFI/OC/config.plist.pre-strixgop010`.
* The 0.1.9 SIGFPE loop (see the section above) is fixed in 0.1.10 by a fully populated IODisplayTimingRangeV2 - the first
  boot with 0.1.10 has not happened yet when this was written.

What the macOS side should do:
1. Do NOT run `macos-strix-gop-install.sh`, `macos-strix-accel-install.sh` or `nullmoth-setup.sh`: they reinstall into
   `/Library/Extensions` and recreate the duplicate-bundle-ID conflict. Update kexts by CI build + copying into
   `EFI/OC/Kexts` from Linux (workflow `build.yml` builds StrixGOP, StrixAccel, StrixMetalGate explicitly).
2. After the first boot collect: `ioreg -l | grep -E 'StrixGOPVersion|GateVersion|GateState'`, `kmutil showloaded | grep -i
   -E 'nullmoth|strix'` (expect all of them, none from AuxKC), `log show --last boot --predicate 'process=="kernel"' |
   grep -i -E 'duplicate|already loaded|strix|NVRM'`, and whether WindowServer stays up (`ls /Library/Logs/DiagnosticReports | grep WindowServer`).
3. Watch for the changed timing: NVIDIA kexts now start in BootKC, earlier than before (they used to load with AuxKC);
   NVRM's 20 s head wait / 34 s boot hold may shift. If WindowServer starts without the Metal device, check StrixMetalGate
   `GateState` first.
4. If HDR still misbehaves, `-strixhdroff` in boot-args disables only the HDR parts without touching the injection layout.

### Step11 12:38 boot forensics and deployment repair applied (2026-10-15)

**Status: APPLIED ON DISK — next macOS boot and visible OLED/HDR result pending.**
This entry supersedes the immediately preceding "Data is empty / all graphics
load from ESP" handoff. Those entries remain as history, not current instructions.
The earlier statement that 0.1.10 "fixed" SIGFPE was a source-level expectation;
the new boot did not load that framebuffer, so runtime validation is still pending.

#### Work history and fresh evidence

The first response in this session inspected existing Linux captures and the
handoff but did not mount macOS Data. Its statement that no new boot log was
available was incomplete. After the owner requested actual investigation and a
fix without rollback, Data was mounted read-only through the existing fstab
entry, revealing the new report `WindowServer-2026-10-15-123903.ips`.

Actual failed boot: `F4C323A7-3891-4EFF-B8A9-B780C9A6E71F`, kernel timestamp
`2026-10-15T05:38:43Z` (12:38:43 local). WindowServer PID164 launched at
12:38:48 and aborted at12:38:55, uptime13s. This is **SIGABRT**, not the previous
0.1.9 timing-range SIGFPE. Triggered stack:
`CoreDisplay::Assert -> CGXMappedDisplayStart -> CGXDisplayDriverInitialize`.

Decoded log evidence:

- `IOFramebufferOpen failed ... PEGP@0/IONDRVFramebuffer ... 0xe00002c7`.
- `GPUWrangler is disabled due to no MappedDisplay`, `System has no accelerator`,
  then `Failed to create FB 1 of 1`.
- ReportCrash captures the `MappedDisplay.cpp:5509` assertion:
  `FB: 0 of 1 opened, succeeded 0 times, failed 1 times`.
- Subsequent WindowServer PIDs482,636,761,826,1061 and others fail the same open
  roughly every10s. This establishes a user-space crash loop, not a static logo
  inferred solely from a screenshot.
- kernelmanagerd reports loaded NVRM, NVRMEdpBL, StrixProbe and StrixMetalGate,
  but no NVRMFB, NVRMAGDC, NVAccel, StrixGOP or StrixAccel. SystemKC loads later.

Raw evidence is private and remains outside Git:
`~/ga403-logs/boot-0110-20261015/` contains the new `.ips`, filtered
`new-boot.jsonl`, `display-log.txt`, decoder diagnostics, policy snapshot,
linker reproduction and symbol census. The archive view uses read-only symlinks
into the mounted Data diagnostics/uuidtext; permanent decoded output and the
copied crash report remain available independently of the mount.

The owner mounted additional APFS volumes read-only after sudo authentication;
volume3 is System, volume4 Update. Inspection of the **installed** collections
confirmed all three required providers absent from BootKC and present in SystemKC:
`com.apple.iokit.IOGraphicsFamily`, `com.apple.iokit.IOAcceleratorFamily2`,
`com.apple.AppleGraphicsDeviceControl`. The installed SLE directories retain
plists but their executable files are elided into SystemKC. Kernel/Force cannot
read nonexistent standalone executables from those directories.

Built the cached OpenCore1.0.9 `Utilities/TestKextInject` with the existing UDK.
Injecting the current ESP StrixGOP into the installer BootKC reproduced:
`IOGraphicsFamily not in Boot KC`, parent vtable resolution to0, and
`Vtable patching failed ... Invalid Parameter`. The utility also exercises
unrelated kernel quirks; only the explicit StrixGOP injection result is used here.
This reproduction plus the actual installed collection census explains why
merely sorting custom Kernel/Add entries did not suffice.

#### Independent panel-personality defect

The ESP StrixGOP0.1.10 bundle copied from CI had `AdoptBootGOP=false`, no
`BootGOPProfile`, and no `PanelEDID`. Even a successful link would fail its opt-in
profile gate. The driver source's default opt-out is intentional; copying a raw
CI artifact over a configured deployment must not erase the local personality.

Retained the **0.1.10 executable** and supplied the existing validated hardware
personality from `~/ga403-logs/lib-ext-removed-20261015/StrixGOP.kext`:
BAR0 `0x880000000`/256MiB,2880x1800,stride11520,depth32,XRGB8888,offset0,
rotation0;128-byte synthesized EDID with valid checksum. Set `AdoptBootGOP=true`
and `HdrModes=true`; boot-arg `strixhdr=1` remains. This is configuration reuse,
not a downgrade to the backup's0.1.9 executable or a claim of measured HDR output.

#### Repair selected, applied changes, and owner concern

The selected repair uses AuxKC, which macOS links against both BootKC and
SystemKC. It keeps all seven **current** executables. This changes deployment;
it does not fix OpenCore to support ESP-only graphics loading. The owner later
challenged the architecture change. That concern remains open, and this state
must not be described as completion of an ESP-only implementation.

Prepared private package `out/890m-trace/step11-bootfix-20261015/` with current
bundles, panel-personality correction, candidate EFI config and SHA256 manifest.
Added `scripts/linux-fix-strix-graphics.sh` and
`scripts/macos-strix-graphics-bootstrap.sh`. The owner ran the prepared sudo
installer at13:07 local and returned its successful output. Re-reading Data and
ESP confirmed:

- `/Library/Extensions` contains current NVRM,NVRMEdpBL,NVRMFB,NVRMAGDC,NVAccel,
  StrixAccel0.1.15,StrixGOP0.1.10. All seven executable hashes match the session's
  ESP binaries. StrixGOP SHA256:
  `b64e1bdebaa4f459551fb83e2eae6502111750a5c1237eea5f4f0997d49ed315`;
  StrixAccel SHA256:
  `0ae72c09ef48855370f65a4ef7bda165113af997db4c7143c474b319c7d4631b`.
- Their seven Kernel/Add entries are disabled to avoid duplicate deployments.
  Their ESP bundles remain; ESP StrixGOP's personality is corrected too.
  StrixMetalGate0.1.1 remains enabled on ESP.
- The small stale AuxKC regenerated during the failed boot was preserved under
  the package's `data-before/` and removed from Data. New AuxKC construction is
  macOS work; none was built or validated by Linux.
- `/Library/LaunchDaemons/com.itlmt7925.graphics-bootstrap.plist` runs
  `/Library/StrixGraphicsFix/bootstrap.sh`. After15s it captures loaded versions
  and registry state. Missing drivers trigger one explicit `kmutil load
  --no-authorization` request for the current seven paths. It records status and
  logs, does not unload drivers, and does not reboot automatically.
- Data was unmounted after writes and remounted read-only. Other APFS mounts
  were removed before the write mount. Installed file hashes were checked before
  publishing the candidate ESP config.

Validation performed: shell syntax checks PASS; matching OpenCore1.0.9 ocvalidate
reports no issues; panel bounds/EDID checksum checks PASS; executable identity
7/7 and installed-bundle byte equality PASS. A flat symbol census is retained
as investigation data, not substituted for kmutil linking or a runtime pass.
No driver downgrade, HDR-off boot argument, WindowServer kill or reboot was
performed by this repair. No Apple graphics family was injected from the KDK.

**Next hardware gate:** boot macOS, allow60–90s, inspect
`/Library/StrixGraphicsFix/status` and `/Library/Logs/StrixGraphicsFix/<UTC>/`.
`REBOOT_REQUIRED` means the current collection was requested and another macOS
restart is needed; `DRIVERS_LOADED` only establishes kext presence, not visible
OLED/HDR success. Require StrixGOP0.1.10,StrixAccel0.1.15,framebuffer/pipe state,
stable WindowServer and owner-visible OLED/HDR. If still frozen, collect this
new boot's report/bootstrap evidence from Linux and continue from its actual
signature. The full boot-fix task is not yet runtime verified or complete.


### Step12 live verification, correct OLED workload selection, EDID override repair (2026-10-15)

Pulled `1b0d802` on macOS 15.8.1/24H32. Owner confirms HDMI + OLED desktop,
no HDR toggle on either display. Bootstrap status is `DRIVERS_LOADED`.
Live StrixGOP **0.1.10**, StrixAccel **0.1.15**, MetalGate **0.1.1**; accelerator
Gate PASS, one pipe, copied transactions increasing, zero validate failures.
The repaired AuxKC deployment is running; ESP-only graphics linking remains
unimplemented. No graphics bundle, EFI entry, boot argument or refresh mode was
changed in this session.

**Measurement correction:** System Profiler names the panel `Built-in OLED`,
but AppKit names it `Built-in Retina Display`. The old load tool silently fell
back to `NSScreen.main` on a failed name match. With HDMI as main, the collector
therefore measured HDMI twice and falsely reported that OLED CPU melt was gone.
Do not use the low-CPU result in `step11-0114-20261015T062040Z` as an OLED result.
Older name-based samples require checking the actual `screen:` line too.

Fixed `strix_present_load.swift` to resolve the built-in screen using the
NSScreenNumber / CGDisplayIsBuiltin identity, support exact `id:<decimal>`
selection and JSON screen inventory, and reject absent/ambiguous selections
instead of falling back. The verify collector enumerates actual IDs, records
per-screen before/after counters, and bases the pipe verdict on transactions
within the OLED load interval. Invalid screen selection exits3 in verification.
The macOS15-compatible identity API is retained; NSScreen.cgDirectDisplayID is
only available starting in macOS26.

Correct workload evidence: `out/890m-trace/step11-0114-20261015T062309Z/`.
External display1783179392: 60.0 ticks/s, WindowServer34.9%.
Built-in550528774:119.1 ticks/s, p99 interval11.52ms, max49.68ms,
WindowServer1405.6%. Display-link callbacks are scheduling evidence, not a
count of scanouts. Copied transactions rose to748, validate failures stayed0.
The new5s spindump reproduces `RunGPUDisplayPipe -> RunFullDisplayPipe ->
CombineLUTs -> CurrentHeadroom -> mutex lock/unlock`; the bottleneck has not
been removed by0.1.15's capability claims. No new unsupported capability or
private WindowServer patch was introduced.

**A concrete HDR blocker repaired on disk:** CoreDisplay's effective OLED EDID
was128 bytes while IODisplayEDIDOriginal and AppleBacklightDisplay contained the
new256-byte CTA/PQ EDID. The installed panel override at
`/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-4c83/DisplayProductID-419c`
still supplied the old128-byte EDID (SHA256
`6b7748c929b59e8d85ea150f47c600b21a8c7c9bc9cf31a0f0c89149c09e6d2c`).
Prepared a candidate from exactly one live StrixGOP AppleBacklightDisplay,
validated panel identity, both block checksums, extension count, CTA boundaries
and PQ static metadata, then installed it after backing up the original.
Only `IODisplayEDID` changed; name, IOGFlags and scale-resolutions are identical.
Backup suffix: `.pre-live-edid-20261015T062040Z`.
Installed override SHA256:
`8e5b2df7ce0756837eb9f66d73ba9d35c230c3ebbb31adf50d80d7472f3cd975`.
The new `tools/strix_edid_override.py` only prepares a candidate; it never installs
or restarts the session. Six focused tests cover preservation, identity,
checksums, malformed CTA, missing PQ and ambiguous/unrelated registry nodes.

Current WindowServer still caches the old EDID: HDR/EDR remains **pending a new
login or normal reboot**, not passed. Do not remove the CTA/HDR modes or revert
the framebuffer to hide the issue. No WindowServer restart was forced.
Advertising PQ still does not implement10-bit scanout, DCN colour programming
or HDR metadata transport. HDMI's own EDID was not modified; no claim that its
monitor supports HDR is made.

**Native/Metal foundation:** evidence in
`out/890m-trace/step05-metal-20261015T062039.031555Z/`.
Live S89N ABI1.1 passed six non-admin contract checks, including refusal of MMIO
reads. Admin FoundationRead passed: RCC512MiB, IP discovery version2,
PSP discovery status0x80000000. These prove fixed bootstrap register access,
not discovered GC IP, GPU VM, initialized engines, command submission or fences.
The strict890M Metal oracle still returns `ABSENT-target-Metal-device`.
Explicit NVIDIA control passes compute3x1024 words and offscreen triangle/clear
readback; `hardware_890m_pass=false`. Never relabel this control as890M acceleration.

Next gates: new-session effective OLED EDID must retain256 bytes, then recheck
HDR/EDR and run the ID-selected OLED benchmark with new stack evidence if it
still melts. GPU backend development separately needs verified IP-discovery
acquisition and GC11.5 dispatch before GPUVM/SDMA/GFX. RCC512MiB is larger than
the256MiB BAR0 aperture: the default discovery offset near the end of512MiB
cannot be read by blindly adding it to the BAR0 CPU address. The Linux memory
layout is not macOS ownership. macOS26 also still needs its own reviewed private
ABI profile; the24H32 runtime gate must not be bypassed.


### Step12 source-backed vendor classification patch (StrixGOP0.1.11)

Owner rejected another tracing-only reboot and repeated unchanged benchmarks.
Stopped workloads; removed both the newly prepared passive next-boot daemon and
the user autocollect agent. No scheduled benchmark/tracing job remains from this
session. Continue source inspection and implementation before another boot.

Read pinned Cobalt64 d6c9aedf8e6526a39e349b5886cbc8c7ddf77f65:
Navi48Accel.cpp, Navi48DisplayOps.h, Navi48Device.m, native_agdc_{pure,flow}.h,
and the relevant DisplayPipeGuard.cpp paths. Cobalt explicitly provides an
AMDRDNA4FB class because CoreDisplay classifies the framebuffer vendor by its
class name. Read local NVIDIA source at f5b5eaa (1.15.0 + GA403 AUX brightness):
NVRMFB publishes NVRMNVDAFramebuffer; NVRMAGDC supplies the plane-scaler descriptor
and refuses unimplemented colour stages. Neither source provides justification
for assuming our advertised colour stages implement a hardware renderer.
No third-party implementation was copied into this patch.

Confirmed the name contract against the actual24H32 CoreDisplay binary in a
separate debug helper process (no WindowServer attachment or modification):
`GetGPUVendorForFramebufferService` calls IOObjectCopyClass and CFStringFind for
Intel, AMD, AppleParavirt and NVDA; AMD returns4, NVDA8, unmatched names1.
`__WSMachineIsAMD_block_invoke` checks vendor4; CGXIsHDRSupported consults this
machine gate before the display HDR queries. Source/disassembly evidence:
`out/890m-trace/step12-source-patch/{vendor-hdr-headroom,machine-gate,hdr-gate}.asm.txt`.
This proves StrixGOPFramebuffer is misclassified; it does not prove correcting
that classification alone removes the CurrentHeadroom contention.

Patch0.1.11 publishes AMDStrixGOPFramebuffer, a no-state subclass of the original
StrixGOPFramebuffer. Existing superclass matching and casts retain their base;
the display implementation, memory ownership, pixel format, AUX backlight and
mode list are inherited. Info.plist selects the subclass. Also brought the
stale source kmod version0.1.7 into agreement with bundle/runtime0.1.11.
The EDID candidate tool accepts the two explicit Strix framebuffer classes.

Build passes and all422 imports resolve through declared providers. Candidate
SHA256:8552afc98a406f2b5b62ba2736c4cf94b30669ad75cf24dec473b60b1f73ac7b.
Deployment preserves the installed personality; only IOClass changes. This
combines the vendor identity correction with the already-installed256-byte
EDID override correction for one subsequent boot. GOP0.1.10 backup:
`/Library/StrixGOP-backup-0110-step12.kext`; AuxKC backup and install records in
the source-patch evidence directory. Live driver changes only after restart.

Acceptance after activation: actual class AMDStrixGOPFramebuffer, AMD vendor
classification, effective EDID256 bytes, existing OLED pipe/HiDPI/backlight,
then HDR gate and CurrentHeadroom behaviour. Physical HDR transport and native
890M Metal/GPU submission remain separate unfinished work. Do not label this
source correction as a verified performance or hardware HDR fix before runtime.

Installation verified: kmutil returned28; AuxKC lists StrixGOP0.1.11, installed
binary hash equals the reviewed candidate, selected class is AMDStrixGOPFramebuffer.


### Step12 reboot result: AMD class active, effective CTA EDID and EDR potential exposed (2026-10-15)

Boot EA06C1BF-ABDB-43B4-B571-D71C70FF9639. StrixGOP0.1.11 is live as
AMDStrixGOPFramebuffer; StrixAccel0.1.15 and MetalGate0.1.1 also loaded.
CoreDisplay's effective EDID and original EDID are both256 bytes. The installed
override still retains its scale-resolutions entry. NSScreen OLED EDR potential
is now **4.0** (before1.0), current1.0/reference0.0. HDMI remains potential1.0.
This establishes successful driver activation and exposure of the new EDID/EDR
capability in the combined vendor-name/EDID patch. It does not isolate the
contribution of each change or validate physical HDR output.

OLED pipe: Gate PASS, one pipe,111 copied transactions, zero validation
failures. Backlight failure counter0. WindowServer889 was running since13:37:17
and sampled at1.1% CPU during idle inspection. No workload or repeat benchmark
was run; idle CPU must not be compared with the prior1406% loaded result.
The filtered current-boot log contains HID assertions, not the previous
CGXMappedDisplayStart display crash signature. No new WindowServer report was
present at inspection. Initial WindowServer164 was followed by889 during boot;
this is not evidence that there were no startup restarts.

Current OLED mode is2880x1800 logical/backing at120Hz, whereas the preceding
session used1440x900 logical HiDPI at2880x1800 backing. The reason for the selected
mode is not yet established; do not silently change the owner's display mode.
Settings HDR toggle and owner-visible scaling remain owner checks. Current EDR1.0
means HDR content/headroom has not been demonstrated by this read-only snapshot.
890M still publishes MetalReady=false; native GPU submission remains unfinished.

Evidence: `out/890m-trace/step12-reboot-EA06C1BF/` contains edr.txt, displays.txt,
GOP/accelerator registry plists and the filtered current-boot WindowServer log.
No automatic tracing job, driver installation, mode change or benchmark was
performed in this reboot check.


### Step12 owner feedback: HDR toggle exposed, colour output incorrect; HDMI HDR gate absent

Owner confirms OLED Settings now offers HDR, but selecting it produces excessive
brightness and wrong colours. This is a failed colour-output result, not working
HDR. The prior patch opened capability discovery; native HDR output was never
implemented. Source confirms the missing contract: StrixGOP HDR twins only change
detailed timing.dynamicRange; getPixelInformation still describes XRGB8888,
getTimingInfo advertises8 bits/component, setDisplayMode only records currentMode
and performs no DCN programming. StrixAccel copies BGRA bytes or truncates l10r
10-bit channels to8 bits, without a transfer-function/gamut/output-metadata path.
Surface packing alone does not identify its transfer function. Do not assume a
PQ-to-SDR conversion is a native HDR fix or blindly apply it to every l10r frame.

A fresh read-only query now shows1440x900 logical /2880x1800 backing at120Hz:
HiDPI has been selected again since the first inspection. No mode change was
made by the agent. The initial post-reboot fallback remains recorded above.

Mi Monitor's real256-byte EDID checksums are valid and its CTA extended tag6
payload060501606004 advertises PQ; it is not an SDR-only EDID. Parsed capability
evidence: step12-reboot-EA06C1BF/edid-capabilities.json. Current NVIDIA source
f5b5eaa NVRMNVDAFramebuffer::getTimingInfoForDisplayMode zeroes the timing and
returns kIOTimingIDInvalid; setDisplayMode accepts only kModeId/depth0 and the
pixel path is8-bit XRGB. No HDR twin or supported dynamic-range timing is
provided there. Therefore HDMI HDR requires NVIDIA framebuffer/KMS output work
as well; do not edit its EDID to fake the missing driver contract.

Next implementation must supply actual output colour handling: for OLED,
validated DCN35 surface/bit-depth, transfer function/gamut and eDP HDR signalling
with coherent mode transitions; for HDMI, expose real HDR modes only alongside
NVIDIA KMS colour/output-metadata handling. Preserve the AMD classification and
EDID fixes. Do not request another reboot for unchanged code or equate the
Settings toggle/EDR potential4.0 with validated HDR output. No benchmark, driver
install, HDR toggle or display-mode change was performed for this feedback.

### Step13 performance first: CurrentHeadroom lock contention patched by a Lilu plugin (StrixHeadroom 0.1.0), 2026-10-15

Direction (owner): performance before HDR/colour/display names. HDR twins, CTA block, EDR potential and the HiDPI mode are
left exactly as they are; this step touches none of them.

Facts used (all from existing traces): OLED-only boot ~155 % WindowServer at 120 fps with no display pipe; with HDMI +
OLED the OLED goes through `RunGPUDisplayPipe -> RunFullDisplayPipe -> CombineLUTs -> Display::CurrentHeadroom` and 7794/7916
spindump samples are `std::mutex::lock` wait (about 24 dispatch_apply workers), 1150-1405 % CPU.

Disassembly (macOS 15.8 24H32 CoreDisplay extracted from the cryptex `os.dmg` dyld cache on Linux with `ipsw dyld extract`,
capstone; symbols from the image export list). `Display::CurrentHeadroom(qual=0)` at `0x7ff80408b2fc` (cache VA):
1. `if [this+0x460]==1` return `[this+0x45c]`; 2. `if [this+0x224]==1` return `[this+0x220]` (cache, no lock);
3. otherwise **lock `this+0x20`**; `EDRDisplay=[this+0x60]`; if present and `[EDRDisplay+0x11]` (headroom requested) go on to
   the full computation which stores `[this+0x220]` and sets `[this+0x224]`; else compute the default (1/`[this+0x170]` or
   a constant) and unlock WITHOUT caching. `+0x11` is only set by `CoreDisplay_XRPresent`, which nothing calls, so every
   call locks and recomputes.

Patch (`kexts/StrixHeadroom`, Lilu UserPatcher on the WindowServer process, CoreDisplay framework in the shared cache):
two exact byte patterns (unique in `__TEXT,__text`, 1 match each) replace the lock call (`0x445`) and both unlock calls
(`0x45c`, `0x4eb`) with a 5-byte NOP. The guarded region only reads fields or stores the same value and flag, so it is
safe without the mutex, and the headroom value itself is unchanged. No pattern match (other macOS build) = no patch.
Boot-args: `-strixhroff` disables, `-strixhrdbg` Lilu debug. Plugin has no state of its own.

Build/install: CI run 38695828531 (`scripts/build.sh StrixHeadroom` clones acidanthera/Lilu for headers + plugin_start.cpp;
undefined Lilu symbols resolved via OSBundleLibraries as.vit9696.Lilu). Copied to `/boot/EFI/OC/Kexts/StrixHeadroom.kext`
with a Kernel/Add entry after Lilu. Backup `config.plist.pre-strixheadroom`. Depends only on Lilu (BootKC) and kpi, so it
does not hit the SystemKC linking problem of the NVIDIA/Strix graphics kexts.

Acceptance (next boot with HDMI + OLED): `scripts/macos-strix-0114-verify.sh` (ID-selected OLED workload) — WindowServer
CPU must drop far below 1100-1400 %, ticks stay ~119/s; Lilu log line for `CoreDisplay` patch applied
(`log show --predicate 'senderImagePath CONTAINS "kernel"' | grep -i -E 'StrixHeadroom|patch'`). If WindowServer is still
hot, spindump again: the next stage is whatever replaces `CurrentHeadroom` at the top of the stack.
Unverified: the patch has not been run on hardware.

## Step14 NullMoth nvidia-macos-driver 2.0.0 evaluation (no code change, not downloaded)

Source: github.com/nullmoth/nvidia-macos-driver compare v1.15.0...v2.0.0 (read via API only; the 378 MB release tarball was not fetched).

- NMXGPU/NMXAccel (new in 2.0): amdgpu (FreeBSD drm-kmod via LinuxKPI on xnu, incl. AMD display core) + IOAcceleratorFamily2 for AMD, opt-in `nmxamd=1`. README itself says "not loaded on hardware yet"; mode switching not done, one XRGB8888 IOFramebuffer, and taking the GPU that drives the boot display resets its display engine. Not a fit for 890M (GC 11.5 / DCN 3.5, our panel is the boot display) -> do not adopt; no performance gain for the OLED+HDMI WindowServer path (that is the CurrentHeadroom lock, fixed by StrixHeadroom).
- NVRMFB: Info.plist match changed to NVIDIA-only (IOPCIPrimaryMatch 0x10de + class 0x03). Old match was IONameMatch display = also claimed the Intel/AMD slot (#119). Relevant to us: confirms NVRMFB must not claim 1002:150e; our NVRMFB build should use the same vendor match so it never takes the AMD slot.
- NVRMFB: EDID panel size -> imageWidth/Height (Mac shows real inches), ELD + hda-gfx for HDMI audio, boot raster = largest validated mode (second high-refresh monitor), BAR1 budget counts scanout. Cosmetic/robustness, optional.
- NVAccel: `nvaccel_vm_sticky` (surface keeps VRAM across deallocPhysical/allocPhysical) fixes black frames/windows black until drag. Candidate for our StrixMetalGate/NVAccel path if black windows appear on the HDMI (NVIDIA) head.
- NVRM security: go(pass>done) root-only, client quota per pid (4096) with reserve for uid<500, event-sleeper cap 256, bound fd range checks. No perf impact.

Verdict: performance-first priority is unaffected by 2.0; keep v1.x base + StrixHeadroom. Optionally cherry-pick the NVRMFB vendor-match and nvaccel_vm_sticky later if symptoms match. Reboot still pending to validate StrixHeadroom.

### Step14 NullMoth 2.0.0: fork synced, package verified, INSTALL = macOS side (2026-10-15)

* Fork `thanhnndev/nvidia-macos-driver` main was 116 commits behind, 0 ahead; synced with `gh repo sync` -> identical to upstream v2.0.0.
* Package `nullmoth-nvidia-2.0.0.tar.gz` (378 MB) downloaded to the Linux scratchpad, SHA-256 matches the release SHA256SUMS
  (`6122fef66b1413d90530d50a9b4a0194bc8f4bbe9bcfa1d873198cc34d772aed`). It is a `pkgroot/` with `install.sh`, 4 kexts
  (NVRM, NVRMFB, NVAccel, NVRMAGDC, all bundle version 0.1), GPUBundles, `Library/NullMoth`. NVRMEdpBL (ours) is not in it;
  its dependency `com.nullmoth.NVRM 0.1` is still satisfied.
* `install.sh` (root, on macOS) replaces only NVRM/NVAccel/NVRMFB/NVRMAGDC in `/Library/Extensions` and rebuilds the AuxKC with
  `kmutil create -n aux --repository /Library/Extensions`, so StrixAccel/StrixGOP/NVRMEdpBL already there are kept in the same
  AuxKC (the arrangement the macOS side repaired). `CHECK=1` = dry run that changes nothing. It also rewrites GPUBundles and
  `/Library/NullMoth`, and takes backups ("restore from $BK" in its messages). It does NOT touch the ESP config.
* Cannot run from Linux (needs kmutil). Not run yet. Steps for the macOS side:
  1. `gh release download v2.0.0 -R nullmoth/nvidia-macos-driver -p nullmoth-nvidia-2.0.0.tar.gz` (or curl), check the SHA-256 above, extract to an empty dir.
  2. `cd <dir>/pkgroot && sudo CHECK=1 bash install.sh` must end with `CHECK PASS (nothing changed)`.
  3. `sudo bash install.sh`, approve in Privacy & Security if asked, reboot.
  4. ESP NV* entries stay disabled (same bundle IDs as AuxKC). Do not re-enable them; the ESP 1.15 copies are now stale.
  5. After boot: `kmutil showloaded | grep -i -E 'nullmoth|strix'`, `scripts/macos-strix-0114-verify.sh` (StrixHeadroom), WindowServer CPU with HDMI+OLED.
* Risks: 2.0 NVRMFB changes the match to NVIDIA-only (good: it no longer claims the AMD slot) and 2.0 has a documented known issue "blank frames on the other display after a refresh change". Our Strix* kexts were built against 1.15 behaviour; if StrixMetalGate/NVAccel handshake changes, collect the log before touching anything.

### Step14 OLED-only now on the display pipe; StrixHeadroom did not patch; EDR request fixes the melt (2026-10-16)

Boot: OLED only, StrixGOP 0.1.11, StrixAccel 0.1.15, StrixHeadroom 0.1.0 loaded. Since the framebuffer identity fix
(47f2ce1) the OLED-only boot also uses the display pipe (`Transactions` 3195, `Copied` 3195, `Pipes=1`), so the OLED-only
case now melts too: WindowServer 1400-1650 % idle, window drag 28 ticks/s (p50 44 ms). Data: `out/890m-trace/step14-*`.

**StrixHeadroom 0.1.0 does nothing.** spindump still shows `CurrentHeadroom+334 -> std::mutex::lock` (the patched call).
The byte patterns do match live memory (checked in-process: CoreDisplay base + 0x3F2FC + 0x142), but Lilu's UserPatcher
reads the target binary from disk (`loadFilesForPatching` -> `FileIO::readFileToBuffer(path)`) to locate patch pages, and
since macOS 11 `/System/Library/Frameworks/CoreDisplay.framework/Versions/A/CoreDisplay` does not exist on disk (dyld
shared cache only). No lookup entries -> nothing patched. Release Lilu logs nothing about it.

**Userland fix, no patching.** The only writer of `gHeadroomRequested` / `EDRDisplay+0x11` is `CoreDisplay_XRPresent(bool)`.
SkyLight calls it from `WS::Displays::CoreDisplayManager::set_edr_present(float)` (`XRPresent(headroom > 1)`), reached
from `update_edr_request()` when the session has a headroom request (`session+0x1b0`) or a wants-HDR surface
(`session+0xc0`, `WSSurfaceSetWantsHDR`). A window with a `CAMetalLayer` (`wantsExtendedDynamicRangeContent`, rgba16F,
extended linear P3) opens such a request. Measured, same boot:

| state | WindowServer CPU | move 600x400 | move 1400x800 | anim | full-screen present |
|---|---:|---|---|---|---|
| no request | 1360-1650 % | 28-29 ticks/s, p50 14-44 ms, p99 75 ms | - | 119.8/s p99 9.2 | 119.5 fps p99 9.0 |
| request open | 140-170 % | 118-119 ticks/s, p99 13 ms | 118.6/s p99 13.5 | 119.3/s p99 13.2 | 119.6 fps p99 14.3 |

EDR stays off (`maximumExtendedDynamicRangeColorComponentValue` 1.0, potential 4.0), so no visible change. When the
request closes the melt comes back after the EDR hysteresis (~20-30 s). A transparent 1x1 hidden window is enough.

Permanent: `tools/strix_headroom_hold.swift` + `scripts/macos-strix-headroom-hold.sh install` (user LaunchAgent
`com.thanhnndev.strix.headroomhold`, KeepAlive, re-asserts on wake/screen change). Installed 2026-10-16.
Still open: the slight p90/p99 rise in the simple-animation cases with the request open (8.4 -> 10-13 ms), and the
remaining ~150 % idle WindowServer.

### Step15 macOS 26.7.1 (25G241) upgrade: boots, display dead because StrixAccel gate refuses Tahoe (2026-10-16)

Evidence (Data volume mounted ro on Linux, `Library/Logs/StrixGraphicsFix/20261016T0716*`, `private/var/log`):
* Tahoe reaches loginwindow (14:17); no kernel panic report. Userland noise: `bluetoothd` ExcUserFault loop (14:18-14:25).
* `kmutil load` of the AuxKC works on Darwin 25.6: NVRM, NVRMFB, NVRMAGDC, NVAccel, NVRMEdpBL (NullMoth **1.15**, Sequoia build), StrixGOP 0.1.11, StrixAccel 0.1.15 all loaded; StrixMetalGate 0.1.1, StrixHeadroom, StrixAmp, StrixProbe (ESP) load.
* HDMI head via NVRMFramebuffer is up (1920x1080 pixel info, NVAccel clients). The OLED (`AMDStrixGOPFramebuffer`, regID 0x100000486/0x100000461) has no pipe: CoreDisplay logs `Unable to find display pipe for IOFB service / regID`, then `Attempting to get capabilities from plane with no gamma`, `Can't run fallback without surface`, `set_device_transfer: can't set device gamma`, WindowServer calls `setup_virtual_framebuffers`, restarts 3 times (pids 202, 204, 715) = the stuck screen.
* Root cause: `StrixAccel: gate FAIL: OS build does not match reviewed profile macos15-24H32-x86_64-ioaccel485.2` (kernel log, both boots). The accelerator refuses by design, so no IOAccelDisplayPipe for the OLED (same symptom as Step04).
* Fix (StrixAccel 0.1.16): profile table with 24H32 and 25G241 (Darwin 25.6.0, xnu-12377.161.15.700.19~2, IOAcceleratorFamily2 487.4.4). Basis for accepting it: `tools/ioaccel_layout.py` + `ioaccel_gen_header.py` run on the Tahoe `SystemKernelExtensions.kc` (read from the mounted volume) produce a declaration header BYTE-IDENTICAL to the committed one (class names, slot order, vslot indices, instance sizes). Extracted profile: scratchpad `tahoe/profile-25G241.json` (EXTRACTED, not runtime-validated). Private-slot semantics and struct offsets (pipe+0x240, transaction layout) are NOT proven; the runtime gate still checks class sizes and pure-slot coverage.
* Not changed on purpose: StrixGOP, StrixMetalGate, StrixHeadroom (no OS-specific layout; they loaded).
* Known remaining Tahoe risks: NullMoth NV* are 1.15 (Sequoia-only); 2.0.0 is the build with macOS 26 support (see Step14 install steps). IONDRVFramebuffer still appears on Tahoe (the `Kernel/Block IONDRVSupport` entry did not stop it).

macOS side: after CI builds StrixAccel 0.1.16 (artifact), `sudo bash scripts/macos-strix-accel-install.sh` with the artifact in `build/StrixAccel.kext`, reboot, then collect `ioreg -rc StrixAccelerator -l | grep StrixAccel` (expect Gate PASS, ABIProfile macos26-25G241..., Pipes 1) and the same CoreDisplay log. Install NullMoth 2.0.0 NV* first if HDMI/NVAccel misbehave.

Step15 install (done from Linux, 2026-10-16 14:46, CI run 38868848326): `/Library/Extensions/StrixAccel.kext` on the Data volume replaced by 0.1.16 (hashes verified, root:wheel), old 0.1.15 + the stale `AuxiliaryKernelExtensions.kc` backed up to `~/ga403-logs/strixaccel-0.1.15-backup-20261016-144614/` and the AuxKC deleted, so `com.itlmt7925.graphics-bootstrap` (RunAtLoad) rebuilds it with `kmutil load` of the 7 bundles on the next boot (same flow as `linux-fix-strix-graphics.sh`). NullMoth 2.0.4 NV* are in `/Library/Extensions` (macOS-side `finish` ran 14:17), untouched. Expected next boot: `StrixAccel: gate` line says ok, `ioreg -rc StrixAccelerator -l | grep StrixAccel` shows Gate PASS + ABIProfile macos26-25G241, CoreDisplay stops logging `Unable to find display pipe`. If the screen is still dead, collect `/Library/Logs/StrixGraphicsFix/<newest>/` (bootstrap.log, display-log.txt, accel-after.txt) and the kernel log lines `(StrixAccel)`.

## Step16 (2026-10-16, Linux): Tahoe freeze triage + fq_codel kernel patch

- Boot 15:55 and 16:07 on 26.7.1 (25G241): StrixAccel 0.1.16 `Gate=PASS`, display pipe present (Step15 fix confirmed on disk logs).
- Only one panic found (`Kernel-2026-10-16-160737.panic`): `assertion failed: now >= *pkt_enq_time` (`classq_fq_codel.c:1127`), reached via `HoRNDIS::outputStart` -> `ifnet_dequeue` -> `fq_codel_dq`. Packet stamped on one CPU is dequeued with an earlier clock on another (TSC skew on AMD). The existing "Remove non-monotonic time panic" patches only cover thread_invoke/dispatch/quantum, not this site.
- Kernel (apv3 `/System/Library/Kernels/kernel`, 25.6): the assert is at 0xffffff8000629d1e, reached by `subq %rcx,%r9; jb` at 0x...629ca8. Pattern `48 8d 3d .. 48 8d 35 .. ba 67 04 00 00 e8` is unique (file off 0x429d1e).
- ESP config.plist: new Kernel/Patch "Strix | fq_codel_dq ..." (25.0.0-25.99.99, Count 1): replaces the panic block with `xor r9,r9; jmp 0x...629caa` (sojourn clamped to 0). Backup: `~/ga403-logs/config.plist.pre-fqcodel-*`.
- Not explained: first force-restart left no panic/stall log (likely a hard hang). Next: collect after reboot (`log show --last boot`, check whether the hang correlates with HoRNDIS/USB tether, Wi-Fi itlmt7925, or GPU), then iGPU perf (CurrentHeadroom re-derive for 25G241), Wi-Fi/BT branches.

## Step17 (2026-10-16, Linux): Tahoe iGPU lag triage, StrixAccel 0.1.17 diagnostics

Evidence (`/Library/Logs/StrixGraphicsFix/20261016T090740Z/display-log.txt`, boot 3 on 25G241):
* Gate PASS, `StrixAccel,Pipes=1`, 40 submits / 40 copies; but every frame (44x) CoreDisplay logs `Fallback GPU Display Pipe transaction submission failed` and ~300x `Attempting to get 3-channel gamma table capabilities from plane with no 3-channel gamma table support`. First full-frame copy 8.7 ms / 20 MB.
* Static read of 25G241 `IOAccelDisplayPipe::transaction_end` (SystemKernelExtensions.kc, 0x14bb0560): it returns/stores `0xe00002f0` (no txn), `set_transaction_args()` error, or `IOAccelDisplayPipeTransaction2::prepare()` error. `prepare()` (0x14baff8a) turns a false return of each plane resource's virtual `IOAccelResource2::prepare` (vtable +0x180) into `0xe00002be`; status is stored in the transaction at +0x58.
* `StrixResource` inherits Apple's `IOAccelResource2::prepare` (map -> freeToPrepareMapping). If that returns false for the OLED surface resource, CoreDisplay reports failure on every frame although StrixDisplayPipe still copies (async worker), which fits "works but lags".
* 0.1.17 logs `status(+58)` of the first 4 transactions at submit time (`txn N submit: ... status(+58) X`). Next boot answers: 0 => failure is elsewhere (user-client wait/end return), 0xe00002be => resource prepare path (override `StrixResource::prepare` to return true and skip mapping), other => set_transaction_args.
* LaunchAgent `com.thanhnndev.strix.headroomhold` exists in the user's LaunchAgents; whether it runs on 26.x is not yet checked.

## Step18 (2026-10-16, macOS 26.7.1 25G241): root cause of the failed pipe transactions confirmed in the 487.4.4 disassembly; StrixAccel 0.1.18 sets config bit 21 so resources allocate as UMA sysmem

Live baseline this boot (0.1.17, boot since 16:44): every submit logs `status(+58)=0xe00002be` (`StrixAccel: txn N submit`), WindowServer ~124 % CPU idle.
Kernel-log counts for the boot: `IOAccelTask::freeToAllocGPUAddress: failed to alloc GART space ... Needed 0 bytes, used 20738048, size 17179865088. vram=1` x50040,
`IOAccelResource2::prepare(): failed to allocate GPU virtual address for mapping. resType=0xc0` x50040,
WindowServer `Fallback GPU Display Pipe transaction submission failed` x25108, `3-channel gamma table capabilities` x402178.

Disassembly (`tools/kc_disasm.py` on `/System/Library/KernelCollections/SystemKernelExtensions.kc`, IOAcceleratorFamily2 487.4.4):

* `IOGraphicsAccelerator2::start` (0x14b9f752) calls `initializeConfigStructure()` (0x14b9fccf), then `leaq 0xc88(%r14), %r12`
  (0x14b9fcd4) and `callq *0x9b0(%rax)` (0x14b9fce4) = `populateAccelConfig` (pure slot 310). The config struct therefore
  starts at `accel+0xc88`, and `accel+0xc90` is `cfg+0x08`.
* `IOAccelResource2::allocMemory` (0x14b88918) reads `0xc90(accel)` and `btl $0x15` (0x14b8893f-0x45). **Bit 21 set** -> jump
  to 0x14b889f2: it aligns `resource+0xc8` up to page size and allocates through `IOAccelSysMemory::withOptions`
  (call at 0x14b88a9e or the 0x363 fallback at 0x14b88b22; the option struct in the first branch is
  `{0xAAAAAAAA00000363, 0}` via the object at `accel+0xb60`). Mode is 0x363 unless `cfg+0x08` bit 30 picks 0x33; bit 26 of
  `cfg+0x08` and bit 30 of `resource+0xc` only choose between the two sysmem sub-paths. **Bit 21 clear** -> `callq *0x8c0(%rax)`
  (0x14b889b1) = allocate-vidmem path -> `StrixVidMemory` with no backing: `getLength()` (vtable +0x168) returns 0, which is
  exactly the logged "Needed 0 bytes".
* The rest of the family agrees that bit 21 = "GPU-addressable system memory (UMA)": `start` does `cfg+0x64 |= 0xa`
  (0x14b9fd16), clears `cfg+0x14` bit 2 (0x14b9febb-0x14b9fed0), creates `IOAccelBufferMemoryDescriptorPool2` at
  `accel+0xc30` (0x14ba00d0-0x14ba00fc) and sizes the wired sysmem budget `accel+0x340 = min(3/32 * total, 768 MiB)` instead
  of the 32 MiB default (0x14ba09ce-0x14ba09f0; total from `sysctlbyname("hw.memsize")`, 0x14ba075e-0x14ba0776, 512 MiB
  fallback). `IOAccelResource2` init also skips `orl $0x10000, resource+0xc` when bit 21 is set (0x14b861bc).
* Caps that keep `withOptions` usable: `getMaxSingleSysMemorySize()` (slot 305, 0x14ba5158) = 3/4 of
  `calcMaxGPUPhysicalMemoryBytes(total)` (slot 311, 0x14ba5e5c) = max(total/3, 64 MiB), so >= 48 MiB — a 2880x1800x4 =
  20.7 MB surface fits; `createBufferMemoryDescriptorInTaskWithOptions` (slot 293, 0x14ba4382) forwards to the kernel task.
* `IOAccelResource2::map()` (0x14b8bc70): for resource byte `+0x14 == 0xc0` (the logged resType) it uses `resource+0x88` = the
  `allocMemory` result and builds the `IOAccelMemoryMap` through the memory's vtable +0x138. `IOAccelTask::freeToAllocGPUAddress`
  (0x14b9e47c) only failed because that map's `getLength()` (vtable +0x168) was 0; the task's GART space is the 16 GiB
  `IORangeAllocator` passed in `StrixTask::setup`.

Fix in 0.1.18 (`kexts/StrixAccel/StrixAccel.cpp`): `cfg+0x08` 0x480000 -> 0x680000 (adds bit 21). Expected after reboot:
no "failed to alloc GART", no "failed to allocate GPU virtual address", `status(+58)=0`, no "Fallback GPU Display Pipe
transaction submission failed", lower WindowServer CPU. Not addressed here: the ~400k "3-channel gamma table capabilities"
lines.

Install (macOS side, from this boot): built with `bash scripts/build.sh StrixAccel` (x86_64 kext bundle, undefined-symbol set
byte-identical to 0.1.17). 0.1.17 backed up to `~/efi-audit/strixaccel-backup/StrixAccel.kext.20261016T171014` (hash
6aff2950...). `/Library/Extensions/StrixAccel.kext` replaced (hash 552358d4...), `kmutil load --no-authorization -p` = rc 28;
`kmutil inspect` shows the on-disk `/Library/KernelCollections/AuxiliaryKernelExtensions.kc` now maps
com.itlmt7925.strixaccel 0.1.18. Running boot still has 0.1.17 (verified); WindowServer never killed, reboot is the user's.

## Step19 (2026-10-16, Linux): the 16/10 panics are the HoRNDIS/fq_codel assert, not the iGPU; the ESP fq_codel patch verified byte-for-byte

The owner reported "the iGPU panics". It does not. Both `Kernel-2026-10-16-*.panic` reports are the same
**network** assert, reached entirely outside the graphics stack:

```
panic(cpu 20/4 ...): assertion failed: now >= *pkt_enq_time
  file: xnu/bsd/net/classq/classq_fq_codel.c, line 1127 @uipc_socket.c:8286
  _fq_codel_dq+0x946 / +0x1e5 -> _fq_if_flow_feedback -> _fq_if_dequeue -> _ifclassq_dequeue
  -> _ifnet_dequeue -> IONetworkInterface::dequeueOutputPackets
  -> com.joshuawise.kexts.HoRNDIS(9.3) HoRNDIS::outputStart        (USB tether)
Kernel Extensions in backtrace: IONetworkingFamily(3.4), HoRNDIS(9.3)
```

None of the four panics on this install involves StrixGOP / StrixAccel / IOAcceleratorFamily2 /
AppleGraphicsDeviceControl / amdgpu (the two 12/10 ones are IO80211Family + AppleSkywalk). The trigger is
HoRNDIS (ESP-injected, `/boot/EFI/OC/Kexts/HoRNDIS.kext`, Kernel/Add enabled) on AMD TSC skew: a packet
timestamped on one CPU, dequeued with an earlier `now` on another. This is the site Step16 patched.

Verification this session (System volume mounted ro at `/mnt/macos-sys`, `vol=3`):

* `/mnt/macos-sys/System/Library/Kernels/kernel` LC_UUID `1291D44A-C0CD-3AC7-A9E4-CA2749B33959`
  **equals the panic's Kernel UUID**; `osrelease` string is `25.6.0`. Right build.
* Applying the config's `Find` under its `Mask` (`3-byte "48 8d 3d" anchor, then wildcard the two rip
  displacements`) yields **exactly one** match: fileoff `0x429d1e` = VA `0xffffff8000629d1e`:
  `lea rdi,[file]; lea rsi,["now >= *pkt_enq_time"]; mov edx,1127; call panic`. `mov edx,1127` is the
  source line, so it is unambiguously the assert.
* `objdump` of the site: `mov %r8,%r9; sub %rcx,%r9; jb 0x629d1e` (taken when `now < pkt_enq_time`), and
  `0x629caa` is the next normal instruction. The patch `Replace` = `xor r9,r9; jmp -0x79` lands on that
  boundary, so the taken branch clamps the sojourn to 0 and continues instead of panicking. Leftover bytes
  after the 20-byte Replace (the old `call` rel32 tail) are unreachable. Safe.
* ESP OpenCore is 1.0.8 (built from the same cached `oc-src`); its Kernel/Patch schema declares
  `Mask`/`ReplaceMask` (`OcConfigurationLib.c` lines 340/344) and `DataPatcher` matches with
  `(Data[i] & Mask[i]) == Find[i]`. MinKernel `25.0.0` / MaxKernel `25.99.99` covers Darwin `25.6.0`.

Conclusion: the patch as it stands in `config.plist` is correct and will stop this panic. It did not stop
the 16:45 one because the live `config.plist` was rewritten **after** that panic (ESP mtime postdates
16:45), i.e. that boot ran an earlier, not-yet-byte-correct version. Runtime proof (phone tethered, no
panic) is still pending. HoRNDIS itself is not the thing to patch: the assert is in xnu's classq; if USB
tethering is not needed, disabling the ESP Kernel/Add `HoRNDIS.kext` entry removes the trigger outright.

Boot 17:25 local, same day (0.1.18 live), for the graphics side: Gate PASS, Pipes 1,
Transactions=Copied=46, `NoPlane=0`, `ValidateFail=0`, ABIProfile `macos26-25G241-x86_64-ioaccel487.4.4`;
`failed to alloc GART space` and `failed to allocate GPU virtual address` are **0** (bit 21 fix held). Still
present: 192 `Fallback GPU Display Pipe transaction submission failed` in the first minute
(`status(+58)` 4x `0`, 4x `0xe00002be`), so the UMA resource change fixed the GART/virtual-address failure
but not every submit. This is again not a panic. `bluetoothd` `ExcUserFault` (5 reports) is userland.

## Step20 (2026-10-16/17, Linux): the remaining pipe-transaction status is `IOAccelResource2::prepare()`; StrixAccel 0.1.19 reports success for it

The boot-17:25 log (`/Library/Logs/StrixGraphicsFix/20261016T102547Z/display-log.txt`, filtered to the new
boot: timestamps >= 17:25:45) has 47 `Fallback GPU Display Pipe transaction submission failed` lines, all in
the first ~9 seconds (17:25:54–17:26:03), and every logged submit carries `status(+58) = 0xe00002be`
(txn 1–4; the diag only printed the first 4). 0.1.18 therefore removed the GART/virtual-address storms but
the transaction status is still non-zero.

Where `0xe00002be` comes from, in the 487.4.4 disassembly (SKC, `tools/kc_disasm.py`):

* `IOAccelDisplayPipeTransaction2::prepare()` (0x14baff8a) walks the transaction's planes
  (`[txn+0x38]`, 0x70 bytes each; `plane+0x10` deviceCache[2], `plane+0x20` IOSurface[2],
  `plane+0x30` resource[2] — layout confirmed by `set_transaction_args` 0x14bb088b-0x14bb08ad), and for each
  plane resource does `mov rax,[rdi]; call [rax+0x170]`; a zero return loads `r14d = 0xe00002be`
  (0x14baffd9). It returns r14d.
* `IOAccelDisplayPipe::transaction_end()` (0x14bb0560) then stores that at `txn+0x58` (0x14bb061e) and
  aborts the transaction, which is the status CoreDisplay reports as the fallback.
* Slot arithmetic: an object's vptr points at its **first virtual**, so `[vptr+0x170]` is virtual #0x170/8 =
  **46 = `IOAccelResource2::prepare`**; read through the vtable *symbol* (which starts with
  offset-to-top/typeinfo) the same entry is at `+0x180`. Apple's own software accelerator agrees:
  `AppleParavirtResource::prepare()` (0x148a6038) tail-calls `[__ZTV16IOAccelResource2+0x180]`, and
  `AppleParavirtResource` overrides exactly slots 46/47 (`prepare`/`complete`) plus 40/51/55/57/58/60-67.
* `IOAccelResource2::prepare` (0x14b8befa) fails when `IOAccelResource2::map()` returns 0; the paths that
  matter are the `freeToPrepareMapping` fallback at 0x14b8c007-0x14b8c016 -> 0x14b8c138 ("failed to wire
  down VRAM size=... trying to fall back to system mem", the message Step18 saw) and the `map()` retry at
  0x14b8c1d1.

Fix in 0.1.19 (`kexts/StrixAccel/StrixAccel.cpp`): override `StrixResource::prepare()` (slot 46).

* It calls the family's implementation first, so the real mapping still happens;
* it logs the first 6 results, and on a failure the resource's `resType(+0x14)`, `flags(+0xe)`,
  prepared-count `(+0x28)`, `map(+0x40)` and `mem(+0x88)`, which is what will say *why* `map()` failed if it
  still does;
* with the new live tunable `StrixAccel,Tune,ResOk` (**default 1**) a failed prepare is reported as success
  and the family's prepared count at `this+0x28` is advanced the way the family itself does at 0x14b8bf76,
  so the family's `complete()` stays balanced. This is sound here because the pipe presents by copying the
  IOSurface into the GOP raster on the CPU and never reads a resource's GPU address. Set
  `StrixAccel,Tune,ResOk 0` to get the raw family result back.
* Counters so the next boot answers the question without another disassembly round: `StrixAccel,Res,Prepare`,
  `StrixAccel,Res,Forced`, and `StrixAccel,Txn,BadStatus` (`txn+0x58 != 0` at submit time — the exact
  condition CoreDisplay logs as a fallback). The submit diagnostic now covers the first 12 transactions.

Verification on the next boot: `StrixAccel,Res,Forced > 0` and `StrixAccel,Txn,BadStatus == 0` (or at least
far below the 47 above) with no `Fallback GPU Display Pipe transaction submission failed` after the first
seconds; if `Forced > 0` but `BadStatus` stays high, the zero status is not coming from the plane resource's
`prepare()` and the `StrixAccel,Res,Prepare` line's field dump is the next evidence.

Build note: a kext cannot be linked on Linux (`ld64.lld` warns "Option `-kext' is undocumented" and then
requires `main`, so it emits neither MH_KEXT_BUNDLE nor the undefined-symbol kext link). `clang++ -target
x86_64-apple-macosx12.0 -mkernel ... -fsyntax-only`/`-c` works against `build/MacKernelSDK`, so source
changes can be compile-checked here; the real build is CI (`build.yml` builds `StrixAccel` and uploads the
`kexts` artifact).

### Step20 build and install (2026-10-17, Linux)

* CI: pushed `ea62cb5` (source + Info.plist + this Step20 + the handoff), `gh workflow run build.yml --ref
  research/890m-cobalt64` -> run **38994889099 success**. Artifact `kexts` -> `build/StrixAccel.kext`:
  `CFBundleVersion 0.1.19`, `Mach-O 64-bit x86_64 kext bundle` (`filetype 0xb` MH_KEXT_BUNDLE), 180696 bytes,
  `sha256(Contents/MacOS/StrixAccel) = a212b978f35933d6f3b809ec2eccaaa7f98092a7cd8d90621f45eba0d31c6d53`;
  no `__cxa`/`atexit`/RTTI undefined symbols; strings carry `StrixAccel,Tune,ResOk`, `StrixAccel,Res,Forced`,
  `StrixAccel,Txn,BadStatus`, `res prepare: family returned`. (The artifact's `StrixGOP.kext` is 0.1.11, the
  version already installed, so nothing else needed to change.)
* 0.1.18 backed up: `/boot/EFI/OC/Kexts-backup/StrixAccel.kext.0.1.18-20261017T093234` plus the Linux
  scratchpad. Its `sha256(Contents/MacOS/StrixAccel) = 552358d460adc569b96c11794a2a2ae01cd7a25d7e974977f747502f42325c27`
  is the hash Step18 recorded for 0.1.18, so the backup is the right build.
* Data volume mounted from Linux with `mount -t apfs -o readwrite,uid=1000,gid=1000,vol=0 /dev/nvme0n1p4
  /mnt/macos-data`. Note for next time: the plain VFS `rw` is not enough for linux-apfs-rw — without the
  fs option `readwrite` it logs `APFS ...: experimental writes disabled to avoid data loss` and mounts `ro`.
* Wrote: `/Library/Extensions/StrixAccel.kext` replaced with the 0.1.19 bundle (re-verified
  `sha256 = a212b978...` after the copy), and the macOS working copy's
  `~/develop/projects/ga403wm-hackintosh/build/StrixAccel.kext` staged with the same bundle so
  `scripts/macos-strix-accel-install.sh` finds it. No other file touched.
* The final macOS-side step stays manual, because the Linux APFS mount maps every file to uid 1000:
  `cd ~/develop/projects/ga403wm-hackintosh && sudo bash scripts/macos-strix-accel-install.sh` (it does
  `chown -R root:wheel` / `chmod -R go-w` and `kmutil load --no-authorization -p`, rc 28 = AuxKC rebuilt,
  reboot required). ESP `Kernel/Add StrixAccel.kext` stays disabled and its ESP stash is still 0.1.15: left
  untouched deliberately.

## Step21 (2026-10-17, Linux): the 17/10 freeze is a Wi-Fi panic, 0.1.19 was still not loaded, and what the failing transaction actually asks for

* The freeze ("use it 1–2 min → hard reset") is a **Wi-Fi** panic, not the iGPU: `Kernel-2026-10-17-093407.panic`,
  page fault at uptime 216.8 s, a store 1 byte past a 512-byte `data.kalloc.512` element inside
  `IO80211BSSBeacon::setBeaconDataFromMsg + 0x2c`, reached from `IO80211Glue::processPendingEventQueue` →
  `WCLMngFrameRouter::scanResultEventHandler` → `WCLScanCacheStore::updateOrAddBeacon` →
  `IO80211ScanCacheStore::updateScanCache`. No graphics kext anywhere in the stack; that boot's own evidence
  (`/Library/Logs/StrixGraphicsFix/20261017T023410Z/`) has `StrixAccel,Transactions = 0`, `Copied = 0` and
  zero `Fallback`/gamma lines. Handed to the Wi-Fi track; the 890M work is unaffected.
* 0.1.19 was **not** running in that boot, which is why nothing changed: `loaded-before.txt` lists
  `com.itlmt7925.strixaccel (0.1.18)` (AuxKC address range), ioreg `StrixAccel,Version = 0.1.18` with no
  `Tune,ResOk` / `Res,Prepare` / `Res,Forced` / `Txn,BadStatus`, and
  `/Library/KernelCollections/AuxiliaryKernelExtensions.kc` still has mtime 17:10 16/10 with no
  `StrixAccel,Tune,ResOk` string (`strings | grep -c` = 0). `/Library/Extensions/StrixAccel.kext` is 0.1.19,
  but macOS loads the AuxKC, so the rebuild is still pending on the macOS side:
  `sudo bash scripts/macos-strix-accel-install.sh` ends with `kmutil load --no-authorization -p <kext>`
  (`rc 28` = AuxKC rebuilt, reboot required).
* What the failing transaction actually asks for — CoreDisplay's own `DisplayPipeState` dump for the first
  rejection (17:23:04.996, the earlier boot of the same log window):
  ```
  Plane Index: 0
  Source Color Space: (kCGColorSpaceICCBased; kCGColorSpaceModelRGB; Built-in OLED 120 Hz)
  Rotation Angle: 0 degrees
  Matrix: [1 0 0][0 1 0][0 0 1]
  LUT: R - [0..0.501961..1] with 256 entries    (same G, B)
  LiT: R - [0..0.5..1] with 3 entries           (same G, B)
  Display Pipe Operations:
      Dirty  Fetch        - Pipe
      Dirty  Scale        - None
      Dirty  Rotate       - None
      Dirty  Linearize    - GPU
      Dirty  CSC          - GPU
      Dirty  System Gamma - Unknown
  ```
  So the pipe is only asked to **fetch**; linearization and CSC are already done on the GPU and handed over as
  a 256-entry LUT + 3-entry LiT per channel. `Attempting to get 3-channel gamma table capabilities from plane
  with no 3-channel gamma table support` directly precedes every rejection on the same plane, and
  `System Gamma - Unknown` looks like its consequence: WindowServer asks the plane for the 3-channel gamma
  table capability, does not get it, and falls back. 27965 such lines accumulate per boot (log spam + `logd`
  + disk), so it is worth removing even though it is not itself fatal.
* AGDC counters, early snapshot, 0.1.18: boot 17:25 `Commands 94, CapServed 28, CapType 0x8000, Refused 38`;
  panic boot `Commands 9, CapServed 0, Refused 2 (0x3,0x941)`. Both have `NoFramebuffer = 1` and
  `Tune,Caps = 13327 = 0x340f`, so at least one capability query was answered while `framebuffer() == NULL`,
  while `CapServed` is non-zero in the boot that actually renders.
* Log-window gotcha: `display-log.txt` is a time-window capture, so it mixes entries from the *previous* boot.
  For `20261016T102547Z` the current boot is everything with `timestamp >= 17:25:45`: **47** `Fallback ...` +
  **329** gamma lines in ~19 s; the other 1645 / 27965 belong to the 17:23 boot inside the same window. Always
  filter by the boot's start before counting.
* Next trace (needs the System volume mounted read-only): locate `3-channel gamma table capabilities` in the
  kernelcache vs in CoreDisplay, then find which query the plane fails to answer (candidate:
  `IOAccelDisplayPipe::copyCapabilities()` slot 282, or the `kCmdFbExtCap` 0x711 type `0x2` path when
  `fbIndex != 0`).

## Step22 (2026-10-17, Linux): the capability entries CoreDisplay reads back — Apple's own AMD numbers, and why 0.1.20 does not flip them blindly

System volume mounted read-only at `/mnt/macos-sys`, `vol=3` (Tahoe 26 keeps
`System/Library/KernelCollections/{System,Boot}KernelExtensions.kc`; `CoreDisplay.framework` has no on-disk binary,
so the string that WindowServer logs is userspace/dyld-cache only).

* `strings` in `SystemKernelExtensions.kc` has `Table - One-Channel`, `Table - Three-Channel`, `Table - Three Channel`,
  `Table - One Channel`, `Piece-Wise Linear`, `ICC Parametric Type 3`, `Fixed Format`, `Configuration ID` — the AGDC
  enums. `3-channel gamma table capabilities` is *not* there, confirming the log line comes from CoreDisplay.
* `kc.xrefs()` on those literals found two independent Apple implementations, and their jump tables decode the enums
  (`tools/kc.py` + Capstone):
  * `AMDRadeonX6000_AmdAgdcServices::stringifyGammaType(AGDCGammaType_t)` @0xbf792c4
  * `stringifyDegammaType(AGDCLinearizationType_t)` @0xbf7923c, `stringifyFbCapabilityType(...)` @0xbf790b8
  * `AtiDeviceControl::getGammaTypeString` @0x13b6eba0, `getLinearizationTypeString` @0x13b6eab0 region
* Resulting enums (both implementations agree):

  | `AGDCGammaType_t` | value | `AGDCLinearizationType_t` | value | `AGDCFBExtendedCapabilitiesType_t` (query type) | value |
  |---|---|---|---|---|---|
  | Configuration ID | 1 | Configuration ID | 1 | CSC | 1 |
  | Fixed Format | 2 | Fixed Format | 2 | Gamma | 2 |
  | Table - One Channel | 8 | Table - One-Channel | 4 | Linearization | 4 |
  | **Table - Three Channel** | **0x10** | Table - Three-Channel | 8 | Pipeline Scaler | 8 |
  | Piece-Wise Linear | 0x20 | Piece-Wise Linear | 0x10 | Plane Scaler | 0x10 |
  |  |  | ICC Parametric Type 3 | 0x20 | Rotation | 0x20 |
  |  |  |  |  | Inline Buffer | 0x40 |
  |  |  |  |  | Queue | 0x80 |
  |  |  |  |  | Closed Caption Regions | 0x100 |
  |  |  |  |  | Mirroring | 0x200 |
  |  |  |  |  | Format Convert | 0x400 |
  |  |  |  |  | HDR Scaler | 0x800 |
  |  |  |  |  | Plane CSC | 0x1000 |
  |  |  |  |  | 3D LUT | 0x2000 |
  |  |  |  |  | Pixel Processing | 0x4000 |
  |  |  |  |  | Cursor | 0x8000 |

  So every `kFbCap*` in `StrixAgdc.h` is right, and `gCapMask = 0x340f` claims CSC + Gamma + Linearization + Pipeline
  Scaler + Format Convert + Plane CSC + 3D LUT.
* `getFbExtendedCapability(AGDCFBGetExtendedCapability_t*)` @0xbf74dd4 is Apple's dispatcher: request layout
  `+0x00 fb/path index (byte), +0x04 type (dword), +0x08 count (out), +0x0c entry[8]`, each entry `0x32c`; the reply for
  the queried type comes from `getFbCapabilityForCsc` (inline for type 1), `ForGamma` (type 2), `ForDegamma` (type 4),
  `ForScaler` (type 0x10), `ForCursor` (type 0x8000); anything else returns `0xe00002c7`. Entry field layout read
  straight off Apple's stores: `+0x00 flags, +0x04 plane mask (u64), +0x0c update period (float), +0x10 type,
  +0x14 fixed format, +0x18 configuration id, +0x20 min (float) / pixel format (CSC), +0x24 max (float) / min (CSC),
  +0x28 max table size / max (CSC)`.
* Apple's own entries (the numbers to match):
  * CSC: `flags 0x80005`, plane mask 1, `type 8`, pixel format `0x50005`/`0x70007` (or +0x1000000 for ≥3 bit depths),
    min `-1.0`, max `1.0`, count 1.
  * Gamma: `flags 0x88005`, plane mask 1, `type 0x10` (Table - Three Channel), min `0.0`, max `1.0`,
    max table size from the GPU, **count 2** (two 0x32c segments).
  * Degamma: `flags 0x80005`, `type 1` (Configuration ID) + configuration id at `+0x18`, max table size 1, count 2.
  * Scaler: `flags 0x80004`, plane mask 0, `type` 0.
* What we have been sending since 0.1.14: `flags 0x80004` and `type 1` for every claimed type. WindowServer's
  evidence that this matters: `Attempting to get 3-channel gamma table capabilities from plane with no 3-channel
  gamma table support` (28294 lines in a long boot), `Attempting to get capabilities from plane with no gamma`
  (91), and `GetThermalCompensationAttributes: can't get framebuffer {red,green,blue} gamma scaling factor on port N
  (e00002ce)` — the last one is our `0x3`/`0x941` refusals (`e00002ce` = unsupported).
* **Why 0.1.20 does not just switch `gCapGammaType` to 0x10**: `StrixAccel,Txn,GammaSeen = 0` in all 12 logged boots
  (0.1.16 → 0.1.18) and the transaction dumps say `Dirty Regamma - GPU`, `Linearize - GPU`, `CSC - GPU`,
  `System Gamma - Unknown` — CoreDisplay currently bakes every colour stage itself and only asks this pipe to
  `Fetch`. Reporting a 3-channel gamma table would move the gamma stage *into* the pipe, and `StrixDisplayPipe`
  copies the surface to the GOP raster without applying any table, so the panel would show un-gamma-corrected
  pixels. The claim therefore has to be A/B tested, not flipped.
* 0.1.20 (this step) adds the levers and nothing else behavioural: boot-args `strixgammatype`, `strixgammaflags`,
  `strixcsctype`, `strixcscflags`, `strixlintype`; live tunables `StrixAccel,CapGammaFlags`, `CapCscType`,
  `CapCscFlags`; counters `StrixAccel,AGDC,Cfg{Flags,GammaType,GammaFlags,CscType,CscFlags}`; and the served-cap log
  line now prints the entry flags/type it actually wrote. Defaults stay at today's values (`type 1`, `flags 0x80004`)
  so a 0.1.20 boot is byte-for-byte the 0.1.19 behaviour plus counters.
* A/B procedure (no rebuild, config lives on the ESP and is editable from Linux): add
  `strixgammatype=16 strixgammaflags=0x88005` to the boot-args, reboot, then compare
  `grep -c '3-channel gamma table capabilities'`, `StrixAccel,Txn,GammaSeen`, `AGDC,CfgGammaType`, the
  `AGDC: 0x711 type 0x2 served ...` line and the on-screen colours. If the spam stops and gamma tables arrive but
  the picture washes out, the next step is to apply the LUT/LiT in the copy path (a 3×256 LUT lookup per pixel) —
  that is the real colour-pipeline win this discovery unlocks.

Install of the 0.1.20 build (same day, Linux): CI run **38997096119 success** -> `build/StrixAccel.kext` version
0.1.20, MH_KEXT_BUNDLE, 180960 bytes, `sha256(Contents/MacOS/StrixAccel) = 1ad3ab12cd6c867a8d84ab69aab7cf522d8bc566df876f166ae98b526ab8cd13`,
0 `__cxa`/`atexit` undefined symbols. 0.1.19 (`a212b978...`, never loaded) backed up to
`/boot/EFI/OC/Kexts-backup/StrixAccel.kext.0.1.19-<ts>`; 0.1.20 written to `/Library/Extensions/StrixAccel.kext` and to
the macOS working copy's `build/StrixAccel.kext` (sha256 re-verified after both copies) plus an ESP copy at
`/boot/EFI/StrixAccel-0.1.20.kext` as a fallback install source. The AuxKC is still 17:10 16/10 (0.1.18) until
`sudo bash scripts/macos-strix-accel-install.sh` runs on macOS (kmutil rc 28 = rebuilt, reboot).

The AuxKC itself cannot be built off-macOS (Mach-O fileset + prelink info, `kmutil`/`kernelmanagerd` only), but it does
not have to be: `scripts/linux-install-strixaccel.sh` installs the bundle from Linux (`rw,readwrite` mount **without**
`uid=`/`gid=` so `chown -hR 0:0` lands in the catalog as root:wheel, dirs 755 / files 644 / `Contents/MacOS/<name>`
755, sha256 compared against the source), backs up the replaced bundle and the old collection into
`/boot/EFI/OC/Kexts-backup/`, then removes
`/Library/KernelCollections/AuxiliaryKernelExtensions.kc`. macOS relinks that collection from `/Library/Extensions` at
the next boot, so the Linux route costs one extra boot (`boot 1` relinks, the bootstrap agent logs `REBOOT_REQUIRED` if
it runs before that; `boot 2` maps the fresh AuxKC) — same mechanism `linux-fix-strix-graphics.sh` has used
("Next macOS boot rebuilds/loads AuxKC").

Mount gotcha seen here: the `readwrite` mount failed with `mount: WARNING: source write-protected, mounted read-only`
while `/mnt/macos-sys` and a stacked `/mnt/macos-data` were still mounted — linux-apfs-rw allows only **one** mount of
the container when writing, and the refusal surfaces as a read-only mount. Unmount every target of
`findmnt -rn -S /dev/nvme0n1p4 -o TARGET` first; then `mount -t apfs -o readwrite,uid=1000,gid=1000,vol=0
/dev/nvme0n1p4 /mnt/macos-data` works (verified: `touch` succeeded).


## Step23 (2026-10-17, macOS 25G241): the per-frame GART failure is a 0-byte IOSurface device cache; StrixAccel 0.1.21

Live 0.1.20 boot (11:55): `Gate PASS`, `Txn,BadStatus 0` (0.1.19 ResOk works), but `Res,Forced == Copy,Frames`
(2050): the family's `IOAccelResource2::prepare()` still fails on **every** frame, 2621x per boot:
`freeToAllocGPUAddress: failed to alloc GART space at segment 0. Needed 0 bytes, used 20738048, size 17179865088.
vram=0` + `prepare(): failed to allocate GPU virtual address for mapping. resType=0xc0`. `vram=0` confirms 0.1.18's
cfg bit 21 (UMA sysmem). The failing resource is WindowServer's OLED surface (`surface 2 2880x1800 BGRA`).

Chain (25G241 SystemKernelExtensions.kc):
* `IOAccelMemoryMap::getLength()` @0x148a0afe = `map->memory(+0x18)->getLength()`; `IOAccelMemory::getLength()`
  @0x1408c5ce = `memory+0x40`. "Needed 0 bytes" = the mapped IOAccelMemory is 0 bytes long.
* `IOAccelResource2::map()`: for type nibble 0 it maps `+0x88` (allocMemory's memory) before `+0x80`.
* `newResourceWithIOSurfaceDeviceCache` @0x14b8777c: type from accel slot 288 `resourceTypeForIOSurface`, `+0x80`
  = `IOAccelSysMemory::withMemoryDescriptor(accel, 0, IOSurface::getMemoryDescriptor())` (length via
  IOMemoryDescriptor slot 57 = getLength, correct), and for type 0xc0 `res+0xc8/+0xb8` come from resource slot 62
  `calculateIOSurfaceDeviceCacheVRAMBytes`.
* Family `resourceTypeForIOSurface` @0x14ba3c3e = `(IOSurface::isSysMemOnly() ? 2 : 3) << 6`, so WindowServer's
  surfaces are 0xc0 (0x40 = device cache), `allocMemory` then allocates `roundup(res+0xc8)` sysmem at `+0x88`.
* `StrixResource::calculateIOSurfaceDeviceCacheVRAMBytes` returned **0/0** -> 0-byte device cache -> 0-length map.
  Apple's `AppleParavirtResource` version (@0x148a5dea) returns `IOSurface::getAllocSize()` / `getBytesPerRow()`
  of `this+0xe0 -> +0x10` (stubs decoded: 0x10d02 getAllocSize, 0x10d08 getBytesPerRow, 0x1123c isSysMemOnly,
  0x104c8 getMemoryDescriptor).
* Side note: the 11x `IOAccelSurface::surfaceStart(): failed to get the vram descriptors` at boot is
  `find_vram_descriptor` (framebuffer `getVRAMRange()` -> `map(1)` -> `getVirtualAddress`) running before a
  framebuffer is attached; StrixGOP implements getVRAMRange. Not per frame.

0.1.21 (built and installed on macOS, AuxKC rebuilt 12:05, reboot pending):
* `StrixAccelerator::resourceTypeForIOSurface` returns **0x80** (live tunable `StrixAccel,UmaSurf`, default 1;
  boot-arg `strixumasurf=0` restores the family rule). On UMA the IOSurface pages are the GPU memory: the resource
  maps the surface itself (`+0x80`), no second allocation, no copy. This is the dynamic GPU-VA path working, not a
  forced success.
* `calculateIOSurfaceDeviceCacheVRAMBytes` mirrors Apple's (only reached with UmaSurf 0).
* Counters `Res,TypeUma`, `Res,TypeDevCache`, `Res,DevCacheKB`, `Tune,UmaSurf`.
* Expected next boot: no `failed to alloc GART` / `failed to allocate GPU virtual address` lines,
  `Res,Forced` ~0 while `Res,Prepare` grows, `Txn,BadStatus 0`, no `Fallback ... submission failed`.


## Step24 (2026-10-17, macOS 25G241): 0.1.21 verified; what WindowServer spends CPU on now

Boot 12:07 with StrixAccel 0.1.21:
* `Res,Forced 0` with `Res,Prepare 3371` (every family `IOAccelResource2::prepare()` now succeeds on its own),
  `Res,TypeUma 8`, `Res,TypeDevCache 0`, `Txn,BadStatus 0`.
* Whole-boot kernel log for `IOAcceleratorFamily2`: **0** `failed to alloc GART space`, **0**
  `failed to allocate GPU virtual address` (2621/boot on 0.1.20). Left: 11x `surfaceStart(): failed to get the vram
  descriptors` at boot (before the framebuffer attaches) and 13 display_change_handler traces.
* WindowServer error log: **0** `Fallback GPU Display Pipe transaction submission failed`; 174
  `3-channel gamma table` lines remain (AGDC entry type, Step22 A/B levers).
* WindowServer CPU: ~165 % for the first minute, then **~74 %** steady (desktop idle-ish, OLED only + HDMI attached);
  kernel_task ~27 %.
* Spindump 1 (first minute): two threads (`CA::CG::Queue`, `com.apple.coreanimation.pipelines`) at 100 % each in
  `NVMTLLibrary newFunctionWithName -> nvmtl_translate (metal2vulkan)`: CoreAnimation's shader warm-up translated
  Metal -> SPIR-V on the CPU by NullMoth's NVMTL. Gone in spindump 2.
* Spindump 2 (steady): compositor = `CompositorMetal` on **NVMTL (RTX 5060 via nouveau Vulkan)**, not the 890M. Per frame:
  `nvmtlSurfaceIn -> nvmtl_vk_image_write` (CPU upload of IOSurfaces into Vulkan images), `nvmtlSurfaceOut ->
  nvmtl_vk_image_read` (CPU readback of the composited frame into the OLED IOSurface), `waitUntilCompleted`; then
  StrixDisplayPipe copies that IOSurface to the GOP raster in the kernel (`Copy,AvgUs` ~5.2 ms). `CombineLUTs` /
  `RunFullDisplayPipe` no longer show up.

Meaning: the 890M side of the display pipe is now clean (resources map through the family's GPU VA allocator, no
fallback). The remaining CPU is the cross-GPU copy chain (dGPU composite -> CPU readback -> CPU copy into the iGPU
scanout). It goes away only when the 890M composites itself: GMC/GART programming, SDMA, GFX11.5 + a Metal device on
the 890M (port milestones 4-10), not in StrixAccel's CPU copy path.


## Step25 (2026-10-17, macOS 25G241): milestone 4 switches to NullMoth's NMXGPU (Linux amdgpu on macOS)

Owner direction: with a hybrid laptop the iGPU must be the default and the NVIDIA card only for heavy work; if that is
hard, ignore NVIDIA for now and do M4.

What the NVIDIA side already does (nullmoth upstream `kexts/NVRM/accel/nvrm-accel.cpp`, headless check): NVAccel
withholds `MetalPluginName` until an NVIDIA display head publishes. With no head after 60 s it restores the name
*without arming* (`debug.nvaccel_headless=1`): apps get the NVIDIA Metal device, WindowServer stays on the GPU that owns
the display (Apple's two-GPU MacBook Pro model). Our boots composite on NVIDIA because (a) an HDMI monitor on the NVIDIA
port arms it, and (b) with OLED only, our own **StrixMetalGate** puts `MetalPluginName` back before the 60 s check so
WindowServer gets the NVIDIA device (written when the 890M had no Metal driver at all). So "iGPU first" needs a Metal
device on the 890M, not a change to the NVIDIA driver; StrixMetalGate must be off once the 890M has one.

NMXGPU (in the installed NullMoth 2.0.4 package, `/Library/NullMoth/kexts/26/NMXGPU.kext`, 15 MB; sources in the fork
workspace `gpu-port/`): drm-kmod (DRM core of Linux 6.14) amdgpu + i915 + xe linked into one kext through FreeBSD's
LinuxKPI on xnu; DRM minors as devfs clone nodes in `/dev/dri`; display bridge = in-kernel DRM client publishing an
IOFramebuffer (`NMXGPUFB`) on one contiguous scan-out buffer. NMXAccel (= nvrm-accel.cpp built `-DNMX_ACCEL`) gives a
Metal device on the AMD GPU; the Metal plugin loads RADV (`/Library/NullMoth/gpu-userland`). Upstream status: "not
yet loaded on hardware", opt-in `nmxamd=1`, probe score 60000 on any display-class AMD function.

The binary carries every 890M IP block: `gfx_v11_0` (130 syms), `gmc_v11_0`, `soc21`, `psp_v14_0`, `smu_v14_0_0`,
`sdma_v6_0`, `mes_v11_0`, `imu_v11_0`, `nbio_v7_11`, `dcn35`/`dcn351`, `vcn_v4_0_5`, `jpeg_v4_0_5`, `vpe_v6_1`,
`isp_v4_1`, `umsch_mm_v4`, IP discovery. That is milestones 4-9 (GMC/GART, PSP/SMU/IH, SDMA, GFX+MES, DCN35) in
amdgpu's own code instead of a hand-written Cobalt64-style driver.

Boot test installed (`scripts/macos-nmxgpu-890m-test.sh`, undo `--undo <esp>`; from Linux copy
`EFI/OC/config.plist.pre-nmxgpu-890m` back):
* firmware: 16 files + LICENSE.amdgpu from linux-firmware `afabaf773c4c...` (the commit NullMoth's manifest pins),
  each SHA-256 checked: gc_11_5_0_{imu,me,mec,mes_2,mes1,pfp,rlc}, psp_14_0_0_{toc,ta}, sdma_6_1_0, dcn_3_5_dmcub,
  dcn_3_5_1_dmcub, vcn_4_0_5, vpe_6_1_0, isp_4_1_1, umsch_mm_4_0_0 -> `/Library/NullMoth/firmware/amdgpu` (7.3 MB).
* NMXGPU + NMXAccel in `/Library/Extensions`, RADV userland into `/Library/GPUBundles/nvmtl`, AuxKC rebuilt
  (contains both).
* boot-args: `+nmxamd=1 -strixgopoff -strixaccoff -strixmetalgateoff`, `strix-probe=1` removed (no second MMIO user).
* 890M DeviceProperties `class-code ffffffff`, `disable-gpu`, `name`/`IOName #display` removed for the test: with them
  NMXGPU's display-class match never sees the GPU (the upstream setup drops `disable-gpu` the same way).
* ocvalidate clean. Test with OLED only (HDMI unplugged).

After the boot: `sudo bash scripts/macos-nmxgpu-890m-collect.sh out/890m-trace/step25-nmxgpu` (kernel log of
NMXGPU/amdgpu/[drm], ioreg, /dev/dri, displays). M4 pass = amdgpu reaches `gmc_v11_0` init (VRAM/GTT sizes, GART
enabled) and PSP/SMU/IH come up; M5-M7 = ring tests of SDMA/GFX/MES pass; display = NMXGPUFB lights the OLED.

## Step26 (2026-10-17, macOS 25G241): first NMXGPU boot - amdgpu hangs in the PCIe partner-bandwidth walk; patched

First boot of the Step25 test (OLED only, `nmxamd=1 -strixgopoff -strixaccoff -strixmetalgateoff`):

- NMXGPU 1.0.0 + NMXAccel 0.1 load from the AuxKC, `/dev/dri/card0` + `renderD128` exist, no panic.
- amdgpu logs only `kernel modesetting enabled`, `initializing kernel modesetting (IP DISCOVERY 0x1002:0x150E
  0x1043:0x3998 0xC1)`, `register mmio base 0xDC300000 / size 524288`, then nothing. NMXGPU stays `!registered`;
  NMXAccel waits ("NMXGPU has not claimed 1002:150e yet").
- The OLED runs on `.Display_boot` (IONDRVFramebuffer, the GOP buffer: 19 MB, "No Kext Loaded", no EDID) - this is
  why System Information lost the display name/details. WindowServer has no accelerator at all (StrixAccel off, NVIDIA
  headless, NMXAccel not started) and composites on the CPU: 160-460 %.
- spindump of kernel_task: the NMXGPU attach thread (`NMXGPU::attachThread -> attachNow -> nmx_bus_add_device ->
  linux_pci_attach_device -> amdgpu_pci_probe -> amdgpu_driver_load_kms -> amdgpu_device_init`) is **running** in
  `amdgpu_device_init+0x11e0..0x124b` calling `device_get_parent` - a spin that also burns a full core.

Disassembly: that range is `amdgpu_device_get_pcie_info()` inlined. `0x164a4/0x164a8(adev)` = `pm.pcie_gen_mask /
pm.pcie_mlw_mask`. On Linux the 890M sits on a root bus, so the APU branch (+0x1181) sets the defaults `0x30007 /
0x2f0000` and returns. Under LinuxKPI the device has a bridge chain, so it takes the non-root branch (+0x11b0) into
`amdgpu_device_partner_bandwidth()`, whose `pci_upstream_bridge()` loop never terminates on NMX's device tree. The
`amdgpu_pcie_gen_cap/lane_cap` params would skip it but are zero-fill `__common` and NMXGPU reads no tunables.

Fix (`scripts/macos-nmxgpu-pcie-patch.sh`, applied, AuxKC rebuilt; `--undo` reverts): file offset `0x1a7f0`
(`amdgpu_device_init+0x11b0`) `83bba464010000740d` -> `e9ccffffff9090900d` = `jmp +0x1181`, i.e. take the APU/root-bus
branch. Guarded by the stock NMXGPU sha256 (33aa04a8...); patched sha256 97a336a3.... The Step25 installer now applies
it; the collector also writes `spin-kernel.txt` + `nmx-stacks.txt` (NMXGPU frames symbolised) in case it stops again.

Next boot: expect amdgpu to reach IP discovery / GMC v11 / PSP 14 / SMU 14 / ring tests; if the display init succeeds
NMXGPUFB takes over the OLED (EDID back) and NMXAccel starts, giving WindowServer a Metal device on the 890M.

Step26 boot 2: the patch did not run yet - NMXGPU's boot guard saw NVRAM `nullmoth-gpu-attaching=1` left by the hung
attach and parked the 890M ("the last attach of 1002:150e never returned ... this GPU stays with macOS"). Cleared with
`nvram -d nullmoth-gpu-attaching`; the patch script now clears it too and the collector records `nvram-guard.txt`.

Step26 boot 3 (guard cleared, PCIe patch live): **amdgpu gets through IP discovery** - all 13 blocks detected
(soc21_common, gmc_v11_0, ih_v6_1, psp, smu, dm, gfx_v11_0, sdma_v6_0, vcn_v4_0_5, jpeg_v4_0_5, mes_v11_0, vpe_v6_1,
isp_ip) - then `Unable to locate a BIOS ROM` -> `Fatal error during GPU init` -> `attach failed (22)`, clean unwind,
no hang.

Why: on an APU amdgpu_get_bios() wants the ACPI VFCT table (GOP-installed copy of the VBIOS). NMXGPU's xkpi
`AcpiGetTable()` -> `nmx_xnu_acpi_table()` walks the IOService plane for a property `"ACPI Tables"` (OSDictionary of
OSData keyed "SIG" / "SIG-n") - AppleACPIPlatformExpert on Tahoe 25G241 no longer publishes it (only
"ACPI Statistics"), hence also "no FADT". The other fallbacks fail on this APU (VRAM BAR holds the GOP framebuffer,
no ROM BAR, `pdev->rom` unset).

Fix: `scripts/macos-strixvfct-install.sh <VFCT.bin> <esp>` builds **StrixVFCT.kext** (codeless; IOClass IOService on
IOResources, personality property `"ACPI Tables" = {"VFCT": <table>}`) from the Linux dump
(`/sys/firmware/acpi/tables/VFCT`, 21636 bytes, one image 101:0:0 1002:150e 21504 bytes - bus 101 matches `pcidebug`
on Tahoe) and adds it to OpenCore Kernel/Add (MinKernel 25) so the node exists before NMXGPU attaches. The VBIOS is
vendor firmware: the kext is generated under build/ (ignored), never committed. `--undo <esp>` removes it.

## Step27 (2026-10-17, macOS 25G241): the 14:33 boot was parked by a stale NVRAM marker, not by a hang; the
StrixVFCT test is still unrun

The owner's single restart (shutdown 14:32:06, next boot 14:33:45) came up **parked**: NMXGPU found NVRAM
`nullmoth-gpu-attaching=1` at attach time (14:33:54.674, thread 857) and printed "the last attach of 1002:150e never
returned (the Mac stopped or restarted); this GPU stays with macOS". Nothing of amdgpu ran, the OLED stayed on
`.Display_boot`, WindowServer had no accelerator. No hang anywhere in the system (no kernel spin; the parked state
was the whole story).

The marker was **not** left by a hung attach. The guard writes it around `nmx_port_attach()` (`xkpi/xnu/nmx_kext.cpp`
194-227: set before, cleared after success or failure), so in boot 3 (12:46:58-14:32) the 12:47:05.585 attach failed
cleanly ("no driver took 1002:150e" at 12:47:05.596). After that:
* `sender == "NMXGPU"` is empty from 12:47:06 to 14:33:54, and a 13:11:47 read of `nvram -p` showed no marker.
* The 14:32:08 shutdown-stall stackshot (boot 3, Time Since Boot 6311s) has **no NMXGPU thread active after boot+9s**:
  every LinuxKPI worker (`linuxkpi_*_wq`, `nmx softclock`, `nmx taskq`, `amdgpu-reset-dev`) reports "last ran
  6302.0-6302.1s ago" = 12:47:06, the boot-3 attach (a second attach would have woken the firmware-loader workers).
* No `sudo`, `osascript` or `nvram`-write process ran in the window (the only two `nvram` launches, 13:11:47 and
  13:36:56, are this session's read-only `nvram -p`/`nvram boot-args`).
* `softwareupdated` emits a sandbox `deny(1) nvram-get nullmoth-gpu-attaching` line at roughly boot+10s whenever the
  variable exists (seen at 12:32:09, 12:41:03 and 14:33:55; **absent for boot 3**). A handy passive detector.

Conclusion (best-supported explanation): `nmx_marker_write(false)` - `removeProperty` + `sync()` through IODTNVRAM -
did **not reach the firmware store**, so the stale "1" came back at the next boot and parked the GPU. The text "(the
Mac stopped or restarted)" is the driver's assumption about a leftover marker and is wrong in this case. The
`nvram -d` **CLI** path does persist: the 12:45:44 CLI clear held (boot 3's attach ran). Worth reporting upstream.

The owner's "black screen" is not the GPU either: WindowServer started twice - 14:33:52.898 (pid 205) and 14:34:27.546
(pid 951) - the second start being the NullMoth flicker stopgap (`com.nullmoth.wsreset` restarts WindowServer once per
boot). A short black flash after the restart, not a parked GPU. (`pmset`: display asleep 13:51:10-14:31:00 before the
restart.)

Also seen: ESP `config.plist` mtime 13:36:56 - rewritten with identical content by an unattributed run at the same
second as the session's two read-only `nvram` launches. Full diff against `config.plist.pre-strixvfct` re-verified:
only `Kernel/Add StrixVFCT.kext`, the nmx boot-args and the emptied 890M `DeviceProperties`.

Owner observation (14:5x): display sleep puts the panel **white**, not off (this parked boot runs on `.Display_boot` -
no EDID, no DCN driver - so nothing blanks the panel and the last GOP frame stays lit). Also explains why the first
two admin prompts failed with -60005: the dialog was opening on a sleeping display. Cosmetic for this test; revisit
when NMXGPUFB owns the display.

Fix applied (14:52): root `nvram -d nullmoth-gpu-attaching` (via osascript; the first two prompts failed with -60005 -
the dialog was coming up on a sleeping display; `caffeinate -u` first). Verified absent. **The next boot is the first
attach that will actually see StrixVFCT's VFCT.** Expectations and evidence plan: `Unable to locate a BIOS ROM` gone,
then ATOM-BIOS parse / GMC v11 / PSP 14 / SMU 14 / IH lines; if it hangs instead, the guard parks the boot after it
(one reboot), and the evidence comes from that boot's `NMXGPU` log plus a `spindump` while it spins or the
shutdown-stall report after a forced restart. Collector: `sudo bash scripts/macos-nmxgpu-890m-collect.sh
out/890m-trace/step27-vfct`.

## Step28 (2026-10-17, macOS 25G241): the StrixVFCT boots - black OLED + IOFramebuffer power-state panic; NMXGPUFB fix

Owner: with the guard cleared the OLED goes black; a forced restart then comes up parked (guard) and works. Twice.
Reports: `Kernel-2026-10-17-150228.panic` and `-152250.panic`, both the boots that attached with StrixVFCT (their
unified log never reached disk - panic at 10.5 s / 24.3 s uptime; the following boots are the parked 15:02 / 15:22
ones). Both identical: page fault CR2 `0x120` at `IOFramebuffer::powerStateWillChangeTo+0x25`, kernel_task PM thread
(`pmDriverCallout -> driverInformPowerChange`), RAX 0.

`powerStateWillChangeTo` starts with `this->fPrivate(0x1c8)->controller([0])->workloop(0x120)`.
`fPrivate->controller` is only assigned in `IOFramebuffer::open()` (via `copyController`); `IOFramebuffer::start()`
only calls `joinPMtree` (vtable 0x7a0). `NMXGPUFB::start()` calls `IOFramebuffer::start()` and then
`registerPowerDriver(this, kFbPowerStates, 2)` (vtable 0x7a8). The initial power change it triggers can reach
`powerStateWillChangeTo` before anything opens the framebuffer, so controller is NULL and the kernel panics. The
framebuffer exists only after amdgpu initialised and the NullMoth display client set a mode, so with the VFCT amdgpu
very likely got through GPU init + DC this time (unconfirmed - no log survived).

Fix: `scripts/macos-nmxgpu-pcie-patch.sh` is now a patch set. `fbpm` = file offset `0x9ced22`,
`ff90a8070000` (`call *0x7a8(%rax)`) -> `31c00f1f4000` (`xor eax,eax; nop4`). Applied together with `pcie`; stock
sha256 is checked by un-applying the known patches; patched sha256 `01cf7420...`; `--undo` restores the stock bytes.
AuxKC rebuilt, guard cleared. Risk: without a power driver, IOFramebuffer gets no power callbacks (no display sleep
on NMXGPUFB) - acceptable for bring-up; if WindowServer then waits on the framebuffer the boot is black but alive, and
its log survives a forced restart.

## Step29 (2026-10-17, macOS 25G241): NMXGPU brings the whole 890M up; WindowServer's open of NMXGPUFB panics on the stale `.Display_boot` pipe

Boots 15:36 / 15:37 / 15:38 (black screen; the boot guard never parked them - not the topic here). Evidence read from Linux
(Data volume mounted ro): `Kernel-2026-10-17-153620.panic`, `-153753.panic`, and the Persist tracev3 files `…137..139`
(LZ4 `bv41` blocks decompressed by hand, `strings`).

Progress, identical in all three boots: `Fetched VBIOS from VFCT` (StrixVFCT works) -> 16 firmware images -> `VRAM 512M`,
`GART 512M`, `reserve … for PSP TMR` -> `amdgpu_dm_initialize_drm_device` -> rings gfx_0.0.0, comp_1.0.0-1.3.1, sdma0,
vcn_unified_0, jpeg_dec_0, mes_kiq_3.1.0, vpe -> `Runtime PM not available` -> 9 connector hotplug events
(`cdev=dri/card0 connector=93..135`) -> `NMXGPUFB` published. **The amdgpu driver is fully up on the 890M**; the `fbpm`
patch from Step28 holds (no `powerStateWillChangeTo` panic any more).

Panic (both reports identical, WindowServer pid 917): page fault CR2 `0x120`, RAX 0,
`IOFramebuffer::getAttributeExt+0x28 <- IOAccelLegacyDisplayPipe::displayModeDidChange+0x30 <-
IOAccelLegacyDisplayMachine::display_mode_did_change <- IOAccelDisplayPipe::display_change_handler <-
IOFramebuffer::deliverGroupNotification <- deliverDisplayModeDidChangeNotification <- IOFramebuffer::open+0xe4c <-
newUserClient`. `getAttributeExt` is `fPrivate(+0x1c8)->controller([0])->workloop(+0x120)`; `controller` is assigned
only in `open()` (copyController, 25G241 `open+0x1da`), and `open()` assigns it for *its own* framebuffer before it
delivers the notification. So the framebuffer the pipe stores at `pipe+0x98` is **not** the one being opened.

Cause: two framebuffers on the same PCI device. The 890M's IORegistry (`out/890m-trace/step26b-nmxgpu/ioreg-fb.txt`) has
`.Display_boot` (`IONDRVFramebuffer`, `IONameMatch "display"`) under `GPPA@8,1/IOPP/VGA@0`, beside NMXGPUFB. NMXAccel's
`IOGraphicsAccelerator2::start` sweep registers a display pipe for every framebuffer of the device, including the
never-opened `.Display_boot`; opening NMXGPUFB then broadcasts the mode change to the group and that pipe's framebuffer
has no controller. (The Step25 test dropped `name`/`IOName` `#display` from the 890M DeviceProperties, which is what
let `IONDRVFramebuffer` match again.)

Fix applied on the ESP (`config.plist`, backup `config.plist.pre-nodisplayname`): 890M DeviceProperties
`name = <"#display\0">`, `IOName = "#display"` - **only those two**; `class-code` stays real so NMXGPU's class match
still sees the GPU. With the name `#display`, `IONDRVFramebuffer` no longer matches, NMXGPUFB is the only framebuffer
and gets the only pipe. ocvalidate clean. Trade-off: the OLED shows the GOP image until NMXGPUFB takes over; if NMXGPUFB
fails there is no fallback framebuffer.

Next boot - watch for: no `.Display_boot` in `ioreg -l -w0 | grep -i Display_boot`; NMXAccel pipe count 1;
WindowServer stays alive; then `NVDisplayPipe` transaction messages (NMXAccel copies frames to the scan-out).
If it still panics, the report names the next NULL; the fallback is to make `getAttributeExt` NULL-safe via an OpenCore
Kernel/Patch on `com.apple.iokit.IOGraphicsFamily` (function at KC va 0x14d0406a, 0x9c bytes).

## Step30 (2026-10-17, macOS 25G241): first live boot on the 890M - display up, Metal still 0 devices

Boot 15:56 (Step28 `fbpm` + Step29 `#display` name): no panic. amdgpu fully up (VFCT VBIOS `113-STRIXEMU-001`, all
16 firmware images, VRAM 512M / GTT 16G, GART, PSP TMR, `SMU is initialized successfully!`, DC 3.2.316 on DCN 3.5,
DMUB 0x09005600, PSR, rings + IB tests pass, `Initialized amdgpu 3.61.0 ... on minor 0`), and the NullMoth display
client lights the OLED: `2880x1800, pitch 11520, phys 0x87c000000`, NMXGPUFB at 120.00 Hz. System Information lists the
890M as the main display, "Metal: Supported". Only remaining IONDRVFramebuffer is on the NVIDIA PEGP (headless).
Non-fatal: `amdgpu_bo_init: Unable to set WC memtype for the aperture base`, `Failed to initialize writeback connector`.

But **WindowServer composites on the CPU (400-1000 %)**: spindump = `CA::OGL::SW::scan_convert/sample_texture` +
`vRotate_90_ARGB_8888` - CoreAnimation's software renderer. Two independent reasons:
1. NMXAccel 0.1 (NullMoth 2.0.4) hard-codes `gNvHeadless = 1` in `start()` ("Metal device for apps, frames copied to
   the framebuffer WindowServer draws"), and NVMTLDriver refuses WindowServer on a headless GPU; the allow-list line
   `!WindowServer` additionally needs `debug.nvaccelfb`, which no loaded kext registers.
2. Even an ordinary process gets **0 Metal devices**: NVMTLDriver loads `libvulkan_radeon` + `libdrm_amdgpu`, RADV
   creates an instance and finds no physical device, because **every open of `/dev/dri/renderD128` and `card0`
   fails with ENODEV** (also as root). `nmx_open` only returns ENXIO; ENODEV (-0x13) comes from
   `drm_stub_open -> drm_minor_acquire(linux_iminor(inode))` - the minor lookup in `drm_minors_xa` or the
   `drm_dev_enter` check fails. Next: map `linux_iminor` for devfs minors 0x2c2/0x2c3 against the DRM minor ids
   (render 128, primary 0), from the NMXGPU v2.0.4 sources (upstream git history before a7f16b0).

## Step31 (2026-10-17): route B - own NMX build; root cause of the ENODEV opens, fixed in source

Decision with the owner: stop depending on the NullMoth NVIDIA package; build NMXGPU/NMXAccel ourselves from the
NullMoth v2.0.4 sources (PolyForm Noncommercial - personal use, kept in the fork, never copied into this BSD repo),
then replace NMXAccel's headless path with our own accelerator. Sources: worktree
`~/develop/projects/nmx-src-2.0.4`, branch `ga403wm-nmx` of the fork (`thanhnndev/nvidia-macos-driver`).

Root cause of Step30's `/dev/dri` ENODEV (read from `gpu-port/xkpi`, matches the shipped binary):
1. `override/src/nmx_linux_cdev.c` `nmx_cdev_open()` hands `d_fdopen` a zeroed `struct file`. LinuxKPI's
   `linux_dev_fdopen()` passes `file->f_vnode` (NULL) as the Linux inode to `drm_stub_open()`; `linux_iminor(NULL)` =
   `-1U`; `drm_minor_acquire(&drm_minors_xa, -1U)` finds nothing and returns -ENODEV. No code in the port ever creates
   the vnode its own `sys/vnode.h` describes.
2. Behind it: `linux_dev_fdopen()` returns ENXIO on success (FreeBSD devfs "file replaced" convention, after
   `finit()`), and `nmx_cdev_open()` treats any non-zero as failure.
So no DRM node open could ever succeed in 2.0.4; RADV (and every Metal device on top of it) had no way in.

Fix (fork commit 6d2f242 "xkpi: DRM device nodes open"): each cdev owns a vnode (`v_rdev` = cdev, VCHR, freed with
the cdev in `dev_rel`), opens pass it in `f_vnode`; ENXIO with `f_ops` installed = success.
A binary patch was judged not worth it (needs a code cave for the allocation). Next: step 2 - build environment
(drm-kmod 6.14 + FreeBSD LinuxKPI + the port's scripts, which hard-code `/Volumes/MiniData/build/gpu-src`), carry the
`pcie` and `fbpm` patches and StrixVFCT's VFCT path into source, build, install, boot.

## Step32 (2026-10-17): own NMXGPU build installed (route B step 2)

Build environment (all outside this repo, `~/develop/projects/gpu-src`): freebsd/drm-kmod `c16de0f9fa` (Linux 6.14,
amdgpu KMS 3.61 - matches the shipped binary), freebsd-src `9d82546a` sparse (`sys/compat/linuxkpi`,
`sys/contrib/ck`, `sys/contrib/dev/acpica/include`; the override `linux_pci.c` needs the `pci_lock` extern that
`e2bef7e3` removed, so the author built just before it; the forked LinuxKPI headers regenerate byte-identical),
`xkpi` -> the fork worktree. Results: runtime 76/76, amdgpu+DRM+TTM 900/900 sources (80 s on this machine), AMD-only
link `NMXGPU 8a793bdf`, 10.8 MB; its undefined symbols are a subset of the shipped binary's (0 new), Info.plist
identical.

Fixes now in source (fork `ga403wm-nmx` 6d2f242 + 579cb54), replacing the binary patches:
* DRM node opens (Step31): vnode per cdev + ENXIO-on-success.
* `pcie`: `linux_pci.c` reports every GPU on a root bus (the port has no PCI-to-PCI bridges above GPUs, so
  `pci_upstream_bridge()` returned the GPU itself and amdgpu's partner-bandwidth walk spun).
* `fbpm`: NMXGPUFB registers its power driver in `open()` instead of `start()` - keeps display power management,
  unlike the binary patch that dropped it.

Installed with `scripts/macos-nmxgpu-own-install.sh <kext>` (backs up the installed binary-patched kext to
`/Library/NullMoth/nmxgpu-backup`; `--undo` restores it), AuxKC rebuilt, guard cleared. StrixVFCT and the `#display`
DeviceProperties stay. NMXAccel is still NullMoth's (headless), so WindowServer stays on the CPU this boot; the test is
whether ordinary processes now get a Metal device (RADV opens renderD128).

## Step33 (2026-10-17): own NMXGPU boots clean; DRM opens work, enumeration does not (clone minors)

The Step32 build booted without problems (OLED, no guard trip). New tools in `tools/890m/`: `drm-open.c` (opens a
node through NullMoth's libdrm, prints the driver) and `metal-devices.swift` (what `MTLCopyAllDevices()` returns).
* `drm-open`: `open /dev/dri/renderD128: driver amdgpu 3.61.0 (AMD GPU)` - the Step31 fix works (before: ENODEV).
* `drmGetDevices2()` still 0, so RADV creates an instance and finds no physical device; Metal devices: 0.

Root cause: NMXGPU's nodes are xnu devfs clone nodes (`devfs_make_node_clone`), and devfs clones at every lookup,
`stat()` included: `stat /dev/dri/renderD128` three times gave rdev `0x21000223`, `...225`, `...227` (open minors
256+, handed out in sequence; `/dev/null` stays `0x3000002`). libdrm's macOS port (`patches/libdrm-macos.patch`)
recognises a node by stat'ing `/dev/dri/*` for the same major:minor (`drmNodeIsDRM`) and names a node from its minor
(`drmProcessPciDevice`: `renderD<minor>`), so with a fresh minor at each stat no node ever matched.

Fix, in two halves:
* fork `nmx_devfs.cpp`: an open minor is `(sequence << 8) | node minor`, and a node's minor is its DRM minor
  (`dri/card0` = 0, `dri/renderD128` = 128; other nodes take free minors from 255 down). Open bookkeeping is per
  sequence; the open hash in `nmx_linux_cdev.c` keys on the sequence. Build `NMXGPU 3533f839`, 0 new undefined
  symbols.
* `scripts/macos-nvmtl-libdrm-minor-patch.sh`: libdrm keeps only the low byte of every minor it takes from a dev_t
  (8 `and $0xffffff` -> `and $0xff`, re-signed ad hoc; stock backed up to `/Library/NullMoth/libdrm-backup`,
  `--undo`). With the low byte the minor is stable across stats and is the DRM minor libdrm expects. The proper form
  is the same change in the libdrm patch when the userland is rebuilt from source (route B step 4).

Both installed (AuxKC rebuilt, libdrm `5f2971fc`); takes effect at the next boot. Expected after it: `drmGetDevices2`
= 1 (card0 + renderD128 folded), RADV lists the 890M, ordinary processes get a Metal device; WindowServer still CPU
(NMXAccel headless).

### Step33b (2026-10-17): minors stable after reboot; GET_PCIINFO was the next wall

After the reboot `stat` gives stable low bytes (card0 `...00`, renderD128 `...80`), but `drmGetDevices2` still 0.
libdrm's `drmProcessPciDevice` opens the node and asks `DRM_IOCTL_GET_PCIINFO` (`0x40106415`): ENODEV. A
`NMX_DRM_IOCTL_SYSFS_GET` probe (same `drm_file -> minor -> dev -> dev` chain, no PCI check) answered ENOENT, so the
chain is fine and `dev_is_pci()` is what failed: LinuxKPI's `pdev->dev.bsddev` is the DRM child of the PCI device
record (`is_pci` = 0), like drmn under vgapci on FreeBSD. Fork 'xkpi: DRM_IOCTL_GET_PCIINFO answers for the DRM child
of a PCI device' accepts the child's parent. Build `NMXGPU 8fc7f7fe` (0 new undefined symbols) installed; reboot
pending. Note: card0 is 0600, so for a normal user libdrm lists the GPU through renderD128 only (enough for RADV).

## Step34 (2026-10-17, Linux): login-window crash loop root cause + IF-leak forensics

### What wedged the 18:23 and 20:17 boots
Both boots ended at the Apple logo with a visible cursor because `SecurityAgent` aborted in
`RB::Device::make_index_buffer()` -> `RB::precondition_failure` -> SIGABRT (23x on 18:23 at the 10 s throttle,
1x on 20:17), so the login window never appeared. The failing Metal device is the nvmtl one: the SecurityAgent
process had `NVMTLDriver`, `libvulkan_radeon.dylib` and `libdrm_amdgpu.1.dylib` loaded
(`usedImages` of `SecurityAgent-2026-10-17-201800.ips`, procLaunch 20:17:46, exit 20:17:47, uptime 42 s).

### The allow list grammar (decoded from `-[NVMTLDevice initWithAcceleratorPort:]`)
Decision order in `NVMTLDriver`:
1. `name == "WindowServer"` -> hardcoded "headless GPU: no device" unless the display owner is NVIDIA.
2. `getenv("NVMTL_ENABLE")` -> device, the list is skipped entirely.
3. name in {`mtlprobe`, `nvmtltest`, `nvmtlrender`} -> device (hardcoded, the list is not consulted).
4. open `/Library/GPUBundles/nvmtl-allow.txt`, else `/Library/Extensions/nvmtl-allow.txt`; unreadable -> no device.
5. line grammar (first-char switch table at `0x25ec`): `#`/blank = keep scanning; **`-Name` = DENY** (stops the
   scan); `*` = everyone (stops); `Name` = that one process (stops); `!Name` / `!*` = "armed-only" (device only
   while `sysctl debug.nvaccelfb != 0`; stops).
6. **The scan stops at the first line that decides** (`0x2360 cmp ebx,2 ; jne 0x254d`), so every `-Name` below
   the `*` line is dead code.

### Why the first two fixes did not work
The shipped file has `*` on line 2 with `!WindowServer` below it, so nothing under `*` was ever read -
`!WindowServer` is not a deny at all (it is the armed-only form), and appending `-SecurityAgent` to the end of
the file could not help: the scan had already stopped at `*` and handed the device out. Evidence: with that
file the 20:17 boot still loaded the AMD nvmtl stack into SecurityAgent, and the on-disk unified log contains
`allow-listed` but **zero** `denied by list` occurrences.

### Fix on disk (applied from Linux, no macOS required)
`scripts/linux-nvmtl-allowlist.sh` default = **rung 1**: writes a list with no `*` line, so only the three
hardcoded tools get the device and everything else (login window, Dock, Finder, Terminal, apps) falls back to
Apple's renderer. `--rung3` writes the denies ABOVE `*` for app testing, `--undo` restores the newest backup.
Applied 2026-10-17 20:33, backup `Library/NullMoth/backup-20261017-203359/nvmtl-allow.txt`.

### IF-leak forensics (panic `unsafe thread_call_cancel_wait`, 17:12:54 and 18:23:36)
* `NMXGPU`/`NVRM`/`NVRMFB` are the only kexts importing `_ml_set_interrupts_enabled`. NMXGPU has exactly
  **11** code references (found through LC_DYSYMTAB local relocations, `tools/890m/kext_relocscan.py`), all in
  its per-thread primitive layer: `nmx_thread_crit_check`, `nmx_critical_enter/exit`, `sched_pin/unpin`
  (identical bodies: counter `[th+0x24]`, saved IF `[th+0xd8]`) and `nmx_mtx_lock/trylock/unlock`,
  `nmx_lock_drop/release` (saved IF in the lock at `+0x2c`).
* They are balanced: `critical_exit`/`sched_unpin` restore only when the counter reaches 0; ASIC-branch
  functions (`gfx_v10_0_get_gpu_clock_counter`, 4 entries / 1 exit) share one exit; the other apparent
  mismatches are tail-`jmp` unpins (`linux_rcu_read_unlock`, `idr_preload_end`, `lkpi_kernel_fpu_end`).
* Their own checker agrees: `NullMoth xkpi: %s returned with critical nesting %d - closed`
  (`nmx_thread_crit_check`, called from `nmx_open/read/close/ioctl/select`) never appears in the on-disk
  unified log, so the counter-based path never leaked.
* Remaining suspects: (a) a lock-family path returning to user space without unlocking, or unlocking a
  different object so a stale saved IF is restored - `nmx_thread_crit_check` returns early when
  `crit_count == 0`, so that class is neither reported nor repaired; (b) NVRM (same import, larger parser).

### Next
1. Reboot: login window must appear. Verify with
   `log show --last boot --style compact --predicate 'eventMessage CONTAINS "not allow-listed"'`.
2. Route B step 4: `tools/890m/drm-open` (expect `amdgpu 3.61.0` on `/dev/dri/renderD128`), then `drmGetDevices2`
   should be 1 with NMXGPU `8fc7f7fe` (GET_PCIINFO now answers for the DRM child of the PCI device) and Metal
   devices > 0. With rung 1 only `mtlprobe`/`nvmtltest`/`nvmtlrender` get the Metal device, so name the test
   binary accordingly or add its name as a bare line to the allow list.
3. RenderBox precondition: the framework binary on the System volume is a broken symlink (code lives in the
   dyld shared cache), so mount the Preboot volume read-only from Linux (the one with `Cryptexes/`) and decode
   `RB::Device::make_index_buffer()` the same way the NVMTLDriver grammar was decoded.
4. IF leak: make `nmx_thread_crit_check` unconditional - log and `ml_set_interrupts_enabled(TRUE)` when
   `ml_get_interrupts_enabled()` reads 0 even with `crit_count == 0` - so the next repro names the syscall
   boundary that leaked; then hunt the missing unlock in the lock family.

## Step33c - the 890M executes user-space command streams (2026-10-18, boot 09:00)

Installed: NMXGPU 4427b86a (fork 54a9fc2) + libdrm 47dbb6f2 (`scripts/macos-nvmtl-libdrm-minor-patch.sh` v2).

Fixes since Step33b:
- **mmap EINVAL for every offset >= 4096:** LinuxKPI's `PAGE_MASK` is `~(PAGE_SIZE-1)` (BSD's is `PAGE_SIZE-1`), so
  `offset & PAGE_MASK` rejected everything. `nmx_mmap` now tests the in-page bits explicitly.
- **drmGetDevice2(fd) failed ("amdgpu: drmGetDevice2 failed"):** an open fd's st_rdev carries the open sequence, a
  stat of the path does not; the four `cmp %r14d, m32` sites in libdrm now compare the low byte (`cmpb`).
- **Panic `unsafe thread_call_cancel_wait` in workq_exit** (Kernel-2026-10-17-171254, 18:23 boot): the per-CPU critical
  counter let a thread leave a DRM syscall with interrupts disabled. Critical nesting is now per thread
  (`td_critnest`, saved IF in `td_crit_saved`, last field of struct thread) and every devfs entry point calls
  `nmx_thread_crit_check` on return. Zero panics and zero "critical nesting" lines on this boot.

Live result (no shim, renderD128, rung-1 allow list):
- `drmGetDevices2: 1`, `drm-open: amdgpu 3.61.0`, Metal device "... RADV STRIX1" via mtlprobe.
- `tools/890m/amdgpu-smoke`: ctx create, GTT BO + cpu_map, VA map, GFX IB submit, fence signalled, the GPU wrote
  0x890d890d to the BO and the CPU read it back. First proof of the 890M running work from user space.
- `tools/890m/metal-compute`: device + MSL compile OK, then `vkCreateComputePipelines` FAILED (wall for Step35).
  Earlier shim trace also showed AMDGPU_CTX EACCES for priority > normal and one AMDGPU_INFO EINVAL; not yet tied to it.

New problem found on the 23:27 boot: the machine hung hard ~23 s after the first display sleep (pmset 23:37:20:
"NMXGPU slow (SetState 0, 708 ms)", WindowServer timed out 30000 ms, then the log just ends, no panic record).
Test boots are run under `caffeinate -dis`; the NMXGPU display-sleep/wake path needs its own fix.

Next: (1) RADV_DEBUG / NVMTL_DUMP_FAILED_DIR on the pipeline failure; (2) NMXGPU power-state (SetState 0/1) hang;
(3) non-headless accelerator so WindowServer composites on the 890M.

## Step33d - a Metal compute kernel runs on the 890M (2026-10-18)

`vkCreateComputePipelines` failed because the shader arena BO could not be CPU mapped: RADV's
`radv_amdgpu_winsys_bo_map` calls mmap(2) on the DRM fd (ENODEV on macOS, a kext cdev cannot be mmap'ed). Found with
`tools/890m/vk-compute-min.c` (bare Vulkan, empty compute shader: NULL shader deref after ACO compiled fine), the
mmap interposer in `pciinfo-shim.c` (`mmap(... off 0x1013c8000) = errno 19`) and the ioctl trace (GEM_CREATE, VA map,
GEM_MMAP, then an immediate VA unmap).
Fix: `scripts/macos-nvmtl-radv-nmxmap-patch.sh` (with --undo) redirects the bo_map mmap to libdrm's `drmNmxMmap`
and the bo_unmap munmap to `drmNmxMunmap` (stubs re-bound from two display-only imports).
Result: `metal-compute` (run as `nvmtltest` because of the rung-1 allow list): command buffer completed in 5.35 ms,
all 1048576 values correct. NVMTL -> RADV -> libdrm_amdgpu -> own NMXGPU executes real compute on the Radeon 890M.
Remaining for WindowServer: a non-headless accelerator, the display-sleep hang, and graphics pipelines.

## Step35 - the first graphics job hung the GFX ring and the reset path panicked the Mac (2026-10-18 15:35)

What happened: to cure the WindowServer CPU melt, the headroom-hold LaunchAgent (a 1x1 transparent CAMetalLayer, it
stopped working when rung 1 of the allow list took the Metal device away: "no Metal device" in its log) was added to
`/Library/GPUBundles/nvmtl-allow.txt`. Within a minute: Kernel-2026-10-18-153556.panic, `NMIPI for unresponsive
processor: TLB flush timeout`. Backtrace of the stuck CPU (the NMXGPU taskqueue thread):
`amdgpu_job_timedout -> gfx_v11_0_reset_kgq -> amdgpu_mes_reset_legacy_queue -> mes_v11_0_submit_pkt_and_poll_completion
-> amdgpu_fence_wait_polling`. So two separate problems:

1. A graphics (not compute) job submitted through RADV never completed on the 890M. Not yet explained; compute works
   (Step33d). The entry was removed from the allow list again and the agent unloaded. Next: reproduce under a bounded
   setup (see 3) with the per-job trace.
2. The recovery path must not be able to take the Mac down. Root cause: every LinuxKPI `spin_lock` pins the thread
   (`local_bh_disable -> sched_pin`) and `sched_pin` was a real critical section, i.e. interrupts off on that CPU. The MES
   reset polls a fence for up to two seconds under its ring lock, so this CPU sat with interrupts off for two seconds
   and another CPU's TLB shootdown IPI timed out. Same family as the Step33c IF leak.
3. Fix (fork): `sched_pin/sched_unpin` now only count (`td_pinned`); a lock is a mutex and excludes other threads
   without owning the CPU. `critical_enter` (FPU window, seqc) is unchanged. `nmx_in_critical` reports both. The devfs
   entry points also close a leaked pin and log it. NMXGPU 67cee035, runtime 76/76, 900/900 compiled.

Cross-check with upstream: docs/NULLMOTH-2.3.6-LESSONS.md (they treat "GPU busy" as different from "GPU gone",
bound every present wait and keep a boot guard; we need the same).

## Step36 - DRM syncobj waits timed out early: kernel clock base was not CLOCK_MONOTONIC

Verified after the Step35 reboot: sched_pin fix works (a GFX ring timeout now ends in MES reset failure, MODE2 reset,
"GPU reset(2) succeeded!", no TLB-flush panic).

Symptom: NVMTL metal-compute -> "GPU event segment submission failed". ioctl trace: DRM_IOCTL_SYNCOBJ_WAIT (nr 0xc3,
WAIT_ALL|WAIT_FOR_SUBMIT, absolute timeout) returned ETIMEDOUT right after AMDGPU_CS.

Test `tools/890m/syncobj-wait.c` (500 ms wait on a never-signalled syncobj, deadline built from three clocks):

| deadline clock | returned after |
|---|---|
| CLOCK_MONOTONIC | 27 ms (wrong) |
| CLOCK_UPTIME_RAW | 501 ms |
| CLOCK_MONOTONIC_RAW | 501 ms |

Cause: macOS CLOCK_MONOTONIC = mach_continuous_time (counts sleep); the kernel's ktime_get -> nanouptime used
mach_absolute_time, 0.47 s behind. RADV builds deadlines from CLOCK_MONOTONIC, so they looked ~0.47 s too close/past.
Fix (xkpi bsdcompat/src/nmx_time.c): uptime_ns uses mach_continuous_time. Timers only use deltas, so nothing else moves.
Open: whether the two hung GFX jobs (seq 8,9) were the same bug or a separate fence/IRQ issue - retest after install.

### Step36b - correction: mach_continuous_time is not CLOCK_MONOTONIC either

2f6fc266 (uptime_ns = mach_continuous_time) rebooted and re-tested: `syncobj-wait` MONOTONIC case still returned early
(78 ms of 500). Measured on the live system: CLOCK_MONOTONIC 119.950 s = wall clock - kern.boottime 119.950 s, while
mach_continuous_time = mach_absolute_time = 120.374 s (no sleep yet). CLOCK_MONOTONIC trails mach time by ~0.42 s, the
gap between mach's epoch and the moment boottime was stamped. Fix: calibrate once, offset = cont_ns - (calendar -
kern.boottime), uptime_ns = cont_ns - offset (kernel time stays strictly monotonic, origin matches user CLOCK_MONOTONIC).

## Step37 - why WindowServer burns 500-700% CPU, and what the next boot will tell us (2026-10-18)

`sample WindowServer` (3 s): top of stack is `CA::OGL::SW::image_sampler / scan_convert / scanline` (CoreAnimation's
SOFTWARE rasteriser), memmove, bzero and idle workq threads. WS composites on the CPU because it has no usable Metal
device. The only real cure is a GFX (graphics) job that completes on the 890M so the NVMTL/NMXAccel path can hand WS a
device - compute already works (Step33d), graphics (CAMetalLayer) hangs the GFX ring (Step35).

Batch for the next boot (kext 4d12165b + this commit, one reboot for all):
1. syncobj clock fix (Step36b) - check `tools/890m/build/syncobj-wait` prints ~500 ms for all three clocks.
2. Job timeout now prints the IP-state dump (GRBM_STATUS, CP_RB/IB, RLC...) to the kernel log
   (patches/amdgpu-timeout-ipdump.patch, applied by all.sh) - this is the first look at WHY a graphics job hangs.
3. Display sleep / setPowerState are timed in the log ("power off begin/done in N ms").
Then: metal-compute, then ONE bounded graphics job (not the headroom agent) and read the dump.

## Step38 - first boot with ffcef230: clock fix verified, compute correct, graphics job intermittent (2026-10-18 16:16)

- `syncobj-wait`: CLOCK_MONOTONIC deadline now waits 502 ms (was 78 ms). RADV uses MONOTONIC, so this is the one that
  matters; the other two clocks now overshoot, as expected.
- `metal-compute`: all 1,048,576 values correct, 2.27 ms. `amdgpu-smoke` GFX IB: fence written by the GPU.
- NEW `tools/890m/metal-render.swift`: one triangle into a 64x64 offscreen texture, polled for 5 s (never blocks).
  Result: INTERMITTENT. Some runs complete in 1-2 ms with the right pixel [255,128,64,255]; others fail after ~254 ms
  ("GPU event segment submission failed") and the kernel only notices ~18 s later (job timeout, MES REMOVE_QUEUE fails,
  MODE2 reset succeeds, no panic). Sequence seen: fail, pass, fail, fail. A pass is as fast as compute, so the
  pipeline is correct; something non-deterministic loses or never delivers the work (suspects: cache coherency between
  the CPU's cached view of system memory and non-snooped GPU reads - the port keeps kernel mappings write-back; doorbell
  or wptr visibility; fence/EOP interrupt delivery).
- The IP-state dump on timeout works but prints garbage: the port's printf has no `%pV`, so `drm_info_printer` printed
  the va_format pointer. Patch now formats each line itself ("NullMoth ipdump: ...").
- Mistake recorded: an 80-run `amdgpu-smoke` loop in the foreground hung the terminal for minutes (every failed run
  blocks until the kernel timeout + GPU reset, 8 resets). Stress loops must be bounded with `timeout` and run in the
  background.

## Step39 - the GPU finishes the work; the CPU does not see the fence (stale cache line) (2026-10-18 16:37)

First readable IP-state dump (kext 12bf55a8, `NullMoth ipdump:` lines), taken at the job timeout of a hung render:

- `ring sdma0 timeout, signaled seq=11, emitted seq=13`, then "Fence fallback timer expired on ring sdma0/gfx_0.0.0"
  every 0.5 s for as long as the process lives (52 times in 90 s).
- GFX side: `CP_RB0_RPTR == CP_RB0_WPTR == 0x600` and `CP_BUSY_STAT/CPC/CPF == 0`: the CP consumed every command and is
  idle. `SDMA0_STATUS_REG` has the idle bit set and `UTCL1_*_XNACK = 0` (no translation fault).
- So the engines are done, yet the CPU's view of the fence says "not yet" and keeps saying it from the fallback timer too.
  That is the signature of a stale CPU-cache line: the fence page is written by the GPU through system memory and the
  kernel's mapping of it is write-back (the port cannot change the cache type of an existing kernel mapping), so a line
  already cached hides the GPU's write until it happens to be evicted - hence the pass/fail lottery (and why compute,
  which touches little memory, mostly passes).
- The stuck process also cannot exit (state `?NE`) until the fences resolve.

Experiment (patches/amdgpu-fence-read-flush.patch): `amdgpu_fence_read` reads, clflushes the line, reads again and
returns the post-flush value; every difference is logged as `STALE fence read on <ring>: cached X, memory Y` (first 40).
Proof if the log fires; fix if renders become reliable. If it proves right, the lasting fix is to map the writeback
(fence) pages uncached in the kernel (or flush at the fence-process points) rather than a per-read clflush.

### Step39b - reading the fallback message correctly; batch for the next boot

`Fence fallback timer expired` is printed only when `amdgpu_fence_process` saw `seq != last_seq`: the fences DO advance,
but only because the 0.5 s timer polled; the completion interrupt did not (promptly) process them. Two independent
suspects therefore stay open and the next kext carries a test for each in the same boot:

1. Lost/late interrupts: `nmx_irq_dispatched` (every IV handled since boot) is printed in each of the first 60 fallback
   lines, together with `last_seq -> new seq` and `sync_seq`. Zero or flat count while jobs run = EOP interrupts never
   arrive.
2. Stale CPU cache of GPU-written memory: `STALE fence read` (plain read vs clflush read of the fence line), and the
   ring dwords are flushed before the doorbell (`amdgpu_ring_commit`).

Also in the same kext: readable IP-state dump (Step38/39), display-sleep DPMS and setPowerState timing, syncobj clock.

### Step40 - build 7 (2f79cc2f) first boot: H1 confirmed in part, graphics hang is a real CP stall, strict pass/fail alternation

Boot 17:00, kext 2f79cc2f loaded, `syncobj-wait` MONOTONIC 501 ms. `render-stress.sh 6`: **pass, fail, pass, fail, pass, fail**
(strictly alternating; fail = NVMTL "GPU event segment submission failed" at 253 ms, kernel timeout ~18 s later, MODE2 reset).

- `STALE fence read` fired 13 times in the window (gfx_0.0.0 x1, mes_3.0.0 x9, sdma0 x3: cached N, memory N+1). So GPU writes to
  system memory do NOT invalidate the CPU's cache lines here: H1 is real for GPU->CPU. With the clflush in place the fences
  that complete are seen, so H1 alone no longer explains the failures.
- No `fence fallback on` lines in this window: the interrupt path is not the story for these hangs (H2 not supported).
- The failing job is now on **gfx_0.0.0** (signaled seq=6, emitted seq=8), not sdma0, and the engine is genuinely busy:
  `CP_RB0_RPTR 0x14e` vs `WPTR 0xb00` (CP stopped inside the ring), `CP_ME_HEADER_DUMP 0xc0023f00` (PM4 type 3, opcode 0x3F
  INDIRECT_BUFFER), `CP_IB1_BASE 0x8001_0002b000`, `CP_IB1_CMD_BUFSZ 0x38`, `GRBM_STATUS 0xa800302c`, `GRBM_STATUS_SE0 0x6`,
  `CPF_STALLED_STAT1 0x1`, all UTCL1 status 0 (no page fault). The CP sits executing an IB with no fault.
- Alternation = state: the first job after boot/after a reset passes, the next one hangs. Something a good graphics job
  leaves behind (or does not flush) breaks the next one.

Hypothesis for build 8 (patches/amdgpu-ttm-force-wc.patch): since GPU writes are not snooped, assume the CPU->GPU direction is
equally incoherent (IB / descriptor / shader contents written through cached CPU views not visible to the GPU, stale RAM
read instead). Make **every GTT page write-combined** (TTM caching = write_combined: PTE not snooped, kernel and user maps WC,
page flushed when it leaves WB). If the alternation disappears, coherence is the root cause.

## Step40 - build 7 (NMXGPU 2f79cc2f) first boot, 2026-10-18 17:19

Kext c4e26ec4 (file sha) / build id 2f79cc2f loaded. syncobj-wait MONOTONIC 501 ms (clock fix holds). metal-compute: 2.08 ms, all 1048576 correct.

render-stress 6: strictly alternating fail/pass (fail, pass, fail, pass, fail, pass). Failures return "GPU event segment submission failed" after ~254 ms; passes take 1-2 ms and are CORRECT. Every failing run ends in a gfx_0.0.0 timeout (signaled 5/emitted 7, 13/15, 21/23) and a MODE2 reset (succeeds, no panic). The reset happens ~13 s after the run, the runs themselves do not wait for it.

Findings:
1. H1 (stale CPU cache) is real but benign here: `STALE fence read` (cached N, memory N+1) fires on mes_3.0.0 and sdma0. It is NOT on gfx_0.0.0, and no `fence fallback on` line appears at all, because the gfx fence never advances.
2. This failure is different from the Step39 sdma one (engines idle, RPTR==WPTR). Here the GFX CP is genuinely stuck: CP_RB0_RPTR 0x3a (later 0x14e, twice) vs CP_RB0_WPTR 0xa00/0xb00, CP_CPF_STALLED_STAT1 = 1 (CPF waiting for ring data), CP_BUSY_STAT 0x80, GRBM_STATUS 0xa800302c, no UTCL1 faults. The CP has not even fetched the first dwords of the failing submission; the stall position (0x14e) repeats after resets.
3. The old ringdump patch prints the 96 dwords BEFORE wptr: all 0xffff1000 (NOP) so it shows nothing useful. It must dump around RPTR.
4. Interpretation: ring fetch by the CPF from system memory (GART) never completes while no fault is reported. Next batch: dump ring dwords around hw RPTR, CP_RB0_BASE/RB_RPTR_ADDR, CP_IB1_BASE/BUFSZ, MES queue state, and test ring placement/flush variants.

Step40b: the nmx_wc A/B (tools/890m/wc-ab.sh) hung on its first pass: an nvmtltest render stayed in state R for >5 min after a MODE2 reset (reset(14)) and would not exit (same exit-stuck bug as before; reboot clears it). No A/B result. Build 8 (NMXGPU 39d039f3 = build 7 + patches/amdgpu-ringdump2.patch: dwords around the hardware RPTR, CP_RB0_BASE/CNTL, IB1 base/bufsz) is INSTALLED, loads at the next boot. Next boot: run render-stress ONCE (background, bounded), read `ringdump hw rptr` / `rptr+xx` lines of the first failing job, then run nmx-tune A/B only if the first test fails to explain the stall; never run wc-ab as a first step (it multiplies hung processes).

## Step41 - build 11 (everything in one kext, no more A/B)

Owner decision: stop A/B and test-read-reboot loops; ship one complete kext and trace on Linux if it still misbehaves.
Data already in hand (Step40): the gfx failure is the CP stalled fetching an IB (INDIRECT_BUFFER, IB1 0x8001_0002b000, 0x38 dw,
CPF_STALLED_STAT1=1) with no UTCL1 fault; force-WC GTT (build 10, c4e26ec4) did not remove the strict pass/fail alternation, so
CPU->GPU coherence of GTT pages is not the cause. A translation that retries forever looks exactly like this (no fault reported).
Build 11 = build 8 contents (ringdump2: ring around hw RPTR) + `amdgpu-noretry.patch` (retry faults off by default: a bad
translation now faults and is reported instead of stalling the CP) + `amdgpu-ibdump.patch` (timeout dump prints the failing
job's IB gpu_addr/length and first 96 dwords, for comparison with the same triangle on Linux/RADV).
Build 11 = NMXGPU d2c08472, INSTALLED (loads at next boot).

Step41b: build 12 NMXGPU 0309394d INSTALLED (loads next boot) = build 11 + per-gfx-job 'NullMoth vmflush' trace (vmid, pasid, pd, flush flags) + 'NullMoth vmregs' dump (GCVM_CONTEXT0-7 PT_BASE/CNTL, INVALIDATE_ENG0 REQ/ACK/SEM, L2 status). Run render-stress once after boot; compare the failing job's vmid/pd with the previous passing job.

## Step42 - M3 audit: what "non-headless accelerator" actually means (no reboot needed)

Source: fork `kexts/NVRM/accel/nvrm-accel.cpp` (class NVAccel, built as NMXAccel with `-DNMX_ACCEL`).
* Under `NMX_ACCEL`, `start()` hard-sets `gNvHeadless=1` and property `NMXAccelHeadless` (line ~620-626) and skips the
  framebuffer-watch / MetalPluginName-withhold / arm path. So today NMXAccel offers a Metal device to apps only; frames are
  copied by the Metal plugin into the framebuffer that WindowServer draws on (the CPU software rasteriser = our 400-950% CPU).
* The NVIDIA path that DOES give WindowServer the GPU is the "armed" path: NVRMFB head publishes -> `fbPublished` ->
  `debug.nvaccelfb=1/3` -> `NVDisplayPipe::initFramebufferResource` (scanout gate) -> mode change delivered. That path is wired to
  `NVRMNVDAFramebuffer` (NVIDIA scan-out). There is no AMD equivalent: nothing publishes an IOFramebuffer owned by NMXGPU
  (the panel is still driven by StrixGOP/GOP framebuffer).
* M3 therefore = (a) an NMX IOFramebuffer/display pipe on amdgpu DC for the eDP OLED (or adopt StrixGOP's framebuffer as the
  scan-out resource for NVDisplayPipe), (b) remove the forced headless in the NMX_ACCEL branch and arm like the NVIDIA path,
  (c) allow-list WindowServer. Not testable until M2 (graphics jobs reliable) - a hung job in WindowServer = black screen.
Order stays: reboot -> build 12 data (vmflush/vmregs) -> fix M2 -> then M3 (a)-(c) in one kext. Nothing installed in this step.

## Step43 - build 12 data decoded: the CP stalls on the ring fetch, and it knows the wptr

Read of the build 12 (0309394d) boot of Oct 19 16:12, first `tools/890m/render-stress.sh` run at 16:23
(raw `kernel: (NMXGPU)` lines, not the script's filtered copy).

Retraction first. `amdgpu_dev_coredump.c` and `gfx_v11_0_print_ip_state()` include `gc/gc_11_0_0_offset.h`, but the
hardware is GC 11.5 (890M/gfx1150) and the whole **GCVM/GCMC block is 4 dwords higher** in
`gc_11_5_0_offset.h` (`CONTEXT0_CNTL` 0x1688 -> 0x168c, `INVALIDATE_ENG0_REQ/ACK/SEM` 0x16ab/0x16bd/0x1699 ->
0x16af/0x16c1/0x169d, `L2_CNTL` 0x15bc -> 0x15c0, `PAGE_TABLE_BASE_ADDR_LO/HI` 0x16f3/0x16f4 -> 0x16f7/0x16f8).
So the build 12 `vmregs` line read other registers: "ctx4/5 CNTL 0x01fffe01/0x01fffe07" are really CONTEXT0/1 CNTL
(contexts **enabled**), "ctx2/3/4 PT_BASE" are really CONTEXT0..2, and the INV_REQ/ACK/SEM and L2/FAULT_ADDR values
are meaningless. Everything derived from them in Step41b ("context 0 disabled", "INV_ACK=0x02f80000",
`FAULT_ADDR=0xffffffff00060000`) is withdrawn. CP block offsets (`RB0_BASE/WPTR/RPTR/CNTL`, `IB1_*`) are identical
in both headers, so those readings stay valid.

What the valid registers say (16:23:38, first gfx timeout of that boot):

* `CP_RB0_CNTL = 0x08a0080a`: RB_BUFSZ=10, RB_BLKSZ=8 (8K ring / 2048 dword), MIN_AVAILSZ=2,
  MIN_IB_AVAILSZ=2, RB_NO_UPDATE=1. Decoded with the 11.5 field list this is the normal GFX11 configuration
  (`rb_bufsz = order_base_2(ring_size / 8)` for an 8192-byte ring), so the ring setup is not the bug.
* `CP_RB_VMID = 0` (ring is fetched in the GART context), `ring gfx_0.0.0 uses VM inv eng 0 on hub 0` - identical to
  the known-good Linux probe in `890M-LINUX-DUMP.md`, so the invalidation-engine allocation is right.
* `CP_CPF_STALLED_STAT1 = 0x1` = **only RING_FETCHING_DATA**. `INDR1_FETCHING_DATA` (bit 1), `UTCL2IU_WAITING_ON_*`
  (7/8) and `GFX_UTCL1_WAITING_ON_TRANS` (9) are all 0: the CP is waiting on **ring data**, not on the IB and not on
  an address translation. `CP_CPF_BUSY_STAT = 0x6` (CSF_RING_BUSY | CSF_INDIRECT1_BUSY), `CP_BUSY_STAT = 0x80`
  (PFP parsing packets).
* `CP_ME_HEADER_DUMP = 0xc0023f00` (INDIRECT_BUFFER) and `CP_IB1_BASE = 0x8001_0002b000`, size 0x38 dw are the
  **previous** job's IB: the ME never entered the job at rptr.
* `CP_RB0_RPTR = 0x13a` is the start of the next job's INDIRECT_BUFFER packet, and `CP_RB0_WPTR = 0xb00` (masked
  0x300) shows the CP **does** know about the new work. So the wptr/doorbell delivery is not what is stuck.
* `ring gfx_0.0.0 timeout, signaled seq=6, emitted seq=8`: six jobs ran, the seventh stopped at its first ring dword.
* The driver is 2502 dwords ahead of the rptr on a 2048-dword ring, i.e. it overran a full ring while the CP sat
  still. That is a consequence, not the cause: `amdgpu_ring_alloc()` only checks `ndw > max_dw`, the space is not
  re-checked per submission.

So the failing operation is a **ring read at rptr that never produces data**. Two mechanisms survive, and the build 12
data cannot separate them:

* H1 - the ring bytes the CP fetches are stale (write-back kernel mapping / non-snooping CP). The empty part of the
  ring is `PACKET3_NOP` with count 0x3FFF = 16384 dwords = **exactly 8 rings**, so a stale NOP at 0x13a makes the CP
  skip 0x4000 dwords, land on 0x13a again and loop with RPTR never changing - which is what every sample shows.
  Note `mb()` in the port is a real `mfence`, so the barrier was never the missing piece; the *wptr page* was: the
  flush in `amdgpu_ring_commit` covered `wptr_old..wptr` of the ring only, while the CP reads the wptr itself from
  `CP_RB_WPTR_POLL_ADDR = ring->wptr_gpu_addr` (a write-back kernel mapping) and `gfx_v11_0_ring_set_wptr_gfx()`
  only did `atomic64_set(ring->wptr_cpu_addr, ...)` before the doorbell.
* H2 - the read really hangs on the fabric (bad GART PTE / wrong physical address). For this one the build 12 dump
  has no usable value, because exactly the registers that would show it (`GCVM_L2_PROTECTION_FAULT_STATUS/ADDR`,
  `INVALIDATE_ENG0_ACK`) were read at the 11.0 offsets.

Build 13 (`ac3edcd7`, 10,812,792 B) tests both at once - one reboot, one run:

1. `gfx_v11_0_ring_set_wptr_gfx()`: `clflush` the wptr writeback line and `mb()` before `WDOORBELL64`.
2. `amdgpu_ring_commit()`: flush the whole 8K ring instead of the `wptr_old..wptr` range (removes the range/wrap
   arithmetic from the picture).
3. `amdgpu_dev_coredump.c`: every GCVM read shifted by +4 dwords for GC 11.5 (+PFLT_CNTL/PFLT_STATUS,
   CP_RB_VMID/WPTR_DELAY/DOORBELL_CONTROL/WPTR_POLL_ADDR/RPTR_ADDR), plus ring state (`use_doorbell`, `wptr`,
   `wptr_old`, software rptr, **rptr read from the writeback memory**, hardware rptr and a second hardware rptr
   sample 5 ms later).

Patch: fork `0fe7d66` (`gpu-port/xkpi/patches/amdgpu-wptr-flush-b13.patch`, applies last over the existing set).
Expected readings after the reboot:
* if the run passes and `hw_rptr == hw_rptr_5ms` moves on -> H1 (visibility) and the wptr-page flush was the cure;
* if it still hangs and `PFLT_STATUS`/`FAULT_ADDR` are non-zero -> H2, with the faulting address;
* if it still hangs with no fault and `hw_rptr == hw_rptr_5ms` -> the CP is looping on the ring (H1 variant that the
  flush does not reach), and the next step is the ring BO's cache attribute, not more ring flushing.

## Step44 - build 13: the wptr page was not it; the trigger is the SECOND VM, not the second job

Build 13 (`ac3edcd7`) installed and booted (20:16). `render-stress.sh 6`: run 1 PASS, 2 FAIL, 3 PASS, 4 FAIL,
5 PASS, 6 FAIL (3/3), i.e. the same alternation - flushing the wptr writeback page and the whole ring changed nothing.

What the corrected (GC 11.5, +4 dword) diagnostics finally say, first timeout 20:18:

* `PFLT_STATUS = 0`, `FAULT_ADDR = 0`, `L2_STATUS = 0` -> no protection fault, no bad translation. `noretry` is set
  (`RETRY_PERMISSION_OR_INVALID_PAGE_FAULT = 0`), so a missed PTE would have been reported, not retried forever.
* `INV_REQ`/`INV_ACK` mirror each other (`0x00f80004`/`04`, `0x00f80010`/`10`, `0x00f80040`/`40`, `INV_SEM = 1`):
  every invalidate the driver asked for was acknowledged.
* `CONTEXT0..2` enabled, `PT_BASE` 0x87fb00001 / 0x87fafc001 / 0x87fafb001, `PAGE_TABLE_DEPTH = 3` (4 levels),
  `BLOCK_SIZE = 0` (9-bit), same for every context - the context programming is consistent.
* `CP_RB_VMID = 0`, `CP_RB_WPTR_DELAY = 0`, `CP_RB_DOORBELL_CONTROL = 0xc0000458` (doorbell on, offset 0x458),
  `CP_RB_WPTR_POLL_ADDR = 0x7fff00401060 = ring->wptr_gpu_addr`, `RPTR_ADDR = 0x7fff00401040`, ring `0x7fff0064d000`.
* `cpstate`: `doorbell 1 wptr 2816` and `CP_RB0_WPTR = 0xb00` - the CP has exactly the driver's wptr. `hw_rptr` sampled
  twice 5 ms apart was identical both times (0x13a/0x13a, 0x14e/0x14e): the CP stands still.
* `sw_rptr`/`mem_rptr` (0x100 / 0x300) lag the hardware rptr (0x13a / 0x34e): the GPU-writes-visible-to-CPU direction is
  still broken, but that is a symptom we already knew about, not the stall.
* `ringdump` at the rptr decodes as one complete submission: `INDIRECT_BUFFER` (IB `0x8001_00001000`, 0x1d8 dwords,
  vmid 2) -> `FRAME_CONTROL` end -> `RELEASE_MEM` (gfx shadow) -> `COND_EXEC` (cond_exe_gpu_addr) -> `RELEASE_MEM`
  (the ring fence, seq) -> NOP fill. The ring side is complete and correct, and the fence sits **after** the IB: a
  stall inside the IB explains both "RPTR pinned at the IB" and "the fence never signals".

So `CP_ME_HEADER_DUMP = 0xc0023f00` is the ME executing that IB, not a stale earlier header.

Isolation (`tools/890m/metal-render-loop.swift`, new): the same triangle N times in **one process** (one VM) is
6/6 CORRECT, twice. The same triangle from a **second process** fails on its first submission after ~250 ms
("GPU event segment submission failed"), then the kernel job timeout + GPU reset. It also fails while the first
process is still alive and holding its device (no teardown, no BO free), so the ingredient is the **second VM**, not
the first process exiting and not the second submission.

Consequences:

* Dead: wptr/doorbell delivery, ring content visibility, ring/wptr flushing, invalidate-engine selection, translation
  faults, memory pressure on the ring. All checks out.
* The defect is in the per-VM path - the second VM's PD/PT/VMID setup or the IB its job points at - and it makes the
  first job of any VM other than the one that started right after a GPU reset read something the CP cannot execute.
* The "first VM after a reset works, the next one fails" rule is a consequence, not the rule: after a reset only one VM
  exists, and as soon as a second one appears it fails.

Build 14 (planned, not built): for a user IB amdgpu keeps no kernel pointer (`ib->ptr` is NULL), so the coredump
cannot print what the CP was asked to run. Add a VM-mapping lookup that kmaps the IB's BO and prints the first 96
dwords at timeout, dump the PD/PT walk for the same VA, and flush the IB's lines just before `emit_ib` - one build
that either fixes it (stale IB content) or names what the CP is really reading (wrong page / wrong PTEs).

## Step45 - Oct 19 Apple-logo boot failure: missing VBIOS; direct PCI ROM fallback installed from Linux

Read-only decode of Persist `16f` and `170`: boot E818A3CA1ECF46D695F10A0F0D0B4BF8 starts at
20:42:10 +0700. At 20:42:18.894, `drmn0: Unable to locate a BIOS ROM` -> `Fatal error during GPU init` ->
`attach failed (22)` -> `no driver took 1002:150E`. NMXAccel waits for NMXGPU to claim the device. WindowServer
then asserts approximately every ten seconds, through 20:49:21. CoreDisplay's 20:48:09 report says
`FB: 0 of 1 opened`, `IOFramebufferOpen` error `0xe00002c7` on NVIDIA PEGP/IONDRVFramebuffer, and
`MappedDisplay.cpp:5509`. This boot fails to bring up a display; there is no new kernel panic report.

StrixVFCT is enabled on the ESP and its 21636-byte payload passes its checksum. The failure is not explained by
a missing EFI bundle. The ACPI shim searches the published IOService tree; timing and its first-dictionary selection
remain hypotheses, not proven root causes. The installed NMXGPU binary (modified 20:38) has SHA256
`b5b573db11bc52ffd5791bffc0efaefdef93b4f64f8af0943adc169132648958`.

Fix applied to the live ESP: `tools/890m/inject-vbios.py` extracts the exact 101:0:0 1002:150e image from StrixVFCT,
checks VFCT length/checksum and the ROM's ATOM header, then adds it as Data property `vbios` on
`PciRoot(0x0)/Pci(0x8,0x1)/Pci(0x0,0x0)`. The existing port supports this path:
`amdgpu_get_bios_apu` -> `amdgpu_read_bios` -> `linuxkpi_pci_map_rom` -> `vga_pci_map_bios` ->
`nmx_xnu_pci_rom`, which checks `vbios` before attempting the ROM BAR. The firmware is 21504 bytes, SHA256
`7375149330e753a4f5903cb9087a79fdab008d02856ca72366a40e6dcfde1777`; firmware and private EFI configs stay outside Git.

Only `vbios` changes: preserve `#display`, boot arguments, the cobalt framebuffer and installed kexts. Do not
enable StrixGOP alongside NMXGPUFB as part of this fix (Step29 documents the duplicate-framebuffer failure).
The prior suggestion to restore StrixGOP is therefore superseded by this narrower fix. No AuxKC rebuild is needed
for a PCI property supplied by OpenCore.

Validation: malformed/truncated/checksum-invalid VFCT inputs rejected, candidate differs from original only by
the extracted `vbios` bytes, candidate and installed config pass ocvalidate 1.0.9. Original config backed up under
`~/ga403-logs/boot-review-20261019/`. Hardware verification is pending: boot macOS and confirm VBIOS acquisition
(the fallback logs `Fetched VBIOS from ROM BAR` even when supplied by the property), successful attach and a stable
WindowServer. This fixes the missing-ROM path; the separate second-VM graphics hang from Step44 remains open.


## Step46 - current boot, dead build-14 IB hook fixed, reproducible build batch (2026-10-19)

Pulled the main repo to `b78a1d7` and the NMX fork to `33fa7fb`. Actual boot is macOS 26.7.1 / 25G241,
21:22:57 local. Loaded NMXGPU UUID `80D4A3FF-1840-3AF3-8219-1E007B0CEB11` matches the installed binary
SHA256 `b5b573db11bc52ffd5791bffc0efaefdef93b4f64f8af0943adc169132648958`. NMXAccel is loaded;
StrixGOP/StrixAccel are not the current scan-out path. Kernel logs show `Fetched VBIOS from VFCT`, successful
amdgpu attach, DCN 3.5 and OLED 2880x1800 @120 Hz. The direct PCI `vbios` fallback remains present but this boot
used VFCT; successful attach does not establish that the fallback itself was exercised.

One bounded, sequential two-process render check of this newly booted build: first VM **3/3 correct** (1-2 ms,
RGBA `[255,128,64,255]`); second VM fails its first submission at 252 ms. At 21:27:32 the GFX timeout has
hw RPTR `0x53a` unchanged over 5 ms, WPTR `0xf00`, and no GCVM protection fault. The second process reused the
same PD/PASID as the first (`87fafc001` / 32769), but received VMID 2 instead of 1. This further narrows the
observation to a new client/VMID/context transition; it does not prove the page tables are the root cause.
No repeated stress/benchmarks or WindowServer allow-list changes were performed.

### Why build 14 did not flush or dump any user IB

`amdgpu_job_prepare_job()` explicitly clears `job->vm` once the VMID is assigned, before `amdgpu_job_run()` ->
`amdgpu_ib_schedule()`. Build 14's `nmx_ib_prepare()` immediately returns on that NULL VM. The timeout dump has
the same dead guard. Independently, its lookup uses canonical/sign-extended addresses directly, unlike the
existing CS/GEM paths, which mask with `AMDGPU_GMC_HOLE_MASK`. The installed binary's assembly confirms a bare
`shrq $12` followed by `amdgpu_vm_bo_lookup_mapping`, with no mask. Consequently, this boot does **not** test
whether flushing the actual user IB fixes the hang.

Build 15 moves preparation into `amdgpu_cs_patch_ibs`, after BO reservation and before VM handling/job enqueue.
It uses the existing reservation-checking `amdgpu_cs_find_mapping`, masks the VA, validates mapping and BO bounds
with 64-bit arithmetic, flushes every cache line of the GFX IB, and issues the memory barrier before enqueue.
It removes the unreachable scheduler hook. A bounded 96-dword first-IB snapshot is owned by each job, so timeout
reporting never walks a VM/BO whose lifetime has ended. The snapshot is the CPU view at submission, not proof
of what the CP fetched, and does not include chained IBs or all shader/descriptor memory.

### Build reliability defect discovered and fixed in the same batch

The old `all.sh` reapplied patches alphabetically with every failure suppressed. This reinserted the obsolete
IB call after its helper had been removed, and duplicated the GCVM diagnostic block. A real compile failure
(`nmx_ib_prepare` undeclared) still produced a linked kext using the previous object (`03d85486`): that artifact
is rejected and **must not be installed**. The legacy b14 patch also contained blank lines as internal context
that do not exist in vendor HEAD; its context is normalized without changing that historical implementation.

An explicit `patches/series` now names all patches in dependency order. `apply-patches.py` replays them on vendor
Git HEAD in a temporary tree with zero fuzz, validates every destination against known intermediate/final
contents, refuses unknown edits, and only then updates changed sources. Repeated replay is an identity operation.
`all.sh` and `rt.sh` return failure when compilation fails; `one.sh` deletes an old object on failure; direct
linking refuses outstanding compile-failure markers. No vendor checkout reset/clean is used.

Validation: the actual IB helper passes 11 host cases (canonical VA, BO offset, snapshot bounds, mapping/kmap
errors, non-GFX/empty/kernel-IB skips). Patch replay tests pass clean application, repeat identity, preservation
of unknown edits, removal of stale objects and direct-link refusal. These tests do not establish GPU reliability.
The sanitizer-enabled host executable terminated with SIGILL on this host; the successful helper checks use the
normal compiler runtime and are not claimed as an ASan/UBSan pass.

### REA boundary and evidence

Applied the `reverse-engineer-anything` skill. REA opened the actual installed NMXGPU and `inspect_macho`
returned UUID/SHA identity matching the loaded kext (parent evidence
`ev_5d5bb88f479ecc766450f761d1d923cfccbbb37a51bc87a7ae664c15f754af9d`). Deep assembly was unavailable:
Ghidra/Java, Hopper, IDA and Kuna providers are not configured/installed. No downloads or configuration changes
were made. Used the existing `xcrun llvm-objdump` for the focused function instead; REA session closed.
Private raw evidence: `out/890m-trace/step46/` (`two-vm.txt`, `kernel.txt`, `ib-schedule.asm`, host/replay test logs,
source reconciliation backup, build logs). Build/install completion is recorded below when verified.


### Build15 completion

Fork commit `05562f5` is pushed to `fork/ga403wm-nmx`. Final driver rebuild: **900/900 compiled, failed 0**;
runtime rebuild: **76 sources, failed 0**. Binary SHA256
`c5dea0e09c96981cd186036831c6dd03ad3f81087156eea7820c1d5d198c61ee`, UUID
`304F821C-A6F0-323B-8328-DC580234D3AF`, 10,812,824 bytes. Vendor HEAD:
`c16de0f9fa84f70b9551f69fde837a7f3a73c0e9`. Candidate directory is
`~/develop/projects/gpu-src/out-b15/NMXGPU.kext`; do not confuse it with stale `gpu-src/out`.
`candidate-patch-jobs.asm` confirms `_amdgpu_cs_find_mapping` and `clflush` inside `_amdgpu_cs_patch_jobs`;
strings contain `ibprep b15`/`ibsnapshot b15` and no old `ibsub`/`ibmap` hook. Build manifest is saved privately.
Both host suites pass and the changed shell scripts parse. A build interrupted while its script was being
revised was also rejected; the final run used a frozen copy and compiled every driver source successfully.

The pipeline also keeps an incomplete marker until each stage succeeds; direct linking refuses either
runtime/driver marker even when compile-failure files have been cleared. Host checks include this case.
Installation was started through the normal administrator dialog, with a hash-checked candidate and a separate
backup of the currently installed kext. Its result is recorded next; hardware reliability remains unverified
until this new binary has actually been booted. No new WindowServer Metal access has been enabled.


### Build15 installed — reboot pending

Administrator install completed successfully. Installed hash matches the verified candidate and `AuxKC rebuilt`
was returned. `kmutil inspect` lists NMXGPU and the new UUID bytes are present in AuxKC. Separate backup:
`/Library/NullMoth/nmxgpu-step46-20261019T143851Z/NMXGPU.kext`. Runtime remains the old loaded build14 until reboot.
After reboot verify UUID `304F821C-A6F0-323B-8328-DC580234D3AF` before running a single bounded two-VM check.
This batch fixes proven dead preparation/build paths; the second-VM graphics hang and WindowServer acceleration
are **not yet verified fixed**. Keep rung 1 and do not add WindowServer/headroom-hold during that check.

## Step47 - Linux after build15 reboot: early TLB/IPI panic recovered from NVRAM

Pulled main repo to `f7b37a0`. Installed NMXGPU still matches build15 SHA256
`c5dea0e09c96981cd186036831c6dd03ad3f81087156eea7820c1d5d198c61ee`; the build15 UUID is present in AuxKC
(mtime 21:38:54 +0700). Live ESP still has the exact 21504-byte PCI `vbios` fallback from Step45.

Important evidence boundary: Persist `173`/`174` decode to the **previous** boot
`725E7CAFA2AB47F5AA15C4E822EE8968`, ending in logout/shutdown at 21:44:31. That boot reached the desktop
(`loginwindow USER_PROCESS` at 21:23:46). It is not a log of the reported new logo freeze. There is no new
on-disk Kernel panic report, no new graphics-bootstrap directory after 21:23, and no later persisted unified-log
boot in the two latest files. Do not reuse the old missing-VBIOS diagnosis for the latest freeze.

Recovered all ten `AAPL,PanicInfo0000`..`0009` EFI variables read-only (strip each 4-byte efivar attribute header,
concatenate in numeric order, unpack little-endian 7-bit ASCII). They contain a readable panic absent from the
on-disk reports, at uptime **11.627151386 seconds**:

```
NMIPI for unresponsive processor: TLB flush timeout
CPU 0: _thread_go <- _thread_wakeup_prim <- VoodooI2CControllerDriver::handleInterrupt+0x138
       <- AppleAPIC <- AppleACPIPlatform (nested interrupt frames)
CPU 12: IPI timeout, unresponsive CPU bitmap 0x1, pmap.c:3101
        _pmap_flush_tlbs <- _pmap_remove_range <- ... <- OSSerialize::free
        <- OSKext::serializeLogInfo <- OSKext::handleRequest
        process: kernelmanagerd
```

`nullmoth-gpu-attaching` currently contains `1`: an NMXGPU attach did not clear its guard. This is consistent
with an early failed boot during attach, but neither the marker nor the retained panic contains an absolute
boot timestamp or the loaded NMXGPU UUID. Exact association with build15 is therefore probable, not proven.
Unlike the Oct18 GPU-reset panic, this retained panic does **not** have amdgpu/MES in its captured stacks.
VoodooI2C is on the unresponsive CPU's interrupt/wakeup path; that alone does not establish it caused the lockup
(a scheduler lock held by another CPU or interrupt-state corruption remains possible). There is no Wi-Fi frame
in this report. Do not claim a proven VoodooI2C, Wi-Fi or NMXGPU root cause from this stack alone.

Private evidence: `~/ga403-logs/boot-review-20261019-b15/` holds raw EFI panic chunks, decoded panic, marker,
and previous-boot JSONL. No EFI, NVRAM or installed kext mutation was made in this investigation. A subsequent
boot with the guard still set can park NMXGPU and leave no display; that must not be mistaken for another
driver attach attempt. Next diagnostic work needs persistent stage/CPU tracing through NMXGPU attach and the
interrupt/critical-section paths, with a recoverable display plan, rather than another uninstrumented reboot.

## Step48 - subsequent logo freezes confirmed as the stale attach guard; cleared once from Linux

The next persisted logs (`175`/`176`) now establish the immediate cause of the repeated logo boots:

* 21:53:24.338 +0700: `NullMoth GPU: the last attach of 1002:150E never returned ... this GPU stays with macOS`.
* 21:56:17.019 +0700: the same guard message on another boot. Neither boot attempts amdgpu attach after that check.
* NMXAccel waits for NMXGPU to claim 1002:150e; CoreDisplay reports `FB: 0 of 1 opened`, NVIDIA's remaining
  IONDRVFramebuffer fails to open (`0xe00002c7`), and WindowServer asserts at `MappedDisplay.cpp:5509`.

An on-disk `Kernel-2026-10-19-215321.panic` has now appeared. Its uptime `11627151386` matches the Step47
NVRAM report exactly: the retained TLB/IPI panic was real, rather than a hypothetical missing-ROM failure.
The filename records report processing on the subsequent boot; it does not establish the failed boot's start
time. The captured blocked CPU is in VoodooI2C's interrupt/wakeup path, not the older amdgpu MES reset path.
The original early panic's cause remains unresolved; clearing the guard does not repair that cause.

Recovery applied on Oct20: copied the exact efivar to private evidence, then used administrator authentication
(`pkexec`) to remove **only** `nullmoth-gpu-attaching-7c436110-ab2a-4bbb-a880-fe41995c9f82`, after verifying its
payload was `1`. Linux's efivar immutable flag was cleared for that variable before deletion. Verified that
the variable no longer exists. This is a one-time clear, not an OpenCore NVRAM/Delete entry: the driver can
still set the marker and park a future failed attach. No panic variables or unrelated NVRAM were deleted.

Live EFI also has `-v` added for visible early-boot diagnostics, with a private config backup and a passing
ocvalidate 1.0.9 result. All other config values, the PCI `vbios`, `#display` identity, installed kexts and AuxKC
are preserved. No build was performed because these changes affect an EFI variable and a boot argument.
Private evidence is under `~/ga403-logs/boot-review-20261020/`.

Verification still requires hardware: the next boot should actually enter NMXGPU attach rather than immediately
park. A successful boot would show recovery from the stale guard, not proof that the TLB panic is fixed.
If the early panic repeats, preserve the verbose stop/backtrace and NVRAM panic before another retry; do not
automatically clear the guard on every boot or attribute it to Wi-Fi without evidence.


## Step49 - build15 boot: second-client regression passes, including simultaneous VMs (2026-10-20)

Boot 09:18:02 local, macOS 26.7.1. Loaded NMXGPU UUID is
`304F821C-A6F0-323B-8328-DC580234D3AF`; installed SHA256 remains
`c5dea0e09c96981cd186036831c6dd03ad3f81087156eea7820c1d5d198c61ee`. NMXAccel is loaded;
StrixGOP/StrixAccel are not. This is the verified build15 from Step46, with no new installation or reboot request.

One bounded pair of sequential processes, 3 triangles each: **6/6 correct** on the actual RADV STRIX1 Metal
device. VM1 uses VMID1, VM2 uses VMID2 with the same reused PD/PASID, matching the formerly failing transition.
All readbacks are `[255,128,64,255]`. Completion times are 1-2 ms except one 68 ms completion in VM2; this is
not a desktop performance measurement. `ibprep b15` fires for actual submissions (outer IB 56 dwords,
VA `ffff80010002b000`, first word `c0023f00`), proving the former dead preparation path now executes.

One distinct coverage case then holds the first device/VM alive for 10 seconds and submits from the second
process. Initial renders **6/6 correct**, plus **5/5 correct** probes from VM1 while/after VM2 runs. Both
processes exit 0. Kernel traces establish distinct active clients, not merely PD reuse:
- held client: VMID3, PASID32769, PD `87fafc001`;
- second client: VMID4, PASID32770, PD `87faf2001`;
- subsequent held-client work returns to VMID3 with pipeline sync.

Across the recorded boot/test window: **0 GFX timeouts, 0 GPU reset-begin events**, 38 `ibprep b15` events.
No repeated unchanged stress loops. These checks establish a pass for the old sequential/concurrent two-client
reproducer; they do not establish arbitrary workload or long-duration GPU reliability. The preparation/kmap/
flush change is the source-backed effective fix in this batch; the exact cache/alias mechanism and chained-IB
visibility have not been isolated independently. Do not reopen the old VMID-programming hypothesis as fact.
Private evidence: `out/890m-trace/step47/{two-vm.txt,concurrent-vm.txt,kernel.txt,result.json}`.

WindowServer PID903 survives the checks; a single ps reading is 154.3% CPU, not a before/after benchmark.
High CPU is not fixed by an app-only Metal pass. Source still hard-sets `gNvHeadless=1` and
`NMXAccelHeadless=true` under `NMX_ACCEL` (`kexts/NVRM/accel/nvrm-accel.cpp`, around lines620-625), skipping
framebuffer-watch/arming. The next milestone is the accelerator/display-pipe binding to the native AMD OLED
framebuffer, including resource ownership and presentation; do not simply widen the Metal allow list or claim
WindowServer acceleration. Existing AMD DC scan-out must be preserved. No WindowServer/headroom-hold allow-list
or power/security setting was changed in this verification batch.


Integration note: Step47/48 from the Linux recovery session arrived while these verification notes were being
pushed and are preserved above. This successful attach demonstrates recovery after the one-time stale-guard
clear; it does **not** resolve the separate early TLB/IPI panic. Keep that attach/interrupt investigation open
before treating the machine as generally stable or widening WindowServer exposure. Step49 raw files retain
`step47` in their local directory name because they were collected before the concurrent notes were fetched.


## Step50 - native AMD display-pipe batch built and installed (2026-10-20)

The Step49 multi-client pass is preserved. This batch addresses the next real blockers instead of repeating
those renders: NMXAccel forced headless and never watched the native framebuffer; NMXGPUFB exposed no scanout
query to the pipe; the existing plugin rejected **all** non-NVIDIA WindowServer devices before the allow list;
NVIDIA device-cache/VRAM paths are not AMD memory management.

### Changes

NMX fork `b5ce9e2` (`ga403wm-nmx`):
- NMXGPUFB exposes its existing, live DCN scanout to the display adapter using the frozen scanout request ABI.
  It checks version/geometry/size and waits until IOFramebuffer open has assigned its controller. CPU physical
  addresses are not advertised as NVIDIA VRAM or RADV GPU VAs: the query returns a CPU mapping, `phys=0`, no handle.
- NMXAccel watches only NMXGPUFB on its **own PCI provider**. An asynchronous arm retries NotReady at 200 ms,
  at most 30 seconds; driver matching never waits for WindowServer open. A pending reference and registration lock
  cover callback/stop lifetime. It handles an already-created family pipe without allocating a duplicate.
- The native path is gated to the exact reviewed 25G241 kernel string. It sets the family's UMA/system-memory
  allocation bit and IOSurface type 0x80 instead of asking NVIDIA RM for a device cache. The family resource
  `prepare()` remains real: **no forced success and no fabricated GPU page-table address** were added.
- Only after exact framebuffer/pipe ownership is established does it publish `NMXDisplayPipeArmed=true` and clear
  `NMXAccelHeadless`. Diagnostics are `debug.nmxaccel_{headless,armed,iop_ok,iop_fail}`.
- Presentation accepts the existing BGRA IOSurface path and copies ordered rows into the native DCN scanout.
  NVIDIA flip/page-off/VRAM paths are skipped for this adapter. **This is GPU rendering plus CPU transfer, not
  zero-copy or a native AMD page-flip implementation.** Remaining copy cost is not claimed fixed.

Plugin worktree `~/develop/projects/890m-ws-plugin`, branch `research/890m-ws-plugin`, commit `2b2620c`:
- Kept the current **upstream 2.3.1 + GA403** source baseline (`805e77a`), rather than reverting the plugin to
  NMX's older 2.0.4 tree or installing 2.3.6. Existing translate/air-runtime/codec/Vulkan/libdrm files are retained.
- AMD WindowServer is eligible only when the **selected NMXAccel port** publishes a true Boolean owned-pipe gate.
  NVIDIA keeps its own headless/sysctl policy; AMD readiness cannot arm NVIDIA and vice versa. The allow list
  remains another required condition, including armed-only entries.
- Eight host policy cases cover owned/unowned AMD, headless NVIDIA, cross-vendor isolation and unsupported vendors.
  Both source commits are pushed to the owner's fork; no PR/issue was created.

### Validation and install

New BSD tool `tools/890m/metal-iosurface.swift` draws a real Metal triangle into a 64x64 BGRA IOSurface and checks
both texture readback and the surface CPU memory. With the prior plugin: both `[64,128,255,255]` reads CORRECT,
completed in 3 ms. After deployment of the rebuilt 2.3.1 plugin: a fresh **unprivileged** nvmtltest process on
RADV STRIX1 returns both reads CORRECT in 4 ms. These are data-path checks, not performance benchmarks or proof
of WindowServer GPU use. No unchanged multi-client stress was rerun.

Context7 was consulted for the Metal/IOSurface API; it returned unrelated bindings rather than an official SDK
entry. Used the installed SDK's MTLDevice.h declaration plus Apple's
[makeTexture(descriptor:iosurface:plane:) reference](https://developer.apple.com/documentation/metal/mtldevice/maketexture(descriptor:iosurface:plane:))
instead. The SDK header explicitly describes creating a texture from the given IOSurface plane.

NMXAccel and the changed NMXGPU framebuffer TU compile/link successfully. The NMXGPU relink retains the existing
successful build15 runtime/900-source objects and IB fix; it is **not** another full 900-source rebuild. The plugin
build succeeds (existing protocol/deprecation warnings remain), is signed, and the installed bundle verifies.
Added reproducible build/manifest and transactional installer scripts. The installer validates candidate hashes,
backs up both kexts/plugin/allow list/AuxKC, tests the deployed plugin before changing kernels/policy, verifies
both new UUIDs in AuxKC, and restores the whole batch on failure. It does not restart WindowServer, reboot,
clear the attach guard, or change power/security/EFI settings. An existing attach marker causes refusal.

Installed successfully; backup `/Library/NullMoth/nmx-ws-20261020T023645Z`:
- NMXGPU SHA256 `0456558e65a8109f020d9945c137280378a327ccf17129f5657082316c440edb`,
  UUID `7FB0A912-7ECC-3597-B51F-55266CBA4F0C`.
- NMXAccel SHA256 `63026c11a410bbe5200216ac50d1b87f09cd9edb364557c306d6ef71ef76e02d`,
  UUID `1043D6C4-4189-3A44-88AE-0C5DD4085A20`.
- Deployed plugin SHA256 `d5ad4d06a3520c80eddde0d0043cf5da3889419c77770ae02185868347125347`,
  UUID `BCC4C4B9-7EC7-3739-B5EA-0788C03FA501`. Bundle signing changes its staged file SHA.
- Existing narrow process policy plus `!WindowServer`; no wildcard, headroom-hold or broader app permission added.

Private evidence: `out/890m-trace/step50/` (build logs, baseline/deployed IOSurface checks, policy test,
candidate/installed manifests and install log). Running kernel is still build15/NMXAccel's prior UUID, PID903
WindowServer remains alive and headless=1. **Reboot pending; WindowServer acceleration is not verified.**

### After the next boot

First confirm both loaded UUIDs above. Read the native headless/armed/transaction counters and the NMXAccel
registry properties. Then inspect WindowServer's Metal creation / render path and the family prepare/transaction
logs. Pipe registration alone or a successful app triangle is not proof that WindowServer switched to the GPU.
If no arm, inspect `NMXDisplayBindError` and the exact FB/PCI association. If armed but no transactions, inspect
plugin gate and renderer initialization; if resource preparation fails, fix the real UMA allocation/mapping,
never force prepare success. Keep the separate early TLB/IPI panic from Steps47/48 open; this batch does not
claim to repair it. No automatic reboot benchmark or new launch job is armed.


## Step51 — upstream NVIDIA 2.4.2 hybrid work profile (2026-10-20, macOS)

User requested latest NVIDIA upstream installed before reboot, using HDMI for work while continuing
AMD porting in hybrid. This deliberately pauses Step50's pending AMD WindowServer pipe trial;
Step50 was never booted. Native AMD OLED scanout and the working IB preparation fixes stay installed.

### Upstream and policy

Fetched official `nullmoth/nvidia-macos-driver` main/tag v2.4.2, commit
`272ccd9da04ff5de95c2791b902fe17a3fa77ce7`. Release:
https://github.com/nullmoth/nvidia-macos-driver/releases/tag/v2.4.2 . The release fixes the missing
NVIDIA display interface in 2.4/2.4.1; this does not establish the cause of our earlier failed starts.
Release archive SHA256, matched to the GitHub asset digest:
`6f2852d1d1a1f510c0cc11a7710bc35f016550b509dff93b7835f48d69874213`.
Unmodified official installer verified every payload SHA256SUMS entry and runtime compatibility,
preflight-linked the full auxiliary collection, selected macOS26 NVAccel, then installed all four
original release kexts and firmware at `/Library/NullMoth/nvfw`.

Separate worktree `../nvidia-hybrid-2.4.2`, branch `research/ga403wm-hybrid-2.4.2`:
`634a204` retains the AMD owned-display gate, `fa734eb` selects NVIDIA for WindowServer/normal
apps and allows `NVMTL_TEST_GPU=amd` only for dedicated probe names, `bb84efe` disables pool/page
reuse on non-NVIDIA. Pushed to personal fork. The plugin still supports one Vulkan vendor per
process, not simultaneous vendors in one process. Display/headless/armed gates remain real.
NVIDIA retains its upstream reuse path. Allow-list order: `-strix-headroom-hold`, `!WindowServer`, `*`.
The broad application policy is intentional for the requested NVIDIA work profile; the retired
stress helper stays denied before the wildcard. No WindowServer restart or live kext unload/load.

NMX fork `0fe144c` adds personality opt-out `NMXDisplayPipeEnabled=false` (missing defaults to
Step50's existing behavior). Installed false pauses AMD WS binding, preserving native AMD OLED,
NMXGPU and independent AMD Metal. No prior port commits reverted. Older `890m-ws-plugin` worktree
and source branch are preserved for resuming the AMD display experiment.

### Actual failures caught and fixed before reboot

1. NVIDIA guard `nullmoth-nv-starts=%02` blocked this boot's NVRM; old `nullmoth-nv-ok=1` also existed.
   NVAccel was waiting for NVRM then refusing startup. HDMI was physically plugged but not online
   in the current profiler. The counter explains current blocking, not why earlier starts failed.
   Fresh upstream installation clears only its NVIDIA guard flags; NMX attach guard absent and untouched.
2. Saved `/Library/NullMoth/gpu-userland` contained stock libdrm/RADV while the active copies were
   patched. Official updater overlays that saved tree, so an ordinary update would regress AMD.
   Wrapper backs up both trees and refreshes the saved overlay from working active files before
   upstream installation. Every saved active file hash is verified afterward. NVK does not link
   against these AMD libdrm libraries; its Vulkan loader matched the existing loader.
3. First collection preflight rejected GA403 NVRMEdpBL: its dependency NVRM 0.1 cannot link with
   release 2.4.2. The wrapper restored the prior state. Both private imports still exist in NVRM,
   but that does not certify the private `nv_state_t` ABI. The custom NV framebuffer AUX caller
   is absent upstream. Parked the unused NVIDIA-eDP companion in the complete backup, preserving
   its source on `ga403wm`; hybrid OLED belongs to AMD. No speculative version relabeling.
4. Next installed plugin's real AMD triangle returned a command-buffer error after 1002 ms.
   Kernel/user logs identify `completion witness missing`, after the Vulkan fence completed,
   with no GFX timeout/reset observed in that submission window. Wrapper again restored the prior
   installation. This does not prove the underlying witness coherency cause. Conservative AMD
   fix: turn off pool/page reuse, retire each completed pool via the existing path, preserve fence
   checks and propagate errors normally. Do not fabricate witness completion. Rebuilt/reinstalled
   changed plugin, then both texture and IOSurface CPU pixel checks passed in 4 ms.

`macos-nvidia-hybrid-install.sh` backs up all changed state, including old firmware, NMXAccel,
NVRMEdpBL, userland overlay, collection, upstream recovery jobs and NVIDIA NVRAM flags. It rolls back
on error. The upstream next-boot lastgood job is extended by `nvidia-hybrid-fallback.py` to restore
wrapper-owned NMXAccel/NVRMEdpBL/overlay as well, keeping the previous AuxKC consistent with disk.
The upstream lastgood job can restore its backup and reboot after two failed display starts;
its desktop bootguard also marks a desktop that stays up as good. These are recovery mechanisms,
not evidence of a working NVIDIA HDMI path.

### Installed final batch and evidence

Private logs/manifests `out/890m-trace/step51/`; complete final backup
`/Library/NullMoth/hybrid-2.4.2-IGDgjBNc`. Upstream own backup
`/Library/NullMoth/backup-20261020-095359.dYDE8l` (use the wrapper backup for full pre-batch state).

| Image | SHA256 | UUID in AuxKC |
|---|---|---|
| NVRM | `713b55d2c766c98abd9a97602103a3986c7e82a04f5d7c43ce62c60301b86ce2` | `0952A192-ADE8-33CF-A282-02DD6DB40DF7` |
| NVAccel26 | `4b2d68a1b129a4afb49d2aa68b90b710ae3d96a3b7361883c8c8fc87d5d247e5` | `B7BD2816-6458-3500-831B-69D9D2AADEDC` |
| NVRMFB | `092f1caa5aaecf2faf999b5971ab61cf625d888596ad203e6d217cd137605eb3` | `5075BFAE-B0FE-3659-BEB6-D7AAEF8856C8` |
| NVRMAGDC | `223a327f0b94ecd9a0ca321f5d69f149d8c4275b0a4e8f6be63d0c6266c6b2de` | `EF61483E-E558-3981-9EEF-4E26C7B14CC3` |
| NMXGPU | `0456558e65a8109f020d9945c137280378a327ccf17129f5657082316c440edb` | `7FB0A912-7ECC-3597-B51F-55266CBA4F0C` |
| NMXAccel | `3c0402c379d68d3eae25a179ab075eac1e708e6e933f8c64ce51a998b47d467d` | `0FA0421C-8585-35E5-B145-52113337C413` |

Deployed hybrid plugin signed bundle SHA256
`1b61fcafeadacdd113eb29459d80e9607d493682b46745187a0b51cb5fc19a44`.
`codesign --verify` passes. No NVIDIA kernel binary modified from release payload. Patched active
AMD libdrm `47dbb6f2783a1ddb...`, RADV `177d41a67558e3e8...`, AMDGPU libdrm
`db7cddeef2781d36...` retained. Nine backend selection cases pass. Final unprivileged forced-AMD
Metal triangle: RADV STRIX1, status4(completed), 4 ms, texture and IOSurface CPU `[64,128,255,255]`,
both CORRECT. This validates the deployed plugin/userland against the still-running b15 kernel.

**Reboot pending.** Stay hybrid with HDMI connected. Confirm live six UUIDs, NVAccel framebuffer
armed/non-headless, NVIDIA native HDMI output and WindowServer Metal first; then run a separately
forced AMD pixel probe. Current live kernel is still b15 and existing WS is still the old software
session. No claim yet of NVIDIA HDMI working, AMD WS working, HDR correctness or full stability.
iGPU kernel faults still affect the whole machine: separate per-process rendering is not panic
isolation. The earlier attach/TLB/IPI panic remains unresolved.


## Step52 — real OLED identity/HiRes installed; boot exposes missing hybrid pipe (2026-10-20)

Read real eDP connector93 through read-only DRM getters: Samsung `ATNA40CU05-0`, vendor4c83/product419c,
300x190mm, EDID256, checksums0/0, DisplayID extension0x70, SHA256
`c018efb7498d1f643af2f0eaea4113806de42635c899da98c655793561af1749`.
The old override carried synthesized EDID with different color primaries (real chroma bytes
`cfd1ae513eb6230b5054`, old `ee91a3544c99260f5054`). Removed only that EDID key, retained HiDPI/IOGFlags,
renamed display Samsung ATNA40CU05-0 (OLED). No guessed ICC installed; supplying real EDID is the basis
for macOS profile generation, not proof of accurate calibration or HDR transport.

NMXGPU source `4811103`: copies the chosen DRM modeset connector's immutable EDID/physical size/internal
flag while holding client->modeset_mutex then mode_config.mutex (same order as DRM probing), validates
complete bounded EDID/header/extensions/checksums, hands DDC blocks to IODisplay, accepts NULL-output
HLDDC capability probes, reports built-in flag and real millimetres. Adds ValidForHiRes to the existing
native mode and connection flags. No scanout timing change, no old nmx_fb_info layout change. New
separate identity API avoids stale compiled callers. Focused EDID validator cases and changed-TU
build/link passed; no unchanged GPU stress loop. Source pushed to NMX fork.

`macos-nmx-display-install.sh` installed GPU SHA
`5c21811761b91734b548870d9b0de41cf9e51f302237f846dcae60287ddc6d1d`, UUID
`5CFA9F52-9045-3977-BC83-A90FA32D7FC6`; verified all six UUIDs in new AuxKC and unchanged other five
kernel binary hashes. Backup `/Library/NullMoth/display-step52-jZGHZean`. The upstream recovery job
now also restores saved NMXGPU to match its saved old AuxKC. Current-session WS/mode untouched during
installation. Scoped next-login helper chooses only vendor4c83/product419c built-in panel, exact
1440x900 logical /2880x1800 backing @120, usable desktop mode, permanent CoreGraphics transaction;
refuses any raster change or ambiguous panel, exits bounded, removes its agent only on confirmation.
HDMI untouched. Artifacts/manifests in `out/890m-trace/step52/`.

**Actual boot 10:05:50:** all six live UUIDs match. NVIDIA HDMI working Mi Monitor1920x1080@144,
NVAccel headless0/armed1. OLED is correctly identified, EDID256,1440x900 HiDPI@120 in profiler;
helper logs success and its agent is gone. User photograph: OLED retains verbose boot console, not
an active desktop. `WindowServer`739 repeatedly logs `Unable to find display pipe` for NMXGPUFB
regID0x10000058d, while NMXAccel headless1/armed0. This is a presentation failure despite the successful
identity/HiDPI patch. IOVersatile dependency messages in the photo do not establish the graphics cause.
Step51's AMD pipe opt-out omitted a required foreign display pipe once WS uses NVIDIA. Investigate
and adapt upstream NVAccel's existing head4 foreign-iGPU CPU-copy path (currently watches NMIntelFB)
for NMXGPUFB. Preserve working NVIDIA HDMI and AMD's real identity; do not fake HDR or remove modes.


## Step53 — fix missing NVIDIA-to-AMD OLED presentation pipe (2026-10-20)

User photo after10:05:50 boot: HDMI works, OLED retains kernel verbose frame; Settings controls/HDR
appear absent. Actual profiler/registry: OLED real EDID256 Samsung ATNA40CU05-0,1440x900 logical with
2880x1800 backing @120; next-login HiDPI helper succeeded and removed itself. All six live UUIDs
match Step52. NVIDIA owns Mi Monitor1920x1080@144, nvaccel_headless0/nvaccelfb1; heads_piped=1,
igpu=0. NMXAccel headless1/armed0. CoreDisplay continuously reports `Unable to find display pipe`
for NMXGPUFB0x10000058d. That missing presentation pipe explains the stuck console despite correct
identity/mode registration. Photo's IOVersatile dependency errors do not establish a graphics cause.
Step51's direct-AMD-pipe opt-out omitted the required foreign-presentation replacement for an
NVIDIA-rendered WS. No EDID/HiDPI revert and no unchanged-code stress/reboot loop.

Read upstream v2.4.2's already implemented NMIntelFB foreign head4 path: same dependent controller
ID0x4E56524D00000001 as NVRMFB; explicit head registration; CPU-only scanout (`kva` nonzero,
`phys`0); `initFramebufferResource` deliberately returns no NVIDIA VRAM resource; presentation skips
NVIDIA page flips and copies IOSurface into foreign scanout. Reused that path for AMD OLED rather
than pretending RADV and NVK can coexist in WS's single Vulkan device.

NMX fork `f6689a6`: only opt-in NMXGPUAMD personality `NMXNvidiaDisplayBridge=true`, internal native
2880x1800, publishes head4, shared NVIDIA dependent controller ID and bridge marker. Default
remains head0. Real EDID, millimetres, HiRes and timing unchanged.
NVIDIA fork `49af2cc`: opt-in NVAccel `NMXForeignDisplayEnabled=true`, exact reviewed25G241 kernel,
watch only marked NMXGPUFB head4. Retained deferred call and registration lock wait for opened
scanout AND primary NVIDIA arming (<=300x200ms); validate CPU-only fields, native geometry,
pitch and allocation bounds before allowing head4. Existing registration verifies exact pipe/FB
ownership and handles gaps between NV head0 and foreign head4. Registration re-delivers mode
change. Read-only armed property and existing per-head counters expose success; no fabricated
resource prepare or mapping. Stop removes notifier/cancels retained callback. Existing NVIDIA
flip/copy behavior remains. No direct AMD WS pipe enabled. Builds use current installed SDK;
accel_build.sh now handles an absent RM compile_cmds/empty Bash3 array safely. Both forks pushed.

Installed final candidate, six UUIDs verified in newly built AuxKC:
- NMXGPU SHA256 `a11d60431d96b8e601981c75620ad6aa2fc3f5791f63968eef7ac59dd89f88ea`, UUID
  `0A0B9BE3-025D-3903-ACAD-D8309B0E0B98`.
- NVAccel SHA256 `956bcfc1d33ca3eb5199626a9a4c2aa01f4d056c809a72a556363e833c88490c`, UUID
  `C43DC1F8-EC92-379F-9D4C-C6F3EC9F7CCA`; installed and cached macOS26 bundle match, cache manifest updated.
- NVRM/NVRMFB/NVRMAGDC/NMXAccel hashes retained exactly from Step52, plugin unchanged `1b61fcaf...`.
  NVAccel candidate Info uses release2.4.2 metadata plus scoped opt-in, not stale source0.1 metadata.

`macos-nvidia-oled-bridge-install.sh` backs up both changed kexts, cached26 and old AuxKC, rolls
back failure; no live kext replacement, WS restart, boot-arg edit or NVRAM clear. Final transaction
backup `/Library/NullMoth/oled-bridge-step53-bCdWZFVn` holds intermediate unbooted head4 candidate;
original `/Library/NullMoth/oled-bridge-step53-qUGbDJ4s` holds the known pre-Step53 boot state
(working HDMI + correctly identified but frozen OLED). Prefer original for pre-Step53 recovery.
The upstream lastgood job still restores its full pre-2.4.2 state including matching saved NMXGPU.
Artifacts/manifests/logs in `out/890m-trace/step53/`.

**Reboot pending; new code has not run.** Normal hybrid boot with HDMI plugged. Verify new live
UUIDs; NMXGPUFB dependent index4/controller group; NVAccelForeignDisplayArmed; heads_piped bit4;
increasing debug.nvaccel_iop_ok_h4 and OLED visibly rendering desktop. Existing HDMI must keep
working. Do not infer success from profiler identity alone. HDR controls/color correctness are
not fixed by a display pipe: current framebuffers still expose SDR8-bit and this batch makes no
HDR transport or color calibration claim. Preserve actual EDID, not synthesized HDR capability.


## Step54 — OLED kernel pipe exists but AGDC omits its userland association (2026-10-20)

Actual boot10:51:00 loaded all Step53 UUIDs correctly. OLED now black, HDMI still works. NVAccel
reports foreign armed=true, heads_published/piped17(0x11), igpu1, iop1, nvaccelfb1. OLED has head4,
shared dependent controller ID, IOAccelIndex1, IOAccelTypes pointing to NVAccel, real EDID/timing.
Yet iop_ok_h4 stays0 and WS761 continuously reports unable to find pipe for OLED0x100000702.
Timeline: OLED publishes10:51:22.681, family creates pipe1 at10:51:28.095, CPU-only scanout resource
path executes, foreign armed10:51:28.106. Pipe0active1, pipe1active0; WS errors begin28.267. This is
not proof of copy failure: no OLED frame reached the copy path at all. Evidence boot-display.log
and nvaccel-boot.log in `out/890m-trace/step54/`.

Fresh entitled IOPresentmentGetMap probe (separate process) reports only HDMI0x1000005df on NVAccel
0x1000004ec, index0. AGDC fbmap n1/maxfb1. Source root cause: NVRMAGDC matches only
NVRMNVDAFramebuffer under its NVIDIA PCI node, supports only physical0..3, drops holes. It never
reports NMXGPUFB physically under AMD, regardless of the valid foreign kernel pipe. A fresh map
also misses OLED, so stale WindowServer state alone does not explain the failure.

Validated the association repair without another boot or live driver modification: a dylib loaded
only into our helper intercepts its own IOConnectCallStructMethod reply0x980 (220bytes). It appends
OLED registry ID as compact slot1, count/maxfb2, portMask6. Real IOPresentment then returns two
entries: HDMIindex0 and OLEDindex1, both same nonzero NVAccel and AGDC. This directly validates
cross-PCI association and compact-index format. It does not initialize WS presentation or prove
rendering. Raw baseline in iop-map.txt/map-io.txt, simulated result in map-simulated-foreign.txt.
No WindowServer injection, global DYLD setting or kernel reply change. LLDB was denied launching
the helper, and no security settings were changed to overcome it. These are ordinary local
helper/runtime observations, not REA provider output.

Fix source:
- NMX fork `0a07b49`: immutable display info gains normalized actual DRM sync polarity; only the
  opted-in foreign OLED publishes a tagged thirteen-word K5 timing record from actual fInfo.
  Clock Hz/milli-Hz, dimensions/sync totals/polarities come from the selected DRM mode, no EDID
  fabrication or HDR flag. Separate display-info layout changed only for its two rebuilt callers;
  old nmx_fb_info remains unchanged.
- NVIDIA fork `287381a`: NVAccel declares NMXNvidiaRenderPCI at first framebuffer publication,
  before open/first IOPresentment map; publishes actual NMXNvidiaPipeIndex after owned registration.
  Scoped NVDAGDCLoader personality flag plus exact25G241 kernel enables foreign AGDC support.
  Scan preserves native heads and appends exactly one marked foreign head4 in compact slot n,
  requiring matching NVIDIA render PCI, dependent group, valid actual timing and (once published)
  matching actual pipe index. Ambiguous candidates refused. AGDC max capacity5, original native
  physical-head limit4 retained. First map may describe the published display before its pipe
  is ready, matching normal NVIDIA discovery behavior; transaction readiness is not fabricated.
- Hybrid0x980 rescans do not use the one-second throttle, which could omit a just-published OLED
  from the first cached map. IOLock serializes table rescan/reply/K5 reads and startup/drop paths,
  preserving retained-entry lifetime. Default profile keeps its previous behavior. Existing K5
  link/SDR scaler capability path now has the OLED's real timing. New agdc_build.sh builds from
  this checkout without unrelated hardcoded staging paths. Both source branches pushed.

Built/installed three changed images; all six UUIDs verified in new AuxKC:
| Image | SHA256 | UUID |
|---|---|---|
| NMXGPU | `3c081efc7419f36017cb98174fadf7997b45ec5c7e7007e0c687142c9aab3ba6` | `087D392A-8DEB-3F54-9F11-EF10E954130C` |
| NVAccel | `004ea2508743ea85b3bae7b7cc69c39ffd9bfe30080eda5fa967b88572b2b931` | `23FB22FE-E38E-3A25-BA12-383B8DC6F2C7` |
| NVRMAGDC | `9b8e19e3a20e18951519b1fd4c73dc39a3cb6e0658b330b8a6b4083fbb966a0a` | `22A5F5CA-AC89-325E-AA29-7DE6E3D15741` |

NVRM/NVRMFB/NMXAccel binary hashes unchanged from Step53; plugin still1b61fcaf. Cached26 NVAccel
and its SHA256SUMS updated. Release2.4.2 Info metadata retained for both NVIDIA candidates, with
explicit opt-in on NVAccel and NVDAGDCLoader. `macos-nvidia-oled-map-install.sh` backs up/restores
all three changed kexts, cached26 and AuxKC; final backup
`/Library/NullMoth/oled-map-step54-9Nf905Py`. No live unload/load, WS restart, NVRAM/EFI/security
change. Build/link/collection checks pass; no repeated unchanged GPU stress run.

**Reboot pending.** Normal hybrid boot with HDMI. Confirm all three new live UUIDs, then AGDC
fbmap/maxfb2 and a fresh map with both framebuffer IDs/nonzero NVAccel/indices0+1; only then
check iop_ok_h4 increasing, errors gone and visible OLED desktop while HDMI stays working.
Committed read-only tools/890m/iop-map.c and adjacent development entitlement enable this check.
The previous scoped HiDPI helper already removed itself after success; existing real EDID/name/
120Hz HiDPI settings preserved. This is not yet an OLED presentation pass and not an HDR fix.


## Step55 — accept the missing AGDC client declaration before initialization (2026-10-20)

Boot11:05:29 matches all Step54 UUIDs. User reports OLED retains verbose console; HDMI functional.
AGDC now actually reports both framebuffers: HDMI0x1000005fc/slot0, OLED0x1000005df/slot1. Fresh
IOPresentment map confirms both entries, NVAccel0x1000004de nonzero, same AGDC0x100000608. Kernel
heads_piped0x11, NMX render-PCI marker/actual pipe index1 correct, real NVRMTiming published. K5
link/caps15each, asked/link/caps masks3, why0, refused_idx-1. iop_ok_h4 remains0 while head0 advances.
Thus Step54 association/timing fixes are real but not a complete presentation pass.

The next failure is explicit: kernel logs cmd0x2001/in4 -> Unsupported at11:05:49.665 (three calls)
and49.992 (two), immediately matching WS IOPresentment `Unable to get AGDC information`, error
0x10000003. No OLED frame reaches the copy path. Kernel creates foreign pipe1 at49.850/arms49.879,
then WS retries at49.992 but the same declaration is still rejected. Existing old Strix AGDC
(kexts/StrixAccel/StrixAgdc.h kCmdClientSet) already recorded and acknowledged this passive4-byte
client declaration. The NVIDIA companion lacked that handler. Map success alone was insufficient
validation in Step54; do not repeat that inference.

Read available SDK/source and local IOPresentment wrapper bytes copied from our own process
(no WS memory access): Initialize accepts one object argument; CreateForRegistryID wraps the
factory. A separate entitled helper attempts CreateForRegistryID for OLED but NVAccel's display
pipe user-client open returns kIOReturnExclusiveAccess because WS owns it. IOServiceOpen/call
interposition only in that helper identifies NVAccel type4 selector0 as this boundary. The helper
returns NULL before initialization. No WS/client ownership was bypassed, no debugserver/security
change and no full initialization success claim. Private helper/interposer traces and wrapper
byte dumps in out/890m-trace/step55; ordinary local evidence, not REA provider output.

Fix: scoped hybrid NVRMAGDC handles0x2001 with exact4-byte input and zero-output validation;
unaligned payload copied safely, declaration recorded, kIOReturnSuccess returned. No client-specific
hardware policy exists in this display companion; this declaration does not acknowledge a GPU
completion, memory preparation, modeset or HDR feature. New header nvrm-agdc-client.h validates
the boundary; focused C checks cover declarations1/0, unaligned input, null input/output storage,
short/oversized input and nonzero output length. Read-only nvrmfb_agdc_client_set and
nvrmfb_agdc_client_set_value counters record handling. Native-only default behavior unchanged.

Built and installed only NVRMAGDC, retaining release2.4.2 metadata + existing hybrid flag:
SHA256 `460fba65165c59c94a03f13d4cc374b2465212d87046175a26017541deb90350`, UUID
`52DE7317-C506-3728-B84F-83533FBE6AEE`. Full AuxKC rebuilt and six UUIDs verified; other five
kernel image hashes and plugin checked unchanged from Step54. Transaction installer
macos-nvidia-agdc-client-install.sh backs up AGDC/AuxKC, rolls back errors. Backup
`/Library/NullMoth/agdc-client-step55-YevKYGQT`; manifest/install/build/protocol checks in step55.
No live kext swap, WS restart, NVRAM clear or EFI/security change. Existing real panel identity,
HiDPI120 and HDMI working session retained. No repetitive unchanged GPU stress tests.

**Reboot pending; new handler has not executed.** Normal hybrid boot with HDMI. First confirm new
AGDC UUID and client_set counter growth; require AGDC information error gone. Then confirm actual
map still2, OLED plane transactions/head4 successes and visible desktop with HDMI intact. If it
still fails, trace initialization/activation after the now-accepted declaration instead of
reverting working association/EDID code or claiming map/pipe creation equals display success.
HDR remains unresolved; the framebuffer's current supported path is SDR8-bit.


## Step56 — where the OLED transaction stops; controller order from the 780M repo (2026-10-20)

Live boot16:05 (Step55) settles where the OLED stops: AGDC0x2001 is accepted (no `AGDC information error`,
client_set12, fbmap n2), WindowServer has a display pipe for head4 (heads_piped0x11), yet every OLED transaction
comes back kIOReturnNotReady — WS: `Failed to submit transaction: IOPRESENTMENT_METHOD_FAILURE: IOReturn: 0x2d8` —
and the panel keeps the verbose console. Counters: iop_ok_h0 41.7k and rising, iop_ok_h4 0, iop_fail 0, copy_skip
3.2k, blank 40. iop_fail0 means NVAccel's performTransaction never refused anything, and the missing K6 line says it
never ran for head4: the pipe call is stopped before the copy. Step54's pipe1active0 is the same fact seen from the
family side.

Read luuumi-dev/amd-rdna3-macos-driver (780M, same NullMoth/Cobalt64 lineage, commits to 2026-10-20). It is not a
working OLED there either — M2 is groundwork, not installed, and commits still fix PhxFB panics; its own doc says
the plugin withholds the device from WindowServer in AMD mode. Three points transfer:
- PhxFB sets IOFBDependentID/Index BEFORE IOFramebuffer::start, because start creates the framebuffer's controller
  only from a dependent ID that already exists (IOFBController::copyController(kDepIDCreate)); without one the
  controller is NULL and the first power-change callout panics (their 7c5c09a). nmx_fb.cpp wrote the ID after start,
  so whatever controller start made was not made from the head4 group.
- isConsoleDevice() must be false when another IOFramebuffer already drives the same GPU's console ("not the console
  beside IONDRV"); ours answered true unconditionally.
- Their boot daemon arms in another order: nvaccelfb1 -> nvaccel_iop1 -> nvaccelfb3 -> killall WindowServer
  (ours: ... -> nvaccelfb4, no WS restart). tools/890m/oled-arming.sh runs either.

Build17 (`out-b17`), source only beyond the ordering/console bits:
- NMX fork ga403wm-nmx: nmx_fb.cpp sets IOFBDependentIndex/ID/built-in/NVRMTiming before IOFramebuffer::start;
  isConsoleDevice() = !fBeside (provider's IOFramebuffer children); a bounded `pipe:` trace of open,
  enableController, setDisplayMode, set/getAttribute(wsrv), VBL registration and the scanout ABI, including the
  NotReady reason (!fPowerRegistered, !fInfo.ok).
- NVIDIA fork research/ga403wm-hybrid-2.4.2: nvrm-accel.cpp logs `trx:` at validateTransaction,
  isTransactionComplete and performTransaction entry, three per head, naming the framebuffer each pipe resolves to.
- Installed NMXGPU `9afb0ffc...` UUID `ADB05A88-79CF-3E1E-A7B4-E5F950A99F64`, NVAccel `7050be67...` UUID
  `FA0F821A-4AA6-39B2-9605-A1C32864C58F`; NVRM/NVRMFB/NVRMAGDC/NMXAccel and the plugin retained byte for byte; six
  UUIDs verified in the rebuilt AuxKC. Installer macos-nvidia-oled-map-install.sh (kept its step54 labelling),
  backup /Library/NullMoth/oled-map-step54-EoYnCyo7, artifacts out/890m-trace/step56/.

Reboot pending. After boot run tools/890m/oled-arming.sh (luuumi order) and read `pipe:`/`trx:` with iop_ok_h4 and
iop_fail. If the pipe still never activates, the trace already names the next question (which entry point WS reaches,
which framebuffer the pipe resolves to); another map test would not. No claim of OLED presentation.


## Step57 — WindowServer holds the OLED pipe but never submits on it (2026-10-21)

Boot 12:07:37, the first boot after the 11:50 session damage. opendirectoryd/trustd/LaunchServices came back
(`whoami` -> user, `sudo` prompts, `do shell script` works, DNS resolves). NVAccel build18 (SHA256
`cc3f88a8...`, UUID `9B78ADDD-039A-3F38-AAC2-D1EF958834BB`) is the loaded image -- the on-disk binary, the AuxKC
entry and `kmutil showloaded` agree -- yet **none of its three new sysctls exist** (`debug.nvaccel_trx_h0`,
`_trx_h4`, `_iop_force_copy` are unknown OIDs, 58 `debug.nvaccel*` entries, same as build17). No explanation was
found and none was needed once kext logging turned out to work again:

    log show --last 40m --style compact --predicate 'senderImagePath CONTAINS "NVAccel"'

returns every `ALOG`/`IOLog` line. `dmesg` does not exist on this build. Head4's `trx:` budget is untouched (the
cap is three per head), so any head4 call would have been logged.

What the live boot says (12:07-12:26):

- `system_profiler SPDisplaysDataType`: Samsung ATNA40CU05-0 (OLED), 2880x1800, UI 1440x900 @ 120 Hz,
  `Online: Yes`, `Connection Type: Internal`, under AMD 0x150e with `Metal: Supported`; "Mi Monitor" 1920x1080
  @ 144 Hz stays the main display. macOS has the panel's full identity and mode.
- Counters: `iop_ok_h0` 22.7k -> 23.1k, `iop_ok_h4` 0, `iop_fail` 0, `copy_skip` 1.7k, `iop_blank` 56,
  `heads_published/registered/piped` all 0x17, AGDC `fbmap n=2` (slot1 = NMXGPUFB 0x10000058b), `client_set` 12.
- `trx:`: only `-> fb NVRMNVDAFramebuffer head 0 surface yes resource yes` (three, then the cap). **WindowServer
  never enters NVAccel's pipe for head 4.** A skipped frame cannot explain ok_h4 = 0 either: the copy path
  reproduces the last good frame after five held frames, so a submitting WS would have produced ok_h4 > 0.
- NMXGPU `pipe:`: `open`, `getAttribute wsrv`, `setDisplayMode`, `scanout ok (foreign 1 head 4) 0xb40 0x2d00`
  at 12:08:07 (WindowServer's own bring-up) and again at 12:13:02; NMXGPUFB publishes EDID 256 B from the DRM
  connector, `NVRMTiming`, 652.264 MHz, dependent index 4, `IOAccelIndex` 1, `display0/AppleDisplay`.
- `ioreg`: two `IOAccelDisplayPipeUserClient2`, both `IOUserClientCreator = "pid 722, WindowServer"`, both
  children of NVAccel; `heads_piped` 0x11 says the head4 pipe exists and its +0x98 points back at NMXGPUFB.
- Arming `debug.nvaccelfb=3` was written twice (12:13:02, 12:24:32): "scanout-backed display pipe ENABLED,
  re-delivering the mode change" both times, no change in ok_h4.
- `killall WindowServer` (SIGTERM) is ignored here: pid 722 survived 20 s. The 780M repo's last arming step
  therefore cannot be reproduced without SIGKILL, which stays forbidden after 11:50 broke opendirectoryd/trustd
  (loginwindow restart). WindowServer CPU fell 52% -> 7% across the attempt, nothing else moved.

Reference repo check (luuumi-dev/amd-rdna3-macos-driver, read this boot): `src/phxaccel/accel/phxfb.cpp` is 236
lines and publishes *less* display information than NMXGPUFB -- one mode, `refreshRate 60 << 16`, a 16.67 ms
`thread_call` VBL timer, `appleTimingID = kIOTimingIDInvalid`, no EDID, no `IOFBTimingRange`, SCANOUT = console
kva + `phys 0` + `actualSize 0`. Our NMXGPUFB already overrides the same thirty IOFramebuffer methods and
publishes strictly more (EDID, NVRMTiming, pixel clock, dependent index/ID before `start`). **"The kext does not
load enough information for the display" is therefore refuted as the cause**; the reference expects the
accelerator's display pipe to do the presenting, which is exactly the part that never runs here. What still
transfers from that repo: its arm order ends with a WindowServer restart (blocked, see above), and the
`NVMTLDevice.m` WindowServer-on-AMD-panel gate -- only needed when WindowServer must run on the AMD GPU, which is
not this route (WindowServer already runs on NVAccel), plus the MES/VM notes for later.

Open question, stated exactly: WindowServer holds an NVAccel display-pipe client for the OLED's framebuffer, the
framebuffer is in the display machine (count grew on `found_framebuffer`), the panel is online at 120 Hz, and yet
no transaction ever reaches `NVDisplayPipe::performTransaction` for head 4. Next probes need no rebuild because
head4's three `trx:` lines are still unspent: change the display arrangement (OLED as main display, then mirror
with HDMI) and watch for the first `trx: ... head 4` line; if it appears, WindowServer's condition is "main
display", if not, instrument the pipe client open (`newUserClient` types above the 40-line cap) next boot.
No claim of OLED presentation; HDMI session untouched.

### Step57b — WindowServer's own log names the failure: "Fallback GPU Display Pipe transaction submission failed"

`sudo log show --last 6m --predicate 'process == "WindowServer"'` is readable (the non-root query returns nothing on
this build). Making the built-in panel the main display (`CGBeginDisplayConfiguration` + origins 0,0 / 1440,0,
reverted afterwards) produced **no** head4 transaction, but the attempt itself made WindowServer try to present, and
CoreDisplay logged the failure it has been hiding:

    [ERROR] - Attempting to get capabilities from plane with no gamma            (8466 in 6 min)
    [ERROR] - Fallback GPU Display Pipe transaction submission failed            (881 in 6 min)
    [ERROR] - Transaction Target State ... Plane Index: 0
              DisplaySurface Size: (2880x1800) Format:BGRA
              Display Pipe Operations: Dirty Fetch - Pipe, Scale/Rotate/Linearize/CSC None,
              System Gamma - Unknown, Regamma - None, EOTF - GPU
    SkyLight: transaction 902 timed out

So WindowServer does build a 2880x1800 BGRA transaction for the OLED, ~2.5 per second, and it never reaches
NVAccel's pipe (no `trx:`/validate line). Two facts explain why:

- `NVDisplayPipe` derives from **IOAccelLegacyDisplayPipe** (`nvaccel_stubs.h:142`), whose header has no plane or
  gamma API at all; the modern `IOAccelDisplayPipe` (0x318 bytes, declared with `copyCapabilities()` in
  `iofam/IOAccelDisplayPipe.h`) is what carries plane capabilities. The family has no
  `IOAccelDisplayPipeGammaTable2` instance, which is exactly what "plane with no gamma" reports.
- The display belongs to the AMD GPU while its accelerator is NVAccel on the NVIDIA GPU, so CoreDisplay takes its
  cross-GPU "fallback GPU display pipe" path, asks the plane for capabilities, gets none, and the submission fails
  before any NVAccel entry point runs.

That reframes the route: the current hybrid asks macOS to present an AMD panel through an NVIDIA pipe, and macOS's
fallback path refuses it. The 780M repo's model is the opposite one -- the display's own GPU accelerator owns the
pipe (`debug.nmxaccel_headless` must read 0, which is why their NVMTL patch checks it; ours reads 1). Two ways
forward, both real work: give the pipe plane/gamma capabilities by moving NVDisplayPipe onto IOAccelDisplayPipe
(smaller, unproven), or let NMXAccel own the OLED's pipe so the display GPU and the accelerator are the same GPU
(the reference model, larger). Display arrangement was restored to HDMI main; no presentation claim.


## Step58 — hand the OLED's pipe to the accelerator that shares its GPU (2026-10-21)

Read the roadmap again before touching anything: M2 was already closed by build15 (Step49: second client passes,
including simultaneous VMs, 0 GFX timeouts), so the open milestone is M3 — a non-headless accelerator for the panel
— and the hybrid bridge is not on the roadmap at all. Step57b had already proved why: CoreDisplay refuses to present
a GPU's panel through another GPU's pipe.

The port already contains the owned path; it was switched off in two plists:
- `NMXAccel`'s personality carries `NMXDisplayPipeEnabled = false`, so `nmxArm()` never runs and
  `debug.nmxaccel_headless` reads 1.
- `NMXGPU`'s personality carries `NMXNvidiaDisplayBridge = true`, so `nmx_fb.cpp` publishes the panel as the NVIDIA
  card's foreign head 4.

Code change (NMX fork `f83041d`, one function): `nmx_fb.cpp::start()` now distinguishes the hybrid bridge from
ownership. With `NMXOwnsDisplay` on the provider and no bridge key, the framebuffer sets its own dependent group
(`IOFBDependentID` 0x4E4D5847_00000001) before `IOFramebuffer::start`, publishes `IOFBDependentIndex` 0, stays
`built-in`, and keeps the real DRM timing record. The bridge branch is unchanged and still selected by its key.

Build: NMXGPU `756903d2ec015b2f` (out-b19). Staged with both plist edits in `out/890m-trace/step58/`; installer
`scripts/macos-nmx-owns-oled-install.sh` backs up NMXGPU/NMXAccel/AuxKC, verifies that neither the bridge key nor
the disabled pipe survives in the staged plists, rebuilds the auxiliary collection and asserts both kext UUIDs are
in it before replacing it, with the same rollback trap as the bridge installer.

Install did not run: the `do shell script` password dialog went unanswered (no backup directory, installed NMXGPU
still `acc8770e`, collection still 12:00). Waiting on the owner to run the one-liner and reboot.

What the next boot must show if the switch is right: `debug.nmxaccel_headless` 0, `NMXDisplayPipeArmed` true,
NMXGPUFB at `IOFBDependentIndex` 0 with `IOAccelTypes` naming NMXAccel, one NMXAccel display pipe driving that
framebuffer, and no `Fallback GPU Display Pipe transaction submission failed` in WindowServer's log. If the pipe is
registered but frames still do not arrive, the copy path is now on the supported side, so `trx:`/`iop:` on NMXAccel
name the next step directly. The NVIDIA bridge remains one plist key away for comparison.

### Step58 result (boot 13:17:12): the OLED's pipe now lives on the GPU that owns the panel; WindowServer looks for it and does not find it

Installed and loaded NMXGPU `756903d2ec015b2f` with `NMXOwnsDisplay`, NMXAccel's personality with
`NMXDisplayPipeEnabled = true`. The switch did what it was written to do:

- NMXGPUFB is head 0 of its own group: `IOFBDependentID` 0x4E4D5847_00000001, `IOFBDependentIndex` 0,
  `built-in` Yes, `IOAccelIndex` 0, and `IOAccelTypes` now names **NMXAccel** (before: NVAccel).
- NMXAccel: `debug.nmxaccel_headless` 0 (was 1), `debug.nmxaccel_armed` 1, `NMXDisplayPipeArmed` Yes,
  `NMXPresentationPath` RADV-IOSurface-copy-to-DCN35, `IOAccelDisplayPipeCapabilities` set by `nmxArm`.
- NVAccel lost the panel: heads 0x1/0x1/0x1, `iop_ok_h4` 0, HDMI still copied (`iop_ok_h0` rising).
- Kernel log: `NMXAccel: registerFramebuffer(1): framebuffer count before = 1` then
  `NMX display pipe armed on owned native framebuffer` at 13:17:30.413.

And the failure changed with it. WindowServer (new pid 773) since 13:17:00:

| message | count |
|---|---|
| `Fallback GPU Display Pipe transaction submission failed` | **0** (was 437 in 10 min) |
| `Unable to find display pipe for IOFB service / regID: 0x13803 / 0x100000598` | 44164 |
| `plane with no gamma` | 330 |

So the cross-GPU fallback that refused the hybrid is gone: the display and the pipe are on the same GPU now. What
remains is that CoreDisplay cannot *find* the pipe: 0x100000598 is NMXGPUFB's registry ID, and NMXAccel's pipe for
it exists (`NMXDisplayPipeArmed` Yes, machine framebuffer count 1). WindowServer opened its display-pipe clients
(type 4) only on NVAccel (13:17:30.294, 13:17:43.98); NMXAccel received types 5/6/2/33 and never a type 4.

Re-selecting the panel's current mode through CoreGraphics (a supported mode change, no timing change) did not make
WindowServer look again: `debug.nmxaccel_iop_ok` stayed 0 and no type-4 client appeared on NMXAccel.

The two accelerators differ in exactly one relevant way: NVAccel is the accelerator of the GPU WindowServer
composites on, NMXAccel is a second accelerator that owns a display but renders nothing for WindowServer. That
points at the roadmap's M3(c), not at the pipe: WindowServer must composite on the iGPU for macOS to treat that
pipe as its own. The gate for that already exists in the Metal plugin (`nvmtl_vk_vendor() == 0x1002 &&
!debug.nmxaccel_headless`), and `debug.nmxaccel_headless` now reads 0 — but WindowServer's compositor GPU is
chosen from the main display, which is still the HDMI monitor on the NVIDIA card.

Next experiment, recoverable by one reboot (the arrangement change is `.forSession`): make the built-in panel the
main display while NMXAccel is non-headless, and watch `debug.nmxaccel_iop_ok` plus whether WindowServer creates a
type-4 client on NMXAccel. No claim of presentation; HDMI session untouched.

## Step59 — the driver's own view of a submission: every ring, sixteen deep, and a sysctl that registers (2026-10-22)

**Status: INSTALLED — reboot pending; the b22 trace has measured nothing yet.**

Why this came before more probes: with Step58's pipe on NMXAccel, the open M2 question is still "why does the first
submission of a *new process* fail about half the time and succeed on every later one in the same process" (fail
returns at ~250 ms; a hang parks the process in `?NE`). Every candidate — VMID allocation, flush ordering, TLB/HDP
ordering, a watchdog that never fires — is decided by one fact nobody could read: what the driver decided for *that*
submission. A kext `printf` is not a dependable channel on this machine (the same NMXGPU/NVAccel lines appear or
vanish depending on the boot), and the answer is needed inside the probe process's lifetime, so the trace lives in
`debug.nmx_*` sysctls and is read around each run.

What was built, in three attempts that each removed a defect the previous one hid:

* **b20** (`cf58b30d`, UUID `87DB4113`): eight scalar sysctls (`jobs`, `jobs_flushed`, `jobs_no_flush`, `timeouts`,
  `last_vmid/pasid/flags/pd`) plus hooks in `amdgpu_vm_flush()` and `amdgpu_job_timedout()`. Two defects, found before
  trusting it: the `amdgpu_vm_flush` hook filtered on `AMDGPU_RING_TYPE_GFX`, so a dispatch scheduled on `comp_1.x`
  would never appear; and `flags` was already ANDed with `job->vm_pd_addr != AMDGPU_BO_INVALID_OFFSET`, so
  "needs_flush false" and "pd invalid" were the same reading.
* **b21** (`407bc56a`, UUID `30DD9240`): a 16-entry ring covering **every** ring type, `seq` for ordering, the raw
  `job->vm_needs_flush` kept apart from the flush the call actually emits, the gds bit added, and a timeout recorded as
  ring `TIME` so it is never mistaken for a submission. Installed and booted — and `sysctl debug.nmx_trace` still
  answered `unknown oid`, although the linked binary carried `sysctl__debug_nmx_trace` and its description string.
* **b22** (`e47373de`, UUID `00F9957A`): the registration fix below. Installed, AuxKC rebuilt, six UUIDs unchanged
  (NVRM/NVAccel/NVRMFB/NVRMAGDC/NMXAccel untouched, NMXGPU's `NMXOwnsDisplay` and NMXAccel's
  `NMXDisplayPipeEnabled` plists preserved), backup `/Library/NullMoth/nmx-owns-oled-1aQoO8ck`.

Root cause of the missing OIDs, two independent faults:

1. **A kext never auto-registers its `SYSCTL_*` entries.** `bsd/sys/sysctl.h` says it outright: the linker set
   registers at kernel init, "UNLESS they are defined in I-O-Kit. In this case, you have to call `sysctl_register_oid()`
   manually - just like in a KEXT." NMXAccel has always done that (`nvaccelInstallSysctl()`); NMXGPU did not, so the
   OIDs existed in the image and nowhere in the kernel's tree.
2. **`bsdcompat/src/nmx_sysctl.c` defined `sysctl__debug_children`** for the port's own in-memory sysctl tree. With
   that definition in the link, even a registered NMXGPU OID would hang off a private, empty list instead of the
   kernel's `debug` list. The port never adds a node under `_debug` (grep over `kpi/`, `bsdcompat/`, `xkpi/`: zero
   uses), so the definition is removed; the symbol is now undefined in the kext and the loader binds the kernel's.
   `nm -m` on b22 confirms the shape NMXAccel has: `_sysctl__debug_children` and `_sysctl_register_oid` are both
   `(undefined) external (dynamically looked up)`.

Patch set: `patches/series` is 15 (`amdgpu-job-timeout-hook.patch` is new; `amdgpu-vmflush-trace.patch` now carries the
all-ring hook). Replay on vendor HEAD `c16de0f9fa` is zero-fuzz and idempotent; runtime 76/76, driver 900/900, 0 failed.

Upstream check in the same session, recorded because it closes the "install a newer AMD driver" route: nullmoth
**v2.5.2** (2026-10-22) is NVIDIA-only. Commit `a7f16b0` (2026-10-16) deleted the whole `gpu-port` — NMXGPU, NMXAccel,
the NPU and the audio driver, 51,693 lines — into a separate, non-public repository. So there is no newer public AMD
driver to install; this fork is the newest AMD line. The 2.5.2 payload was downloaded and hash-verified
(`b3c01bbd…`) and extracted to `out/nullmoth-2.5.2/pkgroot`, deliberately **not** installed: it replaces the NVIDIA
core 610→615 plus the plugin, and cannot change M2.

What the next boot must show, and what each outcome decides:

* `sysctl debug.nmx_trace` exists, header `seq ring type vmid pasid pd needs_flush flush pasid_map pipe_sync
  gpu_reset gds`; `debug.nmx_timeouts` counts scheduler timeouts; a timeout row reads ring `TIME`.
* `bash scripts/890m-m2-probe.sh 10` immediately after login (the failure window is the first minutes after boot; each
  probe is capped at 8 s and the loop stops at the first hang). It prints, per one-dispatch process, `pass/fail/hang`
  and exactly the trace rows that process produced.

| Reading | Conclusion | Where the fix goes |
|---|---|---|
| failing first job has `needs_flush 0` | the VMID ran without its page table being reprogrammed | `amdgpu_vmid_grab` / `amdgpu_vm_flush` ordering |
| `needs_flush 1`, `flush 1`, `pd != 0` | PT base written, but the CP read the old table: TLB/HDP ordering | `emit_flush_gpu_tlb` / `PFP_SYNC_ME` barrier |
| rows on a `comp_*` ring | the failing job is a compute-queue submission, not gfx | the compute-ring path, not the gfx trace |
| ring `TIME` / `timeouts` grows while the process hangs | the watchdog fires and recovery does not free the job | `amdgpu_gpu_recover` / `amdgpu_ring_soft_recovery` |
| `timeouts` stays 0 while a job hangs | the `drm_sched` timeout never runs in this port | the scheduler timeout/timer path |

Next gate: one boot with the current arrangement (HDMI + OLED, rung 1 allow list); this batch changes no allow list,
boot argument, display mode or plugin. WindowServer acceleration and OLED presentation remain exactly as Step58 left
them, and no presentation claim is attached to this step.

## Step60 — with the pipe finally on NMXAccel, the login session cannot get a GPU address (2026-10-22)

**Status: BUILT AND INSTALLED — boot `FC20AA10` measured offline; the fix was compiled by CI (run 39751051561,
NMXAccel `LC_UUID DAB8184D-D77B-310A-A437-AB58A6102935`, sha256 `f72a82a1…`) and written into the Data volume from
Linux. Two boots pending: the first runs the previously collected accelerator and relinks the auxiliary collection,
the second loads this build.**

This is the boot the owner reported as "the login prompt appears, then the panel goes black". Step58's blocker is gone
in it: CoreDisplay finds the pipe, and WindowServer opens display-pipe clients on NMXAccel — the type-4 clients that
never appeared on 2026-10-21. What remains is one failure, repeated once per frame, with one cause.

Timeline (seconds from boot; boot `FC20AA10D6954C45878D6A19D4E6DB4D`, 135.5 s of records):

| t | event |
|---|---|
| 10.965 | `NVRMFB: driver off - the firmware framebuffer 0x880000000 (+20736000) is not in this card's windows, not starting` — no hybrid head 4 this boot |
| 11.393 | NMXAccel starts on NMXGPU's claim: `AMD display adapter: native framebuffer watch enabled` |
| 14.325 | `newDisplayPipe`; `NVDisplayPipe::initFramebufferResource(index 0): scanout gate CLOSED ... frames are copied` |
| 14.384 | `registerFramebuffer(1): framebuffer count before = 1`; `NMX display pipe armed on owned native framebuffer`; `scanout ok (foreign 0 head 0) 0xB40 0x2D00` |
| 14.786 | first `newUserClient(type 4)` on NMXAccel (`IOAccelDisplayPipeUserClient2`) |
| 31.972 | second WindowServer, pid 755 |
| 32.668 | its `type 4` client on NMXAccel |
| 33.127 | first `IOAccelResource2::prepare()` failure, 7073 of them until 113.902 (87.6/s) |

Counts for the whole boot: `failed to allocate GPU virtual address` **7073**, `failed to alloc GART space` **7073**,
`NVTask::allocate: RM refused` 14146 (two log channels per failure), `nvAccelRmHandles: framebuffer gave no kapi
device` 16, `Surface mode contains bad bits` 8, `Fallback GPU Display Pipe transaction submission failed` **0**,
`Unable to find display pipe` **0**.

The four lines, in the order the family emits them:

    NMXAccel: nvAccelRmHandles: framebuffer gave no kapi device (ret 0xFFFFFFFFE00002C7, kapiDevice 0)
    NMXAccel: NVTask::allocate: RM refused 20738048 bytes (align 0) -- no GPU address
    IOAccelTask::freeToAllocGPUAddress: failed to alloc GART space at segment 0. Needed 20738048 bytes, used 0,
        size 1099510583296. vram=0
    IOAccelResource2::prepare(): failed to allocate GPU virtual address for mapping. resType=0x40

Each fact rules something out:

* 20738048 = 2880 x 1800 x 4 (20736000) + 2048. It is the panel-sized surface, not a stray small allocation.
* `used 0, size 1099510583296` = 2^40 - 0xFF000, the task's own nearly empty range. Space is not the limit; the
  allocator was never asked successfully, so no "GART full" reading applies. `freeToAllocGPUAddress` only reclaims
  and calls the task's `allocate` twice — the failure is there, not in the size.
* `vram=0` = the family took the system-memory (UMA) branch of `IOAccelResource2::allocMemory`.
* ret `0xE00002C7` is `kIOReturnUnsupported` and `kapiDevice 0` means the framebuffer *refused* the `nvRmHandles`
  call. 16 lines is `nvAccelRmHandles`' 8-message cap through both `kprintf` and `IOLog`; the handle is never obtained,
  so every later allocation fails the same way without further logging.
* 7073 failures over 80.775 s is 87.6/s: from 33.1 s the login session's WindowServer retries the same mapping
  continuously and never gets an address.

**The earlier "flags regressed to 0x30a44300" reading is wrong, and reverting it would bring back Step18.**
`populateAccelConfig` writes `0x30a44300` under `#ifdef NMX_ACCEL` (`kexts/NVRM/accel/nvrm-accel.cpp:213`) but its
`ALOG` on line 230 prints a hard-coded `flags=0x30844300`, so that log line is not evidence of the value on disk. The
two values differ only in bit 21 (`0x200000`), the bit Step18 identified as "resources allocate as GPU-addressable
system memory" and *added*; Step23 measured what happens without it — a `VidMemory` of length 0, logged as
`Needed 0 bytes`. This boot logs `Needed 20738048` with `vram=0`: bit 21 is in effect and working. What fails is the
virtual address handed to that memory, which is a different subsystem.

**Root cause.** `nvAccelGpuVaAlloc()` needs a `NvKmsKapiDevice` (`nvrm-accel.cpp:1907`) from `nvAccelRmHandles()`,
which calls `NVRM_GPUVA_FN_HANDLES` (`"nvRmHandles"`) on the framebuffer NMXAccel registered. Only the NVIDIA
framebuffers answer that symbol (`kexts/NVRMFB/fb/nvrm-fb.cpp:2845`, `kexts/NVRM/fb/nvrm-fb.cpp:1371`); NMXGPUFB
answers `NVRM_VRAM_FN_SCANOUT` and forwards everything else to `IOFramebuffer::callPlatformFunction`
(`gpu-port/xkpi/xnu/nmx_fb.cpp:172-192`) — exactly the `kIOReturnUnsupported` in the log. Nothing on the AMD side can
answer it instead: `NvKmsKapiDevice` exists only in the NVIDIA code, NMXGPU constructs none, and
`nvrm_kapi_dev_handles()` only reads handles out of such a device. In this boot NVRMFB had refused to start
(10.965), so the registered framebuffer was NMXGPUFB and the accelerator could never resolve an RM handle.

Which resource is it? `resType=0x40` is a device-cache resource, not the 0x80 IOSurface type the driver returns
(`nvrm-accel.cpp:237`), so it comes from another constructor, i.e. the surface buffers WindowServer allocates for the
login session. Against this route it changes nothing: both types end in the same `prepare()` -> `task->allocate`.

**Fix direction: give the task its own address range, because no page table is behind this panel.**
`NMXPresentationPath` is `RADV-IOSurface-copy-to-DCN35`: `initFramebufferResource` deliberately returns no
framebuffer resource and the pipe copies the IOSurface into the DCN raster on the CPU; RADV executes with its own
AMD page tables. The address the family asks for is therefore bookkeeping only — the same shape StrixAccel already
runs on this machine, whose task is "only an address-space bookkeeping object (AppleParavirtTask recipe)" with its own
`IORangeAllocator` and one page reserved (`kexts/StrixAccel/StrixAccel.cpp`, `StrixTask::setup`), and whose comment
states it outright: "Our pipe presents by copying the IOSurface ... and never reads a resource's GPU address".
Step24 measured that shape working (`Res,Prepare` 3371, `Res,Forced` 0, zero GART failures).

Patch: `patches/nmx/0001-accel-task-private-va.patch` (applies to the `ga403wm-nmx` worktree). It
(a) wires the task's `fVa` range to the family's own 1 TiB allocator, locked, shared per device; (b) falls back to that
range when `nvAccelGpuVaAlloc` refuses, recording the result on the map; (c) reports a private-VA map as committed in
`commitIntoGPUPageTable()` instead of demanding an `NVVidMemory` handle; (d) frees the range in `deallocate`.
`nvaccelprivateva=0` restores the RM-only path for an A/B boot.

**It builds on CI.** The accelerator source lives in the `nvidia-macos-driver` fork, whose `ga403wm-nmx` branch had no
workflow; branch `ci/nmxaccel` adds `.github/workflows/build-nmxaccel.yml` on top of the patch. The job runs on
`macos-14`, fetches NVIDIA's public `open-gpu-kernel-modules` tag **610.57.04** (the same version as the local
`~/ogkm610`) for the headers, builds `kexts/NVRM` with `build/nmxaccel_build.sh` and `NM_TAHOE=1`, inserts
`NMXDisplayPipeEnabled` (the local installer's one plist change, which `nmxArm()` requires and the source plist does
not carry), prints the hash and `LC_UUID`, and uploads `NMXAccel.kext`. Run
<https://github.com/thanhnndev/nvidia-macos-driver/actions/runs/39751051561> took 19 s total. `ga403wm`'s own workflow
still builds only the Strix*/itlmt kexts.

**It is installed from Linux.** `kmutil` only exists on macOS, so the write and the relink are split:

* `pkexec scripts/linux-install-nmxaccel.sh <artifact>/NMXAccel.kext` unmounts every mount of the APFS container,
  remounts the Data volume `-o readwrite` (this module accepts `readwrite`, silently ignores `rw`), backs up
  `/Library/Extensions/NMXAccel.kext` and the auxiliary collection to
  `/Library/NullMoth/nmx-step60-20261022T085951Z`, writes the new bundle `root:wheel` (dirs 755, files 644,
  executable 755), arms `scripts/nmx-relink/` as `/Library/StrixGraphicsFix/nmx-relink.sh` +
  `com.itlmt7925.nmx-relink.plist`, and remounts read-only.
* At the next boot the daemon waits 20 s, runs the same `kmutil create -n aux … --repository /Library/Extensions -A`
  the macOS installer runs, asserts both NMXGPU's and NMXAccel's `LC_UUID` are in the new collection, replaces
  `AuxiliaryKernelExtensions.kc`, refreshes `/Library/NullMoth/kexts/26/NMXAccel.kext`, writes
  `/Library/StrixGraphicsFix/nmx-relink.status` and disables itself. This boot keeps running the *old* accelerator —
  a loaded kext cannot be replaced — so it behaves like the boot that produced this step.

The manual route on macOS stays available and does the same in one boot:
`git apply patches/nmx/0001-… && bash build/nmxaccel_build.sh kexts/NVRM out/nmxaccel` then
`sudo scripts/macos-nmx-owns-oled-install.sh <staged trace dir>`.

What the next boots must show, and what each outcome decides:

* boot 1 (old accelerator): `/Library/StrixGraphicsFix/nmx-relink.status` appears within a minute and
  `nmx-relink.log` ends with `RELINKED`; the collection's mtime matches the boot. If it says
  `RELINK_FAILED kmutil=… assert=…`, the old collection was kept — read the log before rebooting again.
* boot 2 (this build): zero `nvAccelRmHandles` / `RM refused` / `freeToAllocGPUAddress` / `failed to allocate GPU
  virtual address`, plus a few `-> private VA 0x...` and `MM commit: private VA ... nothing to map` lines (capped at
  12 and 8) — the mapping path is satisfied and the login session's surfaces prepare.
* `RM refused` still present: the fallback did not run — check the boot argument, and whether `newGPUTask` is the path
  that created this task (`fVa` null would skip the fallback silently in release logging).
* panel lit but the image wrong or frozen: the pipe is a copy path, so read `debug.nmxaccel_iop_ok` /
  `debug.nmxaccel_iop_fail` and the `trx:` budget next; the VA change is not in that path.

Not changed by this step: boot arguments, the allow list, the Metal plugin, the arrangement. No presentation claim.
The day's Wi-Fi panics (AWDL pool flush) are a separate branch and are not this failure.

## Step61 — the VA fix landed; what is left is the compositor, not the pipe (2026-10-22 17:0x)

Boot 2 (16:29, `boot_uuid 7BAE672F…`) confirms Step60 end to end: `nvAccelRmHandles … kapiDevice 0` 12 (the
non-blocking leftovers), `RM refused` 0, `failed to alloc GART` 0, `failed to allocate GPU virtual address` 0,
12× `-> private VA 0x100000/0x14C7000/0x288E000` and 12× `MM commit: private VA … nothing to map`. The pipe arms at
15.214, `scanout ok (foreign 0 head 0)`, seven `display_change_handler` events, `Fallback GPU Display Pipe
transaction submission failed` 0 and `plane with no gamma` 0. The panel therefore has a pipe, a mode and a scanout,
and WindowServer never puts a frame through it.

The reason is one level up: **no process has a Metal device, so nothing is composited at all.**

- pid 205 (login-window WindowServer, root), 15.135: `headless GPU: no device for WindowServer (it composites on
  the GPU that owns the display)`. `plugin/NVMTLDevice.m:322` refuses whenever `nvmtl_vk_vendor() != 0x10de`; the
  panel's accelerator is NMXAccel, vendor 0x1002.
- pid 726 (session WindowServer), 30.527: `vk: zero physical devices through this ICD … (uid 0 euid 88)` at the same
  instant as `Sandbox: WindowServer(726) deny(1) file-write-data /dev/dri/renderD128` and `… /dev/dri/card0`.
- The profile behind that denial is readable on the System volume:
  `/System/Library/Sandbox/Profiles/com.apple.WindowServer.sb` allows `file-write-data` only for `/dev/console`,
  `/private/var/db/.com.apple.iokit.graphics` and `/private/var/run/com.apple.WindowServer.didRunThisBoot`, and its
  `file-issue-extension` rules cover only WindowServer's own cache. A sandbox extension cannot widen it either.
  RADV reaches the GPU through libdrm on `/dev/dri` (BSD nodes), so WindowServer-on-AMD cannot work by flipping the
  plugin gate alone; an IOKit-backed command path would be needed (the StrixAccel-era path never needed this because
  WindowServer composited on the dGPU and only the AMD display pipe copied frames).

Why there is no dGPU compositor either: **NVRM is parked by its own boot guard.** `NVRM::probe` returns NULL when
`nvrm_driver_off()` is true (`NVRM.cpp:373`), and that is true when `nullmoth-nv-starts >= NVRM_GUARD_LIMIT` (2).
The EFI variable held `"2"`, the boot has not one `NVRM:` line, and NVRMFB fell back to `NVRMBootFB`, which refuses
to start because the firmware framebuffer is the panel's (`0x880000000` +20736000 B = 2880x1800x4), not in the
NVIDIA card's windows (`0xD8000000`, `0xDC084000`, `0x892000000`, `0x1000`, `0xDC000000`). That is the HDMI black.

Action taken from Linux, no boot-args or kexts touched: removed the guard counter
`nullmoth-nv-starts-7c436110-ab2a-4bbb-a880-fe41995c9f82` through efivarfs (`nullmoth-nv-ok=1` kept). Next boot NVRM
probes and starts again and counts one start; with the HDMI monitor attached NVRMFB should light head 0 and clear the
counter, which restores both the HDMI output and the dGPU Metal device WindowServer needs. Then the OLED question is
finally measurable: `debug.nmxaccel_iop_ok`, the `trx:` budget, and whether CoreDisplay still answers `plane with no
gamma` (the legacy `IOAccelLegacyDisplayPipe` base of `NVDisplayPipe`) for the cross-GPU present.

## Step62 — the compositor crash is the vendor claim, not the pipe: CoreDisplay aborts on a display whose Metal device came back nil (2026-10-23 1x:xx)

Three boots were logged after the guard patch (`01cb`–`01d0`, decoded from the Data volume with the uuidtext tree
and `dsc/` in place — the logarchive provider wants `Persist/<n>.tracev3`, two-hex-digit uuidtext directories and a
top-level `dsc/`, not a flattened tree). The iGPU side did not regress: NMXGPU 1.0.0 + NMXAccel 0.1 (AuxKC 17:34
Oct 22) still publish `NMXGPUFB`, arm the DCN35 pipe, set 2880x1800@120 and reach `scanout ok (foreign 0 head 0)`.
What changed is the dGPU: the guard patch lets NVRM 2.5.2 run, and NVRM-fb now owns the HDMI head.

| boot | HDMI | NVRM-fb | WindowServer |
|---|---|---|---|
| 10:50 `388439D2` | attached, `dpy 0/4 0x100 connected 1 edid 256 B` | starts, `boot raster 1920x1080 pitch 7680` at 15.71, `NVRMFramebuffer published` 15.74 | 13 processes in 143 s, each dead 0.3 s after launch |
| 10:55 `6B9DAEEC` | absent, `connected 0 edid 0 B` | `kapiInit failed -- refusing to start` 15.92 | pid 1020 runs 348 s, no crash |
| 11:03 `68B018B0` | attached | `boot raster 1920x1080` 17.27 | 6 processes, every 10 s, dead 0.3 s after launch |

The crash is new and not the old `CGXMappedDisplayStart`: four reports at 10:50:56/10:51:01 fault in
`CoreDisplay_CreateDisplayForCGXDisplayDevice` and abort. The binary is not on the System volume (Tahoe keeps it in
the dyld shared cache); the OS cryptex `Cryptexes/OS` on the Preboot volume carries
`cryptex1/current/os.dmg` (APFS), and loop-mounting it gives `System/Library/dyld/dyld_shared_cache_x86_64h`. The
crash frame is `__TEXT 0x7FF805347000 + 289801` = `0x7FF80538DC09` (`symbolLocation` 2972 from `0x7FF80538D06D`), and
the bytes there are the assert tail:

```
7ff80538dbb8  cmpl $0x0,-0x140(%rbp)
7ff80538dbbf  lea  "null"      (0x7FF805452AE7)
7ff80538dbc6  lea  "non-null"  (0x7FF805452ADE)
7ff80538dbcd  cmove %rax,%rcx
7ff80538dbd1  lea  "Failed to create MetalDevice (%s)" (0x7FF805452ABC)
7ff80538dbe9  call snprintf
7ff80538dbf5  lea  "Display"   (0x7FF805452AEC)
7ff80538dbfc  mov  $0xc9c,%edx
7ff80538dc04  call CoreDisplay::Assert
7ff80538dc09  ud2
```

So Tahoe's CoreDisplay requires a **Metal device per display**, and aborts when the display's accelerator advertises
`MetalPluginName` and the plugin answers nil. That is exactly the state the logs show, and it is a plugin ordering
bug, not a pipe bug:

* every WindowServer launch logs two tries, both refused with `headless GPU: no device for WindowServer` (16.87 and
  19.21 in pid 205; once per later pid). `plugin/NVMTLDevice.m:323` refuses whenever `nvmtl_vk_vendor() != 0x10de`;
* `nvmtl_vk_set_accelerator` is first-wins (`if (v && !g_vendor) g_vendor = v;`), and WindowServer asks the
  accelerators in registry order — the built-in AMD panel (`NMXAccel`, 0x1002) first, the NVIDIA one (`NVAccel`,
  0x10de) second. The first request claims `g_vendor = 0x1002`, so the second is refused by the same vendor gate;
* nothing then supplies a device for the NVIDIA framebuffer that NVRM-fb just published, and CoreDisplay asserts on
  it ~0.3 s later. Without HDMI there is no NVIDIA display at all (`NVRM-fb` refuses to start), the AMD-only display
  is tolerated (pid 1020 lives 348 s), and the panel simply never receives a frame.

Fix, no boot-args and no kext changes: WindowServer may not let a non-0x10de accelerator claim the process when an
`NVAccel` exists. The NVIDIA display's accelerator then gets the claim, NVK reaches the card over IOKit (the
WindowServer sandbox allows IOKit, which is why RADV on `/dev/dri` can never work there), and the AMD panel keeps
presenting through its display pipe; apps still get whichever accelerator they ask. The claim deferral is
WindowServer-only.

The plugin is a single translation unit (`plugin/NVMTLDevice.m` `#include`s `plugin/nvmtl_vk.c`), so CI builds it
next to the kext: `macos-26-intel` (the macOS 14 SDK on `macos-14` has no `MTLResidencySet`/`MTLShaderValidation`),
Khronos Vulkan headers, `-bundle -fobjc-arc -O1`, `-framework Foundation Metal IOSurface IOKit CoreFoundation` (IOKit
is needed by the vendor lookup), ad-hoc `codesign`, artifact `NVMTLDriver`.

Installed from Linux into the Data volume, old binary kept:

```
/Library/GPUBundles/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver
  was aa16ed89e19cd5c4308af9fdbb51899754b58c8feb52ca86188ce43fa747b018
  now fee5790b5d490f5a244a01336ccd5524f4e56f5ba141e7e6ec7675f9b6800988
/Library/NullMoth/nvmtl-backup-20261023/NVMTLDriver.aa16ed89  (backup)
```

Rollback is copying the backup back; the kexts, the allow list and the boot arguments are untouched.

What the next HDMI boot must show: no `CoreDisplay_CreateDisplayForCGXDisplayDevice` abort and no 10 s WindowServer
respawn; instead one WindowServer that lives, `WindowServer: the 1002 accelerator does not claim this process` and
`GPU vendor 10de` in its log, `debug.nvaccel_headless` 0, `debug.nvaccelfb` 1. If the abort is gone and the HDMI
desktop appears, the next question is the panel: `debug.nmxaccel_iop_ok` / `debug.nmxaccel_iop_fail`, the `trx:`
budget, and whether the cross-GPU present reaches `NVDisplayPipe` (still an `IOAccelLegacyDisplayPipe`, so `plane
with no gamma` is the expected wall when WindowServer starts pushing the OLED as a second display).

## Step63 — the compositor lives on the dGPU now; the panel is never given a frame (2026-10-23 13:2x–13:3x)

Two boots with the new plugin (`boot_uuid 9D08B76C`, `9B0BCBC74197`; HDMI attached, EDID 256 B). The Step62 fix does
what it was meant to do and nothing crashes:

* `WindowServer: the 1002 accelerator does not claim this process`, then
  `accelerator vendor 1002, but this process runs Metal on 10de: no second device` for the panel's accelerator, then
  `GPU vendor 10de (NVIDIA, NVK)` / `allow-listed: WindowServer` / `UP in this Metal process — "NVIDIA GeForce RTX 5060
  Laptop GPU (NVK GB206-B)"` for the NVIDIA one. One Metal device, on the dGPU, through IOKit.
* WindowServer is stable: login server 205 hands over at ~25 s, session server 790 lives 328 s, 719 lives 406 s. No
  `WindowServer-*.ips` after 11:04, no `CoreDisplay_CreateDisplayForCGXDisplayDevice` abort.
* The HDMI display presents continuously: `NVAccel: surfvram pageoff … 8355840 B` reaches `ok 11264` by 418 s. The
  rate between counter prints is 18–28 fps (55 s for the first 1024, then 37–43 s per 1024).
* The shader path works and caches: `/var/folders/zz/…/C/WindowServer/nvmtl-mesa` grows to `139.8 MiB in 544 files`,
  later boots log `cache hit` for `ViewportToNDC`/`TextureCopy`/`ColorFill`/`UberComposite*`. Translation costs are
  2–17 ms per function, not seconds.

The system nevertheless feels unusable, and the two spindumps say why:

* `Terminal_2026-10-23-133654….hang` (73 s window): WindowServer's `com.apple.coreanimation.pipelines` thread is in
  `CA::OGL::MetalContext::create_pipeline_state → create_fragment_shader → NVMTLLibrary newFunctionWithDescriptor →
  nvmtl_translate_with_fc → metal2vulkan::translate_one` in **9 of 11 samples** — every new function-constant variant
  of CoreAnimation's shaders is compiled on that one thread, and the desktop stops until it returns. The main thread's
  display pass also waits inside `CoreDisplay::DisplaySurface::AccessComplete → NVMTLCommandBuffer
  commitAndWaitUntilSubmitted → waitUntilCompleted` (2 of 11), so each frame is a synchronous GPU round trip.

The OLED gets **zero** frames, and that is not a copy-path failure:

* `NullMoth display: pipe: scanout ok (foreign 0 head 0) 0xB40 0x2D00` at 15.84 — the panel is armed at 2880x1800 and
  scanning out;
* `NMXAccel: NVDisplayPipe::initFramebufferResource(head 0, index 0): CPU-only scanout … frames are copied` and
  `NMX display pipe armed on owned native framebuffer; GPU renders through RADV, present copies IOSurface` — the CPU
  copy path is in place;
* but WindowServer never opens the pipe: `NMXAccel: newUserClient(type 4)` = **0** (no `IOAccelDisplayPipeUserClient2`),
  while `NVAccel` gets 8 of them. Across 330–430 s there is not one `trx:`/present/copy on the AMD pipe, and no
  2880x1800 `shapeSurface`. CoreDisplay sets the mode (`DM displayModeWillChange/DidChange`), gives the panel a
  `new2DContext`, and stops there: without a Metal device for that display it never builds a display surface, so the
  pipe has nothing to display and the raster keeps what the firmware left in it. The "flicker" is the mode/pipe
  delivery happening twice (15.6 and 26.1) on an otherwise empty raster.

So the remaining wall is the same one Step61 named, now measured from the other side: **WindowServer composites the
display it can render on, and the panel is not one of them.** Two ways forward, both a step change:

1. give WindowServer a Metal device that belongs to the panel's accelerator (RADV inside the WindowServer sandbox —
   blocked on `/dev/dri`, so it needs an IOKit-backed command path, or the sandbox rule widened), or
2. find the condition under which SkyLight/CoreDisplay builds a display surface for a display whose accelerator has
   no Metal device, and make the panel satisfy it so the existing `NVDisplayPipe` copy gets a surface to page in.

Neither is a plugin knob. Not changed in this step: boot arguments, kexts, allow list, arrangement. The new plugin
(`fee5790b…`) stays; it is what makes the HDMI desktop exist at all.


## Step64 — direction 2, read from the other side: the panel is not in IOPresentment's map because the 890M has no AGDC service (2026-10-23 14:xx, offline)

Method: CoreDisplay and IOPresentment extracted from the Tahoe dyld cache (`tools/get-ipsw.sh`, `tools/dsc-extract.sh`,
output in `ref/macos-26.7.1/`, `llvm-objdump --macho` for x86_64), cross-checked against the decoded unified log of
boots `9B0BCBC7` / `9D08B76C`. No reboot, no change on the machine.

What CoreDisplay does (macOS 26.7.1):

* `Display::Display` (the constructor reached from `_CoreDisplay_CreateDisplayForCGXDisplayDevice`) asks the display for
  its IOFB service, runs `FindDisplayPipeForService(service)` and stores the result in `[dev+0x14c]`; then it calls
  `CreateMetalDevice(acceleratorID)`. If that throws, the `catch` logs "Failed to create MetalDevice for accelerator" and
  **only asserts (line 0xC9C) when `[dev+0x14c] == 1`**, i.e. when the display has a display pipe. A display without a
  pipe is tolerated silently. That is why the panel-only boot (10:55) survived and the HDMI display aborted (Step62).
* `FindDisplayPipeForService` is only a cache lookup in `gEntryIDs`; the pipes come from `InitializeDisplayPipes`, which
  walks `IOPresentmentGetMap()` (a CFArray of {pipe, service} pairs). "System set to use IOP but no display pipes are
  present" clears `useIOP` for the whole system.
* `UseIOPresentment()` stays true only while every GPU vendor present (bitmask from the IOFramebuffer list) has its
  `useIOP_on{IG,NVIDIA,AMD,APV}` default set. `Display::GetNextSurface` (pool + `DisplaySurface`) is gated on
  `UseIOPresentment()` and `displaySurfaceUsesIOSurface`, not on the Metal device. So a Metal device is not what builds the
  display surface.

What decides the map (`IOPresentment`, `ioPresentmentCreateAssociationMap` → `ioPresentmentFindAGDCMatch`): it iterates
the `AppleGraphicsDeviceControl` services, opens each, asks for `kAGDCVendorInfo`, and associates accelerator,
IOFramebuffer and AGDC by their display-class PCI parent. A GPU without an AGDC service gets no node, no map entry, no
pipe (this is the Step06 finding for StrixAccel, unchanged).

Evidence on the current stack: the only AGDC in the log is NVIDIA's —
`NVRM-agdc: AGDC: UP on PEGP — 1 framebuffer slot(s)` (boots 9B0BCBC7 and 9D08B76C). There is no AGDC line for the 890M, and
`NMXGPU`/`NMXAccel` contain none (`nmx_fb.cpp` only borrows the AGDC K5 timing format; the AGDC object exists only in
`kexts/NVRM/agdc/nvrm-agdc.cpp`, class `NVDADeviceControl`). StrixAccel's `StrixDeviceControl` is off by design
(`-strixaccoff`). Consistent with Step63: `NVAccel` receives eight `newUserClient(type 4)` (its pipe is in the map),
`NMXAccel` receives none (its pipe is not), and the log has a 2880x1800 `iosurface=1` render target on the NVIDIA Metal
device, i.e. WindowServer does render the panel's backing store but has no pipe to hand it to.

Conclusion: the missing piece for direction 2 is not a CoreDisplay condition and not the Metal device, it is an AGDC
service for the 890M that answers like Step06's `StrixDeviceControl` (cmd 1 vendor info AMD/class 2, 0x980 GPU capability
with slot 0 = the NMX framebuffer, 0x921 link config from the real DRM timing, 0x711 type 0x10, 0x2001 accepted). The
PCI node must also carry a display `class-code` (it does now: the DeviceProperties entry has only `name #display`).
This matches roadmap M3(b), "arm the owned display like the NVIDIA path".

Next (not done): `NMXDeviceControl : AppleGraphicsDeviceControl` in the NMX fork, reusing `kexts/StrixAccel/StrixAgdc.h`
and `nvrm-agdc.cpp`, attached to the 890M IOPCIDevice when `nmxArm()` runs; dependency
`com.apple.AppleGraphicsDeviceControl`. Verify with an entitled `iop-getmap` probe (map contains the 890M node and
`IOAccelerator != 0`), `NMXAccel: newUserClient(type 4)` > 0, then the first `trx:` on the AMD pipe.

## Step65 — NMXAGDC: an AGDC service for the 890M (installed, not yet booted)

Step64 found that IOPresentment's device map has no AMD pipe because the 890M has no `AppleGraphicsDeviceControl`
service. `NMXDeviceControl` (nmx-ci `kexts/NMXAGDC`, commit 503ad77, CI job `agdc`) is that service: derived from
NVRMAGDC, vendor AMD 0x1002 class 2, slot table from `NMXGPUFB` (`IOFBDependentIndex`), 0x980 / 0x921 / 0x711 answered
from the framebuffer's `NVRMTiming` (K5 on by default), starts by itself once `NMXGPUFB` exists (retries every 500 ms for
2 min). Sysctls `debug.nmxagdc*`. Installed from Linux with `scripts/linux-install-nmxagdc.sh` (backup
`/Library/NullMoth/nmx-step65-20261023T070831Z`, sha256 074b3b8d…db11); the one-shot relink daemon now also asserts
NMXAGDC is in the new aux collection.

Boot 1 relinks the collection; boot 2 loads NMXAGDC. Check after boot 2: `log show | grep NMX-agdc` ("AGDC: UP"),
`sysctl debug.nmxagdc debug.nmxagdc_cmds debug.nmxagdc_fbmap`, an entitled `iop-getmap` probe (AMD node, accelerator
non-zero), `NMXAccel: newUserClient(type 4)` > 0, then the first `trx:` on the AMD pipe.

### Step65 result — boot 2 (2026-10-23 16:03): AGDC works, the machine freezes ~3 s after the panel pipe opens

Decoded from Linux (unified log of boot `891AFB44`, 32.6 s long; the macOS `wifi.log` stops at the same second, so it is a
real full-system freeze, no panic record, two force reboots).

What worked: `NMX-agdc: AGDC: UP on VGA`, WindowServer lists `agdc /NMXDeviceControl` for gpu 1002.150e, and for the first
time `NMXAccel: newUserClient(type 4)` (IOAccelDisplayPipeUserClient2) > 0 at 29.58, followed by `IOP: 0x1002:0x400`.
IOPresentment now opens the AMD pipe. Step64's cause (no AGDC service, so no pipe) is confirmed.

What did not: WindowServer 205 (running on NVMTL/NVIDIA only, no NMX pipe client) was SIGKILLed at 29.29 (`exit reason
namespace=2 code=9`, no crash report); the respawned 809 opened the NMX pipe at 29.58, `NMX-agdc` got 0x2001, 0x925 and
28x 0x711, all answered `Unsupported` (the K5 answer only covers type 0x10, 0x711 here asks for more), and no NMX `iop: K6
transaction` ever appeared (the NVAccel/HDMI pipe prints them). The log ends 3 s later (SecurityAgent up) with nothing from
the kernel. Earlier panic (`preemption_level -1`, Spotlight, 16:01, before the relink) is from the old kexts, not NMXAGDC.

Rollback applied from Linux so the machine boots again: `nmxamd=1` removed from the boot-args in `/boot/EFI/OC/config.plist`
(backup `config.plist.step66-pre-20261023-161400`). Without `nmxamd` NMXGPU declines the 890M, so no NMXGPUFB, no NMX pipe
and NMXAGDC idles. Re-enable with `+nmxamd=1` once the freeze is understood.

Next: (1) acknowledge only the proven passive `0x2001` client declaration contract (exact 4-byte input, zero output);
keep `0x711` limited to the verified K5/type `0x10` reply and leave `0x925` Unsupported until its semantics are known;
(2) add low-volume entry counters/logs around the display-pipe callbacks so the next boot can distinguish a freeze before
`performTransaction` from one inside it; (3) check whether the 29.29 SIGKILL is the macOS-side agent.

## Step66 — exact AGDC 0x2001 ack + first-pipe observability (2026-10-23 17:xx, offline)

Work was done only in the isolated NMX worktree
`/Users/thanhnndev/develop/projects/nmx-agdc-investigate-20261023`, branch
`codex/nmx-agdc-clientset-trace`; the dirty development checkout was not reset or overwritten. No kext was installed,
`nmxamd=1` remains removed, and there was no reboot.

The Step65 log does **not** justify returning success for every AGDC command. Historical Step07 already showed that
blindly accepting non-type-`0x10` `0x711` breaks the pipe. The only safe contract established here is `0x2001`: the
known NVRMAGDC implementation decodes exactly 4 input bytes into a `uint32_t`, requires zero output bytes, accepts
unaligned input, records the value, and returns success. NMXAGDC now mirrors that exact passive declaration only.
Malformed/null/short/oversized input or non-zero output returns `kIOReturnBadArgument`. `0x711` behavior is unchanged
(K5 answers only the verified scaler/type-`0x10` form); `0x925` remains Unsupported. New read-only counters are
`debug.nmxagdc_client_set` and `debug.nmxagdc_client_set_value`.

A small host-side contract test (`tools/test_nmxagdc_client_set.c`) covers values 1/0, unaligned input, null pointers,
short/oversized input and non-zero output. It passes with `cc -std=c11 -Wall -Wextra -Werror`. NMXAGDC also builds
cleanly:

```text
NMXAGDC md5 fc55fee665f29ad087ba4395811f6192, 55912 B
sha256 a825b953eab7e500287f07459e5e02b3a06bc752832e96e11085323779fd8533
UUID 90C7A833-82AA-3769-9F9A-5AD9D382548D (x86_64)
```

The Step65 freeze happened after `newUserClient(type 4)` but before any `iop: K6` line, so NMXAccel now has
low-volume entry observability without changing transaction results. Each callback increments a counter and logs at
most the first eight entries:

* `debug.nmxaccel_pipe_initfb` — `initFramebufferResource`;
* `debug.nmxaccel_pipe_validate` — `validateTransaction`;
* `debug.nmxaccel_pipe_complete` — `isTransactionComplete`;
* `debug.nmxaccel_pipe_perform` — `performTransaction` entry, before the existing gate/K6 logic.

NMXAccel builds successfully with the tracing patch:

```text
NMXAccel md5 f1864410c706c613e605cfca4361388c, 233576 B
sha256 c4b4b17c7220d5936086314e422b7bd95fc4267bc1608659e6b6a8bd5a8020f0
UUID 6869C77E-E1DA-32B8-98BF-5B2A08D59CBA (x86_64)
Apple clang 21.0.0
```

`strings` on that Mach-O contains all four `iop: TRACE ... entry` messages and all four `nmxaccel_pipe_*` sysctl
names. REA MCP independently opened the same artifact as Mach-O x86_64 and reported the same SHA-256. Deeper REA
queries are currently unavailable because no native analysis provider is configured: Ghidra has no
`GHIDRA_INSTALL_DIR` and no Java runtime, the configured Hopper launcher is missing, and IDA/Kuna are not configured.
This is a tooling limit only; it is not runtime evidence about the driver.

The latest luuumi `amd-rdna3-macos-driver` worktree is still at
`cbb08ddf517c009255a74ad0fbc2cd7e0d6fa339` (`phxboot: keep background neural networks off the GPU, reboot on a GPU
hang`). Its Phoenix stack has the same display-pipe callback shape and still leaves `0x2001` unsupported, so it is
useful for lifecycle comparison but does not supply a proven replacement for this contract. No wholesale Phoenix port
was taken.

Next live boot, only after deliberately re-enabling the NMX stack, capture the existing AGDC counters plus
`debug.nmxagdc_client_set`, `debug.nmxagdc_client_set_value`, `debug.nmxagdc_refused`,
`debug.nmxagdc_last_refused`, `debug.nmxaccel_armed`, `debug.nmxaccel_iop_ok`, `debug.nmxaccel_iop_fail` and all four
`debug.nmxaccel_pipe_*` counters. The first `iop: TRACE` line reached before a freeze determines the next target; a
`performTransaction` entry with no K6 narrows it further. Do not call the freeze fixed until a live boot survives this
path.

### Step66 install — staged for the next hardware boot (2026-10-23 17:47)

The Step66 artifacts were installed into `/Library/Extensions` and a fresh Auxiliary Kernel Collection was built.
The installer backed up the previous NMXAGDC, NMXAccel, cached NMXAccel, and AuxKC at
`/Library/NullMoth/nmx-step66-20261023T104744Z`; its log is
`/Library/NullMoth/nmx-step66-install-20261023T104744Z.log`.

Post-install verification:

```text
NMXAGDC sha256 a825b953eab7e500287f07459e5e02b3a06bc752832e96e11085323779fd8533
UUID 90C7A833-82AA-3769-9F9A-5AD9D382548D

NMXAccel sha256 c4b4b17c7220d5936086314e422b7bd95fc4267bc1608659e6b6a8bd5a8020f0
UUID 6869C77E-E1DA-32B8-98BF-5B2A08D59CBA
```

`kmutil inspect` confirms the rebuilt AuxKC contains `com.nullmoth.NMXGPU`, `com.nullmoth.NMXAccel`, and
`com.ga403wm.NMXAGDC`. The currently running kernel still uses the previous boot's collection. `nmxamd=1` remains
disabled, so this installation by itself does not arm the 890M path; enable it only for the deliberate hardware test.

## Step67 — OLED-only boot 2026-10-23 20:26: amdgpu itself fails to initialise (before any display path)

Decoded from Linux (boot `AB5C9F81`, 105 s, first boot with the Step66 kexts and `nmxamd=1`, HDMI unplugged). This boot never
reaches NMXGPUFB, so none of the Step66 pipe counters exist in it: `drmn0` fails in PSP firmware loading.

```
10.26 drmn0: reserve 0x8900000 from 0x8010000000 for PSP TMR
10.36 drmn0: failed to load ucode SDMA_CTX(0x9) / psp gfx command LOAD_IP_FW(0x6) failed, response status 0x11 (and 0x63)
      ... 19x "failed to load ucode" (SDMA, CP_PFP/ME/MEC1, MES*, RLC*, VCN, DMCUB, VPE)
14.22 drmn0: SMU: I'm not done with your previous command: SMN_C2PMSG_66:0x16 SMN_C2PMSG_82:0x1
14.22 drmn0: Fatal error during GPU init  ->  NullMoth GPU: no driver took 1002:150E
10.21 NMXAccel: NMXGPU has not claimed 1002:150E yet - not starting now   (NMXAGDC then polls 181x "no PCI device or no framebuffer yet")
```

Across the 33 decoded macOS boots amdgpu initialises (`SMU is initialized successfully`) in 30; the failures are
`44BCEA21` (10-21 13:14, 1 ucode failure), `1F4A2989` (10-22 13:14, failure + Fatal) and this one. The working Step65 boot
(`891AFB44`) shows `Seamless boot condition check passed`, `Display Core initialized`, ring tests passing and `NMXGPUFB published`.
So the black OLED here is not the pipe wall: there is no GPU at all. Linux's amdgpu owns the 890M too, but "previous OS = Linux" does
not explain it: `journalctl --list-boots` shows Linux ran 14:38-15:59 and macOS then initialised fine twice (16:01, 16:03), and
`44BCEA21`/`1F4A2989` followed macOS boots, not Linux. Treat it as an intermittent PSP/SMU failure (~3 of 33 boots) that needs the
NMXGPU kext to recover itself (it is built on the mini from drm-kmod; nothing in this repo or CI can rebuild it).

Next: (1) NMXGPU: on `Fatal error during GPU init` do a PSP/SMU reset and retry once (needs the mini build); (2) every boot where
init succeeds, run `scripts/trace-last-boot.sh` (about a minute after the first run) and read the `debug.nmxaccel_pipe_*` counters
for the OLED pipe; the freeze after `newUserClient(type 4)` is the target.

Tooling: `scripts/trace-last-boot.sh [boots] [persist_files]` stages only the newest Persist files, decodes the newest boot and prints
a verdict (GPU init, PSP failures, NMXGPUFB / AGDC / type-4 pipe / K6, last lines before a freeze) to `~/ga403-logs/last-boot.txt`.

## Step68 — OLED boot is laggy because the NMX display pipe never arms: the retry window closes before WindowServer opens the panel (2026-10-23 22:xx)

Two boots decoded from Linux with `scripts/trace-last-boot.sh 2 8` (both: `drmn0: SMU is initialized successfully`, no PSP
failure, so the Step67 amdgpu failure did not happen this time). Boot A (131 s) was force-restarted at the login window;
boot B (566 s) reached the desktop but was unusable.

Boot B, in order:

| t | event |
|---|---|
| 10.04 | `NMXGPUFB published`, `NullMoth display: pipe: scanout NOT READY (foreign 0 head 0) 0x1 0x1` every 200 ms (`fPowerRegistered` is only set by `open()`; the 40-line trace cap is used up by these by ~18 s) |
| 41.47 | `NMXAccel: NMX display bind refused: query 0xFFFFFFFFE00002D8 after 150 attempts` (boot A: 43.34) — `nmxArm` retried 150 × 200 ms = 30 s and gave up |
| 44.01 | WindowServer 1006 spawned |
| 45.18 | WindowServer creates and opens the FB (`Creating FB 1 of 1`), `initFramebufferResource` gate 0 → NULL, `IOFBSetDisplayModeAndDepth` mode 0 fails, `Interface creation error: 0x2002` |
| 45.37 | `Unable to find display pipe for IOFB service / regID: 0xde03 / 0x100000550` |
| 45.43 | `MPAccessSurfaceForDisplayDevice: Failed to set up surface for page flip mode` |
| 45.4 → end | 2485 × `IOAccelLegacySurface::set_shape_backing_length_ext: Bad frame buffer index`, 50 `timed out fence`; no `validate/perform/complete` trace, no `iop: K6`, no `IOP:` line |

So the pipe is **not** broken, it is never armed: `nmxArm` needs `NMXGPUFB::open()` (it is what sets `fPowerRegistered`, and
that open is WindowServer's), and WindowServer now comes up at ~44 s (the AuxKC/relink boots are slow), 3-4 s after the 30 s
window closed. Without `gNvScanout`/`registerFramebufferLocked(1)` there is no display pipe for the panel, CoreDisplay and
IOPresentment have nothing to hand the surface to, and WindowServer (rendering on the NVIDIA NVMTL device) reads every frame
back and writes it into the framebuffer with the CPU: that is the lag. The earlier boot in this file (`scanout ok` at 14.4 s)
armed because the framebuffer was opened early; that is a timing accident, not a design.

Not the cause (checked in the same boot): `ReportCrash` is quiet after the first minute (one cloud-docs error loop of 9.6k
lines in minute 1, memory-limit reports of `dock.extra` / `BiomeAgent` are non-fatal); `launchd` respawn churn is the usual
boot burst (361 spawns in minute 0, ~15/min later); the `IOVersatile` kext retry is 210 lines in the first 2 minutes.

Fix (nmx-ci `ci/nmxaccel` 11f899e, on top of the Step66 branch): `nmxArm` keeps polling — 200 ms for the first 30 s, then
1 s up to 15 minutes — and logs `NMX display bind: scanout ready after N attempt(s)`. Install with
`scripts/linux-install-nmxaccel.sh`, reboot twice (relink, then load). Expected on the next boot: that log line shortly after
`Created FB 1 of 1`, `NMX display pipe armed on owned native framebuffer`, `NVDisplayPipe::initFramebufferResource ... CPU-only
scanout ... frames are copied`, then `iop:` TRACE `validate/perform` lines, `Unable to find display pipe` 0 and no more
`Bad frame buffer index`. Risk: this is the first time the pipe arms with the Step66 AGDC; the Step65 freeze happened right
after the pipe opened, so the log tail after the `armed` line is the next thing to read.

Left for the mini build (NMXGPU): `nmx_fb.cpp` `trace()` caps at 40 lines, all spent on `scanout NOT READY`, so `open` never
shows; count the NOT READY lines separately and keep the cap for the rest.

## Step69 — the Step68 fix works but arms 2 ms too late; publish the scanout before open() (2026-10-23 22:xx, macOS)

Live boot 22:01 (NMXAccel 11f899e + NMXAGDC Step66 + NMXGPU 0340b057), read with `log show --start`:

- `NMX display bind: scanout ready after 152 attempt(s) (2880x1800 pitch 11520)` at 46.677 and `NMX display pipe armed on owned native
  framebuffer`: the polling fix does what it says. No freeze, no panic.
- But WindowServer opens the FB at 46.48-46.50 and CoreDisplay asks for the pipe at 46.679: `Unable to find display pipe for IOFB service
  / regID: 0xd803 / 0x100000562`, `MPAccessSurfaceForDisplayDevice: Failed to set up surface for page flip mode`. The arm is a
  consequence of that same open(), so it always loses the race by milliseconds. Counters: `nmxaccel_pipe_initfb 3`, `validate 0`,
  `perform 0`, `complete 0`, `iop_ok 0`; WindowServer still ~700% CPU (NVIDIA NVMTL render + CPU readback/copy).
- AGDC: `0x2001` accepted (4 times, value 1), `0x3` and `0x941` (48 B in) answered Unsupported, `PerfPowerServices` blocked by AGDCC.
  Nothing is freezing on AGDC now.

Fix (nmx_fb.cpp, NMXGPU 7efe25b8): the scanout callPlatformFunction no longer requires `fPowerRegistered` (it only guards the
IOFramebuffer power driver, which needs open(); the scanout data - kva/width/height/pitch - does not). The pipe now arms ~10 s into the
boot, long before WindowServer. `scanout NOT READY` is counted apart (first 3 then every 100th) so the 40-line trace cap stays for
`open`, `setDisplayMode`, etc. Risk: if arming before open touches IOFramebuffer state, expect the Step28-style power-state panic; the
previous kext is saved at `~/efi-audit/nmxgpu-0340b057` (restore: replace /Library/Extensions/NMXGPU.kext with it, rebuild AuxKC).

Next boot verifies: `scanout ready after N attempt(s)` at ~10-15 s; no `Unable to find display pipe`; `debug.nmxaccel_pipe_validate/
perform/complete` > 0 and `iop: K6`; whether the machine survives the first `performTransaction` (the Step65 freeze point).

## Step70 — why Terminal and osascript dialogs do not come up: the 890M gfx ring hangs on the first app render job (2026-10-24, Linux)

Boot of 16:26 (357 s; NMXAccel 11f899e, old NMXGPU 0340b057 — Step69's NMXGPU was installed afterwards). Decoded with
`EXTRA_PROCS=Terminal,osascript,tccd,... scripts/trace-last-boot.sh 1 8` (new `EXTRA_PROCS` knob keeps more processes).

* The pipe still arms late: `Unable to find display pipe` 47.97, `scanout ready after 155 attempt(s)` 48.20 (Step69's NMXGPU fixes that).
* **WindowServer has no Metal device.** `NVMTL: GPU vendor 1002 (AMD, RADV)` / `headless GPU: no device for WindowServer` /
  `not allow-listed` at 47.83 (`plugin/NVMTLDevice.m` `nvmtl_process_is_allowed`: WindowServer is refused whenever the Vulkan vendor
  is not 0x10de). No NVIDIA GPU is up in an OLED-only boot, so WindowServer composites in software: ~700% CPU, `Bad frame buffer
  index` 15597×, 113 fence timeouts. This is the lag, on top of the missing pipe.
* **Apps do get the AMD device (allow-list `*`) and the first render job kills it.** Terminal: `vk: UP … RADV STRIX1` 102.74, first
  submit `vk: fence wait -> -13 after 253 ms … disabling backend` 104.74 (`Metal failed to build render pipeline … Vulkan is not up
  in this process`), then `drmn0: ring gfx_0.0.0 timeout, signaled seq=16, emitted seq=19` 113.02, `MES failed to respond to
  msg=RESET`, `GPU reset begin` 115.03, `MODE2 reset` / `GPU reset succeeded` 117.78. A Terminal or osascript window needs a Metal
  layer; with the backend disabled it never draws. loginwindow and Finder brought Vulkan up too (no render job logged yet).
* Not the cause: tccd/runningboardd/UserEventAgent volume is churn from the failed UI, `cs_blob` lines are boot-time, ReportCrash quiet.

Mitigation applied from Linux (reversible): `/Library/GPUBundles/nvmtl-allow.txt` has `*` commented out (backup
`/Library/NullMoth/nvmtl-allow-step70-20261024T094731Z.txt`), so ordinary apps get no Metal device and draw in software like
WindowServer; `mtlprobe`/`nvmtltest`/`nvmtlrender` stay allowed by name. Also installed: NMXGPU 7efe25b8 (Step69, `scripts/linux-install-nmxgpu.sh`).

Not done, on purpose: letting WindowServer use the 890M. The gfx ring hangs on the first render job, so that would be a black
screen. Next real blocker is the amdgpu/RADV gfx hang itself (first job: pipeline `fixed_frag_lpf_cpf`, 1216x706 BGRA target):
read the DRM side (`drmn0: Dumping IP State` lines) and test with `tools/890m/vk-compute-min.c` / `render-stress.sh` before any
WindowServer allow-list change.

## Step71 — with the pipe armed before WindowServer, WindowServer aborts for want of a Metal device (2026-10-24 17:2x)

Two boots with NMXGPU 7efe25b8 (Step69) + nvmtl-allow without `*` (Step70). Boot A (55 s of log): `scanout ready after 0 attempt(s)` and
`pipe armed` at 12.0 s, `NullMoth display: pipe: open` and `initFramebufferResource gate 1 … CPU-only scanout … frames are copied` at 45.96,
`newUserClient(type 4)` 45.99, AGDC `0x711` (6508 B in) Unsupported 28×, then `NVMTL: headless GPU: no device for WindowServer` 46.04 and
`Setting offline display` / `Corpse allowed` for pid 1050 at 46.04; ReportCrash 46.40: `Assertion failed: (Failed to create MetalDevice
(non-null)), function Display` (the CoreDisplay line Step64 found: a display that has a pipe must get a Metal device). WindowServer was
spawned once (205 at 6.6 s, 1050 at 45.4 s) and not again: no desktop. Boot B: `drmn0: flip_done timed out` 22.47, NMXGPUFB/pipe armed 22.47,
log ends 31.83 s before WindowServer started (unified log loses the last seconds of a hard freeze, so the freeze point is unknown).

Fix (nmx-ci `ci/nmxaccel` d783aac, `plugin/NVMTLDevice.m`): WindowServer is refused only while `debug.nmxaccel_armed` is 0 or
`debug.nmxaccel_headless` is 1; once NMXAccel owns the display it gets the RADV device (log line `WindowServer: this GPU owns the display`).
Installed with `scripts/linux-install-nvmtl.sh` (plugin sha256 39769b66…, backup `/Library/NullMoth/nvmtl-backup-20261024T173108Z`); one
reboot, no relink. Risk: Step70's gfx-ring hang on an app's first render job can now hit WindowServer (black screen / GPU reset). Next boot
reads: `WindowServer: this GPU owns the display`, `vk: UP`, any `ring gfx_0.0.0 timeout`, `iop: TRACE validate/perform`, `iop: K6`.
