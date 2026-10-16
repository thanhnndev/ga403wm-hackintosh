# Tahoe (macOS 26) migration checklist

Started 2026-10-16. Source state: macOS 15.8.1 (24H32), OpenCore 1.0.9, NullMoth 2.0.4 + fork overlay prepared for the
update (`docs/NULLMOTH.md`). Why Tahoe: last macOS for Intel/x86, so its ABI is the stable final target for the 890M port
(owner direction: full hardware port, not CPU workarounds).

## Snapshot before the upgrade

`bash scripts/macos-pre-upgrade-snapshot.sh 24H32`
* Sanitized (public repo): `out/pre-upgrade-24H32/` — loaded kexts, installed kext versions + executable hashes, OpenCore
  config summary (Kernel/Add with Min/MaxKernel, patches, ACPI, DeviceProperties keys, boot-args), our ioreg classes
  (StrixAccel, StrixGOP, StrixProbe, StrixMetalGate, AsusWmi), debug sysctls, pmset, system_profiler, launchd jobs, dyld
  shared-cache ranges of CoreDisplay/SkyLight/IOSurface/IOKit/Metal/QuartzCore/IO80211.
* Raw (local only, has serials/MACs/UUIDs + full config.plist): `~/efi-audit/pre-upgrade-24H32-20261016T133613/`.
* IO80211 / Skywalk ABI dumps of 24H32 already in `abi/native-wifi/24H32/` (round 3..10) for the Tahoe diff.

## Boot safety changes made for the first Tahoe boot

* ESP `config.plist`: `itlmt7925Native.kext` gets `MaxKernel 24.99.99` (its IO80211/Skywalk vtables and AppleBCMWLAN
  layouts are 24H32-specific; loading it on Darwin 25 risks a panic). Backup `config.plist.pre-tahoe-native-maxkernel`.
  ocvalidate clean. Wi-Fi on Tahoe therefore starts in the Ethernet-mode `itlmt7925.kext` (or not at all): keep USB
  tethering (HoRNDIS, Android) or a USB Ethernet adapter ready.
* Already in config (prepared earlier): kernel patches with 25.x ranges (cpuid, PAT, non-monotonic time incl. 26.4+,
  IOPCIFamily 10-bit tags 26.0+). Strix/NVRM entries on the ESP have MinKernel 24.0.0 and no MaxKernel.
* NullMoth `prepare`: driver parked with `-nvoff`, BAR setting changed, `com.nullmoth.osupdate` LaunchDaemon armed; the first
  Tahoe start runs `finish` (NVAccel 26, AuxKC rebuild incl. overlay, BAR restore, one self-reboot). Rebooting into 15.8.1
  without updating = no NVIDIA driver. Cancel: `nullmoth-setup.sh --update cancel`.
* Lilu plugin `StrixHeadroom` declares max kernel Sequoia: Lilu will not start it on Tahoe (it never patched anyway).
* User LaunchAgent `com.thanhnndev.strix.headroomhold` (EDR request stopgap) stays; harmless if Tahoe does not need it.

## Re-derive / re-test on Tahoe, in order

1. **Boot health:** `sw_vers`, panics (`/Library/Logs/DiagnosticReports/*.panic`), `kmutil showloaded` vs
   `out/pre-upgrade-24H32/kmutil-loaded.txt`, NullMoth `finish` result, NVIDIA Metal device, OLED picture, brightness.
2. **Display stack (890M):** StrixGOP (IOFramebuffer, probably source-compatible: rebuild + test), StrixAccel ABI profile
   (`tools/strix_abi_profile.py`; 24H32 profile is `macos15-24H32-x86_64-ioaccel485.2`, the gate must refuse other
   builds), StrixMetalGate, StrixProbe; CoreDisplay `CurrentHeadroom` / `CombineLUTs` / `RunGPUDisplayPipe` re-read (offsets
   in docs/890M-TRACE.md Step13/14 are 24H32-only); measure WindowServer CPU with and without the headroom hold.
3. **Wi-Fi native:** new IO80211/Skywalk dumps (`abi/native-wifi/<build>/`), regenerate headers
   (`tools/gen_io80211_header.py`), re-check every 24H32 address/layout comment in `kexts/itlmt7925Native/*`, then lift
   `MaxKernel`. Skywalk legacy-Ethernet shim: re-verify.
4. **Rest:** BtLeDlFix (bluetoothd byte pattern is 24H32), BlueToolFixup/MtkBtFw, AppleALC + RogAudio/StrixAmp, AsusWmi,
   AmdCppc, VoodooI2C/TapGuard, USBToolBox map, sleep/wake, battery.
5. **890M port (the real work), on Tahoe:** milestones 4..10 of `docs/890M-COBALT64-PORT-RESEARCH.md`
   (research/890m-cobalt64): GMC v11 UMA/GART + dynamic GPU memory allocation, PSP13/SMU14/IH, SDMA 6.1 copy + fence,
   GFX 11.5 + MES rings and shaders, RADV gfx1150 on Darwin, Metal over Vulkan, WindowServer on the iGPU, DCN35 native eDP
   with hardware LUT/CSC, dGPU D3cold for battery.
