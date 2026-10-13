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
