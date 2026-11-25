# GA403WM on macOS 26 Tahoe: state and roadmap (2026-11-25)

State document of the "v2 (macOS 26 Tahoe)" release. Written from the install log of the reference machine, the
documents in this repository and a read-only check of the running machine on 2026-11-25 (`kmutil showloaded`,
`sw_vers`, boot-args). Nothing here was tested on a second machine. macOS 15 is the previous release (v1 / kext-v1.1)
and is not described here; its documents are [INSTALL.md](INSTALL.md), [HANDOFF.md](HANDOFF.md) and [ROADMAP.md](ROADMAP.md).

Words used in the tables:

- **works**: verified on the reference machine on the date given.
- **partly**: works with a stated limit, or was verified on an older build of the stack and not since.
- **broken**: known not to work.
- **not verified**: no test on record for the current stack. This is not a claim that it fails.

## 1. Summary

One ASUS ROG Zephyrus G14 GA403WM (Ryzen AI 9 HX 370, Radeon 890M, RTX 5060 Laptop, 2880x1800 120 Hz OLED, 32 GB) runs
macOS Tahoe 26.7.2 (25G332, Darwin 25.6) under OpenCore 1.0.9 as a daily machine. The internal display, WindowServer and
all applications run on the Radeon 890M through `NMXGPU`, a source port of Linux amdgpu on a LinuxKPI layer (fork of
NullMoth's driver), with a Metal-on-Vulkan plugin on RADV in user space. Video decode for H.264, HEVC, VP9 and AV1 runs
on the 890M's VCN through a VideoToolbox decoder (`VCNDec`). The RTX 5060 is normally powered off and removed from the
PCI bus at boot (Eco mode, `StrixDgpuGate`). Wi-Fi and Bluetooth (MT7925), audio, the ASUS controls, Docker (through the
`RyzenHV` hypervisor kext) and the iOS Simulator work. The main open items are: the Android emulator guest stalls under
RyzenHV (root cause found, the fix is staged and not yet verified); WindowServer costs about 6.5-7 ms of CPU per
presented frame, and GPU power follows the compositing rate because every present recomposites the whole screen; power
under a Docker load reaches 62 W and 95 C; sleep/wake has not been re-tested on the current stack; and the reference
EFI in the repository still describes the October (macOS 15) configuration. Almost all code was written by an AI and tested on this one laptop.

## 2. What works, by area

"Doc" is the file that backs the row. Files marked (branch `research/audio-rog-dolby`) are on that branch only: the
audio work is not merged into this release. "Log" is the maintainer's install log (package notes, 2026-11-18 to
2026-11-25), which is not in the repository.

### Boot

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| OpenCore boot of macOS 26.7.2 from the internal disk | works | OpenCore 1.0.9 debug build (`opencore-version` DBG-109-2026-10-09) with the Zen 5 timer patch | live boot 2026-11-25 10:40 | `patches/opencore`, `efi/README.md` |
| Eco boot to the login window | works | 14.4 s after kernel start on 2026-11-19 (was 77 s: a 60 s GPU wrangler timeout and a 3.5-4.4 s APFS trim, both fixed). Later boots measured about 23 s and 33 s (cold shader caches once; `MtkBtFw` holds the registry busy for 4-9 s). The owner accepts this | 2026-11-19, 2026-11-23 | `docs/BOOT-TIMELINE.md`; log |
| OpenCore picker | works | Still shown (2 s). A script to hide it exists; whether Esc at power-on still reaches the picker is not verified | 2026-11-19 | `docs/BOOT-TIMELINE.md` |
| Reference EFI in the repository (`efi/`) | partly | `efi/OC/config.plist` was last changed 2026-10-13 and describes the macOS 15 setup (with the reference machine's USB map, `UTBMap.kext`). It lacks the Tahoe kexts and the current boot-args, and it does not reference the S0-idle / PTS5 / LIDFIX tables, although their `.aml` files are in `efi/OC/ACPI`. The live ESP was not exported | checked 2026-11-25 | `efi/`, `docs/FRESH-INSTALL.md` 1.1 |
| Fresh install on a blank disk | partly | Done once by hand on 2026-11-07 through the Tahoe installer app. The one-click installer is a design and read-only prototype scripts | 2026-11-07 | `docs/FRESH-INSTALL.md`, `docs/FRESH-INSTALL-LESSONS-2026-11-07.md` |

### Display, brightness, HDR

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| Internal OLED on the 890M, 2880x1800 at 120 Hz | works | amdgpu display core inside NMXGPU; zero-copy page flips; flip completion from the page-flip interrupt and vblank from the real CRTC since out-33 | 2026-11-18 (out-33), verify script 19 pass / 0 fail on 2026-11-25 | `docs/FRAME-PATH.md`; log |
| Brightness slider and brightness keys | works | Handler inside NMXGPU (Step130c), owner verified | 2026-11-08 | `docs/890M-ROADMAP.md` |
| HiDPI | partly | "Looks like 1440x900" and native 2880x1800, both 120 Hz. No other scaled sizes: the framebuffer reports one mode. Extra modes are deferred | 2026-11-04 (owner report) | `docs/890M-TRACE.md`, "HiDPI scaled modes" |
| HDR / EDR | not verified | No test on the NMXGPU display path. The earlier HDR work was in `StrixGOP`, which is now switched off by boot-arg | - | - |
| Display sleep and wake | works | PASS on Step106c (2026-11-04) and listed as passing in the 2026-11-08 state; no run on record for the kernels since out-31 | 2026-11-08 | `docs/890M-ROADMAP.md` |
| PSR on a static screen | not verified | PSR1 is enabled; whether it is entered is not measured | - | `docs/POWER-FEATURES.md` |
| HDMI output | partly | The port is wired to the RTX. Dead in Eco. In Standard it needs a re-test with the OLED on the 890M. The mode is decided at boot; no switch without a restart | owner question 2026-11-19 | `docs/890M-ROADMAP.md`; log |

### GPU acceleration

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| WindowServer composited on the 890M | works | Frame-path check 19 pass / 0 fail on the 2026-11-25 boot. Trace on out-33: frame total p50 9.27 -> 6.05 ms, late frames 6 % -> 1.3 % | 2026-11-18, 2026-11-25 | `docs/FRAME-PATH.md`; log |
| WindowServer CPU cost | partly | 6.5-7.1 ms of CPU per present (26 % of a core at about 35 presents/s). The driver stack's share is 1.3-2.3 ms. A real Mac is about 1 ms | 2026-11-19, 2026-11-23 | `docs/WS-CPU.md` |
| WindowServer GPU work per present | partly | Every present recomposites the full 2880x1800 screen and runs a full-screen colour pass: about 1.1 ms of GPU per present, whatever the size of the change. The cursor is a software cursor (the framebuffer reports no hardware cursor plane), so every cursor move is a full present plus a flip | 2026-11-25 | `docs/WS-CPU.md` 9.6 |
| Metal in applications | works | Every app gets the 890M (allow list `*`); sandboxed apps go through a user client in NMXAccel | 2026-11-04 (Step102-104) | `docs/890M-ROADMAP.md` |
| WebGL in Chrome and Edge | works | On the 890M since Step104. Google Maps broken strokes fixed (plugin + translator) | 2026-11-04; Maps fix verified 2026-11-18 | `docs/MAPS-WEBGL.md` |
| WebGL in Safari | works | Needs `StrixSbxMap`, a kernel-side exception that lets the WebKit GPU process map eight pinned plugin files by code hash. The pins must be refreshed after every plugin or RADV rebuild | A/B on 2026-11-04 (Step105c) | `docs/890M-ROADMAP.md`, "Safari WebGL" |
| Metal device for the RTX 5060 (hybrid) | broken | Not implemented on this stack. Deferred by the owner | - | `docs/890M-ROADMAP.md`, "Hybrid" |
| GPU compute for LLM runtimes | not verified | No test on the 890M stack | - | - |

### Video decode

Codec matrix of 2026-11-18 (NMXGPU out-33, RADV with all codecs, VCNDec 0.2.0): 59 cells (1080p30/60 and 4K; MP4,
fragmented MP4 over MSE, WebM, WebM over MSE), **58 pass, 0 fail, 1 without a test clip** (10-bit AV1 in WebM). Before
the fixes it was 19 pass, 39 fail. Doc: `docs/VIDEO-CODEC-MATRIX.md`.

| Codec | Chrome | Safari | QuickTime |
|---|---|---|---|
| H.264 8-bit | hardware | hardware | hardware |
| HEVC Main 8-bit | hardware | hardware | hardware |
| HEVC Main10 | hardware | hardware | hardware |
| VP9 profile 0 | hardware | hardware | no WebM in QuickTime |
| VP9 profile 2 (10-bit) | hardware | hardware | - |
| AV1 8-bit | hardware | hardware | hardware |
| AV1 10-bit (MP4 only) | hardware | hardware | hardware |

Limits of this evidence:

- The matrix was run on VCNDec 0.2.0. The live decoder is 0.2.1 (256-byte plane alignment, live since 2026-11-25).
  0.2.1 was tested in-process (`vt_check`: every frame index right, 0 errors) and read once after the boot. **The
  full browser matrix has not been rerun on 0.2.1.**
- Edge was not part of the matrix (the test rule is Chrome only). Edge 4K VP9 on the VCN was observed under the
  owner's use on 2026-11-23.
- Hardware encode is not covered by any document: not verified.
- Each decoded frame is copied once on the GPU into the output IOSurface (12 MB at 4K 8-bit). Linux plays the decoder's
  image without a copy.

### RTX 5060

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| Eco mode: card powered off and off the bus | works | `StrixDgpuGate` runs `_DSM` + `_PS3` and terminates the card's PCI nubs, so macOS does not wait for it. Verified on every boot since 0.2.1; 0.2.12 is live | 2026-11-19 to 2026-11-25 | `docs/BOOT-TIMELINE.md`; log |
| Loop guard (Eco falls back to Standard after an unfinished boot) | works | False trips on 2026-11-16 and 2026-11-22 came from a missing clear at shutdown; fixed in 0.2.5+. The shutdown clear was proven on 2026-11-23 | 2026-11-23 | `docs/BOOT-TIMELINE.md` 0.1 |
| Eco with sleep/wake, and charger plug/unplug with the card off the bus | not verified | The owner starts sleep tests; none was run since the card is taken off the bus. One charger hang on 2026-11-09 was not reproduced in two tests; the third test is deferred | - | `docs/HANDOFF-2026-11-16.md` 5.5 |
| Standard mode (card powered, NullMoth NVRM 2.7.1) | partly | The kernel side boots. The Standard boots on record since 2026-11-10 were loop-guard trips (2026-11-16, 2026-11-22), not planned tests. Apps get no Metal device from the RTX; HDMI needs a re-test | 2026-11-16 | `docs/HANDOFF-2026-11-16.md` |
| Switching mode | partly | NVRAM `strix-gpu-mode` (RogControl 0.6.0 GPU tile); needs a reboot | 2026-11-10 | rog-control-macos PR #17 |

### Wi-Fi and Bluetooth (MT7925)

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| Wi-Fi, native mode (Wi-Fi menu, join from System Settings) | works | `itlmt7925` + `itlmt7925Native`. On 25G241 the mt7925-macos README records 176.6 Mb/s down, 65.0 Mb/s up, HE 160 MHz. In daily use on 25G332; no throughput run on record for 25G332 | 2026-11-02 (numbers), 2026-11-25 (loaded) | mt7925-macos `README.md` |
| Wi-Fi limits | partly | WPA2-PSK only (no WPA3, open networks, 802.1X, 6 GHz). A-MSDU receive is off on purpose. The driver is fully polled, no interrupt: estimated 3-6 % of a core under traffic | 2026-11-23 | `docs/KERNEL-TASK-POLLERS.md` |
| AirDrop / AWDL / Continuity | not verified | In progress in mt7925-macos `dev/awdl`. `itlmt_awdl=1` is set on the reference machine; no working result is recorded | - | mt7925-macos `docs/ROADMAP-AWDL.md` |
| Bluetooth | works | `MtkBtFw` 0.3.1 + `BtLeDlFix` 1.4.0 + BlueToolFixup. The 15 s `bluetoothd` restart loop after a warm reboot was fixed on 2026-11-08; the `bluetoothd` fault at every boot was fixed on 2026-11-23. A BLE mouse is in daily use. Keyboard pairing is not recorded | 2026-11-08, 2026-11-23 | mt7925-macos `docs/BLUETOOTH.md`; `docs/SHUTDOWN-TIMELINE.md` |

### Audio

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| Built-in output and input devices | works | SimpleHDA 1.0.1 brings AppleHDA back on Tahoe; AppleALC 1.9.9 (a local build with a GA403WM layout) for the ALC285 codec | 2026-11-05 | `docs/AUDIO-TAHOE.md` |
| Speakers | works | All four driver groups verified by a microphone sweep: tweeters on the codec, woofers on two CS35L56 amplifiers through `StrixAmp` 0.2.0. The "ROG Speakers" device and its DSP need the RogAudio HAL driver and `rogaudiod`, which must stay unsigned | 2026-11-23 | `docs/AUDIO-ROG.md` (branch `research/audio-rog-dolby`) |
| Microphones | partly | The internal pair works; Clear Mic (noise reduction) verified by speech. The third microphone cannot be reached under AppleHDA (one input engine). The input gain has been found at its minimum, cause unknown; a trace is armed | 2026-11-23 | `docs/AUDIO-ROG.md` 16-19 (branch `research/audio-rog-dolby`) |
| Headphone jack, audio after sleep | not verified | On Tahoe. A fix for ALC285 crackle is known but not applied | - | `docs/AUDIO-TAHOE.md` |

### Keyboard, Fn keys, touchpad, USB

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| Keyboard | works | Internal USB keyboard; needs `ItlXhciKick` (without it key release lags 2 s) | live | `docs/USB-XHCI-LAG.md` |
| Fn keys | partly | Mute and volume work natively. The vendor-page keys (keyboard light, Aura, profile, airplane mode, M3/M4 and others) need `rogkeyd`, a user-space helper with Input Monitoring and Accessibility grants, plus `AsusWmi`. Fn+F10 (touchpad toggle) and Fn+F6 are not mapped | 2026-11-06 (release rogcontrol-v0.5.2) | rog-control-macos `docs/FN-HOTKEYS.md` |
| Touchpad | works | VoodooI2C + VoodooI2CHID in forced polling mode (`-vi2c-force-polling`): about 10k interrupts/s on CPU 0. Interrupt mode is not tested | 2026-11-23 | `docs/KERNEL-TASK-POLLERS.md` |
| USB ports | works | `ItlXhciKick` 0.1.0 polls at 1 kHz. The live ESP has a USB map (USBToolBox + UTBMap); the reference EFI carries the map as it was on 2026-10-13, not compared with the live one | live; map noted 2026-10-12 | `docs/USB-XHCI-LAG.md`, `docs/HANDOFF.md` |
| Webcam | works | UVC, last noted with the audio work | 2026-11-05 | `docs/AUDIO-TAHOE.md` |
| SD card reader | not verified | `Sinetek-rtsx` 9.0.0 is loaded; no function test on record | - | - |

### Sleep, wake, shutdown

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| Sleep and wake | partly | The firmware has no S3. S0 idle sleep with RTC, lid and power-button wake passed with `StrixS0ix` 0.1.12 on 2026-11-07. S0i3 residency was not reached (DISPLAY and NBIO blocks not idle). **Not re-tested** since NMXGPU became a source build (2026-11-08), since IOSurface parking, and since Eco takes the RTX off the bus | 2026-11-07 | `docs/890M-TRACE.md` (Step107-126) |
| Shut Down | works | Stays off since `SSDT-PTS5` (2026-11-05). A shutdown takes 5-18 s for apps to quit plus 4-11 s of teardown, both third-party | 2026-11-05, 2026-11-23 | `docs/SHUTDOWN-TIMELINE.md` |
| Restart | partly | One restart on 2026-11-23 took 3 min 50 s between the kernel's restart message and the reset; cause unknown; a shutdown trace is armed in the gate | 2026-11-23 | `docs/SHUTDOWN-TIMELINE.md` 1.3 |

### Battery, power, thermals

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| Light working load | works | Edge video + Claude app + 4 CLI sessions, AC, Eco, EPP 191: **17.0 W package (RAPL, 60 s), Tctl 57 C average (55-60)**, fans low, wired memory 6.6 GB | 2026-11-23 14:54 | `docs/POWER-UNDER-LOAD.md` |
| Heavy working load | partly | Docker + Android emulator + a Python backend + Claude, AC: **62.2 W package, Tctl 95 C average (91-96)**, fans at maximum, `kernel_task` 108 % from memory compression. Measured at EPP 0 (Turbo), with the RTX powered, Docker on 24 vCPUs and the whole guest wired. **Not re-measured** with EPP 191, Eco, 8 vCPUs and lazy guest wiring | 2026-11-16 18:56 | `docs/HANDOFF-2026-11-16.md` 3; `tools/health/2026-11-16/` |
| GPU rail readout | partly | First read of the SMU metrics on the 2026-11-25 boot: socket 17.4 W, of which **GFX 9.3 W**, all cores 9.4 W, GFX activity 22 %; the derived "rest of SoC" field came out negative (formula wrong). Later reads the same day: **GPU power follows the compositing rate.** Static screen: 0.09 W on the GFX rail, 6.2 W socket. At 81-91 flips/s: 12-19 W on the GFX rail. So the rail does go down when nothing is composited; the cost is per present (see "WindowServer GPU work per present") | 2026-11-25 | `docs/POWER-FEATURES.md`; log (the static and 81-91 flips/s numbers are in the log only) |
| Idle floor | not verified | 5.5 W at 47 C was measured once on 2026-11-08 and not since. Cores idle in HLT; no CC6 at run time | 2026-11-08 | `docs/POWER-FLOOR.md` |
| Profiles, fans, power limits, charge limit | works | `AsusWmi` 0.3.1 + RogControl + `AmdCppcPolicy` do what Linux and Windows do for the presets (one thermal-policy write; firmware loads limits and fan curve). The fan-curve read after the 0.3.1 index fix and the per-profile bench are not done | 2026-11-16 | `docs/PLATFORM-LIMITS.md` |
| Battery | partly | Charge level through SMCBatteryManager. Battery life is not measured in Eco. One reading with the RTX powered and a heavy load: 75 W drain against 31 W package. The "60 W" adapter figure in System Information is a placeholder | 2026-11-16 | `docs/POWER-FLOOR.md` |

### Virtualization and the iOS Simulator

| Item | State | Detail | Evidence | Doc |
|---|---|---|---|---|
| Docker Desktop on `RyzenHV` | works | 0.7.23: guest memory is wired lazily (about 3 GB wired for an 8 GB guest instead of 8 GB). Reclaim of cold guest memory is a run-time switch that resets to off at boot (2.86 -> 1.74 GB when on). Idle containers on 8 vCPUs cost 17.5 % of a core | 2026-11-18, 2026-11-23 | `docs/RYZENHV-GUEST-MEM.md` |
| Docker quit | partly | Quitting Docker Desktop 4.98 can leave a HyperKit process spinning two cores (a HyperKit deadlock, not RyzenHV) | 2026-11-23 | log |
| Android emulator (QEMU with HVF) | broken (fix staged, not verified) | The guest kernel stops at 13.9 s, adb stays offline, qemu at about 100 %. Not host graphics. Root cause found on 2026-11-25: RyzenHV exposed CPUID PKU/OSPKE to guests while macOS never enables PKRU state in XCR0; see section 4. The fix (RyzenHV 0.7.24) is on the ESP and has not run yet | 2026-11-23 (failure), 2026-11-25 (cause) | log; ryzen-hypervisor.framework fork, branch `fix/vmcb-cache-switch` 11ec930 |
| iOS Simulator | works | Renders on the 890M; SimBench 60 fps; the crash loop that cost 1.1 cores was fixed in the translator. One wallpaper shader still fails. Flutter and Android toolchains are not measured in any committed document | 2026-11-07 | `docs/SIMULATOR-PERF.md` |

## 3. Component versions live on 2026-11-25 (boot 10:40:28)

Source: the install log, checked against `kmutil showloaded` on the same boot. UUIDs are the first 8 hex digits of the
binary's LC_UUID.

### Ours (built from the five repositories)

| Component | Where it loads from | Version | UUID | Source commit |
|---|---|---|---|---|
| NMXGPU (`com.nullmoth.NMXGPU`) | AuxKC | 1.0.0, build out-50 | 7390F47B | nvidia-macos-driver fork, `fix/out31` f47d3ed |
| NMXAccel (`com.nullmoth.NMXAccel`) | AuxKC | 0.1 | D454C218 | fork, installed 2026-11-18 (fourth package); unchanged since |
| NMXAGDC (`com.ga403wm.NMXAGDC`) | AuxKC | 0.1 | 90C7A833 | fork; commit not in the log |
| Metal plugin (NVMTLDriver) | `/Library/GPUBundles` | - | AAC482F2 | fork, `claude/mem-census` 8de348c |
| Shader translator | `/Library/GPUBundles` | - | - | 6208982 (installed 2026-11-18; no later entry in the log) |
| RADV (`libvulkan_radeon.dylib`) | `/Library/GPUBundles/nvmtl` | - | 07725f8c (hash prefix from the log) | Mesa built with `-Dvideo-codecs=all` + `scripts/radv/radv-disk-cache-euid.patch` |
| VCNDec | `/System/Library/Video/Plug-Ins` (blessed snapshot) | 0.2.1 | E7D4AB21 | this repo, `tools/890m/vcndec` at 15c33fa (the tree here is one test-only commit newer, d378c71) |
| StrixDgpuGate | ESP | 0.2.12 | 7AD92287 | rog-control-macos `fix/eco-offbus` 80356b5 |
| AsusWmi | ESP | 0.3.1 | 42393DEB | rog-control-macos `fix/fan-curve-index` 44ee05c |
| AmdCppc | ESP | 0.2.1 | 2EBD4419 | rog-control-macos; commit not in the log |
| RogControl.app, rogkeyd | `/Applications`, user LaunchAgent | 0.6.0, 1.2 | - | rog-control-macos `feat/gpu-mode` (PR #17, open); as of 2026-11-16, not re-read on 2026-11-25 |
| RyzenHV | ESP | 0.7.23 | 3A045FC8 | ryzen-hypervisor.framework fork, `research/guest-mem-lazy` |
| itlmt7925 (core) | ESP | 0.1.0 | D2CAADD0 | mt7925-macos `dev/awdl` (0ec468c records the install) |
| itlmt7925Native | ESP | 0.1.0 | 52A0E786 | mt7925-macos |
| MtkBtFw | ESP | 0.3.1 | D173A506 | mt7925-macos `fix/bt-waitquiet` 668f400 |
| BtLeDlFix | ESP | 1.4.0 | C6274348 | mt7925-macos |
| StrixS0ix | AuxKC | 0.1.17 | 1700FABF | this repo, `kexts/StrixS0ix` |
| StrixSbxMap | ESP | 0.1.0 | F66BFC76 | this repo, `kexts/StrixSbxMap` |
| ItlXhciKick | ESP | 0.1.0 | 5D179C74 | this repo, `kexts/ItlXhciKick` |
| StrixAmp | ESP | 0.2.0 | 6E9C3F38 | this repo, branch `research/audio-rog-dolby` |
| RogAudio HAL driver, rogaudiod | `/Library/Audio`, `/Library/Application Support/RogAudio` | - | - | this repo, branch `research/audio-rog-dolby` (installed 2026-11-23) |

Loaded but switched off by boot-arg on this machine: StrixGOP 0.1.11 (E0F294C0, `-strixgopoff`), StrixAccel 0.1.21
(AF1F2E29, `-strixaccoff`), StrixMetalGate 0.1.1 (A1DAB568, `-strixmetalgateoff`). Also loaded from the earlier
research: StrixProbe 0.1.2 (DA6A1F25), StrixHeadroom 0.1.0 (13E8A6D4); their role on the current stack was not
re-checked.

### Third-party (not ours, not redistributed)

| Component | Version | UUID |
|---|---|---|
| OpenCore | 1.0.9 debug build of 2026-10-09 + Zen 5 FSB patch | - |
| NullMoth NVIDIA stack (NVRM, NVAccel, NVRMFB, NVRMAGDC) | 2.7.1 in the AuxKC. In this Eco boot only NVRMAGDC is loaded (4DBD6B43) | |
| Lilu | 1.7.3 | 38ACFA46 |
| VirtualSMC, SMCBatteryManager | 1.3.9 | FF5A572E, CAF7573C |
| AppleALC (local layout build) | 1.9.9 | 58752E4F |
| SimpleHDA | 1.0.1 | F1EA3386 |
| VoodooI2C, VoodooI2CHID, VoodooGPIO, VoodooInput | 2.9.1, 1, 1.1, 1.1.7 | 0BD5308D, 92D5DDB4, 5D44616D, 15EDDA4B |
| BrightnessKeys | 1.0.4 | AE157CF3 |
| ForgedInvariant | 1.5.0 | F0302C2D |
| NVMeFix | 1.1.4 | BDF0CF20 |
| RestrictEvents | 1.1.7 | A708639D |
| AMFIPass | 1.4.1 | 7DF1CDFC |
| BlueToolFixup | 2.7.2 | 037F9890 |
| USBToolBox | 1.2.0 | DF8F0CD3 |
| Sinetek-rtsx | 9.0.0 | 27134E65 |
| NullEthernet | 1.0.6 | A38D6C66 |

### Installed or built, but not running

| Component | State | Purpose |
|---|---|---|
| RyzenHV 0.7.24 (`fix/vmcb-cache-switch` 11ec930) | on the ESP, loads at the next reboot; **not verified on the machine as of 2026-11-25** | the fix for the Android emulator stall (no CPUID PKU/OSPKE for guests), on top of the cache switches and the exception trace. A first 0.7.24 without the fix (56D13B2B, commit 2e2c95c) was staged at 10:44 the same day; the UUID of the build with the fix is not recorded here |
| ItlXhciKick 0.2.0 (3A784B45, branch `thermal/xhcikick-pending` 60548a7) | built, not installed, never run on hardware | kick only when an event is queued; back off when idle |

### Version conflicts between sources

- `docs/HANDOFF-2026-11-16.md` lists itlmt7925 B9E6878A, RyzenHV 0.7.22, AsusWmi 0.3.0, gate 694511EA, NMXGPU out-29.
  All were replaced later; the table above follows the log and the loaded-kext list of 2026-11-25.
- The maintainer's notes say BtLeDlFix 1.3.0 was live on 2026-11-08 with 1.4.0 staged. 1.4.0 is what is loaded now.
- The mt7925-macos README (status dated 2026-11-02) says Bluetooth is "not checked" on Tahoe. The newer notes
  (2026-11-08, 2026-11-23) record it working on 25G332. The README is out of date.
- `docs/HANDOFF-2026-11-16.md` lists "NMXAccel from source" as deferred. `docs/FRAME-PATH.md` (2026-11-18) says NMXAccel
  is built from the fork (`kexts/NVRM/accel/nvrm-accel.cpp` with `NMX_ACCEL`). The later document is followed here.
- The 2026-11-18 15:54 boot: the install log says the gate held Eco; the boot table in `docs/BOOT-TIMELINE.md` labels
  the same boot "RTX on". Not resolved here; no claim in this document depends on it.
- `research/890m-cobalt64` still carries October copies (all 0.1.0) of `kexts/AsusWmi`, `kexts/AmdCppc`,
  `kexts/MtkBtFw`, `kexts/itlmt7925`, `macos/RogControl` and `macos/ItlWiFi`. They are removed on the release branch,
  as on `main`: the live builds come from mt7925-macos and rog-control-macos.

## 4. Known issues, with what is known about the cause

1. **Android emulator guest stalls (owner's blocker). Root cause found, fix not verified.** The guest kernel reaches
   "dlkm_loader: module load count is 47" at 13.9 s and then goes silent; qemu spins. The emulator uses a software GPU,
   so host graphics is ruled out. Cause (2026-11-25): RyzenHV exposed the CPUID bits PKU and OSPKE to guests, while
   macOS never enables PKRU state in XCR0. A Linux 6.12 guest that sees PKU then cannot build signal frames, so user
   space stops at the first signal delivery. Upstream fixed the same thing in its 0.7.9. The fork's fix is commit
   11ec930 on branch `fix/vmcb-cache-switch` of the ryzen-hypervisor.framework fork, staged on the ESP as RyzenHV
   0.7.24. **As of 2026-11-25 it has not been loaded or tested on the machine**, so the emulator still counts as broken.
   The earlier suspects (lazy guest RAM, the timer path, VMCB caching) are not shown to be involved; a review also found
   CLTS/LMSW decoded as MOV CR0 (older than this stall, not shown to be related).
2. **WindowServer CPU per frame.** 6.5-7.1 ms per present. Found and fixed so far: two shader translations of 3.6 s
   each, an empty Mesa disk cache in WindowServer, plane shadows recopied in every command buffer, address lowering run
   twice with no cache. Remaining: the per-frame work in QuartzCore plus plugin, and a "static" desktop that still
   presents about 30 frames/s; the client that keeps it redrawing is not named yet.
3. **Heat and fan noise under a Docker load (62 W, 95 C on 2026-11-16).** Ranked causes: the VM's exit path (most guest
   exits go to user-space HyperKit) and its wired memory, which pushed `kernel_task` to 108 % in compression; EPP 0 on
   AC at that time (now 191); the RTX powered on that boot. In Turbo, 95 C is also what the firmware's limits allow
   (80 W sustained), so part of it is the chosen profile. Not re-measured since the fixes.
4. **GPU and SoC power at light load.** 17 W package while the cores account for 4-6 W. The first rail read gives
   9.3 W to GFX. Every power feature is at the upstream default. Reads on 2026-11-25 show that GPU power follows the
   compositing rate: a static screen is 0.09 W on the GFX rail (6.2 W socket), 81-91 flips/s is 12-19 W on the GFX
   rail. So the rail does drop when nothing is presented, and the cost is the work per present, not a missing power
   feature: every present recomposites the full 2880x1800 screen plus a full-screen colour pass (about 1.1 ms of GPU,
   `docs/WS-CPU.md` 9.6), and the cursor is a software cursor, so each cursor move is a full present and a flip. Which
   client asks for each flip is not counted yet.
5. **`kernel_task` about 20 % of a core with no memory pressure.** Our polling threads: touchpad forced polling
   (est. 5-8 %), the Wi-Fi receive/transmit loop with no interrupt (est. 3-6 %), ItlXhciKick at 1 kHz (est. 1-2 %).
   Estimates; the root spindump that would confirm the split has not been run.
6. **Memory exhaustion hang (2026-11-18 17:46).** 25.2 of 32 GB wired. Cause found: WindowServer leaked about 330 MB of
   GPU memory per Aerial wallpaper clip (plugin keep cache). Fixed in the plugin on 2026-11-19 and verified flat over
   14 min. Parked-buffer and pinned-memory work under real memory pressure is still open.
7. **Graphics page fault from `mediaanalysisd` (2026-11-18 20:34).** It wrote a parked IOSurface import that its submit
   did not list. The code path is not found; three synthetic repros passed; not seen again. Newer kernels print the
   IOSurface on the fault line.
8. **Process-exit hang in `amdgpu_vm_fini` (2026-11-19, once, blocked a shutdown for 2 h 14 min).** Root cause: the
   compatibility layer freed the Linux task of a thread still inside the driver's close path (use after free, lost
   wake-up). Fixed in out-43; not seen since. Review follow-ups on the same teardown path went into out-45.
9. **Restart took 3 min 50 s once (2026-11-23).** No log between the kernel's restart message and the CPU reset.
   Cause unknown (driver shutdown, platform reset or firmware). The gate writes a shutdown trace to NVRAM since 0.2.9.
10. **Sleep.** S0i3 was never reached (DISPLAY and NBIO blocks stay busy), so sleep saves less than it should. No sleep
    test exists for the current kernel, with parked buffers, or with the RTX off the bus.
11. **Microphone gain found at minimum.** coreaudiod does persist the gain, so something sets it. Suspect: an app's
    automatic gain control (WebRTC). A trace in `rogaudiod` logs every change.
12. **Third microphone.** AppleHDA runs one analog input engine with exclusive sources, so no codec layout can capture
    both inputs. It needs a capture driver outside AppleHDA; not started.
13. **Safari WebGL depends on pinned code hashes.** After any plugin or RADV rebuild the pins must be refreshed, or the
    WebKit GPU process loses the 890M (it fails closed).
14. **WindowServer picks up a new plugin or RADV only at a reboot.** A logout does not restart it on this machine.
15. **HDMI.** Wired to the RTX: no output in Eco, and no way to bring it up without a reboot.
16. **Old panics, not ours as far as known.** HoRNDIS (USB tethering) `fq_codel` panics on 2026-11-08; a kernel use
    after free on 2026-11-09 during CloudflareWARP matching whose owning kext was not found.
17. **Docker Desktop quit leaves a spinning HyperKit.** A HyperKit read deadlock on SIGTERM; not RyzenHV.
18. **Reference EFI is stale.** See the Boot table. A reader cannot rebuild the live ESP from `efi/` today.
19. **Versions named here that are not on a default branch or in a release.** RogControl 0.6.0, AsusWmi 0.3.1 and
    StrixDgpuGate 0.2.12 (rog-control-macos: open PRs #16 and #17 and `fix/*` branches), MtkBtFw 0.3.1 and the
    itlmt7925 core (mt7925-macos `fix/bt-waitquiet`, `dev/awdl`), RyzenHV (fork branches, no release), NMXGPU and the
    plugin (fork branches, source only), StrixAmp and RogAudio (this repository, branch `research/audio-rog-dolby`).

## 5. Roadmap

Order follows the owner's priority, stated on 2026-11-16 and again on 2026-11-23: the machine is on only while the
owner works on it, for hours, under video + Claude + Docker. What counts is smoothness under that load, heat and fan
noise, and memory. Boot, login and shutdown seconds do not matter unless something hangs for minutes. Tests that need
the machine idle or asleep come last.

### Next (in flight)

1. **Android emulator under RyzenHV.** Reboot into the staged 0.7.24 (fork commit 11ec930: no CPUID PKU/OSPKE for
   guests) and boot a scratch AVD to adb online. Until that run passes, the fix is unverified. It blocks the owner's
   work today.
2. **RyzenHV cost with Docker.** Keep exits in the kernel where HyperKit allows it; make guest-memory reclaim safe to
   leave on. This is the only lever sized like the 62 W state (estimated 8-15 W).
3. **GPU power per present.** The readout answered the first question: the GFX rail idles at 0.09 W on a static
   screen and costs 12-19 W at 81-91 flips/s. The next steps, in order:
   - **per-client flip census**: count which client causes each present, so the 30 frames/s of a "static" desktop and
     the flips under video get a name;
   - **damage-sized composition**: composite only the changed rectangle instead of the full 2880x1800 screen and the
     full-screen colour pass on every present (about 1.1 ms of GPU each today);
   - **hardware cursor plane**: expose the amdgpu cursor plane so a cursor move is a plane update, not a full present
     plus a flip.
   Also still open from the readout: fix the derived "rest of SoC" field and commit the static and 81-91 flips/s reads
   to `docs/POWER-FEATURES.md`.
4. **WindowServer CPU per present, and who redraws a static desktop.** Same root as item 3; the flip census serves both.
5. **Polling threads in `kernel_task`.** One test boot without touchpad forced polling; a sleep instead of a busy
   window in the Wi-Fi loop; install ItlXhciKick 0.2.0. They also keep idle cores from sleeping deeply.
6. **Memory under pressure.** Pinned and parked GPU memory when RAM is short; the `mediaanalysisd` fault if it returns.
7. **Housekeeping for the release.** Done on branch `release/tahoe-v2`: the side branches with the cited documents and
   the live VCNDec source are merged, and the branch is reconciled with `main` (moved-out sources removed, build and CI
   no longer package them). Still to do: export the live EFI through `scripts/export-efi.py` and check it with
   `scripts/check-efi-privacy.py`; merge rog-control-macos PRs #16 and #17 and the `fix/*` branches the live kexts
   were built from; decide on `research/audio-rog-dolby` and `thermal/xhcikick-pending`.

### Later

- Re-measure the Docker load with the current settings (EPP 191, Eco, 8 vCPUs, lazy wiring).
- Sleep/wake on the current stack, then S0i3; Eco with sleep and charger events (the owner starts these).
- Idle floor, static-screen PSR/IPS read, per-profile bench and fan-curve read (need a quiet machine).
- Rerun the codec matrix on VCNDec 0.2.1; decode straight into the IOSurface (no per-frame copy).
- Wi-Fi: interrupts instead of polling, WPA3, AWDL/AirDrop.
- Audio: microphone gain cause, headphone jack, audio after sleep; merge `research/audio-rog-dolby`.
- HDMI in Standard mode with the OLED on the 890M.
- Hide the OpenCore picker after the Esc test; USB map and a clean reference EFI; the one-click installer.
- The unexplained 3 min 50 s restart, if it happens again.

### Not planned (or deferred by the owner)

| Item | Reason |
|---|---|
| Metal device for the RTX with automatic GPU choice per app | large; deferred by the owner (2026-11-10, 2026-11-16) |
| Extra HiDPI scaled modes | deferred by the owner; the two existing sizes are enough for daily use |
| RADV / libdrm replacement, dropping the NullMoth NVIDIA kexts | deferred; the NVIDIA kexts are the only RTX 5060 driver on macOS |
| HDMI without a reboot | the port belongs to the RTX and the mode is decided at boot; a study was offered, not started |
| Third microphone | needs a new capture driver outside AppleHDA |
| DMUB IPS2 in active idle, Panel Replay | upstream amdgpu forbids IPS2 on this PMFW (93.11 < 93.99, hard-hang workaround); the panel reports PSR1 only |
| Boot, login and shutdown time | owner: not a priority unless it is a hang |
| macOS 15 for the 890M stack | the work targets Darwin 25.x; macOS 15 stays on the v1 / kext-v1.1 setup |
| Other laptops | one machine, one BIOS; no second tester |

## 6. How the pieces map to the repositories

| Repository | Holds | Live pieces built from it |
|---|---|---|
| **thanhnndev/ga403wm-hackintosh** (this one) | OpenCore reference EFI and SSDTs, OpenCore Zen 5 patch, install and recovery scripts, all documents and traces, 890M tools (`tools/890m`: VCNDec, video suite, verify and probe scripts), small kexts | ItlXhciKick, StrixS0ix, StrixSbxMap, VCNDec; StrixAmp and RogAudio from branch `research/audio-rog-dolby`; the retired boot-display kexts StrixGOP / StrixAccel / StrixMetalGate / StrixHeadroom / StrixProbe |
| **thanhnndev/mt7925-macos** | MT7925 Wi-Fi (core + native front end, AWDL work) and Bluetooth | itlmt7925, itlmt7925Native, MtkBtFw, BtLeDlFix |
| **thanhnndev/rog-control-macos** | ASUS platform kexts, the RogControl app, the CPU policy daemon, the Fn-key helper, the dGPU gate | AsusWmi, AmdCppc, AmdCppcPolicy, RogControl.app, rogkeyd, StrixDgpuGate |
| **thanhnndev/ryzen-hypervisor.framework** (fork of OverlordDev/ryzen-hypervisor.framework) | SVM hypervisor kext and its Hypervisor.framework front end | RyzenHV (Docker Desktop runs on it) |
| **thanhnndev/nvidia-macos-driver** (fork of nullmoth/nvidia-macos-driver, PolyForm Noncommercial) | NMXGPU (amdgpu on the xkpi layer), NMXAccel, NMXAGDC, the Metal plugin and translator; the upstream NVIDIA stack | NMXGPU, NMXAccel, NMXAGDC, NVMTLDriver plugin, translator. RADV is Mesa plus two patches kept in this repo under `scripts/radv` |

Notes:

- The licence split matters for a release: everything from the nvidia-macos-driver fork is PolyForm Noncommercial and
  is kept out of this BSD repository. The reference EFI derives from nullmoth/1401 and is PolyForm Noncommercial too.
- A sixth repository, **thanhnndev/strix-890m-macos**, holds a copy of the boot-display kexts and traces (last push
  2026-11-02). The same kexts and traces are still in this repository and are newer here. Which one is the home for
  them is an open question for the maintainer.
- The NVIDIA kexts (NVRM 2.7.1 and friends) are NullMoth's binaries, installed by
  `scripts/macos-install-nvidia-2.7.1.sh`; they are needed only for Standard mode.
