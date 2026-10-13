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
