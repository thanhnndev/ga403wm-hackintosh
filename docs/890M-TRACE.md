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

## Step72 — WindowServer still refused: "!WindowServer" reads NVIDIA's debug.nvaccelfb; 780M plugin fixes ported (2026-10-26, Linux)

Boot after Step71 (84.7 s, decoded with `EXTRA_PROCS=Terminal,osascript scripts/trace-last-boot.sh 1 8`):

* Pipe arms early as intended: `scanout ready after 0 attempt(s) (2880x1800 pitch 11520)` and `display pipe armed` at 10.13.
* WindowServer 43.6 / 54.1 / 64.4 (respawned every 10 s): `WindowServer: this GPU owns the display (NMX pipe armed)` (d783aac works),
  then `'WindowServer' is armed-only and debug.nvaccelfb reads 0 -- no device`, then ReportCrash `Failed to create MetalDevice (non-null)`.
* Cause: `nvmtl_accel_armed()` reads `debug.nvaccelfb`. NMXAccel built with `NMX_ACCEL` registers only `debug.nmxaccel_*`
  (`nvrm-accel.cpp` sysctl install), so beside NVIDIA's NVAccel that OID is the RTX 5060's, which is never armed in an OLED boot.
  The 780M repo (luuumi-dev/amd-rdna3-macos-driver, now "nullarc") does register `debug.nvaccelfb` from its NMXAccel because it has no
  NVIDIA kext; that is why the same allow-list line works there.
* Fix nmx-ci cef446e: the armed-only check accepts `debug.nmxaccel_armed` or `debug.nvaccelfb`.

The first gfx hang (boot1 82.81, `ring gfx_0.0.0 timeout seq 45/48`) re-read: `FAULT_ADDR 0`, `PFLT_STATUS 0` -- no VM fault; CP rptr
stops on the RELEASE_MEM after the IB, i.e. the draw never retires (shader/export hang). The SQC `[gfxhub] page fault` at address 0
(92.23) comes only after the MODE2 reset.

780M reference (cbb08dd, 2026-10-21): WindowServer composites on the 780M at 120 Hz with the same NullMoth 2.4.1 plugin base plus 13
AMD commits in `src/nmplugin`. Ported onto ours with `git am -3 -p3 --directory=plugin` (branch nmx-ci `ci/amd-plugin-port`, CI run
40259037403 green): zero-copy IOSurface images (host import, AMD only, `NVMTL_NO_SURFACE_HOST`), host-buffer memory types, static
sampler fallback, points/lines on AMD, lod clamps, WindowServer linear sampling (`fixed_frag_lpf_cpf` -- our first hung pipeline),
page-aligned BOs, descriptor set layout in ascending binding order (RADV mutable lists), mipmapped CA images, surface backing keep,
`extendedDynamicState` enabled (RADV PS epilog cache), tiled copy bounds. Skipped: 0006 (tracing only, conflicted).

Installed plugin `2b8595ce...` (backup `/Library/NullMoth/nvmtl-backup-20261026T092638Z`, previous `39769b66...`); allow-list unchanged
(`#*`, `!WindowServer`). One reboot. Fallback if the desktop hangs on the 890M: remove `nvaccel=1` from boot-args (NMXAccel does not
start, back to the software desktop) or copy the backup plugin back.

## Step73 — WindowServer's sandbox keeps RADV off /dev/dri: zero GPUs, no Metal device (2026-11-02, Linux)

Boots since Step72 (per-boot summary over the staged Persist files):

| boot | time (+07) | GPU init | WindowServer |
|---|---|---|---|
| B3DB718A | 10-29 13:47 | SMU ok, pipe armed 12 s | `allow-listed: WindowServer` (Step72 fix works), then 4x `Failed to create MetalDevice` |
| 6D70212A | 10-29 13:49 | same | same, 3x |
| 96874556 | 10-29 13:51 | **PSP LOAD_IP_FW fails (5 ucode), SMU busy, Fatal error during GPU init** | no NMXGPUFB at all (Step67's intermittent failure, after two crash-loop warm reboots) |

Why the device still fails (B3DB718A 48.05):

    NVMTL: vk: zero physical devices through this ICD -- vkEnumeratePhysicalDevices -> VkResult 0, count 0, in WindowServer (uid 0 euid 88)
    NVMTL:   NVK did not come up in this process - refusing to be the Metal device for WindowServer
    kernel: Sandbox: WindowServer(1089) deny(1) file-write-data /dev/dri/renderD128
    kernel: Sandbox: WindowServer(1089) deny(1) file-write-data /dev/dri/card0

NullMoth's RADV reaches amdgpu through libdrm and `/dev/dri/*`. `/System/Library/Sandbox/Profiles/com.apple.WindowServer.sb`
(`deny default`) allows file reads everywhere but no file writes or `file-ioctl` under /dev (system.sb: ioctl only on
/dev/dtracehelper); its GPU access is IOKit only (`iokit-open` for `IOAccel*`, `IOFramebuffer*`, `IOSurface*`). The NVIDIA path
works because NVRM is reached through IOKit; loginwindow and Terminal are not under this profile, so they enumerate the 890M.
The 780M stack meets the same wall with IOKit (its Mesa 0005 opens PhxBringup through an NMXAccel proxy client).

Fix now (no kext rebuild): add `(allow file-read* file-write* file-ioctl (subpath "/dev/dri"))` to the WindowServer profile on the
system volume and bless a new snapshot, as OCLP does; `csr-active-config` 0x0A43 already includes CSR_ALLOW_UNAUTHENTICATED_ROOT.
`scripts/ws-sandbox/ws-sandbox-dri.sh` runs once from LaunchDaemon `com.itlmt7925.ws-sandbox-dri` (installed from Linux,
`scripts/linux-install-ws-sandbox.sh`): mounts the system volume at /System/Volumes/Update/mnt1, backs the profile up to
/Library/NullMoth/ws-sandbox-<stamp>, refuses unless the patched profile compiles like the original under sandbox-exec,
`bless --create-snapshot`, reboots. Log/status in /Library/StrixGraphicsFix/ws-sandbox-dri.{log,status}. Undo:
`sudo /Library/StrixGraphicsFix/ws-sandbox-dri-undo.sh` (last sealed snapshot). Long-term, sealed-system-free route: an IOAccel*
proxy user client in NMXAccel for the DRM calls (780M model).

Tooling: Linux apfs now mounts read-only with plain `rw` ("experimental writes disabled"); install scripts use `readwrite`.
The unifiedlog parser cache under ~/.cache/ga403 had been cleared and was rebuilt.

## Step74 — boot loop after Step73: the OLED gets the software compositor because the framebuffer class is not "AMD" (2026-11-02, Linux)

Step73 worked: WindowServer now gets the 890M Metal device (`initWithAcceleratorPort`, `vk: UP ... RADV STRIX1`,
`Metal compositor activated`). Three boots after it (BA955BE9, 120D2065, 4107D7F0) never reached the login window, with or without
HDMI: WindowServer aborts about 10 s after each start, twice per boot, then the session dies.

Crash (WindowServer-2026-11-02-1707*.ips, -171147.ips): `CA::OGL::Context::push_surface` assert `found != slist->end()` (line
1186), logged as `context(N) transient surface ... not found`, on 5 parallel CA SW contexts. Main thread:
`CGXUpdateDisplay -> WS::Updater::UpdateDisplays -> CDDisplay::render_update -> CompositorSW::CompositeLayersToDestination ->
layer_blit_* -> CGLayerKitFetch -> CARenderOGLRender`. Read from the dyld cache (no macOS host: own cache reader plus
LC_SYMTAB of each image in the shared __LINKEDIT, objdump on the extracted __TEXT):

- QuartzCore: `FlattenNode::retain_surface -> FlattenManager::flattened_cache_retain_surface` calls ctx->create_surface_from_iosurface.
  `MetalContext` tracks that surface (`Context::track_surface`); `SWContext::create_surface_from_iosurface` ->
  `create_surface_from_data` does not, so `push_surface` cannot find it. Software compositing plus the flatten cache (active
  because a Metal device exists) asserts on every start.
- SkyLight: `CDDisplay::compositor()` = `WSGetCompositorForAccelerator(accelerator())`; with the Metal compositor on it returns
  CompositorSW only when the display's accelerator is 0, else `CompositorMetal::new_compositor`, which matches
  `-[MTLDevice acceleratorPort]` (our device's port is the right one).
- CoreDisplay: `CGXMappedDisplayStart` takes the accelerator from `IOAccelFindAccelerator` (framebuffer `IOAccelTypes`/`IOAccelIndex`,
  set by `IOAccelDisplayPipe::init` when NMXAccel calls found_framebuffer, 11 s into the boot), and `Framebuffer::Framebuffer` stores
  `GetGPUVendorForFramebufferService` at +0x1f0: it looks for "Intel" (2), "AMD" (4), "AppleParavirt" (0x10) in the framebuffer's
  class name, anything else is 1. The 780M hit exactly this (nullarc 6688143, "PhxAMDFB": vendor 1 turns IOPresentment off and
  leaves the panel on the software compositor with the Metal compositor up). Our class is `NMXGPUFB`.

Fix: the class is `NMXAMDFB` (nvidia-macos-driver 616f00e on ci/nmxaccel-arm-late: nmx_fb.cpp, NMXAccel's match/metaCast, NMXAGDC).
The installed kexts are unsigned and the name is one `NMXGPUFB\0` C string in each, so `scripts/linux-patch-nmx-amdfb.sh` rewrote
it in place (3 bytes each; symbols keep the old name) and armed the AuxKC relink, which now reboots by itself when
`nmx-relink.reboot` is present (no desktop to reboot from):

| kext | before | after |
|---|---|---|
| NMXGPU | 7efe25b8… | e75bb84b… |
| NMXAccel | e111043f… | 5020e9cd… |
| NMXAGDC | a825b953… | 37a390a5… |

Backup: /Library/NullMoth/nmx-amdfb-patch-20261102T104204Z (three kexts + AuxKC). Undo from Linux:
`pkexec scripts/linux-patch-nmx-amdfb.sh undo`. Also seen, not fatal: plugin `vkCreateImage(buffer texture) -> -1000158000`
(DRM modifier plane layout) and host-pointer import refused for memory type 5, both falling back to copies.

Next boot (relink, ~2 min, reboots itself), then the boot after it should show: CoreDisplay vendor 4 for the panel, no
`transient surface ... not found`, and the display on CompositorMetal. If GPUWrangler still reports no accelerator for the framebuffer
(the 780M's second issue, 98e9c7b: GPUWrangler probed before the accelerator), a busy hold on the framebuffer until NMXAccel arms is next.

## Step75: WindowServer and loginwindow are up but no frame reaches the panel: the display pipe is never active (2026-11-02)

Boot 8550F017 (first boot with NMXAMDFB): the Step74 fix holds. No `push_surface` asserts, `Metal compositor activated` at 46.68 s,
loginwindow is front process at 47.3 s. The panel still shows nothing because every frame fails:
`[ERROR] - Fallback GPU Display Pipe transaction submission failed` appears 1752 times, and there is not one
`iop: TRACE performTransaction` line in the kernel log. The transactions die in IOAcceleratorFamily before they reach NMXAccel.

Cause: NMXAMDFB answered the scanout query (`NVRM_VRAM_FN_SCANOUT`) with `phys = 0`. NMXAccel's `initFramebufferResource` then
takes its "CPU-only scanout (another GPU's panel) -- no framebuffer resource" branch and returns NULL. The family marks a display
pipe active only once it has a framebuffer resource (`init_framebuffer_resource` sets +0x298), so every transaction ends NotReady.
This is the 780M's M2 bug: nullarc 676445d, where PhxAMDFB reports the scanout physical address. The 780M also adds an
l10r (ARGB2101010) to XRGB narrowing in performTransaction in the same commit, because WindowServer switches the display surface to
10-bit once colour management is up.

Fix (nvidia-macos-driver 30237fd on ci/nmxaccel-arm-late and ci/nmxaccel):
- `nmx_fb.cpp`: `r->phys = fInfo.phys`, the scanout in the 890M BAR, 0x87C000000 here.
- `nvrm-accel.cpp`: `nmxArm` no longer refuses a non-zero phys. It used to: `|| q.phys`, from b5ce9e2.
- `nvrm-accel.cpp`: l10r frames are narrowed while copied.

Install: `pkexec scripts/linux-patch-nmx-scanout.sh <CI NMXAccel>` does three things:
- Rewrites 24 bytes in the installed NMXGPU (NMXGPU has no CI build). In `NMXGPUFB::callPlatformFunction`, `movq $0,0x18(%rcx)`
  becomes `movq 0x1e8(%rdi),%r10; movq %r10,0x18(%rcx)`. `fInfo.phys` is at this+0x1e8.
- Installs the CI NMXAccel. Run 41463278138 is reproducible: the previous 3 runs all gave e111043f.
- Re-arms the self-rebooting AuxKC relink.

| kext | before | after |
|---|---|---|
| NMXGPU | e75bb84b… | 401c4e4c… |
| NMXAccel | 5020e9cd… | d1083a46… (CI) |

Backup: /Library/NullMoth/nmx-scanout-20261102T143700Z (NMXGPU, NMXAccel, AuxKC).

Expect, after the relink boot:
- `initFramebufferResource ... -> vidmem ... over the LIVE SCANOUT phys 0x87c000000`
- `iop: K6 transaction #1 ... on the panel`
- no `Fallback GPU Display Pipe transaction submission failed`

## Step76: the two boots after Step75 never ran the Step75 code (2026-11-02)

| boot | what happened |
|---|---|
| 46B679A1 | The relink boot. It still runs the old AuxKC: `CPU-only scanout -- no framebuffer resource`, then `Fallback GPU Display Pipe transaction submission failed`. Black screen, as expected. kmutil wrote the new AuxKC. |
| E00F313D | Loads the new AuxKC: NMXAccel uuid F4797484-…, the CI build, and the AuxKC holds the patched NMXGPU bytes. amdgpu fails first: `failed to load ucode SDMA_CTX`, `PSP LOAD_IP_FW 0x63`, `amdgpu_device_ip_init failed`, `Fatal error during GPU init`, SMU busy. No NMXAMDFB, NMXAccel never starts, NMXAGDC polls "no framebuffer". |

E00F313D is the intermittent PSP/SMU init failure of Step67/Step73. It appears after a reboot that is not a cold start. The Step75 pipe
code never ran.

The relink did not reboot by itself because `nmx-relink.sh` ran `launchctl bootout` on its own job before the reboot check. That
kills the script, so the reboot never ran and `nmx-relink.reboot` stayed on disk. The log ends at the bootout, then shows `already-done`
from the next start. Fixed: the reboot check now runs before the bootout.

Next: a cold boot (shut down, then power on) with the installed Step75 kexts. Read the log for:
- `initFramebufferResource ... LIVE SCANOUT phys 0x87c000000`
- `iop: K6 transaction`

## Step77: login window on the OLED; WindowServer hangs after the password (2026-11-02)

Boots C562F754 and 26592254 run the Step75 kexts. `initFramebufferResource ... over the LIVE SCANOUT phys 0x87C...` and
`iop: K6 transaction #0..` show up, and the login window is on the panel. After the password (26592254: ReturnFromAuthCopy at 73.1 s,
Dock and SystemUIServer at 73.8 s, WS `timed out fence` at 74.1 s) the WS main thread logs nothing more. watchdogd kills WindowServer
("main thread unresponsive, 40 s since last checkin"), and the verbose console comes back.

The watchdog spin dumps (~/ga403-logs/step77, identical in both boots) show:

| thread | where |
|---|---|
| WS main (`ws_main_thread`) | SkyLight → NVMTL plugin → blocked on a turnstile owned by `nvmtl.execution` |
| `nvmtl.execution` | RADV → libdrm ioctl → NMXGPU `drm_ioctl` → `drm_ioctl_kernel` → `linux_synchronize_rcu` → `ck_epoch_synchronize_wait`, spinning (cpu 5.5 s of 5.5 s) |
| `linuxkpi_irq_wq` | `linux_rcu_cleaner_func` → `linux_synchronize_rcu` → `ck_epoch_synchronize_wait`, also spinning |

The cause is that an RCU epoch record stays active forever. `linux_rcu_read_lock` takes the record of `curcpu`, and
`linux_rcu_read_unlock` takes the record of `curcpu` again. FreeBSD pins the reader in between. On xnu `sched_pin` only counts (see
the nmx_kernel.c note: a real pin kept interrupts off and caused TLB-shootdown panics), so a reader that migrates ends its epoch on
another CPU's record. Its own record keeps `active != 0`, and every later `synchronize_rcu` waits on it. The other record's
counters and TAILQ tail are also corrupted. Before login the load is light and readers rarely migrate. After login (Dock, SystemUIServer,
apps, much more GPU work) it happens within a second.

Fix (NMXGPU, no CI build: binary rewrite of both functions in place, `scripts/nmx-rcu/rcu.s`, 416 bytes at 0x6c4e00):
- Every reader uses the CPU-0 record of its RCU type. ck_epoch sections make a shared record make progress, the same way FreeBSD's
  per-CPU record is shared by preempted readers on that CPU.
- A spinlock in record 0's padding (+0xf8; the struct ends at 0xd8) serializes the record and TAILQ updates across CPUs. It is held
  only inside the existing critical section (interrupts off), and only around `_ck_epoch_addref`/`_ck_epoch_delref` and the list ops.
- No relocations fall in the range. Only `linux_rcu_runtime_init` and these two functions touch `nmx_dpcpu_linux_epoch_record`.

`pkexec scripts/linux-patch-nmx-rcu.sh`:

| kext | before | after |
|---|---|---|
| NMXGPU | 401c4e4c… | 02a336b4… |

Backup: /Library/NullMoth/nmx-rcu-20261102T170256Z (NMXGPU, AuxKC). The relink is armed and reboots by itself.

Source fix for the mini build: in linux_rcu.c, store the record in the task at lock time (or use a single record with a lock), not
`DPCPU_GET` at unlock.

## Step78 — panic 40 s after login: preemption_level -1 in WindowServer (mutex unlocked while free)

Boot AF86A8DB (2026-11-03): Step77 worked. The password was accepted, loginwindow switched to the session at 49.4 s, then the
whole log stopped at 52.7 s. Nothing from the Mac's logs named the cause. The panic report is in NVRAM (`AAPL,PanicInfo000*`, readable
from Linux in efivars: skip the 4-byte attribute header, then unpack the 7-bit LSB-first stream):

```
panic: thread_invoke: preemption_level -1, possible cause: unlocking an unlocked mutex or spinlock
process: WindowServer (pid 1083), uptime 88 s
  lck_mtx_lock_slow -> thread_block
  IOMemoryDescriptor::createMappingInTask
  nmx_xnu_map_pages <- vmap <- ttm_bo_kmap <- amdgpu_bo_kmap
  amdgpu_cs_patch_jobs+0x345 (b15 nmx_cs_prepare_ibs, kmaps every GFX IB) <- amdgpu_cs_ioctl
```

The stack only shows where the damage was detected. On x86 xnu, `lck_mtx_unlock` of a mutex that is not held is handled as the
release of a mutex held in spin mode, so it calls `enable_preemption`. The preemption level drops to -1, and the next `thread_block`
on that thread panics. Here that is a kmap blocking on a VM mutex. The same panic was seen once before (Step65, Spotlight, 10-23),
so it is a latent xkpi bug and the RCU patch did not introduce it. More GPU work after login makes it frequent.

xkpi's FreeBSD `struct mtx` records the owner (`+0x20`, set only by `nmx_mtx_lock`/`trylock`, also on the release/reacquire paths
of `nmx_lock.c`). So `nmx_mtx_unlock` with no owner is always a bogus unlock.

Guard (NMXGPU, binary): `nmx_mtx_unlock` (0x6d8850) jumps to a copy of itself in `dce_v6_0_crtc_disable` (0x156ef0, SI display
only, never runs on the 890M; `scripts/nmx-mtxguard/cave.s`). The copy reuses the original `lck_spin_unlock`,
`ml_set_interrupts_enabled` and `lck_mtx_unlock` call sites, so no relocation moves. An unlock with no owner does not touch the
xnu lock and prints, through the tail `jmp printf` in `atom_op_beep`:

    NullMoth xkpi: unlock of unlocked mutex <name> (<mtx>) from <caller>

`pkexec scripts/linux-patch-nmx-mtxguard.sh`:

| kext | before | after |
|---|---|---|
| NMXGPU | 02a336b4… | 9ea37786… |

Backup: /Library/NullMoth/nmx-mtxguard-20261102T174508Z. The relink is armed.

Next boot: grep the log for `unlock of unlocked mutex`. The caller address names the code with the unbalanced unlock, which then
gets a proper fix. Not covered: unbalanced `lck_spin_unlock`/`IOLockUnlock` outside the xkpi mutex.

### Step78b — the guard never loaded: launchd kept nmx-relink disabled

The next two boots (04651B8C, D074E24E) panicked the same way (`preemption_level -1`, WindowServer, `amdgpu_cs_ioctl →
amdgpu_cs_parser_fini → drm_exec_fini → free → kmem → lck_mtx_lock`, uptime 89 s), and no `unlock of unlocked mutex` line was
logged. The AuxKC was still the 00:14 one and contained no cave bytes, and the relink had left no log or status. The Step77 relink
had run `launchctl disable system/com.itlmt7925.nmx-relink`. launchd keeps that in
`/private/var/db/com.apple.xpc.launchd/disabled.plist` and ignored the reinstalled plist.

- `nmx-relink.sh` no longer disables its label. The `.done` file and the plist removal already make it one-shot.
- `linux-patch-nmx-mtxguard.sh` removes the label from `disabled.plist`. It was rerun: the patch was already in, and the relink is
  armed again.
- The other `linux-patch-nmx-*.sh` scripts have the same gap if they are rerun.

## Step79 — idr_preload/idr_preload_end lock and unlock different CPUs' mutexes (the real Step78 cause)

The relink with the mtx guard ran (C2D75D9D, 09:04). Then 3 boots:

| boot | what happened |
|---|---|
| B0BE89DF | Login, desktop transition at 51 s. WindowServer killed by the userspace watchdog twice (09:06:44 and 09:07:24, both "main thread unresponsive"). |
| AF54DC1A | PSP firmware load failed, `Fatal error during GPU init` (the known intermittent init failure). |
| 2DEFF732 | WindowServer connected only at 117 s. 105× `Fence fallback timer expired on ring sdma0` (no GPU interrupts), `flip_done timed out`, WindowServer abort in `CoreDisplay::DisplaySurface::GetMTLTexture`. |

No `unlock of unlocked mutex` line was logged and no panic was recorded.

Both watchdog stackshots (B0BE89DF) show the same thing. A WindowServer thread in `drm_syncobj_create_ioctl → drm_syncobj_get_handle →
idr_preload → nmx_mtx_lock` is blocked on a kernel mutex "owned by thread 6698", and that thread no longer exists anywhere in the
stackshot.

`idr_preload` locks `linux_idr_cache[nmx_curcpu()]`, and `idr_preload_end` unlocks `linux_idr_cache[nmx_curcpu()]` again (FreeBSD
linux_idr.c, which relies on `sched_pin`, a counter on xnu, the same fault as Step77). A caller that migrates between the two calls
unlocks the wrong CPU's mutex:
- If that mutex is free, `lck_mtx_unlock` of an unheld mutex drops the preemption level to -1, which caused the Step78 panics
  (08:39 and 09:03 reports, D074E24E/AF86A8DB). The guard catches this case now.
- If another thread holds it, that thread's mutex is stolen. Either way the caller's own CPU's mutex stays locked forever after
  the thread returns or exits, and the next `idr_preload` on that CPU (`drm_syncobj_create` from RADV) hangs WindowServer.

Fix (`scripts/linux-patch-nmx-idr.sh`, NMXGPU binary): the 6 `call nmx_curcpu` that index `linux_idr_cache` (in `idr_preload`,
`idr_preload_end`, and both reserve paths in `idr_get_new_locked` and `idr_get_new_above_locked`) become `xor eax,eax; nopl`, so
there is one cache and one mutex for all CPUs. All are internal rel32 calls, with no relocations. `idr_preload_init`/`uninit` still
set up every CPU's cache (unused).

The other `nmx_curcpu` users were checked:
- `lkpi_kernel_fpu_*` runs inside a critical section with interrupts off.
- `tasklet_schedule` computes the pointer once.
- RCU was fixed in Step77.

| kext | before | after |
|---|---|---|
| NMXGPU | 9ea37786… | c2979d9b… |

Backup: /Library/NullMoth/nmx-idr-20261103T022425Z. The relink is armed.

Source fix for the mini build: in linux_idr.c, keep the `lic` pointer from `idr_preload` in the task (or use one global cache)
instead of `DPCPU_GET` in `idr_preload_end`.

Still open: 2DEFF732's missing sdma interrupts after a failed PSP-init boot.

## Step80 — desktop works, WindowServer dies after about a minute: syncobj wait timeout returned ETIMEDOUT, not ETIME

After Step79 the desktop came up and was usable, with some tearing. About a minute later the screen went to the verbose console
(boot 0577C74D, 266 s). There was no panic, no GPU fault, no ring timeout. WindowServer logged:

```
266.47 NVMTL: vk: fence wait -> -13 after 295 ms (budget 5000 ms); disabling backend without retiring in-flight resources
266.47 Detected command buffer completion failure.  Error code = 0x1
266.47 loginwindow: Window Server exited, closing down the session immediately
```

-13 is `VK_ERROR_UNKNOWN`. NVMTL waits on each fence in 250 ms slices (`vkWaitForFences(…, 250 ms)`) and loops on `VK_TIMEOUT`.
Mesa (17ca6174, `vk_drm_syncobj.c`) returns `VK_TIMEOUT` only if `errno == ETIME`. On macOS that is 101. NMXGPU's
`drm_syncobj_array_wait_timeout` returns `-0x3c` (FreeBSD linuxkpi defines `ETIME` as `ETIMEDOUT`, 60). So every syncobj wait that
times out is a hard error. This was the first fence in the session that took longer than 250 ms. The log also has 31 `STALE fence read
on sdma0` and 9 on `mes_3.0.0`, and 16 `timed out fence`.

Fix (`scripts/linux-patch-nmx-etime.sh`, NMXGPU binary): `movq $-0x3c,%r15` at 0x437ba6 (the timeout path of
`drm_syncobj_array_wait_timeout`) becomes `movq $-0x65,%r15`, the macOS ETIME. Only `drm_syncobj_wait_ioctl` and
`drm_syncobj_timeline_wait_ioctl` call it, and both return the value unchanged. linux_file_ioctl only rewrites
EINTR/ERESTART(SYS).

| kext | before | after |
|---|---|---|
| NMXGPU | c2979d9b… | 1e0e1524… |

Backup: /Library/NullMoth/nmx-etime-20261103T024332Z. The relink is armed.

Source fix for the mini build: in the xnu linuxkpi errno.h, define `ETIME 101`, or remap it in the ioctl return.

Still open:
- Tearing: K6 transactions scan out straight from the IOSurface, and no flip/vblank sync is visible in the log.
- Slow fences (stale sdma/MES fence reads, the missing-interrupt pattern of 2DEFF732).

## Step81 — WindowServer died ~20 s after login; nullmoth-wsreset kills WindowServer on every boot; record WindowServer deaths

Boot 44707127 (Step80, ETIME fix relinked). Timeline:

- 51 s: `nullmoth-wsreset` (the NVIDIA flicker stopgap; it gates on `com.nullmoth.NVAccel`, which still loads for the RTX 5060)
  SIGTERM/SIGKILLs the first WindowServer at the login window (`wsreset.log`: "restarted WindowServer once" 03:28:06). It does
  this on every boot (also 09:31:49 the boot before). On the 890M it only tears down live GPU contexts.
- 80.5 s: login on the second WindowServer (pid 988).
- ~93 s: WindowServer's render side goes silent (no NVMTL / process-state lines; "pid … failed to act on a ping"); only
  "Invalid display" and new-connection lines from other threads continue. That is the render thread blocked in a fence wait.
- 101.3 s: last log line on disk (every process). display-trace sees pid 988 gone at 03:29:02 (up 107 s), then nothing.

No panic, no .ips, no "unlock of unlocked". `STALE fence read` (31) is already handled (fence_process clflushes and uses the
memory value), and no `fence fallback` line: IRQs are arriving. Most likely NVMTL's 5000 ms fence budget ran out on a GPU job that
did not finish (after Step80 a slow fence no longer kills it at 250 ms), but the lines that would say which (NVMTL "fence wait",
drm_sched) were in the last ~6 s that logd never persisted before the power-off.

Fix (`scripts/linux-install-wsdeath.sh`):
- `/Library/NullMoth/no-wsreset`: wsreset exits, no more WindowServer kill at boot.
- `com.nullmoth.wsdeath` (`scripts/wsdeath/`): polls WindowServer every second; when its pid goes away it writes
  `log show --last 3m` (WindowServer, kernel, loginwindow, ReportCrash, watchdogd; ibprep spam dropped) to
  `/Library/NullMoth/wsdeath/<time>-ws<pid>.log` and syncs. The next death is on disk even if the machine is powered off.

Still open: which GPU job stalls >5 s (read from the next wsdeath log), tearing, PSP init retry.

## Step82 — 7 minutes of desktop, then a GPU page fault hung a job; wsdeath recorded it

Boot after Step81 (wsreset off): the desktop ran 7 min (WindowServer 205, 05:33:53Z → 05:40:54Z). `wsdeath/20261103T054054Z-ws205.log`:

```
12:40:48.858 WindowServer  Tracking override 'set_mesh_warp'          (window animation, Edge became frontmost)
12:40:48.917 kernel drmn0: [gfxhub] page fault (src_id:0 ring:24 vmid:1 pasid:32769)
             in page starting at address 0x0000800102e4d000 from client 10
             GCVM_L2_PROTECTION_FAULT_STATUS:0x00101031  UTCL2 client TCP (0x8), MORE_FAULTS 1, PERMISSION_FAULTS 0x3,
             MAPPING_ERROR 0, RW 0 (read)
12:40:53.944 NVMTL: vk: fence wait -> 2 after 5029 ms (budget 5000 ms); disabling backend
12:40:53.945 SkyLight: Detected command buffer completion failure.  Error code = 0x1  -> loginwindow: Window Server exited
```

A shader texture read (TCP) hit a PTE that is not valid (permission fault, not a walker or mapping error) at the high VA
0xffff800102e4d000 (RADV high range, same range as the IBs at 0xffff80010002b000), 60 ms after a window animation began sampling
window surfaces. The job never completed, and NVMTL gave up after its 5 s budget. The respawned WindowServers (8240, 8427) abort in
`CoreDisplay::DisplaySurface::GetMTLTexture` (the device is gone) — secondary. This is the first page fault in all saved logs.

Ruled out: CPU-written page tables (`amdgpu_vm_update_mode` = -1 → mode 2, CPU only for compute VMs; gfx VMs use SDMA).
`amdgpu_noretry` = 1. The fault report's "pid 34005" is not a real pid (task_info is not filled on xnu).

Open: which BO was at that VA (unmapped/evicted while in use, or a fresh mapping whose SDMA PT update had not run), tearing.

## Step83 — tearing: the K6 copy now trails the display scan

Cause: NMXAccel's K6 path (`NVDisplayPipe::performTransaction`, NMX build) copies each 2880×1800 frame (~20 MB, l10r narrowed
to XRGB) straight into the live scanout at phys 0x87C000000 while DCN scans it out. There is no second buffer and no flip, and
the copy ignored the scan, so a refresh shows the top of one frame over the bottom of the last.

Fix (nvidia-macos-driver b5d7a79 on ci/nmxaccel, CI run 41586784851, NMXAccel 99a11fb3…): the copy is written in 48-row bands.
A band is written only after the scan has passed it (+8 rows) in the refresh being scanned, and the whole copy has to land before
the scan comes back to it in the next refresh. Every refresh then shows one complete frame (the old one or the new one). If the
copy starts too late in a refresh to finish ahead of the next one (judged from the measured copy length in scan lines), it trails
the next refresh instead. The scan line is `OTG_STATUS_POSITION` read over BAR5 (DCN 3.5: segment 2 base 0x34C0,
OTG stride 0x80, V_TOTAL 0x1b2f, V_BLANK_START_END 0x1b38, CONTROL 0x1b43, STATUS_POSITION 0x1b4a). These were checked live on
Linux on this machine: OTG0 is the only enabled timing generator, vtotal 1824, active lines 16–1815, and the counter advances.
A timing generator that does not match the frame (active rows ≠ height), or `debug.nmxaccel_beam=0`, falls back to the old
unpaced copy. A simulation of the algorithm (scratch `beamsim.py`) shows no torn refresh at copy speeds from 0.05 to 1.9 scan
lines per row, except the first frame before the copy length is measured.

Cost: up to about one refresh (8.3 ms at 120 Hz) of waiting per frame in performTransaction. It is counted.

Counters: `debug.nmxaccel_beam_{ok,lapped,off,wait_us,copy_us}`. Log: `iop: beam: register BAR5 mapped`, then
`iop: beam: OTG0 vtotal 1824 active 16-1816: copy … us, waited … us, copy ~N lines`.

Install: `pkexec scripts/linux-install-nmx-beam.sh <CI NMXAccel>`. Installed 2026-11-03, backup /Library/NullMoth/nmx-beam-20261103T060033Z, relink armed.

| kext | before | after |
|---|---|---|
| NMXAccel | d1083a46… (CI 41463278138) | 99a11fb3… (CI 41586784851) |

## Step84 — GFX hang after minutes of use: TTM pool pages zeroed through the cached view and never flushed

Boot after Step83: no more tearing. About 2 minutes later (13:20:59, screen saver and lock started at 120 s idle) WindowServer
205 waited 5094 ms on a fence, NVMTL disabled the backend, and WindowServer exited. wsdeath recorded three deaths
(`~/ga403-logs/step84/`): 205 at 13:21:04, the respawned 9653 at 13:21:18 and 9851 at 13:21:28. The user then hard-rebooted.

Kernel, 13:21:09.7 (10 s job timeout): `ring gfx_0.0.0 timeout, signaled seq=73260, emitted seq=73261`. The ring reset
failed (`MES failed to respond to msg=RESET`, then `REMOVE_QUEUE`, `failed to halt cp gfx`). A MODE2 reset reported
success at 13:21:14.98. The GPU then completed nothing: WindowServer 9851's first submit never wrote its keep witness
(`keep witness 1 NOT seen after 1000 ms`, backend disabled), and CoreDisplay threw in `GetMTLTexture`, as after Step82.
Fault registers were clean (`PFLT_STATUS 0`, `FAULT_ADDR 0`, noretry), so this hang was not a VM fault.

Where the CP stopped (GC 11.5 field names):
* `GRBM_STATUS 0xa800302c`: GUI/CP active. SPI, SC, PA, DB, CB, TA and GE idle: no shader work.
* `CP_BUSY_STAT 0x80`: only PFP_PARSING_PACKETS. `CP_CPF_STATUS` shows the ring and IB1 ROQs busy, IB2 not.
* `CP_IB1 0x8001_00055000` (0x1420 dw) and `CP_IB2 0x8001_00015000` (0xf0 dw) were fetched completely (`BUFSZ 0`).
  The ring rptr 0x412 sits on that job's FRAME_CONTROL/RELEASE_MEM tail.
* **`CP_PFP_HEADER_DUMP 0x00000000`**, `CP_ME_HEADER_DUMP 0xc0065800` (ACQUIRE_MEM). The idle state of other boots reads
  `c0001700/c0001700`.

So the PFP was stopped inside the IB on a packet header of zero, a dword that RADV never writes into an IB. The memory
the CP read held zeros where commands should have been.

Mechanism, read from the installed NMXGPU (step77 disassembly, same code today):
* All GTT memory is write-combined (`amdgpu-ttm-force-wc`): PTEs are not snooped, user and vmap mappings are WC.
* When a WC page goes back to the TTM pool, `ttm_pool_free_range` (inlined `ttm_pool_type_give`, call at 0x5fe42b) clears
  it with `pmap_zero_page`, which is `bzero(m->nmx_kva, 4096)`. `nmx_kva` is the kernel's **write-back** view, so the
  page's zeros sit in the CPU cache as dirty lines.
* The pool later hands the page to a new buffer with no flush. `pmap_page_set_memattr` flushes only when the attribute
  changes, and a pool page is already WC.
* The new owner (an IB, a descriptor or address page, a texture) writes through WC, or the GPU writes it without snooping.
  The aliased dirty zero lines are written back over that data whenever they are evicted.
* Linux does not have this alias, because `set_pages_array_wc` makes the direct map WC as well.

This one bug explains several observations:
* Random 64-byte zeros, at a random later time, in buffers the GPU reads.
* It gets more likely the longer the session runs, because more allocations come from recycled pool pages.
* Step82's TCP read through an invalid address (a zeroed descriptor or address table).
* This header-0 hang.
* Why b15's clflush of the IB at submit seemed to cure IB corruption (Step46/49): it pushes the aliased lines out
  before the CP reads, but only for the outer IBs. Chained IBs, IB2s and data buffers are not covered.

Fix, `scripts/linux-patch-nmx-zeroflush.sh` (NMXGPU binary, no CI build):
* `pmap_zero_page` (0x6dda90, 32 bytes) now zeroes the page with `rep stosb` and tail-jumps to
  `pmap_invalidate_cache_range` (0x6dd980), which does clflush per line and then mfence.
* The `jmp _bzero` at 0x6dda9e keeps its bytes, because its external relocation (the only one in 0x6dd900–0x6ddb00) is
  still applied when the AuxKC is linked. The new code jumps around it.
* The script refuses to patch if the original bytes, the caller or the target do not match.

Cost: 64 clflush per freed page.

Not fixed by this: recovery after a GPU reset (MES does not answer, and the MODE2-reset GPU runs no job). With the source of the
corruption gone, that path should no longer be reached; it stays open.

Installed 2026-11-03 13:39 (UTC 06:39): NMXGPU sha256 `0a6c745a…2da2bda0`, backup `/Library/NullMoth/nmx-zeroflush-20261103T063918Z`,
nmx-relink armed (the first macOS boot relinks the AuxKC and reboots by itself).

## Step85 — intermittent PSP LOAD_IP_FW failure at init: what is known, and a snapshot of the PSP before NMXGPU starts

Failing boots on record: E00F313D, F4A73646 (every load 0x11) and 9E6328B3 (mostly 0x63). Older ones are 96874556,
AF54DC1A, 44BCEA21, 1F4A2989 and AB5C9F81. On 9E6328B3 the blobs with no signature (CP_MES_DATA, RLC_RESTORE_LIST_GPM_MEM,
RLC_P) load and every signed one fails. The SMU line that follows is a consequence, not a cause:
`I'm not done with your previous command: SMN_C2PMSG_66:0x16 SMN_C2PMSG_82:0x1` is `PPSMC_MSG_EnableGfxImu` with
argument 1. smu_hw_init sent it on that same boot, after the PSP failures, and it never answers because GC has no firmware.

Ruled out (each was checked against the binary or the hardware):
* VRAM aperture, TMR and GART table placement: VRAM is 0x860000000–0x87FFFFFFF, the TMR is 0x870000000–0x878900000, and the GART table is at 0x87FB00000. No dGPU BAR or xnu RAM overlaps them.
* The setup of the fw_buf pages:
  * `vm_page_alloc_noobj` zeroes the page through the write-back view with attribute 6.
  * `lkpi_set_pages_attr(WC)` then goes through `pmap_page_set_memattr`, which flushes each line with clflush and then mfences, because the attribute changes.
  * Pool pages are zeroed by the Step84 `pmap_zero_page`, which flushes.
  * `amdgpu_gart_invalidate_tlb` mfences before it flushes HDP and the TLBs.
* The shutdown path exists and is complete:
  * `NMXGPU::systemWillShutdown` → `nmx_port_shutdown` → `nmx_bus_call_children("device_shutdown")` → `linux_pci_shutdown` → `amdgpu_pci_shutdown`.
  * `amdgpu_pci_shutdown` sets mp1_state = UNLOAD (2) and calls `amdgpu_device_ip_suspend`, so smu_v14_0_0 sends PrepareMp1ForUnload.
* Late loading of NMXGPU: TMR is reserved 9–11 s after boot on both good and failing boots.

Leading explanation (not yet proven on this machine):
* AMD says the PSP accepts firmware only once per power cycle or hard reset (amd-gfx "amdgpu vs kexec", June 2025, Christian König). On an APU it is worse, because the PSP is shared with the CPU.
* For GFX11+ APUs, Linux relies on PrepareMp1ForUnload at driver unload (see the `amdgpu_device_ip_fini_early` comment). After that message, PMFW resets GC and the next load is accepted.
* A session that ends without that message leaves the next warm-reset boot unable to load firmware:
  * a failed init, which has no SMU hw and fails DESTROY_TMR;
  * a panic;
  * a watchdog;
  * a reboot that skips the shutdown callbacks.
* This fits the F4A73646 → 9E6328B3 chain: a failed boot, then a quick reboot, then another failed boot.
* It also fits the Linux boot after 9E6328B3, which worked. Every Linux boot here starts from S5: `x86/amd: Previous system reset reason [0x00200800]: ACPI power state transition`, so it does not show that a warm reset clears the PSP.
* It does not yet explain the boots after the relink boots C82DFDFB and 46B679A1, which reboot through `/sbin/reboot` with the GPU up.

What decides it: AmdCppc now reads the following before NMXGPU starts, and logs one line,
`AmdCppc: psp at start: reset=… psp35=… psp64=… ring_lo=… ring_hi=… ring_sz=… sol81=… smu_msg=… smu_arg=… smu_resp=…`
(also `sysctl debug.amdcppc.psp`):
* the FCH S5_RESET_STATUS (0xFED803C0);
* the PSP KM ring registers (C2PMSG_69/70/71);
* sOS sign of life (C2PMSG_81);
* the SMU mailbox (C2PMSG_66/82/90);
These are SMN addresses through 00:00.0 config 0x60/0x64, checked against Linux amdgpu on this machine. Live Linux values: ring 0x80_1faa5000 size 0x1000, sol 0x0031860a, SMU msg 0xf arg 7 resp 1.
* A failing boot that shows a warm reset and the previous session's ring still programmed confirms the explanation. The fix is then in NMXGPU init, before PSP hw_init: finish the missing unload (PrepareMp1ForUnload, as Linux's driver unload does) when the PSP still holds a session.
* A failing boot after an S5 reset with clean registers rules it out.

Source: rog-control-macos branch `diag/psp-snapshot`, built by CI. Installed 2026-11-03 to `/boot/EFI/OC/Kexts/AmdCppc.kext` with
`scripts/linux-install-amdcppc-psp.sh`, backup `/boot/EFI/OC/Backup/AmdCppc.kext-20261103T083255Z`. This repository's
`kexts/AmdCppc` copy is stale (the kext moved to rog-control-macos), so the same edit here was reverted.

## Step86 — GFX ring timeout after login (WindowServer back to console): what is ruled out, and an IB probe at the hang

Symptom: the session comes up and runs for a while, then the GFX ring times out and WindowServer dies back to the console.
wsdeath logs `20261103T091549Z-ws3813.log` and `20261103T091808Z-ws2830.log` give the dumps:

| Boot | CP_IB1 | CMD_BUFSZ | Left | PFP header | ME header | Other |
|---|---|---|---|---|---|---|
| 1 | 0x8001_090a0000 | 0x5008 | 0xac8 | 0 | c0055000 | PFLT_STATUS 0 |
| 2 | 0x8001_08e85000 | 0x1f0 | — | 0x1f810080 | c0016900 | "Illegal register access in command stream" |

The CP is inside a WindowServer IB. On boot 2 the PFP is decoding a type-0 header, which no user IB contains. Step84
(zeroflush) did not cure it.

Ruled out against the binary (NMXGPU after Step84):
* User mmap of GEM BOs: `nmx_umap_cache` defaults to 1, which is cache index 0 (kIOInhibitCache, UC). Table 0x899694, `nmx_umap_insert` 0x6cf420.
* Kernel vmap of WC BOs: `ttm_prot_from_caching` WC → memattr 1 → `nmx_xnu_map_pages` table 0x899828 maps it to 0x401 (WC).
* dma_fence callbacks run in FIFO order (add_tail, walk in order).
* VM TLB flush: `amdgpu_vm_tlb_flush`, the `tlb_seq` callback (vm+0x4c0) and the `vmid_grab` flushed_updates check match upstream.
* A stale user mapping after a BO move:
  * `lkpi_unmap_mapping_range` is empty and `zap_vma_ptes` returns 0.
  * The cdev mmap path pins the BO (`nmx_ttm_pin` → `ttm_bo_pin`), and `umap_populate` refills its page array after the pin, so a mapped BO never moves.
* Page zeroing:
  * Pool pages are zeroed through the flushing `pmap_zero_page` (Step84).
  * Fresh pages are bzeroed through the write-back view, then `pmap_page_set_memattr` flushes them, because the attribute changes.
* userptr: not used on that boot (nvmtl.log shows only COPIED).

One thing matters for any further cache theory. This CPU (Ryzen AI 9 HX 370) has no self-snoop (no `ss` in cpuinfo), so a
write-back alias and a UC/WC alias of the same page are not kept coherent by hardware. Every GTT page keeps its
write-back physmap alias (`page+8`). If a dirty line exists there, a clflush or wbinvd at submit (b15, `debug.nmx_wbinvd`)
writes the stale data over the IB, so those knobs cannot tell the causes apart.

What is left:
* (a) The IB really is wrong in memory: an unfound CPU writer through the write-back alias, for example `ttm_move_memcpy` → `kmap_local_page_prot`, or a userland race.
* (b) Memory is right and the GPU fetched something else (GL2 or a stale TLB).

The probe (`scripts/linux-patch-nmx-ibprobe.sh`, source `scripts/nmx-ibprobe/cave.s`):
* Hook: the 7 bytes at 0x17a8c in `amdgpu_coredump`, right after the ringdump printf, jump to a cave over `si_initialize_smc_cac_tables` (0x5aa5a0, SI dpm only, no relocations inside).
* Finding the IB:
  * va = IB1_BASE & 0xffffffffffff; vm = `xa_load(adev->vm_manager.pasids, job->pasid)` under its mutex.
  * mapping = `amdgpu_vm_bo_lookup_mapping(vm, va >> 12)`; bo = `mapping->bo_va->bo`; offset = `mapping->offset + va - mapping->start * 4096`.
  * Limit = min(CP_IB1_CMD_BUFSZ, rest of the mapping, rest of the BO).
* It reads the IB two ways:
  * A: through the BO's cached vmap (bo+0x280), i.e. what memory holds.
  * B: TT BOs only, through each page's write-back alias.
* For each view it:
  * parses PM4 (type 3 with count+2, type 2 and 0xffff1000 as 1 dword, anything else stops);
  * counts the dwords where A ≠ B;
  * prints 16 dwords of A and B around the A parse stop, the first difference and the CP fetch position (cmd − left).
* It only reads: no flush and no new kmap.

Reading the output (`NullMoth ibprobe` lines in the wsdeath log):
* A parses clean to the limit, and the dwords at the fetch position are sane while the CP still choked: the GPU did not fetch what memory holds. This is (b).
* A breaks where the CP broke: the IB is corrupt in memory. This is (a).
  * A ≠ B somewhere means a write-back alias holds different data, so look for the CPU writer.
  * A = B means the corruption was written coherently, so look at userland and the BO's history.

## Step87 — review of Steps 33c–86, the 780M driver and xkpi: force-WC GTT is the leading suspect (2026-11-03, Linux)

### The Step86 probe ran, but its output is unreadable
On hang seq 44981/2 (ws205 died at up=312 s), the probe ran. The two lines right after `ringdump hw rptr` read
`<compose failure [UUID]>`. The uuidtext for NMXGPU (591E7D5A…) holds only `__cstring` (0x6feb20–0x76b3fd), and the
probe's format strings sit in `__text` at 0x5aa5a0, so logd cannot resolve them. There were only two lines (F_HEAD and F_BO),
which means `limit` was 0 and the probe returned before parsing. Any later probe has to print through a `%s` format
that already exists in `__cstring` (0x7001ed `"%s\n"`), with the text built by `scnprintf`. Logs are copied to
`~/ga403-logs/step88/`.

### CP state at every hang (decoded with gc_11_5_0_sh_mask.h)
| hang | IB1 CMD_BUFSZ / left | PFP hdr | ME hdr | CP_BUSY_STAT |
|---|---|---|---|---|
| Step82 | 0x1978 / 0 | c0065800 | c0064900 RELEASE_MEM | 0x48080 |
| Step84 | 0x1420 / 0 | 0 | c0065800 ACQUIRE_MEM | 0x80 |
| Step86 b1 | 0x5008 / 0xac8 | 0 | c0055000 DMA_DATA | 0x8080 |
| Step86 b2 | 0x1f0 / 0 (illegal reg) | 1f810080 | c0016900 SET_CONTEXT_REG | 0x20580 |
| Step88 | 0x2cd0 / 0 | 0 | c0055000 DMA_DATA | 0x8080 |

- `GRBM_STATUS2` 0x5000000c: EA, UTCL2, TCP and CPAXI are all idle, so no memory request is outstanding.
- `CP_BUSY_STAT` 0x8080: only PFP_PARSING and GFX_CONTEXT_BUSY are set. The ME is idle, and the ME header is just its
  last packet. The PFP is the stuck unit, with a header of 0.
- `CPF_STALLED_STAT1` RING_FETCHING_DATA is back-pressure, not a fetch stall.
- The ipdump `GCVM_L2_PROTECTION_FAULT_STATUS` is read at the 11.0 offset (it shows PFLT_CNTL 0x3ffffffc). Trust the
  `vmregs` line instead.

### What the 780M driver (nullarc cbb08dd) does differently
- **System-memory PTE:** every PTE is `0x77 | 4<<48`, i.e. SNOOPED with MTYPE 4 (C_RW_S). This includes RADV "VRAM" BOs.
- **CPU mapping:** write-back only, with no WC or UC alias of system memory.
- **No per-submit flush:** `phxbos_flush` is 0.
- **Power gating:** GFXOFF and gfx PG/CG are never enabled.
- **Background compute:** mediaanalysisd, photoanalysisd and Spotlight are denied Metal, because background ML
  compute hung their GPU within seconds.
- Upstream nullmoth/nvidia-macos-driver moved NMXGPU/xkpi out of the repo at df2cff0. It has no newer coherency commits
  than ours.

### What NMXGPU does (source plus the installed binary)
- **GTT is forced write-combined:** `nmx_gtt_wc` = 1 (0x9255b0, from `amdgpu-ttm-force-wc.patch`, 14d736b). Every TT is
  `ttm_write_combined`, including userptr and SG imports.
  - `amdgpu_ttm_tt_pde_flags` (0x92f10) sets SNOOPED only for cached TTs, so no system page is snooped.
  - The default MTYPE is NC.
- **Every page keeps its write-back alias** (`nmx_kva`). Writers through that alias:
  - `ttm_kmap_iter_tt_map_local` (0x601360) returns the WB view for WC pages without a flush. `ttm_move_memcpy`
    uses it whenever the SDMA move is unavailable, for example after a reset.
  - Userptr/host-imported pages (VK_EXT_external_memory_host from the plugin, `NVMTL_GSUB_HOSTPTR_LIFT=1`) stay WB in
    the process, while the GPU reads them unsnooped.
  - The CPU has no self-snoop, so dirty WB lines are written back over GPU data, and the GPU reads stale DRAM.
- **The detector behind force-WC is racy:** the "STALE fence read" check (`amdgpu_fence.c:117`, binary 0x6e8875) reads the
  WC-mapped `adev->wb`. N→N+1 only means the GPU wrote between the two reads. Step40's "GPU writes are not snooped",
  the premise for force-WC, was never proven with a race-free test.
- **GFXOFF is on:** `amdgpu_pp_feature_mask` = 0xfff7bfff (0x8f6b54) has PP_GFXOFF_MASK set, and 11.5.0 has full PG/CG.
  The trace never examined it.

### Ranked causes
1. **Force-WC GTT**, a departure from upstream (APU GTT is cached + snooped) and from nullarc. It leaves userptr
   pages and the WB alias incoherent with the GPU. The fix is to go back to the upstream coherence model
   (`nmx_gtt_wc` = 0): WB plus SNOOPED, with no alias hazard. Optionally MTYPE C_RW_S, as nullarc uses.
2. **GFXOFF / gfx power gating** under xkpi timing. The PFP stalls with nothing outstanding, and then MES does not answer
   RESET.
3. **A buffer reused while the GPU still reads it** (Step86 b2's garbage header, Step82's permission fault).
   Most of it reduces to cause 1.
4. **Background ML compute**, as on the 780M.
5. MES firmware, stale TLB, IOMMU and TMZ are low (no faults, EA idle, IOMMU off, flush logic as upstream).

## Step88: GTT back on upstream's snooped, write-back model (installed, not yet booted)
The Step87 review found two divergences from upstream and from nullarc. `scripts/linux-patch-nmx-snoopgtt.sh` changes
two `__DATA` defaults in NMXGPU (in `__DATA` the file offset equals the vmaddr):

- **`nmx_gtt_wc` (0x9255b0): 1 → 0.** At 0x92d17/0x92e11, `amdgpu_ttm_tt_create` then gives `ttm_cached`, unless the BO
  set `AMDGPU_GEM_CREATE_CPU_GTT_USWC` (bit 2 of bo+0x258), in which case it gives WC. This matches stock
  `amdgpu_ttm.c`. `amdgpu_ttm_tt_pde_flags` (0x92f10) then sets `AMDGPU_PTE_SNOOPED` for cached TTs, so the GPU snoops
  the CPU caches. The WB `nmx_kva` alias and userptr pages are then coherent with the GPU.
- **`nmx_umap_cache` (0x9264d0): 1 → 2.** In `nmx_umap_insert` (0x6cf420), 2 makes user mmaps follow the pgprot that
  TTM asks for (stock): WB for cached BOs, WC for USWC BOs. The old value 1 forced UC, which would leave a UC user alias
  next to the WB kernel alias of a cached page.
- **`vmap` already follows `prot`** (`linux_page.c` vmap), so a cached BO's kernel map is WB.

Dry run on a copy: only those 8 bytes change. Installed 2026-11-03 10:38Z.
- Backup: `/Library/NullMoth/nmx-snoopgtt-20261103T103804Z`.
- NMXGPU sha256: `3dbc47cc8a857e7725787df63a3e233bd2724de72f40d60efd1350826b5baf00`.
- Relink armed.

The ibprobe hook is still in. It only prints unresolvable lines on a hang. GFXOFF stays on, so only one variable has
changed.

What to read after the boot:
- `sysctl compat.linuxkpi.nmx_wc` should read 0.
- Whether the hang returns.
- Whether "STALE fence read" changes. With a WB `adev->wb`, the clflush re-read is meaningful again.

## Step89: first Step88 boot is stable; WindowServer's CPU goes to contiguous page allocation; three fixes for the next boot (2026-11-03, macOS)

### The Step88 boot
Boot at 17:40 (local). The installed NMXGPU is the Step88 binary (sha256 `3dbc47cc…`, `debug.nmx_umap_cache` = 2). There is
no `compat.linuxkpi.nmx_wc` sysctl, so `nmx_umap_cache` is the check. For 20+ minutes of desktop: WindowServer 205 kept
running, `debug.nmx_timeouts` = 0, no page fault, no ring timeout and no new wsdeath log. The earlier hangs came after 2–7 min.
`STALE fence read` still shows up (36 on sdma0, 4 on mes): about the same rate as before. With a cached, snooped `adev->wb`
this fits the race Step87 described (an SDMA trap that arrives before its fence write is visible). It is harmless,
because fence_process uses the memory value.

PSP: every firmware load worked. AmdCppc's snapshot before NMXGPU started read
`reset=00080800 … ring_lo=1f95c000 ring_hi=00000080 ring_sz=00001000 sol81=00241396 smu_msg=00000019 smu_resp=00000001`.
Bit 19 of S5_RESET_STATUS means software wrote 0x6 to 0xCF9, a warm reboot (the relink's `/sbin/reboot`). The previous
session's KM ring was still programmed. So a warm reset with a live PSP ring does not by itself make the next load fail.
The Step85 explanation now needs a failing boot that shows something else.

### Where WindowServer's CPU goes
WindowServer sat at 50–70 % CPU with a mostly still desktop. `sample` (6 s) and `spindump` (4 s), in
`~/ga403-logs/step89/`:

* 4165 of ~6000 samples on one WindowServer thread are in `__ioctl` ← `drmCommandWriteRead` ← `amdgpu_bo_alloc`
  ← `radv_alloc_memory` ← `nvmtl_alloc_opaque_image_mem` ← `nvmtl_vk_image_create_typed`. NVMTL makes a new image,
  and so a new BO, per surface.
* Kernel side (spindump, symbolised with atos against NMXGPU and `/System/Library/Kernels/kernel`):
  `amdgpu_gem_create_ioctl` → `ttm_pool_alloc` → `linux_alloc_pages` → `vm_page_alloc_noobj_contig` →
  `backing_alloc` → `nmx_xnu_mem_alloc` → `IOBufferMemoryDescriptor::inTaskWithPhysicalMask` →
  `IOKernelAllocateWithPhysicalRestrict` → **`cpm_allocate`** (313 of 316 samples), partly blocked in `thread_block`.
* Why: `ttm_pool_alloc` tries order min(fls(pages)-1, 10) first. On xkpi every order > 0 is a physically contiguous run
  of its own (`nmx_page.c`, BK_RUN through `cpm_allocate`), and it goes back to xnu when the BO is freed. Upstream TTM keeps
  no pool of *cached* pages on x86 (`ttm_pool_select_type` returns NULL), so since Step88 made GTT cached, every BO pays
  this cost. Before Step88 the WC pool recycled pages, so Step88 brought this regression in with the coherency fix.
* Smaller items: `nvmtl_vk_image_write` (CPU uploads, 239 samples), `IOSurfaceClientRelease` (134), fence waits (~130).
* NMXAccel's paced K6 copy: per frame about 4.8 ms of copy and 3.4 ms of `pause` spin waiting for the scan
  (`debug.nmxaccel_beam_copy_us` / `_wait_us` over 7147 frames). It runs on the NMXDisplayPipe work loop. The copy is
  close to memory bandwidth (20 MB read + 20 MB written, l10r→XRGB). The spin wastes CPU.

### Fixes (installed together, take effect on the next boot)
`scripts/macos-patch-nmx-step89.sh [CI NMXAccel]` runs on macOS as root. It backs up to `/Library/NullMoth/nmx-step89-*`,
patches NMXGPU, installs NMXAccel, relinks the AuxKC with kmutil, and checks that the new collection holds the patched
bytes and both UUIDs. `--undo` puts the backup back.

1. **TTM order 0** (NMXGPU 0x5fd9b1): `cmpl $0xa,%eax; movl $0xa,%r12d` → `$0`. Every TT page is order 0, which
   `linux_alloc_pages` serves from `vm_page_alloc_noobj`: xkpi's 2 MB chunk free list (non-contiguous
   `inTaskWithOptions` chunks, a spinlocked pop). No more `cpm_allocate`. The GPU uses 4 KB PTEs for GTT. Chunks are
   never handed back to xnu (that was already true), so wired memory stays at its high-water mark.
2. **ibprobe v2** (`scripts/nmx-ibprobe/cave.s`): every line goes through `snprintf` (the `jmp _snprintf` tail call at
   0x8789e) into a stack buffer, then `printf("%s\n")` with NMXGPU's own format at 0x7001ed. logd can then resolve the
   line, unlike the Step86 `<compose failure>`. The head lines also print pasid, vm, mapping and bo, which shows
   which lookup left `limit` = 0 last time. `CP_IB1_CMD_BUFSZ` = 0x20c0 (seg 1) was checked against NMXGPU's own
   ipdump table. The cave now builds on macOS: clang emits ELF, and `elflink.py` places it. It reproduces the Step86
   `cave.bin` byte for byte.
3. **NMXAccel beam waits sleep** (nvidia-macos-driver `ci/nmxaccel` 414a235, CI run 41623695878, NMXAccel
   `11c9a392…`, UUID 0EA8C295…):
   * Waits `IODelay` until ~150 µs before the target line, then spin. The line period is measured from earlier copies.
     A wait never sleeps across a refresh, so `line()` still sees every wrap.
   * The copy starts when the scan is at h + 8 + 16 − copy length, so only the last band waits.
   * The beam log line now also prints ns/line.

| kext | before | after |
|---|---|---|
| NMXGPU | 3dbc47cc… (Step88) | 47eec16d… |
| NMXAccel | 99a11fb3… (CI 41586784851) | 11c9a392… (CI 41623695878) |

Installed 2026-11-03 11:01Z from macOS. Backup: `/Library/NullMoth/nmx-step89-20261103T110111Z`. The AuxKC was relinked in
place, so no relink boot is needed: the next normal reboot loads it.

What to read after the boot:
- `sample`: `amdgpu_bo_alloc` should be gone from the top of WindowServer's stacks, and WindowServer's %CPU should drop.
- `debug.nmxaccel_beam_wait_us` keeps counting (it is wall time). Check `top`: kernel_task and WindowServer CPU
  during animation.
- `debug.nmxaccel_beam_lapped` should stay near 0, and there should be no tearing.
- If a GFX hang comes back: `NullMoth ibprobe` lines in the wsdeath log, now readable.

## Step90: the Step89 boot crash-loops WindowServer; multi-range WC/UC mappings, split per contiguous range (2026-11-03, Linux)

### The Step89 boot
Black screen, WindowServer crash loop (wsdeath 20261103T1104*–1107*). Every WindowServer instance logs
`NVMTL: vk: keep witness 1 NOT seen after 1000 ms (slot holds 0)`, then `completion witness missing; disabling
backend`, then `G13 surface-in: upload FAILED`. No ring timeout follows the first job. Later:
`[gfxhub] page fault … vmid:3 pasid:32769 … address 0x0 … SQC (data) … PERMISSION_FAULTS 0x3` and at 18:04:45
`ring gfx_0.0.0 timeout, but soft recovered`. The ibsnapshot holds valid PM4: SET_SH_REG loads the user SGPR pointer
0x800100016000, a RADV 32-bit-range upload BO (USWC → WC GTT). So the GPU read the descriptors as zero, and the CPU
read the witness as zero. In the Step88 logs the witness was missing only after a GPU reset.

Ruled out for Step89: order-0 zeroing (`linux_alloc_pages` maps M_ZERO to VM_ALLOC_ZERO, `vm_page_alloc_noobj` bzeroes,
pat_mode WB), the TTM order code, `amdgpu_vm_map_gart` and the SDMA PTE copy (upstream), the Step84 zeroflush, the
ibprobe cave overwriting live code, dma mapping (identity), and kernel vmaps of cached multi-range BOs (IB tests and
kernel jobs work).

### Root cause: physical page attributes in xnu
Order 0 makes every multi-page BO physically discontiguous: `vm_page_alloc_noobj` pops 4 KB pages in descending order,
so even a fresh TT has no adjacent pages. `nmx_xnu_map_user` (mmap ioctl) and `nmx_xnu_map_pages` (vmap) put the page
list in ONE `kIOMemoryTypePhysical64` descriptor and map it with `cache_option(cache)`. xnu (IOMemoryDescriptor.cpp,
vm_object.c, vm_resident.c, device_vm.c, i386 pmap_common.c) handles that descriptor differently depending on the
range count:
- One range: `dp.pagerContig`, `DEVICE_PAGER_CONTIGUOUS`, the object is `phys_contiguous`. `memoryReferenceMap` sets the
  object's wimg (MAP_MEM_ONLY on an empty memq: only `object->wimg_bits`). The fault block-maps the entry:
  `pmap_map_block` → `pmap_enter(…, attr = object wimg)`. The cache mode goes into the PTE; the page itself is not
  touched. This is what every Step88 mapping was (order 10 chunks).
- Several ranges: a non-contiguous device pager. `populateDevicePager` → `device_pager_populate_object` →
  `vm_object_populate_with_private` inserts one private vm_page per page. `vm_page_insert_internal` then runs
  `PMAP_SET_CACHE_ATTR` → `pmap_set_cache_attributes(phys page, object wimg)`, which stores the mode in
  `pmap_phys_attributes[page]` and rewrites the cache bits of EVERY existing PTE of that page
  (`pmap_update_cache_attributes_locked` walks the pv list). The fault path enters PTEs with flags 0, so it takes
  whatever the physical attribute holds. When such an object dies, `vm_page_remove` (`set_cache_attr`) resets the
  page to 0 = write-back, again across all of its mappings.

So with order 0, whichever mapping of a WC page was made or torn down last decides the mode of all its mappings. A
`vunmap`, a second process's mapping of a shared surface going away, or a write-back map anywhere turns RADV's WC
mapping write-back. This CPU has no self-snoop, so CPU stores sit in the cache while the GPU reads memory unsnooped
(zero descriptors, SQC fault at VA 0), and CPU reads hit stale lines while the GPU wrote memory (witness 0).
Setting the cache mode on the descriptor itself does not help: the per-page insert still writes the physical attribute.

### Fix: one contiguous mapping per range for WC/UC (`scripts/nmx-wcsplit/cave.s`)
A cave at 0x5aac00 (after the Step89 ibprobe cave, inside `si_initialize_smc_cac_tables`, SI dpm only, no relocations)
replaces `nmx_xnu_map_user`, `nmx_xnu_unmap_user`, `nmx_xnu_map_pages` and `nmx_xnu_unmap` (a `jmp` at each entry).
- Single range, or the default cache (cached GTT, which is most BOs since Step88): unchanged, one mapping.
- WC/UC/WT with more than one range: reserve the whole size, then map one single-range descriptor per contiguous range
  over it with `kIOMapOverwrite`. Every piece is block-mapped with its mode, and no vm_page of the BO exists, so the
  physical attributes are never written. The handle is `(split *) | 1` = {IOFree size, reservation map, count,
  maps[count]}. Release drops the reservation first (that deallocates the range; overwrite maps never deallocate),
  then the pieces.
- Reservation, user task: a read-only map of one NMXGPU text page repeated, faulted lazily (only public bytes if a
  thread touches it before the overwrite). Kernel: IOKit prefaults kernel maps, and a repeated page would add a pv
  entry per page while every insert walks that list with TLB shootdowns (O(n²)). The kernel reservation is therefore
  one contiguous read-only uncached range of the size, starting at the first range. It creates no vm_page and changes
  no attribute; UC is never read speculatively; the overwrite maps replace it before anything uses it.
- External calls go through the relocated call sites of the replaced bodies, each followed by a `ret` (stubs at
  0x6e2550 IOMalloc, 0x6e25d8 withAddressRanges, 0x6e25e6 IOFree, 0x6e2644 current_task, 0x6e265f
  createMappingInTask, 0x6e26ab task_reference, 0x6e2727 get_task_map, 0x6e2737 vm_deallocate, 0x6e2740
  task_deallocate). The cave calls them with rsp = 8 mod 16, so the callee sees a normal frame. No Mach-O tables
  change.
- `scripts/nmx-wcsplit/emu_test.py` runs the patched binary under unicorn with fake IOKit calls. 18 cases: split and
  single mappings for user and kernel, fixed and anywhere, reservation first on release, IOFree sizes, no leaked
  descriptor/map/allocation, failure of every createMapping, stack alignment, callee-saved registers.

The cost is one descriptor and one map per contiguous range of a WC/UC BO, paid once per mmap/vmap. Cached BOs (the
WindowServer CPU of Step89) are not affected.

| | sha256 |
|---|---|
| NMXGPU before (Step89) | 47eec16d… |
| NMXGPU after | c9bf8730c975d1c1aa5974b316329955eb0cdce7f2cc1995c09bd8796b5bf693 |
| cave.bin | 087a7687d33062872db3d3df01ac67a447c9b1a7b59b3a7a6c3837ce98060736 |

Installed 2026-11-03 11:44Z from Linux (`pkexec scripts/linux-patch-nmx-step90.sh`). Backup:
`/Library/NullMoth/nmx-step90-20261103T114414Z` (NMXGPU.kext + AuxKC). Relink armed: the first boot relinks the AuxKC
and reboots by itself.

What to read after the boot:
- wsdeath: `keep witness … NOT seen` and `upload FAILED` should be gone; no `[gfxhub] page fault … address 0x0`.
- WindowServer %CPU (Step89's goal) should stay low. Watch mmap latency if big WC surfaces show up in `sample`.

## Step91: the Step90 boot works; WindowServer's CPU is now readback out of uncached memory: Step88's nmx_umap_cache=2 means WC, and NVMTL picks the WC type (2026-11-03, macOS)

### The Step90 boot
NMXGPU `c9bf8730` (Step90) and NMXAccel `11c9a392` (Step89) are loaded. The desktop works. No new wsdeath log, and
`debug.nmx_timeouts` = 0. WindowServer still runs at ~100 % CPU. `sample` (`~/ga403-logs/step91/`):
* The Step89 cost is gone. GEM_CREATE ioctls drop from 4165 samples to ~130 for all ioctls, so TTM order 0 works.
* The new hot spot is 4710 of ~6000 samples in `_platform_memmove` ← `nvmtl_vk_image_read` (the "copied out" half of
  NVMTL's private surface images). The spindump kernel frames under it are only timer interrupts, so it is not
  page faults: the copy itself is slow.

`tools/890m/metal-readback.swift`, run as `nvmtltest`, measures it: the GPU clears a shared 2880×1800 rgba8 texture,
`getBytes` reads all of it, and `replaceRegion` writes it back, with every pixel checked. **getBytes took 190 ms
(108 MB/s)**, while replaceRegion took 2–3 ms. That is the read speed of uncached/WC memory.

### Two causes, both needed for the fix
1. **NVMTL asks for a WC type for every host-visible buffer.** The log line is `vk: buffers (host_visible=1) take memory type 2
   flags 0x6`. `nvmtl_vk_buffer_create` (0x3dd5) and `nvmtl_vk_heap_create` (0x1fc89) compute
   `want = host_visible * 5 + 1` and look for an exact match on `(flags & (want ^ 1)) == want`. With want = 0x6, CACHED
   is not compared, so the match is RADV's USWC GTT type.
2. **Step88's `nmx_umap_cache = 2` forces WC, not "follow pgprot".** In the fork source (`nmx_umap_insert`):
   0 = the driver's own attribute, 1 = UC, 2 = WC. The disassembly agrees: 1 → memattr 0, 2 → memattr 1, anything
   else → from the pgprot. So since Step88 every user mmap of a GEM BO has been WC, including cached GTT. Patching NVMTL
   alone still gave 190 ms, with type 5 flags 0xe. Before Step90 the multi-range WC maps were silently write-back
   (Step90's page-attribute stomping), which hid this.

### Fixes
* `scripts/macos-nvmtl-cached-host-patch.sh` (Step91, `--undo`): both sites now compute `want = host_visible * 13 + 1`
  = 0xE (HOST_VISIBLE | HOST_COHERENT | HOST_CACHED). The changes are `43 8d 04 bf` → `41 6b c7 0d` and `8d 04 80` → `6b c0 0d`,
  each followed by the existing `incl %eax`. The bundle is re-signed ad hoc and swapped in by rename, so the running
  WindowServer keeps its mapped pages. Installed 13:57Z: NVMTLDriver `f7b81401…` (binary `3e3f9d92…`), backup
  `/Library/NullMoth/nvmtl-cachedhost-20261103T135713Z`. New processes log `take memory type 5 flags 0xe`.
* `debug.nmx_umap_cache=0` set live. `scripts/macos-patch-nmx-step91.sh` (`--undo`) makes it the default
  (`__DATA` 0x9264d0, 2 → 0) and relinks the AuxKC from macOS. NMXGPU `b13ca867…`, backup
  `/Library/NullMoth/nmx-step91-20261103T140041Z`.

### Result (new processes, this boot)
| test | before | after |
|---|---|---|
| metal-readback getBytes 20 MB | 190 ms (108 MB/s) | **1.9 ms median (~11 GB/s)**, 40 iterations, 0 wrong pixels |
| replaceRegion 20 MB | 2–3 ms | ~2 ms |
| metal-render / metal-compute / metal-iosurface | CORRECT | CORRECT |

Coherence: a cached GTT page is write-back on the CPU and snooped by the GPU (Step88), so GPU writes followed by CPU
reads are correct. The 40-iteration check covers that.

WindowServer still runs the old NVMTL and keeps its old mappings until it restarts, so it gets the gain on the next boot.

What to read after the boot:
- `sysctl debug.nmx_umap_cache` = 0. WindowServer's log says `take memory type 5 flags 0xe`.
- WindowServer %CPU. `sample` should show no `memmove` ← `nvmtl_vk_image_read` at the top.
- wsdeath: no `keep witness … NOT seen`, no `upload FAILED`, no `[gfxhub] page fault`.

## Step92: the Step91 boot is smoother; WindowServer's CPU is now IOSurface copies, because NMXGPU has no userptr (2026-11-03, macOS)

### Step91 boot (21:05 local)
- `debug.nmx_umap_cache` = 0. WindowServer logs `vk: buffers (host_visible=1) take memory type 5 flags 0xe heap 0`.
  The owner reports the desktop is much less laggy.
- WindowServer is at ~72% CPU (top, 6 × 2 s), down from 100%+. kernel_task is at ~25%: NMXDisplayPipe (the K6
  copy) 0.43 s per 8 s, and the four AppleUSBXHCIPCI interrupt threads ~1.1 s per 8 s (MMIO reads in the XHCI
  handler, not the GPU; noted only).
- `sample` WindowServer (8 s): the top work is `-[NVMTLTexture nvmtlSurfaceIn]` → `nvmtl_vk_image_write`
  (~1100 of 6246 samples on the compositing thread) and `nvmtlSurfaceOut` → `nvmtl_vk_image_read` → memmove
  (~600). The rest is waiting (`drmSyncobjWait`, mach_msg). The 190 ms WC readbacks are gone.

### Cause
Every IOSurface goes through a private VkImage: NVMTL copies the surface in when its seed changes and copies it
out after the GPU writes it. The zero-copy path (from the 780M port, `nvmtl_surface_image_create`: "-> its own pages
(host import, no copies)") imports the surface's allocation with VK_EXT_external_memory_host. On the 890M every
import fails: `vk: vkAllocateMemory refused the imported host pointer 0x183150000 (20828160 bytes, memory type 5)`.

RADV's import is `DRM_AMDGPU_GEM_USERPTR`. The NMXGPU build has no `CONFIG_HMM_MIRROR` / `CONFIG_DRM_AMDGPU_USERPTR`:
`amdgpu_hmm_register` is the stub that logs `HMM_MIRROR kernel config option is not enabled` (seen at 21:05:58) and
returns -ENODEV. In the binary the compiler kept only `create BO; set_userptr; -ENODEV` in
`amdgpu_gem_userptr_ioctl` (0x5a790). The submit path has stubs that cannot succeed either:
- `amdgpu_cs_parser_bos`: any userptr entry → `.cold.1` → `-EPERM`.
- `amdgpu_cs_submit`: `!amdgpu_ttm_tt_get_user_pages_done()` → `-EAGAIN`.

xkpi already pins user pages (`lkpi_get_user_pages` → `nmx_user_pages_pin`, an IOMemoryDescriptor wiring on the
task, dropped by the last `put_page`). amdgpu just never called it.

### Fix: userptr without HMM (`scripts/nmx-userptr`, `scripts/macos-patch-nmx-step92.sh`)
The pages are pinned once when the BO is made and held for its lifetime. There is no MMU notifier, so the submit path
never re-fetches. NVMTL keeps the surface alive while its texture lives, so the pinned pages are the surface's.

The cave is C, `cave.c`, built with clang for ELF and placed at 0x5ab300 by `elflink2.py`: .text + .rodata, PC32 only,
1080 bytes. It sits in the dead SI dpm code, after the Step90 cave. Its entries are +0, +8 and +16.

| site | was | now |
|---|---|---|
| ioctl 0x5a7c8 | `mov r14,rsi; add rdi,-0x10` | jmp to +0: the same two instructions, plus filp kept at `[rbp-0x60]` (the frame's free slot at rsp) |
| ioctl 0x5a86b | `mov eax,-ENODEV` (inlined hmm stub) | jmp to +8: `userptr_tail(tbo, args, filp)`, then back to 0x5a893 (the object put) |
| cs_parser_bos 0x1390c | `jne .cold.1` (userptr → -EPERM) | nop6 |
| cs_parser_bos 0x13bb4 | `jne` usermm ≠ current->mm → -EPERM | nop6 |
| cs_submit 0x14842 | `jne` → -EAGAIN for userptr lists | nop6 |
| unpopulate 0x943e9 | inlined `set_user_pages(ttm, NULL)` | `call +16` (`userptr_release`: put each page, then NULL) |

`userptr_tail` does the following:
- `lkpi_get_user_pages(addr, num_pages, write unless READONLY, ttm->pages)`. It pins even without VALIDATE, because
  nothing else fills the array.
- With VALIDATE (RADV always sets it): `amdgpu_bo_reserve`, placement GTT, `ttm_bo_validate`, unreserve.
- `drm_gem_handle_create`, then `args->handle`.
- On a failure before the BO is bound, it puts the pages itself.
- It logs up to 24 lines `NMX userptr: pinned/... FAILED addr .. size .. -> n` (the budget is the now-unused
  `amdgpu_hmm_register.__print_once` byte).

The TT is cached (Step88 `nmx_gtt_wc=0`), so the GART PTEs are snooped and the pages stay coherent with
WindowServer's write-back mapping. Binding uses the existing `amdgpu_ttm_tt_pin_userptr`, which builds an sg table
from `ttm->pages`.

Installed 14:21Z from macOS: NMXGPU `01ecc7bc…` (from Step91 `b13ca867…`), AuxKC relinked, and all three KC probes
present. Backup: `/Library/NullMoth/nmx-step92-20261103T142109Z`. Undo:
- on macOS: `sudo scripts/macos-patch-nmx-step92.sh --undo`;
- from Linux: `pkexec scripts/linux-undo-nmx-step92.sh` (restores the kext and arms nmx-relink).

What to read after the boot:
- `log show --predicate 'eventMessage CONTAINS "NMX userptr"'`: `pinned` lines, and no `FAILED`.
- WindowServer: `-> its own pages (host import, no copies)` and `imported the caller's pages as device memory`.
  There should be no new `refused the imported host pointer`.
- WindowServer %CPU and a `sample`: `nvmtlSurfaceIn`/`nvmtl_vk_image_write` and `nvmtl_vk_image_read` should be gone
  or rare.
- No `[gfxhub] page fault`, no ring timeout, no wsdeath. Content must be right: window contents update, with no
  stale or garbled tiles. A stale page would show as a window that does not repaint.

## Step93: IB prepare per submit made opt-in; NVMTL from source with the cached memtype and a surface keep that holds pools (2026-11-03, macOS)

### Step92 boot
Userptr works: WindowServer's IOSurfaces render in place ("its own pages"), and `nvmtlSurfaceIn/Out` copies are gone from
`sample`. WindowServer dropped from ~72 % to ~50 % CPU, and the owner reports a smoother desktop. What is left in the samples:

1. **Import/free churn.** `nvmtl_surface_keep` evicted every backing whose IOSurface retain count was ≤ 1 at each insert.
   Clients' rotating surface pools were therefore re-imported (userptr BO + image) every frame.
2. **Per-submit IB prepare.** `amdgpu_cs_patch_jobs` (fork patch `amdgpu-zz-ibprepare-b15`, inlined) does this for every GFX IB:
   find_mapping, `amdgpu_bo_kmap` (vmap → `IOMemoryDescriptor::createMappingInTask`), clflush of the IB, mfence, a
   96-dword snapshot for ibprobe, and a `printf("NullMoth ibprep b15: ...")`. That is ~83 log lines/s on an idle desktop.
   The same kmap path was where the Step65/Step90 unlock-of-unlocked panic surfaced.
3. Some pins fail with -14 (EFAULT from `prepare()`). This step does not address it.
4. Not GPU: syncobj waits (mostly sleeping), the NMXAccel K6 copy (0.59 s per 8 s), and XHCI interrupt threads.

### Why b15 is no longer needed
b15 cured IB corruption that had two sources, and both are fixed:
- dirty write-back aliases of WC pool pages (Step84: `pmap_zero_page` flushes);
- un-snooped GTT (Step88: cached TTs are snooped; USWC IBs are WC with no dirty alias).

b15 also covered only outer IBs.

### Fix (NMXGPU binary, `scripts/nmx-ibprep/step93_patch.py`, 40 bytes)
- **0x13f7a** `je 0x14140` (the GFX-ring branch into the prepare loop) becomes `jmp 0x5ab740`. The cave at 0x5ab740 sits after the Step92
  cave, still in `si_initialize_smc_cac_tables`, where there are no relocations. The cave does three things:
  - if the ring is not GFX, it resumes at 0x13f80;
  - if `test byte [nmx_wbinvd_before_submit], 2` (0x9ba204, `__common`, sysctl `debug.nmx_wbinvd`) is clear, it resumes at 0x13f80;
  - otherwise it jumps to 0x14140.
- **0x14357** `cmp dword [rax],0` → `test byte [rax],1`. Bit 0 keeps the whole-cache invalidate after the loop. Before,
  any non-zero value did it.
- With the default `debug.nmx_wbinvd` = 0, no prepare runs. `sysctl -w debug.nmx_wbinvd=2` turns b15 back on at run time for a
  hang hunt, with no reboot. The ibprobe snapshot is only taken in that mode.
- No relocations in any patched range (`otool -r` scan). The dry run on a copy changed exactly 40 bytes.

Installed with `scripts/macos-patch-nmx-step93.sh` (`--undo`; from Linux `scripts/linux-undo-nmx-step93.sh`):
- NMXGPU sha256 `89969711…5f66d6`;
- backup `/Library/NullMoth/nmx-step93-20261103T143817Z`;
- AuxKC relinked in place, with all 3 probes present.

### NVMTL plugin from source (fork `ci/amd-plugin-890m` 76c1614)
The plugin is built from the fork's source, not the Step91 binary patch:
- `memtype()` prefers HOST_CACHED, non-DEVICE_LOCAL for host-visible memory. This is Step91 in source; `NVMTL_HOST_WC=1` opts out.
- `nvmtl_surface_keep` keeps unheld host-import backings for `NVMTL_KEEP_MS` (3000 ms) after their last use, capped at
  `NVMTL_KEEP_IDLE` (48) idle entries, oldest evicted first. Cache hits touch the entry and log `surface keep: hit #N`.

Installed with `scripts/macos-nvmtl-plugin-install.sh` (`--undo`):
- the bundle is copied, ad-hoc signed and swapped in by rename;
- binary `b95c708c…`;
- backup `/Library/NullMoth/nvmtl-plugin-20261103T143758Z` (the Step91 binary `f7b81401…`).

Tests on the new plugin (run as `/tmp/nvd/bin/nvmtltest`) all came back CORRECT:
- metal-render;
- metal-compute (1M values);
- metal-iosurface (GPU and CPU pixel);
- metal-readback (getBytes ~2.4 ms after the first iteration, 0 wrong pixels).

WindowServer loads the new plugin on its next start.

What to read after the boot:
- WindowServer CPU (`top -l 2 -stats pid,command,cpu`) and a `sample` of it, using `tools/890m/sample-chains.py` to find who
  still allocates (`nvmtl_surface_image_create`, `amdgpu_bo_alloc`);
- `log show --last 1m | grep -c "ibprep b15"` should be 0;
- `surface keep: hit` lines in WindowServer's log;
- `debug.nmx_timeouts` stays 0, with no ring timeout and no IB-corruption hang.

New tools:
- `tools/890m/sample-chains.py` prints the ancestor chains of `sample` call-graph nodes that match a regex.
- `tools/890m/nmx-disasm.py` is a capstone disassembler with NMXGPU symbol names.

## Step94: trace of the Step93 boot. WindowServer waits for GPU completion every frame; the K6 CPU copy is still the scanout path (2026-11-03, macOS)

### Step93 boot
- NMXGPU `89969711` and the source-built NVMTL are both live.
- 0 `ibprep b15` lines.
- `surface keep: hit` lines from WindowServer ("own pages").
- `debug.nmx_timeouts` = 0.
- WindowServer is at ~35 % CPU at 3 min uptime (Step92: ~50 %), even with mds_stores and softwareupdated busy after boot.

Logs are in `~/ga403-logs/step93/`: `ws.sample` (8 s) and `spin.txt` (6 s).

### Where the frame time goes (55 fps on the 120 Hz panel)
- **WindowServer main thread** (2.1 s CPU in 6 s). 2051 of 6457 samples are in
  `CompositorMetal::composite` → `MetalContext::Flush` → `-[NVMTLCommandBuffer commitAndWaitUntilSubmitted]` →
  `waitUntilCompleted`.
  - NVMTL deliberately waits for **completion** in WindowServer. The source comment says the display-pipe swap that follows can't be ordered after a GPU
    fence.
  - That is ~4.6 ms per frame of blocked compositor on top of ~6 ms of CPU work, more than the 8.3 ms budget at 120 Hz.
  - The `nvmtl.execution` pump threads show the same time inside `drmSyncobjWait`. The ioctls in the sample are these waits, not CPU.
- **GPU** (`tools/890m/metal-latency.swift`, run as nvmtltest):

  | measurement | wall time | GPU time |
  |---|---|---|
  | tiny job round trip | 0.15 ms | — |
  | 2880×1800 bgr10a2 sample+draw, private VRAM | 0.50 ms | 0.33 ms |
  | same, IOSurface → IOSurface (host-imported system memory) | 1.29 ms | 1.02 ms |
  | IOSurface → private | 0.70 ms | 0.52 ms |
  | private → IOSurface | 1.10 ms | 0.83 ms |

  - The fence path is fast.
  - A side probe (a tiny job every 3 ms, 800 runs) waited > 1 ms in 28 % of runs, up to 5.5 ms. So WindowServer's composites are several
    full-screen passes (layers and blurs on system-memory IOSurfaces), ~4–5 ms of real GPU work.
- **kernel_task** (1.68 s CPU in 6 s):
  - NMXDisplayPipe takes 0.49 s. That is the K6 copy, 4.7 ms per frame by `debug.nmxaccel_beam_copy_us`, plus 3.4 ms of (now sleeping) beam wait.
  - The four AppleUSBXHCIPCI threads take 0.18–0.23 s each, ~13 % in all. Not GPU.

### Next (the frame path, not more CPU trimming)
1. **Swap ordered after the fence in the kernel.**
   - NVMTL returns from `commitAndWaitUntilSubmitted` once the work is submitted.
   - NMXAccel's `performTransaction` waits (sleeping) for that surface's GPU work before the K6 copy or flip.
   - This frees the WindowServer main thread for ~4.6 ms per frame.
2. **Real flips instead of the K6 CPU copy.**
   - DCN scans out a GPU-written buffer, with the surface address latched at vblank.
   - There is an existing `debug.nvaccel_iop_flip` path from the NVIDIA build to start from.
   - This removes 4.7 ms of CPU copy and the beam wait per frame.

## Step95: WindowServer killed by intermittent CS rejections; CS trace and the fence-ordered swap installed for one boot (2026-11-03, macOS)

### What happened (22:05–22:10)
- I ran the IOSurface tests (metal-fence, metal-iosurface) back to back on the live desktop. About a third of the runs failed with
  RADV `The CS has been rejected (-1)`, and the rate went up over time.
  - Only tests with IOSurfaces failed, i.e. submits that carry userptr BOs. metal-render and metal-compute passed every run.
  - Wired memory did not grow from run to run.
- At 22:08:00 WindowServer 205 got `vk: queue submit -> -4; disabling backend` (RADV turns the rejected CS into device lost).
  - `commandBuffer` then returned nil, and SkyLight recursed `RenderEncoder` ↔ `SetScissor` until the stack overflowed (SIGSEGV, stack guard).
  - Each new WindowServer hit `submit -> -4` again within seconds. The kernel state stayed bad until a forced reboot.
- Rule from now on: no back-to-back GPU test loops on the live desktop. Run one test at a time and stop at the first rejection.

### What the -1 is
- xkpi passes the Linux errno through unchanged (`linux_file_ioctl` negates the return; `nmx_drm_node_ioctl`'s -1 only means
  "not ours"). So this is a real -EPERM.
- The upstream `usermm != current->mm` check in `amdgpu_cs_parser_bos` was already removed (Step92, 0x13bb4), and the HMM
  page-fetch stub (`parser_bos.cold.1`, the one direct `push -1`) is only reachable through the jump Step92 nop'd at 0x1390c.
- `amdgpu_ttm_backend_bind`'s "failed to pin userptr" would have logged, and it never did.
- So the source is outside the code that can be read statically. The NMX userptr log was silent too: its 24-line budget had gone on successful pins.

### Step95a: CS trace (NMXGPU binary, `scripts/nmx-cstrace`)
- 31 call sites go through thunks in a C cave at 0x5ab760..0x5abdf0 (dead SI dpm code, after the Step93 cave):
  - every stage of `amdgpu_cs_ioctl`: pass1 parts, `ib_get`, `parser_bos`, `patch_jobs`, `vm_handling`, `sync_rings`, `submit`;
  - the calls inside `parser_bos`: list get/create, lock_pd, prepare_obj ×2, the userptr `ttm_bo_validate`, vm_validate, bo_validate, alloc_gart;
  - the calls inside `vm_handling`: clear_freed, bo_update ×3, handle_moved, update_pdes;
  - the calls inside `sync_rings`: wait_prev_fence, sync_resv;
  - the Step92 cave's `userptr_tail`.
- A failing callee logs `NMX cs-trace: <site> -> <errno>`, with the innermost site first. -EDEADLK, -ERESTARTSYS and -EINTR are skipped.
- `linux_file_ioctl`'s return (0x6b5ccc) logs every -EPERM as `ioctl -> -1`.
- Budgets live in `ci_init_smc_table.__ratelimited` (0x926fe0, CI dpm only): 96 lines for EPERM and 48 for other errors.
- Checks: every site's target and site id were checked in the patched copy, no relocations fall in the patched ranges, and no site passes stack arguments.

### Step95b: fence-ordered swap
- NMXAccel `ci/nmxaccel-fence` a24692f (CI run 41659964136, `1b9c7b9f…`). `performTransaction` sleeps in 100 µs `IODelay`
  steps, capped at 100 ms, until the surface's `NMXFenceDone` ≥ `NMXFencePending`. It reads them with `IOSurface::copyValue`, the kernel
  side of `IOSurfaceSetValue`.
  - Sysctls: `debug.nmxaccel_fence_wait` (kill switch) and `debug.nmxaccel_fence_{frames,waited,wait_us,timeouts}`.
- NVMTL (fork f3563a8, installed `1706da17…`) marks each surface WindowServer writes:
  - pending at commit, done after completion and surface publish;
  - `IOSurfaceSetValue` costs 5.5 µs and leaves the seed alone;
  - commitAndWaitUntilSubmitted then waits only for submission;
  - the sysctl is read per commit, so `sysctl -w debug.nmxaccel_fence_wait=0` brings the old wait back at once.
- `tools/890m/metal-fence.swift` (NVMTL_NMX_FENCE=2): 40/40 frames have pending set at commit, done == pending after the wait, and correct pixels.

Installed with `scripts/macos-install-step95.sh <CI NMXAccel.kext>` (`--undo`; from Linux `scripts/linux-undo-step95.sh`):
- backup `/Library/NullMoth/step95-bk-20261103T152156Z`;
- NMXGPU `4e856bbb…`, NMXAccel `1b9c7b9f…`;
- AuxKC relinked, with all probes present.

### After the boot
1. `sysctl debug.nmxaccel_fence_frames debug.nmxaccel_fence_waited debug.nmxaccel_fence_wait_us debug.nmxaccel_fence_timeouts`.
   WindowServer's log should say `fence-ordered swap ON`.
2. Check WindowServer CPU and the main thread's `waitUntilCompleted` share in `sample`, tearing and stale frames, and the fps headroom.
3. `log show --predicate 'sender == "NMXGPU"' | grep cs-trace`, from normal use first.
   - If it is empty, run metal-iosurface **once at a time** and stop at the first rejection.

## Step96 (2026-11-03): Step95 boot results, commit-thread submit-ahead, read-only userptr retry

Step95 boot (NMXGPU 4e856bbb, NMXAccel 1b9c7b9f, NVMTL 1706da17), first ~10 minutes of normal use:

- **Fence-ordered swap works.** `debug.nmxaccel_fence_frames` 2586, `_waited` 2503, `_wait_us` 1769768 (about
  0.7 ms per frame, IODelay spin in performTransaction), `_timeouts` 0. WindowServer logged
  "fence-ordered swap ON". No tearing or stale frames seen.
- **No CS rejections.** The ioctl -EPERM hook logged nothing. The only trace hits were
  `userptr_tail -> -14` (37 times). That is the GEM_USERPTR import, not CS: our Step92 pin
  (`get_user_pages` -> `IOMemoryDescriptor::prepare`) failed with -EFAULT.
- **Why the pin fails:** `vmmap -v` of WindowServer at the failed addresses shows read-only mappings. Most are
  client CoreAnimation surfaces mapped `r--/r--` SM=SHM, and one is a read-only mapped file (DarkAqua.car).
  libdrm always asks for a writable userptr, so wiring for write fails. Those surfaces fall back to CPU copies.
- **WindowServer main thread** (sample, 6 s): 723 of 3892 samples were still blocked, now in
  `-[NVMTLCommandBuffer waitUntilScheduled]` called by `CoreDisplay::DisplayPipe::RunFullDisplayPipe`. The
  plugin's single execution worker runs the submit-ahead pass only between blocking `WaitForFences`
  (309 samples). So a buffer committed while the worker waited for the previous one was scheduled only once that
  one completed. The fence swap had moved the wait, not removed it.

Fixes:

1. **NVMTL 899c64f** (fork): the ahead pass also runs in `nvmtl_pump_buffers` on the committing thread. A part
   the worker submits itself is held (`_syncHold`), so the ahead pass never submits it twice or out of order.
   `vkQueueSubmit` was already serialized by `nvmtl_submit_mutex`. `NVMTL_COMMIT_AHEAD=0` turns it off.
   `tools/890m/metal-sched.swift` commits a ~1.7 ms buffer A, then a small buffer B, and times B's
   `waitUntilScheduled`:
   - off: p50 0.12 ms, p90 1.66 ms, max 1.90 ms;
   - on: max 0.02 ms;
   - ORDER OK both ways.

   metal-latency and metal-fence (40/40 CORRECT) are unchanged. Installed as a22865a4 (signed); backup
   /Library/NullMoth/nvmtl-plugin-20261103T154812Z. WindowServer loads it on the next boot.
2. **NMXGPU Step96** (`scripts/macos-install-step96.sh`): the cs-trace cave's thunk for the userptr_tail call
   goes through `userptr_ro`. On -EFAULT without READONLY, it sets `args.flags |= READONLY` and
   `gtt->userflags |= 1` (ttm+0x58, the bit `amdgpu_ttm_tt_is_readonly` and `amdgpu_ttm_tt_pte_flags` test, so
   the PTEs get no WRITEABLE bit), then pins again without FOLL_WRITE. Logs "NMX cs-trace: userptr_ro_retry -> 0".
   - To fit the cave (it ends at 0x5abe62, limit 0x5abe80), thunks align with `push rax`/`pop rcx` instead of a
     frame, and name rows are 18 bytes.
   - All 31 thunk targets and site ids were re-verified on a patched copy.
   - cave.bin 9ececcea, NMXGPU 44c7e552.
   - Input is the Step93 NMXGPU from step95-bk-20261103T152156Z.
   - Undo: `--undo`, or `scripts/linux-undo-step96.sh`.

After the next boot:
- `log show --predicate 'sender == "NMXGPU"' | grep -E "cs-trace|NMX userptr"`: expect "userptr_ro_retry -> 0"
  and no "pin FAILED" left unretried.
- WindowServer log "submit-ahead on the committing thread ON".
- Sample WindowServer: the `waitUntilScheduled` share should drop from ~19% of the main thread.
- Fence counters: with WindowServer returning earlier, NMXAccel may spin longer in IODelay. If `_wait_us` per
  frame grows a lot, the next NMXAccel change is to sleep instead of spinning.
- Other leads from this sample:
  - per-frame IOSurface import/free churn: `nvmtlNewSurfaceTexture` -> `amdgpu_create_bo_from_user_mem`
    85 samples, `bo_free` 44;
  - managed-buffer prologue uploads, ~200 KB per submit.

### Step96 boot results (2026-11-03 23:09 and 23:14 boots)

**23:09 boot: lost GPU interrupts (H2 from 2026-10-18), WindowServer crash chain, forced reboot at ~23:14.**

From 23:10:03, about 1 s after NMXGPU started, every fence completed only through amdgpu's 0.5 s fallback timer.
- The log showed "NullMoth: fence fallback on sdma0 ... irqs so far 45"; `nmx_irq_dispatched` stayed frozen at 45.
- "Fence fallback timer expired" lines per minute: 45 / 120 / 119 / 91, until the reboot.

At that time only the kernel's own SDMA jobs were running: no WindowServer, no CS ioctl, no userptr. So Step96 (the
userptr retry and CS thunks) is not implicated. Consequences:
- WindowServer 205 had Vulkan down by 23:11:20 ("pipeline: Vulkan is not up in this process"), then SkyLight
  aborted in `MetalShader::CopyPipelineState` (23:12:08).
- WindowServer 2635 took 7 s to open the Vulkan device and was killed by the watchdog (23:13:08).
- WindowServer 3723 hit "fence wait -> 2 after 5033 ms; disabling backend".
- `last` shows no shutdown, so the machine was force-rebooted at ~23:14.

No earlier boot today shows a fallback line. So this is intermittent, per boot.

**23:14 boot: clean, and Step96 works.**
- NMXGPU 44c7e552, NMXAccel 1b9c7b9f, NVMTL "submit-ahead on the committing thread ON".
- `userptr_ro_retry -> 0` 49 times. 3 "pin FAILED" lines remain; their retry also failed (likely ranges that were
  unmapped or partially mapped).
- WindowServer main thread (6 s sample): `waitUntilScheduled`/`waitUntilCompleted` went from 723 samples to 1.
  The main thread is now ~47% idle in mach_msg and ~45% in the frame update (CPU encoding).
  - Hot spot: per-draw descriptor snapshots, `nvmtlBindSamplerPipeline` -> `nvmtl_snapshot_set_c/md` ->
    `radv_UpdateDescriptorSets`, ~474 samples.
  - The commit-thread submit costs ~250 samples.
- **75.5 fps** (from ~55). Per frame in NMXAccel: fence wait 4.0 ms (GPU still compositing), beam wait 2.2 ms,
  K6 copy 3.2 ms. That is ~9.4 ms of serial present path per frame, the cap below 120 Hz. kernel_task ~28% CPU is
  mostly the copy.
- WindowServer CPU 41-63% (top).
- metal-latency: tiny submit 0.10 ms, p90 frames ~5 ms while WindowServer is busy.

Next, in priority order:
1. **Interrupt loss (H2), in the NMXGPU source.** When the fallback timer sees fence progress with
   `nmx_irq_dispatched` flat, dump IH_RB_RPTR/WPTR/CNTL, IH status, PCI command (INTx disable) and MSI control.
   Then self-heal: run `amdgpu_ih_process` from a short (1-2 ms) poll timer until interrupts come back, so the
   desktop survives while the root cause is found.
2. **Real flips** (removes the beam wait and K6 copy, ~5.4 ms/frame) with the flip ordered on the fence.
3. **Encode cost:** cache descriptor sets per bound-resource state, or use push descriptors, for the per-draw
   snapshot.
4. **NVMTL backend-down:** WindowServer aborts on a nil pipeline. With slow fences, a 5 s budget then "disable
   backend" turns a slow GPU into a crash loop.

## Step97 (lost-interrupt watch): detect, log and survive the boot-time IRQ loss (2026-11-03, macOS, not installed)

The 23:09 boot lost GPU interrupts about 1 s after NMXGPU loaded (H2, see the Step96 boot results). This is a binary
cave for the installed NMXGPU (`scripts/nmx-irqwatch`). It keeps the desktop alive in that state and logs the evidence
for the root cause. It does not fix the root cause.

### What it does
- **Detect** (fence fallback timer callback): the loss is declared when two timer-completed fallbacks happen in a row
  with `nmx_irq_dispatched` unchanged between them, while `adev->irq.installed` and `ih.enabled` are set.
  - A healthy boot cannot meet this: a fence that completes raises an EOP interrupt within µs.
- **Evidence**, logged once per episode for the first 4 episodes, as `NMX irqwatch:` lines in the kernel log:
  - ring name, last_seq/sync_seq, `nmx_irq_dispatched`, and the count of real handler runs;
  - IH ring 0 software state: enabled, rptr, ptr_mask, ring_size, use_doorbell/index, use_bus_addr;
  - the wptr write-back word **before and after a clflush** (H1 for the IH ring), the rptr write-back word;
  - `adev->irq.installed/irq/msi_enabled`, and the 8 dwords of the IV at rptr (after a flush);
  - 25 IH registers. All have BASE_IDX 0 in `osssys_6_1_0_offset.h`. The base is taken at runtime from the ring's own
    `ih_regs.ih_rb_cntl - 0x80`, after checking that rptr = cntl+1 and wptr = cntl+2:
    RB_CNTL 0x80, RB_RPTR 0x81, RB_WPTR 0x82, RB_BASE 0x83, RB_BASE_HI 0x84, RB_WPTR_ADDR_HI 0x85,
    RB_WPTR_ADDR_LO 0x86, DOORBELL_RPTR 0x87, VERSION 0xa5, CNTL 0xa8, CLK_CTRL 0xa9, RETRY_INT_CAM_CNTL 0xac,
    MEM_POWER_CTRL 0xad, CNTL2 0xc1, STATUS 0xc2, INT_FLOOD_CNTL 0xd5, INT_FLOOD_STATUS 0xd9, INT_FLAGS 0xdc,
    COOKIE_REC_VIOLATION_LOG 0xe4, CREDIT_STATUS 0xe5, MMHUB_ERROR 0xe6, MSI_STORM_CTRL 0xf1, CLIENT_CFG 0x184,
    CHICKEN 0x18d, INT_DROP_CNTL 0x18f.
    - Reads use `amdgpu_device_rreg(adev, reg, NO_KIQ)`, the same call `ih_v6_1_get_wptr` (0x4eb8b0) makes.
    - IH_STATUS bits worth checking: RB_OVERFLOW 0x20, BIF_INTERRUPT_LINE 0x400, ZSTATES_FENCE 0x100000,
      IH_BUFFER_MEM_POWER_GATED 0x200000.
    - IH_RB_CNTL bits: ENABLE_INTR 0x20000, RPTR_REARM 0x200000, WPTR_OVERFLOW_CLEAR 0x80000000.
  - PCI config, through `pci_read_config`/`pci_find_cap` on `adev->pdev->dev.bsddev`: command (INTx disable 0x400),
    status, the MSI capability (control, enable bit 0x1, address, data), MSI-X control, pdev irq/msi_enabled.
  - Every entry of nmx_bus.c's `intrs` list: irqno, plus the IOInterruptEventSource's `enabled`, `intIndex`,
    `producerCount`, `consumerCount`, `autoDisable` and `explicitDisable`. The offsets come from the macOS 26 SDK
    header, compiled with offsetof: 0x28 / 0x50 / 0x54 / 0x58 / 0x5c / 0x5d. How to read them:
    - producer frozen: the MSI does not reach the CPU;
    - producer > consumer: the work loop is not running the source;
    - both moving with handler runs but no dispatches: the handler runs but sees no new wptr.
- **Self-heal (degraded mode):**
  - Every fence fallback timer is armed for 2 ms (hz/500) instead of 500 ms. All three arming sites go through
    `fb_arm`.
  - Each expiry flushes the wptr write-back line, processes IH ring 0 through the guard below, and re-arms while the
    ring has unsignalled fences (`last_seq != sync_seq`). It does not poll or re-arm while `adev->shutdown` is set or
    the IH is disabled.
  - The per-expiry "Fence fallback timer expired" warnings are suppressed while degraded.
  - It leaves degraded mode when the *real* handler dispatches an IV again. A status line every 2048 polls (≤32 lines)
    and one at exit give the ms in degraded mode, polls, poll/IRQ dispatch counts, handler runs, timer completions,
    and IH rptr/wptr/STATUS.
  - Budgets: evidence for 4 episodes; ON/OFF lines for 16 episodes.

### Hooks (all `call rel32`, 5 bytes; original bytes, targets and the absence of nearby relocations verified)
| site | in | original callee | now |
|---|---|---|---|
| 0x652f5 | amdgpu_irq_handler | amdgpu_ih_process 0x64cf0 | ih_guarded 0x509100 |
| 0x6e898c | amdgpu_fence_fallback | amdgpu_fence_process 0x6e8840 | fb_process 0x5091d0 |
| 0x586b7 | amdgpu_fence_enable_signaling | mod_timer 0x6b6bb0 | fb_arm 0x509190 |
| 0x58791 | amdgpu_job_fence_enable_signaling | mod_timer 0x6b6bb0 | fb_arm 0x509190 |
| 0x6e8905 | amdgpu_fence_process (re-arm) | mod_timer 0x6b6bb0 | fb_arm 0x509190 |

- At each site rsp ≡ 0 mod 16 at the call: 3 pushes in irq_handler, fallback (+0x10), and enable_signaling; 6 pushes
  + 0x18 in fence_process.
- The cave entries are ordinary C ABI functions with the original callee's signature, so callee-saved registers and
  return values (`al` for the bool, `eax` for the rest) are what the callers expect.
- External calls from the cave go only to: amdgpu_ih_process, amdgpu_fence_process, mod_timer, nmx_jiffies,
  amdgpu_device_rreg, pci_read_config, pci_find_cap, and the `jmp _snprintf` 0x8789e / `jmp _printf` 0xbc46e sites.
- The only data the cave references is: borrowed ST words 0x927010..0x92708f, `nmx_irq_dispatched` 0x9b9950,
  `hz` 0x925e30, `intrs` 0x925af0, and "%s\n" 0x7001ed.

### Cave range and dead-code proof
- Cave: 0x509100..0x50a442 (4930 bytes). It is written inside 0x509100..0x50a630, which is `kv_dpm_enable` plus
  `kv_populate_vce/samu/acp_table` (KV legacy dpm). That range has no relocations, external or local.
  - The earlier choice, CI dpm `ci_initialize_mc_reg_table` (0xcd3d0..0xcde30), was too small. `ci_init_smc_table`
    contains `_log`/`___bzero` relocations, so it cannot be used.
- Why the range is never executed on Strix:
  1. No code outside the range branches into it except `kv_dpm_hw_init+0x4e` and `kv_dpm_resume+0x5a` (calls to
     `kv_dpm_enable`). No data word in __DATA points into it. The kv_populate_* functions are called only from inside
     kv_dpm_enable.
  2. `kv_dpm_hw_init` and `kv_dpm_resume` are reached only through `kv_dpm_ip_funcs` (+0x30, +0x58). That table is
     reached only through `kv_smu_ip_block` (+0x10). The block is referenced only by `cik_set_ip_blocks` (+0x77, +0x1c9).
  3. `cik_set_ip_blocks` is called only from `amdgpu_device_init+0x1ace`, on the asic_type 5..9 branch
     (Bonaire/Kaveri/Kabini/Hawaii/Mullins). Strix is CHIP_IP_DISCOVERY (> 0x12) and takes the discovery path.
- Original bytes sha256 of 0x509100..0x50a630: `405a5f93…`. The patch script refuses any other content.
- State: 16 u64 words at 0x927010.., inside 0x927010..0x927100. These are `ci_init_smc_table.__ratelimited.15`..`.43`,
  which are referenced only by `ci_init_smc_table`. That function is reached only via `ci_smu_funcs+0x88`.
  `ci_smu_funcs` is referenced only from `hwmgr_early_init+0x13c`, the family-CI (0x78) switch arm. Step95's
  0x926fe0/0x926fe4 are not touched.

### Execution context and why the serialization is safe
- The fallback timer is a LinuxKPI timer_list, which is an xkpi callout. All callouts run on the single "nmx softclock"
  kernel thread (bsdcompat nmx_task.c).
  - The thread runs the callback with no spin lock held and is preemptible. It *could* block, but blocking would stall
    every driver timer, so the cave never blocks or spins.
  - All fb_process calls are therefore serialized with each other.
- The real handler runs on the IRQ's IOWorkLoop thread (NMXIrq, one per vector).
- **Guard** on IH ring 0: a request counter in ST[3].
  - A caller does a `lock xadd`. If the counter was 0, the caller is the owner. The owner runs `amdgpu_ih_process`,
    then `lock cmpxchg`es the counter from its snapshot back to 0, and runs again if a request came in meanwhile.
  - A non-owner returns at once (IRQ_HANDLED); the owner processes its work.
  - So `amdgpu_ih_process(ih)` never runs twice at once, nobody waits, and no request is lost.
  - Ring 0 has no other caller: the other three references process ih1, ih2 and ih_soft.
- Deadlock check: IV handlers run on the softclock thread while degraded. They use non-sync `timer_delete`/`mod_timer`
  only. The fallback timer is drained (`timer_delete_sync`) only in fence driver fini, not from any IRQ handler.
- Healthy-boot cost:
  - fallback: one compare, plus one store when it completed fences;
  - timer arm: one compare, then a tail jump to mod_timer;
  - IRQ handler: one plain increment, one `lock xadd`, one `lock cmpxchg`. This is slightly more than "one compare",
    but the guard has to cover both paths always to be race-free.

### Results on a scratch copy
- Input: the installed NMXGPU `44c7e55201a3bcfb…` (Step93 + Step95/96 cs-trace cave).
- `build.sh` checks every symbol address. The build is reproducible: cave.bin `51cd5c3f8f94cb05e47b76abfd459ac39be3e23e9e94b651146b39b79da5d391`.
- `step97_patch.py <NMXGPU>` gives `d534cc334c9dcec682aedb9f3faf9f3dbf0e3abb3590d1ec89978cb6896db908`.
  - Only the cave range and the 5 rel32 fields change (checked with cmp).
  - It is idempotent ("already has Step97").
  - It refuses a modified site.
- `--check-kc` probes: the cave head and tail, plus a ±0x10 window at each site. All 7 unpatched windows occur exactly
  once in the current AuxKC, so kmutil carries them verbatim.
- The installer will be the combined Step97 one written by the main session.

### Risks
- Offsets are taken from this binary's disassembly. Only the IES offsets come from the SDK header (ABI-stable).
- The `intrs` walk is done without `bus_mtx`. The list changes only at attach/detach.
- An IV handler that sleeps would now do so on the softclock thread. None should, since they are written for hard-irq
  context.
- If the root cause is a stale cached wptr *and* the clflush does not help, the IH poll finds nothing. Fences still
  complete through the 2 ms fallback.
- A degraded-mode timer re-armed during fence-driver fini could fire once after `timer_delete_sync`. Fini waits for
  the ring to go empty first, and re-arm needs `last_seq != sync_seq`.
- A false-positive episode costs only 2 ms polling until the next real dispatch.

### After the boot
`log show --predicate 'sender == "NMXGPU"' | grep "NMX irqwatch"`. On a healthy boot it should be empty.

## Step97b: login crash loop = CS -EPERM from a stale xkpi mm (fix installed with Step97)

The boot after Step96 looped at the login window: WindowServer aborted on "CS rejected (-1)", loginwindow showed
the lock screen again, the password led to another crash. The -1 is not the Step95/96 userptr path. It comes from
`amdgpu_bo_list_create` (0xeb04): `__lkpi_current()->mm != usermm` -> -EPERM for every userptr BO in the list.

Root cause in xkpi: transient per-syscall thread records get their mm through `proc->p_lkpi_mm`.
`linux_mm_dtor` (0x6b8db0) frees the mm but clears `p_lkpi_mm` only when `curthread->td_proc` owns it. When the last
reference is dropped from a kernel worker, the pointer stays dangling and the next mm for that process can be a
different object. The userptr BOs that were created under the old mm then never match.

Fix (scripts/nmx-mmfix, cave 0x50a730..0x50a858 in dead `kv_enable_didt`, budget word 0x926ff8):
- `linux_mm_dtor`'s tail call to `uma_zfree_arg` (0x6b8def) becomes `ret`, so the mm is never freed (a small leak per
  process exit, nothing is reused under a stale pointer).
- The CS check calls the cave, which logs up to 64 `NMX mmfix: CS userptr BO mm ... != current mm ...` lines and
  allows the CS.
- Proper fix still to do in the xkpi source: remove the process record on exit and make the dtor clear the
  owner's pointer.

Installed with Step97 by `scripts/macos-install-step97.sh` (NMXGPU 44c7e552 -> c2326f22, both patches in either
order give the same bytes). Backup in /Library/NullMoth/step97-bk-*; undo with `--undo` or
`pkexec scripts/linux-undo-step97.sh`.

After the reboot, check:
- `log show --last boot --predicate 'sender == "NMXGPU"' | grep -E 'NMX (mmfix|irqwatch)'`
- no `p1_bo_handles -> -1` or "CS rejected" lines, and the login is reached
- fps (~75 at Step96)

## Step98: page flips, mode 2 (VRAM swap chain + vblank-latched flips), installed with Step97 for the same boot

The owner asked for flips in this boot rather than one boot later. So Step98 goes in together with Step97/97b, and
flips stay **off** until they are switched on by hand.

**NMXGPU flip API** (`scripts/nmx-flip`). The NMXGPU half that `docs/890M-FLIPS.md` section 5 asks for, as a cave:
the installed NMXGPU is the 2026-10-23 source build plus ~15 binary steps, so a source rebuild would drop those steps.
- Hook: 0x6e3b23 in `NMXGPUFB::callPlatformFunction`, the `je` taken when the name is not `nvScanoutInfo`. The cave
  compares the name against the six `nmxFlip*` names (OSSymbol `isEqualTo(const char *)`, vtable +0x158, as the
  original code does). Anything else continues to `IOFramebuffer::callPlatformFunction` exactly as before.
- Cave: 3792 bytes at 0x507190..0x508060 (`kv_dpm_sw_fini` .. `kv_dpm_set_power_state`, Kaveri-only dpm code). The
  only relocations around it are at 0x507187 and 0x50822b. State: 0xe8 bytes of dead CI dpm ratelimit words at
  0x9270a0.
- Struct offsets come from the real headers: a probe compiled with the xkpi `cc.sh` flags, checked against the binary
  (`fb->buffer` +0x78, `amdgpu_bo.tbo` +0x48, `pin_count` +0x23c).
- What it does:
  - `nmxFlipCaps`: SUBMIT | VRAM_CHAIN | XRGB8888, no IMPORT. Mode 1 (zero copy) needs DC with GPU VM on, which is a
    boot-critical change for its own boot.
  - `nmxFlipBuffers`: home (handle 0) + 2 more XRGB8888 buffers from the bridge's DRM client
    (`drm_client_framebuffer_create`). All three are pinned in VRAM (`amdgpu_bo_pin`) and never unpinned, mapped and
    checked to be physically contiguous. amdgpu GEM has no `.pin`, so without this the home buffer would be
    evictable while another buffer is on screen, under the kva that IOFramebuffer and the K6 copy publish.
  - `nmxFlipSubmit`: non-blocking atomic commit that only changes the primary plane's fb (DC fast update, latched at
    vblank). It holds a reference on the CRTC's `drm_crtc_commit`. Busy while the previous flip is pending.
  - `nmxFlipStatus`: never sleeps. Latched = that commit's `flip_done`. If the plane's fb is not the one last latched,
    the bridge committed home itself (restore, hotplug, display power): generation goes up.
  - `nmxFlipRelease`: busy while on screen or pending, otherwise success (chain buffers stay).
- NMXGPU c2326f22 -> 2d9102d8.

**NMXAccel**: CI `ci/nmxaccel-flip` 37493db (bf7c7ea8), the live a24692f fence build plus the flip path.
`debug.nmxaccel_flip` stays 0 at boot, so NMXAccel never calls the API.

Install: `scripts/macos-install-step98.sh` (backup /Library/NullMoth/step98-bk-20261103T171105Z, `--undo`, or
`pkexec scripts/linux-undo-step98.sh`; Step97's backup still holds the Step96 NMXGPU).

After the boot, in this order, one step at a time:
1. Step97 checks: desktop reached, no "CS rejected", `NMX (mmfix|irqwatch)` lines, fps.
2. `sudo sysctl -w debug.nmxaccel_flip=2`, then read `log show --last 2m | grep -E "NMX flip|iop: flip"` and the
   `debug.nmxaccel_flip_*` counters. Expected: "API up", a chain of 3, `latched` growing with `submitted`, and
   `fallback`, `timeouts` and `tripped` at 0.
3. If anything looks wrong: `sudo sysctl -w debug.nmxaccel_flip=0`. The next frame copies home and flips home.

## Step98 boot (2026-11-04 00:16) and Step98b

**Step97 results: the login crash loop is gone.**
- The desktop came up, with 0 "CS rejected" lines and 48 read-only userptr retries.
- There were no `NMX mmfix` lines. The mm mismatch did not happen on this boot, so the check never had to allow a CS.
- There were no `NMX irqwatch` lines: interrupts were not lost.

**Baseline with flips off** (10 s on an idle desktop): 84.4 fps, beam wait 4.05 ms, K6 copy 5.26 ms and fence wait
2.05 ms per frame, WindowServer at 71% CPU.

**Flips: the API answered, but every call came back NotReady.**
- `debug.nmxaccel_flip=2` logged `NMXGPU flip API MISSING ... (0xe00002d8)`.
- 0xe00002d8 is the cave's NotReady. So the hook and the name dispatch work, but `init()` refused.
- The cause: `init()` waited for `fb->info.ok`. `nmx_fb_open` copies `*out` into `fb->info` (`rep movsq` at 0x6cd5f5)
  and only then sets `out->ok = 1` on the caller's copy (0x6cd60c), so `fb->info.ok` is always 0.
- NMXAccel asks for caps only once per boot (`flip_api` is read-only), so flips need another boot. Flips were set
  back to 0.

**Step98b** (`scripts/macos-install-step98b.sh`):
- the cave checks `fb->info.kva` and `fb->info.size` instead (cave.bin f446ceca, 3800 bytes);
- NMXGPU is rebuilt from the Step97 build in the Step98 backup: da129846;
- NMXAccel is unchanged;
- `macos-install-step98.sh` now carries the same shas;
- undo is still `macos-install-step98.sh --undo`.

## Step98b boot (2026-11-04 00:25): page flips work (mode 2)

- The boot was clean again: NMXGPU da129846, 0 "CS rejected", 48 read-only userptr retries, no irqwatch or mmfix
  lines.
- Flips off, 10 s on an idle desktop (`tools/890m/present-rate.sh 10`): 82.7 fps. Per frame: beam wait 2.36 ms,
  K6 copy 3.44 ms, fence 4.19 ms.
- `sysctl -w debug.nmxaccel_flip=2`:
  - The cave logged `NMX flip: API up` and `chain of 3`. NMXAccel logged `flip API present: caps 0x105` and
    `3 of 3 buffers usable`.
  - The buffers are home (phys 0x87c000000, gpu 0x801c000000) plus 0x864000000 (gpu 0x8004000000) and 0x867c39000
    (gpu 0x8007c39000), all pitch 11520.
  - Every latch reads back the flipped buffer's address from HUBP0 (`HUBP0 addr 0x8004000000` after a flip to
    handle 1, `0x801c000000` after a flip home). The display really scans the buffer that was flipped to.
- Flips on, 10 s: **99.3 fps** (from 82.7). The beam wait is gone (0.00 ms) and the K6 paced copy is gone. The copy
  into the back buffer is now unpaced and not in the beam counters. The latch wait is 3.86 ms on average, off the
  serial path (async completion). Fence wait was 3.64 ms.
- 30 s more: 2321 submitted = 2321 latched. Tripped, timeouts, fallback, drop and hw_mismatch were all 0. The fps over
  those 30 s was 77.4, because the desktop drew fewer frames.
- The `debug.nmxaccel_flip` setting returns to 0 at every boot.

Next:
1. Make flips the default at boot.
2. Mode 1, zero copy: scan the IOSurface itself (DC with GPU VM, its own boot). It removes the remaining CPU copy.
3. A descriptor-set cache in NVMTL, for WindowServer's CPU.

## Step99: zero-copy flips (mode 1) + flips on by default (installed, reboot pending)

NMXGPU 1907d9f9 is the Step97 build (c2326f22, from the Step98 backup) plus `scripts/nmx-flip/step99_patch.py`.

**Zero copy needs DC with GPU VM.**
- The bridge forced `amdgpu_sg_display = 0` in `nmx_fb_before_attach`. That store at 0x6ccfcb is now a nop, so the
  parameter keeps its default -1. `amdgpu_dm_init` then sets `mode_info.gpu_vm_support` (adev+0x10de4) on the APU,
  DC runs with the system context / HVM (Linux's default on Strix), and `amdgpu_display_supported_domains` offers
  GTT for USWC buffers.
- The bridge's own buffers must stay one contiguous VRAM range, because the IOFramebuffer aperture and the K6 copy
  use them. So `nmx_fb_open`'s call to `drm_client_framebuffer_create` (0x6cd39d) goes through `fb_create_vram`,
  which clears `gpu_vm_support` around the call. The mode-2 chain uses the same helper.
- The home buffer is now pinned in VRAM on the first flip call, whatever the mode. DC unpins it when a flip moves to
  another buffer, and without our pin TTM could then evict it.

**`nmxFlipImport`** (`scripts/nmx-flip/import.c`, 2389 bytes at 0x506580 in dead `kv_dpm_sw_init`):
1. The descriptor's pages are read with `getPhysicalSegment`. NMXGPU's own call uses vtable +0x138 and
   `kIOMemoryMapperNone`. They go into a flat sg_table, contiguous runs merged; the dma address is the physical
   address, since xkpi maps 1:1.
2. `amdgpu_gem_object_create(CPU domain, CPU_GTT_USWC, ttm_bo_type_sg)`. The sg_table is set on `bo->tbo.sg` and on
   the ttm_tt TTM already made (`TTM_TT_FLAG_EXTERNAL`), so `amdgpu_ttm_backend_bind` takes the dma addresses from
   it.
3. Pinned in GTT, then `amdgpu_ttm_alloc_gart`. The gpu address is the GART address DCN fetches.
4. A GEM handle on the bridge's DRM file, then `drm_mode_addfb2` (XRGB8888 for 'BGRA', XRGB2101010 for 'l10r', the
   surface's pitch).
- Handles 8..11. `nmxFlipRelease` unpins and removes the fb and the handle; the sg_table is leaked on purpose.
- Caps add IMPORT and XRGB2101010 only when `gpu_vm_support` is set.

**Flips on by default.**
- LaunchDaemon `com.ga403wm.nmx-flip-default` sets `debug.nmxaccel_flip` from
  `/Library/StrixGraphicsFix/nmx-flip.mode`, which defaults to 2. Mode 2 is proven on this machine.
- Mode 1 is switched on by hand after the boot: `sudo sysctl -w debug.nmxaccel_flip=1`. Watch `iop: flip:` and
  `NMX flip: import`. `front_written` counts CoreDisplay drawing into the surface on screen.

Risk: the GPU VM change is in the boot-critical display bring-up. No picture means
`pkexec scripts/linux-undo-step99.sh` from Linux (NMXGPU back to Step98b, daemon removed, relink on the next boot).
On macOS: `sudo scripts/macos-install-step99.sh --undo`. Backup: /Library/NullMoth/step99-bk-*.

## Step99 boot (2026-11-04 10:11): DC with GPU VM boots, flips on by default, zero copy works

- The boot was clean: NMXGPU 1907d9f9, 0 "CS rejected", the panel lit as before. The home buffer is still VRAM at
  phys 0x87c000000 / gpu 0x801c000000, so `fb_create_vram` kept it out of GTT.
- The flip-default daemon logged `flips mode 2 after 1 s`. NMXAccel reports caps 0x307 (SUBMIT, IMPORT, VRAM_CHAIN,
  XRGB8888, XRGB2101010), so `gpu_vm_support` is on. The chain is home + 0x862000000 + 0x866000000.
- Mode 2, 10 s: 69.5 fps for the content on screen. Beam and copy 0, 695/695 latched, kernel_task ~29%.
- Mode 1 (`sysctl -w debug.nmxaccel_flip=1`):
  - Three CoreDisplay surfaces were imported (0x2, 0x4, 0x1), each 2880x1800 pitch 11520 XRGB8888. Each is 5063 pages
    in 5063 runs: the IOSurface pages are not physically contiguous, so the GART is what makes the scan possible.
    The GART addresses are 0x7fff00e83000, 0x7fff0224a000 and 0x7fff03611000.
  - 10 s: 62.6 fps for the content on screen, 626/626 latched, latch wait 6.26 ms (async, off the serial path).
    Fallback, timeouts, tripped, import_fail and front_written were all 0. kernel_task dropped to ~22%: the CPU copy
    is gone.
  - `hw_mismatch` stayed 0 over every mode-1 latch. NMXAccel compares HUBP0's surface address with the import's GART
    address on each latch, so DCN really fetches the IOSurface pages.
- The fps figures follow what the desktop draws; they are not a like-for-like benchmark.
- Still to check: what is on screen with mode 1 (stale or torn pixels if CoreDisplay drew into the surface on
  screen; `front_written` has stayed 0). The default mode is still 2 (`/Library/StrixGraphicsFix/nmx-flip.mode`).
- The owner checked the screen in mode 1 (windows dragged, pages scrolled, typing): it looks normal, with no
  tearing, flicker or garbage. After that use: 17042 submitted, 17041 latched (one in flight), 3 imports. Fallback,
  timeouts, tripped, front_written, hw_mismatch and import_fail were all 0.
- **Mode 1 is now the boot default**: `/Library/StrixGraphicsFix/nmx-flip.mode` = 1. To go back to mode 2, write 2
  there. The daemon's fallback when the file is missing stays 2.

Next: a descriptor-set cache in NVMTL (WindowServer CPU), the root cause of the boot-time interrupt loss (H2), and
the xkpi source fixes (mm lifetime, process records) in place of the Step97b cave.

## Step100: one batch: H2 root cause fix, stale xkpi records, NVMTL descriptor cache, brightness (2026-11-04, installed, reboot pending)

Installed by `scripts/macos-install-step100.sh` (undo: `--undo`, or `scripts/linux-undo-step100.sh` from Linux).
NMXGPU 1907d9f9 (Step99) -> **d4830f51**; all KC probes present (Step97b, Step99, irqfix, mm fix, NMXBacklight).

**H2 (boot-time interrupt loss): the IH thread blocks in a kernel printf.** `amdgpu_fence_read`'s stale-read
diagnostic printf (inlined into `amdgpu_fence_process`, 0x6e88b3) runs on the MSI's interrupt thread. With `-v` every
printf also draws on the video console, and the console stalls for seconds during the first modeset (`nmx_fb_open`).
The handler then never writes rptr back; with RPTR_REARM the IH sends no further MSI, so fences complete only through
the 0.5 s fallback. Evidence (00:13 boot): IH STATUS has an interrupt pending, no overflow; event source produced 34,
consumed 33; software rptr 0x520 vs hardware 0x500; the IRQ thread's last line is `STALE fence read on sdma0` and the
cmpxchg after the printf never ran; NMXAccel stalled in IOLog at the same instant. Same on the 17:10 boot (recovered
after 1.5 s); the 23:09 boot matches in timing (loss within 3 ms of the first mode set on all three).
Fix (`scripts/nmx-irqfix/`): the printf set-up at 0x6e88a0 becomes `call stale_note` (count only, never prints);
irqwatch rebuilt in its region as a safety net that names a blocked handler. Source: `amdgpu-fence-read-noprint.patch`.

**Stale xkpi records (root cause behind Step97b).** Thread records (keyed by thread_t) and process records (keyed by
proc_t) are never removed and xnu reuses both pointers, so a new thread could run with a dead process's task and mm.
`scripts/nmx-mmfix2/`: the lookups in `nmx_thread_get` (0x6d7530) and `nmx_proc_for` (0x6d73c0) now also compare the
stored tid / pid (calling thread_tid / proc_pid through the already-linked call sites); a mismatch unkeys the record
and a fresh one is built. Capped at 4096 per kind. Log: `NMX mmfix2: stale xkpi records retired: threads N, procs M`.
Step97b's bypass and the mm_dtor `ret` stay as a safety net. Source fix: nmx-src fork branch `mm-lifetime` 163d117.

**NVMTL descriptor-set cache** (plugin fork branch `desc-cache` d5da629, UUID 7927EB9E): see
`scripts/nvmtl-desccache/NOTES.md`. CPU test: 157,674 -> 5,059 new sets per 120k draws. Off switch:
`NVMTL_NO_DESCCACHE=1` (`install.sh off`) or `touch /tmp/nvmtl-desccache-off`. Stats line every 60 s.

**Brightness: NMXBacklight.kext** (`kexts/NMXBacklight`, BSD). Matches NMXAMDFB; publishes the "backlight"
IODisplayParameterHandler, gives that framebuffer object a vtable copy whose getAppleSense says LCD (so IOGraphics builds
AppleBacklightDisplay), and applies levels through amdgpu: nmx_backlight_next -> linux_backlight_update_status (percent)
-> amdgpu_dm -> dc_link_set_backlight_level_nits. NMXGPU functions are checked byte for byte first. Boot-arg
`-nmxbloff` disables it. Display name needed no change (System Information: "Samsung ATNA40CU05-0 (OLED)"; System
Settings always says "Built-in Retina Display"). More HiDPI sizes need scaled-mode support in NMXGPUFB
(IOFBScalerInfo, validate/setDetailedTimings, a larger client framebuffer scaled by DC): not in this batch.

**Check after boot:**
- `/usr/bin/log show --last boot --predicate 'sender == "NMXGPU"' | grep -E "irqwatch|STALE|mmfix"`: no irqwatch, no
  sdma STALE lines; mmfix2 counts if any records were recycled; no `NMX mmfix:` (Step97b) lines.
- `/usr/bin/log show --last boot | grep NMXBacklight`: "handler published", `display not yet`, "brightness parameters
  on AppleBacklightDisplay", then "N% applied" on slider moves. `ioreg -lw0 | grep -E "AppleBacklightDisplay"`.
- `scripts/nvmtl-desccache/install.sh status` (hit/miss), `top`, `tools/890m/present-rate.sh 10`.

## Step100b: the Step100 boot ran without NMXGPU; kernelmanagerd replaced the AuxKC (2026-11-04)

Boot 11:03:44 (local): WindowServer crash loop, CoreDisplay `0 of 1 framebuffers` (only the NVIDIA IONDRVFramebuffer).
Not one `(NMXGPU)` line in that boot, so none of the Step100 NMXGPU changes (irqfix, mmfix2) ever ran.

- The VGA matching thread: NMXAccel probe at 52.131, then `NMXGPU has not claimed 1002:150e yet` in the same ms. On the
  good 23:10 boot (Step99) the same thread had a 1.9 s gap there, which is the NMXGPU kext load, followed by `no FADT` and
  `ran 45 SYSINITs`.
- The AuxKC on disk (written 11:01:08) holds: AppleMobileDevice, nke.rvi, HighPointIOP/RR, NMXAccel, nmxbacklight,
  NVAccel, NVRM, NVRMAGDC, NVRMFB, strixaccel, strixgop, pataudit. **No com.nullmoth.NMXGPU and no com.ga403wm.NMXAGDC**,
  and none of the NMXGPU bytes. The Step99 KC (backup step100-bk-20261104T035737Z) had both of them and no pataudit/rvi.
- The installer's own collection was good (`--check-kc` all present) and was moved in at 11:01:01 (`RELINKED`).
  `/private/var/db/KernelExtensionManagement/AuxKC/CurrentAuxKC/` (instructions + uakl + StashedExtensions) was written at
  11:01:06-07 and the KC at 11:01:08: kernelmanagerd rebuilt the AuxKC from `com.apple.kcgen.instructions.plist`
  (`kextsToBuild`), its own list of approved kexts. The trigger was the new kext NMXBacklight in /Library/Extensions
  (its cdHash 08537cc6 is now in the UAKL). NMXGPU and NMXAGDC have never been in that list, because we always link
  by hand with `kmutil create`. The list even pulls PatAudit from ~/develop/.../build/ws-deep.
- Earlier steps changed only existing kexts, so kernelmanagerd never rebuilt and the hand-linked KC stayed.

Fix (nothing in the kexts changes; Step100 is not reverted):
- `scripts/nmx-relink/nmx-relink.sh`: after the `mv`, it waits 45 s and checks the KC **on disk** again for the UUIDs of
  NMXGPU, NMXAccel, NMXAGDC and NMXBacklight. If the KC was replaced, it links again (up to 3 attempts). It reboots only
  when the KC still holds all four.
- `scripts/macos-install-step100.sh`: the same 45 s on-disk check after the `mv`.
- `pkexec scripts/linux-rearm-step100.sh`: checks NMXGPU d4830f51 and NMXBacklight 8a57847a, backs up the kernelmanagerd
  KC and its instructions to /Library/NullMoth/step100b-*, re-arms nmx-relink with the reboot flag.

Next boot: macOS relinks by itself (no desktop, ~2-3 min) and reboots. Look in /Library/StrixGraphicsFix/nmx-relink.log
for `present=True` on both checks and `attempt=1` only. If it took a second attempt, kernelmanagerd rebuilds at boot as
well.

## Step100c: black screen after the relink; the irqfix state overlapped the flip lock (2026-11-04)

The Step100b relink worked on the first attempt. Both KC checks were `present=True`, and the KC (11:30:14) still held all four
kexts. Boots 11:31 and 11:36: NMXGPU came up as before (DC, rings, `driving 1002:150e`, NMXBacklight `100% applied`).
WindowServer opened the pipe, and NMXAccel reached `flip: NMXGPU flip API present ... generation 1` at 11:32:09.577.
After that there is no NMX line at all. At ~up 156 s the userspace watchdog panicked the Mac:
`no successful checkins from WindowServer ... in 120 seconds` (Kernel-2026-11-04-113630.panic). Both boots match.

Spin reports (`WindowServer_*_userspace_watchdog_timeout.spin`):
- The WindowServer main thread is in IOAccelerator `externalMethod`, `blocked by turnstile waiting for kernel_task thread 0x10b3`.
- Thread 0x10b3 `NMXDisplayPipe`: IOAcceleratorFamily2 -> NMXAccel -> NMXGPU+0x5071a3 (the flip cave entry) ->
  **running** at NMXGPU+0x507724 / 0x50772a in all 12 samples. That is `lock()` from nmx-flip/common.h:
  `xchg %eax,0x9270a0(%rip); test; je; pause; jmp`.

Cause:
- The Step99 flip/import caves keep `struct st` at 0x9270a0, with `lock` first.
- The Step100 irqfix cave keeps ST[] at 0x927010 with NSTATE = 23 words, i.e. 0x927010..0x9270c8. Step97 used 16 words,
  ending at 0x927090.
- So ST[18] H_MAXJ (the longest handler run in jiffies, non-zero after the first interrupt) is the flip lock.
  ST[19..22] (STALE_*) overlay gen/current/pending/nbuf/logs/tried/seqSub.
- The REGION file listed `0x927010..0x9270c0` but nobody checked it against the flip's 0x9270a0.
- The first flip spins forever inside the display-pipe gate, and WindowServer waits on the gate.

Fix (`scripts/nmx-irqfix/st_move.py`, d4830f51 -> 3e1b6619):
- ST[] moves to 0x927208..0x9272c0 (`ci_populate_bapm_vddc_vid_sidd.__ratelimited.79` .. `ci_set_mc_special_registers.
  __ratelimited.97`, CI dpm only). 0x927200 is where the flip state ends; 0x927370 is the end of the free CI block.
- Only the 69 rip-relative displacements into 0x927010..0x9270c8 change, by +0x1f8 each. They come from a raw
  disassembly of the cave, 0x509100..0x50a024, with strings after that; the list is `st_sites-d4830f51.txt`.
- Check: the instruction stream is identical after masking the displacements. Every ST ref is now in 0x927208..0x9272b8.
  No byte outside the cave changed (138 bytes in total).
- The cave is not rebuilt from cave.c, because the current clang does not reproduce the installed cave.bin.

Install: `pkexec scripts/linux-patch-step100c.sh`:
- Backs up NMXGPU.kext and the KC to step100c-bk-*.
- Patches NMXGPU and re-arms nmx-relink.
- nmx-relink now also checks byte windows of NMXGPU listed in /Library/StrixGraphicsFix/nmx-relink.probes, because a binary
  patch keeps the UUID.

The relink boot still runs d4830f51, so it will hang and panic again at ~160 s. The relink finishes at ~80 s (it took 53 s
on Step100b).

## Step100 boot (11:53 local, 3e1b6619): H2 quiet, records retired, brightness path live; WindowServer CPU root cause

Boot after the Step100c relink. Desktop OK, flips latch (mode 1 imports, `#0/#1 latched`).
- **H2:** 0 `STALE fence read on sdma*` lines (the IRQ path no longer prints) and no irqwatch line. One boot only.
- **mmfix2:** `stale xkpi records retired: threads 1` (11:53:49) then `threads 2` (11:54:09), procs 0. Recycled thread_t
  pointers do occur in practice; no `NMX mmfix:` (Step97b bypass) line.
- **NMXBacklight:** `sense slot 337, panel registered, initial 100%, display not yet; handler published` (12.7 s), then
  `brightness parameters on AppleBacklightDisplay` (46.5 s) and `100% applied (rc 0)`: the display is an
  AppleBacklightDisplay now. **Owner verified the slider changes the OLED brightness** (12:2x).
- **desc-cache:** `hit 350527 miss 8375783 (long 8188350)` at 7 min, WindowServer ~69 %. 98 % of lookups overflowed the
  key. Root cause: WindowServer's fragment shaders declare binding 192 (`[[color(n)]]` framebuffer fetch; the log says
  so for every such module), `nvmtl_spirv_bmask` returned 0 on any binding outside the layout's bands, so those
  pipelines had no mask and every draw wrote **all ~200 bindings** (CPU test: 21.0 M descriptor writes per 120 k draws
  without a mask vs 0.34 M with one), and the cache key spent 1-2 words on each.
  Fix (plugin fork `desc-cache` e34b10d): the mask skips bindings that are not in the set layout (192..199, 200..479,
  heap set 2) instead of being dropped; the cache key holds only bound descriptors as (binding, value) pairs; 256
  entries per command buffer. CPU tests pass, plus a SPIR-V unit test for the mask (192 skipped, 640/32 kept, heap
  skipped). Built `out/plugin-desccache-e34b10d` (sha a6574d21, UUID 2DEC581D); takes effect at the next WindowServer
  start.

**Cave registry (root cause of Step100c):** `scripts/nmx-caves/check.py NMXGPU` disassembles every cave and checks that
code ranges and borrowed data ranges are disjoint and that every rip-relative data reference of a cave lands in its own
registered range (or a listed NMXGPU global). The live 3e1b6619 passes; the d4830f51 build fails on the irqfix
references to 0x927010 (the overlap that hung the first flip). The Step100 installer runs it before linking;
nmx-relink runs it when `/Library/StrixGraphicsFix/nmx-caves-check.py` is installed. A new cave must add itself to
`REGISTRY`.

### HiDPI scaled modes: root cause and plan (deferred by the owner, 2026-11-04)

System Settings shows one "Larger Text / More Space" tile and no refresh menu: CoreGraphics gets exactly 2 modes
(1440x900 HiDPI and 2880x1800, both 120 Hz, IO mode 1). NMXGPUFB is a fixed single-mode framebuffer:
getPixelInformation / setDisplayMode accept only mode 1, size/pitch/aperture come from fixed fields
(+0x1dc w, +0x1e0 h, +0x1e4 rowBytes, +0x1e8 aperture phys, +0x1f0 VRAM size); it has no validateDetailedTiming /
setDetailedTimings and no scaler info, so `scale-resolutions` in the override cannot add sizes.
Plan: (1) NMXBacklight's vtable copy reports more backing sizes (3360x2100, 3024x1890, 2560x1600, ...) on the native
timing and, on setDisplayMode, gets a buffer of that size from NMXGPU and updates the +0x1dc..+0x1e8 fields;
(2) the flip cave allocates the per-mode VRAM buffer and sets the plane src rect to the fb size on every commit
(today SET_FB_FOR_PLANE keeps src 2880x1800), so DC's plane scaler fits it to the panel; (3) check NMXAccel's copy
fallback for a surface size different from the home buffer. Fallback: boot-arg -nmxbloff.

## Step100 boot 2 (12:29 local, plugin e34b10d live): desc-cache fixed; WindowServer CPU is now load plus NVMTL per-draw cost

State: NMXGPU 3e1b6619, NVMTLDriver UUID 2DEC581D (e34b10d), NMXBacklight and NMXAccel loaded, no panic.

- H2: 0 `STALE fence read on sdma` lines, no irqwatch line. mmfix2: `threads 1, procs 0`. Flip API up 2880x1800.
- NMXBacklight: handler published (sense slot 337), parameters on AppleBacklightDisplay at 100 %.
- Desc-cache (12:34): `hit 3103568 miss 281316 (stale 3902, page 31976, long 0, full 0)`. Hit rate 92 %, `long` went from
  dominant to 0: the e34b10d key fix works.
- Shutdown stall 12:28 (previous boot's shutdown): 1 s, every thread idle (NMX threads parked), caffeinate and
  duetexpertd slow on SIGTERM. Not a GPU issue.

WindowServer, Claude Helper redrawing at 96 % (present-rate 10 s: 111.2 fps, fence 4.23 ms, flips 1112, fallback 0):
- `top`: 59..68 % (Step100 boot 1: ~69 %). `ps -M` delta over 10 s: user 43 %, system 18 %.
- The fence wait (`drmSyncobjWait` under `nvmtl_gsub_finish`, 1449 of 5000 ms in `sample`) sleeps; it is wall time on
  the pump thread, not CPU.
- On-CPU user samples by owner: NVMTL+radv ~30 %, QuartzCore ~25 %, SkyLight ~13 %, rest (objc/malloc/CF under both).
  QuartzCore/SkyLight is the 111 fps compositing load itself.
- NVMTL per 5 s: encoder 829 ms (draws ~430, `nvmtlBindSamplerPipeline` 134), texture create 137 + destroy 94 (per-frame
  `create_variable_blur_mip_surface` -> BO alloc/VA map/free ioctls, `amdgpu_vamgr_free_va` 34), submit 195.

Reducible NVMTL costs (no single bug left), by size:
1. Per-frame texture memory: CA's blur mip surfaces allocate and free a BO every frame. Recycle VkDeviceMemory by
   (size, heap) after the submission that used it retires.
2. `nvmtlBindSamplerPipeline` builds two NSDictionaries and JSON-serializes them per draw for the sampler-variant key.
   Memo the last (pipeline, sampler objects) -> variant per encoder; keep the JSON key only on a miss.
3. `nvmtl_trace_on` reads the clock on every call (41 samples): a flag refreshed by a timer is enough.

## Step101: NVMTL per-draw cost (plugin 3d0dc6a, fork branch desc-cache; loads at the next WindowServer start)

The three reducible costs from "Step100 boot 2":
1. **Image park** (`nvmtl_vk.c`, `nvmtl_vk_image_park/unpark/park_drain`). A plain device texture
   (`newTextureWithDescriptor:`, typed path; not multisample, depth, IOSurface, heap or buffer-backed) is parked at
   dealloc under its creation key (w, h, format, bpp, a8, mips, ShaderWrite, type, layers) and the next texture with
   the same key takes it. At most 48 images / 160 MB (oldest destroyed first, one image at most 40 MB); a failed
   allocation drains the park and tries again. Parked images stay counted in the VRAM totals. Same lifetime rule as the
   destroy it replaces (dealloc runs once no command buffer holds the texture). A destroy also bumped the desc-cache
   image epoch and retired every cached set that held an image; a park does not. Off: `NVMTL_NO_IPARK=1`. Log line
   `image park (hit|miss): hit .. miss .. parked .. evicted ..` at powers of two.
2. **Sampler-variant fast path** (`nvmtlBindSamplerPipeline`): per pipeline, a map from the bound sampler-state objects
   (slot, pointer) to the variant, filled after the JSON-keyed slow path has an answer. The entry holds the state
   objects strongly (no pointer reuse); 256 entries per pipeline, then cleared.
3. **Trace check**: `nvmtl_trace_on` reads the clock every 64th call.

Check at the next boot: `image park` hit count growing with few misses; desc-cache `epochs img` grows much more slowly
than at boot 2 (126754 in 5 min); WindowServer `ps -M` user time against 43 % at 111 fps (`present-rate.sh 10`).

## Step101 boot (12:46 local, plugin 3d0dc6a): image park live; the per-frame churn is sampler states

State: NMXGPU 3e1b6619, NVMTLDriver EBC78554 (3d0dc6a), no panic. `STALE fence read on mes_3.0.0` 8 lines (init and
flip imports): the previous boot had 4 in 17 min, sdma has none, so not a regression.

- WindowServer at ~81 fps over 20 s (`ps -M` delta): user 39.8 %, system 10.5 % (boot 2: 43 % / 18 % at 111 fps, with
  the Claude app redrawing at 96 %; this run it sat at ~5 %, so the load is lighter and only per-frame cost compares:
  CPU per frame by user+system ~5.5 ms at boot 2, ~6.2 ms now: no per-frame gain yet; plain texture creates left the
  profile, but at a lower frame rate fixed per-frame work weighs more).
- Image park: hit 32 miss 96 in the first minute, then fewer than 256 park calls in 4 min: plain textures are not the
  per-frame churn in this load. `newTextureWithDescriptor:` (plain) is gone from `sample`.
- Desc-cache: `epochs img 79728` after 2 min (~660 bumps/s) - still high. Sampler fast path: JSON serialization still
  on the profile (18 of 157 samples in `nvmtlBindSamplerPipeline`).
- Root cause of both: CoreAnimation asks for **new sampler states every frame** (`newSamplerStateWithDescriptor:` 26
  samples per 5 s). Each one was a new VkSampler (and NSDictionary pixel state), its destroy bumped the image epoch
  (retiring every cached set with an image in it), and the fast path keyed by pointer never saw the same pointer.

## Step101b: sampler-state cache (plugin f973e95)

- `newSamplerStateWithDescriptor:` returns one immutable object per unlabelled descriptor (every field: filters, mip,
  anisotropy, address modes, border, reduction, normalized, lodAverage, argument buffers, compare, LOD clamps, bias);
  held for the process lifetime, at most 1024; `NVMTL_NO_SAMPCACHE=1` turns it off. Log `sampler cache: hit N, M made`.
- Pixel-state dictionaries are interned by descriptor too (labelled samplers).
- Trace: the desc-cache stats line now names the destroy behind each image-epoch bump
  (`img by view .. image .. sampler .. bufview ..`), so the next boot shows what is left.

## Step101b boot (13:03 local, plugin f973e95): WindowServer per-frame CPU down ~45 %

State: NVMTLDriver C465B823 (f973e95), no panic; mes STALE lines 6 (background, as before); NMXBacklight active.

- present-rate 20 s: 96.2 fps, fence 3.28 ms, flips 1925, fallback 0.
- `ps -M` delta over 21 s: **user 25.7 %, system 6.6 %** -> ~3.4 ms CPU per frame (Step101 boot ~6.2 ms, boot 2
  ~5.5 ms). `top` 37..40 %.
- Sampler cache: `hit 128, 11 made` (sampler destroys 0).
- Desc-cache after ~1 min: `hit 227076 miss 37582 ... epochs img 15001 (img by view 13043 image 1957 sampler 0)`.
  What is left is image **view** destroys (~200/s).
- Source (sample): `newTextureWithDescriptor:iosurface:` -> surface keep -> `newTextureViewWithPixelFormat:` on the
  cached backing: every per-frame IOSurface wrapper made its own VkImageView with the backing's format and range.

## Step101c: identity views share the image's own view (plugin fbb6ca4)

`nvmtlViewWithFormat:levels:`: a view of a root texture with the same Metal format (not a8), every level and slice,
the same type, and a root without its own or swizzled view takes the image's view (`_ownView` stays nil, `nvview`
falls back to `image->view`); nothing to destroy at dealloc. Log `newTextureView: N identity view(s) share the
image's own view` at powers of two. Off: `NVMTL_NO_IDVIEW=1`. Expect `img by view` to drop to a trickle next boot.

## Step102 (2026-11-04): Metal for sandboxed apps - DRM through IOKit (installed, reboot pending)

Root cause (app test, same day): sandboxed apps (TextEdit, App Store apps, browser GPU processes) are refused
`/dev/dri` (`Sandbox: TextEdit(17713) deny(1) file-read-data /dev/dri`), RADV enumerates 0 GPUs, the plugin refuses
the device and the app draws on the CPU (it looks fine, which hid it). Non-sandboxed Terminal (`NVMTL_ENABLE=1`) is UP
on RADV STRIX1 with no ring timeout.

Pre-check with `sandbox-exec` (deny default + system.sb `(system-graphics)`): `open(/dev/dri/renderD128)` -> EPERM,
but `IOServiceOpen(NMXAccel, …)` reaches the driver (types 0/1 open; the new type answered kIOReturnUnsupported from
the old kext, not "not permitted"). The sandbox allows user clients of an IOAccelerator, as NullMoth's NVIDIA bridge uses.

Fix (fork, PolyForm code stays there):
- NMXAccel `ci/nmxaccel-drmuc` 7bd4e99 (CI run 41789977284, sha 48b3f689): user client type `'NMDR'` (0x4E4D4452),
  `kexts/NVRM/accel/nmx/nmx_drm_uc.cpp`. Selector 0 opens `/dev/dri/renderD<N>` on a kernel thread (kernel vfs context,
  so the caller's sandbox is not asked; the open is its own devfs clone = its own DRM file); selector 1 runs an ioctl
  with VNOP_IOCTL on the caller's thread (mappings land in the caller's task); selector 2 = node major for stat;
  close / process death closes the vnode. Log: `NMXAccel: drm-uc: pid N opened /dev/dri/renderD128 for its sandbox`.
- Plugin `desc-cache` 923deca (`plugin/nvmtl_drm_xnu.h`): only in sandboxed processes (`sandbox_check`), the libc
  imports of RADV, libdrm and libdrm_amdgpu (open, ioctl, close, dup, fcntl F_DUPFD, fstat, stat, access,
  opendir/readdir/closedir) are rebound; each tries the real call first and steps in only on EPERM/EACCES. The handle fd
  is a read-only /dev/null. `NVMTL_DRM_XNU=1` forces the path in an unsandboxed process (tests). Log:
  `drm-xnu: sandbox-safe DRM path armed`, `drm-xnu: <app>: node 128 opened through NMXAccel`.
- Install: `scripts/macos-install-step102.sh` (backup /Library/NullMoth/step102-20261104T070755Z, relink, all probes +
  8 UUIDs verified twice). Undo: `sudo scripts/macos-install-step102.sh --undo`. Allow list unchanged (`!WindowServer`).

After the reboot:
1. Desktop as before (WindowServer unsandboxed: the plugin installs nothing there): picture, brightness, ~2.35 ms/frame.
2. Forced path, unsandboxed: `NVMTL_DRM_XNU=1 NVMTL_ENABLE=1` + tools/890m/build/nvmtltest -> compute correct, kernel log
   `drm-uc: pid … opened`.
3. Sandboxed: `open -n --env NVMTL_ENABLE=1 -a TextEdit` -> no `deny … /dev/dri`, plugin `vk: UP`, `drm-xnu: … opened
   through NMXAccel`; then a sandboxed browser GPU process.
4. Then the allow-list rungs (named apps, then `*`).

## Step102 boot (2026-11-04 14:13, NVIDIA 2.7.1 + Step102): desktop lag = WindowServer on the RTX; sandboxed Metal works

Lag root cause: WindowServer ran its Metal device on the RTX 5060 and copied every frame out through system memory
(`headless GPU: the display belongs to another GPU - IOSurfaces are copied out`); WindowServer used 7:16 CPU in its
first 8 min (~90 %, was ~27 %). The plugin's old WindowServer rule handed the compositor to NVIDIA whenever an NVAccel
exists (`the 1002 accelerator does not claim this process -- the NVIDIA display's accelerator must`). On 2.5.2 no
NVAccel was published, so only the AMD accelerator was asked (13:21 boot: one initWithAcceleratorPort, vendor 1002);
2.7.1 publishes a headless NVAccel (`NVAccelHeadless = Yes`, debug.nvaccel_headless 1) while NMXAccel owns the panel
(debug.nmxaccel_armed 1, nmxaccel_headless 0).
Not a DRM-node mix-up (owner asked: on Linux renderD128 was the dGPU, renderD129 the iGPU): on macOS NVIDIA has no
DRM node, `/dev/dri` holds only card0 + renderD128 = amdgpu 3.61.0 (tools/890m/build/drm-open). Same class of bug,
though: the default picked the dGPU by presence, not by who drives the panel.

Fix, plugin 5be0c73/497348c: in WindowServer, when NMXAccel's display pipe is armed and not headless, the AMD
accelerator claims the process and a headless NVAccel does not (`the panel is on NMXAccel's display pipe -- the
headless NVIDIA accelerator does not claim this process`); without an armed NMX pipe the old NVIDIA rule stays.
New `NVMTL_GPU=amd|intel|nvidia` picks the GPU for an app (first step of the per-app choice). Takes effect at the next
WindowServer start.

Step102 (sandboxed apps) verified on this boot, after two plugin fixes found with a sandbox-exec harness
(scratchpad h.c, libdrm + libdrm_amdgpu + the shim, no root):
- ea3daae: libdrm on macOS tells primary from render by `access("/dev/dri/card<minor>")`; the shim faked card128 as
  present, so the render fd looked primary and amdgpu_get_auth failed. Only render nodes (128..191) are faked now.
- bd6f2cb: WindowServer is sandboxed too (sandbox_check 1) but may open the node; the shim now arms only where
  `sandbox_check(pid, "file-read-data", PATH, "/dev/dri/renderD128")` refuses it (WindowServer 0, TextEdit 1), and
  there skips the refused real call (one violation report per process instead of one per open/stat).
Results: harness inside sandbox-exec: real open -1, IOKit open fd 3, drmGetNodeTypeFromFd 2, amdgpu_device_initialize
0 (3.61). TextEdit (App Sandbox, NVMTL_ENABLE=1 NVMTL_GPU=amd): `drm-xnu: sandbox-safe DRM path armed … this
process's sandbox refuses /dev/dri`, kernel `drm-uc: pid … opened /dev/dri/renderD128 for its sandbox`, `vk: UP …
AMD Radeon 890M Graphics (RADV STRIX1)`, G-SUB submits; no ring timeout/fault. Unsandboxed nvmtltest (NVMTL_GPU=amd)
still correct (2.39 ms); forced IOKit path in an unsandboxed tool reaches the device too.
Installed plugin: bd6f2cb (/Library/GPUBundles, re-signed 07e79c63). Apps without NVMTL_GPU now default to NVIDIA
when NVAccel exists (nvmtl_vk_vendor) - to be decided with the hybrid work.

Next boot: WindowServer on the 890M again (one initWithAcceleratorPort accepted, vendor 1002; NVIDIA port refused),
WS CPU back to ~27 %, desktop smooth; NVRM 2.7.1 GSP state.

## Step102b boot (2026-11-04 14:37): WindowServer back on the 890M

- WindowServer: AMD accelerator accepted (`GPU vendor 1002`, `vk: UP … RADV STRIX1`), NVIDIA port refused
  (`accelerator vendor 10de, but this process runs Metal on 1002: no second device`); no CoreDisplay abort.
- present-rate 10 s: 90.6 fps, flips submitted 906 / latched 905, fallback 0, fence 2.18 ms; WindowServer 31.6 % CPU
  over 10 s (~3.5 ms per frame) three minutes after boot with pkd/diagnosticd/Spotlight still busy (Step101b record:
  2.35 ms). Re-measure when idle.
- NVIDIA 2.7.1: `RmInitAdapter succeeded` (GSP up, 0000:62:00.0); bootguard "this start counts as good".
- No GPU timeout/fault/reset in the kernel log.

## Step103 (2026-11-04 14:42): allow list rung 1 - named apps on the 890M

- Plugin c78c5de: apps default to the low-power NMX GPU (890M); the RTX only with `NVMTL_GPU=nvidia` (with NVIDIA
  2.7.1's NVAccel present the old default was NVIDIA). WindowServer rule unchanged (follows the armed NMX pipe).
- `/Library/GPUBundles/nvmtl-allow.txt` = scripts/nvmtl-allow-rung1.txt: `!WindowServer` plus TextEdit, Preview,
  Calculator, Notes, Terminal, Safari, com.apple.WebKit.GPU. Previous list saved at ~/ga403-logs/nvmtl-allow.before-step103.txt.
  No reboot: apps pick it up at their next launch.
- Tests (fresh instances, ~10 s each): TextEdit, Calculator, Notes, Safari (all App Sandbox -> `drm-xnu … sandbox
  refuses /dev/dri`), Preview with a desktop picture (G-SUB up to 32 parts), Terminal (unsandboxed, plain /dev/dri):
  every one `vk: UP … AMD Radeon 890M Graphics (RADV STRIX1)`, NVIDIA port `no second device`. Kernel: no GPU
  timeout/fault/reset. Desktop meanwhile 96 fps, flips 481/481, fallback 0.
- Blocker found: Safari's WebKit GPU process cannot load the plugin at all - its sandbox
  (WebKit.framework/Resources/com.apple.WebKit.GPUProcess.sb) allows file-read of /Library/GPUBundles but
  file-map-executable only under /System/Library/{Extensions,Components,CoreServices,Video/Plug-Ins} and the cryptex
  frameworks (`deny(1) file-map-executable /Library/GPUBundles/NVMTLDriver.bundle/…`). WebGL in Safari therefore runs
  in software (a WebGL2 page reports OK). Fix needs the plugin on a path that profile can map (all on the sealed system
  volume) or another route; open item, see roadmap.
- Undo: put ~/ga403-logs/nvmtl-allow.before-step103.txt back (root 644).

## Step104 (2026-11-04 15:05): allow list to `*`, Chromium WebGL on the 890M, About This Mac VRAM

- Browsers: Chrome 155 and Edge (fresh profiles; names added: `Google Chrome Helper (GPU)`, `… (Aperitif)`,
  `… (Aperitif GPU)`, same for Edge) - WebGL renderer string `ANGLE Metal Renderer: AMD Radeon 890M Graphics
  (RADV STRIX1) (NVMTL over …)`: WebGL really runs on the iGPU. A profile whose first GPU init failed keeps
  `--use-gl=disabled`; a fresh profile (or chrome://gpu reset) clears it. One Chrome Helper SIGTRAP at 14:56 is in
  `liboptimization_guide_internal` (on-device model service, its own WebGPU/Metal use) - open, watch.
- Rung 2 (Finder, Dock, SystemUIServer, ControlCenter, NotificationCenter, System Settings, Mail, Photos, Music,
  Messages, Maps, Calendar, Reminders, FaceTime, QuickTime Player): all load RADV and open NMDR clients; Dock does
  not use Metal. NotificationCenter first said `vk: zero physical devices`: its sandbox allows reading
  /dev/dri/renderD128 but denies `file-ioctl` (`deny(1) file-ioctl … (_IO "d" 21)`), so the read-only gate did not
  arm drm-xnu. Plugin 820624d (fork desc-cache): arm when either file-read-data or file-ioctl is refused.
  Installed live (6ba40a36abc42bea); NotificationCenter then `node 128 opened through NMXAccel`, renders.
- Rung 3: `*` on (after `-strix-headroom-hold`), scripts/nvmtl-allow.txt = live list. 16 more apps launched
  (App Store, Books, Weather, Stocks, Home, Podcasts, TV, Freeform, Font Book, Activity Monitor, Console, Journal,
  Passwords, Clock, Contacts): all RADV, no crash report, no GPU timeout/fault/reset. Undo `*`:
  ~/ga403-logs/nvmtl-allow.before-step104-star.txt.
- Perf note: WindowServer 186-197 % CPU with ~30 apps open (Weather/TV/Memoji animating), ~50-70 % after closing
  them (boot baseline ~32 %). Sample: most `__ioctl` time is `drmSyncobjWait` (blocked, not spinning); CPU side is
  CoreAnimation layer prep. Follow-up: per-frame cost with many clients.
- Safari WebGL: still software. Research: the WebKit GPU process profile (cryptex
  StagedFrameworks/Safari/WebKit.framework/…/com.apple.WebKit.GPUProcess.sb) maps executables only from sealed
  /System paths and cryptex grafts; `/Library/GPUBundles` is read-only there. Tried: (1) WebGL out of the GPU
  process (`UseGPUProcessForWebGLEnabled` off, WKWebView harness) - WebContent denies the same file-map-executable,
  WebGL disappears; (2) binaries in `Cryptexes/Incoming/OS/usr/lib` (listed in the profile) - the cryptex dirs are
  read-only grafts (EROFS). Remaining route: a kernel-side exception in Sandbox's mmap check for the signed plugin
  files (own step).
- About This Mac "#display 19 MB": the 890M had no `model`/`VRAM,totalMB`, so it showed the IOName (`#display`,
  injected on purpose) and the framebuffer size (2880x1800x4). config.plist DeviceProperties
  PciRoot(0x0)/Pci(0x8,0x1)/Pci(0x0,0x0): `model`="AMD Radeon 890M", `VRAM,totalMB`=512, `VRAM,totalsize`=512 MiB
  (backup config.plist.vram-20261104-144958, occonfig clean). Verify after the next reboot
  (system_profiler SPDisplaysDataType).

## Step104b (2026-11-04 15:10-15:30): WindowServer CPU/memory check, Chrome on-device-model crash root cause

- WindowServer CPU is load, not drift: `present-rate.sh 10` with only the usual apps open = 88.1 fps, flips 881/882,
  fallback 0, WindowServer 26.0 % (~3 ms CPU per frame, Step102b 31.6 % at 90.6 fps). The 186-197 % / 50-70 %
  readings were with ~30 and ~15 animating clients. spindump (4 s, 400 samples): main thread spread over CoreAnimation
  layer prep, IOSurface queries/set-value, display-pipe transactions and NMXGPU ioctls; no single hot kernel frame.
  `__ioctl` samples in `sample` are mostly `drmSyncobjWait` (blocked). 208 NMX jobs/s at 88 fps (~2.4 per frame).
- Memory: `ps` RSS grows ~50 MB per open/quit round of 5 apps, but `vmmap -summary` across a round shows physical
  footprint flat at 1.2 GB (peak 1.6 GB), IOSurface resident unchanged (292.7 MB), MALLOC unchanged; NVMTL image
  census falls back (2001 -> 672 live MTLTextures). No leak; RSS counts shared pages. Footprint itself is high
  (MALLOC_MEDIUM ~509 MB resident) - optimization item.
- Chrome Helper SIGTRAP (14:56) = Chrome's on-device-model service (`liboptimization_guide_internal`, LiteRT
  `LiteRtTopKWebGpuSampler` via Dawn/WebGPU on Metal) ~3 min after browser start (GPU benchmark timer; reproduces on
  fresh profiles prof3/prof4, `Unexpected on_device_model service disconnect`). Its Dawn compute kernel fails in our
  AIR->SPIR-V translator, Dawn CHECKs on the failed pipeline:
  `native emitter: owned Load violates its pointer-pointee and value-type contract: pointer %556, of type %94
  (TypePointer Workgroup %71), points at %71 (TypeStruct %70), but the result type is %4 (TypeInt 32 0)`.
  Kernel shape: threadgroup memory as a kernel argument (`air.address_space 3`, `tint_struct_5 { array<half4,128> }`,
  1024 B), member pointer passed to a non-inlined helper, `<4 x half>` loads/stores on it. Input captured with
  `NVMTL_DUMP_FAILED_DIR` (scratchpad dump/56b1fd7e86828fa0-Kernel.ll). Simple MSL look-alikes (struct/half4/noinline
  helper) translate fine, so the trigger is narrower. Not a driver/kernel fault; WebGL is unaffected.
- Minimal repro (tools/890m/translator-repro/wg-helper-branch.metal, driver run.m: `xcrun clang -fobjc-arc -o run
  run.m -framework Metal -framework Foundation; NVMTL_DUMP_FAILED_DIR=<dir> ./run wg-helper-branch.metal`): a
  non-inlined helper that takes a `threadgroup` pointer (a member of the `[[threadgroup(0)]]` struct argument) and
  stores to it inside an `if` block. Fails for half4/float4/uint/half2 alike (Load or Store contract error, the
  access uses the struct-typed parameter pointer as a word pointer); the same code without the `if`, or written
  directly in the kernel, translates. Area: translator `native/emitter` raw Workgroup parameters
  (`concrete_vector_workgroup_raw_param_pointee` types the helper parameter as the struct, the raw word path in
  `memory/word_access.rs` assumes a raw uint array root). Fix needs a Rust toolchain (none on this Mac) or fork CI.

## Step105 (2026-11-04 15:30): Safari WebGL - StrixSbxMap staged (reboot pending), plugin walls found by simulation

- Design and test plan: docs/890M-ROADMAP.md, "Safari WebGL: Sandbox mmap exception".
- Baseline (WKWebView, tools/890m/webgl-probe.swift): GPU process on -> context created then lost (renderer null),
  `deny(1) file-map-executable …/NVMTLDriver`, `CFBundle: Error loading …NVMTLDriver`; GPU process off -> no context.
- Kernel: StrixSbxMap 0.1.0 (Lilu plugin, kexts/StrixSbxMap) routes Sandbox `_hook_file_check_mmap`; a deny becomes
  allow only for com.apple.WebKit.GPU + pinned path + matching cdhash of the registered code signature blob.
  Staged on the ESP by scripts/macos-install-strixsbxmap.sh (Kernel/Add, MinKernel 25.0.0, MaxKernel 25.99.99,
  8 pins; config backup config.plist.strixsbxmap-20261104-151851). Undo: `--undo`, boot-arg `-strixsbxoff`.
- Simulation (tools/890m/sbx-sim.m: WebKit GPU profile applied in-process + the 8 pins, one bounded render job):
  pins only -> plugin loads, `0 imports` rebound, no device. Needed in addition (each confirmed by removing it
  alone): `sysctl-read hw.pagesize_compat`, `file-read-data /dev/null`, `system-fcntl F_DUPFD_CLOEXEC`. With all
  three: `vk: UP`, MSL source -> in-process AIR->SPIR-V, pixel 0,255,0 PASS. `air-runtime/libzstd.1.dylib` is
  the 8th file (libLLVM loads it at the first translation). Safari's cryptex profile has the same three limits.
- Next: the three plugin fixes in the fork (page size from vm_page_size, a readable handle node, F_DUPFD_CLOEXEC in
  the drm-xnu shim), live install + `--refresh`, `scripts/macos-webgl-safari-test.sh sim` -> PASS before the reboot;
  after the reboot `scripts/macos-webgl-safari-test.sh live --ab`.

## Step105b (2026-11-04 15:35): plugin fb86bf5 - the three WebKit GPU sandbox walls fixed live, simulation PASS

- Fork desc-cache fb86bf5 (pushed to fork/desc-cache; `plugin/nvmtl_drm_xnu.h`, `plugin/nvmtl_vk.c`): page size from
  `vm_page_size` in the import rebinder and for RADV/libdrm `getpagesize`/`sysconf(_SC_PAGESIZE)` (armed processes);
  NMDR handle falls back to `/dev/random`; a refused `F_DUPFD`/`F_DUPFD_CLOEXEC` becomes `dup` + `F_SETFD`.
  Build = build/build_plugin.sh's clang line plus `-framework IOKit` (the script points at a removed ~/nvmtl-build
  tree), 336 warnings like the base. Artifact `nmx-plugin-890m/out/plugin-desccache-fb86bf5/NVMTLDriver`.
- Installed live (scripts/macos-nvmtl-plugin-install.sh, swap by rename): bundle binary f1ddbb96e93ed00a,
  CDHash ba5915fe200d165b31876e720557fac8f944184c; backup /Library/NullMoth/nvmtl-plugin-20261104T083340Z
  (6ba40a36abc42bea = 820624d). Undo: `sudo scripts/macos-nvmtl-plugin-install.sh --undo`, then `--refresh`.
- `scripts/macos-install-strixsbxmap.sh --refresh`: ESP pins updated to the new cdhash (kext not live yet).
- `scripts/macos-webgl-safari-test.sh sim` and `sim --safari`: armed with 27 imports, `vk: UP`, pixel 0,255,0 PASS
  with only the 8 pinned mmaps added to the profile. Control (`sbx-sim --none`) PASS. TextEdit (App Sandbox, fresh
  instance): node opened through NMXAccel, `vk: UP`, no crash. Not re-tested: Chrome/Edge WebGL (only the refused-call
  fallbacks changed; their GPU helper was unaffected), WindowServer (loads the new plugin at its next start).
- After the reboot: `scripts/macos-webgl-safari-test.sh live --ab`.

## Step104c (2026-11-04 15:45): translator fix live - Chrome's on-device-model kernels translate

- Root cause (translator, `passes/stage_input/mod.rs`): a threadgroup kernel argument with AIR
  `air.struct_type_info` was given a workgroup variable typed from that layout even when the emitter had chosen a
  raw uint-array word view for it (it does when a non-inlined helper reaches the argument through a raw cursor,
  e.g. an access inside a branch). The pass only splices the parameter id for the variable, so the word-indexed
  access chains became whole-struct pointers -> owned Load/Store contract failure -> Dawn aborts. Fix: keep the raw
  view whenever the emitter chose it.
- Branch `translator-wg-raw-param` on the fork (635cb43), based on upstream tag v2.7.1 (the live translator's
  release; exports identical). Regression test tests/workgroup_raw_param_layout.rs (fails without the fix).
- Checks: an A/B harness (old live dylib vs new, same process) over 87 cached app shaders = 82 byte-identical,
  5 failing in both (pre-existing, other stages), 9 previously failing kernels fixed (repro variants + Chrome's
  dump), 0 broken. Integration tests on pristine v2.7.1 vs fixed: identical per test case (165/166 ok, the same
  26 pre-existing failures from fixtures missing in the public tree), plus the new test.
- Toolchain: rustup minimal (cargo 1.99.1) in ~/.cargo, spirv-val from the spirv-tools crate (scratch build).
- Installed with scripts/macos-nvmtl-translator-install.sh (bundle swap, backup
  /Library/NullMoth/nvmtl-translator-20261104T084552Z, `--undo`): translator e399e64a4b86d757. New processes load it,
  WindowServer on its next start; the plugin keys SPIR-V caches by the dylib's sha256. Re-signing the bundle also
  re-signs NVMTLDriver (sha changes, code does not).
- Verified live: the repro MSL kernels and the tint-shaped kernel create pipelines; fresh Chrome profile (sandboxed)
  ran its on-device-model WebGPU benchmark at 15:49:13 - four `dawn_entry_point` compute pipelines created
  (4116-15912 B SPIR-V), no crash report, no service disconnect, nmx_timeouts 0.

## Step105c (2026-11-04 16:06): boot check - Safari WebGL on the 890M, translator, VRAM, WindowServer

First boot with StrixSbxMap, plugin fb86bf5 and the Step104c translator together.

- Safari / WKWebView WebGL: `scripts/macos-webgl-safari-test.sh live --ab` renders (ok=true, pixel 0,255,0,255) in the
  WebKit GPU process. That process logs `vk: UP in this Metal process — "AMD Radeon 890M Graphics (RADV STRIX1)"`,
  GPU vendor 1002, and opens DRM node 128 through NMXAccel (the sandbox refuses /dev/dri). The kext count goes
  allowed 8 -> 15 -> 22, stale=0. A/B: with `debug.strixsbx.enable=0` the `file-map-executable` deny on NVMTLDriver
  comes back and WebGL fails (shaderSource TypeError). The first run said LIVE FAIL only because WebKit reports
  unmasked_renderer "Apple GPU" even with the mask off. The verdict now also accepts the GPU process `vk: UP ... 890M`
  line (the log capture includes it), and the rerun prints LIVE PASS.
- Chrome 156: the GPU process has the 890M (`vk: UP ... RADV STRIX1`). No Chrome Helper crash report and no
  `Check failed` / on_device_model disconnect since the translator swap (the last crash report, 14:56, predates it).
- About This Mac: AMD Radeon 890M, 512 MB (ESP `model` + `VRAM,totalMB`).
- WindowServer: about 31-38 % CPU by `ps -o time=` deltas. The 148 % right after login was the decaying `ps %cpu`
  average.

## Step106 (2026-11-04 16:30): VCN decodes on the 890M (AV1/VP9 bit-exact); NMXPowerKeep for display sleep (reboot pending)

### VCN: first hardware video decode
- Kernel: NMXGPU already brings up vcn_v4_0_5 (ip block 8) and jpeg_v4_0_5 (9), loads `amdgpu/vcn_4_0_5.bin` from
  /Library/NullMoth/firmware and creates rings `vcn_unified_0` / `jpeg_dec_0` (step99 boot log). Nothing disables them.
- RADV (live NullMoth build, Mesa bffd919): queue families 0 gfx, 1 compute x4, 2 VIDEO_DECODE, 3 VIDEO_ENCODE, 4
  transfer. Device extensions: video_queue, video_decode_queue, decode_av1, decode_vp9, encode_queue, encode_av1,
  video_maintenance1/2. **No decode_h264 / decode_h265**: that build has the default `-Dvideo-codecs` (royalty-free
  only). Checker: a dlopen of libvulkan_radeon + vkGetPhysicalDeviceQueueFamilyProperties, no submission.
- ffmpeg 8.0 from source (`--enable-vulkan`, headers Vulkan-Headers 1.4.330, ~/develop/projects/radv-video/ffinst)
  with `DYLD_LIBRARY_PATH=/Library/GPUBundles/nvmtl VK_ICD_FILENAMES=/Library/GPUBundles/nvmtl/radeon_icd.json`,
  `-init_hw_device vulkan=vk -hwaccel vulkan` (ffmpeg's native av1 decoder has no software path, so frames mean VCN):
  AV1 conformance av1-1-b8-01-size-16x16 (8 frames) and 226x226, VP9 vp90-2-02-size-16x16 (10 frames) and
  vp90-2-00-quantizer-00 (352x288): per-frame md5 **identical** to the reference .md5 files, 0 decode errors, no ring
  timeout or VCN line in the kernel log. MacPorts is broken on Tahoe ("OS platform mismatch"), hence source builds.
- Next: RADV from source with `-Dvideo-codecs=all` (H.264/HEVC) plus the nmxmap change in source
  (~/develop/projects/radv-video, never installed over the live RADV until it passes the same checks), then a
  VideoToolbox decoder plugin for Safari/Chrome (route (a): CFPlugIn in /Library/Video/Plug-Ins; unproven that
  VideoToolbox picks a third-party hardware decoder for browsers). Netflix: Chrome/Edge (Widevine L3, software)
  already works; Safari's FairPlay hardware path needs Apple's own GPU/video stack and is out of reach.

### NMXPowerKeep: display sleep without a GPU suspend
Root cause of the one recorded display-sleep hang (Step33, "NMXGPU slow (SetState 0, 708 ms)", WindowServer timeout,
silent hang): NMXGPU registers power states 0/1 but never asks for one, so it follows its children. Display sleep
takes NMXAMDFB down, NMXGPU drops to 0 and runs a full amdgpu suspend (always the S3 path) under WindowServer and
NMXAccel. Fix without touching the binary-patched NMXGPU: NMXBacklight 0.2.0 adds `NMXPowerKeep`, an IOService that
matches NMXGPU, joins the power tree as its child and asks for state 1 (input requirement kIOPMPowerOn). Display sleep
is then the framebuffer's DPMS off/on only. System sleep still lowers the whole domain (stage 2, not tested; the
platform has no S3, only s0ix, and NMXGPU's suspend is the S3 path).
- Installed 2026-11-04 16:33 with `scripts/macos-install-nmxpowerkeep.sh` (backup /Library/NullMoth/nmxpowerkeep-*,
  AuxKC relinked, still holds NMXGPU/NMXAccel/NMXAGDC/NMXBacklight after 45 s). Undo: `--undo`; off: `-nmxkeepoff`.
- After the reboot: `ioreg -r -c NMXPowerKeep` shows `PowerKeep,State = 1`, then `scripts/macos-displaysleep-test.sh`
  (display off 20 s, woken by `caffeinate -u`, PASS = no NMXGPU setPowerState(0), no WindowServer timeout).

### Step106b (16:55): RADV from source with all video codecs - H.264/HEVC decode on the VCN
- Build (~/develop/projects/radv-video, not installed): Mesa bffd919 + NullMoth mesa-macos.patch (fork, PolyForm, kept
  out of this repo) + `radv-nmxmap.patch` (the Step33d binary patch as source: drmNmxMmap/drmNmxMunmap in
  radv_amdgpu_winsys_bo_map/unmap/destroy under `__APPLE__`), `-Dvulkan-drivers=amd -Dvideo-codecs=all -Dllvm=disabled`,
  glslang vulkan-sdk-1.4.363.0 built for it, libdrm b97cbde + NullMoth patch for headers only. The dylib links the live
  /Library/GPUBundles/nvmtl libdrm (it has the minor patch), exports the same three ICD symbols as the live one, sha256
  3b964732...; it still links /opt/local libelf and libz, so it is a test build, not an install candidate yet.
- Device extensions add VK_KHR_video_decode_h264/h265 and encode_h264/h265 to the av1/vp9 set.
- Gotcha: `DYLD_LIBRARY_PATH=/Library/GPUBundles/nvmtl` makes dyld resolve the loader's dlopen of the new ICD by leaf
  name to the LIVE libvulkan_radeon.dylib. Use a directory with only the loader symlinked, plus `VK_DRIVER_FILES`.
- ffmpeg, 1280x720 30 fps, 60 frames, clips made with VideoToolbox's software encoder (`-allow_sw 1`; VT has no hardware
  encoder here): H.264 High and HEVC Main decoded with `-hwaccel vulkan` give per-frame md5 identical to ffmpeg's
  software decoder. With `-hwaccel_output_format vulkan` (no software fallback): H.264 60 frames in 0.23 s (user CPU
  0.031 s, ~260 fps), HEVC 0.19 s (user 0.026 s). No amdgpu timeout/fault in the kernel log.
- Codec status on the 890M: H.264, HEVC, VP9, AV1 decode all work through Vulkan Video. Left for browsers: the
  VideoToolbox side (Safari/Chrome only decode through VideoToolbox), and a RADV build that can replace the live one
  (no /opt/local deps, then the WindowServer/app checks) before mpv/IINA can use it from the bundle.

### Step106c (16:58): display sleep PASS with NMXPowerKeep
Boot 16:53: NMXBacklight 0.2.0 loaded, `NMXPowerKeep: holding NMXGPU on while the system is awake`, NMXGPU
IOPowerManagement ChildrenPowerState=1 CurrentPowerState=1. `scripts/macos-displaysleep-test.sh`:
- 20 s dark (16:55:22-16:55:42) and 90 s dark (16:56:35-16:58:05; the Step33 hang came 23 s after the display slept):
  pmset "Display is turned off/on", WindowServer `displayWillSleepWithImages` -> `displayDidWake`, NMXAccel
  `displayModeDidChange` -> `enableAccelerator()` on wake, NVMTL keeps submitting, no NMXGPU setPowerState, no
  amdgpu error, `PowerKeep,Changes` stays 1 (the GPU never left state 1). The panel comes back.
- One CoreAnimation `timed out fence` while dark in the 20 s run (a frame that waited on the dark pipe); it recovers.
  The test script counts it as a note, and FAILs only on another WindowServer timeout, a missing displayDidWake, a
  NMXGPU state 0 or NMXPowerKeep not at 1. Its kernel predicate now uses senderImagePath (process == "kernel" matched
  nothing).
Gate item 2 (sleep/wake): display sleep done. System sleep and lid close are stage 2: NMXGPU's suspend is the S3 path
on an s0ix-only platform, NMXAccel/NMXGPUFB have no wake handling; not tested.

## Step107 (2026-11-04 17:22): system sleep on the s0ix path - NMXGPU suspends amdgpu as suspend-to-idle (reboot pending)

Platform, checked on this machine: AppleACPIPlatform logs `ACPI: sleep states S4 S5`; the DSDT renames `_S3` to `XS3`
(`SS3 = Zero`); SSDT-28 has `\_SB.PEP` (AMDI000A / PNP0D80) with the Modern Standby _DSMs (AMD e3f32452..., mask 0x03
= device constraints only; Microsoft 11e00d56..., mask 0x1F9 = display off/on, entry/exit, MS entry/exit). The owner
confirms Linux on this laptop only offers s2idle. So S3 is out; the model is s0ix (the GPU keeps power).
- NMXGPU's suspend (only reached on system sleep since NMXPowerKeep) invoked power_suspend with POWER_STYPE_FW_SUSPEND
  (2) -> pm_suspend_target_state = PM_SUSPEND_MEM -> amdgpu S3 path (full teardown, PrepareMp1ForUnload, cold re-init
  on resume over powered hardware). The live `amdgpu_acpi_is_s0ix_active` (0x7e40) is the CONFIG_AMD_PMC build: true
  when APU + target TO_IDLE + asic >= RAVEN + gfxoff + FADT LOW_POWER_S0 (flags bit 21, `testb $0x20, 0x72(FADT)`).
  `linux_handle_power_suspend_event` maps stype 3 to TO_IDLE (1).
- `scripts/nmx-s0ix/patch_s0ix.py`: the two `mov $0x2,%esi` at 0x6de44c / 0x6de45d in nmx_port_power become `$0x3`
  (SUSPEND_TO_IDLE). NMXGPU 3e1b6619 -> 2a1bb264. Cave registry unchanged (an immediate, no cave).
  If the FADT bit or gfxoff were missing, amdgpu logs "BIOS has not been configured for suspend-to-idle" and takes
  the S3 path as before; neither is verifiable from Tahoe (no FACP in ioreg), the log answers it.
- NMXBacklight 0.3.0: NMXPowerKeep also logs the system sleep/wake timeline (`registerPrioritySleepWakeInterest`,
  `PowerKeep,SysSleeps/SysWakes/LastWakeMs`), never delays sleep. Boot-arg `nmxkeep_dsleep=0` releases the hold, so
  display sleep exercises NMXGPU's suspend/resume with the system awake (harness).
- Installed 17:22 with `scripts/macos-install-step107.sh` (backup /Library/NullMoth/step107-bk-*, all cave --check-kc
  present, AuxKC holds the four kexts after 45 s). Undo: `--undo`.
- Test after the reboot: `scripts/macos-syssleep-test.sh 60` (pmset hibernatemode/standby/powernap/tcpkeepalive/
  proximitywake/womp 0, saved first, `restore` puts them back; en4 down because itlmt7925 has no power handling; RTC
  wake). Expect in the log: `NMXPowerKeep: system will sleep`, `NullMoth GPU: setPowerState(0)`, suspend returned 0,
  then resume. Not done yet (stage 2c): NMXGPUFB familyDidWake and the NMXAccel submit gate, LPS0 _DSM + SMU OS_HINT
  for real S0i3 residency, itlmt7925 power handling.

## Step108 (2026-11-04 17:27): VideoToolbox decoder plugin probe - VTStub installed in /System (reboot pending, with Step107)

Findings (tools/890m/vtstub, built and tested without root first):
- Registration: Info.plist `CMClassImplementations`, one dict per codec: `CMClassID` com.apple.videotoolbox.videodecoder,
  `CMFactoryFunction` (exported C symbol), `CMMatchingInfo` {VTCodecType, VTIsHardwareAccelerated, VTRating, ...}.
  Higher VTRating wins (AppleH264SW 200, AppleVideoDecoder 400). Factory: `CMDerivedObjectCreate` with a
  {CMBaseClass, VTVideoDecoderClass} vtable (layout read from AV1DecoderSW.bundle); frames go out through
  `VTDecoderSessionEmitDecodedFrame`.
- Registered in process with {hardware: true, rating 1000}: `VTIsHardwareDecodeSupported` turns 1 for avc1/hvc1/av01
  (vp09 after `VTRegisterSupplementalVideoDecoderIfAvailable`, which Chrome and WebKit call), and
  RequireHardwareAcceleratedVideoDecoder picks the stub (60/60 stub frames, H.264 and HEVC).
- /Library/Video/Plug-Ins is scanned with a code requirement (`anchor apple ... info[CFBundleIdentifier] =
  "com.apple."*`, FigRegistry option 1): ad-hoc or Developer ID plugins are dropped silently. /System/Library/Video/
  Plug-Ins is option 0 (no check). Bundle decoders run in VTDecoderXPCService (disable-library-validation, no app
  sandbox), not in the app.
- Gate: the stub only draws a solid colour, so its factory refuses (-12906) unless `/tmp/vtstub.on` exists; then
  VideoToolbox falls back to Apple's decoders (checked: no flag + enable-hw -> real frames; flag + require-hw -> stub
  colour). Side effect while installed: VTIsHardwareDecodeSupported says 1 for the four codecs even with the flag off.
- Installed 17:27 with `tools/890m/vtstub/install.sh --system` (system volume /dev/disk1s4 at
  /System/Volumes/Update/mnt1, new boot snapshot blessed). Undo: `install.sh --undo --system` (next boot).
- After the reboot: `touch /tmp/vtstub.on`, `log stream --predicate 'subsystem == "com.ga403wm.vtstub"'`, then
  `build/vtprobe --supplemental --require clips/t-h264.mp4` (out of process this time), QuickTime Player, Safari and
  Chrome on `test.html`; note which process loads the stub (VTDecoderXPCService or the browser's GPU process), then
  `rm /tmp/vtstub.on`. Next if it loads: a real decoder in the stub's place backed by RADV Vulkan Video (Step106b).

## Step108b / Step107b: post-boot results (2026-11-04)

**VTStub (gated, /System/Library/Video/Plug-Ins):**
- VTDecoderXPCService loads the ad-hoc plugin from /System.
- Flag off (no /tmp/vtstub.on): Apple's decoder runs.
- Flag on with require-hw: stub frames come out for H.264 and HEVC.
- Safari: H.264 runs in-process in com.apple.WebKit.GPU (700+ frames); HEVC goes through VTDecoderXPCService.
- Chrome: avc1 and hvc1 go through VTDecoderXPCService.
- So a real decoder must work in both hosts. Flag removed after the test.

**System sleep, first authorized run (17:36:30):** the machine did not sleep. This was not a platform limit.
- IOPMrootDomain started ON_STATE->SLEEP_STATE ("sleep reason Software Sleep"). `tellChangeDown::userActivityAtSleep 2` (password typed right before) turned it into a dark-wake capability change, f->9.
- In dark wake (`sleepASAP 1`), powerd's `darkwakelinger` InternalPreventSleep held it ("System sleep prevented by kPMCPUAssertion").
- At +1.6 s a UGREEN BLE Mouse HID event caused "Requesting full wake due to dark wake activity tickle", 9->f.
- NMXGPU's s0ix path never ran (NMXPowerKeep SysSleeps 0).
- Fixes in scripts/macos-syssleep-test.sh:
  - wait 10 s after the password before `pmset sleepnow`;
  - hands off all input during the test;
  - log the PMRD START/prevented/full-wake lines;
  - Wi-Fi no longer touched (owned by the AWDL branch).

**System sleep, hands-off rerun (17:46:00):**
- The input problem is gone: powerd's darkwakelinger ended at 17:46:30.
- The only blocker left is `System sleep prevented by kPMPCIUnsupported`. It held the machine in dark wake until the RTC wake at 17:47:10.
- This is the platform's "can't sleep" flag (AppleACPIPlatform/PCI host bridge, assertion `com.apple.pci.hostBridge.preventSleep`). It matches the ACPI table having no _S3 (`ACPI: sleep states S4 S5`, DSDT `XS3`).
- The USB device assertions (the owner's USB tether, level 255) only keep USB ports powered. They do not block sleep.
- A run before this one was spoiled by the script: it restarted `caffeinate -u` during dark wake. The script now waits past the RTC wake first.
- Next: give macOS an `_S3` (SSDT) so the root domain reaches SLEEP_STATE. Then replace the final PM1 S3 write with the s0ix entry: LPS0 _DSM fn 3/7/5 and the SMU OS_HINT, then idle until a wake event.

## Step109: S0 sleep through Apple's own deep idle path (2026-11-04, installed, reboot pending)

**Finding:** AppleACPIPlatform (BootKC, tools/kc.py) already has a complete S0 sleep path. It is only enabled by an ACPI object:
- `initPlatformPowerManagement` evaluates `\_SB.LPS0`. An Integer 1 sets the deep idle flag (+0x16d) and publishes `IOPMDeepIdleSupported` on the root domain. `\_GPE.LXEN` = 1 would also enable the wake GPE methods (not used).
- `resolveSystemStateSupport`: the sleep state mask starts as 0x39 and `AcpiCacheSleepTypeData` drops S3 here. Without the deep idle flag (or a debug flag) S0 is cleared too. "Can sleep" (+0x16c) = S0 or S3.
- `queryPlatformCanSleep` returns 0xe00002e2 while +0x16c is 0. That is the `kPMPCIUnsupported` seen in Step107c.
- `sleepPlatform`: S0 calls `acpi_idle_kernel(callback)`, S3 calls `acpi_sleep_kernel`. The S0 callback clears ACPI status, disables all GPEs, enables the wake GPEs and calls `picSleepWake(2)`. `acpi_idle_kernel` then calls `pmCPUHalt(PM_HALT_SLEEP)` and rebases time on return.

**Blocker in the kernel:** `pmCPUHalt` with type 3 and no `pmDispatch` runs `cli; wbinvd; hlt` and panics ("back from Halt") if it ever returns. Nothing registers `pmDispatch` on AMD (`machdep.xcpm.mode: 0`). So LPS0 alone would hang the first sleep.
- `pmKextRegister(0x66, dispatch, callbacks)` is exported in com.apple.kpi.unsupported.
- With `dispatch == NULL` it only fills the callbacks.
- A wrong version, or a second registration, panics.
- All 67 kernel loads of `pmDispatch` check the field before calling it, including `thread_tell_urgency` (+0xc8, checked at entry). So a table with only `pmCPUHalt` (+0x48) is safe.

**Changes:**
- `acpi/SSDT-S0IDLE.dsl` → `efi/OC/ACPI/SSDT-S0IDLE.aml`: 69 bytes, hand-assembled by tools/mk_ssdt_s0idle.py (no iasl). `Method (\_SB.LPS0) { If (_OSI ("Darwin")) Return (One); Return (Zero) }`. Config ACPI Add entry 8.
- `kexts/StrixS0ix` 0.1.0, matched on PEP (AMDI000A):
  - Gated on Darwin 25, MONITORX, and the lcpu state at +0x58 reading RUN, checked through the callbacks before registering.
  - Registers `pmCPUHalt`:
    - Non-boot CPUs, or an unarmed boot CPU: `lcpu.state = HALT`, then `wbinvd; hlt` forever, as stock.
    - Armed boot CPU: MONITORX/MWAITX C1 (IRQ break with IF=0, 0.25 s TSC timer), polling PM1 (0x800) and GPE0 (0x820/0x824, enabled bits only) until a wake event. It also stops on a long run of immediate breaks (0x80000000) or the `s0ix_maxsec` safety limit (default 300 s, 0x40000000).
  - Top-level power child of the root domain. On real sleep (state 0) it runs PEP MS _DSM 3/7/5 (Microsoft GUID, rev 0) and arms the idle. On wake (state 1) it runs 6/8/4 and publishes S0ix,* (LastWakeEvent, LastIdleMs, IdleEntries).
  - Restart and power-off never arm.
  - No hook: holds a CPU assertion, so sleep is blocked rather than hung.
  - Boot-args: `-s0ixoff`, `-s0ixnodsm`, `s0ix_maxsec`.
- `scripts/macos-install-step109.sh` (`--undo`): kext into the AuxKC (all NMXGPU caves re-checked), SSDT to the ESP, config entry, and backups in /Library/NullMoth/step109-bk-* and `config.plist.pre-step109`.

**Not yet:** the SMU OS_HINT (amd_pmc) for S0i3 residency. NMXGPU's s0ix suspend (Step107) gets its first real run on this sleep.

**Test after the reboot:**
1. `ioreg -r -c StrixS0ix` should show HaltHook Yes and DsmMask 0x1f9. The boot log should say `ACPI: sleep states S0 S4 S5`.
2. `scripts/macos-syssleep-test.sh 60`, hands off. Expect PMRD `ON_STATE->SLEEP_STATE` and `S0ix,LastWakeEvent` 0x400 (RTC).

**Recovery if it hangs:**
- Power button; if that does nothing, hold power 10 s.
- Boot with `-s0ixoff`, or restore `config.plist.pre-step109` from Linux.

## Step109b: first boot with SSDT-S0IDLE, icon fix (2026-11-04)

**SSDT-S0IDLE works.** The boot log reads `ACPI: sleep states S0 S4 S5`, and the root domain has `IOPMDeepIdleSupported = Yes`.

**StrixS0ix 0.1.0 refused its hook:** "lcpu state at +0x58 is 5, not RUN".
- The enum is OFF 0, HALT 1, NONSCHED 2, PAUSE 3, IDLE 4, RUN 5 (I had RUN = 4). The offset was right.
- The safety path worked: the CPU assertion `com.ga403wm.strixs0ix.no-halt-hook` blocks sleep, so there was no hang. DsmMask 0x1f9, MwaitIBE Yes.
- Tahoe publishes no "ACPI Tables" property, so 0.1.0 fell back to 0x800/0x820. Those happen to be correct.

**StrixS0ix 0.1.1:** RUN = 5, FADT read through `IOACPIPlatformDevice::getACPITableData("FACP")`. Installed with macos-install-step109.sh; reboot pending.

**Broken icons in the Dock, System Settings and menus, and high iconservicesagent CPU.**
- Cause: since Step104 (`*`), iconservicesagent renders Tahoe layered icons through RenderBox on the translator. The translator lacks three things RenderBox needs:
  - visible functions: "function constants: re-translate FAILED: native emitter: visible function "custom_fn" is called on a live path but no linked function supplies it";
  - `[[color(n)]]` framebuffer fetch (descriptor binding 192);
  - buffer textures: `vkCreateImage(buffer texture) -> -1000158000`.
- Result: 886 RenderBox `precondition failure` errors in 13 minutes, and wrong icons in the cache.
- Fix:
  - `-iconservicesagent` in scripts/nvmtl-allow.txt and /Library/GPUBundles/nvmtl-allow.txt (backup /Library/NullMoth/nvmtl-allow.before-step109b.txt). Its output is cached, so it draws on the CPU.
  - Icon caches cleared (/Library/Caches/com.apple.iconservices.store and the user com.apple.iconservices), then iconservicesagent, iconservicesd, Dock and Finder restarted.
  - Since then: no NVMTL device in iconservicesagent ("denied by list"), and 0 RenderBox precondition failures.
- Real fix: those three translator features, in the NullMoth translator fork, not here.

**strix-headroom-hold uninstalled (2026-11-04 22:15).** The LaunchAgent had no Metal device: it is denied in the allow list since Step35. So it exited with status 1, and launchd restarted it about 6 times a minute (123 denials this boot). The workaround is obsolete: since Step104 WindowServer composites on the 890M, and this boot ran fine without the agent. It was removed with `scripts/macos-strix-headroom-hold.sh uninstall`; the binary is left in ~/Library/Application Support/StrixHeadroomHold, and `install` brings it back. The `-strix-headroom-hold` deny line stays.

## Step109c: iconservicesagent back on the 890M (2026-11-04)

Done in the session "Translator: RenderBox features for icons":
- **Translator:** a live visible-function call is deferred to pipeline link (#1). Its rbx test arms are dbb55f7 on the translator fork.
- **Plugin**, branch `plugin-renderbox` cut from desc-cache fb86bf5 and **not merged**:
  - df1c9b8: framebuffer fetch (#2), ported from upstream; WindowServer is unchanged unless `NVMTL_FBFETCH_WS=1`.
  - e3d8399: an aligned shadow image when a buffer texture's row pitch is not a multiple of 256 B, which RADV refuses (#3). It keeps the explicit layout; `NVMTL_NO_BUFTEX_SHADOW=1` turns it off.
  - e1d1e26: the 913ade5 port (a buffer texture accepts any view format of the same size).
- **Live plugin** is now 9d816dc7. The backup of a5dc97e2 (fb86bf5) is at /Library/NullMoth/nvmtl-plugin-20261104T153710Z. To go back: `macos-nvmtl-plugin-install.sh --undo`, then `macos-install-strixsbxmap.sh --refresh`.
- **Results:**
  - rbx 17/17.
  - iconservicesagent: 0 precondition failures, 0 failed buffer textures.
  - Icons are pixel-identical to the GPU run and differ from the CPU render only at thin rim edges.
- **Allow list:** the `-iconservicesagent` deny line is removed (this commit).
- **Open:**
  - fetch draws that use triangle strips are not split per triangle (only triangle lists are);
  - merging `plugin-renderbox` into desc-cache is the owner's decision.

**Merged (owner, 2026-11-04):** `plugin-renderbox` was fast-forwarded into desc-cache. desc-cache is now e1d1e26 (df1c9b8, e3d8399, e1d1e26 on top of fb86bf5) and pushed to the fork. The live plugin 9d816dc7 is the build from e1d1e26.

## Step109d: first real S0 system sleep, and the hang after wake (2026-11-04 22:49)

Test: `scripts/macos-syssleep-test.sh 60`, StrixS0ix 0.1.1 live (hook on). Logs: ~/ga403-logs/syssleep-20261104-224925.

**Sleep and wake themselves work.**
- PMRD `ON_STATE->SLEEP_STATE (9->0)` FINISH at 22:50:02. The wake at 22:50:35 is "Wake from Deep Idle [CDNVA] : due to RTC".
- StrixS0ix: idle 32430 ms in the MWAITX loop, wake event 0x400 (RTC), 130 loops, _DSM 3/7/5 and 6/8/4 all 0.
- NVRM: standby took 6477 ms, resume took 902 ms, and the GPU answered.
- powerd reports `WakeTime: 1.064 sec`.

**Then the machine hung and needed a hard restart.** At 22:57:17 the kernel panicked: "userspace watchdog timeout: no successful checkins from WindowServer (2 induced crashes) in 120 seconds".
- CoreAnimation logged `timed out fence` at 22:50:35.997, 45.1 and 46.0.
- From about 22:50:47, ws_main_thread never ran again.
- Spin reports (Kernel-2026-11-04-225717.panic, WindowServer_...225127/225205 .spin), symbolicated against SystemKernelExtensions.kc: `IOFramebufferUserClient::externalMethod -> IOFramebuffer::extGetCurrentDisplayMode -> _extEntry+0x108 -> IOGraphicsControllerWorkLoop::sleepGate -> lck_mtx_sleep`.

**Root cause: NMXAMDFB's pagingState is never set again after a system sleep.** Disassembly of IOGraphicsFamily 600 shows the mechanism.
- `_extEntry` sleeps on `this+0x188` (fServerConnect) until one of these holds: `[this+0x199] & 0x20` (pagingState, bit 13 of the bitfield word 0x198, as in the MacKernelSDK header), a global, or a helper call.
- `IOFramebuffer::systemWork+0x30d` clears pagingState on system sleep, for every framebuffer.
- It is set again only in two places:
  - `IOFramebuffer::open+0x701`;
  - `IOFramebuffer::handleEvent`, for kIOFBNotifyDidWake/DidPowerOn (4) with info != NULL (and event 8).
- `handleEvent` first checks that the calling thread owns the controller's gate (`+0x84`). On any other thread it does nothing.
- The normal path is `IOFramebuffer::setPowerState`. It stores the pending state in bits 8-11 of 0x198, sets pendingPowerChange (0x1000), calls `IOFBController::startThread`, and returns 45 s. Then `checkPowerWork` calls `setAttribute('pwrs')` on the controller thread, and the event path sets pagingState.
- NMXAMDFB (nmxaccel gpu-port/xkpi/xnu/nmx_fb.cpp) overrides setPowerState and acks at once. Its `handleEvent(kIOFBNotifyDidPowerOn)` runs on the PM thread with info NULL, so it is a no-op.
- So after the first system sleep pagingState stays clear, and WindowServer waits forever. The fence timeouts are a side effect: the compositor stalls behind the main thread.
- Display sleep (Step106c) never clears pagingState, which is why it passed.
- NVRMFB hit the same bug and fixed it with `familyDidWake` (nmxaccel 5583ee9, PR #182).

**NMXGPU did not suspend at all.** "suspend returned 0 in 0 ms", with "Power consumption will be higher as BIOS has not been configured for suspend-to-idle".
- xkpi logs "no FADT; ACPI power flags read as zero". Tahoe does not publish the FACP table property, the same issue StrixS0ix hit, so amdgpu sees LOW_POWER_S0 = 0.
- With neither s0ix nor S3 active, amdgpu skips suspend and resume, and the GPU stays powered with its state intact.
- This is harmless for the hang, but it costs power during sleep. The fix (xkpi FADT read through getACPITableData, then the amdgpu s0ix path) is a separate step.

## Step110: NMXBacklight 0.4.0, the system wake work for NMXAMDFB (2026-11-04, installed, reboot pending)

NMXBacklight already gives the NMXAMDFB object a private vtable copy (getAppleSense). 0.4.0 also wraps the **setPowerState** slot:
- **Slot:** taken from NMXBacklight's own vtable, where it still holds `IOService::setPowerState`. The framebuffer's slot must point into NMXGPU's text, otherwise the feature stays off.
- **Sleep tap:** `addFramebufferNotification` on the framebuffer counts kIOFBNotifyWillSleep. Only IOGraphics' system work sends it here.
- **On power-on after a system sleep with pagingState still clear:** a command gate on the framebuffer's workloop runs the wake work, as NVRMFB does:
  - DidWake(true);
  - DidWake(false) once per WillSleep(false);
  - DidPowerOn(false);
  - pagingState = 1;
  - `commandWakeup(&fServerConnect)`.
- **Fallback:** a thread call 3 s after kIOMessageSystemWillPowerOn / HasPoweredOn does the same, if the framebuffer is powered but was never told. HasPoweredOn was not logged in Step109d.
- **Checks:** the fServerConnect offset (0x188) is checked against the header.
- **Off switch:** boot-arg `-nmxfbwakeoff`.

Install: `scripts/macos-install-step110.sh` (`--undo`). It relinks AuxKC and checks every NMXGPU cave, StrixS0ix and the 0.4.0 string, again after 45 s. It is installed; the backup is /Library/NullMoth/step110-bk-20261104T161253Z.

After the reboot:
1. Boot log: `NMXBacklight: ... paging wake on (setPowerState slot N)`, and `ioreg -r -c NMXBacklight -d 1 | grep PagingWake`.
2. `scripts/macos-syssleep-test.sh 60`, hands off. Expected:
   - `NMXBacklight: paging wake (framebuffer power-on, #1): ... WindowServer woken`;
   - no `timed out fence`;
   - WindowServer alive;
   - the desktop redraws.
3. If it hangs again: hold the power button, then run `scripts/macos-syssleep-test.sh collect "<start>"` and check the spin/panic reports.

### Step110 result (2026-11-04 23:37): system sleep and wake PASS, no hang

The boot armed the wake work: `paging wake on (setPowerState slot 253)`.

Test: `macos-syssleep-test.sh 60`. The script itself was cut short when the Claude app restarted during the sleep; the logs below were read by hand.
- Sleep at 23:37:57. StrixS0ix idled 28269 ms in the MWAITX loop; wake event 0x400 (RTC), _DSM all 0.
- At 23:38:33.029, right after the framebuffer power-on: `NMXBacklight: paging wake (framebuffer power-on, #1): DidWake true + 1 x false, DidPowerOn 0x0, paging on, WindowServer woken`.
- `NMXPowerKeep: system has powered on` was logged. It was missing in Step109d.
- The lock screen came up; the owner logged in and got the desktop back. WindowServer stayed alive, with no watchdog report and no panic.
- A few `timed out fence` lines remain, but one is from 23:37:51, before the sleep. That is the driver's existing fence issue, not the sleep path.

Still open: NMXGPU skips suspend because xkpi reads FADT as zero, so the 890M stays powered in S0. Next steps: the xkpi FADT read, then SMU OS_HINT for S0i3 residency, and `macos-syssleep-test.sh restore` for pmset when the sleep tests are done.

## Step111: StrixS0ix 0.1.2 hands the live FADT to xkpi, so amdgpu really suspends in S0 sleep (2026-11-04, installed, reboot pending)

**Root cause of "no FADT; ACPI power flags read as zero".**
- xkpi (nmxaccel gpu-port/xkpi/xnu/nmx_platform.cpp, `copy_acpi_tables`) reads every ACPI table from the **first** registry entry that has an "ACPI Tables" dictionary.
- Tahoe's platform expert publishes none. The only one is StrixVFCT's codeless IOResources node (Step26), which holds VFCT only.
- So `nmx_acpica_init` found no FACP and zeroed `AcpiGbl_FADT`.
- amdgpu then saw ACPI_FADT_LOW_POWER_S0 clear, logged "BIOS has not been configured for suspend-to-idle", and skipped suspend and resume ("suspend returned 0 in 0 ms"). The 890M stayed fully powered through S0 sleep (Step109d/110).

**Fix: StrixS0ix 0.1.2.**
- It already reads the live FACP through `IOACPIPlatformDevice::getACPITableData`.
- It now adds that FACP to the first "ACPI Tables" dictionary (StrixVFCT's), or publishes one on itself when there is none.
- It logs the FADT flags (`S0ix,FadtFlags`) and LOW_POWER_S0 (bit 21).
- It runs before NMXGPU's SYSINIT: in the Step110 boot it was 64 ms earlier. If NMXGPU ever wins that race it just sees the Step110 state.
- `-s0ixnofacp` skips it.
- With the flag visible, the NMXGPU s0ix cave (Step107, stype 3) finally makes amdgpu take its s0ix path: PSP/GFX/MES/SDMA kept, SMU D3Entry, resume without firmware reload.
- This path is new on this machine, and its resume is the risk.

**Install:** `scripts/macos-install-step111.sh` (`--undo`). Backup: /Library/NullMoth/step111-bk-20261104T164602Z.

**After the reboot:**
1. Boot log: `StrixS0ix: FACP (... LOW_POWER_S0 set) published for xkpi: IOService`, and **no** "no FADT".
2. `macos-syssleep-test.sh 60`, hands off. Expected:
   - no "BIOS has not been configured";
   - NMXGPU suspend and resume take real time (not 0 ms);
   - paging wake;
   - desktop back.
3. **If the wake hangs (GPU resume):** hard restart and boot with `-s0ixnofacp` (or `--undo`). That keeps the Step110 behaviour, where sleep works with the GPU powered.

### Step111 result (2026-11-05 08:50): amdgpu really suspends; sleep entry is slow; fans keep running

Boot: `StrixS0ix: FACP (276 bytes, flags 0x2085bd, LOW_POWER_S0 set) published for xkpi: IOService`. No "no FADT" and no "BIOS has not been configured" line.

Test: `macos-syssleep-test.sh 60`. Logs: ~/ga403-logs/syssleep-20261105-084946.
- **GPU now suspends and resumes for real.** NMXGPU suspend took 614 ms (was 0 ms); resume took 323 ms, with "SMU is resumed successfully!".
- **Wake was clean.** Paging wake ran (08:50:57.013), the desktop came back, and WindowServer stayed alive. StrixS0ix: idle 16466 ms, wake event 0x400 (RTC).

**What the owner saw.** The display went off, the keyboard LED stayed on for a while, then started the "breathing" sleep pattern like on Linux, and the fans kept running.

**Sleep entry timeline.**

| Time | Event |
|---|---|
| 08:50:02 | display off and dark wake (f->9); sleep held back by a CPU assertion (cloudd NSURLSession tasks, about 13 s) |
| 08:50:15 | Entering Sleep (`9->0` START) |
| 08:50:33 | kernel drivers are told; pmset reports "apsd is slow (17518 ms)" and "bluetooth.sleep is slow (1517 ms)" |
| 08:50:33.099 | StrixS0ix _DSM 3/7/5. This is the moment the EC starts the keyboard "breathing", about 31 s after the display went off |
| 08:50:40 | NVRM standby done (6935 ms, saving VRAM); then the MWAITX idle starts |

apsd (push notifications) waits about 17.5 s for its connection to close. That is likely the USB-tethered network in use while Wi-Fi is on its own branch. It is user space, not our driver path.

**Fans.** The EC gets the Modern Standby _DSM calls (the LED pattern proves it), but the SoC never reaches S0i3:
- no SMU OS_HINT or S0i3 request is sent (Linux `amd_pmc` does this);
- the RTX stays in RM standby, not D3cold;
- only CPU0 sits in MWAITX, while the other cores HLT.

So the package keeps drawing power and the fans keep running. Next steps for real low-power sleep:
- the `amd_pmc` OS_HINT through the SMU mailbox, with S0i3 residency read back from the SMU;
- dGPU D3cold during sleep;
- optionally, shorten the apsd delay.

## Boot-time audit and `-v` removed (2026-11-05, config changed, no reboot needed yet)

The owner reported that Tahoe boots slowly. Measured on the 08:46 boot (OLED only, no HDMI) with `/usr/bin/log show --last boot` and `sysctl kern.boottime`.

| Phase | From → to | Time |
|---|---|---|
| Firmware + OpenCore | power on → kernel start | not in the logs. Includes the 5 s picker (`Misc > Boot > Timeout 5`, `ShowPicker true`) |
| Kernel + early kexts | kern.boottime 08:46:08.6 → launchd 08:46:12.7 | 4.1 s |
| launchd → WindowServer spawn | 08:46:12.7 → 08:46:15.5 | 2.8 s |
| GPU kexts (NMXGPU modeset done 08:46:19.2, StrixS0ix up 08:46:17.8, NVRM RmInitAdapter 08:46:22.2) | in parallel with the next row | ~7 s, no stall |
| **WindowServer blocked in IOKitWaitQuiet** | 08:46:17 → 08:46:54.1 | **36.2 s** |
| WindowServer → login window shown | 08:46:54.1 → 08:47:00.4 | 6.3 s |
| Password entry (owner) | 08:47:00.4 → 08:47:22.1 | 21.7 s (user time) |
| Login → desktop ready | 08:47:22.1 → 08:47:25.6 | 3.5 s |

Machine time from kernel start to the login window: about 52 s. Of that, 36 s is one wait.

**The 36 s wait is the NVRM boot hold.** At 08:46:17.853 NVRM logs "registry held busy until the display is armed". It holds the IORegistry busy, so WindowServer's IOKitWaitQuiet cannot return. With the OLED only, the RTX has no display (`ENUMERATED: 0 connected display(s)`, all NVRMFB `kapiInit failed -- not starting`). The auto-go thread still runs its full loops:
- it waits 20 × 1 s for `debug.nvaccel_heads_published`. The mask stays 0, and the "mask unchanged 3 times" exit only counts a non-zero mask (`heads published mask 0x0 ... after 20 s`, 08:46:44.0);
- it then tries `debug.nvaccelfb=1` 10 × 1 s (`accelerator level 1 NEVER took after 11 tries`, 08:46:54.07).

After that comes `boot hold RELEASED (display PARTIAL)` at 08:46:54.090, and WindowServer logs again at 08:46:54.098. NVAccel already knew at 08:46:23.855 ("headless check: no display on any NVIDIA connector"). So about 30 s of the hold is spent waiting for an RTX display that never comes.

There is no boot-arg that shortens it:
- `nvrmholdcap` only accepts 40–600 s, and the hold ends at 36 s anyway;
- `-nvrmnogo` skips the whole RTX bring-up, so apps would lose the NVIDIA Metal device.

The fix belongs in the NVRM auto-go thread, in the NVIDIA translator tree (`nmx-translator-271`, PolyForm; no code from it goes into this repo). When the display nub reports 0 connected displays, skip both loops (or release the hold first) and keep the RTX as a headless Metal device. Expected gain: about 30 s per OLED-only boot. Not done here, because it touches the NVIDIA stack.

**`-v` this boot.** No console stall was visible. NMXGPU's first modeset finished at 08:46:19.2, and there is no gap over 1 s in the GPU kext log before the NVRM hold. So `-v` was not the main cost this time. It is still removed: verbose console printing is useless on a normal boot, and the IH-thread printf block during the first modeset can come back.

**Change (ESP):**
- `EFI/OC/config.plist` → `NVRAM > Add > 7C436110-… > boot-args` now has no `-v`. That is the only line that changed (`diff` against the backup), and `plutil -lint` is OK.
- Backup: `config.plist.pre-no-v`.
- `boot-args` is in `NVRAM > Delete > 7C436110-…`, so OpenCore rewrites the NVRAM value on every boot, and no `nvram` write is needed. The live NVRAM still shows `-v` until the next boot.
- Undo: `cp /Volumes/ESP/EFI/OC/config.plist.pre-no-v /Volumes/ESP/EFI/OC/config.plist`, or add `-v` back. For a single verbose boot, press Cmd+V in the OpenCore picker.

**Applied after the owner said yes (2026-11-05):** OpenCore picker `Misc > Boot > Timeout` 5 → 2 s (backup `config.plist.pre-timeout2`, `plutil -lint` OK, only that line changed). Any key still stops the countdown, so the picker stays the Linux fallback.

**Other options, not applied:**
- Debug boot-args (`itlmt_native_nvtrace=1`, `itlmt_stat=1`, `strixamp_trace=1`, `alcverbs=1`, `msgbuf=1048576`) cost little at boot (the log shows no stall from them). Leave them until their research is done.
- kernelmanagerd sandbox denials on `/private/var/db/loadedkextmt.plist` (08:46:18–20) are noise and do not block boot.

## Step112: S0i3 (StrixS0ix 0.1.3), installed 2026-11-05, reboot pending

Step111 sleeps with amdgpu suspended, yet the fans keep running and the keyboard LED only starts breathing about 31 s after display off. Two things keep the SoC out of S0i3:

- **No SMU OS hint.** Linux `amd_pmc` sends OS_HINT(1) after the LPS0 _DSM entry calls; macOS sends nothing.
- **Cores only reach C1.** Non-boot CPUs park in HLT, and the boot CPU waits in MWAITX hint 0. S0i3 needs every core in CC6.

StrixS0ix 0.1.3 adds the following:

- **PMC mailbox** (`amd_pmc`, family 1Ah model 20h, root 1022:1507):
  - Base: SMN 0x13B102E8/EC through 00:00.0 config 0x60/0x64, plus 0x10000.
  - Registers: msg 0x938, arg 0x9BC, rsp 0x980.
  - At start: GETSMUVERSION, then the metrics table address (LOG_GETDRAM_ADDR LO/HI), which is mapped uncached.
  - Sleep, after _DSM 3/7/5: LOG_RESET, LOG_START, OS_HINT(1).
  - Wake, before _DSM 6/8/4: OS_HINT(0) and LOG_DUMP_DATA.
  - Published properties:
    - `S0ix,SmuS0i3Entered`
    - `S0ix,SmuS0i3Us`
    - `S0ix,SmuHintCount`
    - `S0ix,SmuNotMetUs` (32 × u64, per IP block)
    - `S0ix,SmuIdleMask`
  - Log line: `StrixS0ix: OS_HINT(0) ..., S0i3 REACHED/not reached, N ms in S0i3 ..., not met: i:ms ...`
  - Boot-arg `s0ix_pmc=0` turns it off.
- **CC6**: the IO C-state port is CStateBaseAddr+1 (MSR C001_0073), the same as Linux "ACPI IOPORT 0x414".
  - Non-boot CPUs spin on `inb(port)` instead of `hlt`; INIT/SIPI still restarts them. `s0ix_cc6=0` restores HLT.
  - The boot CPU uses inb(port) between wake checks only if `S0ix,BootCC6` is set (via `ioreg` setProperties, or boot-arg `s0ix_cc6boot=1`). If C2 keeps returning immediately (more than 2000 times in a row), it falls back to MWAITX.

Install: `scripts/macos-install-step112.sh` (`--undo`; backup in /Library/NullMoth/step112-bk-*).

Test after reboot:

1. Run the sleep test hands off.
2. Read the `StrixS0ix:` lines: the PMC mailbox and SMU version at boot, and the OS_HINT/S0i3 result on wake.
3. If S0i3 is not reached, the `not met` blocks name the IP blocks still keeping the SoC awake (the RTX not in D3cold is the expected one).
4. Then set BootCC6 and repeat.

Also seen in the Step111 sleep-entry timeline:

- **apsd 17.5 s.** en5 (native Wi-Fi) claims keepalive proxy support, but `APPLE80211_IOC_WOW_ENABLED` returns -3900. apsd waits for its `requestkeepaliveproxy` assertion to time out after 15 s. This was handed to the Wi-Fi branch.
- **cloudd 13 s.** These are SystemIsActive assertions on the `pmset sleepnow` software-sleep path, which goes through dark wake. A lid close is a forced sleep path and needs its own test.

### Step112b: headless NVRM in the same reboot

The boot-time audit (35f435c) found the 36 s NVRM boot hold on OLED-only boots. nmx-translator-271 c54e304 releases the hold once every NVRMDisplay nub reports 0 connected displays.

- Built kext: `~/nvrm-build-headless/NVRM.kext`. Its Info.plist is equal to the live 2.7.1 one.
- Installed with `scripts/macos-install-step112b.sh <kext>`; undo with `--undo`. Backup: /Library/NullMoth/step112b-bk-*.
- Check after the reboot:
  - the log has "NVRMFB reports 0 connected displays ... releasing the boot hold";
  - WindowServer starts about 30 s earlier.

### Boot-time result (boot 2026-11-05 10:05, OLED only): kernel start → login window 15.7 s (was 51.8 s)

This boot ran with the headless NVRM.kext (nmx-translator-271 c54e304, live as com.nullmoth.NVRM 2.7.1). It also had `-v` removed and the picker timeout set to 2 s.

| Phase | 08:46 boot (before) | 10:05 boot (after) |
|---|---|---|
| kern.boottime → launchd | 4.1 s | 1.4 s (10:05:59.2 → 10:06:00.6) |
| launchd → WindowServer spawn | 2.8 s | 2.0 s (→ 10:06:02.6) |
| WindowServer blocked in IOKitWaitQuiet | 36.2 s | 6.5 s (10:06:02.9 → 10:06:09.4) |
| WindowServer → login window shown | 6.3 s | 5.5 s (→ 10:06:14.9) |
| **Kernel start → login window** | **51.8 s** | **15.7 s** |
| Login → LoginComplete | 3.4 s | 10.5 s (10:08:58.5 → 10:09:09.2) |

Firmware + OpenCore time is not in the log. The machine was off from 09:20 to 10:05. That phase includes the 2 s picker (it was 5 s).

**What NVRM did.** At 10:06:09.359 it logged `heads published mask 0x0 ... after 0 s`, then `NVRMFB reports 0 connected displays on every nub after 0 s — releasing the boot hold`, then `boot hold RELEASED (no display on any NVIDIA connector)`. WindowServer logged again 10 ms later (10:06:09.369). The 6.5 s that is left is the RTX go(2) itself: 3.0 s, after the 500 ms settle that starts at 10:06:04.8. NMXGPU's modeset finished at 10:06:06.2.

**Still open: login → desktop.** It took 10.5 s, against 3.4 s before. Most of it is about 5 s between ContinueAfterDesktopReady (10:09:04.1) and ContinueAfterTALCheckin (10:09:09.1), which is the TAL app-relaunch check-in, so it is probably the windows restored by session restore. This is user space and is not looked at yet.

## Step112 result + Step112c (FADT re-read), 2026-11-05

The boot was faster, but the 890M did not suspend in the sleep test. Root cause: a race between StrixS0ix and NMXGPU at start-up. Step112c fixes it; the fix is installed and needs a reboot.

**Boot (headless NVRM, no `-v`)**
- Kernel 10:05:58.
- WindowServer starts at 10:06:02.9.
- NVRM releases its boot hold at 10:06:09.36 ("NVRMFB reports 0 connected displays ... after 0 s"). Before the fix it held for 36 s; it now holds for 6.5 s, and most of that is NVRM `go(2)` (3.0 s).

**StrixS0ix 0.1.3 at boot**
- CStateBaseAddr is 0x413, so the CC6 port is 0x414. Non-boot CPUs use CC6; the boot CPU uses MWAITX.
- PMC mailbox at 0xfd110000, SMU 93.11.0. The metrics table is mapped; idlemask 0xf5c01aff.

**Sleep test (hands off, ~/ga403-logs/syssleep-20261105-101003)**
- The machine slept from 10:12:50 to 10:14:55, about 2 min. The RTC wake was missed because the password took longer than the test window; it woke on XHC0.
- No hang. The paging wake ran and WindowServer stayed alive.
- SMU: OS_HINT(1) and OS_HINT(0) both returned OK, and hint_count is 1.
- S0i3 was **not reached** (0 ms).
- Blocks that were not idle for the whole 124.6 s:
  - 0 DISPLAY
  - 1 CPU
  - 9 NBIO
- ACP, VCN and ISP were not idle for less than 0.11 s.
- The `timecondition_notmet_lastcapture` array has 16 entries in this table version. Entries 16 and up are the totals, and entry 15 is not a time.
- **Why amdgpu did not suspend:** it logged "BIOS has not been configured for suspend-to-idle" and its suspend took 0 ms. xkpi had logged "no FADT" at 10:06:04.832, while StrixS0ix had published FACP at 04.775.
  - xkpi copies the FADT once, in its nmx_acpica_init SYSINIT, and the two kexts start within ~50 ms of each other.
  - The Step111 boot won this race; this boot lost it.
  - So DISPLAY not idle is expected for this run.

**Step112c**
- `scripts/nmx-s0ix/patch_fadt.py`: in nmx_port_power's suspend half, `mov %rdi,%rbx; mov %rax,%rdi` at 0x6de446 becomes `call cave; nop`. The cave sits over dead amdgpu_kv_dpm_get_enable_mask at 0x50ac10. It calls nmx_acpica_init again, which re-reads FACP, so every sleep sees LOW_POWER_S0 whatever the boot order.
  - NMXGPU sha goes from 2a1bb264 to 5760efb6.
  - The patch is registered in nmx-caves/check.py, and patch_s0ix.py still reports "patched".
- Installer: `scripts/macos-install-step112c.sh` (`--undo` restores the previous NMXGPU).

**New tool:** `scripts/s0ix-tools/s0ix-bootcc6.c` (built to build/s0ix-bootcc6, run as root) turns boot-CPU CC6 on or off at runtime. Use it to test the CPU block (1) without a reboot.

**Next**
- After the reboot, run the sleep test: amdgpu must take the s0ix suspend path, and the DISPLAY block should go away.
- Then run with BootCC6 on (the CPU block).
- NBIO (9) is most likely the RTX root port, which needs dGPU D3cold.

## Step112c result + Step113 (StrixS0ix 0.1.4), 2026-11-05

**Step112c works.** amdgpu took its s0ix path on every sleep: "suspend returned 0 in 607/613 ms", resume 321 ms. GFX (block 2) went idle about 0.6 s into the sleep. Mapping block 2 to GFX this way confirms the SMU block order: 0 DISPLAY, 1 CPU, 2 GFX, 5 ACP, 6/7 VCN, 8 ISP, 9 NBIO.

**Runs**
- Run 1 (~/ga403-logs/syssleep-20261105-102642):
  - 75.7 s asleep. A dark wake came from GPE 0x1a (XHC0) after 77 s.
  - S0i3 not reached. DISPLAY, CPU and NBIO were not met for the whole sleep.
- Run 2: invalid. Test 1's script was still waiting and restarted `caffeinate -u`, which woke the machine from its dark wake.
- Run 2b (`S0ix,BootCC6` on):
  - 60.7 s asleep, RTC wake (0x400) on time.
  - `cc6 1`: the boot CPU stayed in one IO C-state read the whole time.
  - S0i3 still not reached, and DISPLAY, CPU and NBIO were unchanged.

**D-states during sleep.** IOPCIFamily logs "did move PMCSR to D3" only for XHC0/1/3/4. Every other function stays in D0: the 890M (VGA), HDAU, PSP, ACP, HDEF, the NPU (150d), IPU, NHI0, SDCR, WLAN and NVMe. Linux puts devices into D3hot (pci_pm_suspend_noirq) before amd_pmc's OS_HINT. Our OS_HINT also went out about 0.6 s **before** amdgpu had finished suspending, because StrixS0ix's setPowerState(0) runs first.

**StrixS0ix 0.1.4 (installed, reboot pending)**
- **OS_HINT(1)/(0) from the halt path.** It is sent on the boot CPU after all drivers have suspended, on both entry and exit. Off: `s0ix-set halthint off` or boot-arg `s0ix_halthint=0`.
- **PCI D-state table.** It is built at the first sleep from IOPCIDevice endpoints that have a PM capability. Each entry keeps its own ECAM map from MCFG, so the halt path never takes an IOPCIBridge lock with interrupts off.
  - In the halt path it records each function's D-state and publishes `S0ix,PciStates` (pre → set → post).
  - With `S0ix,D3Mode` (`s0ix-set d3 N` at runtime, or boot-arg `s0ix_d3=N`) it moves functions with No_Soft_Reset to D3hot after the drivers have suspended. On wake, before OS_HINT(0) returns control, it brings them back to D0 and waits 10 ms.
  - Mode 1 covers the 890M's bus and the NPU bus. Mode 2 adds the other endpoints. The RTX, NVMe, USB and bus 0 are never included. The default is 0 (record only).
- **Boot CPU CC6** is now on by default (`s0ix_cc6boot=0` turns it off).
- **Tool.** `scripts/s0ix-tools/s0ix-set.c` replaces s0ix-bootcc6: `bootcc6`, `d3`, `halthint`.
- **Install.** `scripts/macos-install-step113.sh` (`--undo`). It also checks the FADT patch and the headless NVRM in the AuxKC.

**Plan after reboot**
1. Sleep with mode 0 and read the recorded D-states.
2. Sleep with mode 1 (890M buses in D3hot); DISPLAY should go away.
3. Sleep with mode 2 (NBIO).
4. If CPU is still not met, look at the CC6 configuration (MSR C001_0294 CStateCfg) and at the non-boot cores.

## Shutdown restarts audit (2026-11-05, read-only, nothing installed)

The owner reports that Apple menu → Shut Down restarts the machine instead of powering it off. This audit used only
logs and files: nothing was installed, and the ESP, NVRAM, kexts and pmset were not changed.

**What macOS asked for: power-off, and it got that far cleanly.**
- loginwindow logged every request with its type. Shut Down requests were at 11-04 08:51, 09:34, 18:11 and 23:55, and at
  11-05 09:20:03 (`Received a kAEShowShutdownDialog` → `logoutType:3 - Shutdown`). Restart requests (`kAEShowRestartDialog`,
  `logoutType:2`) were at 11-04 11:03…22:43 and 11-05 10:23:50. So Shut Down is not turned into a restart in user space.
- 09:20:09: launchd ran its normal shutdown phases (`BOOTOUT_SERVICES → … → DOMAIN_DEACTIVATE`), and WindowServer exited
  with exit(0). The unified log ends at 09:20:10.119 (`system wallclock time adjusted`). The kernel halt path (_PTS(5), the
  SLP_TYP write) happens after logd has stopped, so it is never logged.
- No panic: `DumpPanic processed 0 files` at the 10:05 boot, and there is no new `.panic` file (the last one is from 11-04 22:57).
  Panics are normally saved on this machine (11-03 and 11-04 have them), so a panic during halt would have shown up.
- `shutdown_stall_*.shutdownStall` exists for every shutdown and restart. The 09:20:16 one (`spindump -i`) is the usual
  1-second sample taken 2 s into shutdown. It shows idle user processes (caffeinate and others) and no kernel thread stuck.
  It is not a cause.
- SMC "Previous shutdown cause: 5" and AppleRTC "RTC: lost battery power" appear on **every** boot, after restarts too.
  VirtualSMC and DisableRtcChecksum produce them, so they say nothing about how the machine went down.

**What came back after a Shut Down.** No macOS boot followed any Shut Down within minutes:

| Shut Down | Next macOS boot |
|-----------|-----------------|
| 09:20     | 10:05           |
| 23:55     | 08:46           |
| 18:11     | 21:38           |
| 09:34     | 10:11           |

After a Restart the next boot comes within about 1 minute (10:23:50 → 10:24:14). The unified log has no entries at all
between 09:20:10 and 10:05:58. So when the machine "restarts" after Shut Down, it does not reach macOS on its own. The
OpenCore picker has Timeout 2 and ShowPicker on, and its default is macOS, so OC alone would have booted macOS within
seconds. The machine must either:
- come back on and stop before macOS (firmware or OC hang, or another OS was picked), or
- be powered on by hand later.

The owner's observation is needed here: what is on the screen after the "restart" (ROG logo, OC picker, black screen with
the keyboard lit), and does it happen when Windows or Linux shuts down?

**The reset register already gives the answer for each boot.** AmdCppc reads the FCH S5_RESET_STATUS (0xFED803C0) at
start (`sysctl debug.amdcppc.psp`, field `reset=`). The bits, from Linux `s5_reset_reason_txt`:
- 19: software wrote 0x6 to CF9 (warm reset)
- 21: ACPI power state transition (power-on from S5)
- 1: power button held for 4 s
- 23: CPU shutdown event
- 25: hardware watchdog

The current boot followed the 10:23 Restart and reads `reset=00080800`, which is bit 19 + bit 11: a normal CF9 restart,
as expected. Bit 11 is set on every boot and has no name. The boot after a Shut Down has not been read yet, because the
value only survives until the next boot. Read it on the next macOS boot after a Shut Down:
- bit 21 (0x0020xxxx) with no button press: S5 was entered and something woke the machine (a wake source left armed).
- bit 19: something reset the machine instead of entering S5.
- bit 1: the owner forced it off by holding the button.

**Candidates checked**
- StrixS0ix (installed 0.1.3 and repository 0.1.4): `systemWillShutdown` sets `shutdown` and clears `gArmed`, and
  `setPowerState(0)` returns at once when `shutdown` is set. So power-off never runs the PEP _DSM, the SMU OS_HINT/PMC
  messages or the armed idle loop. At halt, non-boot CPUs (and the unarmed boot CPU, if it ever re-enters pmCPUHalt)
  sit in the `inb(0x414)` CC6 loop or in `wbinvd; hlt`. Neither of those resets the machine: CC6 is a core C-state, and
  the S5 write goes to the FCH, which does not need the cores. Low probability. A/B test: boot-arg `-s0ixoff`, or
  remove the kext for one boot.
- No CF9 write and no PEHaltRestart/haltRestart call exists in `kexts/` or in the nmx-* trees (grep). The NMXGPU/NMXNPU
  `systemWillShutdown` paths only run the amdgpu PCI shutdown (PrepareMp1ForUnload).
- ACPI (DSDT dump `abi/acpi/ga403wm/20261012`):
  - `_S5` = {5,0,0,0}, which is normal.
  - `_PTS` runs XPTS (empty), TPM.TPTS, MPTS (AMD, writes FED80200/240), SPTS (`PEWS = Zero`) and NPTS/APTS. Nothing in
    it disables USB/USB4 PME.
  - OC adds no `_PTS`/`_S5` patch, `FadtEnableReset` is false, and SSDT-S0IDLE only adds `\_SB.LPS0`.
- Wake sources:
  - `womp 0`, `proximitywake 0`, and no autorestart key in `pmset -g custom`.
  - `pmset -g sched` holds only `wake` events (calaccessd, osanalytics), which do not power on from S5. There is no `poweron`.
  - The XHCI (GPE 0x19/0x1A) and USB4 bridges (GPP0/GPP1.SWUS, 0x1A) have `_PRW` up to S4.
  - Step112c already showed XHC0 (GPE 0x1A) waking the machine by itself out of S0 sleep after 77 s. A PME that stays
    armed at S5 entry is the classic hackintosh cause of "Shut Down restarts", fixed on other machines by the
    `_PTS(5)` XHC PMEE clear (OC SSDT-PTSWAK / Clover FixShutdown).

**Most likely cause (to confirm with the reset bits): a USB (XHC0..4) or USB4 PME wake left armed when macOS enters S5,
so the machine powers back on right after power-off.** It is less likely to be a kernel-side reset, because there is no
panic and no CF9 path in our code.

**Proposed fix (not applied; it needs a reboot and the owner's OK):**
1. An `SSDT-PTS5` that wraps `_PTS`: rename `_PTS` to `ZPTS` with an OC ACPI patch, then a new `_PTS(Arg0)` that, for
   `Arg0 == 5` under Darwin, clears PME_En (PMCSR bit 8) and writes PME_Status on XHC0..XHC4 and on the USB4 NHI/bridges,
   then calls `ZPTS`. Undo: disable the SSDT and the patch.
2. Before that, the cheap test with no install: after one Shut Down, read `sysctl debug.amdcppc.psp` at the next boot,
   and unplug every USB device (BLE dongle, mouse) before a second Shut Down for comparison.

**Result of the test Shut Down (2026-11-05 10:42), confirmed: S5 is entered, then the machine wakes from S5.**
- loginwindow 10:42:15 `kAEShowShutdownDialog` (Shut Down). The kernel booted again at 10:42:43, about 28 s later, with no
  button press.
- `sysctl debug.amdcppc.psp` on that boot: `reset=00200800`, which is bit 21 (ACPI power state transition) + bit 11. It
  is not bit 19 (CF9 reset), so neither macOS nor a kext reset the machine. The FCH entered S5, and a wake event powered
  it back on.
- macOS records no wake source for an S5 power-on (IOPMrootDomain only has `Wake Type`, from the last sleep).
- So the cause is an S5 wake source left armed. The best candidate is still the XHC/USB4 PME (GPE 0x19/0x1A; XHC0 already
  self-wakes S0 sleep). An RTC alarm is unlikely, because `pmset -g sched` has no event within minutes.
- The earlier long gaps (09:20 → 10:05 and others) were most likely the owner turning the machine off by hand after it
  came back on.
- Next: the `_PTS(5)` PME-clear SSDT (see the proposed fix above), batched with the next reboot, with the owner's OK.
  An optional test with no install: unplug every USB device and the BLE dongle, then Shut Down.

### Step113 first sleep: panic (fixed, reinstalled, reboot pending)

The first sleep test (mode 0) panicked at 10:46:16 on entry to sleep. The machine did not wake and needed a forced restart.

- Panic: `A kext releasing a(n) OSData ... has corrupted the registry`, thrown from `StrixS0ix::buildPci` (via setPowerState). Report: /Library/Logs/DiagnosticReports/Kernel-2026-11-05-105201.panic.
- Cause: `IOACPIPlatformDevice::getACPITableData("MCFG")` does not retain the table for the caller (readFadt already handles FACP this way), and buildPci released it.
- Fix: the release is removed. The kext is rebuilt and reinstalled with `scripts/macos-install-step113.sh`; it loads at the next boot.

### Boot-time step 2: `-nvrmnohold` (2026-11-05 11:06, installed, reboot pending)

On the 10:42 boot, c54e304 was live. The NVRM hold started at 10:42:51.36 and the 890M framebuffer (NMXAMDFB) was published at 10:42:52.73. The hold was released only at 10:42:55.88, when go(2) finished (3.0 s). So WindowServer still waited about 3 s for the RTX only to learn that the RTX has no display. On this machine the desktop is always on the 890M. The RTX is needed only for:
- headless Metal apps. NVAccel's headless check restores MetalPluginName at about +6 s, without the hold;
- HDMI, which is wired to the RTX.

**Change.** NVRM in nmx-translator-271 3d0246f adds the boot-arg `-nvrmnohold`:
- With the flag, NVRM never takes the hold: no adjustBusy(+1) and no cap timer. auto-go and go(2) still run in the background. A display on the RTX is still armed, but WindowServer is already up by then.
- Without the flag, behaviour is the same as c54e304.

Build checks: Info.plist and the undefined imports are equal to the live kext, and `strings` only adds the new lines.

**Installed:**
- `sudo scripts/macos-install-step112b.sh ~/nvrm-build-nohold/NVRM.kext` (the same installer as Step112b). NVRM sha256 is dca5eac6cfca8e7c. The NMXGPU cave checks pass in the new AuxKC and again after 45 s.
- Backup: /Library/NullMoth/step112b-bk-20261105T040555Z (the c54e304 NVRM and the old AuxKC). `--undo` restores it.
- ESP: `-nvrmnohold` was appended to boot-args. Backup `config.plist.pre-nvrmnohold`, `plutil -lint` OK. To undo, drop the flag: the kext without the flag behaves like c54e304.

**Check after the reboot:**
1. The log has `boot hold OFF (-nvrmnohold)` and `registry NOT held (-nvrmnohold)`.
2. The IOAVBNub / WindowServer waitQuiet ends at about the NMXAMDFB publish, not at the end of go(2). The expected gain is about 3 s.
3. Headless Metal still works: the NVAccel headless check line appears, and an app can still pick the RTX.
4. HDMI hotplug after boot, as a separate test: does the RTX display come up? If not, arming on hotplug is its own follow-up.

**Fix installed: SSDT-PTS5 (2026-11-05 11:07). Reboot pending; it takes effect on the first Shut Down after that boot.**
- Source `acpi/SSDT-PTS5.dsl`, compiled with ACPICA iasl 20260930 (the wifi worktree build) to
  `efi/OC/ACPI/SSDT-PTS5.aml` (392 bytes), and copied to `/Volumes/ESP/EFI/OC/ACPI/`.
- What it does:
  - New `\_PTS`. When `Arg0 == 5` and `_OSI("Darwin")`, it clears PME_En (PMCSR bit 8) and writes 1 to PME_Status
    (bit 15) on:
    - XHC0/XHC3/XHC4/NHI0/NHI1 behind GPPC (00:08.3)
    - XHC1 behind GPPA (00:08.1)
    - the USB4 SWUS behind GPP0 (00:01.1) and GPP1 (00:01.2)
  - Then it always calls `ZPTS(Arg0)`, so other OSes and other states behave as before.
  - Bus numbers come from each root port's secondary-bus register. The PM capability is found by a capability walk
    bounded to 48 steps. Absent functions are skipped (vendor/device dword reads 0xFFFFFFFF). Config space goes through
    the firmware's CPM helpers M645/M049/M04B/M04E (ECAM).
- ESP config changes (backup `EFI/OC/config.plist.pre-pts5`):
  - ACPI > Add `SSDT-PTS5.aml` (enabled).
  - ACPI > Patch "_PTS to ZPTS (DSDT only)": Find `5F50545301`, Replace `5A50545301`, TableSignature `DSDT`, Count 1.
    The firmware DSDT (OEM rev 0x01072009) has exactly one match, at 0x288B.
  - The repository's `efi/OC/config.plist` was already different from the ESP, and it was not changed.
- Checked in acpiexec 20260930 with the patched firmware DSDT, all 28 firmware SSDTs and SSDT-PTS5:
  - The table loads (the only error is the existing firmware `GPP5.WLAN._S0W` duplicate).
  - `\_PTS 5` runs with and without the Darwin interface installed.
  - A seeded fake config space (cap at 0x50, PMCSR 0x0108 = D0 + PME_En) gives PMCSR 0x8008 after `ZPMF`, and the cap
    header is unchanged.
- Verify after the next boot, then Shut Down:
  - the machine stays off;
  - at the next power-on, `sysctl debug.amdcppc.psp` reads bit 21 only after the owner presses the button.
  - If it still comes back on its own, the wake is not PCI PME. Next candidates: the GPE0 enables for 0x19/0x1A at S5,
    and the RTC alarm.
- Undo: disable both entries (or restore `config.plist.pre-pts5`).

## Black screen after `-nvrmnohold` (2026-11-05 11:11 and 11:12 boots, traced from Linux)

The two boots after the `-nvrmnohold` + SSDT-PTS5 install (11:11:25 and 11:12:14, both ended with shutdown cause 5)
stayed black. The 10:52 boot before them reached the desktop; its 11:1x `Kernel-...-111129.panic` (spinlock timeout in
WindowServer amdgpu_cs_ioctl → lkpi_kfree → nmx_curthread) is a separate issue, still open.

**Cause (unified log, 11:12 boot, local time):**
- 11:12:22.171 WindowServer: `Setting offline display 0x00000000 main in CGXConstructVirtualFramebuffer`
- 11:12:22.448 WindowServer: `GPU: FB: 0 of 0 opened`. It found no framebuffer, so it uses a virtual one and the main display is offline.
- 11:12:22.623 kernel: `NMXAMDFB published`, 175 ms too late.
- 11:12:22.750 → 25.750: NVRM go(2), with no hold taken (`-nvrmnohold`).
- In every good boot, WindowServer calls `IOFBSetDisplayModeAndDepth ... displayID 0x20d06700` on VGA@0 (GPPA, the 890M). Neither black boot has that call.

The NVRM boot hold kept the registry busy for about 3 s. That made WindowServer wait for the hold, and by the time it ended NMXAMDFB already existed. Without the hold, nothing makes WindowServer wait for the 890M framebuffer. The reason is that NMXGPU::start (0x6e5160) only starts `attachThread` and returns. The amdgpu attach, the modeset and nmx_fb_publish then run outside IOKit's busy window.

**Now:** `-nvrmnohold` removed from the ESP boot-args (owner's call). Backup `config.plist.pre-drop-nvrmnohold-*`. NVRM
without the flag behaves like c54e304 (hold on). SSDT-PTS5 stays.

**Proper fix (not done yet):** NMXGPU should keep itself busy from start() until nmx_fb_publish returns: `adjustBusy(+1)` before
kernel_thread_start and `adjustBusy(-1)` on every exit of attachNow. adjustBusy is virtual. Its slot is in __ZTV6NMXGPU (0x8f5b10),
and an UNSIGND reloc points to it at 0x8f5550/0x8f6150, so a cave can call it through `(*this)->vtbl` with no new relocation. After
that, `-nvrmnohold` can come back.

### Addendum: where the NMXGPU busy hold must start (2026-11-05, from the nmxaccel-ci source)

The fix above takes `adjustBusy(+1)` before `kernel_thread_start` in `start()`. The source
(nmxaccel-ci `gpu-port/xkpi/xnu/nmx_kext.cpp`, comment above `kernel_thread_start`) says why the attach runs on its own
thread: it reads firmware, root mount waits for matching to settle, and an attach inside matching stopped the Mac at the
logo. A busy hold from `start()` keeps the registry non-quiet while `attachNow()` waits for the firmware folder, which is
the same deadlock. So:
1. `adjustBusy(+1)` in `attachNow()` right after `nmx_xnu_wait_firmware_root` returns OK (root is mounted by then).
2. `adjustBusy(-1)` on every exit: after `nmx_fb_publish()` (fb or not) and on every failure branch (marker set, attach
   failed). The early return when the firmware folder never appears takes no hold.
3. A cap thread_call (about 30 s, boot-arg tunable) releases the hold if the amdgpu attach hangs.
4. A `nmxgpu-boot-hold` property and one log line per state.

The window between root mount and step 1 is small: the attach thread is already waiting on the folder, and WindowServer
starts several seconds after mount (11:43 boot: mount 25.50, WindowServer up 30.59, NMXGPU driving 33.77). NVRM's own
hold starts at the same point (after root mount) and has never raced.

Separate, lower priority: WindowServer did not adopt NMXAMDFB when it appeared 0.55 s late. A late NMXAMDFB should
still be taken (connect interrupt, like NVRMFB's `fHotplugBorn` path).

Verify over several boots with `-nvrmnohold` (it is a ~0.6 s race): "Done waiting for IOKitWaitQuiet" (bluetoothd) and
WindowServer's first `IOFBSetDisplayModeAndDepth` on VGA@0 come after "NMXAMDFB published", and no
`Setting main display 0x00000000 offline`. Report: https://claude.ai/artifact/YaTnhdFy7As59STtf699BM

## Step114: NMXGPU spin lock timeout panic (`nmx_thread_lock`), root-cause fix in source (2026-11-05, not built, not installed)

Panic `Kernel-2026-11-05-111129` (11:09, normal use, no sleep, uptime 18 min): "NMIPI for spinlock acquisition
timeout, spinlock 0xffffff99ee8f1220, owner WindowServer on CPU 12", then "mp_kdp_enter() timed-out on cpu 14".

What the panic shows (live NMXGPU 5760efb6, vmaddr = file offset, load base 0xffffff7faaff1000):
- The lock is `nmx_thread_lock`: the global at 0x98bae8 is a pointer to an `lck_spin_alloc_init` lock on the heap
  (zone DATA range, which matches the address).
- CPU 14 is the CPU that panicked ("timed-out on cpu %d" names the CPU running `mp_kdp_enter`), so it is the waiter
  that hit the spin timeout. It did not answer the debugger IPI, so it was spinning with interrupts off.
- CPU 12 holds the lock, running thread code with interrupts on: the backtrace goes from `hndl_allintrs` straight to
  the thread stack, where the frame pointer is `nmx_thread_get`'s (return `nmx_curthread+0x11`). So it was inside the
  locked region of `nmx_thread_get` (walk + Step100 mmfix2 cave), called from `amdgpu_cs_parser_fini -> lkpi_kfree`.
- `mp_cpus_call_cpu_init+0x493` is a wrong symbol. With the BootKC (slide 0x14200000, `tools/kc.py`), the RIP
  0xffffff80004e0937 is in the unnamed function at 0xffffff80004e08b0, right after `mp_safe_spin_lock`: it bumps a
  CPU counter, then loops on `pause` + `machine_timeout_suspended` and services `MP_TLB_FLUSH` (cpu_signals bit 0).
  That is `mp_kdp_wait`. CPUs 0, 1 and 6 (idle) sit at the same RIP. So CPU 12 was parked by the panic's own debugger
  rendezvous. It was not stuck in a cross-call.

Hypothesis "a holder takes a cross-call IPI that waits for a CPU spinning with interrupts off": **refuted**. CPU 12
took the IPI normally and was not waiting for any CPU. There is no lock-order cycle either. Nothing takes another lock
under `nmx_thread_lock` (the cave only calls `thread_tid`). No interrupt handler takes it: xkpi IRQs run on IOKit work
loops (`xnu/nmx_pci.cpp`), callouts and the VBL timer run on thread calls, and the only `ml_at_interrupt_context` users
are guards.

Every acquirer (live binary, `otool -tV`): `nmx_thread_get` (fast walk, slow-path re-check and insert),
`nmx_thread_leave`, `nmx_proc_for`, `tdfind`, `nmx_proc_any_task`, `nmx_threads_release_all`, init/fini.
`nmx_curthread` has 253 call sites. In the live binary nothing calls `nmx_thread_enter`/`leave` (only `kthread_exit`
and `taskqueue_thread_loop` drop records), so user-thread records are never freed (as Step100 found). Callers that take
the lock with interrupts already off:
- `critical_enter` users: `linux_rcu_read_lock`/`unlock`, the FPU window (`linux_fpu.c`), `drm_sched_entity_push_job`,
  `__folio_batch_release`, `gfx_v9/10/11_get_gpu_clock_counter`, `smuio_v14_0_2_get_gpu_clock_counter`. Inside these,
  `critical_exit`, a nested enter, `sched_pin`, `kfree` and sx locks all call `curthread`.
- `MTX_SPIN` mutexes (`nmx_mtx_lock` turns interrupts off while held).

Root cause: the hottest lock in the driver is one global, unfair xnu spin lock. `curthread` runs on every kfree,
sched_pin/unpin, sx lock and critical section, and took that lock on every call, from all 16 CPUs, many with
interrupts off. Meanwhile the holder kept interrupts on, so interrupts could hold it up. With every app on the 890M
(Step104), a waiter with interrupts off could lose the lock past the spin timeout. The panic cannot tell which of
"starved" or "holder stretched" happened (the waiter's stack is cut from the report), but both come from the same
design, and the fix removes both.

Fix, in the NullMoth source fork (`~/develop/projects/nmx-src-2.0.4`, remote `fork`). The branch is
**`xkpi-thread-lockfree`**, on top of `mm-lifetime` (163d117, the source of Step100):
- e249183 `bsdcompat/src/nmx_kernel.c`:
  - `curthread` looks up its record without the lock. Records are type-stable: a dropped record goes on a free list
    and is reused, never `IOFree`d while the layer runs. Links and bucket heads are published with release stores,
    the lock only serializes writers, and a lock-free miss is always looked up again under the lock.
  - The registry lock (`nmx_tl_lock`/`nmx_tl_unlock`) is held with interrupts off on every path.
  - Full-table scans (`tdfind`, `nmx_proc_any_task`, `nmx_proc_reap` step 2, `release_all`) take it one bucket at a
    time.
  - In interrupt context `curthread` uses a per-CPU record and never allocates.
- e4fa61a `tests/thread_registry/run.sh`: a user-space stress test. It extracts the record code verbatim and runs
  16 threads over 24 recycled thread_t values, 12.8M lookups, once with the real hash and once with every record in
  one bucket, under TSan and ASan. Result: 0 mismatches, no reports, counts consistent. The same test with the old
  "IOFree on drop" put back reports heap-use-after-free, so the type-stable records are what make the lock-free path
  safe.
- `nmx_kernel.c` compiles clean with the port's `cc.sh` against the branch's headers (the generated fast path is a
  lock-free walk plus the tid compare; the lock appears only on the miss path).

Not done, by the owner's decision ("fix từ root cause chứ không patch hiện trạng nữa"): no binary cave, no install
script. Not built as a kext and not installed. It goes into one NMXGPU build together with the NMXAMDFB busy-hold
fix from the `-nvrmnohold` black-screen trace above: one build, one install, one reboot, when the owner says so.
Build notes:
- The base must be `ga403wm-nmx` + `mm-lifetime` + `xkpi-thread-lockfree` (which already has both) + the busy-hold
  branch.
- The live binary also carries binary caves with no source counterpart on these branches: ibprobe, wcsplit, userptr,
  ibprep, cstrace, flip, irqfix, mmfix, fadt (`scripts/nmx-caves/check.py`). Before a source build replaces the live
  kext, check that each of those either has a source commit in the build or is re-applied to the new binary.
  Otherwise those fixes are lost.
- To build: `all.sh` (compile), then `kext/build.sh <out>` with `AMD_ONLY=1`, from a tree where
  `GPU_SRC/xkpi` points at the build checkout.

Follow-ups seen on the way (not fixed here): the slow path can still `IOMallocZero` with interrupts off (a thread's
first record made inside an `MTX_SPIN` region). A stale `task->task_thread` pointer to a dropped record now points to
a reused record rather than freed memory.

## Step113 results (d3 0/1/2) + StrixS0ix 0.1.5 (installed, reboot pending), 2026-11-05

**Runs.** Three sleeps on the 11:43 boot (0.1.4 with the MCFG fix). Each slept about 50 to 60 s, woke on the RTC (0x400) on time, and amdgpu suspended in about 610 ms and resumed in about 325 ms. OS_HINT came from the halt path: in/out 0x1/0x1, after amdgpu had suspended. `cc6 1` on every run (the boot CPU stayed in CC6).

S0i3 was **not reached** in any mode: DISPLAY (0), CPU (1) and NBIO (9) were not idle for the whole sleep. GFX (2) is no longer on the list now that amdgpu suspends.

- **d3 0 (record only).** Functions IOPCIFamily already had in D3: NVMe (61:00.0) and the four xHCI. Functions still in D0:

  | Function | Device |
  |---|---|
  | 63:00.0 | MT7925 Wi-Fi |
  | 65:00.0 | 890M, **NSR 0** |
  | 65:00.1 | HDMI audio, NSR 0 |
  | 65:00.2 | PSP |
  | 65:00.5 | ACP |
  | 65:00.6 | HDEF |
  | 67:00.5 | USB4 NHI |
  | 66:00.0 | NPU, NSR 0 |
  | 66:00.1 | IPU |
  | 62:00.0 / 62:00.1 | RTX + audio |
  | 64:00.0 | SD reader, NSR 0 |

- **d3 1.** PSP, ACP, HDEF and IPU went D0→D3→D0. No change in the SMU blocks.
- **d3 2.** Wi-Fi went D0→D3→D0 as well. Still no change. Wi-Fi had not been associated since 12:07, so these runs do not show whether Wi-Fi survives D3.

**Next leads.**
- The CPU block persists with every core in the _CST C2 state (port 0x414). The firmware `_CST` (SSDT-4) has three states: C1 = FFixedHW (MWAIT), C2 = IO 0x414 (latency 18 µs), C3 = IO 0x415 (latency 350 µs). C3 is the deepest, and we never used it.
- DISPLAY and NBIO need the functions without No_Soft_Reset in D3 (the 890M, its HDMI audio, the NPU, the SD reader, the NHI), and in the end the RTX.

**StrixS0ix 0.1.5**
- **C-state port.** CC6 entry now uses base+2, port 0x415 (`_CST` C3), by default. Boot-arg `s0ix_cst=1`, or `s0ix-set cst 1|2` at runtime, picks C2 or C3.
- **More D3 modes.** D3Mode 3 adds functions without No_Soft_Reset, except the 890M. D3Mode 4 adds the 890M. For these functions the config space is saved before D3hot and restored after D0, as `pci_save_state` / `pci_restore_state` do:
  1. the PCIe control registers;
  2. the header, in reverse order so the command register comes last;
  3. MSI addr/data/ctl and the MSI-X ctl.
- **NHI tier.** The USB4 NHI (0c0340) is now tier 2. Only xHCI (0c0330) is still excluded.
- Installed with `scripts/macos-install-step113.sh` (`--undo`).

**Test plan after the reboot**
1. d3 2 with C3: shows whether the CPU block clears.
2. d3 3.
3. d3 4: the 890M itself in D3hot. If amdgpu's s0ix resume cannot cope with the internal reset, this one is expected to fail.

**SSDT-PTS5 result (2026-11-05 12:27): Shut Down now stays off.**
- The boot that shut down started 11:43 with SSDT-PTS5 + `_PTS→ZPTS` (config edited 11:07) and StrixS0ix 0.1.5 (from
  the sleep session).
- 12:27:02 loginwindow `logoutType:3 - Shutdown`. launchd ran its shutdown phases, and the log ends 12:27:11.78. No
  panic.
- The owner saw that the machine did not come back on by itself. The next boot is 12:29:01: the owner powered it on.
- `sysctl debug.amdcppc.psp` on that boot: `reset=00800800`, which is bit 23 + bit 11. All reset readings so far:

  | Boot after | `reset=` | Bit | Meaning (Linux `s5_reset_reason_txt`) |
  |------------|----------|-----|---------------------------------------|
  | Restart | `00080800` | 19 | CF9 warm reset |
  | 10:42 Shut Down, came back on by itself | `00200800` | 21 | ACPI power state transition |
  | 12:27 Shut Down, stayed off | `00800800` | 23 | internal CPU shutdown event |

- Open question: why bit 23 and not bit 21? A CPU shutdown event usually means a core triple-faulted or hit the
  shutdown state. That normally resets the machine, but here the machine stayed off. Two things changed for this
  shutdown:
  - SSDT-PTS5 runs only AML (ECAM config writes to the USB functions) and cannot make a core shut down.
  - StrixS0ix 0.1.5 now parks the non-boot CPUs at halt with the `_CST` C3 port 0x415 (`S0ix,CstDepth 2`). The 10:42
    shutdown used 0.1.3, which parks on 0x414.

  So the likely source is a parked core while the rails go down after the S5 write, not a failure before S5. The
  outcome (power off, stays off) is correct either way.
- A/B test, nothing to install: before the next Shut Down run `build/s0ix-set cst 1` (non-boot CPUs back on 0x414, as
  0.1.3 did). At the next boot read `sysctl debug.amdcppc.psp`:
  - bit 21: bit 23 comes from C3 parking at halt. Fix it in StrixS0ix, for example park on the C2 port or `hlt` when
    `shutdown` is set.
  - still bit 23: it comes from the S5 path itself. Then check the PTS5 table, by disabling it for one shutdown and
    confirming that the machine comes back on.

## Step115 results (StrixS0ix 0.1.5 live) + Step116: StrixS0ix 0.1.6, EC GPE wake (2026-11-05, installed, reboot pending)

**Sleep tests on the 12:29 boot** (`scripts/macos-syssleep-test.sh 120`, RTC wake, AC, cc6 on `_CST` C3 port 0x415):

| Run | D3 mode | Asleep | Not met (ms, SMU slots) | Left in D0 | Resume |
|-----|---------|--------|-------------------------|------------|--------|
| 12:37 | 2 | 94 s | DISPLAY 93666, CPU 11, NBIO 93666 | NPU, 890M + HDMI audio, NHI, SD reader, RTX + audio | ok |
| 12:43 | 3 | none | invalid: the RTC alarm was set before the password, it fired during Software Sleep | | |
| 12:46 | 3 | 95 s | DISPLAY 95374, CPU 11, NBIO 95374 | 890M, RTX + audio | ok, NSR-0 functions restored (D0->D3->D0) |
| 12:52 | 4 | 78 s | DISPLAY 77512, CPU 11, NBIO 77512 | RTX + audio | ok, 890M D3hot -> D0, NMXGPU resume 314 ms, WindowServer fine |

- **CPU is solved.** With the C3 port the CPU block is busy only 11 ms (0.1.4 on C2: the whole sleep).
- **DISPLAY is not a PCI D-state problem.** It stays busy for the whole sleep even with the 890M in D3hot.
  - The streams are off at suspend: NMXAMDFB is a DRM client, so `drm_atomic_helper_suspend` disables its CRTC.
  - DMUB is up (fw 0x09005600, DCN 3.5). PMFW 93.11 gives `DMUB_IPS_RCG_IN_ACTIVE_IPS2_IN_OFF`, so IPS2 is allowed in
    s0ix.
  - Next: log `in_s0ix`, `ips_support`, `disable_ips`, `idle_optimizations_allowed`, the stream count and the IPS
    residency in `dm_suspend`. This goes into the single NMXGPU source build (requested from the nmxgpu session), not
    as a cave.
- **NBIO:** the only functions left in D0 are the RTX and its audio (NSR 1; NVRM standby leaves them in D0).
  0.1.6 adds `s0ix-set d3 5`, which also puts them in D3hot.

**Log bugs found by the owner's question ("is the trace right?"), fixed in 0.1.6:**
- The not-met list printed all 32 slots. SMU 93.11 fills 16 per-block slots, then 16 running totals (slot i + 16).
  Slot 15 is not a block time (values around 4.5e18 us). The raw property shows this: 16 = 0, 17 = 1, 25 = 9.
  0.1.6 prints slots 0..14 by name (`DISPLAY 77512ms CPU 11ms NBIO 77512ms`). The raw 32 slots stay in
  `S0ix,SmuNotMetUs`.
- "D0 at sleep" mixed the functions put in D3 with those left in D0. 0.1.6 logs two lists: "put in D3" and "left in D0".
- The test script set the RTC alarm before the password prompt. The root step now runs
  `scripts/s0ix-tools/syssleep-root.sh`, which sets the alarm after the password. `S0IX_PRE` runs `s0ix-set` in
  the same password step.

**Lid close 13:00 (d3 4): the machine never woke and had to be force-restarted.**
- powerd logged `Entering Sleep state due to 'Clamshell Sleep'` at 13:00:55. Opening the lid did nothing. The power
  button did nothing. The kernel log from about 12:55 was lost with the forced restart.
- **Root cause (DSDT):**
  - The power button is EC query `_QE7` → `Notify (PWRB, 0x80)`. The lid is `_Q2F` → `Notify (LID0, 0x80)`. Both
    arrive on the EC's GPE, `EC0._GPE = 0x0A`.
  - The DSDT has **no `_PRW` at all**, so AppleACPIPlatform disables GPE 0x0A before `pmCPUHalt`.
  - The StrixS0ix halt loop wakes only on PM1 fixed events (the fixed power button is not used: PWRB is a control
    method button) or an enabled GPE.
  - So only the RTC could end a sleep. Every earlier test woke by RTC, which is why this never showed. Idle sleep or
    Apple menu → Sleep would have hung the same way.
- **Fix (0.1.6), the Linux s2idle / Modern Standby model:**
  - The EC GPE is a wake source. `haltEnter` sets its GPE0_EN bit (the word macOS left is saved) and `haltExit` puts
    the saved word back.
  - The status bit stays set, so after the wake ACPI runs the query.
  - Lid open and the power button then wake fully. Other EC events (battery, thermal) should give a dark wake and go
    back to sleep. How often that happens is to be measured.
  - Off with boot-arg `s0ix_ecwake=0`.
  - The wake log names the event (RTC / EC / GPE / time limit / IRQ storm) and the GPE0_EN word at halt
    (`S0ix,EcEnAtHalt`).
- Installed with `scripts/macos-install-step116.sh` (backup `/Library/NullMoth/step116-bk-*`, `--undo`).

**Next boot test order:**
1. `scripts/s0ix-tools/lid-test.sh`: close the lid, open it after about 1 minute. It must wake by itself.
2. The same with the power button instead of opening the lid.
3. A RTC sleep with `S0IX_PRE="$PWD/build/s0ix-set d3 5"`: does NBIO clear with the RTX in D3hot?
4. A long sleep (15 min or more): count the EC dark wakes.

Other sleep findings (audit, open):
- The 300 s safety net (`s0ix_maxsec`) applies only in the MWAITX loop. The boot-CPU CC6 loop has no time limit.
  That is fine now that the lid and the button can wake it, but it should be one rule for both loops.
- D3 mode is runtime only (default 0 after boot). Once d3 4/5 are proven, make it the default (boot-arg `s0ix_d3`).

## Step117: OpenGL apps (old Electron) draw wrong on the 890M, found through Zalo (2026-11-05, ON HOLD, nothing installed)

Owner report: Zalo (`/Applications/Zalo.app`) shows wrong colours and wrong layering (hover reaction bar drawn over the
message bubble, missing emoji, text clipped under the pinned bar). Owner put the work on hold; this is where it stands.

**Zalo is a symptom.** It is Electron 22.3.9 / Chromium 108.0.5359.215. Before Chromium 115, ANGLE on macOS uses its
OpenGL backend, so the chain is: ANGLE-GL -> CGL -> `AppleMetalOpenGLRenderer` (Apple's GL on Metal) -> NVMTL GL bridge
(`plugin/NVMTLGL.m`, GL IR + pluginData lowered in process to AIR, then translator -> SPIR-V) -> RADV -> NMXGPU.
Chrome 156 / Edge / Safari use ANGLE Metal and never reach the GL bridge. Every Electron app older than ~26 and every
plain OpenGL app (old games, Qt/Java GL, CAD, emulators) takes the same path, so the fix target is OpenGL on the 890M.

Evidence (current boot, GPU process pid 1232, then relaunches via `tools/890m/zalo-gpu-log.sh`):
- On the 890M: NMXDrmClient owned by the GPU helper; NVMTL log `vk: UP ... AMD Radeon 890M Graphics (RADV STRIX1)`,
  `allow-listed: Zalo Helper (GPU)`, drm-xnu path armed (sandbox refuses /dev/dri). Not SwiftShader, not the RTX.
- GL bridge in use: `GL: vertex/fragment lowered in process (GL IR ... -> ... AIR) -> ours`, `GL: reflection usageFlags
  answered 0`, `__main has no AIR - cannot be reflected`, `buffer slot 0 is bound at offset 108, not a multiple of 16`.
- No crash reports today (Zalo, helpers, MTLCompilerService, WindowServer); no GPU fault, no nvk-reason, no forwarded
  unknown selector in the per-run NVMTL logs.
- Renderer flags `--enable-zero-copy --enable-gpu-memory-buffer-compositor-resources`; small IOSurfaces at pitch 64/128
  go through buffer-texture shadows (row upload + writeback per command buffer).
- Managed-buffer prologue uploads ~100 GB in ~10 min (12288 submits, merged dirty ranges): a cost, not the glitch.

A/B runs (env knobs only for Zalo, nothing installed):
| run | result |
|---|---|
| GL path, default | glitch |
| `--use-angle=metal` | black window: Metal front end cannot write `com.apple.metalfe/.../monolithic_metal.pcm` in the GPU helper sandbox ("Operation not permitted"), every ANGLE MSL compile fails. Separate bug (in-sandbox MSL source compile). |
| GL + `NVMTL_NO_DESCCACHE/DIRTYONLY/IPARK/BUFREUSE/SAMPCACHE/IDVIEW=1` | glitch unchanged: plugin caches ruled out |
| GL + `NVMTL_SCHEDULE_AFTER_SURFACE_WRITES=1` | glitch unchanged: cross-process IOSurface ordering ruled out (NMXFence marks only run in WindowServer, still worth noting) |
| `--disable-gpu --disable-gpu-compositing` | control started (GPU helper made 0 pipelines); owner result not recorded before the hold |
Also checked: `isComplete`/`waitUntilComplete` answers come from `_resRefs`, released at command buffer completion (correct).

Next (when resumed): a differential GL harness. Run the same CGL program on the 890M and on Apple's software renderer
(`kCGLRendererGenericFloatID`, GLRendererFloat is present), diff the pixels per op: per-draw uniform updates (ring offsets),
premultiplied blend, scissor, glTexSubImage, FBO to texture, glBlitFramebuffer/glCopyTexSubImage, TEXTURE_RECTANGLE from
an IOSurface, share-group contexts. The first op that differs points into the GL bridge / translator. Fix goes in the
plugin fork (nmx-plugin-desccache) or the translator, not in Zalo.

**Step116 lid test (13:48, StrixS0ix 0.1.6 live, d3 0): still no wake, forced restart.**
- powerd: `Entering Sleep state due to 'Clamshell Sleep'` at 13:48:19. The kernel log from about 13:47 was lost
  again.
- So the EC GPE wake alone did not fix it, or the hang is elsewhere: the clamshell sleep entry, or the wake with the
  lid open.
- Every Software Sleep test (four runs) woke by RTC.
- Next: `scripts/s0ix-tools/lid-rtc-test.sh`. It sets an RTC alarm after the password, then the lid is closed and
  kept closed past the alarm. On the first wake the script dumps and syncs the kernel trace before the lid is opened.
  - The RTC wakes it: the halt path works in clamshell, and the hang is the lid-open wake.
  - The RTC does not wake it: the clamshell sleep entry hangs.

**Lid + RTC test 14:11 (0.1.6, d3 0): the clamshell sleep entry is fine; the lid-open / power-button wake is what fails.**
- The lid closed at 14:11:20 and `Clamshell Sleep` started at 14:11:34. NVRM standby took 7.0 s, then halt.
- The RTC woke the machine at 14:13:29 with the lid still closed: `wake event 0x400 (RTC)`, 105.9 s idle, cc6 1.
- Not met: DISPLAY 105884, CPU 19, NBIO 105884 ms.
- `GPE0_EN at halt 0x600a104`: bits 2, 8, 13, 15, 25 and 26 are enabled. Bit 10 (EC) is not, which confirms that
  macOS disables the EC GPE. 0.1.6 set it for the halt.
- At the wake (14:13:29.004) the root domain read the lid as **open** while it was still closed (`clamshell closed 0`).
  `LID0._LID` returns 1 (open) while `EC0.ECOK` is 0, so right after the wake the EC is not yet usable by AML. The
  machine therefore did a full wake.
- So with the EC GPE enabled, a lid open or a power button press during the sleep still does not end it. Either the EC
  raises no GPE0 status in this state, or the wake that follows hangs. The trace cannot say which: the kernel log
  never survives the forced restart.

**Step118: StrixS0ix 0.1.7, observe mode (installed, reboot pending).**
- `s0ix-set ecwake 2`: the EC GPE is not enabled and the boot CPU stays on the MWAITX loop (0.25 s polls).
- Every PM1 / GPE0 status bit raised while halted is recorded with its first time. The log line is
  `status bits raised while halted: ... GPE0xa@61234ms`, and the same data is in `S0ix,SeenGpe0Sts` and
  `S0ix,SeenPm1Sts`.
- The RTC still ends the sleep, so a lid open or a power button press during the sleep shows which bit it raises,
  and no forced restart is needed.
- `ecwake 0|1` = off / wake source (1 is the default, as in 0.1.6).

Test (one password):
- `S0IX_PRE="$PWD/build/s0ix-set ecwake 2" scripts/s0ix-tools/lid-rtc-test.sh 180`.
- Close the lid at once. Open it at about 60 s (the screen stays dark), and press the power button once at about 120 s.
- At 180 s the RTC wakes the machine; read the raised bits.

**Observe run 14:38 (0.1.7, `ecwake 2`, MWAITX loop): the lid and the power button raise no GPE0 and no PM1 bit.**
- The lid closed at 14:38:27 and halt began at about 14:38:51. The owner opened the lid at about 30 s and pressed the
  power button at about 60 s.
- The RTC woke the machine at 14:39:52 (60.5 s): `SeenGpe0Sts = 0`, `SeenPm1Sts = 0x410`. Bit 10 is RTC and bit 4 is
  BM_STS, and both appear only at 60519 ms, which is the alarm.
- So neither event reaches GPE 0x0A or PWRBTN_STS during the sleep. 0.1.6's EC GPE enable could never have worked.
- **Where they go (SSDT-22):** `\_SB.GPIO._AEI` lists pin 0, plus pins 5, 0x10, 0x3A, 0x3B, 0x36 and 0x12 (D3C).
  - Pin 0 is `PBTN`: Edge, ActiveHigh, ExclusiveAndWake, debounce 50 ms. It is listed when `CMBS == 0`, which is this
    machine's case.
  - `_EVT(0)` reads EC BACH, then does `Notify (\_SB.PWRB, 0x80)` and `Notify (\_SB.LID0, 0x80)`.
  - AMD GPIO 0 is the PWR_BTN_L pin. In Modern Standby the EC pulses it for the lid and for the button. At runtime the
    same events also come as EC queries (`_Q2F`, `_QE7`), which is why lid close and the power button work while
    awake.
- macOS has no `_AEI` / `_EVT` support. The AMDI0030 controller is bound to VoodooGPIOAMD (IRQ 7), which serves only the
  touchpad's pin. Nothing arms pin 0, and nothing runs `_EVT`.
- Latent issue: at the RTC wake the lid read as open while it was closed. `LID0._LID` returns 1 when `EC0.ECOK` is 0,
  so any dark wake in a closed laptop can turn into a full wake with the screen on. This needs an SSDT: `_LID` should
  return the last EC state while ECOK is 0.

**Step119: StrixS0ix 0.1.8, GPIO pin 0 wake (installed, reboot pending).**
- `haltEnter` maps AMDI0030 MMIO and saves the pin 0 control word. It sets InterruptEnable (bit 11), the IRQ delivery
  mask bit (12) and S0i3 wake (13), and clears the latched status (W1C bits 28/29), which drops the lid-close pulse.
- `wakeEvent`: pin 0 interrupt or wake status is wake event `0x20000` ("GPIO 0: lid/power button").
- `haltExit` puts back the old control word with the status cleared, before interrupts come back, so VoodooGPIO never
  sees a pin 0 interrupt.
- 300 ms after a pin 0 wake, a thread call evaluates `\_SB.GPIO._EVT(0)`. That delivers the Notify that Linux and
  Windows deliver.
- The boot CPU stays on the MWAITX loop while pin 0 is armed (`gpiocc6 off`, the default) until IRQ 7 is proven to end
  CC6.
- `s0ix-set gpiowake 0|1|2`: off / wake / observe. Boot-arg `s0ix_gpiowake`.
- Logged on every wake: pin 0 at halt and at wake, when its status was first seen, and the level toggles.
- Test: `scripts/s0ix-tools/lid-rtc-test.sh 90` (RTC safety net at 90 s). Open the lid at about 30 s: it must wake at
  once with `wake event 0x20000`. Then the same with the power button.

**Latent lid-state bug traced: `_LID` reads "open" from the wake until `EC0._PS0` (SSDT-LIDFIX, on the ESP, next boot).**
- Firmware `LID0._LID` (DSDT line 14573) is `If (EC0.ECOK) { LIDS ? 0 : 1 } Else { Return (One) }`.
- `EC0._PS3` sets `ECOK = Zero` and `_PS0` sets it back from `OKEC`. macOS power-manages the EC0 device (AppleACPIEC),
  so during sleep and right after the wake `_LID` reports **open**.
- Seen at the 14:13 RTC wake: the root domain logged `clamshell closed 0` 4 ms after the wake with the lid shut, and
  did a full wake.
- Risk: any dark wake in a closed laptop (RTC, maintenance, network, a later EC/GPIO event) can turn into a full wake
  with the panel on, in a bag.
- `LIDS` is bit 5 of ERAM byte 0x52. ERAM is `SystemMemory 0xFEDD8300`, the EC RAM window that SSDT-ECRAM already
  reads at runtime, so it is valid with the EC in D3. `ECOK` gates only the EmbeddedControl region.
- **Fix:**
  - `acpi/SSDT-LIDFIX.dsl`: under Darwin, `_LID` reads `LIDS` directly, still taking MUT0 like the firmware. Other OSes
    run the firmware method.
  - OpenCore patch `_LID to XLID`, DSDT only, Find `5F4C494400A0` → `584C494400A0`. It is unique in the live DSDT
    (SysReport copy, 66513 bytes).
  - The table and the ACPI/Add entry are on the ESP. Backup: `config.plist.pre-lidfix`. ocvalidate is clean.
  - Undo: disable both entries together.
- Check after the boot:
  - `ioreg -r -k AppleClamshellState -d1` follows the lid.
  - In the next lid + RTC test, the RTC wake with the lid shut logs `clamshell closed 1` and stays a dark wake.

## Step119 lid test 17:01 (0.1.8, battery) and Step120

- What happened: lid closed, the machine went to sleep. The owner opened the lid at about 17:02:25 (around 50 s asleep) and the screen stayed dark. The machine woke by itself at 17:02:54.
- Trace:
  - The wake came from the MWAITX poll, not from an interrupt: `wake event 0x1000a (EC: lid/button/other)` after 56867 ms idle, `PM1.4@56868ms GPE0xa@56868ms`.
  - GPIO pin 0 was 0x8150b00 at halt and 0x8153b00 at wake. The only change is our armed bits 12/13. No status bit, no level toggle, at any point.
- Reading: the lid open did not reach the SoC on _AEI pin 0, and it raised no SCI for about 30 s. The EC GPE that finally fired may have been that delayed lid event, or a periodic EC event (battery). A full wake then followed because `_LID` reads "open" while EC0 is in D3 (fixed by SSDT-LIDFIX, active next boot).
- Suspect: the PEP _DSM Modern Standby commands we send at sleep.
  - fn 3: `ECMD 0x97`, `HBHT = 1`.
  - fn 7: `UPHK` → `ECM1 0x98`.
  - Neither checks ECOK. Both are sent from `setPowerState(0)` after EC0 `_PS3`.
  - In this mode the EC may hold lid events back, or signal them on a pin other than 0.
- Step120 = StrixS0ix 0.1.9 (`scripts/macos-install-step120.sh`, `--undo`):
  - Every _AEI pin (0, 5, 0x10, 0x3A, 0x3B, 0x36, 0x12) is sampled in the MWAITX loop. The log line is `_AEI pin X halt/wake/changes/first at ms`.
  - New switch `S0ix,DsmSkip` (`s0ix-set dsmskip MASK`): `0x180` leaves out fn 7/8, `0x18` leaves out fn 3/4. Default 0.
- Next boot, with SSDT-LIDFIX: three 90 s lid tests, each opening the lid at about 45 s.
  - A: defaults.
  - B: `dsmskip 0x180`.
  - C: `dsmskip 0x198`.
  - For each, compare the time from lid open to the GPE 0x0A status bit, and which pin moved.

## Edge web video lag (2026-11-05 17:15-17:25, diagnose only, nothing installed)

Owner report: web video in Microsoft Edge 156.0.4314.58 is still slightly laggy; `edge://gpu` shows Canvas
"software only". Method: a second Edge instance with a throwaway profile (scratchpad, `--remote-debugging-port`),
YouTube "COSTA RICA IN 4K 60fps" (LXb3EKWsInQ) muted, quality pinned through the player API, other codecs hidden from
YouTube by overriding `MediaSource.isTypeSupported` / `mediaCapabilities.decodingInfo` in the page. Decoder names from
the DevTools Media domain (= media-internals), frame counts from `getVideoPlaybackQuality()`, CPU from `top`
(2 s samples, averages slightly low because the first sample reads 0). The owner's own Edge was left alone.
powermetrics was not run: the top/log evidence is already conclusive, and it needs a password prompt.

### 1. Decode: almost no hardware decode, and VTStub causes a fallback stutter
| content | Edge picks first | result | final decoder | CPU in the decoding process |
|---|---|---|---|---|
| VP9 1080p60 (YouTube default) | VideoToolboxVideoDecoder | "video decoder fallback after initial decode error" | **VpxVideoDecoder** (libvpx, renderer) | renderer ~64 % |
| VP9 2160p60 | VideoToolboxVideoDecoder | same fallback | **VpxVideoDecoder** | renderer **~190 %** |
| AV1 1440p/1080p | VideoToolboxVideoDecoder | same fallback | **Dav1dVideoDecoder** | renderer ~40 % (short run) |
| H.264 High 1080p60 | VideoToolboxVideoDecoder | stays | VT, but **AppleH264SW** in VTDecoderXPCService | VTDecoderXPCService ~39 % |

- Why: VTStub (Step108) is still in `/System/Library/Video/Plug-Ins` and `/tmp/vtstub.on` does not exist. Its
  Info.plist advertises avc1/hvc1/vp09/av01 as hardware with rating 1000, so `VTIsHardwareDecodeSupported` = 1 and
  `edge://gpu` lists "Decode vp9/av1/hevc/h264 ... Hardware accelerated". Chrome then opens a VT session, VideoToolbox
  calls the stub first, and the stub refuses: log `VTSTUB CreateInstance codec=vp09 refused (no /tmp/vtstub.on)` (same
  for av01, avc1). For VP9/AV1 there is no Apple fallback in VT here (AppleGVAVPXDecoder/AV1 hardware needs Apple
  silicon), so the first frame fails and Chrome reinitialises in software. For H.264, VT falls back to AppleH264SW,
  which is CPU decode inside VTDecoderXPCService and still counts as a platform decoder.
- Cost of the fallback: every new decoder runs it again, and YouTube creates a new decoder at start, on every
  quality/ABR switch and on seeks. Measured: 50 of the first 105 frames dropped at 1080p start, 79-108 dropped in the
  first ~700 frames on other runs. That is ~1 s of stutter each time. In steady state only 0.6-2 % of frames drop
  (9-31 of ~1440 in 24 s). This matches "slightly laggy": mostly hitches, not a constantly low frame rate.
- VTStub's fake capability also makes MediaCapabilities report VP9/AV1 4K60 as power efficient, so YouTube serves
  4K60 VP9, which then software-decodes at ~190 % CPU.
- The VCN path (Step106/106b, bit-exact via RADV Vulkan Video) is not used by any browser: the live RADV has no
  H.264/HEVC and there is no real VideoToolbox decoder yet.

### 2. GPU process: on the 890M, but Chrome believes it is NVIDIA
- Edge GPU process (`--type=gpu-process`) maps NVMTLDriver + `/Library/GPUBundles/nvmtl/libvulkan_radeon.dylib`;
  GL_RENDERER `ANGLE Metal Renderer: AMD Radeon 890M Graphics (RADV STRIX1) (NVMTL over ... 890M ...)`,
  Skia backend `GraphiteDawnMetal`. Drawing really runs on the 890M.
- `edge://gpu` GPU0 is `VENDOR=0x10de DEVICE=0x2d59` (RTX 5060 Laptop) with the 890M strings. Chrome takes the PCI
  ids from the IOKit parent of the Metal device's registryID. The default Metal device is the NVMTL instance under
  `PEGP@0/NVAccel` (NVIDIA, MetalPluginName NVMTLDriver), while NMXAccel (890M) carries a second one. NVMTL routes
  that device's work to RADV, but its identity stays NVIDIA.
- Per-frame cost at 60 fps VP9 1080p (small 809x455 player, 120 Hz panel): Edge GPU process ~38-44 % CPU,
  WindowServer ~92-104 % (58 % idle with the same windows; boot baseline ~32 %). A 4 s `sample` of the GPU process
  shows no CPU readback/upload hot spot in user space (no ReadPixels/getBytes/IOSurfaceLock; 8 samples of
  memmove). The nvmtl.execution queue is blocked in `drmSyncobjWait` (150/159), and the rest is mach_msg/kevent
  waits. So the GPU-process CPU is mostly kernel/IPC time plus the libvpx-frame upload, not a copy loop. WindowServer's
  per-frame cost is the known NVMTL per-draw/CA cost (Step100-101, Step104b), multiplied by a 60 fps layer update.

### 3. Canvas "software only" = Chrome's NVIDIA-on-Mac blocklist entry
`Problems Detected`: "Don't use the OOPR Canvas feature on Macs with NVIDIA GPUs: 1227033 ... Disabled Features:
accelerated_2d_canvas". It matches because of the 0x10de vendor id above, not because of anything wrong with the
890M. Driver Bug Workarounds also list `force_low_power_gpu` and `disable_ms_video_super_resolution` (dual-GPU/NVIDIA
rules). Check: a test instance with `--ignore-gpu-blocklist` reports `2d_canvas: enabled`, same workarounds. Software
canvas hurts sites that draw video into a canvas (YouTube ambient mode, web players with canvas renderers): each such
draw becomes a GPU->CPU readback.

### Root cause, ranked
1. **VTStub's hardware claim** (Step108, gated off) sends every VP9/AV1/H.264 stream into VideoToolbox first. VP9/AV1
   fail and fall back to libvpx/dav1d with ~1 s of dropped frames at start, on each quality switch and on seeks.
   H.264 decodes in software inside VT.
2. **All decode is CPU decode** (libvpx / dav1d / AppleH264SW). At 4K60 that is ~190 % CPU in the renderer.
3. **High per-frame compositing cost**: WindowServer +35-45 % and the GPU process ~40 % at 60 fps, from the NVMTL/CA
   cost already traced (Step101 and later), not a new readback.
4. **Canvas on software**, because NVMTL's default Metal device has NVIDIA's PCI identity. This matters only for
   canvas-based players.

### Proposed next fixes
- A (quick, next reboot, owned by the main session): remove VTStub (`tools/890m/vtstub/install.sh --undo --system`)
  until a real decoder replaces it. Chrome then goes straight to libvpx/dav1d with no failed VT init, and stops
  advertising 4K60 VP9 as power efficient. Expect the start/switch stutter to go away. CPU decode stays.
- B (owner, no reboot): Edge `edge://flags/#ignore-gpu-blocklist` gives hardware Canvas back now. Or, in the driver:
  make the NVMTL device that is routed to RADV report NMXAccel's registryID (890M, 0x1002:0x150e), so Chrome sees AMD
  and drops the NVIDIA rules (canvas, force_low_power_gpu). Untested: Chrome may also change other AMD-specific
  workarounds, so A/B it.
- C (the real fix, from Step106b): a VideoToolbox decoder backed by RADV Vulkan Video in VTStub's place, with
  VP9/AV1 first (the live RADV already has them) and H.264/HEVC after an installable `-Dvideo-codecs=all` RADV. It
  should output IOSurface-backed CVPixelBuffers, so Chrome can hand frames to CoreAnimation as overlays without an
  upload.
- D: WindowServer per-frame cost stays the general NVMTL item. Re-measure after A and C, because zero-copy overlays
  should also cut the GPU-process share.
- Not useful: the guessed `--disable-features=VideoToolboxVp9Decoding,VideoToolboxAv1Decoding` had no effect in Edge
  156 (VT was still tried first).

- 17:3x: VTStub removed (`tools/890m/vtstub/install.sh --undo --system`), new snapshot blessed; live after the next reboot (batched with Step120 + SSDT-LIDFIX). Recheck Edge: no "decoder fallback", no dropped-frame burst at start/quality switch.

### Edge video lag, part 2 (2026-11-05 18:11-18:20, boot 18:03 without VTStub, diagnose only)

Same method (throwaway Edge profile, DevTools port, YouTube LXb3EKWsInQ), plus a `requestVideoFrameCallback` and
`requestAnimationFrame` probe in the page that records every presentation gap over 25 ms, and a 6 s `sample` of
WindowServer (root, via osascript).

**Fix A works.** `edge://gpu` no longer lists H.264/VP9/AV1 hardware decode (only HEVC, Apple's own claim). Chrome
now logs `Cannot select VideoToolboxVideoDecoder ... kUnsupportedConfig` and picks VpxVideoDecoder/Dav1dVideoDecoder
directly, with no "fallback after initial decode error". Steady 22 s windows: VP9 1080p60 drops 0 of 1320 frames,
VP9 2160p60 drops 0 of 1318 (renderer ~198 % CPU, libvpx), seek +60 s drops 0. CPU: WindowServer 63 % idle, ~96-107 %
while playing; Edge GPU process 22-31 %; renderer ~49 % at 1080p.

**What is left is presentation hitches, and they come from WindowServer.**
- VP9 1080p60, 30 s: p50 16.6 ms, 11 gaps of 25-49 ms. VP9 1080p60, 60 s: p99 42.5 ms, 162 gaps over 25 ms and 40
  skipped presentations. Most of them (87) fell in 18:18:20-30, when NotificationCenter drew a banner and the owner
  clicked: any extra WindowServer work shows up as video hitches. AV1 1080p30: only 2 gaps (63/67 ms) in 20 s.
- The page's own rAF clock skips at the same instants as the video, so the frame clock misses frames. Decode is not
  the cause.
- Edge GPU process `sample` during playback: CrGpuMain/main thread and VizCompositorThread are idle ~97 % of samples
  (mach_msg waits). Edge is not the bottleneck.
- WindowServer `sample` (6 s, VP9 1080p60): `ws_main_thread` is busy 78 % of samples. Another ~14 % is blocked
  ioctls: `amdgpu_create_bo_from_user_mem` 180, `ac_drm_cs_submit_raw2` 199, `bo_destroy` 91, `drmNmxMmap` 66.
  So about 92 % of the main thread is spent, with no headroom left for a 60 fps client plus anything else.
- Where the busy time goes: `CA::OGL::render_contents_background -> bind_image -> MetalContext::update_surface ->
  -[NVMTLDevice newTextureWithDescriptor:iosurface:plane:]` (2733 samples, ~70 % of the main thread) ->
  `nvmtlNewSurfaceTexture` -> **`nvmtl_surface_keep` 2451** (+ `nvmtl_vk_buffer_import_host` 200). Leaves:
  `-[__NSDictionaryM objectForKeyedSubscript:]` -> `-[NSArray isEqualToArray:]` -> `-[__NSCFNumber compare:]`.

**Root cause (NVMTL plugin, `plugin/NVMTLDevice.m` `nvmtl_surface_keep`, same code in desc-cache, renderbox and
890m branches):**
1. The surface keep and its `used` timestamps are NSMutableDictionary objects keyed by
   `@[@(IOSurfaceID), @(plane), @(w), @(h), @(pixelFormat), @(ropt), @(fbo)]`. `-[NSArray hash]` is the element count,
   so every key hashes to 7 (checked: `@[@463,…].hash == @[@999,…].hash == 7`). Every lookup is a linear scan of
   7-number `isEqualToArray:` compares. The weak NSMapTable cache uses the same keys.
2. Every cache miss (a new wrapper for a surface) runs the eviction sweep over `keep.allKeys` with two such lookups
   per key, so one insert costs O(n^2) NSNumber compares. Measured on this CPU, a standalone copy of the sweep takes
   0.7 ms at n=100, 2.5 ms at 200, 10.5 ms at 400 and 36.6 ms at 800. The frame budget is 8.3 ms at 120 Hz. WindowServer
   holds keep entries for every surface any client still retains, plus up to 48 idle host entries.
3. During video, misses happen every frame (the `buffer_import_host` + `create_bo_from_user_mem` + `bo_destroy`
   ioctls in the same sample: the surface's pages are pinned and imported again). Which part of the 7-field key
   changes per frame for Chrome's video layer (a new IOSurface from Chrome's pool, the second plane, a different
   pixelFormat/ropt from CA) is not yet known.
This is very likely also the general "WindowServer 50-100 % CPU" seen since Step104b, because any client that updates
IOSurface contents pays it. Idle WindowServer was not sampled this time.

**Proposed fix (NVMTL plugin, NullMoth code: stays in the nmx-plugin-* fork, not this repo):**
- Key the keep/used/cache maps by a real hash: a C struct key in a CFDictionary with custom callbacks, or one
  NSNumber/NSValue packing (IOSurfaceID, plane, fmt, ropt, fbo) with w/h checked on hit. Merge keep and used into
  one entry {texture, lastUsedMs}.
- Run the eviction sweep at most every ~250 ms or when the map grows past a bound, not on every insert. Find held vs
  unheld entries without two dictionary lookups per key.
- Then log the miss reason for Chrome's video layer (which key field differs from the previous entry for the same
  IOSurfaceID). If the IOSurface is the same and only ropt/fbo/pixelFormat differ, share one host import per
  (surface, plane) and make views, so the userptr BO is not re-imported each frame.
- Measure again with the same probes: WindowServer main-thread busy %, gaps over 25 ms per minute (target 0 without
  other activity), CPU at idle.
- Still open from part 1: Canvas software via the NVIDIA PCI identity (fix B), and CPU decode (fix C, VCN-backed
  VideoToolbox decoder).

### Edge video lag, part 3: surface keep fix (2026-11-05 18:20-18:40, installed, WindowServer loads it at the next boot)

- Fork branch `surface-keep-hash` (ff0ebef, cut from desc-cache e1d1e26 = the live 9d816dc7 build, pushed to `fork`),
  `plugin/NVMTLDevice.m`:
  - `NVMTLSurfKey` (7 fields, splitmix64 hash, field compare) replaces the NSArray key in the weak cache and the keep.
  - The keep's `used` map is merged into the keep entry (`NVMTLSurfKeep {texture, last}`). The old `used` map also
    leaked a stamp for every key touched after its keep entry went.
  - The sweep enumerates in place: no `allKeys` copy, one lookup per dropped entry. The rules are unchanged: held
    entries stay; unheld host entries stay for `NVMTL_KEEP_MS` 3000 and are capped at `NVMTL_KEEP_IDLE` 48; others
    go.
  - Miss accounting: the first 12 misses are logged with their reason (`new surface`, `same surface, other key`,
    `dropped: unheld|expired|idle cap`). After that, one summary line every 30 s: `surface keep: 30 s: hits …,
    misses … (…), N entries, sweep avg/max us`.
- Build: the same clang line as build/build_plugin.sh plus `-framework IOKit`, with
  `-I radv-video/Vulkan-Headers-1.4.330/include`. A base build of e1d1e26 with this line has the same segment sizes and
  symbols as the live plugin. 336 warnings, none new. Artifact
  `nmx-plugin-890m/out/plugin-surfkeep-ff0ebef/NVMTLDriver`, LC_UUID 95F40145-4825-3874-B14D-1C46A1FECC7D.
- Test `plugin/tests/surfkeep_test.m` (`NM_TEST_PLUGIN=… NM_TEST_ACCEL=NMXAccel`, on the 890M, no install):
  - A wrapper clears the surface green and goes away. The next wrapper must read green, clear it red, and the one
    after must read red. An sRGB wrapper of the same surface also works. PASS on base and fix.
  - Then it holds N wrapped surfaces and wraps 200 fresh ones:

  | live surfaces | base miss avg / max | fix miss avg / max | base hit | fix hit |
  |---|---|---|---|---|
  | 100 | 3011 / 6243 us | 192 / 642 us | 11.6 us | 6.2 us |
  | 400 | 12061 / 21521 us | 309 / 3715 us | 21.6 us | 6.6 us |

- Installed 18:26 with `scripts/macos-nvmtl-plugin-install.sh` (bundle binary 57aee79b89b0ffbc, backup
  /Library/NullMoth/nvmtl-plugin-20261105T113638Z = 9d816dc7), then `scripts/macos-install-strixsbxmap.sh --refresh`
  (new NVMTLDriver cdhash 3fca36be…, ESP + live sysctl, stale=0). Apps started since then (WallpaperDynamicExtension,
  Edge GPU process) load it and log `surface keep: miss (new surface)` / hits, with no errors.
- Edge A/B in its GPU process (fresh test instance, VP9 1080p60 forced, 20 s window), base reinstalled in between.
  Background load was higher than in part 2 (Docker, Zalo; WindowServer 83-100 %):
  - base: 251 and 224 drops of ~1200, GPU process ~57 %.
  - fix: 30 and 197 drops of ~1200, GPU process 42-56 %.
  - This is the same within noise. Edge's GPU process holds few surfaces, and WindowServer is still on the old plugin
    until it restarts, so the drops come from WindowServer at ~95 %, not from the plugin in Edge.
- After the next boot (reboot owned by the main session, nothing to do before it):
  1. `/usr/bin/log show --last 5m --predicate 'process == "WindowServer" AND eventMessage CONTAINS "surface keep"'`.
     The 30 s line gives the miss rate and its reasons. If `dropped: idle cap` dominates during video, raise
     `NVMTL_KEEP_IDLE` in nvrm610.conf. If `same surface, other key` dominates, share one import per (surface, plane).
  2. WindowServer `sample` during the same video: `nvmtl_surface_keep` should be near 0. Measure main-thread busy %.
  3. Hitch probe (`hitch.mjs`: rVFC/rAF gaps over 25 ms per 30 s; was 11-162) and WindowServer idle CPU (was 58-83 %).
- Undo: `sudo scripts/macos-nvmtl-plugin-install.sh --undo`, then `scripts/macos-install-strixsbxmap.sh --refresh`.
- Idle check, 18:45 (owner: "the whole machine stalls with only Docker + Zalo open"; WindowServer 74-100 % with no video,
  still on the old plugin): a 6 s WindowServer `sample` shows `nvmtl_surface_keep` in **3075 of 4802 main-thread
  samples (64 %)** at idle. 2550 of those are in `objectForKeyedSubscript:` -> `isEqualToArray:`, and 1148 in the
  idle-cap LRU sort, whose comparator does two colliding lookups per compare. Path: `update_display_callback ->
  CompositorMetal::composite -> CA::OGL::render_contents_background -> bind_image -> update_surface ->
  newTextureWithDescriptor:iosurface:plane:`. So the same O(n^2) keep is the root cause of the general WindowServer CPU
  and desktop stalls, not just of video. Every client window or layer that updates (Zalo/Electron, Docker Desktop,
  Claude) adds entries, so n grows and the cost per miss grows with n^2. The fixed plugin is installed. WindowServer
  maps it only when it restarts (log out and back in, or the pending reboot).

## Step120 results (18:48-19:13) and Step121

The owner ran the tests with the lid opened at about 45 s; the RTC alarm was the safety net.

| test | settings | result |
|---|---|---|
| A | defaults (_DSM 3/7/5, GPIO pin 0 armed) | Lid open: nothing. No _AEI pin moved (0, 5, 0x10, 0x3A, 0x3B, 0x36, 0x12), no GPE0, no PM1 for 80 s. Woke on the RTC. |
| B | `dsmskip 0x180` (no fn 7/8 = EC 0x98/0x86) | **Lid open woke it at once**: GPE 0x0A, "Wake ... due to /Lid Open", full wake in about 1 s. |
| D | B + RTC alarm with the lid closed | SSDT-LIDFIX works: the clamshell stays closed and the machine goes back to sleep. Lid open later woke it at once (18:56:10). |
| E | B + `gpiowake 0` (CC6 loop) | Lid open wakes. CPU not-met is down to 19 ms from the whole sleep. Only DISPLAY and NBIO still block S0i3. |
| F | power button, lid open | No pin, GPE or PM1 bit when pressed during the halt (19:10, 19:11 with pin 0 armed, 19:13 with `dsmskip 0x198`). |

- Root cause of the lid wake: PEP _DSM fn 7 (`UPHK` → `ECM1 0x98`) puts the EC in a mode with no lid SCI. It does not use GPIO pin 0 for the lid either. Leaving out fn 7/8 fixes it.
- Power button:
  - The two runs with the old script (10 s before sleep, press after about 30 s) show the press as an EC GPE wake that ends in a dark wake only: 18:59:18 "DarkWake ... due to /" and 19:03:21, then maintenance sleep.
  - In the later runs the press came about 12 s after the screen went off. That is while macOS is still suspending drivers, before the halt (sleep is entered about 15-25 s after `pmset sleepnow`), so the press was lost.
  - So the button reaches the halt, but macOS does not treat it as user activity.
- Leftover RTC alarms from earlier tests made some wakes look like full wakes (18:54:58, 18:59:39). `scripts/s0ix-tools/cancel-pmset-wakes.sh` now runs in each root step. The syssleep test now sleeps 3 s after the password.
- Step121 = StrixS0ix 0.1.10 (`scripts/macos-install-step121.sh`):
  - Defaults are now DsmSkip 0x180 and GPIO wake off.
  - PWRB (PNP0C0C) is watched with `registerInterest`. On `kIOACPIMessageDeviceNotification` 0x80 within 60 s of our wake, it tickles IODisplayWrangler (`activityTickle`; `requestUserActive` is not exported to kexts), which the root domain turns into a full wake from dark wake.
  - Each PWRB message is logged with its type, argument and time.
  - Reboot pending.
- Next: power button test with the press about 30 s after the screen goes off, then a long sleep to check the fans and the EC dark wakes.

## Step121 power button test (19:21) and Step122

- 0.1.10 was live after the reboot: PWRB was being watched, DsmSkip 0x180 and GPIO wake off were the defaults.
- The owner pressed the power button about 30 s after the screen went off:
  - At 19:22:33 the EC GPE 0x0A woke the halt (11.7 s into it). It was only a dark wake ("due to /").
  - **No PWRB message reached the interest handler.** So either `_QE7` → `Notify(PWRB, 0x80)` did not run, or macOS delivers it only to AppleACPIButton, which does not turn it into a full wake from dark wake.
  - The full wake came at 19:22:58 from the test script (HID activity).
- Step122 = StrixS0ix 0.1.11 (`scripts/macos-install-step122.sh`):
  - After an EC GPE wake, while still in the halt path, the kext takes the EC query itself: status 0x66 SCI_EVT, command 0x84, data 0x62, 5 ms timeouts.
  - 500 ms after the wake it runs that `_Qxx` on EC0 from a thread call and logs `EC query X at the wake`. AppleACPIEC then finds no SCI_EVT left.
  - On 0xE7 (`_QE7`, power button) it tickles IODisplayWrangler for a full wake.
  - Switch: `s0ix-set ecquery on|off`, boot-arg `s0ix_ecquery=0`.
  - The log will also show which query the earlier "EC: other" dark wakes carry (battery, thermal).

## Edge web video lag part 4: after the surface keep fix (boot 2026-11-05), buffer texture shadow copies

The surface keep fix (fork `surface-keep-hash` ff0ebef, plugin 57aee79b) was loaded by WindowServer at this boot.

| measure | before (part 2/3) | after the reboot |
|---|---|---|
| `nvmtl_surface_keep` share of WindowServer's main thread, idle | 64 % | 0.3 % |
| same, 60 fps video | ~63 % | 0.7 % |
| WindowServer CPU, idle | 58-83 % | 23.6 % |
| WindowServer CPU, VP9 60 fps in Edge | - | 55 % |
| hitch probe, VP9 60 fps, 60 s, no sampler attached | 162 gaps over 25 ms, 40 dropped (1080p60) | **3 gaps over 25 ms (worst 50 ms), 0 dropped**, p99 17.6 ms (YouTube ABR picked 720p60) |

- Keep stats: about 540 misses per 30 s, most of them "idle cap" (388). That is NVMTL_KEEP_IDLE 48; raising it is a tuning option, not done.
- What WindowServer's main thread still spends: about 55 % busy plus 12-16 % blocked in the submit ioctl (`ac_drm_cs_submit_raw2`).
  The biggest NVMTL item was **`nvmtl_btsh_rows` → `radv_CmdCopyBuffer2`: 887 of 4441 samples (20 %) during video, 322/3921 (8 %) idle**.
  - RenderBox masks in WindowServer are buffer textures like 176x48 R8 with bytesPerRow 192. GFX11 linear images need a 256-byte pitch, so NVMTL gives them a shadow image and copies the rows in before every command buffer that uses them (about 6 per command buffer).
  - The copy was one `VkBufferCopy` per row. RADV records every region as its own compute dispatch, so one mask cost 48 dispatches.
- Fix, fork `surface-keep-hash` **bf0ef9e**: each shadow gets a transfer-only twin image over the same memory (same format, size, pitch; usage TRANSFER_SRC|DST, kept in GENERAL). The upload is one `vkCmdCopyBufferToImage` with `bufferRowLength` = the app's pitch, and the writeback is one `vkCmdCopyImageToBuffer`. The tracked image's own layout is not touched. `NVMTL_BTSH_ROWCOPY=1` brings back the per-row copies; the log says `shadows made, N of them one-copy`.
  - `plugin/tests/btsh_test.m`: R8 176x48 pitch 192 read, read again after a CPU change, RGBA8 100x20 pitch 448 at offset 64, render-clear writeback (texels land, row padding and bytes before the offset untouched). PASS on both builds.
  - Cost, 300 command buffers with 6 shadowed masks each: commit CPU **117-128 us → 73-75 us**, GPU time the same (8 us). surfkeep_test still passes.
  - Installed as plugin d2b358c7 (backup /Library/NullMoth/nvmtl-plugin-20261105T123646Z), sbxmap pins refreshed. **WindowServer loads it at its next start** (log out/in or the pending reboot); new apps load it at once.
  - Undo: `sudo scripts/macos-nvmtl-plugin-install.sh --undo`, then `scripts/macos-install-strixsbxmap.sh --refresh`.
- Next after that boot: sample WindowServer during video again (btsh share should be near 0), then look at the submit ioctl wait and the remaining software paths (Canvas in software, CPU video decode).

## Edge web video lag part 5: after the btsh boot (2026-11-05 21:20) - the submit ioctl scales with live IOSurfaces

- WindowServer runs plugin d2b358c7 (bf0ef9e). Log: `1984 shadows made, 1984 of them one-copy`. Main thread sample (10 s, Zalo and Claude open):
  busy 48.7 %; `nvmtl_btsh_rows` **20 % → 0.2 %**; `nvmtl_surface_keep` 0.8 %; NVMTL plugin own code is small now.
- The largest item left is the submit: `vkQueueSubmit` → `radv_amdgpu_winsys_cs_submit` → `ac_drm_cs_submit_raw2` = **11.4 %** of the main thread (about 110 submits/s, so ~1 ms each).
- spindump with kernel stacks: 75 of 500 main-thread samples are in that ioctl, and almost all of them are **on CPU in NMXGPU**, not waiting:
  `drm_ioctl` → amdgpu CS ioctl → `amdgpu_cs_p1_bo_handles`, `amdgpu_bo_list_create`, `drm_exec_prepare_obj`/`drm_exec_lock_obj` (`linux_ww_mutex_lock_sub`, `nmx_sx_try_xlock`), `amdgpu_cs_bo_validate`, `drm_gem_object_lookup`, `ttm_resource_compatible`, `amdgpu_ttm_tt_is_userptr`.
  That is the per-BO work of the BO list: the cost grows with the number of BOs every submit carries.
- Why so many BOs: RADV makes every non-WSI allocation resident (`buffer_make_resident(true)` in radv_device_memory.c). Private allocations are `is_local` (`AMDGPU_GEM_CREATE_VM_ALWAYS_VALID`) and stay off the list, but **host-pointer imports are not local**. NVMTL imports every IOSurface that way (`create_bo_from_user_mem` / `radv_bo_from_ptr`), so every live IOSurface texture is in RADV's global BO list and goes to the kernel with **every** submit, used or not.
- Measured (`plugin/tests/submit_scale_test.m`, fork surface-keep-hash 85914af): commit of a 256-byte copy

  | live shared MTLBuffers | live IOSurface textures | commit CPU |
  |---|---|---|
  | 0 | 0 | 100 us |
  | 1000 | 0 | 115 us |
  | 1000 | 250 | 480 us |
  | 1000 | 500 | 770 us |

  About 1.4 us per live IOSurface per submit. WindowServer has about 740 live images (image census) and ~110 submits/s → ~1 ms per submit → ~11 % of its main thread, the number the sample shows.
- **This is the "Docker + Zalo makes the machine stall" mechanism:** every window, layer and app surface is an IOSurface that WindowServer wraps, so each new window makes *every* WindowServer frame slower, linearly, until its main thread is full. Apps on the 890M pay the same per their own surfaces.
- Ways to fix it (to decide):
  1. Kernel (NMXGPU source build, already planned as tech debt): on macOS a host-pointer BO is wired memory that never moves, so it can be validated once and then treated like a VM_ALWAYS_VALID BO (kept off the per-submit list). Also cut the per-BO cost (ww_mutex over sx lock, lookups): 1.4 us per BO is several times Linux.
  2. RADV (our libvulkan_radeon): keep host-pointer imports off the global list after their first submit and add them to a command buffer only when NVMTL says it uses them (private entry point; NVMTL knows each command buffer's IOSurface textures). Needs care with bindless descriptors.
  3. Smaller: fewer imports (one BO per IOSurface, shared across planes/wrappers; release keep entries sooner).

## Step114b: DISPLAY IPS sleep trace added to the NMXGPU source build (2026-11-05, not built, not installed)

For the S0i3 blocker: every s0ix sleep the SMU marks DISPLAY (slot 0) and NBIO (slot 9) "not met" for the whole sleep,
even with the 890M in D3hot. The question is whether `dm_suspend` really gets DCN 3.5 into IPS.

On the same fork branch as Step114 (`xkpi-thread-lockfree`), commit **ec38af4**:
`gpu-port/xkpi/patches/amdgpu-dm-ips-trace.patch`, last in `patches/series`. The full series of 16 patches replays
cleanly on drm-kmod HEAD. Both patched files compile with the port's flags (tested in an APFS clone of the vendor tree,
so the shared tree is untouched). Log lines start with `NullMoth ips:` and appear once per suspend/resume:
- `dm_suspend`: one line each at "suspend before", "after dc_set_power_state(D3)", "after allow_idle_optimizations"
  (plus whether `dc_allow_idle_optimizations(true)` was called or skipped) and "suspend done (dmub D3)". Each line
  logs `in_s0ix`, `caps.ips_support`, `config.disable_ips`, `idle_optimizations_allowed`, the stream count of
  `current_state`, and the DMUB shared-state IPS signals with the RCG/IPS1/IPS2 entry/exit counters.
- `dm_resume` entry, before `apply_idle_power_optimizations(false)`: the same line.
- `dcn35_clk_mgr` init: `smu_ver`, `disable_ips` before and after, and `dcn35_smu_get_ips_supported`. If
  `disable_ips` is already DISABLE_ALL, the line says PMFW was not asked.

The DMUB counters are read from shared memory. I did not use the GPINT residency query
(`dc_dmub_srv_ips_query_residency_info`), because it wakes the DMCUB, which would change the very sleep being
measured.

How to read it:
- Entry counters unchanged between "suspend done" and "resume" while streams 0, `ips_support` 1 and the allow call
  ran: IPS is allowed but not entered.
- `ips_support` 0, or the allow call skipped: the IPS path is off by config or capability.
- Counters move but DISPLAY is still "not met": the blocker is somewhere else.

It ships in the same single NMXGPU build as Step114 and the NMXAMDFB busy hold (one build, one install, one reboot).

## Edge web video lag part 6: surface list (RADV + plugin), installed 2026-11-05 22:13

Fix for part 5 (every live IOSurface rode every submit), owner picked the RADV route.
- RADV: source build `~/develop/projects/radv-video/build-res.sh` = Mesa bffd919 + NullMoth mesa-macos.patch + radv-nmxmap.patch + **`scripts/radv/radv-nvmtl-surface-list.patch`** (MIT, ours):
  - winsys: a second list `surface_bo_list` next to the global BO list (same lock). `radv_amdgpu_nvmtl_bo_set_surface` moves a resident BO between them; a surface BO has `use_global_list = false`, so `radv_cs_add_buffer` adds it to the command streams that use it.
  - each `radv_amdgpu_cs` has `nvmtl_exact`; `radv_amdgpu_get_bo_list` adds the whole surface list unless every CS of the submit is exact. A client that never calls the new entry points gets the old behaviour.
  - `radv_nvmtl.c` exports `radv_nvmtl_abi` (1), `radv_nvmtl_memory_set_surface`, `radv_nvmtl_cmd_use_memory`, `radv_nvmtl_cmd_exact` (dlsym; NVMTL opens the ICD directly, so the handles are RADV's).
  - Install names: system libz, /Library/GPUBundles/nvmtl libdrm (every needed symbol is there), no rpaths, no libelf (the old test-build blocker).
- Plugin (fork `surface-keep-hash` **c315472**):
  - IOSurface host imports (`nvmtl_surface_image_create`) are moved to the surface list (`_hostSL`).
  - When a submission part is sealed, its resource set (the command buffer retains everything it uses until it completes, so it names every texture its commands touch) + dirty surfaces + drawable: each IOSurface texture's root allocation is added to the part's VkCommandBuffer, then the buffer is marked exact. Prologue and counter-reset command buffers (buffer copies, fills, query resets) are exact too. Any other submit stays non-exact and carries every surface.
  - `gpuResourceID` (argument encoders, residency through gpuResourceID) puts that texture's surface back on the global list, since an argument buffer can reach it without a binding.
  - `NVMTL_SURFACE_LIST=0` turns it off; with a RADV without `radv_nvmtl_abi` it stays off (log: `vk: surface list ON/OFF`).
- Harness (`submit_scale_test`, commit of a 256-byte copy, 1000 live buffers):

  | live IOSurface textures | live RADV | new RADV, list off | new RADV, list on |
  |---|---|---|---|
  | 0 | 115 us | 60 us | 56 us |
  | 250 | 480 us | 179 us | 58 us |
  | 500 | 770 us | 356 us | **48-58 us** |

  surfkeep_test (render into an IOSurface, read it through another) and btsh_test pass with the list on and off. No NMXGPU fault/timeout in the kernel log.
- Installed (22:13): RADV 2a2269ce (backup /Library/NullMoth/radv-live-20261105T151335Z), plugin 998153ff (backup nvmtl-plugin-20261105T151335Z), sbxmap pins refreshed (allowed 8, stale 0). New processes use it now (TextEdit: `surface list ON`); **WindowServer at the next boot**.
  - Each app recompiles its shaders once on the new driver (NVMTL fc cache miss, ~3.8 s for `fixed_frag_lpf_cpf`), WindowServer too at the first login.
  - Undo: `sudo scripts/macos-nvmtl-radv-install.sh --undo`, `sudo scripts/macos-nvmtl-plugin-install.sh --undo`, `scripts/macos-install-strixsbxmap.sh --refresh`.
- Next boot: WindowServer sample (submit ioctl share should drop from ~11 %), hitch probe, CPU with Docker + Zalo open.

Side note, the 21:58 freeze (owner force-rebooted at 22:00): the system log stops at 21:58:21 for every process; no NMXGPU fault/timeout. Just before: System Settings frontmost and a loginwindow password sheet (21:58:15). Nothing from this trace was running (source reading only; the RADV build started 22:07).

## Step122 power button test (22:18) and Step123

- 0.1.11 caught the power button press during the halt: the EC GPE 0x0A woke it (10.7 s into the halt, GPE 0x17 also set), and the kext read EC status 0x09 and **query 0xCE**. `_QCE` only does `DBG8 = 0xCE`: it is the EC's Modern Standby wake ping. Nothing in it notifies PWRB, so macOS stays in dark wake. 0xE7 (`_QE7`, Notify PWRB) is the awake path only.
- Step123 = StrixS0ix 0.1.12 (`scripts/macos-install-step123.sh`): a full wake (display wrangler tickle) on query 0xCE or 0xE7. The list is `S0ix,UserQueries` (`s0ix-set userq 0xE7CE`, boot-arg `s0ix_userq`), up to 4 bytes. Reboot pending.
- Open question: whether 0xCE also comes for non-user EC events (battery, charger). If so, a closed lid still sends macOS back to sleep. The lid query code is checked in the next lid test.
- 22:24 lid test on 0.1.11: lid open = EC query 0x2F (`_Q2F` run by us), "Wake ... due to /Lid Open", screen on. The query interception does not break the lid. So 0xCE is the power button, not a generic EC wake ping for every event.

## Edge web video lag part 7: first boot on the surface list (2026-11-06 12:50)

- WindowServer runs RADV 2a2269ce + plugin 998153ff: `vk: surface list ON`; census `1024 imports moved (0 refused, 0 back to global for gpuResourceID), 30252 command buffers exact, 192595 surface uses listed`, against ~30.5k submits: almost every submit is exact and lists ~6 surfaces.
- No NMXGPU fault/timeout. The one `NMX userptr: pin FAILED ... size 24000 -> -14` per boot was there before too (21:21, 21:39, 22:00 on 2026-11-05).
- WindowServer 2 min after login (Claude, Spotlight indexing): 25.6 % CPU. Main thread (10 s sample): busy 42.4 %; `ac_drm_cs_submit_raw2` **7.5 %** (was 11.4 %); surface_keep 0.3 %, btsh 0.2 %, `nvmtl_part_list_surfaces` 0.0 %.
- Smaller than the harness promised: ~140 submits/s, still ~0.5 ms each. spindump (kernel stacks): the time is still per-BO list work (`amdgpu_cs_p1_bo_handles`, `amdgpu_bo_list_create`, `drm_exec_lock_obj`, `amdgpu_cs_bo_validate`, `amdgpu_ttm_tt_get_usermm`). So the submits still carry many BOs that are neither surfaces nor local; in the harness the global list is empty.
- To see which: RADV `radv_nvmtl_stats` / `radv_nvmtl_global_breakdown` (patch updated) and plugin **eac2b8f** log `vk: BO list:` (global list by RADV_BO_PRIORITY, host-pointer or allocation, VRAM/GTT) after 256 submits, and live/handles-per-submit every 4096 submits. eac2b8f also fixes exact marking waiting for the first IOSurface import.
  Installed 14:19 (RADV 90402a4b, backup radv-live-20261106T061914Z; plugin 73ec26c8, backup nvmtl-plugin-20261106T061914Z; sbxmap allowed 16). Light apps (TextEdit, Notes, Safari) did not reach 256 submits; WindowServer logs it after the next boot.

## Edge web video lag part 8: the BO-list census names the rest (2026-11-06 13:41)

- Boot with RADV 90402a4b + plugin eac2b8f in WindowServer. `vk: BO list:` in WindowServer's log:
  - right after login: `14 global BOs: [prio 14 host-ptr GTT: 14, 5348 KB]`, 28 handles per submit (13.5 global);
  - once apps were open (~5 min): `515 global BOs: [prio 14 host-ptr GTT: 515, 45540 KB]`, **135.5 handles per submit (120.7 global)**, the most 526.
  - Only 7 of the first 20k submits carried the surface list (`2048 imports moved, 0 back to global`): the surface list works; what is left is one kind only.
- Priority 14 = an application allocation at the default VK_EXT_memory_priority, host-pointer, GTT, ~88 KB each: `newBufferWithBytesNoCopy` (NVMTLDevice_contract.m; Managed >= 1 MiB takes the VRAM-copy path instead). Every one of them went to the kernel on every submit, ~1.4 us each.
- Fix, plugin **8633045** (fork `surface-keep-hash`), no RADV change: the no-copy import goes on the same RADV list as the IOSurface imports (`nvmtl_vk_buffer_list_mark`). `nvmtl_part_list_surfaces` lists every retained NVMTLBuffer on the list, and a texture's backing buffer (`_backBuf`, so the buffer-texture shadow upload in the prologue is covered). A buffer whose address can reach the GPU without being retained goes back to the global list: `gpuAddress`, argument encoder `setBuffer`, `gpuResourceID` of a texture on it. Log: `vk: buffer list ON`, `buffer list: N no-copy imports moved, M back to global`. `NVMTL_BUFFER_LIST=0` turns it off.
- Harness `tests/nocopy_list_test.m`, commit of a blit that uses none of the live no-copy buffers:

  | live no-copy buffers | list off | list on |
  |---|---|---|
  | 0 | 58 us | 48 us |
  | 250 | 173 us | 46 us |
  | 500 | 322 us | 37 us |
  | 1000 | 514 us | **46 us** |

  With 1000 alive: no-copy -> no-copy copy, a texture on a no-copy buffer -> buffer, and a buffer after `gpuAddress` all read back correctly, on and off. No NMXGPU fault/timeout.
- Installed 13:48: plugin 5271bd8e (backup /Library/NullMoth/nvmtl-plugin-20261106T064753Z = eac2b8f), RADV unchanged (90402a4b), sbxmap refreshed (stale 0). TextEdit started on it, no fault. **WindowServer at the next boot.**
  - Undo: `sudo scripts/macos-nvmtl-plugin-install.sh --undo`, then `scripts/macos-install-strixsbxmap.sh --refresh`.
- Next boot, read in WindowServer's log: `buffer list: ... back to global` (if `gpuAddress` users send most of them back, the escape rule needs a finer test), `BO list: ... handles each` (expect ~15-30 instead of ~135), NMXGPU faults; then the WindowServer sample (submit ioctl share, was 7.5 %), CPU with Docker + Zalo open.
- Baseline before that boot (13:50, WindowServer still on eac2b8f, 13 min up, Claude app redrawing): `top` 60-77 %. spindump 5 s: WindowServer **3.03 s CPU, 2.60 s of it ws_main_thread**; the nvmtl.execution fence waiters 0.09 s (their `drmSyncobjWait` sleeps, it does not spin). Main thread sample (self time, 5 s): busy 55.9 %; kernel ioctl = CS submit **13.2 %** (the no-copy buffers, back to ~500 live), QuartzCore 8.4 %, libobjc 6.2 %, memmove/bzero 4.3 %, RADV 4.0 %, SkyLight 3.6 %, malloc 3.2 %, NVMTL 3.1 %, CoreFoundation 2.4 %. `WS::Updater::UpdateDisplays` 48 % inclusive, `CompositorMetal::composite` 31 %. Expected after the buffer list: submit ioctl ~1-2 %, main thread ~45 % busy; the rest is per-frame compositing (CoreAnimation + NVMTL/RADV encoding), the next thing to cut (frames per second and cost per frame).

## Edge web video lag part 9: first boot on the buffer list (2026-11-06 13:57)

- WindowServer on plugin 8633045: `vk: buffer list ON`; `2048 no-copy imports moved, 0 back to global (address escaped)`. BO-list census: **0 global BOs**, 330-340 BOs on the surface list; **18-24 handles per submit** (was 135.5), the most 416; 49 of 32768 submits carried the whole surface list.
- Kernel log for the boot: no fault, timeout or reset. Only the lines every boot has (one `NMX userptr: pin FAILED`, `KMS: Failed to initialize writeback connector`, one dc_dmub_srv WARNING).
- WindowServer 2.5 min after login (Claude app open), spindump 5 s: **2.39 s CPU** (was 3.03 s), ws_main_thread 1.97 s (was 2.60 s); fence waiters 0.13 s. Main thread sample (5 s):

  | main thread | 13:50 (eac2b8f) | 14:00 (8633045) |
  |---|---|---|
  | busy | 55.9 % | **39.2 %** |
  | kernel ioctl (self) | 13.2 % | **5.0 %** (CS submit 2.6 %) |
  | QuartzCore self | 8.4 % | 6.4 % |
  | RADV self | 4.0 % | 3.0 % |
  | NVMTL self | 3.1 % | 2.2 % |
  | `CompositorMetal::composite` incl. | 31 % | 20 % |

  The load is not identical (13 min vs 2.5 min after login), so the drop in compositing is partly less to draw; the ioctl drop is the fix (handles per submit 135 -> 23).
- What is left: per-frame compositing, about 220 submits/s (32768 in ~150 s), so several submits per display frame, each with `commitAndWaitUntilSubmitted` (5.8 % incl.). Next: count submits per frame and who triggers the redraws, then cut submits per frame and per-frame CPU in NVMTL/RADV encoding.

## Edge web video lag part 10: per-frame cost, surface keep evictions (2026-11-06 14:10)

- The panel runs at 120 Hz (`UI Looks like: 1440 x 900 @ 120.00Hz`), so ~220 submits/s is ~1.8 per frame: CoreAnimation's normal shape, not the problem. Kernel CS submit now ~0.11 ms each (was ~0.5 ms).
- Main thread split (sample 14:00, self time, by whether a driver frame is on the stack): idle 60.8 %, **Apple 21.4 %** (CA/SkyLight/WindowServer), **driver 17.9 %** (NVMTL + RADV + the kernel under them). Driver entry points: commit 5.6 %, drawIndexedPrimitives 2.8 %, `newTextureWithDescriptor:iosurface:plane:` 2.0 %, setFragmentTexture 1.2 %, setRenderPipelineState 1.0 %, ...
- Managed uploads: the prologue census counts ~430k Managed uploads (14 GB) in WindowServer's first 4 min, ~21 per submit (CA vertex buffers; the plugin keeps a VRAM copy because the device says it is not unified memory). No CPU in the sample (GPU copies), so not on this list; on the APU it is still wasted copying, for later.
- Surface keep 30 s reports: hits 4-13k, **misses 600-1200, nearly all `after drop: idle cap`** (~35 per second); sweep max **69 ms and 95 ms** (8-11 frames at 120 Hz). Apps render into pools of 2-3 surfaces and WindowServer holds only the one on screen; with a flat cap of 48 idle entries, a desktop with more windows evicts surfaces that come back a frame later, and each comes back as a pin + GPU map (and the eviction an unmap + free, on the main thread inside the sweep).
- Fix, plugin **bcbb0d7** (fork `surface-keep-hash`): idle entries at least `NVMTL_KEEP_IDLE` (48), then up to `NVMTL_KEEP_IDLE_MB` (1024 MB) of surface memory, at most `NVMTL_KEEP_IDLE_MAX` (512); `NVMTL_KEEP_MS` (3 s) unchanged, so only surfaces the GPU used in the last 3 s stay. Dropped entries are released on a utility queue, not inside the sweep. The 30 s report adds drops, idle MB, the slowest sweep's drop count.
- Harness `tests/surfpool_test.m`: 30 apps x 3 pooled 1440x900 surfaces, looked up by mach port and wrapped every frame (WindowServer's pattern). Per wrap after the first round: **1.6 ms with the flat cap (every one re-imported), 6 us with the byte cap.** Pixel readback correct; surfkeep_test, btsh_test, nocopy_list_test pass; no new kernel lines.
- Installed 14:08: plugin f19dbd94 (backup /Library/NullMoth/nvmtl-plugin-20261106T070620Z = 8633045), sbxmap stale 0; WindowServer at the next boot. Read then: `surface keep: idle entries kept ...` line, the 30 s reports (idle-cap misses near 0, sweep max), WindowServer sample.

## Edge web video lag part 11: GPU fault with the buffer list, WindowServer restart (2026-11-06 14:07)

- 14:07:06 kernel: `[gfxhub] page fault (src_id:0 ring:24 vmid:4 pasid:32794)`, address 0x000080030be18000, `GCVM_L2_PROTECTION_FAULT_STATUS:0x00401031`, client **TCP** (shader texture/buffer read), PERMISSION_FAULTS 0x3, MAPPING_ERROR 0. The same pasid faulted again at 14:07:16, then `Dumping IP State` (hang).
- 14:07:16 WindowServer (pid 205, plugin 8633045 = buffer list ON, up 9 min) crashed: `/Library/Logs/DiagnosticReports/WindowServer-2026-11-06-140723.ips`, EXC_BAD_ACCESS stack guard. The main thread recursed `MetalContext::RenderEncoder` -> `SetScissor` -> `RenderEncoder` ... under `MetalTiledBacking::RenderToDestination`, with `-[NVMTLCommandQueue commandBuffer]` at the top: after the hang the queue gave no command buffers and SkyLight retried until the stack ran out. WindowServer restarted at 14:07:23 (pid 11669) on the plugin installed at 14:06 (bcbb0d7).
- It is the **only** GPU page fault in the last 3 days of logs, on the first boot with the buffer list (the surface list had two clean boots).
- Mechanism (most likely): a userptr BO that a submit does not list is not revalidated by the kernel. Before the lists every submit listed every import, so a use the command buffer does not name was harmless; now it faults once that BO's pages were invalidated (CPU-side mapping change), which is rare. Checked and covered: every set*Buffer / blit / SASS / tessellation / acceleration-structure path retains into the same `_resources` set; texture views and surface aliases have `_parent`; textures on a buffer (`newTextureWithDescriptor:offset:bytesPerRow:`, `newTiledTextureWithDescriptor`, texture buffers) set `_backBuf`; `initStandin` goes through the same no-copy path; `gpuAddress` / argument encoder escapes counted 0 in WindowServer. The gap is not found yet.
- Done: plugin **779c55b** turns the buffer list OFF by default (`NVMTL_BUFFER_LIST=1` turns it on). The surface list (IOSurface imports) stays on. Harness: off 552 us / on 34 us per commit with 1000 no-copy buffers, all copies correct.
- Also in 779c55b: on an integrated GPU, Managed buffers are one CPU-visible allocation (no VRAM copy, no per-submit upload; `NVMTL_MANAGED_SYSMEM=0/1`); `tests/managed_test.m` passes both ways. The prologue census now splits Managed uploads from buffer-texture shadow uploads (the 430k "managed uploads" included both).
- Next, to bring the buffer list back: find the use the command buffer does not name. Candidates to instrument: GPU addresses written by the plugin into descriptor/argument data outside the bind paths (address snapshots reused across command buffers), and CA's `MetalTiledBacking` buffers. A debug mode that records every nvk_buffer whose address goes into a command buffer and checks it against the part's list at seal would find it in the harness.

## Edge web video lag part 12: buffer-list audit (2026-11-06 14:25)

- Code reading found no path that uses a no-copy import without the part's resource set naming it: one seal path (`nvmtlSealPartWithSignal`), `restart` puts the part's resources back so encoder binding tables that re-snapshot after a seal stay covered; the bind table (`c->table`) lives per part and is freed at retire. RADV lists BOs that a Vulkan command names by VkBuffer itself (the surface list sets `use_global_list=false`), so the gap can only be a descriptor set or address table entry (buffer device address).
- Plugin **3f9fabb**: audit mode, on when `/Library/NullMoth/nvmtl-bl-audit` exists (or `NVMTL_BL_AUDIT=1`). No-copy imports are registered (removed when destroyed). Each part records every buffer its descriptor sets and address tables name for bindings the pipeline declares, with the method that bound it (`nvmtl_slot.who`), and the no-copy buffers its resource set would list. At seal, a used import that would not be listed logs `vk: buffer-list AUDIT MISS (...) bound by <symbol>` (40 at most); `vk: buffer-list audit: N parts, U no-copy uses, M NOT named` every 4096 parts. It runs with the buffer list off, so nothing changes in what a submit carries.
- Installed 14:22: plugin f4c1450e (backup nvmtl-plugin-20261106T072236Z), flag file created, sbxmap allowed 12 stale 0. Apps started since (Preview, Maps, Photo Booth, Freeform, Safari) log `AUDIT ON (buffer list off)`, no MISS, no GPU fault. WindowServer runs it from the next boot, together with bcbb0d7 (surface keep byte cap) and 779c55b (iGPU Managed, buffer list off).
- Next boot, read: `grep "pid <WS> " /tmp/nvmtl.log | grep -E "AUDIT|audit:|managed buffers:|prologue census|surface keep: 30"`. A MISS names the method; then fix that path and turn the buffer list back on. Remove the flag file when done (`sudo rm /Library/NullMoth/nvmtl-bl-audit`).

## Edge web video lag part 13: the buffer-list fault was ClickToX, not WindowServer; list back on in WindowServer (2026-11-06 14:50)

- WindowServer CPU on this boot (plugin 3f9fabb, buffer list OFF, audit on; WS up 249 s; Photo Booth was open just before): spindump 5 s, **4.90 s CPU**. The main thread was busy 3.28 s; `coreanimation.pipelines` spent 0.97 s compiling once at startup.
  - Main thread self time: `mach_msg2_trap` 210 of 501 samples (idle receive) and `__ioctl` 80. Of those 80, `ac_drm_cs_submit_raw2` takes 60 (**12 % of the main thread**). Imports and BO allocs (surface textures) take the rest.
  - Inclusive: NVMTL 151 samples, `nvmtlSubmitWithEvents` 94, `vk_common_QueueSubmit` 61.
  - Why submits cost again: `vk: BO list: 245-388 global BOs: [prio 14 host-ptr GTT ...]`. With the list off, every no-copy import rides every submit (part 9 had 0 global BOs with the list on).
- Audit (all processes, /Library/NullMoth/nvmtl-bl-audit): WindowServer 32768 parts and Photo Booth 4096 parts, **0 no-copy uses** through buffer descriptors or address tables, 0 misses.
- **The 14:07 fault was not WindowServer.** The kernel's fault line names `in process pid 32923`. That is a thread id, and the same boot's log has `process ClickToX[7955] thread 32923 caught burning CPU` at 14:05:39. ClickToX ran plugin 8633045 with the buffer list on: MPS convolution (`AMDConvolution::ndArrayConvolution2DAMD_NCHW`), heaps with placed aliases, and buffer textures on no-copy pages (`1216x512 VkFormat 98 pitch 4864 bound at 0`, shadowed 1200x500 / 1400x800). The GPU hang from its fault is what took WindowServer down.
- WindowServer itself ran with the list on from 14:00 to 14:07 (8633045) and again after its restart until the reboot (bcbb0d7), with no fault.
- Done: plugin **565ac46**. The buffer list is ON in WindowServer only and OFF in every other process.
  - `NVMTL_BUFFER_LIST=0/1` still decides per process.
  - `/Library/NullMoth/nvmtl-bl-off` turns it off everywhere without a reinstall.
  - `nocopy_list_test` passes unset/1/0 (unset in a harness = OFF).
  - Installed (NVMTLDriver sha1 80022006) and the sbxmap refreshed. WindowServer picks it up at the next boot.
- Expected next boot: WindowServer `BO list: 0 global BOs`, and submit ioctl back to ~5 % of the main thread (part 9). Read `vk: buffer list ON ... WindowServer` and the audit lines.
- Open:
  - The ClickToX path. Its audit lines appear only when ClickToX runs; texture slots are not in the audit yet.
  - btsh uploads: 31.5 GB per 12288 WindowServer submits (~2.6 MB each), GPU-side copies.
- Photo Booth preview not rendering: handed to its own session (an upstream NullMoth PR has the fix).

## Photo Booth: preview renders (upstream #433/#471), lag measured (2026-11-06 15:20)

- Symptom: Photo Booth's live preview stayed black, and the camera felt laggy.
- Cause of the black preview: QuartzCore hands the driver a CAMetalLayer drawable (framebufferOnly off) with usage ShaderRead only. `CIRenderDestination` then refuses it ("usage must include ShaderWrite").
- Fix: port of upstream NullMoth **#433** (`1ffcb94`), the WindowServer guard `b8c3e9f`, and open PR **#471** (`5d48fea`), by hand because our surface key is `NVMTLSurfKey`. Fork commit **3bec140** on `surface-keep-hash`.
  - Surface textures with framebufferOnly off report RenderTarget, plus ShaderWrite when a storage image or `nvmtl_storage_view_for`'s twin can write them. WindowServer keeps its own usage.
  - Textures answer `-isDrawable`, and the drawable flag is part of the surface key, so Core Image picks screen orientation.
  - Upstream's `test_coreimage_surface_destination`: 6 failures on f4c1450e, 0 after. `test_coreimage_drawable_orientation`: 0.
- Lag, fork commit **79b4017** (installed 0b4fd9f9 = 565ac46 + diagnostics). Switches, all off by default: `NVMTL_FRAME_STATS=1`, `NVMTL_KEEP_OFF=1`, `NVMTL_SURF_WIDEN=0`. Set them with `launchctl setenv`, then relaunch the app.
  - Camera: ASUS FHD UVC, 1920x1080 420v. It delivers **30 fps, ~115 ms** from capture to Photo Booth (cmio `DELTA`).
  - Plugin, per 5 s: 90 command buffers/s, commit -> completed 2.5 ms average. ~400 surface-in copies/s (~600 MB/s): the two camera planes and the 1440x960 drawable each go through a private image (`copied in and out (more than one plane)`). Photo Booth ~45 % CPU, WindowServer 50-70 % while the preview runs.
  - `NVMTL_SURF_WIDEN=0` (old path): Photo Booth 22 % CPU and 300 copies/s, but the preview is black.
  - `NVMTL_KEEP_OFF=1`: same numbers as baseline, so surface keep is not the cause.
  - The 2 fps with 2 s delay seen first is Photo Booth's own idle mode: it calls `-[AVCaptureSession stopRunning]` about 2 min after its window stops being frontmost, then restarts slowly. It is not a driver stall.
- Banding in one photo (14:43) did not come back. Back-to-back photos with widening on and off under the same light are both clean. New tests: `plugin/tests/ci_gradient_test.m` (Core Image sRGB output into a surface texture) and `vt_420v_test.m` (VTPixelTransfer 420v -> BGRA). Both match the CPU result within 1-2 levels.
- Open: the per-frame CPU copies. Upstream's opt-in **#475** (multi-plane IOSurface VRAM sharing), **#476** (deferred surface uploads) and **#463** (reuse VRAM imports) target exactly this, but they are written for NVIDIA BAR imports and need #464/#467.
- `plugin/tests/desccache_test.sh` fails to compile since the buffer-list/audit commits: its extractor has no stubs for `nvmtl_btsh_note` / `nvmtl_audit_used`.

## Black screen on the 15:43 and 15:48 boots (2026-11-06, traced from Windows): lost 890M MSI during the NVRM bring-up

Both boots after the 15:42 reboot stayed black. WindowServer made its main window on the virtual display
`FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF`, and the NVMTL plugin logged `headless GPU: no device for WindowServer`.
The 14:31 boot before them was good. Boot-args and the display kexts (NMXGPU, NMXAccel, StrixGOP, StrixAccel, NVRM*)
were the same in all three boots. The only ESP changes after 14:31 were itlmt7925.kext (14:41) and the
StrixSbxMap Info.plist (15:33, new NVMTLDriver CDHashes, scope `com.apple.WebKit.GPU` only).

Method: the tracev3 files (Persist `0x2fa`, `0x300`, `0x301`) were copied from the Paragon APFS mount and parsed
on Windows. The parser walks each firehose chunk and adds `base_continuous_time + delta` per entry. On x86 that is ns
since boot. Times below are seconds since boot.

| boot | NMXGPU published | NVRM `(MSI)` + RmInitAdapter | NMX `LOST interrupts` | NMXAMDFB `kept` | registry QUIET | WindowServer GPU scan | main display |
|---|---|---|---|---|---|---|---|
| 14:31 good | 8.62 | 9.70 | none | **9.59** | 12.64 | 13.13 (`fb0:0 /NMXGPU/NMXAMDFB`) | panel |
| 15:43 bad | 7.76 | 8.84 | 13.99 | **13.995** | 11.86 | 12.29 (no fb0, agdc 0) | virtual |
| 15:48 bad | 9.02 | 10.09 | 15.03 | **15.98** | (not checked) | 13.57 (no fb0, agdc 0) | virtual |

- NVRM always starts RmInitAdapter (and turns on MSI for the RTX) about 1.08 s after NMXGPU publishes. NMXGPU's
  attach normally reaches NMXAMDFB about 0.97 s after publish. The good boot won by about 0.11 s.
- In both bad boots NVRM turned on MSI while the NMX attach was still running. The 890M's next interrupt then never
  reached the CPU. The Step100 cave says: `cause: handler idle with IVs pending (rptr 0x720 wptr_wb 0x840): the MSI
  did not arrive`, IOInterruptEventSource `produced 45 consumed 45` (producer frozen), and MSI is still enabled
  (`ctrl 0x85`, `addr 0xfee00000 data 0x4079`/`0x407a`).
- The loss was declared about 5 s after NVRM's `(MSI)` in both boots (5.15 s and 4.94 s). Degraded mode (2 ms IH poll)
  started, and NMXAMDFB was published 0.5 ms / 0.95 s later.
- NVRM's boot hold ends when it finds no display on the RTX (`no display on any NVIDIA connector`, 11.86 on 15:43).
  The registry then goes quiet. By that time NMXAMDFB is not there yet, so WindowServer scans the 890M without a
  framebuffer and uses the virtual display. This is the same window as the 11-05 `-nvrmnohold` black boots, reached
  in a different way.
- Of the dumps checked, `LOST interrupts` and the virtual display appear only in these two boots (0x2f6..0x2fa
  have neither).

**Cause:** the H2 interrupt loss again, this time a real lost MSI (Step100 removed the printf-stall cause). It
coincides with NVRM's MSI enable during the NMX attach. The 5 s stall until degraded mode pushes NMXAMDFB past
NVRM's hold.

**Not proven:** why NVRM's MSI setup drops the 890M's MSI. The two devices have different vectors (0x79/0x7a on the
890M). Candidates: the interrupt controller or IOPCIFamily MSI allocation path in the translator, or the IH re-arm
racing with something NVRM does during RmInitAdapter.

**Fixes, in order:**
1. NMXGPU busy hold (the Addendum above): `adjustBusy(+1)` after `nmx_xnu_wait_firmware_root`, and `-1` after
   `nmx_fb_publish`. WindowServer would then wait for NMXAMDFB even in this case (desktop at ~14 s, in degraded mode).
2. Detect the loss faster in the cave. The attach waited about 5 s before degraded mode started. A fence wait that
   sees IVs pending with a frozen producer could poll at once.
3. Root cause: order NVRM's RmInitAdapter after NMXAMDFB publish (an NVRM wait on the `NMXAMDFB` match, capped), and
   log the IH and MSI state right before and after NVRM's `(MSI)` to see which write loses the interrupt.

### Side-session audit for the 15:43/15:48 black boots (main session, 16:40)

Everything that changed between the good 14:31 boot and the 15:42 reboot (file mtimes on the ESP, /Library/Extensions, /Library/GPUBundles, /Library/LaunchDaemons/Agents and /Library/NullMoth, plus git):

| time | what | session |
|---|---|---|
| 14:41 | `EFI/OC/Kexts/itlmt7925.kext` (4th swap of the day, backups 13:30/13:48/14:12/14:41) | AWDL / AirDrop (mt7925-macos) |
| 14:42 to 15:33 | NVMTLDriver.bundle in /Library/GPUBundles, 5 installs: buffer-list audit, 565ac46 list in WindowServer only, Photo Booth fixes | edge-video-lag, photobooth-fix, camera-copies |
| 15:33 | `StrixSbxMap.kext` Info.plist: new NVMTLDriver CDHashes | photobooth-fix |

- Nothing changed between 15:48 and 16:33. The same files gave two black boots (15:43, 15:48) and a good one (16:33).
- So no single change broke the display. It is the boot race between NMXAMDFB and NVRM's MSI enable.
- Margins: on this good boot NMXAMDFB was published at 16:33:57.935 and NVRM `(MSI)` + RmInitAdapter came at 58.056, so it won by 0.12 s (14:31 won by 0.11 s).
- Any change to kernel boot timing can flip that race, such as a new Wi-Fi kext or extra kexts. The user-space NVMTL plugin changes cannot move the kernel side, but WindowServer then loads that plugin with no 890M framebuffer and logs `headless GPU`.
- Fix: the NMXGPU busy hold (`adjustBusy` until `nmx_fb_publish`) in the next NMXGPU source build, then order NVRM's RmInitAdapter after NMXAMDFB.

## Edge web video lag part 14: buffer list verified in WindowServer (boot 2026-11-06 16:33)

- Plugin: fork `camera-copy-890m` f8b9420 (UUID 2F49751C), which includes 565ac46 (buffer list on in WindowServer only), 3bec140 and 79b4017 (Photo Booth).
- WindowServer log:
  - `buffer list ON ... (NVMTL_BUFFER_LIST=unset, WindowServer)`.
  - `BO list: 0 global BOs` at every census.
  - Audit: 32768 parts, 0 no-copy uses, 0 misses.
  - No NMXGPU page faults, ring timeouts or IP dumps.
  - No new WindowServer crash report.
  - The audit's start-up line still says "(buffer list off)", because it reads only the env var. This is cosmetic.
- spindump 5 s, taken while the Claude app was streaming (its renderer ~53 % CPU): WindowServer 3.33 s CPU, main thread 2.61 s (was 3.28 s on the list-off boot).
  - Submit ioctl `ac_drm_cs_submit_raw2`: **12 of 500 samples = 2.4 %** of the main thread (list off: 60 = 12 %; part 9: 5 %).
  - Inclusive: `UpdateDisplays` 165, `nvmtlSubmitWithEvents` 28, `newTextureWithDescriptor:iosurface:plane:` 15, `MetalContext::draw_elements` 30.
  - `memmove` 18 samples come from `_XGetRegisteredCursorImages`, a client asking for cursor images; not the driver.
  - `ps` over 10 s: 4.43 s CPU (44 %) in the same conditions.
- Remaining:
  - btsh (buffer-texture shadow) uploads: 156k uploads / 20 GB per 28672 submits (~0.7 MB each). This is GPU-side copy work.
  - Compositing itself (`UpdateDisplays`).
- Other errors this boot (not new):
  - `function constants: re-translate FAILED: visible function reference "custom_fn"` in iconservicesagent, Spotlight, Dock and SecurityAgent.
  - `buffer texture: refused on alignment` (bind at +32/+48) in WindowServer: that texture takes the copy path.

## Step124: NVRM waits for NMXAMDFB (fix for the 15:43/15:48 black boots, installed 2026-11-06 16:47, reboot pending)

- Cause, from the black-boot audit above: NVRM's MSI enable + RmInitAdapter came while NMXGPU was still attaching. The 890M lost its next MSI, NMXAMDFB came ~5 s late (after NVRM's boot hold ended) and WindowServer took the virtual display. Good boots won by 0.11-0.12 s.
- Fix side: NVRM, not NMXGPU. A new NMXGPU source build would drop ~25 live binary patches (scripts/nmx-caves/check.py), so the NMXGPU busy hold (fork `xkpi-thread-lockfree`) stays for the source build after the caves are ported.
- NVRM: nmx-translator-271 `nvrm-wait-nmxamdfb` a039577 (pushed to the fork), built to `~/nvrm-build-nmxwait`, sha 5305bd506ef4d24f (was dca5eac6cfca8e7c). One new import, `IOService::copyMatchingService`; Info.plist unchanged (2.7.1).
  - `autoGo`, after the settle block and before `measureBootRaster`: if an `NMXGPU` service shows up within 3 s, wait for `NMXAMDFB` (up to `nvrmnmxwait=N` s, default 20, 0 = off, max 120). NVRM still holds its boot busy, so WindowServer waits too. The hold cap (settle + 40 s) covers 20 s.
  - Property `nvrm-nmx-wait` on NVRM, plus log `890M wait: NMXAMDFB registered after N ms - starting this card's bring-up (MSI + RmInitAdapter)` or a TIMEOUT line.
  - `go(2)` logs the 890M MSI capability (ctrl, address, data, PCI command) before and after this card's MSI enable and after `rm_init_adapter`, so a lost-MSI boot shows whether NVRM's enable touched the 890M's MSI registers.
- Installer `scripts/macos-install-step124.sh` (backup `/Library/NullMoth/step124-bk-20261106T094700Z`). AuxKC checked after the relink and again after 45 s: all NMXGPU caves (mmfix, flip, irqfix, mmfix2, s0ix, fadt), StrixS0ix 0.1.12, NMXBacklight 0.4.0, headless NVRM, the new wait string. StrixS0ix and NMXGPU were not touched.
- After the reboot, check:
  - `/usr/bin/log show --boot --predicate 'sender == "NVRM"' | grep -E '890M (wait|MSI)'`: the wait line shows N ms; the MSI ctrl/data match before and after.
  - WindowServer framebuffer fb0 on `/NMXGPU/NMXAMDFB`, no virtual display, NVRM boot hold time.
- Undo: `sudo scripts/macos-install-step124.sh --undo`, or boot-arg `nvrmnmxwait=0` to turn the wait off without relinking.

## Edge web video lag part 15: audit covers textures on no-copy pages (2026-11-06 16:55)

- btsh is not a WindowServer CPU target. Its shadows exist because Core Animation makes buffer textures at buffer offset +32 / +48. The hardware needs a 256-byte image base (`buffer texture: refused on alignment ... bind at 48 vs alignment 256`), so a shadow image is required. It costs ~5 uploads of ~130 KB per submit, about 150 MB/s of GPU copy, and records as one copy each.
- The audit gap: a buffer texture bound straight on a no-copy import (`... bound at 0 (DRM linear ...)`, as in ClickToX's MPS path) reaches the shader through an image descriptor, or, with bindless-all, through the address table's bindless slot. RADV does not list BOs from either. Part 12's audit checked only buffer bindings.
- Fork `camera-copy-890m`:
  - **df33243**: with the audit on, image and view handles of textures on no-copy pages map to their import. Sampled and storage bindings count as uses of that import. The audit start line reports the real buffer-list state.
  - **1fd1a05**: textures in the address table (bindless slots) count too.
- Test: `tests/audtex_test.m` (runs on the installed plugin). Core Image samples a 64x64 texture on no-copy pages, and a blit reads it after CPU changes: PASS.
  - The log shows `first texture binding on no-copy pages (... slot 601, bound by -[NVMTLComputeCommandEncoder setTexture:atIndex:])` and no AUDIT MISS. CI's compute kernel reads it through the bindless slot.
  - Core Image keeps its own copy of a source texture it has seen, so only the blit pass checks CPU writes.
- Installed (backup `nvmtl-plugin-20261106T095107Z` = 47f9d0ce, the camera-copy build) with the sbxmap refreshed. Buffer-list behaviour is unchanged (on in WindowServer only). Apps pick it up on launch, WindowServer at the next boot.
- ClickToX (the owner's app, Release build) relaunched under the audit. The OCR path (Cmd-Shift-S) needs a real keypress: osascript may not send keystrokes. After a few captures, grep its log for `AUDIT MISS` / `texture binding on no-copy pages`.

## Fresh Tahoe 26.7.2 (25G332): WindowServer has no Metal device = NMXAccel kernel-string gate (2026-11-07)

Handed over from the fresh-install session (local_93191de7).
- Symptom on 25G332: WindowServer logs "the 1002 accelerator does not claim this process" and "headless GPU: no device for WindowServer". NMXAccel logs "scanout gate CLOSED", `debug.nmxaccel_armed` stays 0, and the desktop is CPU-composited and freezes at login.
- On live 25G241 nothing writes `debug.nvaccelfb`. The arm comes from NMXAccel itself:
  - The `nmxArm` thread call sees NMXAMDFB and logs "NMX display bind: scanout ready", then `registerFramebufferLocked(1)` → "debug.nvaccelfb now reads 1" → "NMX display pipe armed".
  - The `sysctl:` prefix in that log is only the registration helper's label.
- That watch is only set up when `IOKitBuildVersion` is exactly the 25G241 kernel string: nvrm-accel.cpp, "native framebuffer watch %s" → "not on reviewed kernel profile".
  - 25G241: `Tue Aug 18 17:46:40 PDT 2026; root:xnu-12377.161.15.700.19~2`
  - 25G332: `Mon Oct 12 00:33:09 PDT 2026; root:xnu-12377.161.15.701.48~2`
  - The gate guards private IOAcceleratorFamily2 offsets. The family is 487.4.4 on both builds, so the offsets still apply.
- Fix on the Tahoe Data volume:
  - `scripts/fresh-install/nmxaccel-kernel-gate.py` swaps in the 25G332 string (same length, one occurrence) and gives the binary a new LC_UUID: 7B94D937-…-3EF1 → …3EF0.
  - Original: `/Library/StrixGraphicsFix/NMXAccel.25G241-orig`.
  - kccheck now reports NMXAccel MISSING from the Tahoe AuxKC, so auxguard relinks it 45 s into the next Tahoe boot and reboots once.
- Other binaries with the 25G241 string: only StrixAccel, which is off (`-strixaccoff`). The NMXGPU, NVRM, plugin and RADV binaries do not have it.
- Proper fix (NMXAccel source): gate on the IOAcceleratorFamily2 version and the reviewed offsets, not the exact xnu build string. Otherwise every point update needs this patch.

### NMXAccel family-layout gate (replaces the 25G241 kernel-string gate)

- The exact `IOKitBuildVersion` match is gone. NMXAccel now arms the 890M pipe when the IOAcceleratorFamily2 class sizes
  (IOGraphicsAccelerator2, IOAccelDisplayMachine, IOAccelLegacyDisplayMachine, IOAccelEventMachineFast2, IOAccelTask,
  via `OSMetaClass::getMetaClassWithName()->getClassSize()`) equal the reconstructed headers' static_assert sizes.
  OS updates need no code change unless the family layout itself changes; a mismatch is logged per class
  (`family layout: X size N, headers M  <-- MISMATCH`) and sets `NMXFamilyLayoutOK = false`.
- Boot-arg `nmxaccel_gate=0` skips the check, `=2` forces it off.
- Source: nmxaccel-ci branch `nmxaccel-family-gate` (from ci/nmxaccel-drmuc 7bd4e99), CI run 42350604915 (macos-15).
- Installed on 25G332 with `scripts/macos-install-nmxaccel-gate.sh` (backup in /Library/StrixGraphicsFix/nmxaccel-gate-bk-*,
  `--undo`), AuxKC relinked + kccheck ok. Verify after reboot: `log show --last boot | grep -E 'family layout|framebuffer watch|pipe armed'`.
- `scripts/fresh-install/nmxaccel-kernel-gate.py` (the string-swap patch) is now obsolete for new installs.

### Reboot 2026-11-07 14:29 (25G332): family gate, Step124, power button PASS

- NMXAccel family gate: all 5 classes match the headers (IOGraphicsAccelerator2 3544, IOAccelDisplayMachine 376,
  IOAccelLegacyDisplayMachine 504, IOAccelEventMachineFast2 3376, IOAccelTask 600), `NMXFamilyLayoutOK = Yes`,
  "native framebuffer watch enabled" + "NMX display pipe armed" on 25G332 with no kernel-string patch. WindowServer = 890M, Metal 3.
- Step124: "NVRM-xnu: 890M wait: NMXAMDFB registered after 884 ms - starting this card's bring-up"; boot OK.
- Power button wake (StrixS0ix 0.1.12), logs ~/ga403-logs/syssleep-20261107-143111: halted 8.7 s, wake event 0x1000a
  (EC GPE), EC status 0x9, query 0xCE -> `_QCE` -> wrangler tickle -> "PMRD: Requesting full wake due to dark wake
  activity tickle", full wake promotion 895 ms. Lid (0x2F) and power button (0xCE) both wake the machine fully now.
  Still open: S0i3 not reached (not met: DISPLAY, NBIO).

## Edge web video lag part 16: all Edge video is CPU-decoded; VCN does 1080p60 VP9 at 6x realtime (2026-11-07 15:10)

Boot 25G332 14:29, plugin with buffer list in WindowServer (0 global BOs). The owner's normal use is iOS Simulator
running next to a video, so these runs were taken with sim-perf's simulator up (SimMetalHost on the 890M, the
simulator's MercuryPosterExtension crashing about every 20 s, ReportCrash ~85 %). That load is part of the test.

### Measurements (probe Edge, YouTube LXb3EKWsInQ, rVFC/rAF gaps over CDP)

| run | length | decoded | dropped | rVFC gaps > 25 ms | worst |
|---|---|---|---|---|---|
| 720p60, 2026-11-06, idle machine | 60 s | - | 0 | 7 | 33 ms |
| 1080p60, 2026-11-06, idle machine | 45 s | - | 27 | 39 | 104 ms |
| 720p60, 2026-11-07, simulator up | 45 s | 1716 | 374 | 479 | 651 ms |
| 1080p60, 2026-11-07, simulator up | 40 s | 2397 | 164 | 225 | 99 ms |

### Root cause: no hardware decoder for VideoToolbox, so Chromium decodes on the CPU

`Media.enable` over CDP for the YouTube player:

- `Cannot select VideoToolboxVideoDecoder for video decoding. status=kUnsupportedConfig` for vp9 and av1.
- `Selected VpxVideoDecoder` (VP9, 1920x1080) / `Selected Dav1dVideoDecoder` (AV1) = software decoders in the renderer.
- `sample` of the renderer (12 s): ~43 % of a core in Edge framework code; the GPU process only ~5 %.

So every web video (VP9/AV1 on YouTube) is decoded by the CPU and competes with WindowServer, the simulator and
everything else. With an idle machine 1080p60 still drops; with a simulator up even 720p60 drops. The buffer-list work
lowered WindowServer's cost but cannot fix this: the frames are late before they reach the compositor.

### VCN decode on the live RADV (no new install)

Clip: 1920x1080 60 fps VP9 profile 0, 300 frames, 12 Mbit/s, made in the probe Edge with WebCodecs `VideoEncoder`
(scratchpad `mkclip.mjs`, nothing downloaded). ffmpeg 8.0 from radv-video/ffinst, `VK_DRIVER_FILES=/Library/GPUBundles/nvmtl/radeon_icd.json`:

| decoder | wall | CPU |
|---|---|---|
| libavcodec vp9, 1 thread (no x86 asm in this build) | 4.94 s (1.0x realtime) | 4.94 s |
| libavcodec vp9, auto threads (no x86 asm) | 1.35 s | 6.92 s |
| Vulkan video on VCN (frames stay on GPU) | 0.81 s (6.2x realtime) | 0.57 s |
| Vulkan video + `hwdownload` to NV12 | 2.72 s | 5.41 s (readback through uncached memory) |

The VCN output is bit-exact with libavcodec (framemd5 NV12, 0 of 300 frames differ). The software rows come from
an ffmpeg built with `--disable-x86asm`, so they overstate the CPU cost; the Edge renderer number (libvpx with SIMD,
~43 % of a core at 1080p60) is the one that counts.

### Plan: a real VideoToolbox decoder on VCN (replaces VTStub)

- Same registration as VTStub (Step108: bundle in /System/Library/Video/Plug-Ins, runs in VTDecoderXPCService, claims
  vp09/av01 as hardware so Chromium picks `VideoToolboxVideoDecoder`), but decoding for real through RADV Vulkan video.
- Output must not be read back by the CPU (last row of the table): decode, then a GPU copy into the CVPixelBuffer's
  IOSurface pages imported as host memory (the same no-copy import the NVMTL plugin uses for IOSurfaces).
- Open questions before the first install: GPU access (NMXGPU user client, /Library/GPUBundles) from the
  VTDecoderXPCService sandbox, and the VT decoder vtable fields Chromium uses (decode frame, finish, copy properties).

## Edge web video lag part 17: VCNDec, a VideoToolbox VP9/AV1 decoder on the 890M VCN (2026-11-07 16:10, built, not installed)

Source: `tools/890m/vcndec` (BSD; links a minimal static LGPL libavcodec built by `ff-build.sh`).

- `src/vcndec.c`: libavcodec vp9/av1 with the Vulkan hwaccel on the live RADV (`/Library/GPUBundles/nvmtl`), no
  software fallback. The minimal ffmpeg (vp9 + av1 decoders, vp9_vulkan/av1_vulkan, no avformat/filters) is patched to
  dlopen the live loader `/Library/GPUBundles/nvmtl/libvulkan.1.dylib` first and the plugin sets `VK_DRIVER_FILES`,
  because VTDecoderXPCService has no DYLD/Vulkan environment. The decoded image goes out with one
  `vkCmdCopyImageToBuffer` per plane into a VkBuffer that imports the destination IOSurface's own pages
  (VK_EXT_external_memory_host, one import per IOSurface, cached with the surface retained). The CPU never reads
  VRAM; a host-cached staging buffer + memcpy is the fallback (`VCN_NO_IMPORT=1`).
- `src/vcnvt.c`: the VideoToolbox decoder class (vtable from VTStub), `vp09` + `av01` registered as hardware,
  rating 1000. Accepts profile 0, 8-bit 4:2:0 (vpcC / av1C checked; 10-bit is refused so the app decodes it itself),
  emits NV12 `420v`/`420f` with the format's colour tags, one emit per sample (hidden frames -> FrameDropped).
  Kill switch: `/Library/NullMoth/vcndec-off`.
- `install.sh --system` (from VTStub): copies the bundle into /System/Library/Video/Plug-Ins and blesses a new boot
  snapshot; `--undo --system` removes it.

Tests (no install; 1080p60 clips made with WebCodecs, `tools/mkclip.mjs`):

| test | frames | result | speed | CPU |
|---|---|---|---|---|
| `vcndec_test` VP9, direct IOSurface import | 900 | bit-exact (300/300 vs libavcodec) | 155-177 fps | 1.6 ms/frame |
| `vcndec_test` VP9, staging + memcpy | 900 | - | 143 fps | 2.05 ms/frame |
| `vt_test -b` VP9 through VTDecompressionSession (require hardware) | 300 | bit-exact 300/300 | 180 fps | 2.1 ms/frame |
| `vt_test -b` AV1 through VTDecompressionSession | 240 | 240/240 = ffmpeg Vulkan decode | 75 fps with md5 | - |

- With the in-process registration `VTIsHardwareDecodeSupported` turns 1 for vp09 and av01 and a session that
  requires hardware picks VCNDec (log: "VCNDEC StartSession vp09 1920x1080 ... on the 890M VCN", "close: in 300 out
  300 dropped 0 errors 0 (gpu-copy 300 cpu-copy 0 imports 1)").
- At 60 fps the decoder costs ~10 % of one core, against ~43 % for the Edge renderer's libvpx at 1080p60, and the
  decode itself runs on VCN, so the simulator / WindowServer load no longer starves it.
- Open: the session property `UsingHardwareAcceleratedVideoDecoder` reads 0 with the in-process registration
  (VideoToolbox answers it from the registration; check again with the bundle in /System). Safari: WebKit's GPU
  process may host the decoder in-process for some codecs; its sandbox must allow /Library/GPUBundles/nvmtl.

### VCNDec installed (2026-11-07, next boot)

- `tools/890m/vcndec/install.sh --system`: /dev/disk1s4 mounted at /System/Volumes/Update/mnt1, VCNDec.bundle in
  System/Library/Video/Plug-Ins, new boot snapshot blessed. Live after the next reboot.
- Undo: `install.sh --undo --system` (next boot). Kill switch now: `touch /Library/NullMoth/vcndec-off`.
- After the reboot: `build/vt_test clip.ivf` without `-b` must pick VCNDec (log subsystem com.ga403wm.vcndec),
  then Edge `Media.enable` must report `VideoToolboxVideoDecoder`, then `tools/hitch.mjs` 720p60/1080p60 with the
  simulator up; Safari VP9 check.

## Step125: NMXGPU from one source build (tech debt; 2026-11-07 15:40, installed, reboot pending)

The live NMXGPU (5760efb6) was the Oct 22 source build 7efe25b8 plus ~25 byte patches (FRESH-INSTALL.md 1.3). Fork
branch `nmx-source-port` (thanhnndev/nvidia-macos-driver, from 2dbf59a; private build tree
`~/develop/projects/nmx-build-xkpi`) carries all of them as source, plus the three fixes that were never caves:

| area | cave step | now in source |
|---|---|---|
| class NMXAMDFB, scan-out phys | 74, 75 | xnu/nmx_fb.cpp |
| rcu reader on CPU 0 + lock, idr cache CPU 0, unlock-of-unlocked guard | 77, 79, 78 | override linux_rcu.c / linux_idr.c, nmx_lock.c |
| syncobj ETIME, zero flush, GTT snoop, TTM order 0 | 80, 84, 88, 89 | patches + nmx_page.c / linux_compat.c |
| ibprobe, WC split maps, umap cache off, ibprep opt-in | 89, 90, 91, 93 | amdgpu-ibprobe.patch, nmx_vm.cpp, nmx_kext.cpp |
| userptr pin + read-only retry, cs-trace, mm mismatch | 92, 95/96, 97b | amdgpu-userptr-*.patch, linux_compat.c |
| irqwatch + H2 fence-read noprint, mm lifetime | 97, 100, mmfix2 | amdgpu-irqwatch-*.patch, fork 163d117 |
| flip/import API, DC on GPU VM, home in VRAM | 98/99 | override nmx_fb_bridge.c (`nmx_fb_flip_call`) |
| s2idle suspend, FADT re-read before suspend | 107, 112c | nmx_port.c, nmx_acpica.c (`nmx_acpica_reread`) |
| lock-free curthread (spin lock timeout panic) | - | fork e249183 |
| DISPLAY IPS trace (`NullMoth ips:`) | - (Step114b) | amdgpu-dm-ips-trace.patch, fork ec38af4 |
| NMXAMDFB boot hold (`nmxgpu-boot-hold`) | - | NMXGPU::holdArm/holdRelease in attachNow |

- Reproducibility first: the baseline worktree builds 7efe25b8 bit-identical, so the only differences are the ports.
- Build: 900/900 drm sources, 76/76 runtime. New kernel imports: `OSCompareAndSwap`, `gOSKextUnresolved` and a weak
  `proc_starttime`. The first build (bcd54768) imported `proc_starttime` strongly: it is in the 26.5 SDK but 25G332
  exports it to no kext, kmutil refused the link ("could not find a kext which exports this symbol") and the
  installer rolled back. A weak import called directly (f083d838) failed too ("Unexpected bind type: 3": kmutil
  binds weak symbols only through data pointers), so the weak reference sits in a data pointer, checked against
  `gOSKextUnresolved` (pid-only process identity where missing): NMXGPU **928335c2** (10.9 MB).
- The boot hold: NMXGPU goes busy once the firmware folder exists (not in start(): before the root mount that would
  hang the logo) and drops it when NMXAMDFB is published, on every failure exit, or after a 30 s cap. Property
  `nmxgpu-boot-hold` = `released: NMXAMDFB published after N ms`.
- `scripts/macos-install-step125.sh <NMXGPU.kext>` (`--undo`): backs up NMXGPU + AuxKC + auxguard probes, installs,
  relinks, rewrites `/Library/StrixGraphicsFix/nmx-relink.probes` to three windows of the new __text that occur once
  in the binary and once in the collection, checks kccheck + probes, NVRM Step124, StrixS0ix 0.1.12, NMXBacklight and
  the source-build strings, again after 45 s; any failure rolls everything back.
- The cave checkers (`scripts/nmx-*/... --check-kc`) used by older installers (step97..step124) no longer apply to
  NMXGPU; do not rerun those installers on top of this build.

After the reboot, grep:

```bash
/usr/bin/log show --last boot --predicate 'sender == "NMXGPU"' --style compact | grep -E 'NullMoth ips:|boot hold|NMX flip|NMX irqwatch|NMX cs-trace|FADT re-read|unlock of unlocked'
```

```bash
ioreg -rc NMXGPU -l | grep nmxgpu-boot-hold
```

## Step126: S0i3 NBIO trace (StrixS0ix 0.1.13), installed 2026-11-07, reboot pending

What is known about the two S0i3 blockers left (SMU slots 0 DISPLAY, 9 NBIO, both "not met" for the whole sleep):
- NBIO: with every endpoint but the RTX and its audio in D3hot (Step116 d3 4) NBIO stayed busy, so the suspects are
  the RTX link (GPP9, NVRM standby leaves 62:00.0/.1 in D0, link in L0) or links that never get L1.2 enabled.
  The RTX's real power-off is `\_SB.PCI0.GPP9.PG00._OFF` (SSDT-5 "OptRf2"): EC VGAT = 0, `DL23` (link to L2/L3),
  `POFF`; `_ON` brings it back (`PON`, `L23D`). Linux reaches S0i3 on these laptops with the dGPU in D3cold.
- DISPLAY: the 890M in D3hot does not clear it, so it is DCN 3.5 IPS inside NMXGPU. Step125 (NMXGPU source build,
  NMXGPU session) carries the `NullMoth ips:` trace (Step114b) for the same reboot.

StrixS0ix 0.1.13 (read-only trace, `scripts/macos-install-step126.sh`, `--undo`; relinks with kccheck + probes, so it
fits on top of the Step125 source build):
- At each sleep: one `StrixS0ix: link 00:dd.f -> bus: rp aspm S/E l1ss S/E ltr E genG xW dll D; ep bb:00.f ...` line
  per root port and its endpoint (ASPM 1 = L0s, 2 = L1; L1SS bits 0..3 = PCI-PM L1.2, PCI-PM L1.1, ASPM L1.2,
  ASPM L1.1), also in `S0ix,Links`.
- At wake: `root port DLL active at halt/wake` per secondary bus (0 at halt = link down / L2-L3).
- The runtime `s0ix-set d3 5` test (RTX + audio in D3hot) is still to run; the owner starts sleep tests.

## Step127: the console bridge lights the panel only; the cache knobs become writable (source, 2026-11-07)

Owner-visible symptom: with an HDMI monitor plugged in the machine does not reach the desktop; unplugged it boots.
`nmx_fb_bridge.c` lit *every* connected output the fbdev way, one buffer as large as the largest mode, and pointed
each lit CRTC at it. With a monitor attached at boot the panel's CRTC could be programmed for the monitor's mode, or
the second CRTC on the same buffer failed the commit, and the boot stopped there.

The bridge now calls `bridge_restrict_to_panel()` after `drm_client_modeset_probe`, both at open and at hotplug:
the panel (eDP/LVDS) keeps its own mode and is the only modeset given a framebuffer; external outputs get
`ms->mode = NULL`, which the atomic commit turns into a disabled CRTC, and one line is logged per output
(`NullMoth display: leaving external output … off`). With no panel connected the old behaviour is kept, so a
headless boot still lights what is there. Menu of evidence this is the right layer: the fault is in mode selection,
not in the panel path (the OLED comes up 2880x1800 in every boot without HDMI); the NVIDIA side has its own guard
removed (Step126/NullMoth 2.5.2 notes) and can be excluded at boot with `nullmoth-remove=1` if a monitor-plugged
boot still stops.

Second defect found while trying to A/B the knobs: `debug.nmx_umap_cache`, `debug.nmx_umap_flush` and
`debug.nmx_wbinvd` were declared `CTLFLAG_RW | CTLFLAG_LOCKED | CTLFLAG_KERN`. The `CTLFLAG_KERN` node answers
userland writes with EPERM (`sysctl: … Operation not permitted`), and macOS' `sysctl(8)` then prints the old value
instead of `old -> new`, so the first boot after b26 could not be measured at all. They are plain `CTLFLAG_RW` now.

Correction (Step128): this was **not** the Step125 build. UUID `591E7D5A` is the old cave-chain NMXGPU (see line ~4761);
928335c2 has UUID `E9E87100` and was only in the AuxKC waiting for a reboot. 928335c2 has never run.
Measured on the old NMXGPU (installed `928335c2`, loaded UUID `591E7D5A`), 6 fresh processes of
`metal-first-job.swift` with one dispatch each: **6/6 pass**, jobs +445 to +758 per process, `timeouts +0`,
`grab_stray +0`. The AMD device reports `Metal 3`, OLED `2880 x 1800`, 120 Hz, internal. The VA-0 page fault from
Steps 59-66 does not reproduce on this build, so the mapping work in Step125 (WC split maps, umap cache off,
userptr pin) is the fix that landed; the knobs stay as the A/B switch if it comes back.

**Step126 pre-reboot test 15:53 (0.1.12 live, `s0ix-set d3 5`): every endpoint in D3hot, NBIO still not met.**
- Logs ~/ga403-logs/syssleep-20261107-155326. Put in D3: 63:00.0 65:00.0/.1/.2/.5 62:00.0/.1 (RTX + audio)
  66:00.0/.1 67:00.5 64:00.0; left in D0: none. RTC wake, 5.1 s halted (a CPU assertion held the sleep 14 s).
- NVRM resumed fine from D3hot (RESUME 0x0, 890 ms); NMXGPU resume 649 ms.
- `S0ix,SmuNotMetUs`: slot 0 (DISPLAY) = slot 9 (NBIO) = 5078686 us, identical to the microsecond, CPU 11 ms.
- So the RTX in D0 is not the NBIO blocker, and D-states are not the answer. NBIO and DISPLAY track each other
  exactly, which points at one cause: DCN not reaching IPS keeps an NBIO path busy. The Step125 `NullMoth ips:` trace
  is the next thing to read; the 0.1.13 link trace will confirm or rule out the L1.2 side.

## Step128: the Step125/126 reboot hangs at every boot; NMXGPU 928335c2 is the only boot-time kernel change (2026-11-07 16:00-17:10)

Three boots after the 15:56 reboot (15:56:56, 15:59:11, 16:01:44) all froze ~2 s after logd started, about 6 s after
kernel start, which is when kernelmanagerd loads the AuxKC. Traced from Windows, read-only: the Data volume was read
with `dissect.apfs` (Paragon refused to mount: activation "Authorization is denied"), and NVRAM through
`GetFirmwareEnvironmentVariableW`.

Evidence:
- No panic: no new `.panic` file and no `aapl,panic-info` in NVRAM. `nullmoth-nv-starts` is absent (counter 0) and
  `nullmoth-nv-ok=1`, so the NVIDIA boot guard is not involved; when it does trigger it only parks NVRM, it does not
  freeze the machine.
- The 14:29 panic (`mp_kdp_enter() timed-out`, 23/24 acks, spindump) happened at shutdown; the boot after it was good.
- Only logd.0.log kept data from the hung boots. system.log, install.log, the powermanagement asl and the tracev3
  extents written in those boots are all zeros, so the disk stopped committing at ~6 s.
- Verbose boot (`-v` added to the ESP config.plist at 16:45): `StrixS0ix: 0.1.13 up ... halt hook on` is printed, the
  boot continues, and the last lines are `X86PlatformPlugin ... _CST/_PSS failed`, `IOPPF StartupPowerEvents 0x0`,
  `IOVersatile failed to load`. The good boot at 14:29 prints the same lines at 6.156 s, then NVRM at 6.313 s and
  NMXGPU at 6.73 s. Neither NVRM nor NMXGPU lines appear. This does not mark the hang point: once amdgpu
  initializes DCN, the panel stops scanning out the firmware framebuffer, so the console freezes on screen.

What changed after the 14:29 good boot:

| change | when (UTC+7) | runs at boot? |
|---|---|---|
| NMXGPU 928335c2 (Step125 source build, UUID E9E87100) | 15:34 | **yes**, first time ever |
| StrixS0ix 0.1.13 (Step126) | 15:39 | the new code runs only in `setPowerState(0)`/halt (`buildPci`, `logLinks`, root-port status reads); boot path same as 0.1.12 |
| AuxKC relink | 15:40 | carries the two kexts above |
| ESP `StrixSbxMap.kext/Contents/Info.plist` | 15:40:58 | only 8 new NVMTL cdhash pins, used only on `com.apple.WebKit.GPU` mmap; binary unchanged since 11-04 |
| VCNDec, NVMTL translator | 15:30, 15:40 | userland, loads much later |

NMXAccel (14:17) and NVRM Step124 (11-06) both booted fine at 14:29. Every other kext on the ESP is older than 14:29.

Code reviewed in the fork (`nmx-source-port`, 2cf0bcc), without finding the hang line:
- Boot hold (`holdArm`/`holdRelease`, ff47964): `adjustBusy(1)` once the firmware folder exists, capped at 30 s, so it
  cannot hang by itself for more than 2 minutes.
- Lock-free curthread (d345b3e): writers take the registry spin lock with interrupts off. A stuck lock would end in
  an xnu spinlock-timeout panic, and there is none.
- `amdgpu-dm-ips-trace.patch` (e0da44f): adds `printf` only.
- Weak `proc_starttime` through a data pointer (2cf0bcc): checked against NULL and `gOSKextUnresolved` before the
  call; it runs on the first `curproc`, early in the kext start. Not proven safe on the machine: how kmutil binds a
  missing weak import in the AuxKC was not checked.

State left for the next boot:
- ESP `config.plist`: `-v` added (backup `config.plist.bk-addv-20261107T164437`), `nmxamd=1` removed (backup
  `config.plist.bk-nonmx-20261107T170744`). Only the boot-args string changed (LF kept, +3 / -9 bytes).
- Without `nmxamd`, NMXGPU declines the 890M (`opted_in()` in nmx_kext.cpp). Everything installed stays in place.

Next:
1. Boot with `nmxamd` off. If it boots, NMXGPU 928335c2 is confirmed. If it still hangs, look at NVRM next
   (`nullmoth-remove=1`).
2. From that macOS, build 928335c2 with NVRAM breadcrumbs (`nmxgpu-stage` at module start, `nmx_port_start`,
   firmware wait, `holdArm`, each amdgpu IP block init, DC init, `nmx_fb_publish`). Write each mark with
   `IODTNVRAM`/SetVariable so it reaches flash before the hang. Boot once with `nmxamd=1`, then read the last mark
   from Windows (same NVRAM read as above). That mark is the stage to fix.
3. Also dump the AuxKC bind for `_proc_starttime` (value of `nmx_proc_starttime_fn` in the collection) to rule the
   weak import in or out.
4. To get the normal setup back: re-add `nmxamd=1`, or copy `config.plist.bk-nonmx-20261107T170744` over
   `config.plist` (that backup still has `-v`).

### Step128 root cause: the weak `proc_starttime` import (2026-11-07 17:20)

The boot at 16:46 (UTC+7) wrote its panic, and the next boot (with `nmxamd` off) saved it to disk:
`/Library/Logs/DiagnosticReports/Kernel-2026-11-07-164643.panic`. It was never a hang. `debug=0x100` halts on panic
and the frozen screen showed nothing new.

```
panic(cpu 3 ...): Kernel trap at 0xffffff800e85cd38, type = 14=page fault ... Kernel NX fault
RAX = RCX = RIP = CR2 = 0xffffff800e85cd38
com.nullmoth.NMXGPU : _nmx_thread_get + 0x1b6
  <- _nmx_curthread + 0x1c <- _lkpi_fpu_safe_exec + 0x15 <- _lkpi_kmalloc + 0x2e <- _linux_compat_init + 0x131
  <- _nmx_sysinit_run + 0x1c0 <- _nmx_port_start + 0x108 <- NMXGPU::start + 0x11d <- IOService::startCandidate
com.nullmoth.NMXGPU(1.0)[E9E87100-...]   uptime 7.07 s   KernelCache base 0xffffff800e800000
```

- RIP == CR2, and the address is inside the kernel image (base + 0x5cd38), in a non-executable page: a call through a
  function pointer that points at data.
- `nmx_thread_get` -> `nmx_curproc` -> `nmx_proc_for` -> `nmx_proc_start` calls `nmx_proc_starttime_fn`, the weak
  `_proc_starttime` added in 2cf0bcc. 25G332 does not export `proc_starttime` to kexts, and kmutil bound the missing
  weak symbol to an address in kernel data, not NULL and not the value of `gOSKextUnresolved`. The guard passed, and
  the first `curthread` of `NMXGPU::start` (from `linux_compat_init` kmalloc) jumped into data.
- With `nmxamd` off, NMXGPU declines the 890M before `nmx_port_start`. Bootguard logged "desktop came up and stayed up"
  at 17:10:22 and 17:14:40. So the rest of the Step125/126 set (StrixS0ix 0.1.13, StrixSbxMap, NVRM) boots.

Fix: fork `nmx-source-port` 326858e. The weak import is gone; `nmx_proc_start` returns 0, so the pid alone tells the
owners of a recycled `proc_t` apart (the fallback the code already described). No other weak import exists in
`gpu-port/xkpi`. Lesson: on this kmutil, never use `weak_import` for a kernel symbol that may be missing; check the
export list of the running kernel and leave the symbol out.

To get the 890M back (on the Mac):
1. `cd ~/develop/projects/nmx-build-xkpi`, pull `nmx-source-port` (326858e), build NMXGPU.kext.
2. `sudo scripts/macos-install-step125.sh <out>/NMXGPU.kext` (AuxKC relink).
3. Re-add `nmxamd=1` to boot-args in ESP `config.plist`, reboot. Keep `-v` for the first boot.

### Step128 follow-up: the boots with `nmxamd` off reach loginwindow with no picture (2026-11-07 17:30)

Four boots after `nmxamd=1` was removed (BOOT_TIME 17:09:31, 17:13:48, 17:24:49, 17:26:35, UTC+7). None panicked:
no new `.panic`, no `aapl,panic-info` in NVRAM. Bootguard logged "desktop came up" for each one (17:10:22, 17:14:40,
17:25:43, 17:27:28). In the last boot's log (Persist 0x37), WindowServer (pid 200) and loginwindow (pid 207) run.
NVKMS reports `no display on any NVIDIA connector`. NMXGPU declines (no `nmxamd`), and StrixGOP is off
(`-strixgopoff`). So nothing drives the OLED, which keeps the frozen verbose text. No console login happened after
15:56 (no `USER_PROCESS` in system.log).

So "it still hangs" is the missing panel driver, not a new fault. The installed NMXGPU is still 928335c2, which has
the weak import, so re-adding `nmxamd=1` before installing the fixed build (326858e) would panic again. To build
on the Mac you need a picture first: remove `-strixgopoff` so StrixGOP 0.1.11 (boot-raster framebuffer, no
acceleration) shows the login window. Then build, install, re-add `nmxamd=1` and put `-strixgopoff` back.

### Step128 fix applied from Windows: two bytes in the installed AuxKC (2026-11-07 17:40)

The exact fault, from the installed binaries (`/Library/Extensions/NMXGPU.kext` and
`/Library/KernelCollections/AuxiliaryKernelExtensions.kc`, pulled read-only):

```
nmx_proc_for (kext 0x6db8f5, AuxKC 0x7c58f5):
  mov rax, [nmx_proc_starttime_fn] ; test rax, rax ; je skip
  mov rcx, [GOT gOSKextUnresolved] ; cmp rax, [rcx] ; je skip   <- compares with the VALUE of gOSKextUnresolved
  call rax                                                      <- NX fault
```

In the AuxKC, the slot `nmx_proc_starttime_fn` (AuxKC 0xa16ec8) and the GOT entry of `gOSKextUnresolved`
(0x98b0d8) are both chained fixups with target 0x15cd38. kmutil binds a missing weak symbol to the *address* of
`gOSKextUnresolved` (that is what Apple's `OSKextSymbolIsResolved` compares: `&sym != &gOSKextUnresolved`), and that
address is kernel data. The guard compared with the value, so it always passed. Second copy of the same inline in
the reaper (kext 0x6dd166).

Patch (AuxKC is not code-signed: no LC_CODE_SIGNATURE), both `je` -> `jmp` to the "no proc_starttime" path:

| AuxKC offset | APFS block (Data volume) | before | after |
|---|---|---|---|
| 0x7c5907 | 0x855d9e +0x907 | `74 28` | `eb 28` |
| 0x7c7170 | 0x855da0 +0x170 | `74 37` | `eb 37` |

How it was written, with no APFS write driver: Paragon refuses to mount (activation denied), and `wsl --mount` cannot
attach disk 0 (it carries Windows). APFS checksums metadata objects only, not file data, so overwriting bytes inside
an existing extent is invisible to the filesystem. `scripts`-less, in the session scratchpad: `auxkc_patch.py`
(dissect.apfs). It finds the extent (one extent, logical 0, phys 0x8555d9, 0x1dd8000 bytes; not compressed, not
encrypted). Dry run first: the raw block, the block read through APFS and the pulled copy must be equal and match
the byte pattern. Then it backs up both 4 KiB blocks, writes them through `\.\Harddisk0Partition3`, reads them
back (byte now `eb`, the other 4095 bytes unchanged).

ESP: `nmxamd=1` added back (backup `config.plist.bk-addnmx-20261107T174020`). The config is now byte-identical to
the one before Step128 removed it, `-v` kept.

Still to do:
- `/Library/Extensions/NMXGPU.kext` is still 928335c2 with the bug. Any AuxKC rebuild (kmutil, kext install) relinks
  from it and brings the panic back. Build the source fix (fork `nmx-source-port` 326858e) and install it with
  `scripts/macos-install-step125.sh` before the next AuxKC rebuild.
- Undo of the byte patch: write the two `.orig` blocks back to blocks 0x855d9e and 0x855da0 (valid only while the
  AuxKC file is not rebuilt).

### Step128 after the byte patch: hard hang at ~12 s uptime, no panic saved (2026-11-07 18:00)

Three boots with the patched AuxKC and `nmxamd=1` (timesync boots 10:43:52, 10:45:41, 10:58:00 UTC). The 7 s panic is
gone: the verbose text runs on, then the panel goes black (amdgpu has taken DCN). The owner waited 3 minutes in the last
boot; Caps Lock did not toggle its LED.

Evidence (pulled read-only from Windows, `apfs_pull11.py`):
- The last write of anything on the Data volume is 10:58:10.90 UTC: logd.0.log, Persist `0x3a`, strixamp.log,
  wifi.log, install.log, fsck_apfs.log all end by then. Nothing in the 3 minutes after. Timesync maps 10:58:05.4535 to
  kt 6.539 s, so the disk stopped at **~12.0 s uptime**; the 10:45 boot stopped at ~12.3 s. The Persist/Special tracev3
  extents of these boots are zeros (metadata committed, log data never written), so the kernel log of the hang is lost.
- No `aapl,panic-info` in NVRAM, `nullmoth-nv-starts` absent, `nullmoth-nv-ok=1`. This is weaker than it looks: the
  15:56-16:01 boots carried the same weak-import panic and also left no `aapl,panic-info`; only the 16:46 one did.
- The byte patch itself is correct: both `je` -> `jmp` targets leave `start = 0` (0x6db8e5..0x6db8fc zero the
  slot; 0x6dd1a9 is `xor edx, edx`), which is what 326858e does in source.
- `amdgpu-dm-ips-trace.patch` was re-read: printf only (the "dcn35 PMFW IPS support" in its title is the existing
  upstream call it logs around). Ruled out.

Where ~12 s falls, from the good 14:29 boot with the old NMXGPU and NVRM Step124 (Persist 0x2fa, same boot-args):
NMXGPU loaded 7.24 s, amdgpu firmware 8.20 s, `amdgpu_dm_initialize_drm_device` 8.61 s, NMXAMDFB published 9.59 s,
NVRM released by the Step124 wait at 9.70 s and in RTX bring-up (RmInitAdapter, GSP firmware, `_DSM`) through
10-12 s, WindowServer 13.13 s. So the hang is after the DCN takeover and in the window where NMXAMDFB is published and
NVRM brings the RTX up. Boot timing moves by ~1 s between boots, so the exact stage is not known.

Ruled out as test levers: `-nvoff` also parks NMXGPU (`opted_in()` in nmx_kext.cpp), and the "1401" picker
entry / `nullmoth-remove` uninstalls the NVIDIA driver. Neither isolates NVRM from NMXGPU.

Next: the hang stage needs evidence the disk cannot give (the system stops before logd's data reaches it). Build
326858e on the Mac with NVRAM breadcrumbs (Step128 Next 2): one `nmxgpu-stage` mark per stage written with
`IODTNVRAM`, plus NVRM's existing marks; boot once with `nmxamd=1`, read the last mark from Windows. Building and
installing needs one macOS session with a picture (NMXGPU off, StrixGOP raster on), since kmutil cannot run from
Windows and only byte-sized fixes can be written into the AuxKC in place.

### Step128 restore: the 14:29 good boot set put back from Windows (2026-11-07 18:15, reboot pending)

Owner's call: record the trace, then put ESP, kexts and /Library back as they were at the last good boot (14:29,
before Step125/126). Nothing could be relinked (no kmutil on Windows), so the files of that boot were written back
in place from the installers' own backups, the same way as the two-byte patch.

The good boot, from auxguard.log 2026-11-07 07:29:11Z: NMXGPU UUID `591E7D5A` (sha 5760efb6, cave chain), StrixS0ix
`28371854` (0.1.12), probes `0x509100/0x509800/0x509e00`, every other kext as today (NMXAccel C18FD8B4, NMXAGDC
90C7A833, NMXBacklight EF716CC3, NVRM 573209B7, NVAccel 3D45DC36, NVRMFB 64F97BB0, NVRMAGDC 4DBD6B43).

| target | source | sizes (target / source) |
|---|---|---|
| /Library/KernelCollections/AuxiliaryKernelExtensions.kc | step125-bk-20261107T083523Z (built 07:18Z, booted at 14:29) | 31293440 / 31195136 |
| /Library/Extensions/NMXGPU.kext/Contents/MacOS/NMXGPU | step125-bk (591E7D5A) | 10904240 / 10871640 |
| /Library/Extensions/NMXGPU.kext/Contents/Info.plist | step125-bk | 2452 / 2093 |
| /Library/Extensions/StrixS0ix.kext/Contents/MacOS/StrixS0ix | step126-bk-20261107T084026Z (0.1.12) | 70040 / 65680 |
| /Library/Extensions/StrixS0ix.kext/Contents/Info.plist | step126-bk | 1472 / 1472 |
| /Library/StrixGraphicsFix/nmx-relink.probes | new probes for 591E7D5A (see below) | 41 / 41 |
| ESP EFI/OC/config.plist | config.plist.bk-addv-20261107T164437 (the 14:29 config; differs from the current one by `-v` only) | |

- File sizes cannot change from Windows, so a shorter source is padded: Mach-O files with zeros (past the last
  segment, not parsed), plists with newlines after `</plist>` (XML trailing whitespace; both parse). The old probes
  file is 42 bytes and the live one 41, so `probes_calc.py` picked three new windows of the 591E7D5A `__text`
  (`0x80000 0x40`, `0x37f800 0x40`, `0x64bb00 0x40`), each found once in the binary and once in the old AuxKC. The
  original three still match too.
- Checks before writing: not compressed, not encrypted, never cloned (inode flags 0x8000 only), no physical block
  shared with any of the 161 files under /Library/{NullMoth step12*,StrixGraphicsFix,KernelCollections,Extensions},
  each target unchanged since the 18:12 pull, raw blocks equal to the blocks read through APFS. Raw blocks saved
  before the write (session scratchpad `restore_bk_20261107T181538`), read back after it.
- Checks after (fresh APFS parse, files read through the filesystem): every target = its source + padding; both
  plists parse (StrixS0ix 0.1.12); the kccheck conditions hold on the result (three probes 1x/1x, NMXGPU 591E7D5A and
  StrixS0ix 28371854 in the collection, the seven other UUIDs present). So auxguard should log `AuxKC ok` and not relink.
- ESP: current config kept as `config.plist.bk-restore-20261107T181537`.
- Not reverted (userland, loaded long after the boot window, and paired with each other): the NVMTL translator
  (15:40), VCNDec (15:30), and the ESP `StrixSbxMap.kext` Info.plist (15:40:58, cdhash pins for that translator).

State for the next boot: old NMXGPU (cave chain) with `nmxamd=1`, StrixS0ix 0.1.12, NVRM Step124, NMXAccel family
gate, no `-v`. This is the configuration that booted at 14:29.

Do not, on macOS, before the hang above is understood:
- rerun `scripts/macos-install-step125.sh` or `scripts/macos-install-step126.sh` as they are. Step125 installs a
  source build whose weak import panics (928335c2), and 326858e, which fixes that, still hangs the boot at ~12 s
  (the byte-patched AuxKC behaves like 326858e).
- install any NMXGPU source build without NVRAM stage marks, so a hang can be located from Windows.
- worry about the padded files: the next `ditto`/kmutil install replaces them whole.

### Step128 restore verified on macOS (boot 2026-11-07 20:36)

- Loaded: NMXGPU 591E7D5A (cave chain), StrixS0ix 0.1.12 (28371854), NMXAccel C18FD8B4, NVRM 573209B7 and the rest
  as listed above; auxguard `AuxKC ok` (no relink). 890M Metal 3, OLED 2880x1800, `NMXFamilyLayoutOK = Yes`.
  No new panic file after 16:46.
- StrixS0ix 0.1.13 (Step126) is not a suspect: the `nmxamd`-off boots ran it and reached the desktop, and its new code
  runs only at sleep. It can come back with any later relink once the NMXGPU in /Library/Extensions is a good build
  (the restored 591E7D5A is). The Step126 installer itself is fine; Step125's is not.
- Side sessions asked to re-check their own changes on this boot (userland, not reverted): NVMTL translator astc fix
  + StrixSbxMap pins (sim-perf), VCNDec in /System (edge-video-lag), and the NMXGPU session for the ~12 s hard hang of
  326858e (review + NVRAM stage-mark build, no install without the owner).

### VCNDec verified on boot 2026-11-07 20:36 (old cave-chain NMXGPU 591E7D5A, same build as the 15:xx tests)

- Loads from /System/Library/Video/Plug-Ins in VTDecoderXPCService: `vt_test` without `-b` -> VTIsHardwareDecodeSupported 1,
  VP9 1080p60 300/300 frames bit-exact vs libavcodec, 202 fps, 0.44 ms client CPU/frame; AV1 240/240 frames, 205 fps, 0 errors.
- Edge (CDP Media.enable): `Selected VideoToolboxVideoDecoder` for vp9 and av1, `kIsPlatformVideoDecoder true`.
  VCNDec log: one YouTube session "in 5815 out 5815 dropped 0 errors 0 (gpu-copy 5815)".
- Edge YouTube LXb3EKWsInQ, simulator up (40 s each):

| run | decoded | dropped | rVFC gaps > 25 ms | worst | before (CPU decode, part 16) |
|---|---|---|---|---|---|
| 720p60 (right after page load) | 2399 | 30 | 41 | 58 ms | 374 dropped, worst 651 ms |
| 1080p60 | 2398 | 7 | 17 | 44 ms | 164 dropped, worst 99 ms |

  CPU during 1080p60: Edge renderer 19 % (was ~123 %), VTDecoderXPCService 5 %, WindowServer 61 %.
- No crash reports dated after 20:36, no NMXGPU timeout/reset/fault lines (only the routine "mmfix2 stale xkpi records retired").
- Safari: no VCNDec session seen after opening the same YouTube page (no VCNDEC log line from WebKit or a second
  VTDecoderXPCService), so Safari's VP9/AV1 path is not verified yet.

### Step128 review of 326858e against the cave chain, and a stage-mark build (2026-11-07 20:55, built, not installed)

The 7 s panic was the Step125 port's own mistake. kmutil binds a missing weak import to the address
`&gOSKextUnresolved` (Apple's `OSKextSymbolIsResolved` compares addresses). f083d838 compared against that address
and could not link. 928335c2 was then "corrected" to compare against the value. Lesson kept in the installer:
`macos-install-step125.sh` now refuses any NMXGPU that still names `_proc_starttime` or lacks the stage marks.

Review of 326858e, the paths that run in the ~9.6-12 s window (no hang line found; ranked by suspicion):

| area | vs the cave chain | can it hang hard? |
|---|---|---|
| NMXAMDFB boot hold (new) | the cave chain never made NMXGPU busy | not by itself: capped at 30 s, released on every exit. It shifts the boot order, though: the registry root stays busy until publish, and `adjustBusy(-1)` runs on the attach thread right after `nmx_fb_publish`. NVRM's Step124 wait is plain `waitForMatchingService` with timeouts, no waitQuiet. Bisect with `nmxhold=0` |
| lock-free curthread (d345b3e, never booted before) | new | writers use `lck_spin` with interrupts off. No path re-enters it on one CPU: `nmx_curproc`, `proc_name` and `IOMalloc` run outside it, the reaper only queues, and interrupt context gets per-CPU records without the lock. A stuck holder would end in a spin-timeout panic |
| mm/record lifetime (163d117, replaces the mmfix2 cave, never booted before) | broader than the cave | runs on thread/process recycling, so it is live during boot; no lock nesting found |
| rcu (Step77) | same CPU-0 record, but one global raw spin for both types instead of one per type | held only inside `critical_enter` (interrupts off) around `ck_epoch_begin/end`; cannot nest |
| WC/UC split maps (Step90) | same flags as cave.s (kernel reservation 0x1101, cache-mask test) | kernel vmap path same; user paths run only after WindowServer |
| snooped GTT, umap_cache 0, zero flush, TTM order 0 | same values as Step88/91/84/89 | no |
| irqwatch (Step97/100) | same design | lock-free single owner, nobody spins |
| IPS trace | printf only | no |

An open point on NVRAM evidence: NVRM's boot guard writes `nullmoth-nv-starts` with a plain `setProperty` and no
sync. So "nv-starts absent" after a hang may only mean the write never reached flash, not that NVRM never started.

Build: fork `nmx-source-port` e32615c (326858e + stage marks + `nmxhold`), NMXGPU **ed82aa34**, at
`~/develop/projects/nmx-build-xkpi/out-6/NMXGPU.kext`. No weak imports; every kernel import is one other kexts here
already link against (`memchr` and `ml_get_interrupts_enabled` were avoided for that reason).
- `nmxgpu-stage` (Apple GUID 7C436110-...): the last ~180 bytes of `<uptime ms>:<stage>|` entries. Stages: start,
  port_start, port_started, "fw ok, hold, attach", ip_early_init, ip_init, `hw <block>` before each amdgpu hw_init (so
  `hw amdgpu_dm` = the DCN takeover), ip_init done, ip_late_init, attached, "registered, fb publish", fb modeset,
  fb modeset done, fb published, hold released, the first `nmxFlip*` call. Each write is followed by
  `IONVRAM-FORCESYNCNOW-PROPERTY`.
- `nmxgpu-alive`: from "hold released", once a second for 40 s: `<ms> ms beat <n> irq <890M IRQs dispatched> nvrm
  <NVRM's nvrm-nmx-wait>`. The last beat dates the hang, and whether its IRQ count still moves.
- Boot-args: `nmxstage=0` turns the marks off, `nmxhold=0` skips the boot hold.
- The extra NVRAM writes (~25 + 40) shift boot timing a little; if the hang is a race it may move.

Reading the marks from Windows: `GetFirmwareEnvironmentVariableW(L"nmxgpu-stage", L"{7C436110-AB2A-4BBB-A880-FE41995C9F82}", ...)`,
the same for `nmxgpu-alive`. On macOS: `nvram nmxgpu-stage nmxgpu-alive`.

Not installed. Install only with the owner's OK: `sudo scripts/macos-install-step125.sh ~/develop/projects/nmx-build-xkpi/out-6/NMXGPU.kext`
(rollback on any failure, `--undo`).

### Step128 stage-mark build installed (2026-11-07 20:57, owner's OK, reboot pending)

- `macos-install-step125.sh out-6/NMXGPU.kext` succeeded: NMXGPU ed82aa34, UUID 6613CA5C. Backup at
  /Library/NullMoth/step125-bk-20261107T135605Z (the restored 591E7D5A, padded copy, sha 8fead28b).
- New auxguard probes: `0xb4100 0x40 0x383100 0x40 0x651d00 0x40`.
- The AuxKC was relinked and checked twice (now and after 45 s). Also checked separately: kccheck, all 10 kexts OK, StrixS0ix 0.1.12, and the
  `nmxgpu-stage` / `nmxgpu-alive` / `nmxhold=0` strings are in the collection, `_proc_starttime` is not.
- Boot-args unchanged: `nmxamd=1`, no `-v`, boot hold on (no `nmxhold`).
- After the reboot: `nvram nmxgpu-stage nmxgpu-alive` (macOS), or the same variables under the Apple GUID from Windows
  if it hangs. If it hangs, the next boot is with `nmxhold=0`. Undo: `sudo scripts/macos-install-step125.sh --undo`.

### Step128 stage-mark boot: kernel panic at 10.15 s in NMXAccel's early display-mode delivery (read from Windows, 2026-11-07 22:4x)

Boots with NMXGPU ed82aa34 (6613CA5C), from the Data volume and NVRAM (read only, `scripts/windows-apfs/`):
- Persist: the 20:36 boot logs to 22:13:47 (WindowServer death report 22:13:21, the reboot into ed82aa34). After that,
  `0x49.tracev3` (created 22:33:38) is empty and `0x4a.tracev3` (22:36:11) has one non-zero 4K block: no log of
  either boot reached the disk.
- `Kernel-2026-11-07-223607.panic` (written by the 22:36 boot about the boot before it), uptime **10.153 s**:
  page fault CR2 `0x120`, RAX 0, on a `kernel_task` thread call:
  `IOFramebuffer::getAttributeExt+0x28 <- IOAccelLegacyDisplayPipe::displayModeDidChange+0x30 <-
  IOAccelLegacyDisplayMachine::display_mode_did_change+0xea <- NMXAccel deliverModeChange+0x7c <-
  registerFramebufferLocked+0x57a <- nmxArm+0x227 <- thread_call`. NMXAccel C18FD8B4 (unchanged since the good boots).
- NVRAM after these boots: no `nmxgpu-stage`, no `nmxgpu-alive`, no `aapl,panic-info`. The marks never reached flash
  (at least two boots ran a build that writes them from ~7 s), so the stage-mark method gives nothing on this machine;
  the panic report is the evidence.

Disassembly (25G332 SystemKC, read from the sealed System volume):
- `IOFramebuffer::getAttributeExt` (KC 0x14d0406a) does `rbx = [[this+0x1c8]+0]->+0x120` with no NULL test:
  `fPrivate->controller->workloop`, the lock taken before every attribute. `controller` is assigned only in
  `IOFramebuffer::open()` (Step29).
- `IOAccelLegacyDisplayPipe::displayModeDidChange` (KC 0x14b98542) starts with `getAttributeExt(pipe->fb (+0x98), 'mirr')`.
- `display_mode_did_change` (KC 0x14b65b02) calls every pipe's `displayModeDidChange` once the nest count at
  machine+0x10c drops to 0.

So: `nmxArm` got "scanout ready" from NMXAMDFB, registered the pipe and delivered will/did_change to a framebuffer that
nobody had opened yet (WindowServer opens it at ~13 s). NMXAMDFB's scanout answer is ready as soon as `fInfo` is set
before `registerService` (Step69 design, `nmx_fb.cpp` callPlatformFunction), so nothing stops the arm before open().
The 326858e "hard hang at ~12 s" is very likely the same panic without a saved report (same window, same build line).

Why the cave chain boots live: the arm there happened after the FB was open (WindowServer, or the earlier kernel open),
so `controller` was set. The source port changes the order (NMXAMDFB boot hold, kernel modeset before publish), and the
200 ms `nmxArm` poll now wins the race at ~10 s.

Fix (needs a build): never deliver the mode change to a framebuffer that is not open.
- NMXAccel `deliverModeChange` / `onCountGrewLocked`: skip `display_mode_will/did_change` while
  `fb->fPrivate(+0x1c8)->controller` is NULL (register the pipe, deliver later). WindowServer's own `open()` delivers the
  group's mode change itself (Step29 backtrace), so nothing is lost.
- Or NMXGPU: NMXAMDFB sets a "opened" flag in `open()`, and the scanout query answers NotReady until then only for the
  first registration (this brings back the Step69 race, so the NMXAccel side is the better place).


### Step128 fix written from Windows: NMXAccel skips the mode change while NMXAMDFB is not open (2026-11-07 23:06, owner's OK, reboot pending)

In place in the installed AuxKC (the ed82aa34 collection, NMXAccel C18FD8B4), `scripts/windows-apfs/auxkc_patch_nmxaccel.py`:
- NMXAccel `deliverModeChange` (KC 0xcff30). The 58 bytes at 0xcff4e..0xcff88 were its two "delivering
  display_mode_will_change/did_change" ALOG calls. They now hold the test
  `fFB(+0x1020) == NULL || fFB->fPrivate(+0x1c8) == NULL || fPrivate->controller([0]) == NULL -> return` (0xd0108, the
  function's own epilogue), else `jmp 0xcff88` (the original `display_mode_will_change` call). Offsets: `fDM` +0x1000 and
  `fFB` +0x1020 from `registerFramebufferLocked`'s own checks, `fPrivate` +0x1c8 and `controller` at [0] from
  25G332 `getAttributeExt`.
- Covers both callers (0xcfe25 in `registerFramebufferLocked` = the panic path, 0xc802e). will/did stay paired, so the
  machine's nest count (+0x10c) is untouched. Once the FB is open (the cave-chain order) it delivers exactly as before.
  Before open the pipe is still registered and armed; WindowServer's `open()` delivers the group's mode change itself.
- Checks: not compressed, one block (0x96753a, +0xf4e), raw == APFS read == the 22:41 pull, the old bytes matched
  before the write, read back after it, a fresh APFS parse sees the new bytes. NMXGPU probes and the kext UUIDs are not
  touched, so auxguard's kccheck should pass and not relink. Original block saved in the session scratchpad
  (`auxkc_block_96753a_20261107T230638.orig`).
- Lost: the "delivering ..." log line. Any `kmutil` relink drops the patch, so the same test has to go into NMXAccel's
  source (`kexts/NVRM/accel/nvrm-accel.cpp` `deliverModeChange`).

Next boot, read: no panic at ~10 s, the desktop on the 890M; then `log show --last boot | grep -E 'pipe armed|Created FB|display pipe'`
and `nvram nmxgpu-stage nmxgpu-alive` (the stage marks did not survive a panic; on a live boot they show whether they work at all).
If it still goes black, the next panic report (written by the boot after it) names the next stop.


### Step128 reverted to the 20:36 good set from Windows (2026-11-07 23:14, owner's call)

What the boots after the NMXAccel patch showed (Data volume, read 23:12):
- `Kernel-2026-11-07-230819.panic` is the report of the 22:36 boot (unpatched, same 10.15 s `deliverModeChange` panic,
  uptime 9.79 s), written by the 23:08 boot.
- The two patched boots (auxguard / nmx-flip-default at 16:08:21Z and 16:10:20Z) got past 10 s, ran 1-2 min each
  (Persist 0x4b-0x4e, ~34 MB of log in ~3 min) and left no panic, but the screen stayed black. Their logs are not decoded.

Owner: revert. `scripts/windows-apfs/apfs_restore2.py` wrote the installer's own backup
`/Library/NullMoth/step125-bk-20261107T135605Z` back in place (the set that booted at 20:36):
AuxKC (sha 3e7bb295, same size), NMXGPU 591E7D5A (8fead28b, padded 4808 zero bytes), its Info.plist, probes.
Checks: inode flags 0x8000 only, no target block shared with any of 2968 files under /Library/{NullMoth,
StrixGraphicsFix,KernelCollections,Extensions} and out-6, raw == APFS before writing, raw read back after, a fresh parse
shows 0 differing blocks. Raw blocks saved in the session scratchpad (`restore2_bk_20261107T231447`). ESP and the
other kexts were not touched by Step125 and are as at 20:36. The NMXAccel patch is gone with the old AuxKC.

## Edge web video lag part 18: VCNDec showed a loop of the first frames (stale IOSurface seed), fixed (2026-11-07 21:10)

- Owner: on screen the video only looped its first few frames and stuttered. The hitch probe could not see it: it
  counts frame callbacks, not what is on screen.
- WindowServer log: the video surfaces (2-plane NV12, row 1924 bytes) take the NVMTL "item 7: private image, copied in
  and out" path. That path uploads a surface only when its IOSurface seed moves ("G13 surface-in ... seed 0 uploaded").
  VCNDec writes the frame into the surface's pages with the GPU (host-pointer import), so the seed of every pool
  surface stayed 0: WindowServer uploaded each pool surface once and then showed that first frame forever.
- Fix (`src/vcndec.c`): after the GPU copy, `IOSurfaceLock(s, 0)` + `IOSurfaceUnlock(s, 0)` moves the seed.
- New test `build/metal_check clip.ivf`: decodes with vcndec, reads each frame back through Metal (the installed NVMTL
  plugin) and compares it with the surface's bytes. `NVMTL_NO_PLANE_HOST=1` forces the copied path WindowServer takes:

| run | stale frames through Metal |
|---|---|
| without the seed move (`VCN_NO_SEED=1`) | 295 of 300 (only the first 7 = pool size are right) |
| with the fix | 0 of 300 |
| own-pages path (default in a single process), with or without the fix | 0 of 300 |

- Mitigation now: `/Library/NullMoth/vcndec-off` set at 20:58 (Edge back on its software decoders after a page reload).
  The fixed bundle is installed in /System for the next boot; remove the kill switch after that boot and re-check.

### Step128 root cause found on macOS: the source build's Info.plist lost `NMXOwnsDisplay` (2026-11-07 23:3x)

Read on the restored macOS (boot 23:16, NMXGPU 591E7D5A), from the unified log of the two black boots (23:08, 23:10)
and the good one (20:36):

- **Black boot (ed82aa34 + the Windows NMXAccel byte patch):** NMXAMDFB published 9.9 s, pipe armed, WindowServer opened the
  FB at 12.9 s (`pipe: open`, `scanout ok`, `setDisplayMode`), but `nmxgpu-stage` stops at `hold released` (no `first flip`
  mark), and the kernel log has no `NMX flip: API up`, no `import`, no `performTransaction`, no
  `GATES after deliverModeChange ... pipe 0 active = 1`. WindowServer never presented a frame: black.
- **Good boot (cave chain):** `delivering display_mode_will_change/did_change` at 25.083 s, **before** `pipe: open` at
  29.72 s, with no panic, then `pipe 0 active = 1`, `flip: API up`, imports, transactions. So "mode change before open()"
  is not the bug, and the Windows-side NMXAccel patch (skip the delivery before open) removed the one delivery that turns
  the pipe active: that is what made the patched boots black.
- **Difference:** `IOFramebuffer::start()` builds the framebuffer's controller only from an `IOFBDependentID` that is
  already set (b15 comment in `nmx_fb.cpp`). NMXAMDFB sets it only when the internal panel is `foreign` or `owned`, and
  `owned` needs `NMXOwnsDisplay = true` on the NMXGPU provider. The live cave-chain `Info.plist` has it
  (`IOKitPersonalities/NMXGPUAMD/NMXOwnsDisplay`, written by `macos-nmx-owns-oled-install.sh`, Step80); the source
  tree's `gpu-port/xkpi/kext/Info.plist` never had it (a full plist diff shows this is the only difference), and
  out-6 (ed82aa34) has none. So NMXAMDFB had no controller group: unpatched, NMXAccel's first mode change faulted in
  `getAttributeExt` on `fPrivate->controller` NULL (CR2 0x120 at 10.15 s; the earlier "hang at ~12 s" is the same panic
  without a saved report); patched, no panic but no display pipe, black.

Fix (fork `nmx-source-port`, not yet booted):
- `kext/Info.plist`: `NMXOwnsDisplay` true in the NMXGPUAMD personality.
- `xnu/nmx_fb.cpp`: the internal panel is owned unless the provider says `NMXOwnsDisplay = false` explicitly, and a
  panel that ends up neither owned nor foreign logs `neither owned nor foreign ... no display pipe`.
- `scripts/macos-install-step125.sh` refuses a build whose plist lacks `NMXOwnsDisplay=true` or whose binary lacks the
  owned-by-default fix.
- NMXAccel stays as built (C18FD8B4): the delivery before open is correct once the controller exists.

### Step129: NMXGPU 4fa624f9 (owned-by-default fix) + StrixS0ix 0.1.13 installed (2026-11-07 23:4x, owner's OK, reboot pending)

- NMXGPU from fork `nmx-source-port` 57ae789 (UUID B9229F5F, sha 4fa624f9): `NMXOwnsDisplay` true in the plist,
  owned-by-default in `nmx_fb.cpp`, plus everything of e32615c (stage marks, `nmxhold=0`, IPS trace, lock-free
  curthread, boot hold, no `proc_starttime`). Installed with `scripts/macos-install-step125.sh` (backup of the cave set
  591E7D5A in `/Library/NullMoth/step125-bk-*`), then `scripts/macos-install-step126.sh` (StrixS0ix 0.1.13). AuxKC
  checked: both kexts by UUID, NVRM Step124, NMXAccel family gate, NMXBacklight 0.4.0; probes 0xb4100/0x383100/0x651d00.
- Expect after the reboot: NMXAMDFB with `IOFBDependentID`, `GATES after deliverModeChange ... pipe 0 active = 1`,
  `NMX flip: API up`, imports, desktop on the 890M, no panic; `nmxgpu-boot-hold` "released: NMXAMDFB published".
- Undo from macOS: `sudo scripts/macos-install-step125.sh --undo` (+ `macos-install-step126.sh --undo`). If the boot
  fails: the Windows restore of `step125-bk-*` as in the 23:14 revert.

### Step129 VERIFIED (boot 2026-11-08 09:12): the source-built NMXGPU drives the OLED

- Loaded: NMXGPU B9229F5F (4fa624f9, fork 57ae789), StrixS0ix 0.1.13. No new panic file (latest is still the 23:08 report
  of the ed82aa34 boot, CR2 0x120 at 9.79 s, the cause fixed here).
- `boot hold released: NMXAMDFB published after 1393 ms`; NMXAMDFB has `IOFBDependentID` 0x4E4D584700000001 and
  `NMXOwnsDisplay`; NMXAccel `delivering display_mode_will_change/did_change` with no fault, `GATES ... pipe 0 active = 1`,
  `pipe armed`; NVRM `890M wait: NMXAMDFB registered after 892 ms`; `NMX flip: API up` at 09:12:47; `nmxgpu-stage` ends
  `fb published | hold released | 14914:nmxFlipCaps` (the NVRAM marks do persist on a live boot). 890M Metal 3.
- So the whole technical-debt build (lock-free curthread, boot hold, all caves in source, IPS trace) is live. Next: one
  sleep test (owner starts it) for the `NullMoth ips:` and `StrixS0ix: link` lines.
- Also on the earlier cave boots, not from Step129: WindowServer abort 23:18:29 (uptime 110 s) in window capture
  (`WSCaptureCreateIOSurfaceMachPortForWindowList` -> `MetalIOSurfaceBacking::PrepareForUse` -> `AbortWithTextureInfo`:
  a capture IOSurface did not get a Metal texture), and 22:13:36 a CoreDisplay assert in `RunFullDisplayPipe` (uptime
  5800 s, the reboot into ed82aa34). Open: the capture abort (screenshot/screen-share path through NVMTL).

**WindowServer abort 23:18:29 (cave boot), root cause chain** (edge-video session + kernel log):
1. 23:18:09.985 amdgpu `[gfxhub] page fault (src_id:0 ring:40 vmid:2 pasid:32803)`, client TCP, `PERMISSION_FAULTS 0x5`,
   `RW 1`: a shader of some app (amdgpu names "pid 14947" with an empty process name: the xkpi task identity, not a
   macOS pid that logged anything) wrote to a page mapped read-only (likely a read-only userptr import, Step92).
2. The GFX queue stalls: NMXAccel `iop: fence ... after 100 ms - copied anyway` from 23:18:10, WindowServer's NVMTL
   `vk: fence wait -> 2 after 5027 ms; disabling backend` at 23:18:15, CoreAnimation `GPU event segment submission
   failed`, `MTLTexture creation failed - (vulkan down)`.
3. The next window capture needs a texture: `AbortWithTextureInfo`, WindowServer abort.
Open (NMXGPU/xkpi, mine): one app's GPU write fault must not take WindowServer down. Next: name the faulting process
(pasid -> process in the xkpi VM fault print), and check whether the read-only userptr retry hands a writable target
to the GPU; and whether amdgpu's job timeout/ring reset recovers before NVMTL's 5 s budget in WindowServer.
This happened on the cave build (591E7D5A); Step129's source build has the same userptr code (35c6815).

## Step130: brightness slider dead on Step129; NMXBacklight removed, its work moved into the NMXGPU source (2026-11-08)

Owner: the brightness slider no longer works (first boot on the source-built NMXGPU, Step129).

Root cause: NMXBacklight 0.4.0 called NMXGPU by **fixed file address** (`linux_backlight_update_status` 0x6c3970,
`nmx_backlight_next` 0x6d25f0, `__ZTV8NMXGPUFB` 0x8f4f10, checked against byte signatures of the NullMoth cave build)
and swapped NMXAMDFB's vtable for a private copy. The source build has another layout, so at 09:12:41
`NMXBacklight: vtable ... is not NMXGPUFB's, inert`: no "backlight" child under the framebuffer, `getAppleSense` not
LCD, so IOGraphics made a plain `AppleDisplay` (no `AppleBacklightDisplay`, no slider, no Fn brightness). The same
kext also carried the Step109d **paging wake** (WindowServer hang after a system sleep), so that fix was off too: a
system sleep on Step129 would have hung WindowServer after wake. StrixGOP 0.1.11 is loaded but silent (it serves the
firmware GOP framebuffer, which is not there under NMXGPU).

**Rule (do not repeat): no kext may call into NMXGPU (or any of our own drivers) by address, by byte signature or by
patching its vtable. Anything NMXGPU-specific goes into the NMXGPU source (fork nmx-source-port), where the compiler
keeps it right across rebuilds.** Address-based hooks were only acceptable while NMXGPU was a NullMoth binary we could
not rebuild; since Step129 we own the source.

Fix (fork nmx-source-port, NMXGPU out-8):
- `override/src/linux_pci.c`: `nmx_backlight_percent(set, &pct)` over xkpi's backlight registry and amdgpu's own
  backlight ops (`amdgpu_dm_backlight_update_status` -> DC, AUX nits on the OLED). Same path NMXBacklight used.
- `xnu/nmx_fb.cpp`: NMXAMDFB publishes the `backlight` IODisplayParameterHandler (`NMXFBBacklight`, applies from a
  thread call, `Backlight,*` properties on the framebuffer) before registerService, and overrides `getAppleSense` (LCD
  for connection 0). `-nmxbloff` leaves it out.
- `xnu/nmx_fb.cpp`: the Step109d paging wake as members (WillSleep tap, gate on the framebuffer workloop, power-on in
  `setPowerState`, 3 s fallback armed on WillPowerOn and HasPoweredOn). `NMXPagingWake` property; `-nmxfbwakeoff`.
- `xnu/nmx_kext.cpp`: NMXPowerKeep (Step106 display-sleep hold of NMXGPU, sleep/wake timeline) is a child NMXGPU
  starts itself; `-nmxkeepoff`, `nmxkeep_dsleep=0` as before.

Cleanup: `kexts/NMXBacklight` and `scripts/macos-install-nmxpowerkeep.sh` deleted; NMXBacklight dropped from
`scripts/build.sh`, auxguard, nmx-relink, step126 and the sleep test scripts. Older step installers (100..125) still
name it; they install the NullMoth cave chain and are history, superseded by Step125/130.

NullMoth daemons reviewed: `com.nullmoth.displaytrace` (continuous NVRM/WindowServer log streams for NullMoth's NVIDIA
display bug reports) and `com.nullmoth.wsreset` (restart WindowServer once per boot, NVIDIA flicker stopgap; last ran
2026-11-03) are removed by the Step130 installer (plists kept in the backup). Kept: `bootguard` (NVIDIA boot-good
counter for the boot picker), `recover` (NVRAM-flag uninstall safety net, exits at once), `wsdeath` (ours, Step81,
captures logs when WindowServer dies: needed for the screenshot-markup freeze), `nmx-flip-default`, `auxguard`.

Install: `sudo scripts/macos-install-step130.sh ~/develop/projects/nmx-build-xkpi/out-9/NMXGPU.kext` (relinks AuxKC,
new probes, checks the Step130 strings and that NMXBacklight is gone). Undo: `--undo`.
Verify after reboot: `ioreg -c AppleBacklightDisplay` present, `NullMoth display: backlight handler published`,
slider and Fn keys change the panel, `NMXPagingWake` = Yes, `NMXPowerKeep: holding NMXGPU`.

### Part 19: WindowServer re-imports video surfaces (surface keep "expired")

- 1080p60 VP9 in a scratch-profile Chrome (VCNDec live, picture verified on screen): WindowServer ~85 % CPU. A 10 s
  spindump puts 26 % of its main thread in `-[NVMTLDevice newTextureWithDescriptor:iosurface:plane:]`, 21 % of it in
  `nvmtl_vk_buffer_import_host` (ioctls). The 30 s surface keep reports show why: up to 1460 of 1775 misses per 30 s are
  "after drop: expired".
- Cause found in the sweep: a held entry (surface retained elsewhere) kept the time of its last wrap, so a surface held
  longer than NVMTL_KEEP_MS (3 s) without a new wrap expired at the first sweep after its release.
- Fix: plugin 9f3e2b6 (nmx-plugin-camcopy). Held entries restart their idle time at each sweep. The 30 s report adds when
  expired surfaces came back (< 250 ms / < 1 s / < 3 s / later) and the held refresh count; up to 6 expired misses per
  window are logged with size, format and idle time at the drop.
- Installed 2026-11-08 09:44: NVMTLDriver sha256 11b15ce6 (backup /Library/NullMoth/nvmtl-plugin-20261108T024416Z =
  ad4b5c35), strixsbxmap --refresh stale 0. WindowServer loads it at the next boot (together with Step130).
  Undo: `sudo scripts/macos-nvmtl-plugin-install.sh --undo`, then `scripts/macos-install-strixsbxmap.sh --refresh`.
- After that boot: the 30 s reports (expired count, came-back buckets), WindowServer CPU with 1080p60 in Chrome, and
  screenshot / screen share (main session asked: the 23:18 capture abort followed a 5 s GPU hang, "vulkan down").

### Screenshot-markup freeze (WindowServer abort 23:18): the faulting process and the mechanism

- amdgpu's "pid 14947" is the xkpi task's `pid` = the thread id (`td_tid`), not a process id. TID 0x3a63 in the unified
  log is **mediaanalysisd[1905]** (Live Text / TextRecognition, Espresso `default.metallib`) running on the screenshot
  open in Preview. Not Preview, and not WindowServer.
- Its last NVMTL lines before the fault (23:18:08): `surface 174 plane 0/1 ... fmt '420f' -> its own pages (host import,
  written back after each command buffer)` and `storage twin: 1376x864 (IOSurface) is written through an optimal-tiled
  storage copy`. 23:18:09.985: gfxhub `PERMISSION_FAULTS 0x5`, `RW 1`, client TCP.
- Mechanism: the surface is mapped read-only in that process. A writable userptr pin then fails, and Step96
  (`nmx_userptr_tail`) silently retries read-only, so the GPU PTEs have no WRITEABLE bit. NVMTL does not know and builds
  a writable wrapper (write-back, storage twin, single-plane alias with rw=1). The GPU write faults, and the GFX job
  hangs the shared ring until the 10 s job timeout.
- WindowServer's NVMTL gives up on a fence after 5 s, so its backend is disabled and the next window capture aborts.

Fixes (one reboot, with Step130):
- NMXGPU out-9: `patches/amdgpu-gfx-timeout-3s.patch`, gfx/sdma/video job timeout 10 s -> 3 s, so soft recovery of the
  guilty job finishes inside NVMTL's 5 s budget. One app's GPU fault must not take WindowServer down.
- NVMTL plugin (edge-video session): check `VM_PROT_WRITE` of the range before a writable host import; a read-only
  mapping gets a private image for writable wrappers.
Verify: open a screenshot in Preview, draw with Markup, Live Text active. Expect no gfxhub fault, or a fault followed by
`soft recovered` within ~3 s, and WindowServer staying up.

NMXGPU out-9 built 09:49: 4d4e6563 (UUID 8A149786), fork 521730c = Step130 + gfx timeout 3 s. This is the build to install.
- Same boot, 09:49: plugin dd43056 on top (installed sha256 00660e02, backup nvmtl-plugin-20261108T024947Z = 11b15ce6,
  sbxmap stale 0, TextEdit loads it). Root cause from the main session: at 23:18 mediaanalysisd (Live Text on a Preview
  screenshot) host-imported a surface mapped read-only in it as a writable wrapper; amdgpu pinned the pages read-only,
  the GPU wrote them (gfxhub PERMISSION_FAULTS), the GFX ring hung and WindowServer's capture aborted. Fix:
  `nvmtl_span_writable` (mach_vm_region, VM_PROT_WRITE over the span). Read-only mapping: a read-only wrapper imports
  read-only (`_hostRO`), a writable one gets a private image, surface-out skips the CPU write-back. Unit check: rw 1, one
  read-only page 0, hole 0, own IOSurface 1. Look for `mapping is read-only in this process` (apps, mediaanalysisd) and
  `surface-out: surface N is mapped read-only` after the boot; NVMTL_SURF_RO_CHECK=0 turns it off.

Installed 2026-11-08 ~10:00: Step130 (NMXGPU out-9 8A149786, AuxKC checked twice, NMXBacklight.kext and displaytrace/wsreset daemons gone) + NVMTL plugin dd43056 (00660e02, edge-video session: read-only mapping check + surface keep). Reboot pending.

### Step130 boots read from Windows: both ended without a shutdown and without a panic (2026-11-08 10:10)

Data pulled from Windows (dissect.apfs, read only) at 10:10: system.log, logd.0.log, fsck_apfs.log, wifi.log,
nmx-flip-default.log, bootguard.log, Persist/Special/Signpost tracev3, NVRAM under the Apple GUID.

| | Boot A (first Step130 boot) | Boot B |
|---|---|---|
| kernel start | 10:02:57 (`BOOT_TIME 1794106977`) | ~10:05:14 (logd up 10:05:18, same +4 s as boot A) |
| fsck / flips on | 10:03:03 / 10:03:05 | 10:05:19 / 10:05:21 |
| desktop | bootguard "came up and stayed up" 10:03:49 | no bootguard line |
| last sign of life | wifi health check 10:04:04 (next one due 10:04:34 never written), logd 10:04:50 | NVRAM `nmxgpu-alive` beat 14 at 21578 ms (~10:05:36) |
| end | no `SHUTDOWN_TIME`, no "No userlevel firehose clients left" | Persist `...5e` and Special `...45` allocated but all zeros (data never flushed) |

- NVRAM after boot B: `nmxgpu-stage` ... `8562:fb modeset done|8571:fb published|8571:hold released|`;
  `nmxgpu-alive` = `21578 ms beat 14 irq 759 nvrm NMXAMDFB after 893 ms`. The beats run once a second for 40 s from
  "hold released", so they stopped after 14 of 40. No `aapl,panic-info`, no .panic report.
- Boot A's Persist `...5d` was flushed only to 67.6 s uptime (10:04:04); the last ~50 s before its end are not on disk.
- From the disk alone a hard hang and a forced power-off look the same. Both boots ended with no shutdown record
  and no panic: boot A ~2 min after the desktop came up, boot B at ~22 s uptime, before airportd's first log.
  Boot B never reached the desktop; it stopped about where boot A was starting WindowServer/loginwindow.
- The Step129 boot before them (09:12-10:02) ran 50 min. WindowServer crashed at 10:02:18 (stack guard,
  `-[NVMTLCommandQueue commandBuffer]` under `RenderEncoder` <-> `SetScissor` recursion, the 2026-11-06 14:07 pattern:
  the NVMTL backend had stopped giving command buffers). The shutdown stall report is from 10:02:42.
- Open: what the screen showed at the end of each boot (frozen picture, black, or still moving). The next boot needs
  a longer record: the 40 s beat window misses a hang at ~2 min.

### Step130 black screen: NMXAccel never takes NMXAMDFB, so the display pipe is never armed (2026-11-08 10:40, read from Windows)

Owner: both Step130 boots showed a **black screen**; the owner held the power button (so A and B were power-offs on a
black panel, not hangs).

Kernel log decoded from Windows (firehose entries with the absolute formatter: the format string is at
`format_string_location` inside the kext image; NMXGPU image = AuxKC vm 0xe5000, NMXAccel = 0xc0000, from the catalog's
pid-0 load table: NMXGPU 8A149786 at 0xff7f96deb000 size 0x8a4000, NMXAccel C18FD8B4 at 0xff7f96dc6000). NMXAccel is the
same binary in Step129 and Step130, so its lines decode the same way for both boots.

| | Step129 boot 09:12 (picture) | Step130 boot A 10:02:57 (black) |
|---|---|---|
| NMXAMDFB published | 8.73 s | 9.197 s (`boot hold released ... after 1380 ms`) |
| NMXAccel `NMXAMDFB published -- display machine framebuffer count = 0` | 8.731 | **missing** |
| `NMX display bind: scanout ready` / `pipe armed on owned native framebuffer` | 8.731 | **missing** |
| `GATES after deliverModeChange: pipe 0 active = 1` | 8.731 | **missing** |
| WindowServer open, mode change | later, gate open | 13.695 `initFramebufferResource ... gate 0`, `scanout gate CLOSED -- returning NULL` (x3) |
| backlight | (NMXBacklight inert) | `backlight handler published (initial 100%)`, `backlight set brightness = 100`, `100% applied (rc 0)` |

- The backlight itself worked (100 %, rc 0). The panel was black because WindowServer's pipe had no scanout: NMXAccel's
  `fbPublished` never logged, so `nmxArm` never ran. `fbPublished` returns silently unless the new service is an
  `NMXGPUFB`, its provider's provider is NMXAccel's PCI device, and it carries `NMXScanoutBridgeVersion`. Same signature
  as the Step128 black boots (no arm, no `GATES`, no `flip: API up`, NVRAM stages end at `hold released` without
  `nmxFlipCaps`).
- The only Step130 change on that path is in `NMXAMDFB::start()` (fork 521730c, `xnu/nmx_fb.cpp`): before the
  framebuffer registers, it now attaches the `backlight` child and calls `registerService(kIOServiceSynchronous)` on it
  (kernel log 9.196991 `childPublished | backlight`, then 9.197218 `childPublished | NMXAMDFB`). NMXPowerKeep (new child of
  NMXGPU) and the 3 s job timeout do not touch the framebuffer publish. Which `fbPublished` check fails is not visible
  in the log (it returns without a line).
- Test that isolates it without a rebuild: boot-arg `-nmxbloff` (NMXAMDFB skips `publishBacklight()`, back to Step129's
  start order; no slider). Picture with it = the backlight child registration is the cause.
- Source fix to build on macOS: publish the backlight child after `fb->registerService()` in `nmx_fb_publish()` (still
  before WindowServer's first open at ~13.7 s), not synchronously inside `start()`; and log every early return in
  NMXAccel's `fbPublished`.

**Applied (2026-11-08 10:59, from Windows, owner's request):** `-nmxbloff` appended to the boot-args in ESP
`EFI/OC/config.plist` (`NVRAM > Add > 7C436110-… > boot-args`; OpenCore rewrites the NVRAM value each boot). Only that
line changed (+10 bytes), XML parses, ESP unmounted. Backup `config.plist.bk-bloff-20261108T105940`. To undo, drop the
flag. Expected on the next boot: `-nmxbloff: no backlight` in the kernel log, no brightness slider or keys, and
`getAppleSense` no longer reports LCD. Picture = the backlight child registration in `start()` is the cause.

## Side check: "NullMoth" menu bar item, Olaz, and the two 11:19/11:23 panics (2026-11-08)

**Menu bar item ("Power off Card" x3).** Not a NullMoth app. It is Apple's own `ExpressCard.menu` in SystemUIServer. NullMoth installs no menu bar app, LaunchAgent or login item (its installer only adds two OpenCore picker entries, "1401: Remove NVIDIA driver" and "1401: Start once without NVIDIA driver"). The menu shows because the root ports GPP4 and GPP9 report PCIe hot-plug (`IOPCIHotPlug = Yes`, `IOPCIHPType = 33`), so IOPCIFamily treats their children as removable cards:
- Display Controller = RTX 5060 (10de:2d59, GPP9/PEGP)
- Multimedia Device = RTX HDMI audio (10de:22eb, GPP9/HDAU)
- Unknown Card Type = Realtek RTS525A SD reader (10ec:525a, class ff, GPP4/SDCR)

Nothing to uninstall. Do not click "Power off Card" on the RTX entries (it ejects the GPU under NVRM). Hiding the menu means clearing hot-plug on GPP4/GPP9 (ACPI/DeviceProperties in config.plist); not done, it touches the ESP config and the RTX D3cold path. Side effect worth knowing: the "removable" flag is also why WindowServer's `gpu-policies` is `avoidRemovable`, which keeps apps off the RTX.

**Olaz.** `app.olaz.mac`, the owner's own native Zalo client (`~/develop/projects/zalo-swift-re`, ad-hoc signed, AVFoundation + Network + ScreenCapture, rebuilt 11:22:53). No crash report for Olaz exists in either DiagnosticReports folder. It did not crash by itself: the machine panicked under it.

**Panic B, `Kernel-2026-11-08-112352.panic`** (boot 11:19:45, panic at 206 s = ~11:23:11): `assertion failed: now >= *pkt_enq_time` in `fq_codel_dq`. The backtrace is `HoRNDIS::outputStart -> IONetworkInterface::dequeueOutputPackets -> ifclassq/fq_codel`. A OnePlus 13 was plugged in for USB tethering at 11:22:10 (HoRNDIS en2 published, `AppleUserECMData::start fail`), 61 s before the panic. Not the Wi-Fi driver and not the GPU stack. A packet's enqueue time was later than the dequeue time: either HoRNDIS (old third-party kext, 9.3) dequeues on a path that breaks fq_codel's clock order, or the TSC is not in sync across cores and HoRNDIS just happened to be the dequeuer. The cross-core TSC check was handed to the Wi-Fi/network session. HoRNDIS was live again in the next boot (11:24:47) with no panic so far, so it is not deterministic.

**Panic A, `Kernel-2026-11-08-111949.panic`** (a boot that ended at 23 s, before 11:19:45): `NMIPI for unresponsive processor: TLB flush timeout`; CPU 0 sat in `AppleAPICInterruptController::handleInterrupt` under `AppleACPIPlatformExpert::dispatchGlobalInterrupt` (a level-triggered global interrupt firing again and again), and airportd on CPU 22 waited for it in a pmap TLB shootdown. airportd is the victim, not the cause. That boot left no unified log (it died before the log was flushed), so the interrupt source is unknown. Candidates: a GPIO/ACPI interrupt left asserted early in boot (I2C touchpad runs `-vi2c-force-polling`, AsusWmi EC, StrixS0ix). Next trace: log the GSI number in a kernel-side handler or read `ioreg` interrupt counts right after login when it repeats.

Next: Wi-Fi/network session checks TSC sync across cores and HoRNDIS; if HoRNDIS is confirmed, use the phone's tethering over Wi-Fi/Bluetooth or remove HoRNDIS from OpenCore (owner decides).

## Step130c: -nmxbloff boot confirms the backlight child; fix installed (2026-11-08 ~11:40)

- Boot 11:23:50 with `-nmxbloff`: picture. `NullMoth display: -nmxbloff: no backlight`; NMXAccel
  `GATES after deliverModeChange: pipe 0 active = 1` and `display pipe armed`; `NMX flip: API up`. On the same
  boot: `NMXPagingWake` = Yes, NMXPowerKeep `holding NMXGPU` (state 1), and plugin dd43056 loaded in WindowServer.
  So the synchronous registration of the `backlight` child inside `NMXAMDFB::start()` is the cause of the black panel.
- Fix (fork 6c7de24, NMXGPU out-10, UUID BC71D713):
  - `NMXScanoutBridgeVersion` is set right after `IOFramebuffer::start()`.
  - `publishBacklight()` moved out of `start()` into `nmx_fb_publish()`, after `fb->registerService()`. The
    child's `registerService()` is now asynchronous, with `fLcd` set first. This is the point where the old NMXBacklight
    attached, and its slider worked.
- Installed with `macos-install-step130.sh .../out-10` (AuxKC checked twice). `-nmxbloff` removed from the ESP
  boot-args with `tools/occonfig.py args del` (backup `EFI/OC/config.plist.step130c`).
- If the panel is black again, put `-nmxbloff` back from Windows (copy `config.plist.step130c` back) and add logging of
  every early return in NMXAccel's `fbPublished`.
- WindowServer crash 10:02:18 (Step129 boot, during the reboot to Step130): `GPU reset` at 10:02:05 during shutdown,
  then `-[NVMTLCommandQueue commandBuffer]` -> SkyLight `MetalContext::RenderEncoder`/`SetScissor` recursed until the stack
  guard (SIGSEGV). Open, for the plugin: commandBuffer must not hand SkyLight something that makes it recurse after the
  backend is down.

### Step130c VERIFIED (boot 2026-11-08 11:47): picture + brightness from the NMXGPU source

- NMXGPU out-10 (BC71D713) loaded without `-nmxbloff`. Picture is up, and there is no new panic. (The 11:46
  shutdownStall belongs to the previous boot's reboot.)
- `backlight handler published after the framebuffer (... initial 100%), panel sense LCD` at 11:47:06. IOGraphics then
  built **AppleBacklightDisplay** (`backlight parameters on AppleBacklightDisplay`), and NMXAccel armed the display pipe.
- End-to-end test with DisplayServicesSetBrightness: 0.5 gives `Backlight,Percent` 50 and restore gives 100, both rc 0,
  failures 0. `NMXPagingWake` = Yes.
- Visual confirmation (slider and Fn keys) is still owed by the owner.

## Step131: zero-copy flips were off since the source port (PAGE_MASK) (2026-11-08 12:10)

From cpu-thermal (docs/CPU-THERMALS.md, cause 2): on every boot since Step129, `NMX flip: import failed at
descriptor page (0)` (8 refusals), `flip_submitted 0`. NMXAccel therefore CPU-copied every frame: ~100 fps x 20.7 MB,
the NMXDisplayPipe thread at 16 % of a core, and `beam_copy_us` 3.3-7.4 s per 10 s.

Root cause: `override/src/nmx_fb_bridge.c` `flip_import()` tests `pa & PAGE_MASK`. That file includes LinuxKPI
headers, where `PAGE_MASK` is Linux's `~(PAGE_SIZE - 1)`, not BSD's `PAGE_SIZE - 1`. So every non-zero physical
address looked misaligned. The cave build (`scripts/nmx-flip/import.c`) tested `pa & 4095`; the source port changed the
spelling and not the meaning. `nmx_linux_cdev.c` already carries a comment about this trap. The other `PAGE_MASK` users
are BSD-side (`bsdcompat`) or Linux code that means the Linux mask.

Fix: fork 8c18558, test `pa & (PAGE_SIZE - 1)`. NMXGPU out-11. Expected after the reboot: `NMX flip: import N:
2880x1800 ...` lines, `flip_submitted` rising, `beam_copy_us` near 0, and lower WindowServer/kernel_task CPU.

Panics today:
- 11:23 and 11:57: `fq_codel` `now >= *pkt_enq_time` under HoRNDIS (USB tethering).
- 11:19: TLB flush timeout, CPU 0 stuck in APIC interrupt handling. CPU 0 also takes the touchpad I2C controller's
  ~10k IRQs/s (VoodooI2C polling, CPU-THERMALS cause 4): a strong suspect for the 11:19 storm.

The owner suspects the AWDL work (boot-arg `itlmt_awdl=1`). The AWDL session has been asked to confirm or rule it out.

### Step131 installed (2026-11-08 12:11)

- NMXGPU out-11 (fork 8c18558, UUID BB80044A, flip_import PAGE_MASK fix) installed with `scripts/macos-install-step130.sh`, backup `/Library/NullMoth/step130-bk-*`.
- StrixS0ix 0.1.14 (runtime CC6 idle hook, idle mode 0 at boot = stock) installed with `scripts/macos-install-s0ix-idle.sh`, backup `/Library/NullMoth/s0ix-idle-bk-20261108T051048Z`.
- AuxKC relinked twice, kccheck + new probes OK both times (rc 0). Reboot pending.
- After boot check: `NMX flip: import` lines, `flip_submitted` rising, `beam_copy_us` ~0, WS/kernel_task CPU lower; StrixS0ix 0.1.14 mode 0; brightness; no panic.
- Undo: `sudo scripts/macos-install-s0ix-idle.sh --undo`, then `sudo scripts/macos-install-step130.sh --undo` (back to out-10).

### Part 20: plane host in WindowServer (plugin 5405e50), measured on the 12:14 boot

- Plugin 5405e50 on 0a2f577 (installed 12:11, sha256 8201eaaa, backup nvmtl-plugin-20261108T051123Z = 00660e02,
  sbxmap stale 0; WindowServer loaded it at the 12:14 boot):
  - plane host import on in WindowServer (`surface planes: host import ... shadowed on the GPU`, NV12 planes `-> its own
    pages`, no more G13 surface-in uploads of video planes);
  - surface keep: a live wrapper (the backing or a view of it) keeps its entry up to 60 s after its last wrap
    (`held entries refreshed N (by a live wrapper M)`);
  - WindowServer exits with the reason when a device that was up is lost, instead of SkyLight's RenderEncoder ->
    SetScissor recursion (WindowServer-2026-11-08-100218.ips); a failed begin returns its capacity slot.
- Test: local 1080p60 VP9 clip (WebCodecs, remuxed to WebM, served on 127.0.0.1; no network: the 11:57/12:14 panics are
  HoRNDIS fq_codel `now >= *pkt_enq_time`, network side) in a scratch-profile Chrome, VCNDec decoding.

| Plugin in WindowServer | dropped / frames (40 s) | rVFC gaps > 25 ms | worst | `newTextureWithDescriptor:iosurface:` share of WS main thread |
|---|---|---|---|---|
| dd43056 (private plane images) | 4 / 2397 | 97 | 75 ms | 26 % (11-07 spindump, YouTube) |
| 5405e50 (plane host) | 0 / 2398 | 40 | 50 ms | 3 % (25 of 801 samples) |

- Picture checked on screen: the clip's frame counter advances (132 -> 182 between two captures), colours right.
- Video's own WindowServer cost is now small: pause vs play moved WindowServer ~37 -> ~40 % in a quiet window; the rest
  of WindowServer's 40-90 % follows whatever else is on screen (the owner's Edge was playing at the same time).
- WindowServer spindump (8 s, main thread 5.17 s CPU): UpdateDisplays 341 samples, CompositorMetal 199, CoreAnimation
  OGL render 146, present 56; NVMTL submit 60 (radv cs submit 27), surface import 19. What is left is mostly SkyLight /
  CoreAnimation CPU work per layer, then submit cost: the next lead for compositor CPU.

### Step131 VERIFIED (boot 2026-11-08 12:13:58, after the 12:14 HoRNDIS fq_codel panic)

- NMXGPU BB80044A loaded. `NMX flip: import 8..11: 2880x1800 pitch 11520, 5063 pages` at 12:14:13, 0 import failures: zero-copy flip works again (was off since the source port).
- Brightness: handler published, `Backlight,Writes` 252, Failures 0, LastRc 0. `NMXPagingWake` = Yes.
- StrixS0ix 0.1.14 loaded; the cpu-thermal session is cycling runtime idle mode 0/1/2 (12:23-12:25) for its A/B.
- WindowServer about 39 % with Edge + Chrome Remote Desktop open (edge plugin 5405e50 also live this boot).
- New noise: bluetoothd ExcUserFault x5 since 12:01 (also before this boot; not ours to chase here).
- Owner test 12:40: drawing in Preview Markup no longer freezes (the screenshot / Live Text freeze from Step130: 3 s gfx timeout in NMXGPU + read-only userptr check in plugin dd43056+). PASS.

### Part 21: WindowServer compositor CPU breakdown, and a GPU fault from non-resident surface pages

- WindowServer spindump (8 s, plugin 5405e50, busy desktop): main thread 356 of 801 samples waiting for messages; the
  busy rest is spread thin (QuartzCore 54, SkyLight 43, NMXGPU kext 43, objc 34, malloc 31, radv 26, NVMTL 20 self).
  UpdateDisplays 341 inclusive: render_update 218 (CoreAnimation OGL render 146: NVMTL draw 17, setFragmentTexture 12,
  setRenderPipelineState 12), present 56 (CoreDisplay RunFullDisplayPipe 35, NVMTL submit 16), prepare_coreanimation
  40. No single hotspot left in the plugin; display at 120 Hz, ~4.6 ms of main-thread CPU per composited frame.
  `renderCommandEncoderWithDescriptor:` formats an NSString per encoder (3 samples): small, noted.
- 12:42:49 GPU fault: mediaanalysisd (thread 0x13e39, Live Text), gfxhub PERMISSION_FAULTS 0x5, TCP RW 1; GFX ring timeout
  soft-recovered 3 s later; WindowServer `slowest submit 3008 ms` (screen stalled 3 s). The surface was mediaanalysisd's
  own new 420f surface (398, plane host, written back after each command buffer): a writable mapping, so dd43056's check
  passed. A fresh IOSurface has none of its pages resident (`mincore`: 0 of 297); the kernel's write pin of non-resident
  pages fails and nmx_userptr_tail retries read-only (`NMX cs-trace: userptr_ro_retry -> 0`, the log budget used up by
  WindowServer at 12:14:53).
- Plugin 1f8b72d: each page of a writable span gets a `lock orb $0` before a writable host import (no byte changes;
  297 of 297 resident after). `surface prefault: N writable host imports ...` in the log; NVMTL_PREFAULT=0 skips it.
  Kernel side proposed to the main session: fault pages in for write before the read-only retry, count retries in a sysctl.
- Installed 12:47: plugin 1f8b72d, sha256 796125b9 (backup nvmtl-plugin-20261108T054744Z = 8201eaaa), sbxmap stale 0.
  TextEdit loads it (`surface prefault: 1 writable host imports faulted in ... (1052 KB)`); WindowServer at the next boot.
  Watch: no gfxhub PERMISSION_FAULTS from Live Text (mediaanalysisd) on screenshots.

### Step132: userptr write pin falls back to read-only on a fresh IOSurface (GPU fault 12:42, building)

- 12:42:49 GPU fault PERMISSION_FAULTS 0x5 (TCP write) from mediaanalysisd (thread 0x13e39), gfx ring timeout, soft recover after 3 s; WindowServer "slowest submit 3008 ms" (screen stuck 3 s). Found by the edge-video session.
- The surface was a 420f IOSurface mediaanalysisd had just made, mapped RW, 0/297 pages resident. The writable pin failed with -EFAULT, Step96's read-only retry then pinned it RO ("userptr_ro_retry -> 0"; the log budget was already spent at boot), and the GPU wrote into it. Plugin dd43056's check only catches r-- mappings, so it let this one through.
- Fix in NMXGPU (fork, out-12): `nmx_xnu_user_wire` retries a failed writable `prepare()` once after a read-only wire faults the range in; the RO fallback only follows a second failure. No new kernel imports (no vm_fault: Step128 rule).
- New counters: `debug.nmx_pin_write_fail`, `nmx_pin_write_retry_ok`, `nmx_pin_ro_retry`, `nmx_pin_last_rc`, `nmx_pin_last_rc2` (IOReturn), plus a budgeted `NMX pin: write wire ... failed` log line.
- Userspace signal: on the RO fallback `args->flags` comes back with AMDGPU_GEM_USERPTR_READONLY (IOWR ioctl); a writer should refuse that import. The edge session's plugin 1f8b72d also prefaults writes before host-import.
- Step132 installed 12:55: NMXGPU out-12 (fork 1c75638, UUID 97A9E93B) with `scripts/macos-install-step130.sh`, AuxKC relinked + checked, rc 0. Same reboot as the edge plugin 1f8b72d. After boot: read `sysctl debug | grep nmx_pin`.

### Step132 boot (2026-11-08 14:23:43; owner restart, a shutdown stall report at 12:55)

- NMXGPU 97A9E93B + StrixS0ix 0.1.14 loaded; edge plugin 1f8b72d (write prefault) in WS. 11 flip imports, `debug.nmx_timeouts` 0, brightness Writes 253 / Failures 0, `NMXPagingWake` Yes.
- `debug.nmx_pin_write_fail` 328 = `nmx_pin_ro_retry` 328, `nmx_pin_write_retry_ok` 0, `last_rc` = `last_rc2` = 0x2 (KERN_PROTECTION_FAILURE). Every one is WindowServer (pid 207, thread 0x3c4) importing client surfaces mapped r--: the Step96 case, a read-only pin is right there and no GPU writes it.
- So the read fault-in retry never helps a protection failure; it only costs one extra wire per WS import. Next NMXGPU build: skip the retry when rc is KERN_PROTECTION_FAILURE, keep it for other codes.
- The 12:42-style fault (fresh RW IOSurface in mediaanalysisd) has not come back yet. If it does, `nmx_pin_last_rc` from a non-WS process says which code it was.
- Edge session (14:3x): WS write wires fail 100 % (1028/1028, rc 0x2) even after its plugin prefaulted the spans (resident, CPU-writable). Correction to the log text: "after a read fault-in failed 0x2" is the second *write* prepare; the read-only wire works. So xnu refuses a writable UPL on these IOSurface entries while the CPU can write them. Asked the edge session for mach_vm_region_recurse info (protection/max_protection/share_mode/user_tag/object, purgeable state) on failing spans.
- Step132b (building as out-13, not installed): no fault-in retry on KERN_PROTECTION_FAILURE; failures outside WindowServer kept apart: `debug.nmx_pin_other_fail`, `nmx_pin_other_rc`, `nmx_pin_other_name`; the log line names the process (WS budget 4, others 24). Uses only proc_name/proc_pid/current_proc, already imported.

## Trace part 22: plugin 1f8b72d (write prefault) live, boot 14:23 (2026-11-08)

- Plugin 796125b9 (1f8b72d) loaded in WindowServer (pid 207). It logged `surface prefault: 1 writable host imports faulted in for writing first (20340 KB this one)`, so the writable path runs before the import.
- After about 12 min: `debug.nmx_timeouts` 0. No `PERMISSION_FAULTS`, no `ring gfx timeout`, no `slowest submit` this boot. The last fault is still 12:42, from the previous boot (mediaanalysisd, non-resident pages; the prefault is the fix for that).
- `nmx_pin_write_fail` 1028 = `nmx_pin_ro_retry` 1028, all from WS thread 0x3c4 with rc 0x2. That is the r-- client-surface case covered in the Step132 boot section above, not a wire bug. The plugin skips writable imports on r-- spans (dd43056), so those surfaces are never written by the GPU.
- WS CPU 36 % at 12 min uptime, idle desktop. Video measurement with the local clip still to do on this boot.
- Undo plugin: `scripts/macos-nvmtl-plugin-install.sh --undo` (back to 8201eaaa, 5405e50), then `scripts/macos-install-strixsbxmap.sh --refresh`.
- Correction (edge session): the 1028 WS failures are client surfaces mapped r-- (Step96 case); the RO pin is right, no wire bug. The 20340 KB prefault was a different, writable import. Region-info request withdrawn. out-13 = Step132b as written above (no retry on rc 2, non-WS failures counted apart), installs with the next reboot batch.

## Trace part 22b: YouTube 1080p60 in Chrome, boot 14:23 (2026-11-08)

Network is native Wi-Fi (en1); HoRNDIS is not loaded, so YouTube is safe to test on this boot. Scratch Chrome (`--user-data-dir` in the scratchpad), video LXb3EKWsInQ forced to hd1080, 40 s probe (requestVideoFrameCallback, rAF, getVideoPlaybackQuality), `top` sampled every 5 s.

| Metric | Value |
|---|---|
| Stream | VP9 profile 0 8-bit (itag 303), 1920x1080@60 |
| Decode | VTDecoderXPCService 6-8 % CPU (VCNDec on VCN) |
| Frames shown (rVFC) | 58.6 fps |
| rAF | 117 fps |
| Dropped | 32 / 2396 (1.3 %) |
| Gaps > 50 ms | 3, max 117 ms |
| WindowServer CPU | 82-91 %, avg ~86 % |
| Google Chrome (all processes, summed by top name) | ~41 % |

Decode is no longer the cost: VCN handles VP9 and frame pacing is close to 60 fps. The remaining cost is WindowServer compositing at about 86 % CPU while a 1080p60 video plays (idle desktop: 36 %). That matches part 21's diffuse SkyLight/CoreAnimation profile; next step is a WS spindump during this exact playback to split the 86 %.
- Step132b installed 14:4x: NMXGPU out-13 (fork a3e5484, UUID C112960E, same 579 imports as out-12), AuxKC relinked + checked, rc 0. Loads at the next reboot (no reboot asked for it alone). After boot: `sysctl debug | grep nmx_pin_other`.

### Step133: one page-registry spin lock was ~4 s of CPU per 10 s of YouTube (building)

- Edge session spindump, 10 s of YouTube 1080p60 VP9 in Chrome (WS ~86 % CPU): samples running inside IOSimpleLockLock: WS 541 (~1.8 s of WS's 11.2 s), Claude Helper 315, Chrome 239, kernel_task 52, VTDecoder 26; ~4 s CPU spinning in total.
- All on `pg_lock` in xkpi `bsdcompat/src/nmx_page.c`, taken once per page by every userptr pin (`nmx_phys_to_page`, pin-list push in `nmx_user_pages_pin`) and every unpin (`vm_page_unwire_noq` -> `page_pop_pin`, from `amdgpu_ttm_tt_unpopulate` on GEM close), plus TTM pool alloc/free. One lock for every GPU process, a 1266-page surface = thousands of acquisitions per frame.
- Fix (fork, out-14): the page registry and the per-page pin lists move to 256 stripe locks keyed by the page's hash bucket; `pg_lock` keeps only the chunk/free list and live counts. No path nests two of these locks or takes a stripe under `pg_lock`.
- Still open on the plugin side (edge session): WS's `nvmtl.surface-keep.release` thread spends 338/413 samples in GEM close, so some BO is still made and destroyed every frame.

## Trace part 22c: where WindowServer's 86 % goes during YouTube 1080p60 (2026-11-08 14:40)

System-wide spindump, 10 s, 3020 samples (~3.3 ms each), Chrome playing VP9 1080p60 (part 22b). WindowServer used 11.2 s CPU in 10 s.

| WS thread | CPU in 10 s |
|---|---|
| main (ws_main_thread) | 8.0 s |
| nvmtl.surface-keep.release | 1.24 s |
| CoreAnimation render-server | 0.63 s |
| nvmtl.execution | 0.47 s |

**Main thread:** 1378 of 3020 samples (46 %) are in `-[NVMTLDevice newTextureWithDescriptor:iosurface:plane:]`:
- `nvmtl_vk_buffer_import_host` (userptr pin + GPU map): 879.
- `nvmtl_prefault_write`: 422. These are real page faults (`user_trap` → `vm_fault_enter` → `pmap_enter_options`) that the kernel wire would otherwise take, so the prefault moves the cost but does not add much.
- Plugin log: about 1000 surface imports per 30 s, mostly small writable surfaces (128 KB) plus the decoder's 420v planes (read-only imports).

**Release thread:** 338 of 413 samples are the GEM close ioctl (`drmCloseBufferHandle`). The plugin frees as many userptr BOs as it imports.

**Kernel hot spot: one global IOSimpleLock in NMXGPU's linuxkpi page shim.** Samples spinning (`IOSimpleLockLock`, state running), by process: WindowServer 541 (~1.8 s), Claude Helper 315, Chrome 239, kernel_task 52, VTDecoderXPCService 26. That is about 4 s of CPU across the system spent spinning in 10 s. Callers, all per page:

| Caller | Path | Samples (WS / Claude / Chrome) |
|---|---|---|
| `vm_page_unwire_noq` | `linux_release_pages` ← `amdgpu_ttm_tt_unpopulate` (unpin on close) | 211 / 111 / 32 |
| `nmx_user_pages_pin` | ← `nmx_userptr_pin` | 150 / 87 / 17 |
| `nmx_phys_to_page` | ← `nmx_user_pages_pin` ← `lkpi_get_user_pages` | 130 / 102 / 209 |
| `vm_page_alloc_noobj` | ← `ttm_pool_alloc` | 44 WS |
| `vm_page_free` | ← `ttm_pool_free_range` | 49 kernel_task |

**Two fixes, in order of size:**
1. Kernel (NMXGPU, main session): take the page lock once per range instead of once per page, or split it into buckets or make the phys→page lookup lock-free. This helps every GPU process, not just WS.
2. Plugin: stop the import/free churn. Keep entries expire after 3 s idle, and most misses are "expired", so small writable surfaces come back and are pinned again. Next build should log which surfaces are re-imported (size, owner, age) before changing keep times.
- Step133 installed 14:5x: NMXGPU out-14 (fork fde4618, UUID FE95BAD4, includes Step132b; 579 imports), AuxKC relinked + checked, rc 0. Next reboot. Edge plugin 5786ad9 (keep 30 s) built, waits for the owner's OK to go in the same reboot.
- Edge plugin 5786ad9 (NVMTL_KEEP_MS 30 s, sha f45f15bc) installed 14:5x at the owner's OK, StrixSbxMap --refresh rc 0 (ESP pins + live sysctl). WS loads it with NMXGPU out-14 at the next reboot. Undo: `sudo scripts/macos-nvmtl-plugin-install.sh --undo` (back to 796125b9) + --refresh.
- Correction: the edge session installed the same plugin 23 s earlier (backup 20261108T074851Z = 796125b9); this session's second install left backup 20261108T074914Z = a313ed1b (the new plugin itself), so plain --undo would be a no-op. Undo instead: `sudo scripts/macos-nvmtl-plugin-install.sh /Library/NullMoth/nvmtl-plugin-20261108T074851Z/NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver` then `sudo scripts/macos-install-strixsbxmap.sh --refresh`.

### Step133 boot (2026-11-08 14:51:56; shutdown stall report 14:50:42 again on the way down)

- NMXGPU FE95BAD4 (out-14: stripe locks + Step132b), StrixS0ix 0.1.14 loaded; plugin keep30 (a313ed1b) in WS. 11 flip imports, brightness Writes 252 / Failures 0, `NMXPagingWake` Yes. No panic.
- `nmx_pin_write_fail` 109 = `ro_retry` 109, all WindowServer rc 2 (r-- client surfaces), `nmx_pin_other_fail` 0, `last_rc2` 0 (no pointless retries any more).
- `nmx_timeouts` 1: `ring sdma0 timeout, signaled seq=31, emitted seq=31` at 14:52:06 (boot + 10 s), ring reset success. Signaled == emitted: the fence had completed and the timeout fired anyway (a late/missed fence interrupt at boot, not a hung engine). First sdma0 one today (earlier ones were vcn_unified_0, signaled = emitted - 1). Watch whether it repeats on the next boots.
- CPU at idle 4 min after boot: WS 49 %, Claude Helper 63 %. The YouTube spindump re-run (edge session) gives the before/after for the lock + keep30 change.

## Trace part 23: YouTube 1080p60 after out-14 (stripe locks) + plugin keep30, boot 14:51 (2026-11-08)

Same test as parts 22b/22c: scratch Chrome, video LXb3EKWsInQ at hd1080 (VP9 itag 303), 40 s probe, then a 10 s system-wide spindump.

| Metric | Before (14:23 boot) | After (14:51 boot) |
|---|---|---|
| Frames shown (rVFC) | 58.6 fps | 58.9 fps |
| Dropped | 32 / 2396 (1.3 %) | 26 / 2397 (1.1 %) |
| Gaps > 50 ms (max) | 3 (117 ms) | 1 (83 ms) |
| WindowServer CPU (top) | ~86 % | ~81 % |
| WS CPU in the 10 s spindump | 11.2 s | 9.3 s |
| `IOSimpleLockLock` samples, whole system | ~1230 (WS 541) | 38 (WS 9) |
| WS main: `newTextureWithDescriptor:iosurface:plane:` | 1378 | 797 |
| …of which `nvmtl_vk_buffer_import_host` | 879 | 226 |
| …of which `nvmtl_prefault_write` | 422 | 535 |
| `nvmtl.surface-keep.release` CPU | 1.24 s (338 GEM close) | 0.41 s (93 GEM close) |

- **out-14 removed the lock contention:** the pin/unpin spin is gone in every process (WS, Chrome, Claude, VTDecoder).
- **Keep30 moved the misses.** Plugin reports per 30 s: hits 3286, misses 1012 (new surface 102, expired 8, **idle cap 902**), 602 entries, idle 503 MB.
  - With a 30 s window the working set is larger than `NVMTL_KEEP_IDLE_MAX` (512), so the LRU cap now drops entries that come back.
  - The sweep also grew to 849 µs average (2.5 ms max) per import, because it walks every entry.
- **The biggest single plugin cost left is the write prefault** (18 % of the WS main thread). It is real page faults on the WS mapping of each newly imported surface, so it only drops with fewer re-imports.
- **Next (plugin):**
  1. Log what the cap drops (size, format) to see why WS has 600+ distinct surfaces during one video.
  2. Then either raise the cap, or key the cap by bytes rather than count.
  3. Make the sweep incremental, so it stops walking all entries on every import.
- Step133 measured (edge session, trace part 23 4e4f4e7, YouTube 1080p60 10 s): IOSimpleLockLock samples system-wide ~1230 -> 38 (WS 541 -> 9); WS CPU 11.2 -> 9.3 s per 10 s; surface-keep.release 1.24 -> 0.41 s (GEM close 338 -> 93); video 58.9 fps, 1.1 % dropped. Stripe locks: VERIFIED. Rest is plugin-side (prefault faults, keep cap 512 entries).
- Pending for the next reboot: edge plugin cb1a5e6 (idle cap 2048 entries, sweep at most every 100 ms, idle-cap miss log), installed by the edge session at the owner's OK, signed f3068ae2; --undo goes back to keep30 a313ed1b (backup 20261108T080310Z).

### Boot 2026-11-08 15:04 (out-14 + plugin cb1a5e6), Step134 building

- Live: NMXGPU FE95BAD4, StrixS0ix 0.1.14, plugin f3068ae2 (cb1a5e6). No panic. Brightness Writes 256 / Failures 0. `nmx_pin_ro_retry` 950 (all WS), `nmx_pin_other_fail` 0.
- 15:17:30 gfxhub PERMISSION_FAULTS 0x5, TCP write (RW 1), vmid 5, pasid 32795, xkpi tid 29052, VA 0x80010fc40000; gfx "timeout, but soft recovered". No non-WS read-only pin happened this boot, so this write hit either a WS read-only client import or another read-only BO. Finder / QuickLookUIService were busy at the time. The fault print said "in process  pid 29052": xkpi never filled `td_name`, so amdgpu's task_info comm was empty.
- 15:18:54 `vcn_unified_0 timeout, signaled 508, emitted 509` (third VCN timeout today: 10:02, 12:26, 15:18).
- Shutdown stall reports at 12:55, 14:50, 15:04: every shutdown since StrixS0ix 0.1.14 loaded. Spindump of 15:04 shows nothing busy (0.57 s CPU), NMXGPU threads waiting, idle CPUs in the StrixS0ix idle hook. Passed to the cpu-thermal session.
- Step134 (fork, building out-15): `td_name` is set from the process record's `p_comm` when a thread record is made or recycled, so amdgpu fault prints name the process.
- Correction (cpu-thermal session): shutdown stalls are older than StrixS0ix 0.1.14 (11 reports since 11-06, today also 10:02 and 11:46). StrixS0ix+20600 is the cli after hlt in s0ixMachineIdle = idle CPUs; shutdown/offline goes through pmCPUHalt, not the idle hook. The stall is userspace waiting for processes to exit (caffeinate started at boot, crashpad handlers, securityd, duetexpertd). Not a kernel issue.
- Step134 installed 16:4x: NMXGPU out-15 (fork c811a92, UUID 5E71137B, 579 imports; = out-14 + td_name), AuxKC relinked + checked. Next reboot.

## Side note: 15:17 gfxhub fault and VCN AV1 timeouts (2026-11-08, boot 15:04)

- **VCN:** all three `vcn_unified_0 timeout` events today came during AV1 1920x1080 sessions in VTDecoderXPCService (VCNDec): sessions started at 10:00:32, 12:23:45 and 15:18:03, timeouts at 10:02:05, 12:26:11 and 15:18:54. No VP9 session timed out (12:08, 12:29, 14:37, 14:57). This is an AV1 decode hang on VCN, in VCNDec's scope; to be traced.
- **15:17:30 fault:** `PERMISSION_FAULTS 0x5`, TCP write, vmid 5. About 150 ms earlier QuickLookUIService (CoreImage + Espresso) submitted 128 parts, after writing an IOSurface storage twin (1088x1376, VkFormat 98). It is the main suspect; the xkpi tid could not be mapped to a process.
- **Plugin read-only handling:** the plugin never reuses an RO host import for a write request, and it refuses write imports on spans that are not writable. Gap: when the CPU mapping is writable but the kernel write wire fails, the kernel silently pins RO and the plugin cannot tell (RADV never passes `AMDGPU_GEM_USERPTR_READONLY`). Asked main for an RO-fallback ring that is matched against fault addresses.
- Edge session: the 15:18 VCN timeout and the 10:02 / 12:26 ones were all inside AV1 1080p sessions (VP9 sessions never timed out): an AV1-on-VCN bug in VCNDec, owned by the edge session. For 15:17 it saw QuickLookUIService (CoreImage/Espresso, "storage twin ... written through an optimal-tiled storage copy", 128 parts submitted 150 ms before). With `nmx_pin_other_fail` 0 that write was not into a Step96 read-only userptr.
- Step135 installed 16:4x: NMXGPU out-16 (fork ffee0b1, UUID 7103416C, 579 imports; = out-15 + romap). New patches `amdgpu-romap-gem.patch` / `amdgpu-romap-gmc11.patch`: GEM_VA MAP/REPLACE records ranges mapped without write (kind 1 read-only userptr, kind 2 no AMDGPU_VM_PAGE_WRITEABLE) per pasid with comm/pid in a 1024-entry ring; UNMAP/CLEAR drop them; a gmc11 page fault prints "NMX: address is inside <kind> map #n [start,end) by <proc> pid N" or "in no recorded read-only mapping". Next reboot.

## Trace part 24: VCN hang = power gating cycle, not AV1 content (2026-11-08 17:31)

**Stream captured.** A scratch browser played YouTube AV1 1080p60 (Big Buck Bunny, itag 399). The capture holds 11471 packets: profile 0, 8-bit, no film grain, 128x128 superblocks, some IntraBC frames. It is kept locally only, not in the repo: `~/develop/projects/radv-video/clips/yt-av1-399-bbb.ivf`.

| Run (`tools/890m/vcndec/build/vcndec_test`) | Result |
|---|---|
| Continuous, 3 loops (`-v -l 3`) | 34413 frames at 559 fps, no hang |
| 1.5 s pause after every 30 packets (`-v -p 30 1500 -n 3000`) | Hang after pause #35 (packets 1050-1053, right after the resume): `ring vcn_unified_0 timeout, signaled 49684 / emitted 49685`, MODE2 reset 17:31:26, VK_ERROR_DEVICE_LOST in the process |

The VCN idle timeout is about 1 s, so each pause powers VCN down and the next submit powers it up. The three real hangs today (10:02, 12:26, 15:18) also came in sessions with sparse submits (about 10 per second: paused, background or buffering video), not steady 60 fps decoding.

**Conclusion:** the hang is in VCN power gate / ungate in NMXGPU (`amdgpu_vcn_idle_work_handler`, `amdgpu_vcn_ring_begin_use`, VCN 4.0.5 DPG pause). It is not in VCNDec or the AV1 bitstream. Handed to the main session with the repro command. A/B next: VCN power gating off.

`vcndec_test` gained `-v` (one stderr line per packet before it is sent), `-n <packets>`, and `-p <burst> <ms>` (pause after every burst).

### Step136: VCN hang after a power-gate cycle (out-16 live since 17:33, out-17 building)

- Edge session repro (trace part 24, 2cca12b): the offline AV1 1080p60 clip decodes 34,413 frames back-to-back with no hang; with a 1.5 s pause every 30 packets (VCN idle > 1 s, so it gates and ungates) it hangs at pause 35: `vcn_unified_0 timeout, signaled 49684 / emitted 49685`, MODE2 reset 17:31:26, VK_ERROR_DEVICE_LOST. The three real hangs today were low-rate sessions (paused or background tabs). Clip (YouTube content, not committed, gitignored) at `tools/890m/vcndec/clips/run3_1920x1080.ivf` and `~/develop/projects/radv-video/clips/yt-av1-399-bbb.ivf`; repro `tools/890m/vcndec/build/vcndec_test -v -p 30 1500 -n 3000 <clip>` (one GPU reset when it hangs).
- Not a workqueue race: xkpi `cancel_delayed_work_sync` drains a running idle handler (taskqueue_cancel EBUSY -> taskqueue_drain).
- Missing upstream fix "drm/amdgpu: read back register after written for VCN v4.0.5" (VCN 4.0.5 with doorbells can miss the WPTR after starting from idle). New patch `amdgpu-vcn405-readback.patch`: RREG32 regUVD_STATUS at the end of `vcn_v4_0_5_start_dpg_mode`, each instance of `vcn_v4_0_5_start`, and `vcn_v4_0_5_stop_dpg_mode`. Building as out-17 (= out-16 + this); if the repro still hangs, the next test is an A/B with VCN power gating off.
- Boot 17:33 (out-16 7103416C): no panic, `nmx_timeouts` 0, 21 WS read-only pins, 0 outside WS, brightness OK.
- 17:33 restart (owner did not start it): no panic report, no shutdown/logout sequence; the unified log just stops at 17:33:22.57 mid normal activity (Wi-Fi, mdworker, tcp). DumpPanic: "previous shutdown cause 5" (not trustworthy on this machine). That is a hard reset / hang with no panic, 1 min 54 s after the VCN repro's MODE2 GPU reset at 17:31:28 ("GPU reset(3) succeeded"). Earlier VCN resets today (10:02, 12:26, 15:18) did not take the machine down, so the link is likely but not proven. Until out-17 is in, the vcndec_test pause repro should not be run again (each run costs a GPU reset).
- Step136 installed 17:4x: NMXGPU out-17 (fork 6adeee4, UUID 0FE4163C, 579 imports; = out-16 + VCN 4.0.5 read-back). Next reboot, then the edge session reruns the pause repro.
- Pending for the next reboot with out-17: edge plugin 5ba6363 (tiles <= 2 MB kept 120 s, idle x bytes eviction cap, other-key miss log; for the ~7 % WS core on Electron tiles), installed by the edge session at the owner's OK, signed 53b67f84; --undo goes back to cb1a5e6 (backup 20261108T114130Z).

## Trace part 25: VCN power-gate hang fixed by out-17 (2026-11-08 20:33, boot 20:26)

NMXGPU out-17 (0FE4163C, Step136) adds the upstream "read back register after written for VCN v4.0.5" fix: one `RREG32 regUVD_STATUS` at the end of `start_dpg_mode`, `start` (per instance) and `stop_dpg_mode`.

Same repro as part 24, run once: `vcndec_test -v -p 30 1500 -n 3000` on the same clip (YouTube AV1 1080p60, `~/develop/projects/radv-video/clips/yt-av1-399-bbb.ivf`).

| Kernel | Result |
|---|---|
| out-16 (17:31) | hang after pause 35, `vcn_unified_0 timeout` signaled = emitted - 1, MODE2 reset (machine hard-reset ~2 min later) |
| out-17 (20:33) | 3000/3000 frames, 100 pause/resume cycles, rc 0, no NMXGPU log lines, `debug.nmx_timeouts` 0 |

The kernel does not log gate/ungate, so the number of real power-gate cycles is not counted. The pause pattern is identical (1.5 s > the 1 s VCN idle timeout). Pending: watch real video use (paused or background tabs) for `vcn_unified_0 timeout` over the next sessions.

### 2026-11-08 19:04 hang (out-16 boot, no panic)

- Owner confirms the machine froze; the log just stops at 19:04:03.5. There is no .panic and no WindowServer .ips. SMC cause 5 is meaningless here, because VirtualSMC reports 5 on every boot.
- Sequence of events:
  - 19:03:34.01: the AC adapter was unplugged (PMRD ac 0, pmset "Using Batt").
  - RogControl `powerChanged()` then applied the battery set: firmware profile silent (2), with battery limits SPL 20 / SPPT 25 / FPPT 35.
  - 19:03:36.03: NMXAccel "flip did not latch within 50 ms", so flip was turned off for the rest of the boot.
  - 19:03:36.71: beam copy took 132 ms, LAPPED 3 times in a row.
  - After that, no NMXGPU timeout, reset or fault was logged. 27 s later the system froze silently.
- Earlier AC to battery switches today (12:41, 16:27) did not trip flip or hang, so the trigger is a candidate, not proven.
- A drop of only 4 % battery between 19:04 and 20:26 means the machine was off most of that time, not hung at full power.
- 15:18:55 (15:04 boot) was a different event: a gfx ring timeout, then MODE2 reset.
- Next:
  - A/B on AC: switch RogControl Silent <-> Performance a few times and watch for flip-latch misses or stalls.
  - If it reproduces, out-18 logs SMU limit/clock changes around the flip.

### 2026-11-08 20:33 VCN repro on out-17 (Step136): PASS

- Command: `vcndec_test -v -p 30 1500 -n 3000`, using the same clip as the out-16 run (yt-av1-399-bbb).
- Run once, 20:33:23 to 20:36:03.
- Result: 3000/3000 frames, all 100 pauses of 1.5 s done, rc 0.
  - For comparison, out-16 hung at pause 35 (17:31). Each 1.5 s pause is longer than VCN_IDLE_TIMEOUT (1 s), so every pause lets the power gate kick in.
- NMXGPU logged no timeout, reset or ringdump in that window, and debug.nmx_timeouts is still 0.
- Conclusion: the VCN 4.0.5 register read-back fixes the hang after power-gate idle. out-18 does not need the vcn_pg_lock / PG-off A/B.
- One limitation: the kernel does not log gate/ungate, so the number of actual gate cycles is inferred from the pause timing, not counted.

### 2026-11-08 20:41 A/B: firmware profile Silent <-> Performance on AC (out-17)

- The firmware profile was switched with a small AsusWmi client (selector 1, what=1; same path as RogControl), 4 rounds of 2 -> 0, 10 s apart, then 60 s of watching.
- Result: no flip-latch miss, no LAPPED copy, no NMXGPU timeout/reset. nmxaccel_flip_tripped 0, nmx_timeouts 0.
- The profile switch alone does not reproduce the 19:03 stall.
- What is left is the real AC -> DC transition, i.e. what the firmware/SMU does on unplug beyond the profile. Test that only with the owner present.

### 2026-11-08 20:52 boot: Step137 (out-18 194BFE13 + plugin a95189e) live

- Loaded:
  - NMXGPU 194BFE13
  - RyzenHV 0.7.15
  - `-FIOff` (ForgedInvariant loaded but disabled)
  - StrixS0ix 0.1.14
- Plugin on disk: 2fc47b9a.
- No panic. The only report is a shutdown_stall at 20:52:30, the known userspace wait.
- After 4 min: nmx_timeouts 0, flip_tripped 0, pin_ro_retry 165 (WS r-- imports, expected), pin_other_fail 0.
- TSC is in sync on 24 threads. bluetoothd is up with no restarts.
- Bug: the Step137 `debug.nmx_surf_*` counters are declared but never passed to `sysctl_register_oid`, so they are invisible. Whether the surface path pins anything cannot be read on this boot.
  - Fixed in Step137b (fork f31cedf), building as out-19. It installs with the next batch.

## Trace part 26: YouTube 1080p60 lag on boot 20:52 (Step137 live) is memory pressure plus an NMXGPU page-record leak (2026-11-08 21:20)

Boot 20:52: NMXGPU out-18 (194BFE13), plugin a95189e (5FC87442). Normal desktop load: Docker (hyperkit, 8 GB VM), Claude, and another session's clang build. The owner's point stands: this load must not make video lag on an HX 370 with 32 GB of RAM.

**Step137 in WS (idle):**
- The plugin logs `surface hint: on` and never logs `refused`.
- In a 6 s WS spindump with no video, the import path is almost gone: `radv_bo_from_ptr` 2 samples, no prefault.
- The kernel `nmx_surf_*` counters are still invisible (out-19).

**YouTube LXb3EKWsInQ at hd1080 (VP9 itag 303), scratch Chrome, 40 s probe:**

| Metric | Part 23 (boot 14:51) | Boot 20:52 |
|---|---|---|
| Frames shown (rVFC) | 58.9 fps | 33.3 fps |
| Dropped | 26 / 2397 | 280 / 1507 |
| Gaps > 50 ms (max) | 1 (83 ms) | 91 (3233 ms) |
| rAF | ~117 | 65 |
| WindowServer (top) | ~81 % | 47-94 % |

**System-wide 10 s spindump during playback:**
- kernel_task used 21.7 s of CPU: VM_compressor 6.7 + 2.6 s, VM_pageout_scan 5.2 s, VM_cswap_trigger 2.2 s. The machine is thrashing.
- `vm_stat`: 47 k free pages, 2.79 M pages in the compressor, swap 0.

**Wired memory (`zprint`): 20.0 GB of 32 GB.**

| Owner | Wired |
|---|---|
| com.overlorddev.RyzenHV | 8.42 GB (Docker hyperkit `-m 8192M`, the guest RAM wired in full) |
| com.nullmoth.NMXGPU | 5.80 GB |
| zones | 2.81 GB, of which `kalloc.type.var4.256` 3.24 M elements (~810 MB, growing during playback) and `kalloc.type.var4.96` 4.5 M (~420 MB) |
| PTE / PMAP | 590 / 317 MB |
| IOSurface | 314 MB |

**NMXGPU page-record leak (`bsdcompat/src/nmx_page.c`):**
- Every user page pinned for a userptr BO (`nmx_user_pages_pin`) gets a `BK_FICTITIOUS` record from `nmx_phys_to_page()`: a backing plus a vm_page (~256 B), and a registry entry.
- Nothing removes these records. `vm_page_free()` returns early for `BK_FICTITIOUS`, and no path unregisters them.
- The registry (65536 buckets) therefore grows toward one record per physical page ever pinned (up to 8.4 M on 32 GB). Lookups get slower with uptime.
- In the playback spindump, each WS surface import (`nvmtl_vk_buffer_import_host`, 96 samples) spends 87 samples in `amdgpu_gem_userptr_ioctl` → `nmx_user_pages_pin`. 73 of those are in `nmx_phys_to_page+83`, the `reg_find_locked` chain walk.

**Next:**
- Kernel (main session):
  - Free a fictitious user-page record when its last pin is dropped, or keep user pins out of the registry.
  - Find out what the 5.8 GB on the NMXGPU tag is.
- Owner's call: Docker's VM memory. RyzenHV wires all of it, so 8 GB is gone for macOS whenever Docker runs.
- Then repeat this probe under the same load.

### 2026-11-08 21:40 Step138: page-record leak for pinned user pages (found by edge-video-lag)

- Symptom on boot 20:52:
  - YouTube 1080p60 runs at 33 fps with 280/1507 frames dropped.
  - kernel_task uses 21.7 s CPU per 10 s, 16.7 s of it VM compressor/pageout: the machine is thrashing.
  - Wired memory is 20 GB of 32 GB:
    - RyzenHV 8.4 GB: Docker VM 8 GB, wired in full.
    - NMXGPU tag 5.8 GB.
    - Zones 2.8 GB. kalloc var4.256 holds ~3.2 M elements and grows during video.
- Cause: `nmx_phys_to_page` made a permanent BK_FICTITIOUS record (backing + vm_page + reg_entry) for every user page ever pinned. `vm_page_free` returned early for those and nothing unregistered them.
  - The registry grows with uptime.
  - WindowServer imports spend 73 of 87 samples walking the hash chains (`reg_find_locked`).
- Fix, Step138 (fork a1c786c):
  - Records for user pages are BK_USER. They are freed when the last reference goes and no pin is left.
  - If any other path (PHYS_TO_VM_PAGE / virt_to_page) reaches the record, it turns permanent, as before.
  - The `nmx_user_pages_pin` failure path no longer pops pins of other requests.
  - New counters: `debug.nmx_userrec_{live,made,freed,kept}`.
- Step138b (c9d7c9f): `debug.nmx_pages_live` and `debug.nmx_userwire_{count,pages}`, to split the 5.8 GB NMXGPU tag between GTT/system pages and userptr wirings.
- Build: out-20 (1B44E2DB, from aa92afc: Step137b + 138 + 138b + 138c; review fixes from edge-video-lag). Checks: 0 weak, 581 imports, NMXOwnsDisplay, counters present. Not installed.
- Leak rate on out-18 (cpu-thermal zprint, 21:21 -> 21:43, same boot):
  - kalloc var4.256 went 3.24 M -> 3.44 M (+~200k records, +~50 MB in 22 min, ~2.3 MB/min). That fits the page-record leak.
  - var4.96 went 4.5 M -> 4.09 M. It shrinks, so it is not this leak.
  - NMXGPU tag went 5.80 -> 4.89 GB: about 0.9 GB of it is dynamic.
  - Check after out-20: var4.256 flat, `nmx_userrec_live` tracks pinned pages, `nmx_userrec_kept` ~0.
- 2026-11-08 ~21:55: out-20 (1B44E2DB) installed with the owner's OK (step130 script: AuxKC relinked, probes ok, kccheck ok). It loads at the next reboot.
  - Backup of out-18 is in /Library/NullMoth/step130-bk-*.
  - Undo: `scripts/macos-install-step130.sh --undo`.
  - The BT LE advertising loop was handed to the "Fix bluetoothd crash loop" session.

### 2026-11-08 21:51 boot: out-20 (1B44E2DB) + RyzenHV 0.7.17 + BtLeDlFix 1.3.0 live

- No panic. nmx_timeouts 0, flip on, pin_other_fail 0.
- Step138 works at +2 min:
  - userrec: made 374748, freed 136943, live 237805 (~0.9 GB of pinned user pages), **kept 0**. No other path turns records permanent.
- Step137 verified:
  - nmx_surf_hint 312, nmx_surf_wire 312, all miss/bad_page/no_surf/short/prep_fail 0.
  - Every hinted import pins the IOSurface's own memory.
- What NMXGPU holds wired:
  - pages_live 364748: ~1.39 GB of port page records (GTT/system).
  - userwire 807 descriptors, 349096 pages (~1.33 GB) of user/IOSurface wirings.
  - The 4.9-5.8 GB seen on out-18 needs re-measuring under daily load on this boot.
- Bluetooth: 0 "STATUS 718" lines in 2 min, bluetoothd 1.9 % CPU. The LE advertising loop is fixed by BtLeDlFix 1.3.0 (masked patterns for 26.x).

## Trace part 27: YouTube 1080p60 on boot 21:51 (out-20, Step138 live); sandboxed Chrome GPU never gets the surface hint (2026-11-08 22:05)

Boot 21:51 runs NMXGPU out-20 (1B44E2DB), RyzenHV 0.7.17, BtLeDlFix 1.3.0, and plugin a95189e. Docker was not running during this test. The same probe as part 26 was used: scratch Chrome, video LXb3EKWsInQ at hd1080 (VP9 itag 303), 40 s.

| Metric | Boot 20:52 (part 26) | Boot 21:51 |
|---|---|---|
| Frames shown (rVFC) | 33.3 fps | 42.1 fps |
| Frames decoded in 40 s (`totalVideoFrames`) | 1507 | 1048 |
| Dropped | 280 | 8 |
| Gaps > 50 ms (max) | 91 (3233 ms) | 40 (525 ms) |
| rAF | 65 | 108 |
| WindowServer (top) | 47-94 % | 33-87 % |
| kernel_task VM_compressor + pageout, per 10 s | 16.7 s | 3.4 s |
| Wired before playback | 20 GB | 6.9 GB |

**Step138 page counters**, sampled every 5 s:
- Before playback: `userrec_live` 348 k, `userwire_pages` 535 k.
- Playback peak: 664 k and 999 k. That is 3.8 GB of user pages pinned, mostly WS and Chrome surface imports.
- 60 s after Chrome closed: back to 285 k and 418 k.
- `userrec_kept` stayed at 0 throughout. The leak is fixed.

**Video path: the Chrome GPU process imports every decoded frame through the per-page prefault.**
- In the 10 s system spindump, CrGpuMain used 3.1 s.
  - 229 / 999 samples are in `newTextureWithDescriptor:iosurface:plane:`.
  - 129 of them are in the userptr BO create.
  - 98 are in `nvmtl_prefault_write`.
- In the installed binary (5FC87442), that call site (`nvmtlNewSurfaceTexture+1636`, return 0x8104) is the full-span fallback. It runs only when `nvmtl_surface_hint` (not inlined) fails.
- Cause: the hint opens `/dev/dri/renderD128` with a plain `open()`, which the browser GPU sandbox refuses. RADV in the same process reaches the node through the drmx wrappers (NMXAccel NMDR connection), so its imports work, but the hint is off for that process.
- The kernel's `nmx_surf_hint` / `surf_wire` (3176 / 3176, 0 miss) therefore come from WindowServer only.

**Fix**, plugin branch `plugin/video-lag` 4e68b8b (built as UUID 2869ADAB, not installed):
- The hint now opens, sends and closes through `nvmtl_drmx_w_open/_ioctl/_close`.
- NMDR runs the ioctl from the caller's thread with no ioctl filter (`nmx_drm_uc.cpp` selIoctl → VNOP_IOCTL), so the kernel's per-task hint matches the caller's later userptr import.
- WindowServer is unchanged: the real `open()` succeeds there.

**Still open:**
- Only 1048 frames were decoded in 40 s (about 26 fps at the source), with 40 gaps. This is either network buffering or GPU-process stalls behind the per-frame prefault; the fix above has to be tested first to tell them apart.
- WS main thread: 4.9 s of CPU per 10 s. Its import share fell from 103 to 39 samples. That part belongs to main and cpu-thermal.

### 2026-11-08 22:20 video re-measure on boot 21:51 + plugin 9c6d1ed (video-lag hint fix merged)

- edge-video-lag (trace part 27, dc5924e) measured YouTube 1080p60 VP9 in Chrome with Docker off:
  - rVFC 42.1 fps (was 33.3), 8 dropped (was 280), max gap 525 ms (was 3233 ms).
  - kernel_task VM work 3.4 s per 10 s (was 16.7).
  - Step138 counters: live / userwire went 348k / 535k before -> 664k / 999k at peak -> 285k / 418k 60 s after Chrome closed; kept stayed 0.
  - Conclusion: the leak is fixed.
- Remaining video-path cost: the sandboxed Chrome GPU process could not open /dev/dri, so its IOSurface hint never ran. Each frame then took the full-span `nvmtl_prefault_write`: 98 of 999 CrGpuMain samples.
- Fix: plugin/video-lag 4e68b8b. The hint now goes through `nvmtl_drmx_w_*`, so it falls back to the NMDR user client, whose ioctls run on the caller's thread. WS is unchanged. Reviewed and merged into camera-copy-890m as 9c6d1ed.
- Built from 9c6d1ed: `nmx-plugin-camcopy/out/NVMTLDriver-9c6d1ed`, sha dcb03c9d, UUID 770FBF92. Not installed.
- After install, check:
  - Chrome GPU spindump: `nvmtl_prefault_write` under nvmtlNewSurfaceTexture should be ~0.
  - `nmx_surf_hint` should rise faster during playback.
- Next install batch, each only with the owner's OK:
  - this plugin
  - StrixS0ix 0.1.15 (A17EB334, version gate)
  - BtLeDlFix 1.4.0, which the BT session installs

## Trace part 27b: the "26 fps decode" was a YouTube pre-roll ad, not a stall (2026-11-08 22:08)

Boot 21:51, plugin a95189e (the 9c6d1ed hint fix is not installed). Docker hyperkit was running. Probe v2 logs one line per second: play rate (currentTime / wall time), decoded, dropped, rVFC callbacks, seconds buffered ahead, YouTube buffer health, and waiting/stalled events.

- **Play-now run** (as in part 27):
  - Seconds 1-25 play at rate 1.00 with 25 decoded, 25 rVFC and 0 dropped per second. The buffer drains from 21 s to 0.2 s and is never refilled. This is a 25 fps pre-roll ad, fully preloaded.
  - At second 26, `currentTime` jumps back and the frame counters reset: the main video starts.
  - From then on it runs at 60 decoded / 60 rVFC per second with 0 dropped.
  - Part 27's "1048 frames in 40 s" was the ad plus the switch, not a decode or GPU stall.
- **Prebuffered run** (main video paused until 16 s were buffered, then 40 s measured):
  - Rate 0.974 (the first second resumes from pause), 62.5 decoded/s, 57.6 rVFC/s.
  - 28 dropped, mostly in the first 5 s after resume; 0-1 per second after that.
  - Buffer stays 24-27 s ahead. 0 waiting, 0 stalled.
  - rVFC processingDuration averages 32 ms, max 154 ms.
- top during that run: WindowServer 21-65 %, kernel_task 17-37 %.

**Conclusion:** neither network buffering nor a GPU-process stall limits the decode rate. The VCNDec + Chrome path sustains 1080p60 under daily load (Docker running).

**Left:**
- The drop burst when play resumes.
- The per-frame import cost in Chrome's GPU process. Fix 9c6d1ed is merged and waits for the next batch; re-measure after it is live.
- Future probes skip ads: wait for the main video to start, i.e. when `currentTime` resets and the frame counters restart.

### 2026-11-08 22:12 install batch for the next boot (owner OK)
- Plugin 9c6d1ed (sha dcb03c9d, UUID 770FBF92; signed bundle binary e77766e8). Backup /Library/NullMoth/nvmtl-plugin-20261108T151155Z (was 2fc47b9a). StrixSbxMap pins refreshed on the ESP and live (routed=1, stale=0). Undo: `scripts/macos-nvmtl-plugin-install.sh --undo`, then `scripts/macos-install-strixsbxmap.sh --refresh`.
- StrixS0ix 0.1.15 (A17EB334), with the pmDispatch version check (property `S0ix,PMDispatchVersion`), is in the AuxKC. kccheck passed; NMXGPU is still out-20 1B44E2DB. Undo: `scripts/macos-install-s0ix-idle.sh --undo`.
- ItlXhciKick 5D179C74 (merge of thermal/xhcikick-idle 3fd2fb1 + b862dec: `itlkickidle` default 16; after 2 min NVRAM `itlz0` is written only when the health line changes, full counters in ioreg `itlz0`) is on the ESP. Backup: EFI/OC/Kexts-backup/ItlXhciKick.kext.20261108-221205 (BF038C9C).
- Already staged by other sessions: BtLeDlFix 1.4.0, and the native Wi-Fi ABI gate 206D41C8.
- Checks after boot:
  - ioreg `S0ix,PMDispatchVersion` reads 0x66 and the hook is installed.
  - ItlXhciKick stats show `/d` and IPIs go down.
  - The plugin logs `surface hint: on` in Chrome GPU.
  - `sysctl debug.btledlfix`.
  - `ioreg -l | grep itlmt-native-abi` reads "ok: 10 classes".
- Wi-Fi native 25F33563 (mt7925-macos dev/awdl dc0c88a: CCFaultReporter on its own idle work loop, plus the 206D41C8 ABI gate). It is on the ESP and replaces 206D41C8. Backup: EFI/OC/Kexts-backup/itlmt7925Native.kext.20261108-221302. Check after boot: the ctl:faultLoop=own trace, and CCFaultReporter wakes near 0.
- The plugin in the batch is now 9bfd0c5: cpu-thermal's fence pool, plus reading `debug.nmxaccel_fence_wait` at most once a second, on top of 9c6d1ed. Built by main: UUID E26F136E, sha c8670a0c, signed bundle binary ec1a057d. SbxMap pins refreshed (stale=0).
  - Backups:
    - /Library/NullMoth/nvmtl-plugin-20261108T151939Z = 9c6d1ed, so `--undo` goes back to 9c6d1ed.
    - /Library/NullMoth/nvmtl-plugin-20261108T151155Z = a95189e (2fc47b9a).
  - The env var `NVMTL_FENCE_POOL=0` turns the pool off.

### 2026-11-08 23:51 boot with the batch
- Loaded:
  - ItlXhciKick 5D179C74
  - StrixS0ix 0.1.15 A17EB334 (PMDispatchVersion = 102 = 0x66, HaltHook Yes)
  - itlmt7925Native 25F33563
  - BtLeDlFix 1.4.0 (`debug.btledlfix` adv=on)
  - NMXGPU out-20 1B44E2DB
  - StrixSbxMap
  - plugin 9bfd0c5 installed
- ItlXhciKick at 119 s: busy controllers c0/c2 were kicked 106912 times (1 ms), empty ones c1/c3 6682 times (≈16 ms). No misses.
- Wi-Fi is up on en1. `itlmt-native-abi` was not found in ioreg; I asked the Wi-Fi session to check.
- debug.nmx_surf_wire 605, userrec_kept 0, userrec_live 138763 at 3 min (the trend is tracked by cpu-thermal).
- There is a shutdown_stall report at 23:27 from the previous shutdown; not yet read.
- No crash reports since boot. WindowServer at 1.6 %.
- Post-boot verification tasks were sent to cpu-thermal, video-lag and Wi-Fi.

## Trace part 28: Chrome surface hint live (plugin 9bfd0c5); YouTube 1080p60 plays at 60 fps with 1 drop in 60 s (2026-11-09 00:05)

Boot 23:51: plugin 9bfd0c5 (UUID E26F136E) = the 9c6d1ed Chrome hint fix plus cpu-thermal's fence pool. NMXGPU is out-20. Docker hyperkit was running (14.3 s of CPU in the 10 s spindump). Measured with the new `tools/890m/yt-probe/probe.mjs`: scratch Chrome, pre-roll ad skipped (55 s), video LXb3EKWsInQ at hd1080 VP9, 60 s, with two pause/resume cycles of 3 s each.

**1. Hint in Chrome works.**
- The Chrome GPU process cannot write `/tmp/nvmtl.log` because of its sandbox, so the check uses the kernel counters.
- `debug.nmx_surf_hint` grows ~0.5/s at idle (WindowServer only) and ~27/s while Chrome plays: 1715 → 10304 between 23:57:28 and 00:03:01, when the clip ended.
- `surf_wire` = `surf_hint` throughout, with `surf_miss` 0.

**2. Playback**, from the per-second timeline:

| Metric | Part 27 (boot 21:51, hint off in Chrome) | Boot 23:51 |
|---|---|---|
| Decoded / rVFC in 60 s | ~60/s steady state | 3604 / 3599 |
| Dropped | 28 in 40 s (burst on resume) | 1 in 60 s |
| Drops in the 5 s after a resume | 6+ | 1 and 0 |
| waiting / stalled | 0 / 0 | 0 / 0 |
| rVFC processingDuration avg | 32 ms | 31.9 ms |

**Chrome GPU process (CrGpuMain), 10 s spindump:**

| Metric | Part 27 | Boot 23:51 |
|---|---|---|
| CPU | 3.12 s | 1.57 s |
| `newTextureWithDescriptor:iosurface:` samples | 229 | 49 |
| `nvmtl_prefault_write` samples | 98 | 0 |
| userptr import samples | 129 | 46 |
| GPU process total CPU | 4.7 s | 2.7 s |

**3. Fence pool.**
- No stall or corruption during playback. Two 1080p frames captured mid-play (t = 112 s and 117 s) are clean.
- `nmx_timeouts` 0. `nmxaccel_fence_timeouts` is 1, but its only log line is at 23:52:45 (`iop: fence: surface 0xe pending 3496, done 3490 after 100 ms - copied anyway`). That is one minute after boot, before any test. Reported to main and cpu-thermal for their side.

**Other numbers from the spindump:**
- kernel_task: VM_compressor 1.37 + 0.68 s, pageout_scan 1.26 s per 10 s.
- WindowServer: 6.2 s per 10 s.
- `userrec_kept` 0.

### 2026-11-09 00:10 NMXGPU out-21 built (not installed)
- From nmx-source-port 17a6b28 (Step139): `debug.nmx_pin_by_proc` counts user-page pin calls and pages per process name, to attribute the ~56k pages/s userrec churn seen on the 23:51 boot.
- The CS path does not re-pin (Step92 `if (0)`), so the churn comes from userptr BO create/free.
- Build: UUID 7864AA59, 0 weak symbols, 581 imports (identical to out-20), NMXOwnsDisplay present.
- It goes in the next batch.

### 2026-11-09 09:31 boot (no changes since 23:51)
- Loaded: the same batch (NMXGPU out-20, native 25F33563, ItlXhciKick 5D179C74, StrixS0ix 0.1.15). No new panic or crash reports.
- Shutdown stalls at 23:27 and 00:17 (reports decoded with `spindump -i`). In both, Docker was still running when shutdown sampled: com.docker.hyperkit with 24 vCPU threads idle, plus docker-agent. Other common processes were crashpad handlers and caffeinate. None of our kexts is in a blocked stack.
- Lead: shutdown waits for the Docker VM to exit. It goes to the RyzenHV session (does a vCPU blocked in the kext delay exit on SIGTERM?).
- Next batch candidates: NMXGPU out-21 7864AA59 (Step139 nmx_pin_by_proc), Wi-Fi native A62C12D2 (ABI and faultloop properties visible).

## Trace part 29: the ~56k page records/s during Chrome video are keep-cache thrash in Chrome's GPU process (2026-11-09)

Question from main (cpu-thermal saw `nmx_userrec_made/freed` rise ~56k/s during the part 28 probe). Plugin 9bfd0c5 (E26F136E), NMXGPU out-20.

**Rates.** Counters sampled every 1 s around a 60 s probe at 00:13-00:15:
- Idle before playback: 0-1k records/s.
- During playback: 34-67k/s, made ≈ freed, `nmx_userrec_live` flat at ~555k.
- `nmx_surf_hint` rises 16-32/s, so roughly 2000-4000 pages per hinted import.
- The rate stayed at ~45k/s after the scratch Chrome closed, because the owner's own Chrome was then playing a video (VTDecoder busy). Any Chrome video does this.

**Attribution:**
- WindowServer: its 30 s keep reports show 1-3 misses/s, so it is not the source.
- VCNDec alone: `vcndec_test` on the AV1 1080p clip, 1200 frames, `imports 1`, 1031 records in total. It caches its import per surface, so it is not the source either.
- Chrome GPU process:
  - The plugin's log is not in `/tmp/nvmtl.log`. That file is owned by `_windowserver` and is mode 644, so user processes log to `$TMPDIR/nvmtl.log` (`/var/folders/.../T/nvmtl.log`). A scratch Chrome run with `--disable-gpu-sandbox` (logging only) wrote there.
  - Its keep reports: `hits 0, misses 433 (new surface 3, idle cap 430)`, idle 1016 MB (the cap). idle-cap drops came back < 250 ms: 59, < 1 s: 286, < 3 s: 14.
  - The drops are all `2816x1472 fmt 80` (16.6 MB, window size), idle 3-4 s at the drop, back after 67-470 ms.
  - So Chrome cycles about 65 window-size surfaces while the video plays. 14 re-imports/s × ~4000 pages ≈ 56k records/s.

**Cause:** the cap drop order from 5ba6363 (idle age × bytes, oldest first) is the worst case for a cycle larger than the cap. It always drops the surface that comes back next.

**Fix**, plugin `plugin/video-lag` 9983f0c on camera-copy-890m 9bfd0c5, built `NVMTLDriver-9983f0c` UUID 5D8E67D8, not installed:
- When the idle cap binds, large surfaces (> NVMTL_KEEP_SMALL_KB) still go before small tiles.
- Among large ones, bytes first, then the most recently idle first (MRU). A fixed part of the cycle stays resident and only the overflow re-imports.
- Small tiles keep the old order.

**To check after install:**
- Chrome GPU keep reports (in `$TMPDIR/nvmtl.log`, needs the GPU sandbox off) show hits instead of 0.
- `nmx_userrec_made` per second during 1080p60 drops well below 56k.

**Open question:** why Chrome keeps ~65 window-size buffers in rotation. If it is Chrome's IOSurface pool reacting to surfaces in use, it is a separate issue on the Chrome/WS side.
- Plugin 9983f0c (video-lag, trace part 29) merged into camera-copy-890m.
  - What it fixes: Chrome's GPU process cycles ~65 window-size surfaces while a video plays, more than the 1 GB keep cap holds. The old oldest-first drop always evicted the next surface to come back, so 0 hits and ~56k page records/s.
  - The change: when the idle cap binds, large surfaces are dropped MRU (bytes first, then newest idle first).
  - Built by main: UUID 503C0AC5, sha cff7a9ed. Not installed; next-batch candidate.
- Wi-Fi core itlmt7925 2773F995 (dev/awdl 4568bf2: sniffer-config width code fix for the 160 MHz AP hang) was put on the ESP by the Wi-Fi session with the owner's OK. Backup: BBFBA198 at EFI/OC/Kexts-backup/itlmt7925.kext.20261109-094632. It loads at the next boot.

## Trace part 30: why Chrome "rotates ~65 window-size surfaces" (2026-11-09, plugin E26F136E, NMXGPU out-20)

Open question from part 29: is Chrome's IOSurface pool growing because surfaces stay "in use"?

**WindowServer in-use time is normal.** `tools/890m/inuse-test` (c093972) does what Chrome's compositor does: a CALayer gets a new IOSurface each frame at 60 Hz, and a surface is reused only once `IOSurfaceIsInUse()` is false.

| mode at 2816x1472 | in use after replace | pool size |
|---|---|---|
| CPU writes | p50 16.7 ms, p90 17.4 ms | 4 surfaces |
| Metal clear, cached texture | p50 16.7 ms | 3 surfaces |
| Metal clear, new texture per frame | p50 16.7 ms | 3 surfaces |

WS lets go after one frame, as on a real Mac. Use count is not what grows a pool.

**IOSurface object semantics (scratch test `look.c`):**
- `IOSurfaceLookupFromMachPort` returns a new IOSurfaceRef object on each lookup, even while another object for the same surface is alive in the process.
- So the keep cache's "held" test (`CFGetRetainCount(_surf) > 1`) cannot see a surface that Chrome holds as a mach port (a GpuMemoryBuffer handle) and looks up per use. Such a surface counts as idle while Chrome still uses it. That is why part 29's surfaces were "idle 3-4 s" yet came back.
- A freed surface's ID is handed out again at once. So "back after N ms" can also be a new surface that reused the ID.

**Re-run today (09:44, VP9 1080p60, scratch Chrome, Docker up):**
- The GPU process (pid 8737) wrote no 30 s keep report at all; it only reports on a miss, so it had no sustained misses after warm-up.
- No 2816x1472 surfaces were seen, and the part 29 thrash did not reproduce.
- Playback was 2700 decoded in 45 s; 64 drops, all in the first second (quality switch).
- `ioclasscount IOSurface`, default cap vs `NVMTL_KEEP_IDLE_MB=64`: plateau ~1015 vs ~885, inconclusive. The owner's own Chrome shares the counter, and the B probe returned no result.
- Part 29 ran AV1 at a window-size backing of 2816x1472, with the owner's Chrome also playing. The trigger is probably codec or window size; still open.

**Conclusion:**
- Not a WindowServer or use-count issue.
- 9983f0c stays as the guard for when the cycle exceeds the cap.
- Re-run the post-install check with AV1 (`probe.mjs` with an AV1 video) and the scratch window maximised, so the part 29 case is the one measured.

## Trace part 31: what IOSurfaceIsInUse sees, and the keep cache's held test (2026-11-09)

Main's follow-up to part 30: use IOSurfaceIsInUse for the keep cache's held/idle decision. First, what it reports. Scratch tests on Tahoe 26:

| state of the surface | IsInUse |
|---|---|
| one IOSurfaceRef in this process | 0 |
| + a mach port (IOSurfaceCreateMachPort) | 1 |
| + a second object from IOSurfaceLookupFromMachPort | 1 |
| port deallocated, one object again | 0 |
| locked | 1 |
| another process holds it (IOSurfaceLookup by global ID) | **0** |
| use count incremented (what CoreAnimation does while displaying) | 1 |

Cost: ~4 ns per call, so it reads process-local state and makes no kernel call.

**What this means for the keep cache:**
- It sees exactly what the retain-count test misses: a port or another object in the same process. That is how Chrome's GPU process holds GpuMemoryBuffer surfaces.
- It does not see other processes' references. So in WindowServer it adds only the use count, which CoreAnimation sets while a layer shows the surface. It cannot hold every client app's surfaces.
- Our own import does not set it: inuse-test with a cached plugin texture saw IsInUse drop to 0 one frame after WindowServer released the surface (part 30).

**Change:** plugin `plugin/video-lag` 0317f25 on 9983f0c, built `NVMTLDriver-0317f25` UUID 6F15C136, sha d43c60ef, not installed.
- A surface IsInUse reports as held counts as held, like a live wrapper.
- Bounded by NVMTL_KEEP_VIEW_MS (60 s) after the last wrap, so nothing is pinned forever.
- The 30 s report has a new field: "by IOSurfaceIsInUse N".

**To check after install:**
- WindowServer (`/tmp/nvmtl.log`): the "by IOSurfaceIsInUse" count is small, and entries and idle MB do not grow over 10+ minutes compared with before.
- Chrome GPU (`$TMPDIR/nvmtl.log`, sandbox off) during AV1 1080p60 in a maximised window: hits > 0 and idle-cap misses near 0.
- Plugin 0317f25 (video-lag part 31) merged on top of 9983f0c. The keep cache now treats IOSurfaceIsInUse as held, still bounded by NVMTL_KEEP_VIEW_MS, so surfaces Chrome holds through a mach port count as in use. Built by main: UUID 977F9F64, sha 9401582a. This replaces 9983f0c as the next-batch plugin.
- RyzenHV 0.7.18 D6B9AF8B is ready (Fix RyzenHV session, research/ga403wm-zen5 9993875).
  - Cause of the idle Docker cost: ~53k exits/s, 35k of them xAPIC nested page faults. The kext did a full TLB flush on every VMRUN.
  - Fix: flush by ASID, write DR/TSC_AUX only when they change, FPU self-check on 1 VMRUN in 64.
  - Not installed.
- Shutdown stalls closed (Fix RyzenHV session): the vCPUs are idle in HyperKit's own cvwait, not in RyzenHV. Docker Desktop quits without stopping its VM, so hyperkit is orphaned under launchd and lives until the final kill. The reports are the normal 2 s sample, not a hang; one at 12:55 had no Docker at all. Fix, if wanted: quit Docker Desktop before shutdown. RyzenHV 0.7.18 is pushed (research/ga403wm-zen5 9993875).

### 2026-11-09 09:58 install batch (owner OK)
- Plugin 0317f25 (UUID 977F9F64; signed bundle binary ae638a67). Backup: /Library/NullMoth/nvmtl-plugin-20261109T0257*, which holds 9bfd0c5. SbxMap pins refreshed (stale=0).
- NMXGPU out-21 7864AA59 (Step139 nmx_pin_by_proc) went in through macos-install-step130.sh. AuxKC relinked; kccheck OK for all 8 kexts.
- Wi-Fi native A62C12D2 on the ESP. Backup: 25F33563 at EFI/OC/Kexts-backup/itlmt7925Native.kext.20261109-095805.
- Already staged by the Wi-Fi session: core 2773F995.
- RyzenHV 0.7.18 D6B9AF8B is being installed by the Fix RyzenHV session.
- Checks after boot:
  - `sysctl debug.nmx_pin_by_proc`
  - Chrome AV1 1080p60 maximised: keep hits > 0, userrec_made/s
  - WS keep "by IOSurfaceIsInUse" count stays small
  - ioreg itlmt-native-(abi|faultloop)
  - hyperkit CPU and exits/s
- RyzenHV 0.7.18 D6B9AF8B is on the ESP (Fix RyzenHV session). Backup: 0.7.17 5B53EE91 at EFI/OC/Kexts-backup/RyzenHV.kext.20261109-095823. The batch is complete; ready to reboot.

### 2026-11-09 ~10:03 panic after AC unplug, boot ~10:05
- On the boot after the batch reboot, the owner unplugged AC and the machine froze. With debug=0x100 the panic screen stays up, so the freeze was the panic.
- Panic (Kernel-2026-11-09-100606.panic, uptime 163 s): a GP fault in OSMetaClass::applyToInstances, under IOService::copyExistingServices / getMatchingServices / is_io_service_get_matching_services_ool, process CloudflareWARP. RAX = 0x656372756f736552 = "Resource": a dangling object in a metaclass instance set whose memory has been reused. That is a use-after-free in some kext's IOKit object lifetime; WARP's enumeration on the power change only tripped over it.
- The current boot loaded the whole batch: out-21 7864AA59 (`nmx_pin_by_proc` works), native A62C12D2 (abi ok, faultloop own), core 2773F995, RyzenHV 0.7.18 D6B9AF8B. It is running on battery with no repeat so far.
- Investigation: a timeline and class attribution are in progress; the Wi-Fi, RyzenHV and video sessions were asked to audit their object lifetimes.

### 2026-11-09 battery drain, dGPU D3cold (StrixS0ix 0.1.16)
- On battery after boot: ~31 W from the battery (AppleSmartBattery −3.98 A → −2.1 A at 14.5 V), but the CPU package is only 7.2 W (debug.amdcppc.sensors RAPL). The RTX 5060 is in PCI D0 the whole time: NVRM 2.7.1 has no runtime power management (RTD3/GC6 off), so the card and its PCIe link never sleep.
- ACPI (SSDT-5 "OptRf2"): GPP9 has _PR0/_PR3 = PG00. PEGP._PS3 calls PG00._OFF only after the NVIDIA Optimus _DSM sets OMPR=3. PG00._OFF clears EC VGAT, then does BPGF, link disable (DL23), POFF and APGF.
- StrixS0ix 0.1.16 (C7BB7761): boot-arg `s0ix_dgpuoff=1`. 20 s after start, if neither RTX function has a registered driver (boot with `-nvoff`), it puts both into D3hot through PMCSR and evaluates `\_SB.PCI0.GPP9.PG00._OFF`. The result goes to the property `S0ix,DgpuOff` ("PG00._OFF rc, PG00._STA"). If any driver is attached it refuses.
- This is an iGPU-only boot mode: no RTX, no HDMI (the HDMI port is on the RTX).
- Not installed. The proper fix, RTD3 inside NVRM so the card powers off when idle without a reboot, is a separate NVRM port project.
- 2026-11-09 install batch for the dGPU-off test:
  - StrixS0ix 0.1.16 C7BB7761 is in the AuxKC; kccheck OK.
  - The ESP config.plist boot-args gained `-nvoff s0ix_dgpuoff=1`. Backup: EFI/OC/config.plist.pre-dgpuoff; restore it to undo. A first edit landed in the repo's efi/OC copy by mistake and was reverted.
  - RyzenHV 0.7.20 0D48F260 (root-cause fix: header deps, ABI self-check, variable-size stats) is being installed by the Fix RyzenHV session.
  - After boot, check:
    - `ioreg -l | grep S0ix,DgpuOff` should read PG00._STA 0;
    - the RTX is gone from the bus or its link is down;
    - battery watts against ~31 W;
    - sleep/wake;
    - RyzenHV hvf-smoke before Docker.
- RyzenHV 0.7.20 0D48F260 is on the ESP (backups: 0.7.18 broken, 0.7.17). The batch is complete; ready to reboot.
- 2026-11-09 10:36, read from Windows (ESP read-only): the owner reports the dGPU-off batch does not boot. The only
  boot-args difference from `config.plist.pre-dgpuoff` is `-nvoff s0ix_dgpuoff=1`. `-nvoff` also parks NMXGPU:
  `opted_in()` in nmx_kext.cpp (nmx-source-port) returns false on `-nvoff` before it looks at `nmxamd=1`. With
  `-strixgopoff` also set, no driver takes the 890M, so the panel has no framebuffer (same lever ruled out at line
  ~8311). The dGPU-off test cannot be run with `-nvoff` as the switch: it needs an NVRM-only off flag, or `opted_in()`
  must let `nmxamd=1` win over `-nvoff`. Not changed on the ESP (owner's call).
- 2026-11-09 10:38, from Windows, owner's request: `-nvoff s0ix_dgpuoff=1` removed from the ESP boot-args. The string
  now equals the one in `config.plist.pre-dgpuoff`; XML parses, ESP unmounted. Backup of the dGPU-off config:
  `EFI/OC/config.plist.bk-nvoff-20261109T103845`. StrixS0ix 0.1.16 and RyzenHV 0.7.20 stay installed; without
  `s0ix_dgpuoff=1` the dGPU-off code in StrixS0ix only sets `S0ix,DgpuOff = off`.
- 2026-11-09 11:05, root cause of the failed dGPU-off boot (main): `-nvoff` is NullMoth's "park every GPU driver" flag,
  not an NVRM-only switch. It is read by NVRM/NVRMFB/NVAccel/NVRMAGDC (`nvrm_driver_off()`), and also by NMXGPU
  `opted_in()` (nmx_kext.cpp:551, checked before `nmxamd=1`), NMXNPU `opted_in()` and NMXAGDC `nvrm_driver_off()`.
  With `-strixgopoff` set, nothing drove the 890M, so the panel had no framebuffer. Mistake: the boot-arg went on the ESP
  without a grep of every kext's handling of it. Fix direction: no `-nvoff`. The RTX is kept from NVRM by StrixDgpuGate
  (rog-control-macos feat/gpu-mode 90b7e08): default-category claim, score 2000 > NVRM 1000, decided from NVRAM
  `strix-gpu-mode`, with a loop guard (`strix-gpu-eco-try`) and `-strixgate_off` for recovery. Review sent: NVAccel
  (IOAccelerator, score 100) waits 30 s for `nvrm-claimed` in start(), so the gate needs an IOAccelerator hold
  personality, and the Eco decision has to be cached once for all personalities. Audit: NMXGPU only reads NVRM in
  nmx_beat (optional); HDAU 10de:22eb has no driver; no kext parses strixgate_*/strix-gpu-*; OC NVRAM Delete leaves the
  keys alone. StrixS0ix 0.1.16 `s0ix_dgpuoff` stays dormant (no arg) and is superseded by the gate.
- 2026-11-09 11:25, StrixDgpuGate dry run staged (owner OK, main). Kext built from rog-control-macos feat/gpu-mode 9b73c81
  (0.1.0, UUID 52DE19FB, 0 weak symbols), copied to EFI/OC/Kexts, Kernel Add #47 (Min 25.0.0, Max 25.99.99). OC-injected, so
  it is on PEGP before the AuxKC brings NVRM. ESP boot-args + `strixgate_dry=1` (parsed only by StrixDgpuGate).
  NVRAM `strix-gpu-mode=eco`, `strix-gpu-eco-try` cleared. Backup: EFI/OC/config.plist.pre-strixgate.
  Audit: no `-nvoff`; NMXGPU/NMXAGDC/NMXNPU read nothing from the gate; the plugin's WindowServer/Vulkan picks fall back to
  NMXAccel when there is no NVAccel (nvmtl_vk.c 116-160). Expected next boot: `ioreg -c StrixDgpuClaim` + StrixDgpuAccelHold on
  PEGP, no NVRM/NVAccel, gate-state "eco: ... dry run", RTX still powered, HDMI dead, 890M/OLED as before.
  Undo: OC picker boot-arg `-strixgate_off`, or `sudo nvram strix-gpu-mode=standard`, or Kernel Add #47 Enabled=false /
  restore config.plist.pre-strixgate. A boot that does not reach 90 s uptime trips the loop guard (next boot NVRM).
- 2026-11-09 11:30, next-boot batch checked (main): RyzenHV 0.7.21 B37AAE98 on the ESP (Fix RyzenHV session, owner OK; 0.7.20 in
  Kexts-backup/RyzenHV.kext.20261109-112219) + StrixDgpuGate dry run 52DE19FB (Kernel Add #47, strixgate_dry=1,
  strix-gpu-mode=eco). Config still carries both gate changes. One reboot covers both.
