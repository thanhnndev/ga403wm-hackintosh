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
Choppiness note: copy max 6.6 ms is inside the 8.3 ms budget and full-frame 8 ms hits once per
~15 s — the remaining judder suspect is WindowServer pacing to the main HDMI 144 Hz display while
the OLED runs 120 Hz. Test: make OLED main (or match rates) and compare; needs owner eyes.
