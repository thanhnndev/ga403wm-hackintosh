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
